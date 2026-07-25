with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Web.Binding.Decoders;

package body Web.Binding.Codecs.JSON is

   use Web.Binding.Errors;
   use Web.Binding.Streams;

   LF : constant Character := Character'Val (10);

   --  Pull one raw byte, refilling from the stream. Eof also covers a stream
   --  fault (Stream_End set with an error left in Cur_Err by the caller path).
   procedure Load_Raw (R : in out Reader; C : out Character; Eof : out Boolean) is
      Last    : Natural;
      Outcome : Read_Outcome;
   begin
      C := ' ';
      loop
         if R.Buf_Pos <= R.Buf_Len then
            C := R.Buffer (R.Buf_Pos);
            R.Buf_Pos := R.Buf_Pos + 1;
            Eof := False;
            return;
         end if;
         if R.Stream_End then
            Eof := True;
            return;
         end if;
         Read (R.Stream.all, R.Buffer, Last, Outcome);
         case Outcome is
            when Chunk =>
               R.Buf_Len := Last;
               R.Buf_Pos := R.Buffer'First;
            when End_Of_Input =>
               R.Stream_End := True;
            when Over_Limit =>
               R.Stream_End := True;
               R.Cur_Err := Json_Token_Limit_Exceeded;
            when Cancelled | Failed =>
               R.Stream_End := True;
               R.Cur_Err := Json_Malformed;
         end case;
      end loop;
   end Load_Raw;

   --  Discard Cur and load the next character, tracking the position of Cur.
   procedure Consume (R : in out Reader) is
      C : Character;
      E : Boolean;
   begin
      if not R.Cur_Eof then
         R.At_Offset := R.At_Offset + 1;
         if R.Cur = LF then
            R.At_Line := R.At_Line + 1;
            R.At_Col := 1;
         else
            R.At_Col := R.At_Col + 1;
         end if;
      end if;
      Load_Raw (R, C, E);
      R.Cur := C;
      R.Cur_Eof := E;
   end Consume;

   procedure Skip_WS (R : in out Reader) is
   begin
      while not R.Cur_Eof
        and then (R.Cur = ' ' or else R.Cur = Character'Val (9)
                  or else R.Cur = Character'Val (10)
                  or else R.Cur = Character'Val (13))
      loop
         Consume (R);
      end loop;
   end Skip_WS;

   procedure Fail (R : in out Reader; Id : Web.Binding.Errors.Error_Id) is
   begin
      R.Cur_Kind := Error_Token;
      R.Cur_Err := Id;
      R.State := S_Error;
   end Fail;

   --  Capture the current position as the token start.
   procedure Mark (R : in out Reader) is
   begin
      R.Tok_Offset := R.At_Offset;
      R.Tok_Line := R.At_Line;
      R.Tok_Col := R.At_Col;
   end Mark;

   function Hex (C : Character) return Integer is
   begin
      case C is
         when '0' .. '9' => return Character'Pos (C) - Character'Pos ('0');
         when 'a' .. 'f' => return 10 + Character'Pos (C) - Character'Pos ('a');
         when 'A' .. 'F' => return 10 + Character'Pos (C) - Character'Pos ('A');
         when others     => return -1;
      end case;
   end Hex;

   --  Read exactly four hex digits (Cur positioned at the first). Returns the
   --  value, or -1 on any non-hex / short input.
   function Read_Hex4 (R : in out Reader) return Integer is
      Value : Integer := 0;
      D     : Integer;
   begin
      for I in 1 .. 4 loop
         if R.Cur_Eof then
            return -1;
         end if;
         D := Hex (R.Cur);
         if D < 0 then
            return -1;
         end if;
         Value := Value * 16 + D;
         Consume (R);
      end loop;
      return Value;
   end Read_Hex4;

   --  Append a Unicode code point as UTF-8.
   procedure Append_Cp (Buf : in out Unbounded_String; Cp : Natural) is
   begin
      if Cp <= 16#7F# then
         Append (Buf, Character'Val (Cp));
      elsif Cp <= 16#7FF# then
         Append (Buf, Character'Val (16#C0# + Cp / 64));
         Append (Buf, Character'Val (16#80# + Cp mod 64));
      elsif Cp <= 16#FFFF# then
         Append (Buf, Character'Val (16#E0# + Cp / 4096));
         Append (Buf, Character'Val (16#80# + (Cp / 64) mod 64));
         Append (Buf, Character'Val (16#80# + Cp mod 64));
      else
         Append (Buf, Character'Val (16#F0# + Cp / 262_144));
         Append (Buf, Character'Val (16#80# + (Cp / 4096) mod 64));
         Append (Buf, Character'Val (16#80# + (Cp / 64) mod 64));
         Append (Buf, Character'Val (16#80# + Cp mod 64));
      end if;
   end Append_Cp;

   --  Scan a string starting at the opening quote into R.Cur_Text. Sets an
   --  error and returns False on any violation.
   function Scan_String (R : in out Reader) return Boolean is
   begin
      R.Cur_Text := Null_Unbounded_String;
      Consume (R);  --  opening quote
      loop
         if R.Cur_Eof then
            Fail (R, Json_Malformed);
            return False;
         end if;
         if Byte_Count (Length (R.Cur_Text)) > R.Settings.Max_String then
            Fail (R, Decode_Value_Too_Long);
            return False;
         end if;

         declare
            C : constant Character := R.Cur;
         begin
            if C = '"' then
               Consume (R);
               exit;
            elsif C = '\' then
               Consume (R);
               if R.Cur_Eof then
                  Fail (R, Json_Malformed);
                  return False;
               end if;
               case R.Cur is
                  when '"'  => Append (R.Cur_Text, '"'); Consume (R);
                  when '\'  => Append (R.Cur_Text, '\'); Consume (R);
                  when '/'  => Append (R.Cur_Text, '/'); Consume (R);
                  when 'b'  => Append (R.Cur_Text, Character'Val (8)); Consume (R);
                  when 'f'  => Append (R.Cur_Text, Character'Val (12)); Consume (R);
                  when 'n'  => Append (R.Cur_Text, LF); Consume (R);
                  when 'r'  => Append (R.Cur_Text, Character'Val (13)); Consume (R);
                  when 't'  => Append (R.Cur_Text, Character'Val (9)); Consume (R);
                  when 'u'  =>
                     Consume (R);
                     declare
                        Cp : Integer := Read_Hex4 (R);
                     begin
                        if Cp < 0 then
                           Fail (R, Json_Malformed);
                           return False;
                        end if;
                        if Cp in 16#D800# .. 16#DBFF# then
                           --  High surrogate: require a low-surrogate escape.
                           if R.Cur /= '\' then
                              Fail (R, Json_Malformed);
                              return False;
                           end if;
                           Consume (R);
                           if R.Cur /= 'u' then
                              Fail (R, Json_Malformed);
                              return False;
                           end if;
                           Consume (R);
                           declare
                              Lo : constant Integer := Read_Hex4 (R);
                           begin
                              if Lo not in 16#DC00# .. 16#DFFF# then
                                 Fail (R, Json_Malformed);
                                 return False;
                              end if;
                              Cp := 16#10000# + (Cp - 16#D800#) * 16#400#
                                + (Lo - 16#DC00#);
                           end;
                        elsif Cp in 16#DC00# .. 16#DFFF# then
                           Fail (R, Json_Malformed);  --  lone low surrogate
                           return False;
                        end if;
                        Append_Cp (R.Cur_Text, Cp);
                     end;
                  when others =>
                     Fail (R, Json_Malformed);  --  invalid escape
                     return False;
               end case;
            elsif Character'Pos (C) < 32 then
               Fail (R, Json_Malformed);  --  raw control character
               return False;
            else
               Append (R.Cur_Text, C);
               Consume (R);
            end if;
         end;
      end loop;

      if not Web.Binding.Decoders.Valid_UTF8 (To_String (R.Cur_Text)) then
         Fail (R, Decode_Invalid_UTF8);
         return False;
      end if;
      return True;
   end Scan_String;

   --  Scan a JSON number into R.Cur_Text (raw literal). Cur is at '-' or a digit.
   function Scan_Number (R : in out Reader) return Boolean is

      procedure Take is
      begin
         Append (R.Cur_Text, R.Cur);
         Consume (R);
      end Take;

      function Is_Digit return Boolean is
        (not R.Cur_Eof and then R.Cur in '0' .. '9');

   begin
      R.Cur_Text := Null_Unbounded_String;
      if R.Cur = '-' then
         Take;
      end if;

      if R.Cur_Eof then
         Fail (R, Json_Malformed);
         return False;
      end if;
      if R.Cur = '0' then
         Take;  --  a leading zero admits no further integer digits
      elsif R.Cur in '1' .. '9' then
         Take;
         while Is_Digit loop
            Take;
         end loop;
      else
         Fail (R, Json_Malformed);
         return False;
      end if;

      if not R.Cur_Eof and then R.Cur = '.' then
         Take;
         if not Is_Digit then
            Fail (R, Json_Malformed);
            return False;
         end if;
         while Is_Digit loop
            Take;
         end loop;
      end if;

      if not R.Cur_Eof and then (R.Cur = 'e' or else R.Cur = 'E') then
         Take;
         if not R.Cur_Eof and then (R.Cur = '+' or else R.Cur = '-') then
            Take;
         end if;
         if not Is_Digit then
            Fail (R, Json_Malformed);
            return False;
         end if;
         while Is_Digit loop
            Take;
         end loop;
      end if;

      if Byte_Count (Length (R.Cur_Text)) > R.Settings.Max_Number then
         Fail (R, Json_Number_Out_Of_Range);
         return False;
      end if;
      return True;
   end Scan_Number;

   --  Match an exact keyword (true/false/null) starting at Cur.
   function Scan_Word (R : in out Reader; Word : String) return Boolean is
   begin
      for C of Word loop
         if R.Cur_Eof or else R.Cur /= C then
            Fail (R, Json_Malformed);
            return False;
         end if;
         Consume (R);
      end loop;
      return True;
   end Scan_Word;

   procedure Push (R : in out Reader; F : Frame; Ok : out Boolean) is
   begin
      if Depth_Count (R.Depth) >= R.Settings.Max_Depth then
         Fail (R, Json_Depth_Exceeded);
         Ok := False;
         return;
      end if;
      R.Depth := R.Depth + 1;
      R.Stack (R.Depth) := F;
      Ok := True;
   end Push;

   --  The state after a completed value at the current depth.
   procedure After_Value (R : in out Reader) is
   begin
      R.State := (if R.Depth = 0 then S_Doc_Done else S_Comma_Or_End);
   end After_Value;

   procedure Emitted (R : in out Reader; K : Token_Kind; Ok : out Boolean) is
   begin
      R.Tokens := R.Tokens + 1;
      if R.Tokens > R.Settings.Max_Tokens then
         Fail (R, Json_Token_Limit_Exceeded);
         Ok := False;
         return;
      end if;
      R.Cur_Kind := K;
      Ok := True;
   end Emitted;

   procedure Start (R : in out Reader; Settings : Config := Default_Config) is
   begin
      R.Settings := Settings;
      R.State := S_Doc_Value;
      R.Depth := 0;
      R.Tokens := 0;
      R.At_Offset := 0;
      R.At_Line := 1;
      R.At_Col := 1;
      Consume (R);  --  prime Cur (position stays at 0 for the first char)
      R.At_Offset := 0;
      R.At_Line := 1;
      R.At_Col := 1;
      R.Started := True;
   end Start;

   --  Parse and emit one value token (object/array/string/number/bool/null),
   --  updating the state for what follows. Cur is at the first char.
   procedure Read_Value (R : in out Reader; Ok : out Boolean) is
      Pushed : Boolean;
   begin
      Ok := False;
      Mark (R);
      case R.Cur is
         when '{' =>
            Consume (R);
            Push (R, In_Object, Pushed);
            if not Pushed then
               return;
            end if;
            Emitted (R, Start_Object, Ok);
            if Ok then
               R.State := S_Key_Or_End;
            end if;
         when '[' =>
            Consume (R);
            Push (R, In_Array, Pushed);
            if not Pushed then
               return;
            end if;
            Emitted (R, Start_Array, Ok);
            if Ok then
               R.State := S_Value_Or_End;
            end if;
         when '"' =>
            if not Scan_String (R) then
               return;
            end if;
            Emitted (R, String_Value, Ok);
            if Ok then
               After_Value (R);
            end if;
         when '-' | '0' .. '9' =>
            if not Scan_Number (R) then
               return;
            end if;
            Emitted (R, Number_Value, Ok);
            if Ok then
               After_Value (R);
            end if;
         when 't' =>
            if not Scan_Word (R, "true") then
               return;
            end if;
            R.Cur_Bool := True;
            Emitted (R, Boolean_Value, Ok);
            if Ok then
               After_Value (R);
            end if;
         when 'f' =>
            if not Scan_Word (R, "false") then
               return;
            end if;
            R.Cur_Bool := False;
            Emitted (R, Boolean_Value, Ok);
            if Ok then
               After_Value (R);
            end if;
         when 'n' =>
            if not Scan_Word (R, "null") then
               return;
            end if;
            Emitted (R, Null_Value, Ok);
            if Ok then
               After_Value (R);
            end if;
         when others =>
            Fail (R, Json_Malformed);
      end case;
   end Read_Value;

   procedure Close_Container (R : in out Reader; K : Token_Kind; Ok : out Boolean)
   is
   begin
      Consume (R);
      R.Depth := R.Depth - 1;
      Emitted (R, K, Ok);
      if Ok then
         After_Value (R);
      end if;
   end Close_Container;

   procedure Advance (R : in out Reader) is
      Ok : Boolean;
   begin
      if R.State in S_Error | S_Done then
         return;
      end if;

      loop
         Skip_WS (R);
         case R.State is
            when S_Doc_Done =>
               if R.Cur_Eof then
                  Mark (R);
                  R.Cur_Kind := End_Document;
                  R.State := S_Done;
               else
                  Fail (R, Json_Trailing_Content);
               end if;
               return;

            when S_Doc_Value | S_Value =>
               if R.Cur_Eof then
                  Fail (R, Json_Malformed);
                  return;
               end if;
               Read_Value (R, Ok);
               return;

            when S_Value_Or_End =>
               if R.Cur_Eof then
                  Fail (R, Json_Malformed);
                  return;
               elsif R.Cur = ']' then
                  Mark (R);
                  Close_Container (R, End_Array, Ok);
                  return;
               else
                  Read_Value (R, Ok);
                  return;
               end if;

            when S_Key_Or_End =>
               if R.Cur_Eof then
                  Fail (R, Json_Malformed);
                  return;
               elsif R.Cur = '}' then
                  Mark (R);
                  Close_Container (R, End_Object, Ok);
                  return;
               elsif R.Cur = '"' then
                  Mark (R);
                  if not Scan_String (R) then
                     return;
                  end if;
                  Emitted (R, Key, Ok);
                  if Ok then
                     R.State := S_Colon;
                  end if;
                  return;
               else
                  Fail (R, Json_Malformed);
                  return;
               end if;

            when S_Key =>
               if not R.Cur_Eof and then R.Cur = '"' then
                  Mark (R);
                  if not Scan_String (R) then
                     return;
                  end if;
                  Emitted (R, Key, Ok);
                  if Ok then
                     R.State := S_Colon;
                  end if;
               else
                  Fail (R, Json_Malformed);
               end if;
               return;

            when S_Colon =>
               if not R.Cur_Eof and then R.Cur = ':' then
                  Consume (R);
                  R.State := S_Value;
                  --  continue: read the member value on the next iteration
               else
                  Fail (R, Json_Malformed);
                  return;
               end if;

            when S_Comma_Or_End =>
               if R.Cur_Eof then
                  Fail (R, Json_Malformed);
                  return;
               elsif R.Cur = ',' then
                  Consume (R);
                  R.State :=
                    (if R.Stack (R.Depth) = In_Object then S_Key else S_Value);
                  --  continue
               elsif R.Cur = '}' and then R.Stack (R.Depth) = In_Object then
                  Mark (R);
                  Close_Container (R, End_Object, Ok);
                  return;
               elsif R.Cur = ']' and then R.Stack (R.Depth) = In_Array then
                  Mark (R);
                  Close_Container (R, End_Array, Ok);
                  return;
               else
                  Fail (R, Json_Malformed);
                  return;
               end if;

            when S_Error | S_Done =>
               return;
         end case;
      end loop;
   end Advance;

   function Kind (R : Reader) return Token_Kind is (R.Cur_Kind);
   function Text (R : Reader) return String is (To_String (R.Cur_Text));
   function Bool_Value (R : Reader) return Boolean is (R.Cur_Bool);
   function Error_Id (R : Reader) return Web.Binding.Errors.Error_Id is
     (R.Cur_Err);
   function Line (R : Reader) return Line_Number is (R.Tok_Line);
   function Column (R : Reader) return Column_Number is (R.Tok_Col);
   function Offset (R : Reader) return Offset_Count is (R.Tok_Offset);

end Web.Binding.Codecs.JSON;
