with Web.Binding.Paths;
with Web.Binding.Results;

--  Signed integer decoder.
--
--  Decodes text to a value of the signed integer type Target, distinguishing
--  invalid syntax (decode.invalid_integer) from a well-formed value outside the
--  target range (decode.integer_out_of_range). It never raises on malformed or
--  oversized input: the magnitude is accumulated with an explicit overflow
--  guard and range-checked against Target'First .. Target'Last.
--
--  Target must lie within Long_Long_Integer's range (the usual HTTP integer
--  targets: Integer, Natural, Positive, Long_Integer, Long_Long_Integer and
--  subranges). Wider targets need a dedicated decoder.
generic
   type Target is range <>;
package Web.Binding.Decoders.Integer_Decoders is

   --  The accepted numeric base.
   type Radix is (Decimal, Hexadecimal, Octal, Binary);

   --  Immutable decoder configuration. The defaults are the strict query/form
   --  policy: decimal only, no surrounding whitespace, no digit separators, no
   --  leading plus, negatives allowed, and no partial parsing.
   type Config is record
      Base               : Radix := Decimal;
      Allow_Negative     : Boolean := True;
      Allow_Leading_Plus : Boolean := False;
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

   --  Decode Text into a Target value or a structured error.
   --  @param Text The raw input text.
   --  @param Path The exact structured path, for error provenance.
   --  @param Source The originating source kind.
   --  @param Settings The immutable configuration.
   --  @return A success value or a decoding error.
   function Decode
     (Text     : String;
      Path     : Web.Binding.Paths.Field_Path;
      Source   : Source_Kind;
      Settings : Config := Default_Config) return Result;

end Web.Binding.Decoders.Integer_Decoders;
