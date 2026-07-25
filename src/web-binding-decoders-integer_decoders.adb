package body Web.Binding.Decoders.Integer_Decoders is

   use Web.Binding.Errors;

   function Meta return Decoder_Meta is
   begin
      return
        (Id            => To_Identifier ("web.binding.integer"),
         Expected_Type => To_Identifier ("integer"),
         Accepts       => Text_Only,
         Consumes_Stream => False,
         Max_Lookahead => 0);
   end Meta;

   --  The numeric value of a base.
   function Base_Value (Base : Radix) return Long_Long_Integer is
   begin
      case Base is
         when Decimal     => return 10;
         when Hexadecimal => return 16;
         when Octal       => return 8;
         when Binary      => return 2;
      end case;
   end Base_Value;

   --  The value of a digit character in the given base, or -1 if not a digit.
   function Digit_Value (C : Character; Base : Radix) return Integer is
      Limit : constant Integer := Integer (Base_Value (Base));
      Value : Integer;
   begin
      case C is
         when '0' .. '9' =>
            Value := Character'Pos (C) - Character'Pos ('0');
         when 'a' .. 'f' =>
            Value := 10 + Character'Pos (C) - Character'Pos ('a');
         when 'A' .. 'F' =>
            Value := 10 + Character'Pos (C) - Character'Pos ('A');
         when others =>
            return -1;
      end case;
      return (if Value < Limit then Value else -1);
   end Digit_Value;

   --  Build a failure result carrying one error.
   function Fail
     (Id     : Error_Id;
      Path   : Web.Binding.Paths.Field_Path;
      Source : Source_Kind;
      Params : Error_Parameters := No_Parameters) return Result is
   begin
      return Results.Make_Failure
        (Single_Error
           (Make_Error
              (Id         => Id,
               Path       => Path,
               Source     => Source,
               Origin     => Decode_Origin,
               Parameters => Params)));
   end Fail;

   --  The range parameters for an out-of-range error.
   function Range_Params return Error_Parameters is
      Params : Error_Parameters;
   begin
      Params.Has_Minimum := True;
      Params.Minimum := Long_Long_Integer (Target'First);
      Params.Has_Maximum := True;
      Params.Maximum := Long_Long_Integer (Target'Last);
      Params.Expected_Type := Text_Param ("integer");
      return Params;
   end Range_Params;

   function Decode
     (Text     : String;
      Path     : Web.Binding.Paths.Field_Path;
      Source   : Source_Kind;
      Settings : Config := Default_Config) return Result
   is
      First : Integer := Text'First;
      Last  : Integer := Text'Last;

      function Invalid return Result is
      begin
         return Fail (Decode_Invalid_Integer, Path, Source);
      end Invalid;

   begin
      --  Surrounding whitespace: trimmed when allowed, otherwise left in place
      --  so it is rejected as a non-digit below.
      if Settings.Allow_Whitespace then
         while First <= Last and then Text (First) = ' ' loop
            First := First + 1;
         end loop;
         while Last >= First and then Text (Last) = ' ' loop
            Last := Last - 1;
         end loop;
      end if;

      if First > Last then
         return Invalid;  --  empty
      end if;

      declare
         Idx      : Integer := First;
         Negative : Boolean := False;
         Mag      : Long_Long_Integer := 0;
         Any      : Boolean := False;
         Prev_Sep : Boolean := False;
         B        : constant Long_Long_Integer := Base_Value (Settings.Base);
      begin
         --  Optional sign.
         if Text (Idx) = '-' then
            if not Settings.Allow_Negative then
               return Invalid;
            end if;
            Negative := True;
            Idx := Idx + 1;
         elsif Text (Idx) = '+' then
            if not Settings.Allow_Leading_Plus then
               return Invalid;
            end if;
            Idx := Idx + 1;
         end if;

         if Idx > Last then
            return Invalid;  --  sign with no digits
         end if;

         --  Leading-zero policy: a multi-character magnitude may not start '0'.
         if not Settings.Allow_Leading_Zero
           and then Text (Idx) = '0'
           and then Idx < Last
         then
            return Invalid;
         end if;

         while Idx <= Last loop
            declare
               C : constant Character := Text (Idx);
               D : Integer;
            begin
               if C = '_' and then Settings.Allow_Separators then
                  --  A separator must sit strictly between two digits.
                  if not Any or else Prev_Sep or else Idx = Last then
                     return Invalid;
                  end if;
                  Prev_Sep := True;
               else
                  D := Digit_Value (C, Settings.Base);
                  if D < 0 then
                     return Invalid;
                  end if;
                  --  Overflow guard: keep Mag within Long_Long_Integer before
                  --  the multiply-add, so oversized input never raises.
                  if Mag > (Long_Long_Integer'Last - Long_Long_Integer (D)) / B
                  then
                     return Fail (Decode_Integer_Out_Of_Range, Path, Source,
                                  Range_Params);
                  end if;
                  Mag := Mag * B + Long_Long_Integer (D);
                  Any := True;
                  Prev_Sep := False;
               end if;
            end;
            Idx := Idx + 1;
         end loop;

         if not Any then
            return Invalid;
         end if;

         declare
            Signed : constant Long_Long_Integer :=
              (if Negative then -Mag else Mag);
         begin
            if Signed < Long_Long_Integer (Target'First)
              or else Signed > Long_Long_Integer (Target'Last)
            then
               return Fail (Decode_Integer_Out_Of_Range, Path, Source,
                            Range_Params);
            end if;
            return Results.Make_Success (Target (Signed));
         end;
      end;
   end Decode;

end Web.Binding.Decoders.Integer_Decoders;
