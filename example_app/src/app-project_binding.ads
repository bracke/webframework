with Ada.Strings.Unbounded;
with Web.Request;

--  Decodes the add-project form body (application/x-www-form-urlencoded) into
--  typed fields using the Web.Binding subsystem -- the `decode` step of the
--  decode -> validate pipeline. Extraction only; semantic checks live in
--  App.Project_Validation. Decoded is False when the form body itself is
--  malformed or exceeds the codec limits.
package App.Project_Binding is

   use Ada.Strings.Unbounded;

   type Project_Form is record
      Name              : Unbounded_String;
      Status            : Unbounded_String;
      Project_Type      : Unbounded_String;
      Functions         : Unbounded_String;
      Has_Project_Tools : Boolean := False;
      Has_GNAT          : Boolean := False;
      Has_GitHub        : Boolean := False;
      Has_Alire         : Boolean := False;
      Decoded           : Boolean := True;
   end record;

   function Bind (Request : Web.Request.Request_Type) return Project_Form;

   --  Delete command decoded from the body (id=NNN). Decoded is False when the
   --  body is malformed or the id is absent / not an integer.
   type Delete_Form is record
      Id      : Integer := 0;
      Decoded : Boolean := True;
   end record;

   function Bind_Delete (Request : Web.Request.Request_Type) return Delete_Form;

end App.Project_Binding;
