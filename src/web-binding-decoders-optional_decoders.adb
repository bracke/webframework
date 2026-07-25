package body Web.Binding.Decoders.Optional_Decoders is

   function Decode
     (Is_Present : Boolean;
      Text       : String;
      Path       : Web.Binding.Paths.Field_Path;
      Source     : Source_Kind) return Result is
   begin
      if not Is_Present then
         return Results.Make_Success ((Present => False));
      end if;

      declare
         Base : constant Base_Results.Result := Base_Decode (Text, Path, Source);
      begin
         if Base_Results.Succeeded (Base) then
            return Results.Make_Success
              ((Present => True, Value => Base_Results.Value_Of (Base)));
         else
            return Results.Make_Failure (Base_Results.Errors_Of (Base));
         end if;
      end;
   end Decode;

end Web.Binding.Decoders.Optional_Decoders;
