with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Strings.Unbounded.Text_IO;
with Ada.Text_IO;
with App.Store;
with Templates;

package body App.Templates is
   use Ada.Strings.Unbounded;

   Template_Root : constant String := "example_app/templates";

   function Template_Path (File_Name : String) return String is
   begin
      --  Prefer repository-root paths used by the CLI and tests.
      if Ada.Directories.Exists (Template_Root) then
         return Template_Root & "/" & File_Name;
      end if;

      return "templates/" & File_Name;
   end Template_Path;

   function Read_Template (File_Name : String) return String is
      File   : Ada.Text_IO.File_Type;
      Result : Unbounded_String;
   begin
      --  Read entire file to preserve template formatting exactly.
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Template_Path (File_Name));

      while not Ada.Text_IO.End_Of_File (File) loop
         Append (Result, Ada.Strings.Unbounded.Text_IO.Get_Line (File));
         if not Ada.Text_IO.End_Of_File (File) then
            Append (Result, ASCII.LF);
         end if;
      end loop;

      Ada.Text_IO.Close (File);
      return To_String (Result);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Read_Template;

   function Render
     (File_Name : String;
      Context   : Standard.Templates.Values.Value) return String
   is
      Template_Item : constant Standard.Templates.Template :=
        Standard.Templates.Parse (Read_Template (File_Name));
   begin
      --  Parse/compile each request path into an in-memory template object.
      return Standard.Templates.Render (Template_Item, Context);
   end Render;

   function Replace_Marker
     (Source      : String;
      Marker      : String;
      Replacement : String) return String
   is
      Position : constant Natural := Ada.Strings.Fixed.Index (Source, Marker);
   begin
      --  If marker missing, return source unchanged to avoid partial failures.
      if Position = 0 then
         return Source;
      end if;

      --  Replace first occurrence only; application templates are authored with
      --  single marker instances for stable fragment injection.
      return Source (Source'First .. Position - 1)
        & Replacement
        & Source (Position + Marker'Length .. Source'Last);
   end Replace_Marker;

   function Render_Todo_Items return String is
      use Standard.Templates.Values;

      Result : Unbounded_String;
      Context : Value;
      Items   : constant App.Store.Todo_Vectors.Vector := App.Store.Todos;
   begin
      --  Empty collection path is explicit to avoid blank fragment rendering.
      if Items.Is_Empty then
         return "<li class=""todo-empty"">No todos yet.</li>";
      end if;

      --  Build todo list as concatenated fragments, one item per stored row.
      for Title of Items loop
         Context := Object;
         Set (Context, "title", String_Item (Title));
         Append (Result, Render ("todo-item.html", Context));
      end loop;

      return To_String (Result);
   end Render_Todo_Items;
end App.Templates;
