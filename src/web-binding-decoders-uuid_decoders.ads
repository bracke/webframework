with Web.Binding.Paths;
with Web.Binding.Results;

--  UUID decoder.
--
--  Accepts only the canonical hyphenated form (8-4-4-4-12 hex digits) and
--  normalizes it to lowercase. Anything else is decode.invalid_uuid.
package Web.Binding.Decoders.UUID_Decoders is

   --  A normalized canonical UUID.
   type UUID_Value is record
      Text : String (1 .. 36);
   end record;

   package Results is new Web.Binding.Results (UUID_Value);

   subtype Result is Results.Result;

   --  The decoder's static metadata.
   --  @return The metadata describing this decoder.
   function Meta return Decoder_Meta;

   --  Decode Text into a normalized UUID or a structured error.
   --  @param Text The raw input text.
   --  @param Path The exact structured path.
   --  @param Source The originating source kind.
   --  @return A success value or a decoding error.
   function Decode
     (Text   : String;
      Path   : Web.Binding.Paths.Field_Path;
      Source : Source_Kind) return Result;

   --  The canonical text of a decoded UUID.
   --  @param Value The UUID value.
   --  @return Its 36-character canonical string.
   function Image (Value : UUID_Value) return String;

end Web.Binding.Decoders.UUID_Decoders;
