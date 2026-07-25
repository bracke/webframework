package body Web.Binding.Decoders.DateTime_Decoders is

   use Web.Binding.Errors;

   function Meta return Decoder_Meta is
   begin
      return
        (Id            => To_Identifier ("web.binding.datetime"),
         Expected_Type => To_Identifier ("datetime"),
         Accepts       => Text_Only,
         Consumes_Stream => False,
         Max_Lookahead => 0);
   end Meta;

   function Decode
     (Text   : String;
      Path   : Web.Binding.Paths.Field_Path;
      Source : Source_Kind) return Result
   is
      F    : constant Integer := Text'First;
      Last : constant Integer := Text'Last;

      Y, M, D, H, Mi, S : Integer;
      Millis      : Integer := 0;
      Offset      : Integer := 0;
      Cur         : Integer;

      function Invalid return Result is
        (Results.Make_Failure
           (Single_Error (Make_Error (Decode_Invalid_Datetime, Path, Source))));

   begin
      --  "YYYY-MM-DDThh:mm:ssZ" is the shortest acceptable form (20 chars).
      if Text'Length < 20
        or else Text (F + 4) /= '-' or else Text (F + 7) /= '-'
        or else Text (F + 10) not in 'T' | 't' | ' '
        or else Text (F + 13) /= ':' or else Text (F + 16) /= ':'
        or else not Calendar.Digits_Value (Text, F, 4, Y)
        or else not Calendar.Digits_Value (Text, F + 5, 2, M)
        or else not Calendar.Digits_Value (Text, F + 8, 2, D)
        or else not Calendar.Digits_Value (Text, F + 11, 2, H)
        or else not Calendar.Digits_Value (Text, F + 14, 2, Mi)
        or else not Calendar.Digits_Value (Text, F + 17, 2, S)
        or else not Calendar.Valid_Date (Y, M, D)
        or else not Calendar.Valid_Time (H, Mi, S)
      then
         return Invalid;
      end if;

      Cur := F + 19;

      --  Optional fractional seconds.
      if Cur <= Last and then Text (Cur) = '.' then
         Cur := Cur + 1;
         declare
            Frac_Start : constant Integer := Cur;
            Buf        : String (1 .. 3) := "000";
            Kept       : Integer;
         begin
            while Cur <= Last and then Text (Cur) in '0' .. '9' loop
               Cur := Cur + 1;
            end loop;
            declare
               Count : constant Integer := Cur - Frac_Start;
            begin
               if Count < 1 or else Count > 9 then
                  return Invalid;
               end if;
               Kept := Integer'Min (3, Count);
            end;
            for I in 0 .. Kept - 1 loop
               Buf (I + 1) := Text (Frac_Start + I);
            end loop;
            Millis :=
              (Character'Pos (Buf (1)) - Character'Pos ('0')) * 100
              + (Character'Pos (Buf (2)) - Character'Pos ('0')) * 10
              + (Character'Pos (Buf (3)) - Character'Pos ('0'));
         end;
      end if;

      --  Required time offset.
      if Cur > Last then
         return Invalid;
      end if;

      if Text (Cur) in 'Z' | 'z' then
         Offset := 0;
         Cur := Cur + 1;
      elsif Text (Cur) in '+' | '-' then
         declare
            Sign : constant Character := Text (Cur);
            OH, OM : Integer;
         begin
            if Cur + 5 > Last
              or else Text (Cur + 3) /= ':'
              or else not Calendar.Digits_Value (Text, Cur + 1, 2, OH)
              or else not Calendar.Digits_Value (Text, Cur + 4, 2, OM)
              or else OH > 23 or else OM > 59
            then
               return Invalid;
            end if;
            Offset := OH * 60 + OM;
            if Sign = '-' then
               Offset := -Offset;
            end if;
            Cur := Cur + 6;
         end;
      else
         return Invalid;
      end if;

      --  No trailing content.
      if Cur <= Last then
         return Invalid;
      end if;

      return Results.Make_Success
        ((Date           => (Year => Y, Month => M, Day => D),
          Time           => (Hour => H, Minute => Mi, Second => S,
                             Milli => Millis),
          Has_Offset     => True,
          Offset_Minutes => Offset));
   end Decode;

end Web.Binding.Decoders.DateTime_Decoders;
