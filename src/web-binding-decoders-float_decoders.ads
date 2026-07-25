with Web.Binding.Paths;
with Web.Binding.Results;

--  Floating-point decoder.
--
--  Decodes a strict decimal float (optional sign, digits, optional fraction,
--  optional exponent) to Target. Rejects NaN/Infinity as decode.non_finite_float
--  and malformed syntax as decode.invalid_float. An overflow while converting is
--  caught at a defensive boundary and reported as decode.non_finite_float, never
--  propagated as an exception.
generic
   type Target is digits <>;
package Web.Binding.Decoders.Float_Decoders is

   package Results is new Web.Binding.Results (Target);

   subtype Result is Results.Result;

   --  The decoder's static metadata.
   --  @return The metadata describing this decoder.
   function Meta return Decoder_Meta;

   --  Decode Text into a Target float or a structured error.
   --  @param Text The raw input text.
   --  @param Path The exact structured path.
   --  @param Source The originating source kind.
   --  @return A success value or a decoding error.
   function Decode
     (Text   : String;
      Path   : Web.Binding.Paths.Field_Path;
      Source : Source_Kind) return Result;

end Web.Binding.Decoders.Float_Decoders;
