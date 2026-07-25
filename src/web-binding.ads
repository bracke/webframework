--  Request Binding and Input Decoding subsystem.
--
--  Web.Binding converts an already-parsed HTTP request into strongly typed Ada
--  values before validation and application logic run. It performs syntactic
--  decoding only: it never authenticates, authorizes, validates business rules,
--  stores files, or renders output. A syntactically invalid value is a decoding
--  failure here; a well-formed value that breaks an application rule is a
--  validation failure and belongs to a later layer.
--
--  This root package holds the foundational vocabulary shared by every child:
--  the request source kinds and the strongly separated scalar quantity types.
--  Keeping byte counts, item counts, offsets, depths and ordinals as distinct
--  types prevents accidental cross-assignment in the parsers that follow.
--
--  See docs/BINDING.md for the package map, error-id registry and invariants.
package Web.Binding is

   pragma Pure;

   --  Where a bound value originates. Path rendering and diagnostics use this
   --  to classify and to choose a stable source-root prefix.
   type Source_Kind is
     (Route_Parameter,
      Query_Parameter,
      Header_Value,
      Cookie_Value,
      URL_Encoded_Field,
      Multipart_Field,
      Multipart_Upload,
      Structured_Body);

   --  Strongly separated quantity types. They are deliberately distinct so that,
   --  for example, a byte offset can never be assigned to an item count without
   --  an explicit conversion. Ranges are generous but finite: every
   --  attacker-controlled dimension is bounded by an effective limit long before
   --  these type maxima are reached.

   --  A count of octets (body size, value length, header bytes).
   type Byte_Count is range 0 .. 2 ** 48;

   --  A count of items (collection elements, fields, parts).
   type Item_Count is range 0 .. 2 ** 31;

   --  A zero-based offset into a byte stream.
   type Offset_Count is range 0 .. 2 ** 48;

   --  A zero-based index into a collection.
   type Index_Number is range 0 .. 2 ** 31;

   --  A nesting depth (JSON, nested records, path segments).
   type Depth_Count is range 0 .. 4_096;

   --  A number of path segments.
   type Path_Length is range 0 .. 4_096;

   --  The 1-based occurrence ordinal of a repeated parameter or header.
   type Parameter_Ordinal is range 0 .. 2 ** 31;

   --  The 1-based number of a multipart part.
   type Part_Number is range 0 .. 2 ** 31;

   --  A count of accumulated errors.
   type Error_Count is range 0 .. 2 ** 31;

   --  A count of lexical tokens (JSON).
   type Token_Count is range 0 .. 2 ** 40;

   --  A 1-based line number, for source locations that expose one.
   type Line_Number is range 0 .. 2 ** 40;

   --  A 1-based column number, for source locations that expose one.
   type Column_Number is range 0 .. 2 ** 40;

end Web.Binding;
