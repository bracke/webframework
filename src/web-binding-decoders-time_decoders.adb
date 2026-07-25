package body Web.Binding.Decoders.Time_Decoders is

   use Web.Binding.Errors;

   function Meta return Decoder_Meta is
   begin
      return
        (Id            => To_Identifier ("web.binding.time"),
         Expected_Type => To_Identifier ("time"),
         Accepts       => Text_Only,
         Consumes_Stream => False,
         Max_Lookahead => 0);
   end Meta;

   function Decode
     (Text   : String;
      Path   : Web.Binding.Paths.Field_Path;
      Source : Source_Kind) return Result
   is
      F : constant Integer := Text'First;
      H, Mi, S : Integer;
      Millis : Integer := 0;

      function Invalid return Result is
        (Results.Make_Failure
           (Single_Error (Make_Error (Decode_Invalid_Time, Path, Source))));

   begin
      if Text'Length < 8
        or else Text (F + 2) /= ':' or else Text (F + 5) /= ':'
        or else not Calendar.Digits_Value (Text, F, 2, H)
        or else not Calendar.Digits_Value (Text, F + 3, 2, Mi)
        or else not Calendar.Digits_Value (Text, F + 6, 2, S)
        or else not Calendar.Valid_Time (H, Mi, S)
      then
         return Invalid;
      end if;

      --  Optional fractional seconds: '.' then 1..9 digits, milliseconds kept.
      if Text'Length > 8 then
         declare
            Frac_First : constant Integer := F + 9;
            Count      : constant Integer := Text'Last - Frac_First + 1;
            Buf        : String (1 .. 3) := "000";
            Kept       : constant Integer := Integer'Min (3, Count);
         begin
            if Text (F + 8) /= '.' or else Count < 1 or else Count > 9 then
               return Invalid;
            end if;
            for I in 0 .. Count - 1 loop
               if Text (Frac_First + I) not in '0' .. '9' then
                  return Invalid;
               end if;
            end loop;
            for I in 0 .. Kept - 1 loop
               Buf (I + 1) := Text (Frac_First + I);
            end loop;
            Millis :=
              (Character'Pos (Buf (1)) - Character'Pos ('0')) * 100
              + (Character'Pos (Buf (2)) - Character'Pos ('0')) * 10
              + (Character'Pos (Buf (3)) - Character'Pos ('0'));
         end;
      end if;

      return Results.Make_Success
        ((Hour => H, Minute => Mi, Second => S, Milli => Millis));
   end Decode;

end Web.Binding.Decoders.Time_Decoders;
