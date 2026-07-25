with Web.Binding;
with Web.Binding.Paths;
with Web.Binding.Codecs.URL_Encoded;
with Web.Binding.Sources;
with Web.Binding.Streams.Memory;
with Web.Binding.Policies;
with Web.Binding.Decoders.Integer_Decoders;

package body App.Project_Binding is

   package URL renames Web.Binding.Codecs.URL_Encoded;
   package Src renames Web.Binding.Sources;
   package Mem renames Web.Binding.Streams.Memory;
   package BP renames Web.Binding.Paths;
   use Web.Binding.Policies;
   use type URL.Parse_Outcome;
   use type Src.Resolution_State;

   package Int_Dec is new Web.Binding.Decoders.Integer_Decoders (Integer);

   --  Parse the request body as an urlencoded form. Ok is False on a codec
   --  failure (too many fields / oversized).
   procedure Parse_Body
     (Request : Web.Request.Request_Type;
      Form    : out URL.Form_Source;
      Ok      : out Boolean)
   is
      Body_Content : constant String := Web.Request.Request_Body (Request);
      Stream       : Mem.Memory_Stream := Mem.Create (Body_Content);
      Outcome      : URL.Parse_Outcome;
   begin
      URL.Parse (Stream, Form, Outcome, URL.Default_Config);
      Ok := Outcome = URL.Parsed;
   end Parse_Body;

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
      Form   : URL.Form_Source;
      Ok     : Boolean;
      Result : Project_Form;
   begin
      Parse_Body (Request, Form, Ok);
      if not Ok then
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

   Id_Path : constant BP.Field_Path :=
     BP.Append_Field (BP.Rooted (Web.Binding.URL_Encoded_Field), "id");

   function Bind_Delete (Request : Web.Request.Request_Type) return Delete_Form is
      Form   : URL.Form_Source;
      Ok     : Boolean;
      Result : Delete_Form;
   begin
      Parse_Body (Request, Form, Ok);
      if not Ok then
         Result.Decoded := False;
         return Result;
      end if;

      declare
         Id_Text : constant String := Field (Form, "id");
         Decoded : constant Int_Dec.Results.Result :=
           Int_Dec.Decode (Id_Text, Id_Path, Web.Binding.URL_Encoded_Field);
      begin
         if Id_Text = "" or else not Int_Dec.Results.Succeeded (Decoded) then
            Result.Decoded := False;
         else
            Result.Id := Int_Dec.Results.Value_Of (Decoded);
         end if;
      end;
      return Result;
   end Bind_Delete;

end App.Project_Binding;
