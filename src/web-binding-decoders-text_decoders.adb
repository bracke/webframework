package body Web.Binding.Decoders.Text_Decoders is

   use Web.Binding.Errors;

   function Meta return Decoder_Meta is
   begin
      return
        (Id            => To_Identifier ("web.binding.text"),
         Expected_Type => To_Identifier ("text"),
         Accepts       => Text_Only,
         Consumes_Stream => False,
         Max_Lookahead => 0);
   end Meta;

   function Fail
     (Id     : Error_Id;
      Path   : Web.Binding.Paths.Field_Path;
      Source : Source_Kind;
      Params : Error_Parameters := No_Parameters) return Result is
   begin
      return Results.Make_Failure
        (Single_Error (Make_Error (Id, Path, Source, Decode_Origin,
                                   Parameters => Params)));
   end Fail;

   function Decode
     (Text     : String;
      Path     : Web.Binding.Paths.Field_Path;
      Source   : Source_Kind;
      Settings : Config := Default_Config) return Result
   is
      Over_Limit : constant Boolean :=
        Settings.Max_Bytes > 0
        and then Byte_Count (Text'Length) > Settings.Max_Bytes;
   begin
      if Settings.Require_UTF8 and then not Valid_UTF8 (Text) then
         return Fail (Decode_Invalid_UTF8, Path, Source);
      end if;

      if Over_Limit or else Text'Length > Bounded.Max_Length then
         declare
            Params : Error_Parameters;
         begin
            Params.Has_Actual := True;
            Params.Actual := Long_Long_Integer (Text'Length);
            Params.Has_Maximum := True;
            Params.Maximum :=
              (if Settings.Max_Bytes > 0
               then Long_Long_Integer (Settings.Max_Bytes)
               else Long_Long_Integer (Bounded.Max_Length));
            return Fail (Decode_Value_Too_Long, Path, Source, Params);
         end;
      end if;

      return Results.Make_Success
        (Bounded.To_Bounded_String (Text));
   end Decode;

end Web.Binding.Decoders.Text_Decoders;
