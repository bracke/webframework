with Ada.Strings.Unbounded;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with App.Auth;
with App.Authz;
with App.Projects;
with App.Attachments;
with App.Notifications;
with App.Smtp_Catcher;
with App.Project_Binding;
with Web.Multipart;
with App.Project_Validation;
with App.Login_Validation;
with Validation.Results;
with Web.Assets.Clients;
with App.Runtime;
with App.State;
with App.Csrf;
with App.Nav;
with App.Templates;
with Templates.Values;
with Web.Html;
with Web.Server;
with Web.Logging;
with Webfiles;
with Webframework_Forms;
with Forms.Submission;
with Forms.Urlencoded;

package body App.Pages is
   use Ada.Strings.Unbounded;
   use type Forms.Urlencoded.Decode_Status;

   --  The viewer clearance carried on the request context ("clearance" fact),
   --  or 0 if none. Drives the navigation visibility filter.
   function Clearance_Of (Context : Web.Context.Request_Context) return Natural is
   begin
      if Web.Context.Has_Attribute (Context, "clearance") then
         return Natural'Value (Web.Context.Attribute (Context, "clearance"));
      end if;
      return 0;
   exception
      when others =>
         return 0;
   end Clearance_Of;

   --  API response contract. Every JSON endpoint returns exactly one of:
   --    * {"status":"success"}                          (Api_Success)
   --    * {"status":"error","message":"..."}            (Api_Error)
   --    * {"status":"error","issues":[...]}             (validation, Error_JSON)
   --  -- one "status" discriminator across all of them. Message must be a
   --  JSON-safe literal (no quotes/backslashes); user-influenced text is only
   --  ever emitted through Error_JSON, which escapes it.
   Json_Content_Type : constant String := "application/json; charset=utf-8";
   Success_Body      : constant String := "{""status"":""success""}";

   function Api_Error
     (Status : Positive; Message : String) return Web.Response.Response_Type is
     (Web.Response.Create
        (Status,
         "{""status"":""error"",""message"":""" & Message & """}",
         Json_Content_Type));

   function Api_Success return Web.Response.Response_Type is
     (Web.Response.Create (200, Success_Body, Json_Content_Type));

   --  A one-line context tag for API error logs, so a failure line names the
   --  route it came from (the framework logs request_id/method/path at the
   --  transport layer; this correlates the handler-level line to the route).
   function Log_Tag (Request : Web.Request.Request_Type) return String is
     (Web.Request.Method (Request) & " " & Web.Request.Path (Request) & ": ");

   --  The navigation bar: the menu (Home / Projects / To-Do) comes from the
   --  navigation library via App.Nav -- the active page highlighted from the
   --  path, items filtered by Clearance -- wrapped with a logout control (the
   --  logout POST carries the session-bound CSRF token).
   function Generate_Nav_Bar
     (Current_Path : String; Clearance : Natural) return String
   is
   begin
      return
        "<header><nav>" & App.Nav.Menu_Html (Current_Path, Clearance) &
        "<a href=""#"" class=""nav-logout"" onclick=""logout();return false;"">"
        & "Logout</a></nav></header>" &
        "<script>" &
        "function logout(){fetch('/api/logout',{method:'POST'," &
        "headers:{'Content-Type':'application/x-www-form-urlencoded'}," &
        "body:window.wfCsrfBody('')})" &
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

   function Home
     (Request : Web.Request.Request_Type;
      Context : Web.Context.Request_Context) return Web.Response.Response_Type is
      use Standard.Templates.Values;
      View : Value := Object;
      Page : Unbounded_String;
      --  Bind the CSRF token to the SAME session the response cookie will
      --  carry: resolve the session once, so a first (cookieless) visit does
      --  not mint one session for the token and another for the cookie.
      Session_Id : constant String := App.Runtime.Find_Or_Create_Session (Request);
   begin
      --  Access is decided by the route guard before this runs; the manual
      --  session check is gone.
      --  Build the full HTML page through templates and inject the composed body fragment.
      Set (View, "title", String_Item ("Ada Webframework Example"));
      Standard.Templates.Values.Set
        (View, "csrf_token",
         Standard.Templates.Values.String_Item
           (App.Csrf.Token (Session_Id)));
      Page := To_Unbounded_String (App.Templates.Render ("layout.html", View));

      --  Add navigation bar for authenticated pages
      declare
         Current_Path : constant String := Web.Request.Path (Request);
         Nav_Bar : constant String :=
           Generate_Nav_Bar (Current_Path, Clearance_Of (Context));
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
      return App.Runtime.Html_Response (Session_Id, To_String (Page));
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

   --  Session-state updates are done through visitors that carry their own
   --  per-call data in their fields (see Web.Live.State_Visitor). Concurrent
   --  requests each own a stack-local visitor, so nothing is shared -- unlike a
   --  module global written before With_State, which two logins would race on.

   --  Record the authenticated principal on the (rotated) session.
   type Auth_Applier is new App.Runtime.Live.State_Visitor with record
      Principal : Unbounded_String;
      Username  : Unbounded_String;
      Clearance : Natural := 0;
      Token     : Unbounded_String;
   end record;
   overriding procedure Apply
     (Self : in out Auth_Applier; State : in out App.State.App_State) is
   begin
      App.State.Set_Authenticated
        (State, To_String (Self.Principal), To_String (Self.Username),
         Self.Clearance, To_String (Self.Token));
   end Apply;

   --  Clear the auth fields (no per-call data).
   type Auth_Clearer is new App.Runtime.Live.State_Visitor with null record;
   overriding procedure Apply
     (Self : in out Auth_Clearer; State : in out App.State.App_State) is
      pragma Unreferenced (Self);
   begin
      App.State.Clear_Authentication (State);
   end Apply;

   --  Read the identity-session token out of state at logout, into the visitor.
   type Token_Reader is new App.Runtime.Live.State_Visitor with record
      Token : Unbounded_String;
   end record;
   overriding procedure Apply
     (Self : in out Token_Reader; State : in out App.State.App_State) is
   begin
      Self.Token := To_Unbounded_String (App.State.Get_Session_Token (State));
   end Apply;

   --  Parse form data from request content (application/x-www-form-urlencoded)
   --  Render the login page with the login form template.
   function Login (Request : Web.Request.Request_Type) return Web.Response.Response_Type is
      Context : Standard.Templates.Values.Value := Standard.Templates.Values.Object;
      Page    : Unbounded_String;
      --  One session for both the embedded token and the response cookie, so a
      --  first (cookieless) visit does not fail its own CSRF check on submit.
      Session_Id : constant String := App.Runtime.Find_Or_Create_Session (Request);
   begin
      --  Build the full HTML page through templates and inject the login form.
      Standard.Templates.Values.Set
        (Context, "title", Standard.Templates.Values.String_Item ("Login - Ada Webframework Example"));
      Standard.Templates.Values.Set
        (Context, "csrf_token",
         Standard.Templates.Values.String_Item
           (App.Csrf.Token (Session_Id)));
      Page := To_Unbounded_String (App.Templates.Render ("layout.html", Context));
      Page := To_Unbounded_String
        (App.Templates.Replace_Marker
           (To_String (Page),
            "<!-- wf:body -->",
            App.Templates.Render ("login.html", Standard.Templates.Values.Object)));

      --  Return HTML response with session cookie
      return App.Runtime.Html_Response (Session_Id, To_String (Page));
      exception
         when Error : others =>
            Web.Logging.Error
              ("login route render failed: " & Ada.Exceptions.Exception_Message (Error));
            return Web.Response.Internal_Server_Error;
   end Login;

   --  Handle login API endpoint.
   function Api_Login (Request : Web.Request.Request_Type) return Web.Response.Response_Type is
      Sub          : Forms.Submission.Data (8, 4096);
      Body_Status  : Forms.Urlencoded.Decode_Status;
      Username     : Unbounded_String;
      Password     : Unbounded_String;
      Session_Id   : constant String := App.Runtime.Find_Or_Create_Session (Request);
   begin
      --  CSRF: the POST must carry a token valid for this (anonymous) session.
      if not App.Csrf.Verify (Request, Session_Id) then
         return Api_Error (403, "invalid csrf token");
      end if;

      --  Decode the urlencoded body into a submission with the forms library,
      --  then read the fields by name (percent-decoded, order-independent).
      Webframework_Forms.Read_Urlencoded (Request, Sub, Body_Status);
      if Body_Status /= Forms.Urlencoded.Decode_Ok then
         return Web.Response.Bad_Request ("Malformed form body");
      end if;
      Username := To_Unbounded_String
        (Webframework_Forms.To_String
           (Forms.Submission.Value_Of (Sub, Webframework_Forms.To_Bytes ("username"))));
      Password := To_Unbounded_String
        (Webframework_Forms.To_String
           (Forms.Submission.Value_Of (Sub, Webframework_Forms.To_Bytes ("password"))));

      --  Input-format validation only: the username must be well-formed and the
      --  password present. The generic message discloses nothing about which
      --  field failed or whether an account exists; credential VERIFICATION is
      --  Identity's job below. The password contents are never validated.
      if Length (Password) = 0
        or else Validation.Results.Has_Errors
                  (App.Login_Validation.Validate_Username (To_String (Username)))
      then
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
               Applier : Auth_Applier :=
                 (App.Runtime.Live.State_Visitor with
                  Principal => To_Unbounded_String (Principal),
                  Username  => Username,
                  Clearance => App.Auth.Clearance_Of (Principal),
                  Token     => To_Unbounded_String (Token));
            begin
               App.Runtime.With_State (Effective, Applier);
               return App.Runtime.Html_Response
                 (Effective, Success_Body);
            end;
         else
            return Api_Error (401, "invalid username or password");
         end if;
      end;
      exception
         when Error : others =>
            Web.Logging.Error
              (Log_Tag (Request) & "login API failed: " & Ada.Exceptions.Exception_Message (Error));
            return Web.Response.Internal_Server_Error;
   end Api_Login;

   --  Handle logout API endpoint.
   function Api_Logout (Request : Web.Request.Request_Type) return Web.Response.Response_Type is
      Session_Id : constant String := App.Runtime.Require_Session (Request);
   begin
      --  CSRF: a logout with a live session must carry a valid token.
      if Session_Id'Length > 0
        and then not App.Csrf.Verify (Request, Session_Id)
      then
         return Api_Error (403, "invalid csrf token");
      end if;

      if Session_Id'Length > 0 then
         --  Revoke the identity session (so its token can never be replayed),
         --  clear the auth fields, then invalidate the framework session.
         declare
            Reader  : Token_Reader;
            Clearer : Auth_Clearer;
         begin
            App.Runtime.With_State (Session_Id, Reader);
            if Length (Reader.Token) > 0 then
               App.Auth.Revoke_Session (To_String (Reader.Token));
            end if;
            App.Runtime.With_State (Session_Id, Clearer);
         end;
         App.Runtime.Invalidate_Session (Session_Id);
      end if;

      --  Return success response
      return App.Runtime.Html_Response (Session_Id, Success_Body);
      exception
         when Error : others =>
            Web.Logging.Error
              (Log_Tag (Request) & "logout API failed: " & Ada.Exceptions.Exception_Message (Error));
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
      --  One session for both the embedded token and the response cookie.
      Session_Id : constant String := App.Runtime.Find_Or_Create_Session (Request);
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
      Standard.Templates.Values.Set
        (View, "csrf_token",
         Standard.Templates.Values.String_Item
           (App.Csrf.Token (Session_Id)));
      Page := To_Unbounded_String (App.Templates.Render ("layout.html", View));

      --  Add navigation bar for authenticated pages
      declare
         Current_Path : constant String := Web.Request.Path (Request);
         Nav_Bar : constant String :=
           Generate_Nav_Bar (Current_Path, Clearance_Of (Context));
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
      return App.Runtime.Html_Response (Session_Id, To_String (Page));
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
      View : Value := Object;
      Page : Unbounded_String;
      Todo_Content : Unbounded_String;
      --  One session for both the embedded token and the response cookie.
      Session_Id : constant String := App.Runtime.Find_Or_Create_Session (Request);
   begin
      --  Access is decided by the route guard before this runs.
      --  Build the full HTML page through templates
      Set (View, "title", String_Item ("Todos - Ada Webframework Example"));
      Standard.Templates.Values.Set
        (View, "csrf_token",
         Standard.Templates.Values.String_Item
           (App.Csrf.Token (Session_Id)));
      Page := To_Unbounded_String (App.Templates.Render ("layout.html", View));

      --  Add navigation bar for authenticated pages
      declare
         Current_Path : constant String := Web.Request.Path (Request);
         Nav_Bar : constant String :=
           Generate_Nav_Bar (Current_Path, Clearance_Of (Context));
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
      return App.Runtime.Html_Response (Session_Id, To_String (Page));
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
      --  Authorization is enforced by the route guard before this runs.
      --  decode -> validate: Web.Binding decodes the urlencoded body into typed
      --  fields; the Validation library then checks them before any DB write.
      Form  : constant App.Project_Binding.Project_Form :=
        App.Project_Binding.Bind (Request);
      Input : constant App.Project_Validation.Project_Input :=
        (Name         => Form.Name,
         Status       => Form.Status,
         Project_Type => Form.Project_Type,
         Functions    => Form.Functions);
      Check : constant Validation.Results.Result :=
        App.Project_Validation.Validate (Input);
   begin
      --  CSRF: reject a mutation whose token is not valid for this session.
      if not App.Csrf.Verify
        (Request, App.Runtime.Find_Or_Create_Session (Request))
      then
         return Api_Error (403, "invalid csrf token");
      end if;

      --  A malformed / oversized form body never reaches validation.
      if not Form.Decoded then
         return Api_Error (400, "malformed form body");
      end if;

      --  Reject invalid input with the structured issues as JSON.
      if Validation.Results.Has_Errors (Check) then
         return Web.Response.Create
           (400, App.Project_Validation.Error_JSON (Check),
            Json_Content_Type);
      end if;

      --  Add the validated project to the database.
      Add_Project
        (Name              => To_String (Form.Name),
         Status            => To_String (Form.Status),
         Project_Type      => To_String (Form.Project_Type),
         Functions         => To_String (Form.Functions),
         Has_Project_Tools => Form.Has_Project_Tools,
         Has_GNAT          => Form.Has_GNAT,
         Has_GitHub        => Form.Has_GitHub,
         Has_Alire         => Form.Has_Alire);

      return Api_Success;
   exception
      when Error : others =>
         Web.Logging.Error
           (Log_Tag (Request) & "add project API failed: " & Ada.Exceptions.Exception_Message (Error));
         return Web.Response.Internal_Server_Error;
   end Api_Add_Project;

   --  API endpoint to delete a project
   function Api_Delete_Project
     (Request : Web.Request.Request_Type;
      Context : Web.Context.Request_Context) return Web.Response.Response_Type is
      use App.Projects;
      pragma Unreferenced (Context);
      --  decode -> validate: Web.Binding decodes the id as a typed integer; the
      --  Validation library then checks it is a positive project id.
      Form  : constant App.Project_Binding.Delete_Form :=
        App.Project_Binding.Bind_Delete (Request);
      Check : constant Validation.Results.Result :=
        App.Project_Validation.Validate_Delete ((Id => Form.Id));
   begin
      --  CSRF: reject a mutation whose token is not valid for this session.
      if not App.Csrf.Verify
        (Request, App.Runtime.Find_Or_Create_Session (Request))
      then
         return Api_Error (403, "invalid csrf token");
      end if;

      --  A missing / non-integer id never reaches validation.
      if not Form.Decoded then
         return Api_Error (400, "invalid project id");
      end if;

      if Validation.Results.Has_Errors (Check) then
         return Web.Response.Create
           (400, App.Project_Validation.Error_JSON (Check),
            Json_Content_Type);
      end if;

      Delete_Project (Form.Id);

      return Api_Success;
   exception
      when Error : others =>
         Web.Logging.Error
           (Log_Tag (Request) & "delete project API failed: " & Ada.Exceptions.Exception_Message (Error));
         return Web.Response.Internal_Server_Error;
   end Api_Delete_Project;

   ---------------------------------------------------------------------------
   --  Attachments (file upload / list / download / delete)
   ---------------------------------------------------------------------------

   function Trim (S : String) return String is
     (Ada.Strings.Fixed.Trim (S, Ada.Strings.Both));

   --  Value of Name in an "a=b&c=d" string (query or urlencoded body); "" if
   --  absent. The values here are integers, so no percent-decoding is needed.
   function Param_Value (Source : String; Name : String) return String is
      Key    : constant String := Name & "=";
      Cursor : Natural := Source'First;
   begin
      while Cursor <= Source'Last loop
         declare
            Amp  : constant Natural :=
              Ada.Strings.Fixed.Index (Source (Cursor .. Source'Last), "&");
            Stop : constant Natural := (if Amp = 0 then Source'Last else Amp - 1);
            Pair : String renames Source (Cursor .. Stop);
         begin
            if Pair'Length >= Key'Length
              and then Pair (Pair'First .. Pair'First + Key'Length - 1) = Key
            then
               return Pair (Pair'First + Key'Length .. Pair'Last);
            end if;
            exit when Amp = 0;
            Cursor := Amp + 1;
         end;
      end loop;
      return "";
   end Param_Value;

   --  The attachments page body: the multipart upload form and the file table.
   function Attachments_Content (Session_Id : String) return String is
      Items : App.Attachments.Entry_Array (1 .. App.Attachments.Max_Attachments);
      Count : Natural;
      Token : constant String := App.Csrf.Token (Session_Id);
      Body_Html : Unbounded_String;
      procedure P (S : String) is
      begin
         Append (Body_Html, S);
      end P;
   begin
      App.Attachments.List (Items, Count);
      P ("<div class=""panel""><h1>Attachments</h1>");
      P ("<p>Upload a file &mdash; it is staged, integrity-hashed, committed to "
         & "durable storage, and served back on demand.</p>");
      --  The body is streamed, so the CSRF token rides in the query string
      --  (verified before the body is read), not as a form field.
      P ("<form method=""post"" action=""/attachments/upload?csrf="
         & Web.Html.Escape_Attribute (Token)
         & """ enctype=""multipart/form-data"">");
      P ("<input type=""file"" name=""document"" required> ");
      P ("<button type=""submit"">Upload</button></form>");
      if Count = 0 then
         P ("<p><em>No attachments yet.</em></p>");
      else
         P ("<table><thead><tr><th>#</th><th>Name</th><th>Size</th>"
            & "<th></th></tr></thead><tbody>");
         for I in 1 .. Count loop
            declare
               E   : App.Attachments.Entry_View renames Items (I);
               Num : constant String :=
                 Trim (App.Attachments.Doc_Number'Image (E.Number));
               Nm  : constant String := E.Name (1 .. E.Name_Length);
            begin
               P ("<tr><td>" & Num & "</td>");
               P ("<td><a href=""/attachments/download?doc=" & Num & """>"
                  & Web.Html.Escape_Text (Nm) & "</a></td>");
               P ("<td>" & Trim (Webfiles.Byte_Count'Image (E.Size))
                  & " bytes</td>");
               P ("<td><form method=""post"" action=""/attachments/delete"" "
                  & "style=""display:inline"">");
               P ("<input type=""hidden"" name=""" & App.Csrf.Field
                  & """ value=""" & Web.Html.Escape_Attribute (Token) & """>");
               P ("<input type=""hidden"" name=""doc"" value=""" & Num & """>");
               P ("<button type=""submit"">Delete</button></form></td></tr>");
            end;
         end loop;
         P ("</tbody></table>");
      end if;
      P ("</div>");
      return To_String (Body_Html);
   end Attachments_Content;

   function Attachments
     (Request : Web.Request.Request_Type;
      Context : Web.Context.Request_Context) return Web.Response.Response_Type
   is
      use Standard.Templates.Values;
      View       : Value := Object;
      Page       : Unbounded_String;
      Session_Id : constant String := App.Runtime.Find_Or_Create_Session (Request);
   begin
      Set (View, "title", String_Item ("Attachments"));
      Set (View, "csrf_token", String_Item (App.Csrf.Token (Session_Id)));
      Page := To_Unbounded_String (App.Templates.Render ("layout.html", View));

      declare
         Current_Path : constant String := Web.Request.Path (Request);
         Nav_Bar : constant String :=
           Generate_Nav_Bar (Current_Path, Clearance_Of (Context));
      begin
         Page := To_Unbounded_String
           (App.Templates.Replace_Marker
              (To_String (Page), "<main>", Nav_Bar & "<main>"));
      end;

      Page := To_Unbounded_String
        (App.Templates.Replace_Marker
           (To_String (Page), "<!-- wf:body -->",
            Attachments_Content (Session_Id)));
      Page := To_Unbounded_String
        (App.Templates.Replace_Asset_Urls
           (To_String (Page), Web.Assets.Clients.Css_Url,
            Web.Assets.Clients.Js_Url));

      return App.Runtime.Html_Response (Session_Id, To_String (Page));
   exception
      when Error : others =>
         Web.Logging.Error
           ("attachments route render failed: "
            & Ada.Exceptions.Exception_Message (Error));
         return Web.Response.Internal_Server_Error;
   end Attachments;

   function Upload_Attachment
     (Request : Web.Request.Request_Type;
      Body_R  : in out Web.Http_Body.Reader) return Web.Response.Response_Type
   is
      Session_Id : constant String := App.Runtime.Find_Or_Create_Session (Request);
      Content_T  : constant String := Web.Request.Header (Request, "Content-Type");
      Boundary   : constant String := Web.Multipart.Boundary_Of (Content_T);
      Csrf_Token : constant String :=
        Param_Value (Web.Request.Query_String (Request), "csrf");
      Uploaded   : Boolean;
   begin
      --  The body is streamed, so the CSRF token travels in the query and is
      --  checked before a single byte is read into storage.
      if not App.Csrf.Verify_Token (Session_Id, Csrf_Token) then
         return Web.Response.Forbidden ("invalid csrf token");
      end if;
      if Boundary = "" then
         return Web.Response.Bad_Request ("expected multipart/form-data");
      end if;

      App.Attachments.Stream_Upload (Body_R, Boundary, Uploaded);
      if not Uploaded then
         Web.Logging.Error (Log_Tag (Request) & "attachment was not accepted");
      end if;
      return App.Nav.Redirect ("attachments");
   exception
      when Error : others =>
         Web.Logging.Error
           (Log_Tag (Request) & "attachment upload failed: "
            & Ada.Exceptions.Exception_Message (Error));
         return Web.Response.Internal_Server_Error;
   end Upload_Attachment;

   function Download_Attachment
     (Request : Web.Request.Request_Type;
      Context : Web.Context.Request_Context) return Web.Response.Response_Type
   is
      pragma Unreferenced (Context);
      Doc_Text : constant String :=
        Param_Value (Web.Request.Query_String (Request), "doc");
   begin
      if Doc_Text = "" then
         return Web.Response.Not_Found;
      end if;
      return App.Attachments.Download (App.Attachments.Doc_Number'Value (Doc_Text));
   exception
      when Constraint_Error =>
         return Web.Response.Not_Found;
      when Error : others =>
         Web.Logging.Error
           (Log_Tag (Request) & "attachment download failed: "
            & Ada.Exceptions.Exception_Message (Error));
         return Web.Response.Internal_Server_Error;
   end Download_Attachment;

   function Delete_Attachment
     (Request : Web.Request.Request_Type;
      Context : Web.Context.Request_Context) return Web.Response.Response_Type
   is
      pragma Unreferenced (Context);
      Session_Id : constant String := App.Runtime.Find_Or_Create_Session (Request);
      Doc_Text   : constant String :=
        Param_Value (Web.Request.Request_Body (Request), "doc");
   begin
      if not App.Csrf.Verify (Request, Session_Id) then
         return Web.Response.Forbidden ("invalid csrf token");
      end if;
      if Doc_Text /= "" then
         begin
            App.Attachments.Delete (App.Attachments.Doc_Number'Value (Doc_Text));
         exception
            when Constraint_Error =>
               null;  --  unparsable number: nothing to delete
         end;
      end if;
      return App.Nav.Redirect ("attachments");
   exception
      when Error : others =>
         Web.Logging.Error
           (Log_Tag (Request) & "attachment delete failed: "
            & Ada.Exceptions.Exception_Message (Error));
         return Web.Response.Internal_Server_Error;
   end Delete_Attachment;

   ---------------------------------------------------------------------------
   --  Email-notification demo
   ---------------------------------------------------------------------------

   --  The demo page body: a send form, the last send's outcome, and every
   --  message the in-process SMTP catcher captured (raw RFC 5322 bytes).
   function Email_Demo_Content (Session_Id : String) return String is
      Token     : constant String := App.Csrf.Token (Session_Id);
      Last      : constant App.Notifications.Send_Result := App.Notifications.Last_Send;
      Body_Html : Unbounded_String;
      procedure P (S : String) is
      begin
         Append (Body_Html, S);
      end P;
      use type App.Notifications.Send_Phase;
   begin
      P ("<div class=""panel""><h1>Email notification demo</h1>");
      P ("<p>Send an email notification. It flows through the notifications "
         & "engine &rarr; notifications_email &rarr; smtplib &rarr; a real "
         & "socket &rarr; an in-process SMTP catcher on 127.0.0.1:"
         & Web.Html.Escape_Text (Trim (Positive'Image (App.Smtp_Catcher.Port)))
         & ", which captures the bytes on the wire and shows them below.</p>");

      P ("<form method=""post"" action=""/email-demo/send"">");
      P ("<input type=""hidden"" name=""" & App.Csrf.Field & """ value="""
         & Web.Html.Escape_Attribute (Token) & """>");
      P ("<p><label>To<br><input type=""email"" name=""to"" required "
         & "value=""alice@example.com""></label></p>");
      P ("<p><label>Subject<br><input type=""text"" name=""subject"" required "
         & "value=""Hello from example_app""></label></p>");
      P ("<p><label>Message<br><textarea name=""message"" rows=""4"" required>"
         & "It works end to end.</textarea></label></p>");
      P ("<button type=""submit"">Send email</button></form>");

      --  Last send outcome.
      if Last.Phase /= App.Notifications.Not_Started then
         P ("<h2>Last send</h2><ul>");
         P ("<li>phase: " & Web.Html.Escape_Text
              (App.Notifications.Send_Phase'Image (Last.Phase)) & "</li>");
         P ("<li>create result: "
            & Web.Html.Escape_Text (To_String (Last.Create_Image)) & "</li>");
         P ("<li>steps run: " & Trim (Natural'Image (Last.Steps_Run)) & "</li>");
         if Last.Provider_Called then
            P ("<li>provider result: "
               & Web.Html.Escape_Text (To_String (Last.Provider_Class))
               & " / "
               & Web.Html.Escape_Text (To_String (Last.Provider_Certainty))
               & "</li>");
         end if;
         P ("<li>reached catcher: "
            & (if Last.Reached_Catcher then "yes" else "no") & "</li>");
         P ("</ul>");
      end if;

      --  Captured mailbox.
      declare
         N : constant Natural := App.Smtp_Catcher.Count;
      begin
         P ("<h2>Captured messages (" & Trim (Natural'Image (N)) & ")</h2>");
         if N = 0 then
            P ("<p><em>Nothing captured yet.</em></p>");
         else
            for I in 1 .. N loop
               declare
                  Mail  : App.Smtp_Catcher.Captured_Mail;
                  Found : Boolean;
               begin
                  App.Smtp_Catcher.Get (I, Mail, Found);
                  if Found then
                     P ("<div class=""panel"">");
                     P ("<p><strong>envelope from:</strong> "
                        & Web.Html.Escape_Text (To_String (Mail.Envelope_From))
                        & " &nbsp; <strong>envelope to:</strong> "
                        & Web.Html.Escape_Text (To_String (Mail.Envelope_To))
                        & "</p>");
                     P ("<pre>"
                        & Web.Html.Escape_Text (To_String (Mail.Raw_Message))
                        & "</pre>");
                     P ("</div>");
                  end if;
               end;
            end loop;
         end if;
      end;

      P ("</div>");
      return To_String (Body_Html);
   end Email_Demo_Content;

   function Email_Demo
     (Request : Web.Request.Request_Type;
      Context : Web.Context.Request_Context) return Web.Response.Response_Type
   is
      use Standard.Templates.Values;
      View       : Value := Object;
      Page       : Unbounded_String;
      Session_Id : constant String := App.Runtime.Find_Or_Create_Session (Request);
   begin
      Set (View, "title", String_Item ("Email Demo"));
      Set (View, "csrf_token", String_Item (App.Csrf.Token (Session_Id)));
      Page := To_Unbounded_String (App.Templates.Render ("layout.html", View));

      declare
         Current_Path : constant String := Web.Request.Path (Request);
         Nav_Bar : constant String :=
           Generate_Nav_Bar (Current_Path, Clearance_Of (Context));
      begin
         Page := To_Unbounded_String
           (App.Templates.Replace_Marker
              (To_String (Page), "<main>", Nav_Bar & "<main>"));
      end;

      Page := To_Unbounded_String
        (App.Templates.Replace_Marker
           (To_String (Page), "<!-- wf:body -->",
            Email_Demo_Content (Session_Id)));
      Page := To_Unbounded_String
        (App.Templates.Replace_Asset_Urls
           (To_String (Page), Web.Assets.Clients.Css_Url,
            Web.Assets.Clients.Js_Url));

      return App.Runtime.Html_Response (Session_Id, To_String (Page));
   exception
      when Error : others =>
         Web.Logging.Error
           ("email-demo route render failed: "
            & Ada.Exceptions.Exception_Message (Error));
         return Web.Response.Internal_Server_Error;
   end Email_Demo;

   function Send_Email_Demo
     (Request : Web.Request.Request_Type;
      Context : Web.Context.Request_Context) return Web.Response.Response_Type
   is
      pragma Unreferenced (Context);
      Session_Id  : constant String := App.Runtime.Find_Or_Create_Session (Request);
      Sub         : Forms.Submission.Data (8, 8192);
      Body_Status : Forms.Urlencoded.Decode_Status;
      Result      : App.Notifications.Send_Result;
   begin
      if not App.Csrf.Verify (Request, Session_Id) then
         return Web.Response.Forbidden ("invalid csrf token");
      end if;
      Webframework_Forms.Read_Urlencoded (Request, Sub, Body_Status);
      if Body_Status /= Forms.Urlencoded.Decode_Ok then
         return Web.Response.Bad_Request ("Malformed form body");
      end if;
      declare
         To_Email : constant String := Webframework_Forms.To_String
           (Forms.Submission.Value_Of (Sub, Webframework_Forms.To_Bytes ("to")));
         Subject  : constant String := Webframework_Forms.To_String
           (Forms.Submission.Value_Of (Sub, Webframework_Forms.To_Bytes ("subject")));
         Message  : constant String := Webframework_Forms.To_String
           (Forms.Submission.Value_Of (Sub, Webframework_Forms.To_Bytes ("message")));
      begin
         App.Notifications.Send (To_Email, Subject, Message, Result);
      end;
      return App.Nav.Redirect ("email_demo");
   exception
      when Error : others =>
         Web.Logging.Error
           (Log_Tag (Request) & "email-demo send failed: "
            & Ada.Exceptions.Exception_Message (Error));
         return Web.Response.Internal_Server_Error;
   end Send_Email_Demo;

end App.Pages;
