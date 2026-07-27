with Ada.Strings.Unbounded;

--  Bounded multipart/form-data parsing (RFC 7578). The webframework owns
--  multipart parsing; this splits an already-read request body into parts
--  without copying content -- each part records the byte range of its content
--  within the original body string. Failures are reported as a status, never an
--  exception. Applications feed file parts to an upload adapter and field parts
--  to the forms decode.
package Web.Multipart is

   Max_Parts        : constant := 256;
   Max_Header_Bytes : constant := 4_096;   --  per-part header section ceiling

   type Part_Kind is (Field_Part, File_Part);

   type Part is record
      Kind         : Part_Kind := Field_Part;
      Name         : Ada.Strings.Unbounded.Unbounded_String;
      Filename     : Ada.Strings.Unbounded.Unbounded_String;  --  file parts only
      Content_Type : Ada.Strings.Unbounded.Unbounded_String;
      --  Content is Body_Text (First .. Last); Last < First means empty content.
      First        : Positive := 1;
      Last         : Natural  := 0;
   end record;

   type Part_Array is array (Positive range <>) of Part;

   type Parse_Status is (Ok, No_Boundary, Malformed, Too_Many_Parts);

   --  Parse Body_Text delimited by Boundary into Parts (a caller-sized buffer);
   --  Count is how many were filled. Too_Many_Parts if the body has more parts
   --  than Parts'Length or Max_Parts.
   procedure Parse
     (Body_Text : String;
      Boundary  : String;
      Parts     : out Part_Array;
      Count     : out Natural;
      Status    : out Parse_Status);

   --  Extract the boundary token from a Content-Type header value
   --  ("multipart/form-data; boundary=XYZ"); "" if absent. Handles a quoted
   --  boundary.
   function Boundary_Of (Content_Type : String) return String;

end Web.Multipart;
