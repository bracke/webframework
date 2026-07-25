with Ada.Strings.Unbounded;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with App.Auth;
with App.Authz;
with App.Projects;
with App.Project_Validation;
with Validation.Results;
with Web.Assets.Clients;
with App.Runtime;
with App.State;
with App.Templates;
with Templates.Values;
with Web.Html;
with Web.Server;
with Web.Logging;

package body App.Pages is
   use Ada.Strings.Unbounded;

   --  Generate navigation bar HTML with current path highlighted
   --  The active item is rendered as a span (not clickable) instead of a link
   function Generate_Nav_Bar (Current_Path : String) return String is
      Home_Active : constant Boolean := Current_Path = "/";
      Projects_Active : constant Boolean := Current_Path = "/projects";
      Todo_Active : constant Boolean := Current_Path = "/todo";
   begin
      return
        "<header><nav>" &
        (if Home_Active then "<span class=""nav-home active"">Home</span>"
         else "<a href=""/"" class=""nav-home"">Home</a>") &
        (if Projects_Active then "<span class=""nav-projects active"">Projects</span>"
         else "<a href=""/projects"" class=""nav-projects"">Projects</a>") &
        (if Todo_Active then "<span class=""nav-todo active"">Todos</span>"
         else "<a href=""/todo"" class=""nav-todo"">Todos</a>") &
        "<a href=""#"" class=""nav-logout"" onclick=""logout();return false;"">Logout</a>" &
        "</nav></header>" &
        "<script>" &
        "function logout(){fetch(" &
        "'/api/logout',{method:'POST',credentials:'include'})" &
        ".then(r=>{if(r.ok){window.location.href='/login'}})" &
        ".catch(e=>console.error('Logout failed:',e))}</script>";
   end Generate_Nav_Bar;

   function Home_Content return String is
      use Standard.Templates.Values;

      Home_Context    : Value := Object;
      Counter_Context : Value := Object;
      Content         : Unbounded_String;
   begin
      --  Build fragment contexts in a single render pass to keep output stable.
      Set (Home_Context, "title", String_Item ("Ada Webframework Example"));
      Set (Counter_Context, "counter", String_Item ("0"));

      --  Load the base page and compose each fragment in deterministic order.
      Content := To_Unbounded_String (App.Templates.Render ("home.html", Home_Context));
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

      return To_String (Content);
   end Home_Content;

   --  Type to hold authentication data for state updates
   type Auth_Data is record
      Principal : Unbounded_String;
      Username  : Unbounded_String;
      Clearance : Natural := 0;
      Token     : Unbounded_String;
   end record;

   --  Global variable to pass auth data to state processor
   --  Note: This is a temporary workaround. In a real application, use a better design.
   Current_Auth_Data : Auth_Data;

   function Home
     (Request : Web.Request.Request_Type;
      Context : Web.Context.Request_Context) return Web.Response.Response_Type is
      use Standard.Templates.Values;
      pragma Unreferenced (Context);
      View : Value := Object;
      Page : Unbounded_String;
   begin
      --  Access is decided by the route guard before this runs; the manual
      --  session check is gone.
      --  Build the full HTML page through templates and inject the composed body fragment.
      Set (View, "title", String_Item ("Ada Webframework Example"));
      Page := To_Unbounded_String (App.Templates.Render ("layout.html", View));

      --  Add navigation bar for authenticated pages
      declare
         Current_Path : constant String := Web.Request.Path (Request);
         Nav_Bar : constant String := Generate_Nav_Bar (Current_Path);
      begin
         --  Insert nav bar before the main content
         Page := To_Unbounded_String
           (App.Templates.Replace_Marker
              (To_String (Page),
               "<main>",
               Nav_Bar & "<main>"));
      end;

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

   --  State process for setting authentication
   procedure Set_Auth_Process (State : in out App.State.App_State) is
   begin
      App.State.Set_Authenticated
        (State, To_String (Current_Auth_Data.Principal),
         To_String (Current_Auth_Data.Username), Current_Auth_Data.Clearance,
         To_String (Current_Auth_Data.Token));
   end Set_Auth_Process;

   --  State process for clearing authentication
   procedure Clear_Auth_Process (State : in out App.State.App_State) is
   begin
      App.State.Clear_Authentication (State);
   end Clear_Auth_Process;

   --  Extraction channel for reading the session token out of state at logout.
   Logout_Token : Unbounded_String;
   procedure Read_Token_Process (State : in out App.State.App_State) is
   begin
      Logout_Token := To_Unbounded_String (App.State.Get_Session_Token (State));
   end Read_Token_Process;

   --  Parse form data from request content (application/x-www-form-urlencoded)
   procedure Parse_Form_Data
     (Content : String;
      Username : out Unbounded_String;
      Password : out Unbounded_String) is
   begin
      Username := To_Unbounded_String ("");
      Password := To_Unbounded_String ("");

      --  Simple parsing for username=value&password=value
      declare
         Username_Start : constant Natural := Ada.Strings.Fixed.Index (Content, "username=") + 9;
         Username_End : Natural;
         Password_Start : constant Natural := Ada.Strings.Fixed.Index (Content, "password=") + 9;
      begin
         if Username_Start > 9 and then Username_Start <= Content'Last then
            Username_End := Ada.Strings.Fixed.Index (Content, "&", Username_Start);
            if Username_End = 0 then
               Username_End := Content'Last + 1;
            end if;
            Username := To_Unbounded_String (Content (Username_Start .. Username_End - 1));
         end if;

         if Password_Start > 9 and then Password_Start <= Content'Last then
            declare
               Password_End : Natural := Ada.Strings.Fixed.Index (Content, "&", Password_Start);
            begin
               if Password_End = 0 then
                  Password_End := Content'Last + 1;
               end if;
               Password := To_Unbounded_String (Content (Password_Start .. Password_End - 1));
            end;
         end if;
      end;
   end Parse_Form_Data;

   --  Render the login page with the login form template.
   function Login (Request : Web.Request.Request_Type) return Web.Response.Response_Type is
      Context : Standard.Templates.Values.Value := Standard.Templates.Values.Object;
      Page    : Unbounded_String;
   begin
      --  Build the full HTML page through templates and inject the login form.
      Standard.Templates.Values.Set
        (Context, "title", Standard.Templates.Values.String_Item ("Login - Ada Webframework Example"));
      Page := To_Unbounded_String (App.Templates.Render ("layout.html", Context));
      Page := To_Unbounded_String
        (App.Templates.Replace_Marker
           (To_String (Page),
            "<!-- wf:body -->",
            App.Templates.Render ("login.html", Standard.Templates.Values.Object)));

      --  Return HTML response with session cookie
      return App.Runtime.Html_Response (Request, To_String (Page));
      exception
         when Error : others =>
            Web.Logging.Error
              ("login route render failed: " & Ada.Exceptions.Exception_Message (Error));
            return Web.Response.Internal_Server_Error;
   end Login;

   --  Handle login API endpoint.
   function Api_Login (Request : Web.Request.Request_Type) return Web.Response.Response_Type is
      Body_Content : constant String := Web.Request.Request_Body (Request);
      Username : Unbounded_String;
      Password : Unbounded_String;
      Session_Id : constant String := App.Runtime.Find_Or_Create_Session (Request);
   begin
      --  Parse username and password from form data
      Parse_Form_Data (Body_Content, Username, Password);

      if Length (Username) = 0 or else Length (Password) = 0 then
         return Web.Response.Bad_Request ("Username and password are required");
      end if;

      --  Authenticate through the identity-backed credential store, which
      --  returns the caller's authorization principal id on success.
      declare
         Principal : constant String :=
           App.Auth.Authenticate (To_String (Username), To_String (Password));
      begin
         if Principal /= "" then
            --  Rotate the session id on this privilege change to defeat session
            --  fixation, then record the principal in the rotated session.
            declare
               Rotated : constant String :=
                 App.Runtime.Regenerate_Session (Session_Id);
               Effective : constant String :=
                 (if Rotated /= "" then Rotated else Session_Id);
               --  Open an identity session; its token is validated against the
               --  identity repository on every subsequent request.
               Token : constant String := App.Auth.Create_Session (Principal);
            begin
               Current_Auth_Data :=
                 Auth_Data'(Principal => To_Unbounded_String (Principal),
                            Username  => Username,
                            Clearance => App.Auth.Clearance_Of (Principal),
                            Token     => To_Unbounded_String (Token));
               App.Runtime.With_State (Effective, Set_Auth_Process'Access);
               return App.Runtime.Html_Response
                 (Effective, "{""status"": ""success""}");
            end;
         else
            return Web.Response.Create
              (401, "Invalid username or password", "text/plain; charset=utf-8");
         end if;
      end;
      exception
         when Error : others =>
            Web.Logging.Error
              ("login API failed: " & Ada.Exceptions.Exception_Message (Error));
            return Web.Response.Internal_Server_Error;
   end Api_Login;

   --  Handle logout API endpoint.
   function Api_Logout (Request : Web.Request.Request_Type) return Web.Response.Response_Type is
      Session_Id : constant String := App.Runtime.Require_Session (Request);
   begin
      if Session_Id'Length > 0 then
         --  Revoke the identity session (so its token can never be replayed),
         --  clear the auth fields, then invalidate the framework session.
         Logout_Token := Null_Unbounded_String;
         App.Runtime.With_State (Session_Id, Read_Token_Process'Access);
         if Length (Logout_Token) > 0 then
            App.Auth.Revoke_Session (To_String (Logout_Token));
         end if;
         App.Runtime.With_State (Session_Id, Clear_Auth_Process'Access);
         App.Runtime.Invalidate_Session (Session_Id);
      end if;

      --  Return success response
      return App.Runtime.Html_Response (Session_Id, "{""status"": ""success""}");
      exception
         when Error : others =>
            Web.Logging.Error
              ("logout API failed: " & Ada.Exceptions.Exception_Message (Error));
            return Web.Response.Internal_Server_Error;
   end Api_Logout;

   --  Safely read the clearance an upstream guard attached to the context.
   function Context_Clearance
     (Context : Web.Context.Request_Context) return Natural is
   begin
      return Natural'Value (Web.Context.Attribute (Context, "clearance"));
   exception
      when others =>
         return 0;
   end Context_Clearance;

   function Projects
     (Request : Web.Request.Request_Type;
      Context : Web.Context.Request_Context) return Web.Response.Response_Type is
      use Standard.Templates.Values;
      --  Access is already decided by the route guards (Resolve_Principal then
      --  Require_App_Access); an unauthenticated or unauthorized caller never
      --  reaches this handler, so the manual session check is gone.
      --
      --  The listing itself is planned through tables from the same principal
      --  and clearance: the plan governs which columns show and carries the
      --  authorization scope, rather than the handler dumping every row/column.
      Plan : constant App.Authz.Listing_Plan :=
        App.Authz.Plan_Projects_Listing
          (Web.Context.Principal (Context), Context_Clearance (Context));
      View : Value := Object;
      Page : Unbounded_String;
      Projects_Data : App.Projects.Project_Vectors.Vector;
      Total_Rows : Natural := 0;
   begin
      --  Fail closed: if tables could not produce a ready plan, do not list.
      if not Plan.Ready then
         return Web.Response.Forbidden;
      end if;

      --  Enforce the authorization data scope in the query itself (the backend
      --  adapter role): the displayed rows come straight from a scoped query, so
      --  out-of-scope rows are never fetched. The unscoped total is read only to
      --  report how many rows the scope excludes.
      Projects_Data := App.Projects.Get_Projects (Alire_Only => Plan.Restrict_To_Alire);
      Total_Rows :=
        (if Plan.Restrict_To_Alire
         then Natural (App.Projects.Get_Projects.Length)
         else Natural (Projects_Data.Length));

      Set (View, "title", String_Item ("Projects - Ada Webframework Example"));
      Page := To_Unbounded_String (App.Templates.Render ("layout.html", View));

      --  Add navigation bar for authenticated pages
      declare
         Current_Path : constant String := Web.Request.Path (Request);
         Nav_Bar : constant String := Generate_Nav_Bar (Current_Path);
      begin
         --  Insert nav bar before the main content
         Page := To_Unbounded_String
           (App.Templates.Replace_Marker
              (To_String (Page),
               "<main>",
               Nav_Bar & "<main>"));
      end;

      --  Replace body content with the projects table, rendered under the plan.
      Page := To_Unbounded_String
        (App.Templates.Replace_Marker
           (To_String (Page),
            "<!-- wf:body -->",
            App.Templates.Render_Projects_Table
              (Projects_Data,
               Scope_Applied      => Plan.Scope_Applied,
               Mask_Functions     => Plan.Mask_Functions,
               Authorized_Columns => Plan.Authorized_Columns,
               Total_Rows         => Total_Rows)));

      --  Replace asset URLs with versioned URLs for cache busting
      Page := To_Unbounded_String
        (App.Templates.Replace_Asset_Urls
           (To_String (Page),
            Web.Assets.Clients.Css_Url,
            Web.Assets.Clients.Js_Url));

      --  Ensure cookie-backed session response is used for /projects
      return App.Runtime.Html_Response (Request, To_String (Page));
      exception
         when Error : others =>
            --  Keep route stable and return explicit HTTP 500 on any rendering failure.
            Web.Logging.Error
              ("projects route render failed: " & Ada.Exceptions.Exception_Message (Error));
         return Web.Response.Internal_Server_Error;
   end Projects;

   --  Render the todo page
   function Todo
     (Request : Web.Request.Request_Type;
      Context : Web.Context.Request_Context) return Web.Response.Response_Type is
      use Standard.Templates.Values;
      pragma Unreferenced (Context);
      View : Value := Object;
      Page : Unbounded_String;
      Todo_Content : Unbounded_String;
   begin
      --  Access is decided by the route guard before this runs.
      --  Build the full HTML page through templates
      Set (View, "title", String_Item ("Todos - Ada Webframework Example"));
      Page := To_Unbounded_String (App.Templates.Render ("layout.html", View));

      --  Add navigation bar for authenticated pages
      declare
         Current_Path : constant String := Web.Request.Path (Request);
         Nav_Bar : constant String := Generate_Nav_Bar (Current_Path);
      begin
         --  Insert nav bar before the main content
         Page := To_Unbounded_String
           (App.Templates.Replace_Marker
              (To_String (Page),
               "<main>",
               Nav_Bar & "<main>"));
      end;

      --  Render todo content
      Todo_Content := To_Unbounded_String
        (App.Templates.Replace_Marker
           (App.Templates.Render ("todo.html", Object),
            "<!-- wf:todos -->",
            App.Templates.Render_Todo_Items));

      --  Inject todo content into body
      Page := To_Unbounded_String
        (App.Templates.Replace_Marker
           (To_String (Page),
            "<!-- wf:body -->",
            To_String (Todo_Content)));

      --  Replace asset URLs with versioned URLs for cache busting
      Page := To_Unbounded_String
        (App.Templates.Replace_Asset_Urls
           (To_String (Page),
            Web.Assets.Clients.Css_Url,
            Web.Assets.Clients.Js_Url));

      --  Ensure cookie-backed session response is used for /todo
      return App.Runtime.Html_Response (Request, To_String (Page));
      exception
         when Error : others =>
            --  Keep route stable and return explicit HTTP 500 on any rendering failure.
            Web.Logging.Error
              ("todo route render failed: " & Ada.Exceptions.Exception_Message (Error));
         return Web.Response.Internal_Server_Error;
   end Todo;

   --  API endpoint to add a new project
   function Api_Add_Project
     (Request : Web.Request.Request_Type;
      Context : Web.Context.Request_Context) return Web.Response.Response_Type is
      use App.Projects;
      pragma Unreferenced (Context);
      Body_Content : constant String := Web.Request.Request_Body (Request);
   begin
      --  Authorization is enforced by the route guard before this runs.
      --  Parse form data from request body
      --  Expected format: name=...&status=...&project_type=...&functions=...&
      --                  has_project_tools=true/false&has_gnat=true/false&...
      declare
         Name_Start : constant Natural := Ada.Strings.Fixed.Index (Body_Content, "name=") + 5;
         Status_Start : constant Natural := Ada.Strings.Fixed.Index (Body_Content, "status=") + 7;
         Type_Start : constant Natural := Ada.Strings.Fixed.Index (Body_Content, "project_type=") + 13;
         Functions_Start : constant Natural := Ada.Strings.Fixed.Index (Body_Content, "functions=") + 10;
         Tools_Start : constant Natural := Ada.Strings.Fixed.Index (Body_Content, "has_project_tools=") + 18;
         Gnat_Start : constant Natural := Ada.Strings.Fixed.Index (Body_Content, "has_gnat=") + 9;
         Github_Start : constant Natural := Ada.Strings.Fixed.Index (Body_Content, "has_github=") + 11;
         Alire_Start : constant Natural := Ada.Strings.Fixed.Index (Body_Content, "has_alire=") + 10;

         function Extract_Value (Start : Natural; Content : String) return String is
            End_Pos : Natural;
         begin
            if Start = 0 or else Start > Content'Last then
               return "";
            end if;
            End_Pos := Ada.Strings.Fixed.Index (Content, "&", Start);
            if End_Pos = 0 then
               End_Pos := Content'Last + 1;
            end if;
            return Content (Start .. End_Pos - 1);
         end Extract_Value;

         function Parse_Bool (Value : String) return Boolean is
         begin
            return Value = "true" or else Value = "1" or else Value = "yes";
         end Parse_Bool;

         Name : constant String := Extract_Value (Name_Start, Body_Content);
         Status : constant String := Extract_Value (Status_Start, Body_Content);
         Project_Type : constant String := Extract_Value (Type_Start, Body_Content);
         Functions : constant String := Extract_Value (Functions_Start, Body_Content);
         Has_Project_Tools : constant Boolean := Parse_Bool (Extract_Value (Tools_Start, Body_Content));
         Has_GNAT : constant Boolean := Parse_Bool (Extract_Value (Gnat_Start, Body_Content));
         Has_GitHub : constant Boolean := Parse_Bool (Extract_Value (Github_Start, Body_Content));
         Has_Alire : constant Boolean := Parse_Bool (Extract_Value (Alire_Start, Body_Content));

         --  Decode -> validate: feed the typed fields to the Validation library
         --  before touching the database.
         Input : constant App.Project_Validation.Project_Input :=
           (Name         => To_Unbounded_String (Name),
            Status       => To_Unbounded_String (Status),
            Project_Type => To_Unbounded_String (Project_Type),
            Functions    => To_Unbounded_String (Functions));
         Check : constant Validation.Results.Result :=
           App.Project_Validation.Validate (Input);
      begin
         --  Reject invalid input with the structured issues as JSON.
         if Validation.Results.Has_Errors (Check) then
            return Web.Response.Create
              (400, App.Project_Validation.Error_JSON (Check),
               "application/json; charset=utf-8");
         end if;

         --  Add project to database
         Add_Project
           (Name        => Name,
            Status      => Status,
            Project_Type => Project_Type,
            Functions   => Functions,
            Has_Project_Tools => Has_Project_Tools,
            Has_GNAT        => Has_GNAT,
            Has_GitHub      => Has_GitHub,
            Has_Alire       => Has_Alire);

         return Web.Response.Create
           (200, "{""status"": ""success""}", "application/json; charset=utf-8");
      end;
      exception
         when Error : others =>
            Web.Logging.Error
              ("add project API failed: " & Ada.Exceptions.Exception_Message (Error));
            return Web.Response.Internal_Server_Error;
   end Api_Add_Project;

   --  API endpoint to delete a project
   function Api_Delete_Project
     (Request : Web.Request.Request_Type;
      Context : Web.Context.Request_Context) return Web.Response.Response_Type is
      use App.Projects;
      pragma Unreferenced (Context);
      Body_Content : constant String := Web.Request.Request_Body (Request);
   begin
      --  Authorization is enforced by the route guard before this runs.
      --  Parse project ID from request body (format: id=123)
      declare
         Id_Start : constant Natural := Ada.Strings.Fixed.Index (Body_Content, "id=") + 3;

         function Extract_Id return Natural is
            End_Pos : Natural;
         begin
            if Id_Start = 0 or else Id_Start > Body_Content'Last then
               return 0;
            end if;
            End_Pos := Ada.Strings.Fixed.Index (Body_Content, "&", Id_Start);
            if End_Pos = 0 then
               End_Pos := Body_Content'Last + 1;
            end if;
            return Natural'Value (Body_Content (Id_Start .. End_Pos - 1));
         end Extract_Id;

         Project_Id : constant Natural := Extract_Id;
      begin
         if Project_Id = 0 then
            return Web.Response.Bad_Request ("Invalid project ID");
         end if;

         --  Delete project from database
         Delete_Project (Project_Id);

         return Web.Response.Create
           (200, "{""status"": ""success""}", "application/json; charset=utf-8");
      end;
      exception
         when Constraint_Error =>
            return Web.Response.Bad_Request ("Invalid project ID");
         when Error : others =>
            Web.Logging.Error
              ("delete project API failed: " & Ada.Exceptions.Exception_Message (Error));
            return Web.Response.Internal_Server_Error;
   end Api_Delete_Project;

end App.Pages;
