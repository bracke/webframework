with Ada.Strings.Bounded;
with Ada.Strings.Unbounded;
with Web.Binding.Streams;

--  Streaming multipart/form-data parser.
--
--  A defensive pull parser over a body stream. It skips the preamble, then for
--  each part reads the bounded headers (Content-Disposition -> field name and
--  optional filename; optional part Content-Type) and streams the body up to the
--  next boundary. Boundary detection uses a compacting buffer with block search
--  that holds back a delimiter-length tail, so a boundary split across read
--  chunks is found and the result is fragmentation-invariant; scanning is linear
--  and bounded, and file bodies are never fully buffered here (a caller streams
--  them via Read_Body; phase 11 wires the upload sink).
--
--  Client filenames are metadata only -- never a trusted path. Limits bound the
--  part count, header size and text-field size; malformed framing is a
--  structured Outcome, never an exception.
package Web.Binding.Multipart is

   Max_Meta : constant := 256;

   package Meta_Strings is
     new Ada.Strings.Bounded.Generic_Bounded_Length (Max_Meta);

   type Part_Info is record
      Name         : Meta_Strings.Bounded_String;
      Filename     : Meta_Strings.Bounded_String;
      Content_Type : Meta_Strings.Bounded_String;
      Is_File      : Boolean := False;
   end record;

   type Config is record
      Max_Parts        : Positive := 64;
      Max_Header_Bytes : Positive := 8_192;
      Max_Field_Bytes  : Positive := 65_536;
   end record;

   Default_Config : constant Config := (others => <>);

   type Outcome is
     (Ok,
      Malformed,
      Too_Many_Parts,
      Header_Too_Large,
      Field_Too_Large,
      Invalid_Boundary,
      Missing_Name,
      Stream_Failed);

   type Multipart_Reader
     (Stream : access Web.Binding.Streams.Input_Stream'Class) is limited private;

   --  Prime the reader with the boundary (from the Content-Type).
   --  @param R The reader.
   --  @param Boundary The multipart boundary (without dashes).
   --  @param Settings The limits.
   procedure Start
     (R        : in out Multipart_Reader;
      Boundary : String;
      Settings : Config := Default_Config);

   --  Advance to the next part, parsing its headers. Available is False at the
   --  end of the document or on a fatal condition (see Status).
   --  @param R The reader.
   --  @param Info The part's metadata (when Available).
   --  @param Available True when a part follows.
   procedure Next_Part
     (R         : in out Multipart_Reader;
      Info      : out Part_Info;
      Available : out Boolean);

   --  Stream the current part's body into Out_Buf. Done is True when the part
   --  ends (its boundary consumed). Call repeatedly until Done.
   --  @param R The reader.
   --  @param Out_Buf Receives body bytes.
   --  @param Last The last written index.
   --  @param Done True at the end of the part.
   procedure Read_Body
     (R       : in out Multipart_Reader;
      Out_Buf : out String;
      Last    : out Natural;
      Done    : out Boolean);

   --  Accumulate the current text part's body (bounded by Max_Field_Bytes).
   --  @param R The reader.
   --  @param Value The accumulated body.
   procedure Read_Text
     (R     : in out Multipart_Reader;
      Value : out Ada.Strings.Unbounded.Unbounded_String);

   --  Drain and discard the current part's body (for an ignored part).
   --  @param R The reader.
   procedure Skip_Body (R : in out Multipart_Reader);

   --  The parser status.
   --  @param R The reader.
   --  @return The outcome so far.
   function Status (R : Multipart_Reader) return Outcome;

private

   Max_Delimiter : constant := 210;   --  "\r\n--" + boundary (<= 200)
   Buffer_Size   : constant := 8_192;

   type Parse_State is
     (S_Before_Headers, S_In_Body, S_Done, S_Error);

   type Multipart_Reader
     (Stream : access Web.Binding.Streams.Input_Stream'Class) is limited record
      Settings   : Config := Default_Config;
      Delimiter  : String (1 .. Max_Delimiter);
      Delim_Len  : Natural := 0;
      Buf        : String (1 .. Buffer_Size);
      Pos        : Natural := 1;
      Last       : Natural := 0;
      Stream_End : Boolean := False;
      State      : Parse_State := S_Done;
      Parts      : Natural := 0;
      Result     : Outcome := Ok;
   end record;

end Web.Binding.Multipart;
