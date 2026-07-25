with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Web.Binding.Multipart is

   use Web.Binding.Streams;
   use Meta_Strings;

   CR   : constant Character := Character'Val (13);
   LF   : constant Character := Character'Val (10);
   CRLF : constant String := [1 => CR, 2 => LF];

   function Lower (S : String) return String is
      R : String (S'Range);
   begin
      for I in S'Range loop
         R (I) := Ada.Characters.Handling.To_Lower (S (I));
      end loop;
      return R;
   end Lower;

   --  Compact unconsumed bytes to the front and pull more from the stream.
   --  Returns whether new bytes arrived.
   function Refill (R : in out Multipart_Reader) return Boolean is
      SL : Natural;
      Oc : Read_Outcome;
   begin
      if R.Pos > 1 then
         R.Buf (1 .. R.Last - R.Pos + 1) := R.Buf (R.Pos .. R.Last);
         R.Last := R.Last - R.Pos + 1;
         R.Pos := 1;
      end if;
      if R.Stream_End or else R.Last >= R.Buf'Last then
         return False;
      end if;
      Read (R.Stream.all, R.Buf (R.Last + 1 .. R.Buf'Last), SL, Oc);
      case Oc is
         when Chunk =>
            R.Last := SL;
            return True;
         when End_Of_Input =>
            R.Stream_End := True;
            return False;
         when Over_Limit =>
            R.Stream_End := True;
            R.Result := Malformed;
            return False;
         when Cancelled | Failed =>
            R.Stream_End := True;
            R.Result := Stream_Failed;
            return False;
      end case;
   end Refill;

   function Available (R : Multipart_Reader) return Natural is
     (R.Last - R.Pos + 1);

   --  Consume the boundary trailer: "--" ends the document, CRLF starts a part.
   procedure Read_Trailer (R : in out Multipart_Reader) is
   begin
      while Available (R) < 2 and then Refill (R) loop
         null;
      end loop;
      if Available (R) < 2 then
         R.State := S_Done;  --  lenient: EOF right after the boundary
         return;
      end if;
      if R.Buf (R.Pos) = '-' and then R.Buf (R.Pos + 1) = '-' then
         R.Pos := R.Pos + 2;
         R.State := S_Done;
      elsif R.Buf (R.Pos) = CR and then R.Buf (R.Pos + 1) = LF then
         R.Pos := R.Pos + 2;
         R.State := S_Before_Headers;
      else
         R.State := S_Error;
         R.Result := Malformed;
      end if;
   end Read_Trailer;

   --  Skip the preamble and consume the first dash-boundary.
   procedure Find_First_Boundary (R : in out Multipart_Reader) is
      Dash     : constant String := R.Delimiter (3 .. R.Delim_Len);
      Dash_Len : constant Natural := Dash'Length;
   begin
      loop
         declare
            Idx : constant Natural :=
              Ada.Strings.Fixed.Index (R.Buf (R.Pos .. R.Last), Dash);
         begin
            if Idx > 0 then
               R.Pos := Idx + Dash_Len;
               Read_Trailer (R);
               return;
            end if;
            --  Discard preamble but keep a possible partial match.
            if R.Last - R.Pos + 1 > Dash_Len - 1 then
               R.Pos := R.Last - (Dash_Len - 1) + 1;
            end if;
            if not Refill (R) then
               R.State := S_Error;
               if R.Result = Ok then
                  R.Result := Malformed;
               end if;
               return;
            end if;
         end;
      end loop;
   end Find_First_Boundary;

   procedure Start
     (R        : in out Multipart_Reader;
      Boundary : String;
      Settings : Config := Default_Config)
   is
      Delim : constant String := CRLF & "--" & Boundary;
   begin
      R.Settings := Settings;
      R.Pos := 1;
      R.Last := 0;
      R.Stream_End := False;
      R.Parts := 0;
      R.Result := Ok;
      if Boundary'Length = 0 or else Delim'Length > Max_Delimiter then
         R.State := S_Error;
         R.Result := Invalid_Boundary;
         return;
      end if;
      R.Delimiter (1 .. Delim'Length) := Delim;
      R.Delim_Len := Delim'Length;
      Find_First_Boundary (R);
   end Start;

   --  Read one header line into Line. Ok is False if it exceeds capacity or the
   --  stream ends without a terminator.
   procedure Read_Line
     (R    : in out Multipart_Reader;
      Line : out String;
      Len  : out Natural;
      Ok   : out Boolean) is
   begin
      Len := 0;
      Ok := True;
      loop
         declare
            Nl : constant Natural :=
              Ada.Strings.Fixed.Index (R.Buf (R.Pos .. R.Last), CRLF);
         begin
            if Nl > 0 then
               Len := Nl - R.Pos;
               if Len > Line'Length then
                  Ok := False;
                  Len := 0;
                  R.Pos := Nl + 2;
                  return;
               end if;
               Line (Line'First .. Line'First + Len - 1) := R.Buf (R.Pos .. Nl - 1);
               R.Pos := Nl + 2;
               return;
            end if;
            if Available (R) > Line'Length then
               Ok := False;
               return;
            end if;
            if not Refill (R) then
               Ok := False;
               return;
            end if;
         end;
      end loop;
   end Read_Line;

   --  Extract a parameter value ("name", "filename") from a header line.
   function Param_Value
     (Line : String; Name : String; Present : out Boolean) return String
   is
      Pat : constant String := Lower (Name) & "=";
      Idx : constant Natural := Ada.Strings.Fixed.Index (Lower (Line), Pat);
   begin
      Present := Idx > 0;
      if Idx = 0 then
         return "";
      end if;
      declare
         V : constant Natural := Idx + Pat'Length;
      begin
         if V <= Line'Last and then Line (V) = '"' then
            declare
               E : Natural := V + 1;
            begin
               while E <= Line'Last and then Line (E) /= '"' loop
                  E := E + 1;
               end loop;
               return Line (V + 1 .. E - 1);
            end;
         else
            declare
               E : Natural := V;
            begin
               while E <= Line'Last and then Line (E) /= ';'
                 and then Line (E) /= ' '
               loop
                  E := E + 1;
               end loop;
               return Line (V .. E - 1);
            end;
         end if;
      end;
   end Param_Value;

   function Header_Is (Line : String; Name : String) return Boolean is
      Low : constant String := Lower (Line);
      Pat : constant String := Lower (Name) & ":";
   begin
      return Low'Length >= Pat'Length
        and then Low (Low'First .. Low'First + Pat'Length - 1) = Pat;
   end Header_Is;

   function Header_Value (Line : String; Name : String) return String is
      Colon : constant Natural :=
        Ada.Strings.Fixed.Index (Line, ":");
      F     : Natural;
   begin
      pragma Unreferenced (Name);
      if Colon = 0 then
         return "";
      end if;
      F := Colon + 1;
      while F <= Line'Last and then Line (F) = ' ' loop
         F := F + 1;
      end loop;
      return Line (F .. Line'Last);
   end Header_Value;

   procedure Next_Part
     (R         : in out Multipart_Reader;
      Info      : out Part_Info;
      Available : out Boolean)
   is
      Line        : String (1 .. 4_096);
      Len         : Natural;
      Ok          : Boolean;
      Header_Total : Natural := 0;
      Name_Seen   : Boolean := False;
      File_Seen   : Boolean;
   begin
      Info := (Name => Null_Bounded_String, Filename => Null_Bounded_String,
               Content_Type => Null_Bounded_String, Is_File => False);
      Available := False;

      if R.State /= S_Before_Headers then
         return;
      end if;

      R.Parts := R.Parts + 1;
      if R.Parts > R.Settings.Max_Parts then
         R.State := S_Error;
         R.Result := Too_Many_Parts;
         return;
      end if;

      loop
         Read_Line (R, Line, Len, Ok);
         if not Ok then
            R.State := S_Error;
            R.Result := Header_Too_Large;
            return;
         end if;
         exit when Len = 0;  --  blank line ends the headers

         Header_Total := Header_Total + Len + 2;
         if Header_Total > R.Settings.Max_Header_Bytes then
            R.State := S_Error;
            R.Result := Header_Too_Large;
            return;
         end if;

         declare
            L : constant String := Line (1 .. Len);
         begin
            if Header_Is (L, "content-disposition") then
               declare
                  Nm : constant String :=
                    Param_Value (L, "name", Name_Seen);
                  Fn : constant String := Param_Value (L, "filename", File_Seen);
               begin
                  if Name_Seen then
                     Info.Name := To_Bounded_String (Nm, Drop => Ada.Strings.Right);
                  end if;
                  if File_Seen then
                     Info.Is_File := True;
                     Info.Filename :=
                       To_Bounded_String (Fn, Drop => Ada.Strings.Right);
                  end if;
               end;
            elsif Header_Is (L, "content-type") then
               Info.Content_Type := To_Bounded_String
                 (Header_Value (L, "content-type"), Drop => Ada.Strings.Right);
            end if;
         end;
      end loop;

      if not Name_Seen then
         R.State := S_Error;
         R.Result := Missing_Name;
         return;
      end if;

      R.State := S_In_Body;
      Available := True;
   end Next_Part;

   procedure Read_Body
     (R       : in out Multipart_Reader;
      Out_Buf : out String;
      Last    : out Natural;
      Done    : out Boolean)
   is
      procedure Emit (From, To : Natural) is
         N : constant Natural :=
           Natural'Min (To - From + 1, Out_Buf'Length - (Last - Out_Buf'First + 1));
      begin
         if N > 0 then
            Out_Buf (Last + 1 .. Last + N) := R.Buf (From .. From + N - 1);
            Last := Last + N;
            R.Pos := From + N;
         end if;
      end Emit;

   begin
      Last := Out_Buf'First - 1;
      Done := False;
      if R.State /= S_In_Body then
         Done := True;
         return;
      end if;

      loop
         declare
            Idx : constant Natural :=
              Ada.Strings.Fixed.Index
                (R.Buf (R.Pos .. R.Last), R.Delimiter (1 .. R.Delim_Len));
         begin
            if Idx > 0 then
               Emit (R.Pos, Idx - 1);
               if R.Pos >= Idx then
                  R.Pos := Idx + R.Delim_Len;
                  Read_Trailer (R);
                  Done := True;
               end if;
               return;
            end if;

            declare
               Safe_Last : constant Integer := R.Last - (R.Delim_Len - 1);
            begin
               if Safe_Last >= R.Pos then
                  Emit (R.Pos, Safe_Last);
                  return;
               end if;
            end;

            if not Refill (R) then
               --  EOF with no closing boundary: the rest is body, then malformed.
               if R.Pos <= R.Last then
                  Emit (R.Pos, R.Last);
               end if;
               R.State := S_Error;
               if R.Result = Ok then
                  R.Result := Malformed;
               end if;
               Done := True;
               return;
            end if;
         end;
      end loop;
   end Read_Body;

   procedure Read_Text
     (R     : in out Multipart_Reader;
      Value : out Ada.Strings.Unbounded.Unbounded_String)
   is
      Chunk : String (1 .. 4_096);
      Len   : Natural;
      Done  : Boolean;
   begin
      Value := Null_Unbounded_String;
      loop
         Read_Body (R, Chunk, Len, Done);
         if Len >= Chunk'First then
            if Length (Value) + Len <= R.Settings.Max_Field_Bytes then
               Append (Value, Chunk (1 .. Len));
            else
               R.Result := Field_Too_Large;
            end if;
         end if;
         exit when Done;
      end loop;
   end Read_Text;

   procedure Skip_Body (R : in out Multipart_Reader) is
      Chunk : String (1 .. 4_096);
      Len   : Natural;
      Done  : Boolean;
   begin
      loop
         Read_Body (R, Chunk, Len, Done);
         exit when Done;
      end loop;
   end Skip_Body;

   function Status (R : Multipart_Reader) return Outcome is (R.Result);

end Web.Binding.Multipart;
