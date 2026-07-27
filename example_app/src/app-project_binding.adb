with Webframework_Forms;
with Forms.Submission;
with Forms.Urlencoded;
with Forms.Values;

package body App.Project_Binding is

   package WF renames Webframework_Forms;

   use type Forms.Urlencoded.Decode_Status;
   use type Forms.Values.Coerce_Status;

   --  A field's decoded string value ("" if absent).
   function Field (Sub : Forms.Submission.Data; Name : String) return String is
     (WF.To_String (Forms.Submission.Value_Of (Sub, WF.To_Bytes (Name))));

   --  A checkbox/boolean field, coerced with the forms library's lenient HTML
   --  semantics (1/true/on/yes -> True; absent/"" -> False).
   function Bool_Field (Sub : Forms.Submission.Data; Name : String) return Boolean
   is
      Result : Boolean;
      Status : Forms.Values.Coerce_Status;
   begin
      Forms.Values.To_Boolean
        (Forms.Submission.Value_Of (Sub, WF.To_Bytes (Name)), Result, Status);
      return Status = Forms.Values.Coerce_Ok and then Result;
   end Bool_Field;

   function Bind (Request : Web.Request.Request_Type) return Project_Form is
      Sub    : Forms.Submission.Data (32, 16384);
      Status : Forms.Urlencoded.Decode_Status;
      Result : Project_Form;
   begin
      WF.Read_Urlencoded (Request, Sub, Status);
      if Status /= Forms.Urlencoded.Decode_Ok then
         Result.Decoded := False;
         return Result;
      end if;

      Result.Name              := To_Unbounded_String (Field (Sub, "name"));
      Result.Status            := To_Unbounded_String (Field (Sub, "status"));
      Result.Project_Type      := To_Unbounded_String (Field (Sub, "project_type"));
      Result.Functions         := To_Unbounded_String (Field (Sub, "functions"));
      Result.Has_Project_Tools := Bool_Field (Sub, "has_project_tools");
      Result.Has_GNAT          := Bool_Field (Sub, "has_gnat");
      Result.Has_GitHub        := Bool_Field (Sub, "has_github");
      Result.Has_Alire         := Bool_Field (Sub, "has_alire");
      return Result;
   end Bind;

   function Bind_Delete (Request : Web.Request.Request_Type) return Delete_Form is
      Sub    : Forms.Submission.Data (8, 4096);
      Status : Forms.Urlencoded.Decode_Status;
      Result : Delete_Form;
   begin
      WF.Read_Urlencoded (Request, Sub, Status);
      if Status /= Forms.Urlencoded.Decode_Ok then
         Result.Decoded := False;
         return Result;
      end if;

      declare
         Id_Bytes : constant WF.Byte_Array :=
           Forms.Submission.Value_Of (Sub, WF.To_Bytes ("id"));
         Value    : Long_Long_Integer;
         Coerce   : Forms.Values.Coerce_Status;
      begin
         Forms.Values.To_Integer (Id_Bytes, Value, Coerce);
         if Id_Bytes'Length = 0 or else Coerce /= Forms.Values.Coerce_Ok then
            Result.Decoded := False;
         else
            Result.Id := Integer (Value);
         end if;
      end;
      return Result;
   end Bind_Delete;

end App.Project_Binding;
