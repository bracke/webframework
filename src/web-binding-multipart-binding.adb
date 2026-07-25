with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Web.Binding.Multipart.Binding is

   function Read_Field
     (R    : in out Multipart_Reader;
      Path : Web.Binding.Paths.Field_Path) return Field_Results.Result
   is
      Value : Unbounded_String;
   begin
      Read_Text (R, Value);
      return Decode (To_String (Value), Path, Multipart_Field);
   end Read_Field;

   function New_Tracker return Field_Tracker is
      T : Field_Tracker;
   begin
      return T;
   end New_Tracker;

   procedure Note
     (T : in out Field_Tracker; Name : String; Duplicate : out Boolean) is
   begin
      for I in 1 .. T.Count loop
         if To_String (T.Names (I)) = Name then
            Duplicate := True;
            return;
         end if;
      end loop;
      Duplicate := False;
      if T.Count < Max_Fields then
         T.Count := T.Count + 1;
         T.Names (T.Count) := To_Unbounded_String (Name);
      end if;
   end Note;

   function Seen (T : Field_Tracker; Name : String) return Boolean is
   begin
      for I in 1 .. T.Count loop
         if To_String (T.Names (I)) = Name then
            return True;
         end if;
      end loop;
      return False;
   end Seen;

end Web.Binding.Multipart.Binding;
