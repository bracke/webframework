with Web.Binding.Paths;
with Web.Binding.Results;
with Web.Binding.Decoders.Calendar;

--  RFC 3339 date-time decoder.
--
--  Accepts full-date "T" full-time with a required time offset (Z or +/-hh:mm)
--  and optional fractional seconds. The date-time separator may be 'T', 't' or a
--  space. The date and time components are validated as real calendar values, so
--  an impossible instant is decode.invalid_datetime, not an exception.
package Web.Binding.Decoders.DateTime_Decoders is

   subtype Date_Time_Value is Calendar.Date_Time_Value;

   package Results is new Web.Binding.Results (Date_Time_Value);

   subtype Result is Results.Result;

   --  The decoder's static metadata.
   --  @return The metadata describing this decoder.
   function Meta return Decoder_Meta;

   --  Decode an RFC 3339 date-time or a structured error.
   --  @param Text The raw input text.
   --  @param Path The exact structured path.
   --  @param Source The originating source kind.
   --  @return A success value or a decoding error.
   function Decode
     (Text   : String;
      Path   : Web.Binding.Paths.Field_Path;
      Source : Source_Kind) return Result;

end Web.Binding.Decoders.DateTime_Decoders;
