with Ada.Strings.Unbounded;
with Ada.Exceptions;
with App.Runtime;
with App.Templates;
with Templates.Values;
with Web.Html;
with Web.Server;
with Web.Logging;
with Web.Response;

package body App.Pages is
   use Ada.Strings.Unbounded;

   function Home_Content return String is
      use Standard.Templates.Values;

      Home_Context    : Value := Object;
      Counter_Context : Value := Object;
      Content         : Unbounded_String;
      Todo_Content    : Unbounded_String;
   begin
      --  Build fragment contexts in a single render pass to keep output stable.
      Set (Home_Context, "title", String_Item ("Ada Webframework Example"));
      Set (Counter_Context, "counter", String_Item ("0"));

      --  Load the base page and compose each fragment in deterministic order.
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
      Context : Value := Object;
      Page    : Unbounded_String;
   begin
      --  Build the full HTML page through templates and inject the composed body fragment.
      Set (Context, "title", String_Item ("Ada Webframework Example"));
      Page := To_Unbounded_String (App.Templates.Render ("layout.html", Context));
      Page :=
        To_Unbounded_String
          (App.Templates.Replace_Marker
             (To_String (Page),
              "<!-- wf:body -->",
              Home_Content));

      --  Ensure cookie-backed session response is used for /, so websocket state is consistent.
      return App.Runtime.Html_Response (Request, To_String (Page));
      exception
         when Error : others =>
            --  Keep route stable and return explicit HTTP 500 on any rendering failure.
            Web.Logging.Error
              ("home route render failed: " & Ada.Exceptions.Exception_Message (Error));
         return Web.Response.Internal_Server_Error;
   end Home;

   function Health (Request : Web.Request.Request_Type) return Web.Response.Response_Type is
      pragma Unreferenced (Request);
   begin
      --  Health is intentionally delegated to framework helper for compatibility
      --  with orchestration and smoke checks.
      return Web.Server.Health_Response;
   end Health;

   function Error_Not_Found
     (Request : Web.Request.Request_Type;
      Status  : Positive;
      Detail  : String) return Web.Response.Response_Type
   is
      pragma Unreferenced (Status);
      pragma Unreferenced (Detail);
      Path : constant String := Web.Request.Path (Request);
      Escaped_Path : constant String :=
        Web.Html.Escape_Text ((if Path'Length = 0 then "/" else Path));
   begin
      return
        Web.Response.Html
          ("<!doctype html>"
           & "<html><head><title>Page not found</title></head>"
           & "<body><h1>Page not found</h1><p>Path: "
           & Escaped_Path
           & "</p></body></html>");
   end Error_Not_Found;

   function Error_Bad_Request
     (Request : Web.Request.Request_Type;
      Status  : Positive;
      Detail  : String) return Web.Response.Response_Type
   is
      pragma Unreferenced (Status);
      pragma Unreferenced (Request);
      Detail_Line : constant String :=
        (if Detail'Length = 0
         then ""
         else "<p>" & Web.Html.Escape_Text (Detail) & "</p>");
   begin
      return
        Web.Response.Html
          ("<!doctype html>"
           & "<html><head><title>Bad request</title></head>"
           & "<body><h1>Bad request</h1>" & Detail_Line & "</body></html>");
   end Error_Bad_Request;

   function Error_Server
     (Request : Web.Request.Request_Type;
      Status  : Positive;
      Detail  : String) return Web.Response.Response_Type
   is
      pragma Unreferenced (Request);
      pragma Unreferenced (Status);
      Detail_Line : constant String :=
        (if Detail'Length = 0
         then ""
         else "<p>" & Web.Html.Escape_Text (Detail) & "</p>");
   begin
      return
        Web.Response.Html
          ("<!doctype html>"
           & "<html><head><title>Server error</title></head>"
           & "<body><h1>Server error</h1>" & Detail_Line
           & "</body></html>");
   end Error_Server;
end App.Pages;
