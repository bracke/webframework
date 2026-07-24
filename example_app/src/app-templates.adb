with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Strings.UTF_Encoding.Wide_Strings;
with Ada.Strings.Unbounded.Text_IO;
with Ada.Text_IO;
with App.Store;
with Templates;

package body App.Templates is
   use Ada.Strings.Fixed;
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

   --  Replace asset markers with versioned URLs
   function Replace_Asset_Urls
     (Html    : String;
      Css_Url : String;
      Js_Url  : String) return String
   is
      Result : Unbounded_String := To_Unbounded_String (Html);
      DQ : constant Character := Character'Val (34); --  Double quote

      --  CSS link pattern: <link rel="stylesheet" href="/static/style.css">
      Css_Pattern : constant String :=
        "<link rel=" & DQ & "stylesheet" & DQ & " href=" & DQ & "/static/style.css" & DQ & ">";
      Css_Replacement : constant String :=
        "<link rel=" & DQ & "stylesheet" & DQ & " href=" & DQ & Css_Url & DQ & ">";

      --  JS script pattern: <script src="/static/webframework.js"></script>
      Js_Pattern : constant String :=
        "<script src=" & DQ & "/static/webframework.js" & DQ & "></script>";
      Js_Replacement : constant String :=
        "<script src=" & DQ & Js_Url & DQ & "></script>";
   begin
      --  Replace CSS URL
      declare
         Css_Index : constant Natural := Index (To_String (Result), Css_Pattern);
      begin
         if Css_Index > 0 then
            Replace_Slice (Result, Css_Index, Css_Index + Css_Pattern'Length - 1, Css_Replacement);
         end if;
      end;

      --  Replace JS URL
      declare
         Js_Index : constant Natural := Index (To_String (Result), Js_Pattern);
      begin
         if Js_Index > 0 then
            Replace_Slice (Result, Js_Index, Js_Index + Js_Pattern'Length - 1, Js_Replacement);
         end if;
      end;

      return To_String (Result);
   end Replace_Asset_Urls;

   --  Helper function to trim trailing spaces from strings
   function Trim_Spaces (Text : String) return String is
      Last_Non_Space : Natural := Text'Last;
   begin
      --  Find last non-space character
      while Last_Non_Space >= Text'First and then Text (Last_Non_Space) = ' ' loop
         Last_Non_Space := Last_Non_Space - 1;
      end loop;

      if Last_Non_Space < Text'First then
         return "";
      else
         return Text (Text'First .. Last_Non_Space);
      end if;
   end Trim_Spaces;

   --  Render projects table from projects data
   function Render_Projects_Table
     (Projects : App.Projects.Project_Vectors.Vector) return String
   is
      use Standard.Templates.Values;
      use App.Projects;

      Template : constant String := Read_Template ("projects.html");
      Context : Value := Object;

      --  Build the projects table rows
      Projects_Html : Unbounded_String;

      --  Helper function to get boolean display
      --  The page is served as UTF-8, so these must be the encoded bytes. Under
      --  -gnatW8 a String literal holds decoded code points, and U+2713 does not
      --  fit Standard.Character -- encode from a Wide_String instead.
      function Bool_To_String (Value : Boolean) return String is
      begin
         if Value then
            return Ada.Strings.UTF_Encoding.Wide_Strings.Encode ("✓");
         else
            return Ada.Strings.UTF_Encoding.Wide_Strings.Encode ("✗");
         end if;
      end Bool_To_String;

      --  Helper function to convert Natural to clean String (without leading space)
      function Nat_Image (Value : Natural) return String is
         Img : constant String := Natural'Image (Value);
      begin
         if Img'Length > 0 and then Img (Img'First) = ' ' then
            return Img (Img'First + 1 .. Img'Last);
         end if;
         return Img;
      end Nat_Image;

      DQ : constant Character := Character'Val (34); --  Double quote
   begin
      --  If no projects, return empty table with message
      if Projects.Is_Empty then
         Set (Context, "projects_loop",
              String_Item ("<tr><td colspan=" & DQ & "9" & DQ & ">No projects found.</td></tr>"));
         return Standard.Templates.Render (Standard.Templates.Parse (Template), Context);
      end if;

      --  Build table rows for each project
      for Project of Projects loop
         Ada.Strings.Unbounded.Append (Projects_Html, "<tr data-project-id=" & DQ &
                 Nat_Image (Project.Id) & DQ & ">");
         Ada.Strings.Unbounded.Append (Projects_Html, "<td>" & Trim_Spaces (Project.Name) & "</td>");
         Ada.Strings.Unbounded.Append (Projects_Html, "<td>" & Trim_Spaces (Project.Status) & "</td>");
         Ada.Strings.Unbounded.Append (Projects_Html, "<td>" & Trim_Spaces (Project.Project_Type) & "</td>");
         Ada.Strings.Unbounded.Append (Projects_Html, "<td>" & Trim_Spaces (Project.Functions) & "</td>");
         Ada.Strings.Unbounded.Append (Projects_Html, "<td class=" & DQ & "bool-cell" & DQ & ">" &
                 Bool_To_String (Project.Has_Project_Tools) & "</td>");
         Ada.Strings.Unbounded.Append (Projects_Html, "<td class=" & DQ & "bool-cell" & DQ & ">" &
                 Bool_To_String (Project.Has_GNAT) & "</td>");
         Ada.Strings.Unbounded.Append (Projects_Html, "<td class=" & DQ & "bool-cell" & DQ & ">" &
                 Bool_To_String (Project.Has_GitHub) & "</td>");
         Ada.Strings.Unbounded.Append (Projects_Html, "<td class=" & DQ & "bool-cell" & DQ & ">" &
                 Bool_To_String (Project.Has_Alire) & "</td>");
         --  Add actions column with delete button
         Ada.Strings.Unbounded.Append (Projects_Html, "<td class=" & DQ & "actions-cell" & DQ & ">" &
                 "<button class=" & DQ & "delete-btn" & DQ & " onclick=" & DQ & "deleteProject(" &
                 Nat_Image (Project.Id) & ")" & DQ & ">Delete</button>" &
                 "</td>");
         Ada.Strings.Unbounded.Append (Projects_Html, "</tr>");
      end loop;

      --  Replace the marker with the actual projects HTML
      return Replace_Marker (Template, "<!-- PROJECTS_TABLE_ROWS -->", To_String (Projects_Html));

      --  Alternative approach: use the template system properly
      --  This would require a more complex template structure
      --  For now, the manual HTML building approach above works
   exception
      when others =>
         --  Fallback to simple message if rendering fails
         return "<div class=" & DQ & "panel" & DQ & ">" &
                "<h1>Projects</h1>" &
                "<p>Error rendering projects table.</p>" &
                "</div>";
   end Render_Projects_Table;

end App.Templates;
