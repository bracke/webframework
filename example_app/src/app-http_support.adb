with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.Fixed;

with Web.Request;
with Web.Response;
with Web.Context;
with Web.Server;

with App.Pages;
with App.Csrf;
with App.Nav;
with App.Projects;
with App.Runtime;
with App.State;
with App.Auth;
with App.Authz;
with App.Guards;
with App.Templates;

package body App.Http_Support is

   Fail_Count : Natural := 0;

   procedure Check (Cond : Boolean; Label : String) is
   begin
      if Cond then
         Put_Line ("OK   " & Label);
      else
         Put_Line ("FAIL " & Label);
         Fail_Count := Fail_Count + 1;
      end if;
   end Check;

   --  A trivial guard-protected handler; access is decided before it runs.
   function Stub
     (Request : Web.Request.Request_Type;
      Context : Web.Context.Request_Context) return Web.Response.Response_Type
   is
      pragma Unreferenced (Request);
   begin
      return Web.Response.Text ("ok principal=" & Web.Context.Principal (Context));
   end Stub;

   --  Visitors carry their per-call data in their own fields (see
   --  Web.Live.State_Visitor), so the harness shares no mutable global that
   --  concurrent updates could race on.
   type Auth_Applier is new App.Runtime.Live.State_Visitor with record
      Principal : Unbounded_String;
      Clearance : Natural := 0;
      Token     : Unbounded_String;
   end record;
   overriding procedure Apply
     (Self : in out Auth_Applier; State : in out App.State.App_State) is
   begin
      App.State.Set_Authenticated
        (State, To_String (Self.Principal), "user",
         Self.Clearance, To_String (Self.Token));
   end Apply;

   --  Read the identity-session token back out of a session's state.
   type Token_Reader is new App.Runtime.Live.State_Visitor with record
      Token : Unbounded_String;
   end record;
   overriding procedure Apply
     (Self : in out Token_Reader; State : in out App.State.App_State) is
   begin
      Self.Token := To_Unbounded_String (App.State.Get_Session_Token (State));
   end Apply;

   --  Log a user in: create a framework session, authenticate through the
   --  identity repository, open an identity session, and store the auth on the
   --  session. Returns the framework session id (the cookie value).
   function Setup_Login (Username : String; Password : String) return String is
      Seed : constant Web.Request.Request_Type := Web.Request.Create ("GET", "/");
      Sid  : constant String := App.Runtime.Find_Or_Create_Session (Seed);
      Principal : constant String := App.Auth.Authenticate (Username, Password);
   begin
      if Principal = "" then
         return "";
      end if;
      declare
         Applier : Auth_Applier :=
           (App.Runtime.Live.State_Visitor with
            Principal => To_Unbounded_String (Principal),
            Clearance => App.Auth.Clearance_Of (Principal),
            Token     => To_Unbounded_String (App.Auth.Create_Session (Principal)));
      begin
         App.Runtime.With_State (Sid, Applier);
      end;
      return Sid;
   end Setup_Login;

   --  A returning user re-established from a remember-me cookie: a Basic
   --  (low-assurance) identity session with no fresh password presentation.
   --  Returns the framework session id (the cookie value).
   function Setup_Remembered (Principal : String) return String is
      Seed : constant Web.Request.Request_Type := Web.Request.Create ("GET", "/");
      Sid  : constant String := App.Runtime.Find_Or_Create_Session (Seed);
      Applier : Auth_Applier :=
        (App.Runtime.Live.State_Visitor with
         Principal => To_Unbounded_String (Principal),
         Clearance => App.Auth.Clearance_Of (Principal),
         Token     =>
           To_Unbounded_String (App.Auth.Create_Remembered_Session (Principal)));
   begin
      App.Runtime.With_State (Sid, Applier);
      return Sid;
   end Setup_Remembered;

   --  Dispatch a request (optionally carrying a session cookie) and return the
   --  HTTP status the guard chain produced.
   function Status_Of
     (Method : String; Path : String; Cookie : String := "") return Natural
   is
      Req : Web.Request.Request_Type := Web.Request.Create (Method, Path);
   begin
      if Cookie /= "" then
         Web.Request.Set_Header (Req, "Cookie", "wf_session=" & Cookie);
      end if;
      return Web.Response.Status (Web.Server.Dispatch (Req));
   end Status_Of;

   --  A POST request carrying session Sid and a valid CSRF token for it, so a
   --  handler's CSRF check passes and the request reaches the handler logic.
   function Csrf_Post
     (Path : String; Data : String; Sid : String) return Web.Request.Request_Type
   is
      Full : constant String :=
        (if Data = "" then "" else Data & "&")
        & App.Csrf.Field & "=" & App.Csrf.Token (Sid);
      Req  : Web.Request.Request_Type :=
        Web.Request.Create ("POST", Path, "", Full);
   begin
      Web.Request.Set_Header (Req, "Cookie", "wf_session=" & Sid);
      return Req;
   end Csrf_Post;

   --  A fresh (anonymous) session id, for minting CSRF tokens in tests.
   function New_Session return String is
     (App.Runtime.Find_Or_Create_Session (Web.Request.Create ("GET", "/")));

   --  The wf_session id a response sets in its Set-Cookie header ("" if none).
   function Cookie_From (Resp : Web.Response.Response_Type) return String is
      Header : constant String := Web.Response.Header (Resp, "Set-Cookie");
      Key    : constant String := "wf_session=";
      At_Key : constant Natural := Ada.Strings.Fixed.Index (Header, Key);
   begin
      if At_Key = 0 then
         return "";
      end if;
      declare
         Start : constant Positive := At_Key + Key'Length;
         Semi  : constant Natural :=
           Ada.Strings.Fixed.Index (Header (Start .. Header'Last), ";");
      begin
         return (if Semi = 0 then Header (Start .. Header'Last)
                 else Header (Start .. Semi - 1));
      end;
   end Cookie_From;

   --  The CSRF token a rendered page carries in its <meta> tag ("" if none).
   function Meta_Token_From (Page : String) return String is
      Key    : constant String := "name=""csrf-token"" content=""";
      At_Key : constant Natural := Ada.Strings.Fixed.Index (Page, Key);
   begin
      if At_Key = 0 then
         return "";
      end if;
      declare
         Start : constant Positive := At_Key + Key'Length;
         Quote : constant Natural :=
           Ada.Strings.Fixed.Index (Page (Start .. Page'Last), """");
      begin
         return (if Quote = 0 then "" else Page (Start .. Quote - 1));
      end;
   end Meta_Token_From;

   procedure Run (Failures : out Natural) is
   begin
      App.Auth.Initialize;
      App.Authz.Initialize;

      --  Wire the same seam the app uses: a global principal resolver, a
      --  page-guarded route and an API-guarded management route (the "/api/
      --  projects/" prefix makes the policy require administrator clearance).
      App.Runtime.Use_Guard (App.Guards.Resolve_Principal'Access);
      App.Runtime.Get
        ("/secure", Stub'Access, App.Guards.Require_App_Access'Access);
      App.Runtime.Post
        ("/api/projects/probe", Stub'Access,
         App.Guards.Require_App_Access_Api'Access);

      --  The real, public login routes (rendered page + API), so the tests can
      --  exercise the actual first-contact flow through Dispatch rather than
      --  constructing sessions directly.
      App.Runtime.Get ("/login", App.Pages.Login'Access);
      App.Runtime.Post ("/api/login", App.Pages.Api_Login'Access);

      --  Anonymous: redirected from a page, 401 from an API.
      Check (Status_Of ("GET", "/secure") = 303,
             "http: anonymous is redirected from a protected page");
      Check (Status_Of ("POST", "/api/projects/probe") = 401,
             "http: anonymous gets 401 from a protected API");

      --  Administrator: admitted everywhere.
      declare
         Admin : constant String := Setup_Login ("admin", "admin123");
      begin
         Check (Admin /= "", "http: admin logs in");
         Check (Status_Of ("GET", "/secure", Admin) = 200,
                "http: admin is admitted to the protected page");
         Check (Status_Of ("POST", "/api/projects/probe", Admin) = 200,
                "http: admin may manage");
      end;

      --  Viewer: may view, may not manage.
      declare
         Viewer : constant String := Setup_Login ("viewer", "viewer123");
      begin
         Check (Viewer /= "", "http: viewer logs in");
         Check (Status_Of ("GET", "/secure", Viewer) = 200,
                "http: viewer is admitted to the protected page");
         Check (Status_Of ("POST", "/api/projects/probe", Viewer) = 403,
                "http: viewer is forbidden from managing");
      end;

      --  A remembered (low-assurance) administrator session: full clearance,
      --  but the step-up gate refuses management until an interactive
      --  re-authentication. This is the assurance gate proven over the wire.
      declare
         Admin_R : constant String := Setup_Remembered ("d.principal.admin");
      begin
         Check (Admin_R /= "", "http: admin returns on a remembered session");
         Check (Status_Of ("GET", "/secure", Admin_R) = 200,
                "http: a remembered session may view");
         Check (Status_Of ("POST", "/api/projects/probe", Admin_R) = 403,
                "http: a remembered low-assurance session may NOT manage "
                & "(step-up)");
      end;

      --  Session revocation takes effect on the very next request.
      declare
         Sid    : constant String := Setup_Login ("admin", "admin123");
         Reader : Token_Reader;
      begin
         App.Runtime.With_State (Sid, Reader);
         Check (Status_Of ("GET", "/secure", Sid) = 200,
                "http: a live session is admitted");
         App.Auth.Revoke_Session (To_String (Reader.Token));
         Check (Status_Of ("GET", "/secure", Sid) = 303,
                "http: a revoked identity session is anonymous at once");
      end;

      --  Navigation library: the anonymous->login redirect is built by route
      --  name (reverse URL), and the nav menu highlights the active page and is
      --  filtered by clearance (fail-closed for anonymous).
      declare
         To_Login  : constant Web.Response.Response_Type := App.Nav.Redirect ("login");
         Menu_Auth : constant String := App.Nav.Menu_Html ("/projects", 100);
         Menu_Anon : constant String := App.Nav.Menu_Html ("/", 0);
      begin
         Check (Web.Response.Status (To_Login) = 303
                and then Web.Response.Header (To_Login, "Location") = "/login",
                "nav: reverse-URL redirect targets the login route");
         Check (Ada.Strings.Fixed.Index (Menu_Auth, "href=""/projects""") > 0,
                "nav: menu links items by reverse URL");
         Check (Ada.Strings.Fixed.Index (Menu_Auth, "class=""active""") > 0,
                "nav: menu highlights the active page from the path");
         Check (Menu_Anon = "",
                "nav: menu is empty for anonymous (fail-closed visibility)");
      end;

      --  Authorization-aware projects listing (tables + tables_authorization):
      --  the plan masks the sensitive functions column for a viewer but not an
      --  admin, applies the Alire data scope, and is fail-closed for an
      --  unauthorized caller.
      declare
         Admin_Plan  : constant App.Authz.Listing_Plan :=
           App.Authz.Plan_Projects_Listing ("d.principal.admin", 100);
         Viewer_Plan : constant App.Authz.Listing_Plan :=
           App.Authz.Plan_Projects_Listing ("d.principal.viewer", 10);
         Anon_Plan   : constant App.Authz.Listing_Plan :=
           App.Authz.Plan_Projects_Listing ("", 0);
      begin
         Check (Admin_Plan.Ready and then not Admin_Plan.Mask_Functions,
                "tables: admin sees the functions column (not masked)");
         Check (Viewer_Plan.Ready and then Viewer_Plan.Mask_Functions,
                "tables: a viewer's functions column is masked");
         Check (Admin_Plan.Scope_Applied and then Admin_Plan.Restrict_To_Alire
                and then Viewer_Plan.Restrict_To_Alire,
                "tables: the Alire data scope is applied to the listing");
         Check (not Anon_Plan.Ready,
                "tables: an unauthorized principal is fail-closed (no plan)");
      end;

      --  The plan's decision is actually honored in the rendered table: with
      --  Mask_Functions the sensitive value is withheld from the output; without
      --  it the same value is shown. (Rendered from templates/projects.html,
      --  resolved relative to the example_app working directory.)
      declare
         use App.Projects;
         Secret : constant String := "ZZ-functions-secret";
         Rows   : Project_Vectors.Vector;
         Row    : Project_Record;
      begin
         Row.Id := 1;
         Row.Name (1 .. 4)         := "Demo";
         Row.Status (1 .. 6)       := "active";
         Row.Project_Type (1 .. 3) := "lib";
         Row.Functions (1 .. Secret'Length) := Secret;
         Rows.Append (Row);

         declare
            Masked : constant String := App.Templates.Render_Projects_Table
              (Rows, Scope_Applied => True, Mask_Functions => True,
               Authorized_Columns => 4, Total_Rows => 1);
            Shown  : constant String := App.Templates.Render_Projects_Table
              (Rows, Scope_Applied => True, Mask_Functions => False,
               Authorized_Columns => 5, Total_Rows => 1);
         begin
            Check (Ada.Strings.Fixed.Index (Masked, Secret) = 0,
                   "tables: the functions value is withheld from a masked render");
            Check (Ada.Strings.Fixed.Index (Shown, Secret) > 0,
                   "tables: the functions value is shown in an unmasked render");
         end;
      end;

      --  Real first-contact login through Dispatch: a fresh cookieless client
      --  GETs the login page (the ACTUAL Login handler renders it and sets the
      --  session cookie), reads the CSRF token from the page, and logs in with
      --  exactly the cookie + token it was handed. This drives the real
      --  Login/Api_Login handlers end to end -- the path Setup_Login bypasses --
      --  and is the regression guard for the session-bound CSRF binding (a token
      --  and a cookie that name the same session).
      declare
         Get_Login : constant Web.Response.Response_Type :=
           Web.Server.Dispatch (Web.Request.Create ("GET", "/login"));
         Sid   : constant String := Cookie_From (Get_Login);
         Token : constant String :=
           Meta_Token_From (Web.Response.Content_Body (Get_Login));

         First_Login : Web.Request.Request_Type :=
           Web.Request.Create
             ("POST", "/api/login", "",
              "username=admin&password=admin123&"
              & App.Csrf.Field & "=" & Token);

         --  Same cookie, but a token bound to a DIFFERENT session.
         Wrong_Token : Web.Request.Request_Type :=
           Web.Request.Create
             ("POST", "/api/login", "",
              "username=admin&password=admin123&"
              & App.Csrf.Field & "=" & App.Csrf.Token (New_Session));
      begin
         Web.Request.Set_Header (First_Login, "Cookie", "wf_session=" & Sid);
         Web.Request.Set_Header (Wrong_Token, "Cookie", "wf_session=" & Sid);

         Check (Web.Response.Status (Get_Login) = 200
                and then Sid'Length > 0 and then Token'Length > 0,
                "http: GET /login renders, sets a session cookie and a token");
         Check (Web.Response.Status (Web.Server.Dispatch (First_Login)) = 200,
                "http: a first cookieless visit logs in with the page's token");
         Check (Web.Response.Status (Web.Server.Dispatch (Wrong_Token)) = 403,
                "http: a token bound to another session is refused (403)");
      end;

      --  API error contract: every JSON endpoint answers with a single shape,
      --  {"status":"error",...} as application/json -- never plain text and
      --  never a second {"error":...} shape. Covers the two responses that used
      --  to diverge: a failed login (was text/plain) and a CSRF rejection (was
      --  {"error":...}).
      declare
         Sid : constant String := New_Session;
         --  Valid session + token, wrong password -> 401.
         Bad_Login : constant Web.Response.Response_Type :=
           Web.Server.Dispatch
             (Csrf_Post ("/api/login", "username=admin&password=wrongpass", Sid));
         --  No token -> CSRF rejection.
         No_Token : constant Web.Response.Response_Type :=
           Web.Server.Dispatch
             (Web.Request.Create
                ("POST", "/api/login", "", "username=admin&password=admin123"));

         function Is_Error_Json (R : Web.Response.Response_Type) return Boolean is
           (Ada.Strings.Fixed.Index
              (Web.Response.Content_Body (R), """status"":""error""") > 0
            and then Ada.Strings.Fixed.Index
              (Web.Response.Header (R, "Content-Type"), "application/json") > 0);
      begin
         Check (Web.Response.Status (Bad_Login) = 401
                and then Is_Error_Json (Bad_Login),
                "http: a failed login returns the JSON error contract (401)");
         Check (Web.Response.Status (No_Token) = 403
                and then Is_Error_Json (No_Token),
                "http: a CSRF rejection returns the JSON error contract (403)");
      end;

      --  Add-project reject path: the handler decodes the urlencoded body via
      --  Web.Binding, validates it, and returns HTTP 400 with the structured
      --  issues as JSON. (Context is unused by the handler, so no session is
      --  needed; the reject paths never touch the database.)
      declare
         Ctx : constant Web.Context.Request_Context := Web.Context.New_Context;
         Sid : constant String := New_Session;

         function Body_Has (Response : Web.Response.Response_Type; Text : String)
           return Boolean is
           (Ada.Strings.Fixed.Index
              (Web.Response.Content_Body (Response), Text) > 0);

         --  With a valid CSRF token: the request reaches decode + validation.
         No_Name    : constant Web.Response.Response_Type :=
           App.Pages.Api_Add_Project
             (Csrf_Post ("/api/projects/add", "status=active", Sid), Ctx);
         Token_Only : constant Web.Response.Response_Type :=
           App.Pages.Api_Add_Project
             (Csrf_Post ("/api/projects/add", "", Sid), Ctx);
         --  Without a CSRF token: refused before validation.
         No_Csrf    : constant Web.Response.Response_Type :=
           App.Pages.Api_Add_Project
             (Web.Request.Create
                ("POST", "/api/projects/add", "", "name=X&status=active"), Ctx);
      begin
         Check (Web.Response.Status (No_Name) = 400,
                "http: add-project with no name is rejected (400)");
         Check (Body_Has (No_Name, "validation.not_empty"),
                "http: 400 body carries the structured issue id");
         Check (Body_Has (No_Name, "$.name"),
                "http: 400 body carries the field path");
         Check (Web.Response.Status (Token_Only) = 400,
                "http: add-project with no fields is rejected (400)");
         Check (Web.Response.Status (No_Csrf) = 403,
                "http: add-project without a CSRF token is refused (403)");
      end;

      --  Delete and login reject paths: a non-positive / non-integer id and a
      --  blank username are rejected with 400 before any state change.
      declare
         Ctx : constant Web.Context.Request_Context := Web.Context.New_Context;
         Sid : constant String := New_Session;
         Zero_Id : constant Web.Response.Response_Type :=
           App.Pages.Api_Delete_Project
             (Csrf_Post ("/api/projects/delete", "id=0", Sid), Ctx);
         Bad_Id : constant Web.Response.Response_Type :=
           App.Pages.Api_Delete_Project
             (Csrf_Post ("/api/projects/delete", "id=abc", Sid), Ctx);
         Blank_User : constant Web.Response.Response_Type :=
           App.Pages.Api_Login
             (Csrf_Post ("/api/login", "username=&password=x", Sid));
         Login_No_Csrf : constant Web.Response.Response_Type :=
           App.Pages.Api_Login
             (Web.Request.Create ("POST", "/api/login", "", "username=x&password=y"));
         Good_Login : constant Web.Response.Response_Type :=
           App.Pages.Api_Login
             (Csrf_Post ("/api/login", "username=admin&password=admin123", Sid));
      begin
         Check (Web.Response.Status (Zero_Id) = 400,
                "http: delete with a non-positive id is rejected (400)");
         Check (Web.Response.Status (Bad_Id) = 400,
                "http: delete with a non-integer id is rejected (400)");
         Check (Web.Response.Status (Blank_User) = 400,
                "http: login with a blank username is rejected (400)");
         Check (Web.Response.Status (Login_No_Csrf) = 403,
                "http: login without a CSRF token is refused (403)");
         Check (Web.Response.Status (Good_Login) = 200,
                "http: valid login succeeds (credentials forms-decoded)");
      end;

      --  Add-project success round-trip: a valid body is decoded, validated and
      --  written to the database (HTTP 200); the row is then found and deleted
      --  (HTTP 200) -- the full decode -> validate -> insert -> delete path.
      --  Re-running this suite reopens the persisted database and replays its
      --  uncheckpointed WAL, so the delete-by-key of a freshly written row on a
      --  re-run is the regression guard for the database primary-key-reuse
      --  recovery fix (a replayed committed deletion must stay deleted).
      declare
         Ctx : constant Web.Context.Request_Context := Web.Context.New_Context;
         Sid : constant String := New_Session;
         Probe : constant String := "RoundTripProbe";

         function Trim (S : String) return String is
           (Ada.Strings.Fixed.Trim (S, Ada.Strings.Both));

         function Find_Probe_Id return Natural is
         begin
            for P of App.Projects.Get_Projects loop
               if Trim (P.Name) = Probe then
                  return P.Id;
               end if;
            end loop;
            return 0;
         end Find_Probe_Id;

         Add_Resp : constant Web.Response.Response_Type :=
           App.Pages.Api_Add_Project
             (Csrf_Post
                ("/api/projects/add", "name=" & Probe & "&status=active", Sid),
              Ctx);
         New_Id : Natural;
      begin
         App.Projects.Initialize;
         Check (Web.Response.Status (Add_Resp) = 200,
                "http: add-project with a valid body succeeds (200)");
         New_Id := Find_Probe_Id;
         Check (New_Id > 0,
                "http: the added project is present in the database");
         if New_Id > 0 then
            declare
               Del_Resp : constant Web.Response.Response_Type :=
                 App.Pages.Api_Delete_Project
                   (Csrf_Post
                      ("/api/projects/delete", "id=" & Trim (New_Id'Image), Sid),
                    Ctx);
            begin
               Check (Web.Response.Status (Del_Resp) = 200,
                      "http: deleting the added project succeeds (200)");
            end;
            Check (Find_Probe_Id = 0,
                   "http: the deleted project is gone from the database");
         end if;
      end;

      New_Line;
      Put_Line ("Failures:" & Natural'Image (Fail_Count));
      Failures := Fail_Count;
   end Run;

end App.Http_Support;
