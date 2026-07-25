with Ada.Strings.Bounded;
with Web.Binding.Paths;
with Web.Binding.Results;

--  Base64 decoder.
--
--  Decodes standard or URL-safe Base64 text into raw bytes, delivered as the
--  bounded string Target (one Character per byte). Malformed input (bad
--  alphabet, misplaced or wrong-count padding, data after padding) is
--  decode.invalid_base64; output exceeding the bound is decode.value_too_long.
generic
   with package Bounded is
     new Ada.Strings.Bounded.Generic_Bounded_Length (<>);
package Web.Binding.Decoders.Base64_Decoders is

   subtype Target is Bounded.Bounded_String;

   type Alphabet is (Standard, URL_Safe);

   type Config is record
      Which           : Alphabet := Standard;
      Require_Padding : Boolean := True;
   end record;

   Default_Config : constant Config := (others => <>);

   package Results is new Web.Binding.Results (Target);

   subtype Result is Results.Result;

   --  The decoder's static metadata.
   --  @return The metadata describing this decoder.
   function Meta return Decoder_Meta;

   --  Decode Base64 Text into raw bytes or a structured error.
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

end Web.Binding.Decoders.Base64_Decoders;
