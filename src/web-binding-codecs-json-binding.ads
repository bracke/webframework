with Ada.Strings.Unbounded;
with Web.Binding.Paths;
with Web.Binding.Results;

--  Typed JSON binding primitives.
--
--  Drives the phase-6 pull tokenizer to bind typed values without a DOM. The
--  reader is always positioned AT the current value token; the primitives walk
--  objects and arrays, skip unknown values, and extract scalars. The application
--  supplies deterministic member dispatch (a case on the key), tracks duplicates
--  with a Member_Tracker, and folds each field result into a Record_Binders
--  builder (via its Assign). Errors carry exact JSON paths and aggregate within
--  a structurally valid object.
package Web.Binding.Codecs.JSON.Binding is

   type Value_Shape is
     (Shape_String, Shape_Number, Shape_Boolean, Shape_Null,
      Shape_Object, Shape_Array, Shape_None);

   --  The shape of the value the reader is currently positioned at.
   --  @param R The reader.
   --  @return The shape.
   function Current_Shape (R : Reader) return Value_Shape;

   --  Whether the reader is at the start of an object.
   --  @param R The reader.
   --  @return True if Start_Object.
   function Begin_Object (R : Reader) return Boolean;

   --  Whether the reader is at the start of an array.
   --  @param R The reader.
   --  @return True if Start_Array.
   function Begin_Array (R : Reader) return Boolean;

   --  Read the next object member: advances past the key to its value token.
   --  Done is True at the object's end (consumed).
   --  @param R The reader.
   --  @param Key The member key (when not Done).
   --  @param Done True at End_Object.
   procedure Next_Member
     (R    : in out Reader;
      Key  : out Ada.Strings.Unbounded.Unbounded_String;
      Done : out Boolean);

   --  Advance to the next array element's value token. Done at End_Array.
   --  @param R The reader.
   --  @param Done True at End_Array.
   procedure Next_Element (R : in out Reader; Done : out Boolean);

   --  Skip the current value (scalar, or a whole nested object/array), leaving
   --  the reader on that value's last token.
   --  @param R The reader.
   procedure Skip_Value (R : in out Reader);

   --  Extract the current scalar value as a typed result via Decode. Objects and
   --  arrays are json.unexpected_kind; null is rejected here (the caller applies
   --  a null policy by checking Current_Shape first). Boolean values decode from
   --  "true"/"false"; numbers from their raw literal; strings from their text.
   generic
      type Field_Type is private;
      with package Field_Results is new Web.Binding.Results (Field_Type);
      with function Decode
        (Text   : String;
         Path   : Web.Binding.Paths.Field_Path;
         Source : Source_Kind) return Field_Results.Result;
   function Read_Scalar
     (R    : Reader;
      Path : Web.Binding.Paths.Field_Path) return Field_Results.Result;

   --  A bounded set of seen member keys, for duplicate detection.
   type Member_Tracker is private;

   --  A fresh tracker.
   --  @return The tracker.
   function New_Tracker return Member_Tracker;

   --  Note a key; Duplicate is True if it was already seen.
   --  @param T The tracker.
   --  @param Key The member key.
   --  @param Duplicate True on a repeat.
   procedure Note
     (T : in out Member_Tracker; Key : String; Duplicate : out Boolean);

   --  Whether a key has been seen (for required-field checking).
   --  @param T The tracker.
   --  @param Key The member key.
   --  @return True if seen.
   function Seen (T : Member_Tracker; Key : String) return Boolean;

private

   Max_Keys : constant := 256;

   type Key_Array is
     array (1 .. Max_Keys) of Ada.Strings.Unbounded.Unbounded_String;

   type Member_Tracker is record
      Count : Natural := 0;
      Keys  : Key_Array;
   end record;

end Web.Binding.Codecs.JSON.Binding;
