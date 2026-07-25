package body Web.Binding.Decoders.Defaulted_Decoders is

   function Decode
     (Is_Present : Boolean;
      Default    : Target;
      Text       : String;
      Path       : Web.Binding.Paths.Field_Path;
      Source     : Source_Kind) return Base_Results.Result is
   begin
      if not Is_Present then
         return Base_Results.Make_Success (Default);
      end if;
      --  Present: delegate. A malformed present value stays an error and is
      --  never silently replaced by the default.
      return Base_Decode (Text, Path, Source);
   end Decode;

end Web.Binding.Decoders.Defaulted_Decoders;
