package body Web.Binding.Decoders.Date_Decoders is

   use Web.Binding.Errors;

   function Meta return Decoder_Meta is
   begin
      return
        (Id            => To_Identifier ("web.binding.date"),
         Expected_Type => To_Identifier ("date"),
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
      Y, M, D : Integer;

      function Invalid return Result is
        (Results.Make_Failure
           (Single_Error (Make_Error (Decode_Invalid_Date, Path, Source))));

   begin
      if Text'Length /= 10
        or else Text (F + 4) /= '-' or else Text (F + 7) /= '-'
        or else not Calendar.Digits_Value (Text, F, 4, Y)
        or else not Calendar.Digits_Value (Text, F + 5, 2, M)
        or else not Calendar.Digits_Value (Text, F + 8, 2, D)
        or else not Calendar.Valid_Date (Y, M, D)
      then
         return Invalid;
      end if;

      return Results.Make_Success
        ((Year => Y, Month => M, Day => D));
   end Decode;

end Web.Binding.Decoders.Date_Decoders;
