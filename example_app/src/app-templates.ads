with Templates.Values;

package App.Templates is
   --  Render a template file from example_app/templates.
   --  @param File_Name Template file name.
   --  @param Context Template context.
   --  @return Rendered HTML text.
   function Render
     (File_Name : String;
      Context   : Standard.Templates.Values.Value) return String;

   --  Replace a marker in rendered application-owned HTML.
   --  @param Source Rendered source HTML.
   --  @param Marker Marker text to replace.
   --  @param Replacement Replacement HTML.
   --  @return Source with the first marker replaced.
   function Replace_Marker
     (Source      : String;
      Marker      : String;
      Replacement : String) return String;

   --  Render persisted todo items using the todo item template.
   --  @return Rendered todo item HTML.
   function Render_Todo_Items return String;
end App.Templates;
