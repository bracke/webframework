with Ada.Strings.Bounded;

--  Structured field paths.
--
--  A field path is a bounded sequence of typed segments, not a pre-rendered
--  string (invariant BIND-006). Rendering to text is a separate, deterministic
--  presentation step, so the same path can be localized or formatted differently
--  without losing its structure. Paths are bounded in both depth and per-segment
--  name length; appending past the depth bound saturates and sets a truncation
--  flag rather than raising.
package Web.Binding.Paths is

   pragma Preelaborate;

   --  Maximum characters retained per field or key name.
   Max_Segment_Name : constant := 128;

   --  Maximum number of segments in a path.
   Max_Depth : constant := 32;

   package Name_Strings is
     new Ada.Strings.Bounded.Generic_Bounded_Length (Max_Segment_Name);

   subtype Segment_Name is Name_Strings.Bounded_String;

   --  The kinds of path step. A root anchors the path to a request source; the
   --  others descend into fields, collection indices, map keys and union
   --  alternatives.
   type Segment_Kind is
     (Root_Segment,
      Field_Segment,
      Index_Segment,
      Key_Segment,
      Alternative_Segment);

   type Path_Segment (Kind : Segment_Kind := Field_Segment) is record
      case Kind is
         when Root_Segment =>
            Root : Source_Kind;
         when Field_Segment | Key_Segment | Alternative_Segment =>
            Name : Segment_Name;
         when Index_Segment =>
            Index : Index_Number;
      end case;
   end record;

   type Field_Path is private;

   --  An empty path with no segments. Rendered as the empty string.
   function Empty_Path return Field_Path;

   --  A path anchored at a request source root.
   --  @param Root The originating source kind.
   --  @return A single-segment path.
   function Rooted (Root : Source_Kind) return Field_Path;

   --  Append a named object field. Truncated names past Max_Segment_Name and
   --  appends past Max_Depth saturate deterministically.
   --  @param Path The path to extend.
   --  @param Name The field name.
   --  @return The extended path.
   function Append_Field (Path : Field_Path; Name : String) return Field_Path;

   --  Append a collection index.
   --  @param Path The path to extend.
   --  @param Index The zero-based element index.
   --  @return The extended path.
   function Append_Index
     (Path : Field_Path; Index : Index_Number) return Field_Path;

   --  Append a map key.
   --  @param Path The path to extend.
   --  @param Key The map key.
   --  @return The extended path.
   function Append_Key (Path : Field_Path; Key : String) return Field_Path;

   --  Append a union alternative selector.
   --  @param Path The path to extend.
   --  @param Name The alternative name.
   --  @return The extended path.
   function Append_Alternative
     (Path : Field_Path; Name : String) return Field_Path;

   --  The number of segments in the path.
   --  @param Path The path.
   --  @return The segment count.
   function Depth (Path : Field_Path) return Depth_Count;

   --  Whether the path saturated a bound (name length or depth) when built.
   --  @param Path The path.
   --  @return True if any append was truncated.
   function Truncated (Path : Field_Path) return Boolean;

   --  Render the path to a stable, deterministic string. A root becomes its
   --  source key (query, route, headers, cookies, body, multipart); a field or
   --  key becomes ".name"; an index becomes "[n]"; an alternative becomes
   --  "<name>". For example body.items[3].quantity or body.payment<card>.expiry.
   --  @param Path The path to render.
   --  @return The rendered path text.
   function Render (Path : Field_Path) return String;

   --  The stable source-root key used when rendering a root segment.
   --  @param Root The source kind.
   --  @return The root key text.
   function Source_Root_Key (Root : Source_Kind) return String;

   --  The name of the last field or map-key segment, or "" if the path has none.
   --  Used to attach an error to a form field by its leaf name.
   --  @param Path The path.
   --  @return The leaf field/key name, or the empty string.
   function Last_Name (Path : Field_Path) return String;

private

   type Segment_Array is array (Positive range 1 .. Max_Depth) of Path_Segment;

   type Field_Path is record
      Length         : Natural := 0;
      Truncated_Flag : Boolean := False;
      Segments       : Segment_Array;
   end record;

end Web.Binding.Paths;
