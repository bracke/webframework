with Ada.Strings.Bounded;
with Web.Binding.Errors;

--  Validation integration adapter.
--
--  No Validation sibling exists yet, so this is the narrow contract the seam
--  needs: a merged presentation that combines a bind result's decoding errors
--  with the validation layer's semantic issues, preserving each entry's origin
--  (From_Decoding vs From_Validation). Binding hands validation a decoded typed
--  value and compatible field paths (this package renders decoding paths and
--  accepts validation paths in the same string form); validation never touches
--  the raw request, and semantic rules never live in binding descriptors.
package Web.Binding.Validation is

   type Issue_Origin is (From_Decoding, From_Validation);

   Max_Entries : constant := 128;
   Max_Field   : constant := 128;
   Max_Key     : constant := 128;
   Max_Path    : constant := 512;

   package Field_Strings is
     new Ada.Strings.Bounded.Generic_Bounded_Length (Max_Field);
   package Key_Strings is
     new Ada.Strings.Bounded.Generic_Bounded_Length (Max_Key);
   package Path_Strings is
     new Ada.Strings.Bounded.Generic_Bounded_Length (Max_Path);

   type Presentation is limited private;

   --  Empty the presentation.
   --  @param P The presentation.
   procedure Reset (P : out Presentation);

   --  Append a bind result's decoding errors (origin From_Decoding), each with
   --  its stable error-id key, leaf field name and rendered path.
   --  @param P The presentation.
   --  @param Errors The decoding errors.
   procedure Add_Decoding_Errors
     (P : in out Presentation; Errors : Web.Binding.Errors.Error_Collection);

   --  Append a validation issue (origin From_Validation).
   --  @param P The presentation.
   --  @param Field The field id.
   --  @param Code The stable validation code (localization key).
   --  @param Path The field path, in the same rendered form as decoding paths.
   procedure Add_Validation_Issue
     (P     : in out Presentation;
      Field : String;
      Code  : String;
      Path  : String := "");

   --  The total number of entries.
   --  @param P The presentation.
   --  @return The count.
   function Count (P : Presentation) return Natural;

   --  The origin of an entry.
   --  @param P The presentation.
   --  @param Index The 1-based position.
   --  @return The origin.
   function Origin_Of (P : Presentation; Index : Positive) return Issue_Origin;

   --  The field of an entry.
   --  @param P The presentation.
   --  @param Index The 1-based position.
   --  @return The field id.
   function Field_Of (P : Presentation; Index : Positive) return String;

   --  The key (error-id key or validation code) of an entry.
   --  @param P The presentation.
   --  @param Index The 1-based position.
   --  @return The key.
   function Key_Of (P : Presentation; Index : Positive) return String;

   --  The rendered path of an entry.
   --  @param P The presentation.
   --  @param Index The 1-based position.
   --  @return The path text.
   function Path_Of (P : Presentation; Index : Positive) return String;

   --  The number of decoding-origin entries.
   --  @param P The presentation.
   --  @return The count.
   function Decoding_Count (P : Presentation) return Natural;

   --  The number of validation-origin entries.
   --  @param P The presentation.
   --  @return The count.
   function Validation_Count (P : Presentation) return Natural;

private

   type Entry_Record is record
      Origin : Issue_Origin := From_Decoding;
      Field  : Field_Strings.Bounded_String;
      Key    : Key_Strings.Bounded_String;
      Path   : Path_Strings.Bounded_String;
   end record;

   type Entry_Array is array (1 .. Max_Entries) of Entry_Record;

   type Presentation is limited record
      Used    : Natural := 0;
      Entries : Entry_Array;
   end record;

end Web.Binding.Validation;
