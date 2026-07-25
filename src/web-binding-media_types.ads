with Ada.Strings.Bounded;

--  Structural media-type parsing.
--
--  Parses a Content-Type value ("application/json; charset=utf-8",
--  "multipart/form-data; boundary=xyz", "application/vnd.api+json") into its
--  type, subtype, structured suffix, charset and multipart boundary. Type,
--  subtype, suffix and charset are lowercased (case-insensitive); the boundary
--  is kept verbatim. Invalid syntax leaves the result Valid => False, which the
--  caller maps to body.invalid_content_type -- parsing never raises.
package Web.Binding.Media_Types is

   Max_Token    : constant := 127;
   Max_Boundary : constant := 200;

   package Tokens is
     new Ada.Strings.Bounded.Generic_Bounded_Length (Max_Token);
   package Boundaries is
     new Ada.Strings.Bounded.Generic_Bounded_Length (Max_Boundary);

   type Media_Type is record
      Valid      : Boolean := False;
      Main       : Tokens.Bounded_String;      --  "application"
      Sub         : Tokens.Bounded_String;     --  "vnd.api+json"
      Suffix     : Tokens.Bounded_String;      --  "json" (after '+'), else empty
      Charset    : Tokens.Bounded_String;      --  from ;charset=, else empty
      Boundary   : Boundaries.Bounded_String;  --  from ;boundary=, else empty
   end record;

   --  Parse a Content-Type value.
   --  @param Text The raw header value.
   --  @return The parsed media type (Valid => False on malformed syntax).
   function Parse (Text : String) return Media_Type;

   --  Whether the media type parsed.
   --  @param M The media type.
   --  @return True if valid.
   function Is_Valid (M : Media_Type) return Boolean;

   --  Whether the subtype carries a structured suffix (e.g. +json).
   --  @param M The media type.
   --  @return True if a suffix is present.
   function Has_Suffix (M : Media_Type) return Boolean;

   --  The normalized "type/subtype" text (lowercased), or "" if invalid.
   --  @param M The media type.
   --  @return The normalized essence.
   function Normalized (M : Media_Type) return String;

end Web.Binding.Media_Types;
