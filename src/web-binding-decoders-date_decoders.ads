with Web.Binding.Paths;
with Web.Binding.Results;
with Web.Binding.Decoders.Calendar;

--  ISO 8601 calendar date decoder.
--
--  Accepts exactly YYYY-MM-DD. A well-formed but impossible date such as
--  2026-02-31 is decode.invalid_date -- a decoding failure, distinct from a
--  valid date that a later validation layer rejects for business reasons.
package Web.Binding.Decoders.Date_Decoders is

   subtype Date_Value is Calendar.Date_Value;

   package Results is new Web.Binding.Results (Date_Value);

   subtype Result is Results.Result;

   --  The decoder's static metadata.
   --  @return The metadata describing this decoder.
   function Meta return Decoder_Meta;

   --  Decode an ISO 8601 date (YYYY-MM-DD) or a structured error.
   --  @param Text The raw input text.
   --  @param Path The exact structured path.
   --  @param Source The originating source kind.
   --  @return A success value or a decoding error.
   function Decode
     (Text   : String;
      Path   : Web.Binding.Paths.Field_Path;
      Source : Source_Kind) return Result;

end Web.Binding.Decoders.Date_Decoders;
