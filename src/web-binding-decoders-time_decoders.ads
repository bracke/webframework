with Web.Binding.Paths;
with Web.Binding.Results;
with Web.Binding.Decoders.Calendar;

--  Time-of-day decoder.
--
--  Accepts HH:MM:SS with an optional fractional part (.f up to .fffffffff),
--  keeping millisecond resolution. 24-hour, zero-padded fields; a leap second
--  (:60) is permitted. Anything else is decode.invalid_time.
package Web.Binding.Decoders.Time_Decoders is

   subtype Time_Value is Calendar.Time_Value;

   package Results is new Web.Binding.Results (Time_Value);

   subtype Result is Results.Result;

   --  The decoder's static metadata.
   --  @return The metadata describing this decoder.
   function Meta return Decoder_Meta;

   --  Decode a time of day (HH:MM:SS[.frac]) or a structured error.
   --  @param Text The raw input text.
   --  @param Path The exact structured path.
   --  @param Source The originating source kind.
   --  @return A success value or a decoding error.
   function Decode
     (Text   : String;
      Path   : Web.Binding.Paths.Field_Path;
      Source : Source_Kind) return Result;

end Web.Binding.Decoders.Time_Decoders;
