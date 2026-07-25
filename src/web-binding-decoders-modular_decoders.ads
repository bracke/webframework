with Web.Binding.Paths;
with Web.Binding.Results;

--  Modular integer decoder.
--
--  Decodes an unsigned value of the modular type Target, distinguishing invalid
--  syntax (decode.invalid_integer) from a value at or above the modulus
--  (decode.integer_out_of_range). Decimal by default; no sign. Overflow-guarded,
--  never raising.
generic
   type Target is mod <>;
package Web.Binding.Decoders.Modular_Decoders is

   type Radix is (Decimal, Hexadecimal, Octal, Binary);

   type Config is record
      Base               : Radix := Decimal;
      Allow_Whitespace   : Boolean := False;
      Allow_Separators   : Boolean := False;
      Allow_Leading_Zero : Boolean := True;
   end record;

   Default_Config : constant Config := (others => <>);

   package Results is new Web.Binding.Results (Target);

   subtype Result is Results.Result;

   --  The decoder's static metadata.
   --  @return The metadata describing this decoder.
   function Meta return Decoder_Meta;

   --  Decode Text into a modular Target value or a structured error.
   --  @param Text The raw input text.
   --  @param Path The exact structured path.
   --  @param Source The originating source kind.
   --  @param Settings The immutable configuration.
   --  @return A success value or a decoding error.
   function Decode
     (Text     : String;
      Path     : Web.Binding.Paths.Field_Path;
      Source   : Source_Kind;
      Settings : Config := Default_Config) return Result;

end Web.Binding.Decoders.Modular_Decoders;
