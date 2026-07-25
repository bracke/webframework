with Ada.Strings.Unbounded;
with Web.Binding.Paths;
with Web.Binding.Results;

--  Typed multipart binding helpers.
--
--  The ergonomic counterpart of Web.Binding.Codecs.JSON.Binding for multipart
--  forms: the application iterates parts (Multipart.Next_Part), dispatches on the
--  field name, and for a text field calls Read_Field to decode its body into a
--  typed result (folded into a Record_Binders builder with Assign); for a file
--  field it streams via Web.Binding.Uploads.Stream_Part. A Field_Tracker gives
--  duplicate detection and required-field checking.
package Web.Binding.Multipart.Binding is

   --  Read the current text part's body and decode it as a scalar. The caller
   --  should have confirmed the part is a text field (Info.Is_File is False);
   --  a file part is streamed through the upload session instead.
   generic
      type Field_Type is private;
      with package Field_Results is new Web.Binding.Results (Field_Type);
      with function Decode
        (Text   : String;
         Path   : Web.Binding.Paths.Field_Path;
         Source : Source_Kind) return Field_Results.Result;
   function Read_Field
     (R    : in out Multipart_Reader;
      Path : Web.Binding.Paths.Field_Path) return Field_Results.Result;

   --  A bounded set of seen field names, for duplicate and required checks.
   type Field_Tracker is private;

   --  A fresh tracker.
   --  @return The tracker.
   function New_Tracker return Field_Tracker;

   --  Note a field name; Duplicate is True if it was already seen.
   --  @param T The tracker.
   --  @param Name The field name.
   --  @param Duplicate True on a repeat.
   procedure Note
     (T : in out Field_Tracker; Name : String; Duplicate : out Boolean);

   --  Whether a field name has been seen.
   --  @param T The tracker.
   --  @param Name The field name.
   --  @return True if seen.
   function Seen (T : Field_Tracker; Name : String) return Boolean;

private

   Max_Fields : constant := 256;

   type Name_Array is
     array (1 .. Max_Fields) of Ada.Strings.Unbounded.Unbounded_String;

   type Field_Tracker is record
      Count : Natural := 0;
      Names : Name_Array;
   end record;

end Web.Binding.Multipart.Binding;
