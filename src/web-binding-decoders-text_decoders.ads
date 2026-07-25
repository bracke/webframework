with Ada.Strings.Bounded;
with Web.Binding.Paths;
with Web.Binding.Results;

--  Bounded text decoder.
--
--  Validates UTF-8 by default and enforces a byte-length bound (both the
--  bounded type's capacity and an optional tighter Max_Bytes), then yields the
--  text as the bounded string Target. Invalid UTF-8 is decode.invalid_utf8;
--  over-length input is decode.value_too_long. Never truncates silently.
generic
   with package Bounded is
     new Ada.Strings.Bounded.Generic_Bounded_Length (<>);
package Web.Binding.Decoders.Text_Decoders is

   subtype Target is Bounded.Bounded_String;

   type Config is record
      Require_UTF8 : Boolean := True;
      Max_Bytes    : Byte_Count := 0;
   end record;

   Default_Config : constant Config := (others => <>);

   package Results is new Web.Binding.Results (Target);

   subtype Result is Results.Result;

   --  The decoder's static metadata.
   --  @return The metadata describing this decoder.
   function Meta return Decoder_Meta;

   --  Decode Text into the bounded string Target or a structured error.
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

end Web.Binding.Decoders.Text_Decoders;
