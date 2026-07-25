with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.Fixed;

with Web.Request;
with Web.Response;
with Web.Context;
with Web.Server;

with App.Pages;
with App.Runtime;
with App.State;
with App.Auth;
with App.Authz;
with App.Guards;

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

   --  Pending auth applied to a session by With_State.
   Pending_Principal : Unbounded_String;
   Pending_Clearance : Natural := 0;
   Pending_Token     : Unbounded_String;

   procedure Apply_Auth (State : in out App.State.App_State) is
   begin
      App.State.Set_Authenticated
        (State, To_String (Pending_Principal), "user",
         Pending_Clearance, To_String (Pending_Token));
   end Apply_Auth;

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
      Pending_Principal := To_Unbounded_String (Principal);
      Pending_Clearance := App.Auth.Clearance_Of (Principal);
      Pending_Token := To_Unbounded_String (App.Auth.Create_Session (Principal));
      App.Runtime.With_State (Sid, Apply_Auth'Access);
      return Sid;
   end Setup_Login;

   --  A returning user re-established from a remember-me cookie: a Basic
   --  (low-assurance) identity session with no fresh password presentation.
   --  Returns the framework session id (the cookie value).
   function Setup_Remembered (Principal : String) return String is
      Seed : constant Web.Request.Request_Type := Web.Request.Create ("GET", "/");
      Sid  : constant String := App.Runtime.Find_Or_Create_Session (Seed);
   begin
      Pending_Principal := To_Unbounded_String (Principal);
      Pending_Clearance := App.Auth.Clearance_Of (Principal);
      Pending_Token :=
        To_Unbounded_String (App.Auth.Create_Remembered_Session (Principal));
      App.Runtime.With_State (Sid, Apply_Auth'Access);
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
         Sid   : constant String := Setup_Login ("admin", "admin123");
         Token : constant String := To_String (Pending_Token);
      begin
         Check (Status_Of ("GET", "/secure", Sid) = 200,
                "http: a live session is admitted");
         App.Auth.Revoke_Session (Token);
         Check (Status_Of ("GET", "/secure", Sid) = 303,
                "http: a revoked identity session is anonymous at once");
      end;

      --  Add-project reject path: the handler decodes the urlencoded body via
      --  Web.Binding, validates it, and returns HTTP 400 with the structured
      --  issues as JSON. (Context is unused by the handler, so no session is
      --  needed; the reject paths never touch the database.)
      declare
         Ctx : constant Web.Context.Request_Context := Web.Context.New_Context;

         function Add_Project_Response
           (Body_Value : String) return Web.Response.Response_Type is
           (App.Pages.Api_Add_Project
              (Web.Request.Create
                 ("POST", "/api/projects/add", "", Body_Value), Ctx));

         function Body_Has (Response : Web.Response.Response_Type; Text : String)
           return Boolean is
           (Ada.Strings.Fixed.Index
              (Web.Response.Content_Body (Response), Text) > 0);

         No_Name    : constant Web.Response.Response_Type :=
           Add_Project_Response ("status=active");
         Empty_Body : constant Web.Response.Response_Type :=
           Add_Project_Response ("");
      begin
         Check (Web.Response.Status (No_Name) = 400,
                "http: add-project with no name is rejected (400)");
         Check (Body_Has (No_Name, "validation.not_empty"),
                "http: 400 body carries the structured issue id");
         Check (Body_Has (No_Name, "$.name"),
                "http: 400 body carries the field path");
         Check (Web.Response.Status (Empty_Body) = 400,
                "http: add-project with an empty body is rejected (400)");
      end;

      --  Delete and login reject paths: a non-positive / non-integer id and a
      --  blank username are rejected with 400 before any state change.
      declare
         Ctx : constant Web.Context.Request_Context := Web.Context.New_Context;
         Zero_Id : constant Web.Response.Response_Type :=
           App.Pages.Api_Delete_Project
             (Web.Request.Create ("POST", "/api/projects/delete", "", "id=0"),
              Ctx);
         Bad_Id : constant Web.Response.Response_Type :=
           App.Pages.Api_Delete_Project
             (Web.Request.Create ("POST", "/api/projects/delete", "", "id=abc"),
              Ctx);
         Blank_User : constant Web.Response.Response_Type :=
           App.Pages.Api_Login
             (Web.Request.Create ("POST", "/api/login", "", "username=&password=x"));
      begin
         Check (Web.Response.Status (Zero_Id) = 400,
                "http: delete with a non-positive id is rejected (400)");
         Check (Web.Response.Status (Bad_Id) = 400,
                "http: delete with a non-integer id is rejected (400)");
         Check (Web.Response.Status (Blank_User) = 400,
                "http: login with a blank username is rejected (400)");
      end;

      New_Line;
      Put_Line ("Failures:" & Natural'Image (Fail_Count));
      Failures := Fail_Count;
   end Run;

end App.Http_Support;
