with Ada.Strings.Unbounded;
with App.Live;
with App.Templates;
with Templates.Values;

package body App.Pages is
   use Ada.Strings.Unbounded;

   function Home_Content return String is
      use Standard.Templates.Values;

      Home_Context    : Value := Object;
      Counter_Context : Value := Object;
      Content         : Unbounded_String;
      Todo_Content    : Unbounded_String;
   begin
      Set (Home_Context, "title", String_Item ("Ada Webframework Example"));
      Set (Counter_Context, "counter", String_Item ("0"));

      Content := To_Unbounded_String (App.Templates.Render ("home.html", Home_Context));
      Todo_Content :=
        To_Unbounded_String
          (App.Templates.Replace_Marker
             (App.Templates.Render ("todo.html", Object),
              "<!-- wf:todos -->",
              App.Templates.Render_Todo_Items));
      Content :=
        To_Unbounded_String
          (App.Templates.Replace_Marker
             (To_String (Content),
              "<!-- wf:counter -->",
              App.Templates.Render ("counter.html", Counter_Context)));
      Content :=
        To_Unbounded_String
          (App.Templates.Replace_Marker
             (To_String (Content),
              "<!-- wf:profile -->",
              App.Templates.Render ("profile.html", Object)));
      Content :=
        To_Unbounded_String
          (App.Templates.Replace_Marker
             (To_String (Content),
              "<!-- wf:todo -->",
              To_String (Todo_Content)));

      return To_String (Content);
   end Home_Content;

   function Home (Request : Web.Request.Request_Type) return Web.Response.Response_Type is
      use Standard.Templates.Values;
      Session : constant String := App.Live.Find_Or_Create_Session (Request);
      Context : Value := Object;
      Page    : Unbounded_String;
   begin
      Set (Context, "title", String_Item ("Ada Webframework Example"));
      Page := To_Unbounded_String (App.Templates.Render ("layout.html", Context));
      Page :=
        To_Unbounded_String
          (App.Templates.Replace_Marker
             (To_String (Page),
              "<!-- wf:body -->",
              Home_Content));
      return App.Live.Html_Response (Session, To_String (Page));
   end Home;
end App.Pages;
