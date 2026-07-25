with Web.Binding.Errors;

function Web.Binding.Decoders.Guard
  (Text   : String;
   Path   : Web.Binding.Paths.Field_Path;
   Source : Source_Kind) return Field_Results.Result is
begin
   return Decode (Text, Path, Source);
exception
   when others =>
      declare
         C : Web.Binding.Errors.Error_Collection :=
           Web.Binding.Errors.Empty_Collection;
      begin
         Web.Binding.Errors.Append
           (C,
            Web.Binding.Errors.Make_Error
              (Web.Binding.Errors.Internal_Decoder_Failure, Path, Source,
               Web.Binding.Errors.Internal_Origin));
         return Field_Results.Make_Failure (C);
      end;
end Web.Binding.Decoders.Guard;
