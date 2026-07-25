with Ada.Strings.Unbounded;
with Web.Binding.Streams;
with Web.Binding.Sources;

--  Streaming application/x-www-form-urlencoded codec.
--
--  Parses a body stream into ordered name/value pairs without buffering the
--  whole body as one string: a byte-level state machine consumes each chunk, so
--  percent escapes and the '&' / '=' delimiters may split across reads and the
--  result is identical regardless of fragmentation. Percent-decodes both parts
--  and maps '+' to space; a malformed or truncated escape marks that value
--  (resolved later as form.invalid_percent_escape) without discarding it. Pair
--  count and per-field name/value lengths are bounded; the aggregate body size
--  is bounded by the stream limit. Lookup exposes the pairs as Sources.
--
--  Charset note: bytes are delivered as decoded; UTF-8 validation is a decoder
--  concern (Web.Binding.Decoders.Text_Decoders yields decode.invalid_utf8),
--  keeping extraction and decoding layered.
package Web.Binding.Codecs.URL_Encoded is

   type Form_Source is private;

   type Parse_Outcome is
     (Parsed,
      Too_Many_Fields,
      Field_Too_Large,
      Body_Too_Large,
      Stream_Failed,
      Cancelled);

   type Config is record
      Plus_As_Space : Boolean := True;
      Max_Fields    : Positive := 512;
      Max_Name      : Positive := 4_096;
      Max_Value     : Positive := 65_536;
   end record;

   Default_Config : constant Config := (others => <>);

   --  Parse a body stream into a form source.
   --  @param Stream The body input stream (consumed to end or fatal error).
   --  @param Result The parsed pairs.
   --  @param Outcome Parsed, or the fatal condition that stopped parsing.
   --  @param Settings The immutable configuration.
   procedure Parse
     (Stream   : in out Web.Binding.Streams.Input_Stream'Class;
      Result   : out Form_Source;
      Outcome  : out Parse_Outcome;
      Settings : Config := Default_Config);

   --  Every value supplied for Name, in request order.
   --  @param Source The parsed form.
   --  @param Name The field name.
   --  @return The occurrences.
   function Lookup
     (Source : Form_Source; Name : String)
      return Web.Binding.Sources.Occurrences;

   --  The number of parsed pairs.
   --  @param Source The parsed form.
   --  @return The pair count.
   function Field_Count (Source : Form_Source) return Natural;

private

   Max_Stored_Fields : constant := 512;

   type Form_Pair is record
      Name  : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
      Bad   : Boolean := False;
   end record;

   type Pair_Array is array (1 .. Max_Stored_Fields) of Form_Pair;

   type Form_Source is record
      Length : Natural := 0;
      Pairs  : Pair_Array;
   end record;

end Web.Binding.Codecs.URL_Encoded;
