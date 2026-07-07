with Templates.Values;

--  Thin template façade used by example pages and components.
package App.Templates is
   --  Render a raw template file with the provided context.
   --  Render a template file from example_app/templates.
   --  @param File_Name Template file name.
   --  @param Context Template context.
   --  @return Rendered HTML text.
   function Render
     (File_Name : String;
      Context   : Standard.Templates.Values.Value) return String;

   --  Replace a marker in rendered HTML owned by the app.
   --  Replace a marker in rendered application-owned HTML.
   --  @param Source Rendered source HTML.
   --  @param Marker Marker text to replace.
   --  @param Replacement Replacement HTML.
   --  @return Source with the first marker replaced.
   function Replace_Marker
     (Source      : String;
      Marker      : String;
      Replacement : String) return String;

   --  Build the current todo list fragment from persisted todos.
   --  Render persisted todo items using the todo item template.
   --  @return Rendered todo item HTML.
   function Render_Todo_Items return String;
end App.Templates;
