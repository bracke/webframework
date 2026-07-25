with Web.Binding.Codecs.URL_Encoded;
with Web.Binding.Sources;
with Web.Binding.Streams.Memory;
with Web.Binding.Policies;

package body App.Project_Binding is

   package URL renames Web.Binding.Codecs.URL_Encoded;
   package Src renames Web.Binding.Sources;
   package Mem renames Web.Binding.Streams.Memory;
   use Web.Binding.Policies;
   use type URL.Parse_Outcome;
   use type Src.Resolution_State;

   --  Resolve a single form field to its raw decoded value (empty when absent).
   function Field (Form : URL.Form_Source; Name : String) return String is
      Occ : constant Src.Occurrences := URL.Lookup (Form, Name);
      Res : constant Src.Scalar_Resolution :=
        Src.Resolve_Scalar
          (Occ, Duplicates => Use_First, On_Empty => Allow_And_Decode);
   begin
      if Res.State = Src.Resolved_Value or else Res.State = Src.Resolved_Empty
      then
         return Src.Value (Occ, Res.Index);
      else
         return "";
      end if;
   end Field;

   function Parse_Bool (Value : String) return Boolean is
     (Value = "true" or else Value = "1" or else Value = "yes");

   function Bind (Request : Web.Request.Request_Type) return Project_Form is
      Body_Content : constant String := Web.Request.Request_Body (Request);
      Stream       : Mem.Memory_Stream := Mem.Create (Body_Content);
      Form         : URL.Form_Source;
      Outcome      : URL.Parse_Outcome;
      Result       : Project_Form;
   begin
      URL.Parse (Stream, Form, Outcome, URL.Default_Config);
      if Outcome /= URL.Parsed then
         Result.Decoded := False;
         return Result;
      end if;

      Result.Name              := To_Unbounded_String (Field (Form, "name"));
      Result.Status            := To_Unbounded_String (Field (Form, "status"));
      Result.Project_Type      := To_Unbounded_String (Field (Form, "project_type"));
      Result.Functions         := To_Unbounded_String (Field (Form, "functions"));
      Result.Has_Project_Tools := Parse_Bool (Field (Form, "has_project_tools"));
      Result.Has_GNAT          := Parse_Bool (Field (Form, "has_gnat"));
      Result.Has_GitHub        := Parse_Bool (Field (Form, "has_github"));
      Result.Has_Alire         := Parse_Bool (Field (Form, "has_alire"));
      return Result;
   end Bind;

end App.Project_Binding;
