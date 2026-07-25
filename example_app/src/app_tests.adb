with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line;
with Ada.Containers;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Validation.Results;
with App.Project_Validation;
with App.Login_Validation;

with Web.Request;
with Web.Context;
with Web.Events;
with Authorization.Evaluator;
with Authorization.Results;

with App.Auth;
with App.Authz;
with App.State;
with App.Guards;
with App.Query_Binding;
with App.Projects;

--  Regression tests for the example app's stack integration: identity password
--  hashing, the two-user credential store, and the role-based authorization
--  decisions and tables plan. Exit status is non-zero on any failure.
procedure App_Tests is
   package Ev  renames Authorization.Evaluator;
   package Rez renames Authorization.Results;
   use type Rez.Enforcement_Status;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Label : String) is
   begin
      if Cond then
         Put_Line ("OK   " & Label);
      else
         Put_Line ("FAIL " & Label);
         Failures := Failures + 1;
      end if;
   end Check;

   function View_Req return Web.Request.Request_Type is
     (Web.Request.Create ("GET", "/projects"));
   function Manage_Req return Web.Request.Request_Type is
     (Web.Request.Create ("POST", "/api/projects/delete"));

   --  Build the request context the guards would produce: principal, the
   --  clearance the user store records, and the assurance level the session was
   --  established at -- both carried as derived facts. Assurance defaults to
   --  INTERACTIVE, what a password login yields.
   function Context_For
     (Principal : String;
      Assurance : String := "INTERACTIVE") return Web.Context.Request_Context
   is
      Ctx : Web.Context.Request_Context := Web.Context.New_Context;
   begin
      if Principal /= "" then
         Web.Context.Set_Principal (Ctx, Principal);
         Web.Context.Set_Attribute
           (Ctx, "clearance", Natural'Image (App.Auth.Clearance_Of (Principal)));
         Web.Context.Set_Attribute (Ctx, "assurance", Assurance);
      end if;
      return Ctx;
   end Context_For;

   function Allowed
     (Principal : String; Request : Web.Request.Request_Type) return Boolean is
     (Ev.Enforcement_Of
        (App.Authz.Decide (Principal, Request, Context_For (Principal))) in
        Rez.Authorized | Rez.Authorized_With_Requirements);

   --  As Allowed, but with an explicit session assurance level -- to exercise
   --  the step-up gate independently of clearance.
   function Allowed_At
     (Principal : String;
      Request   : Web.Request.Request_Type;
      Assurance : String) return Boolean is
     (Ev.Enforcement_Of
        (App.Authz.Decide
           (Principal, Request, Context_For (Principal, Assurance))) in
        Rez.Authorized | Rez.Authorized_With_Requirements);

   function Plan_For (Principal : String) return App.Authz.Listing_Plan is
     (App.Authz.Plan_Projects_Listing
        (Principal, App.Auth.Clearance_Of (Principal)));
begin
   --  The identity-repository credential store: two users, fail-closed. Seeding
   --  creates real principals, accounts, bindings and password credentials;
   --  Authenticate runs through the repository's password verification.
   App.Auth.Initialize;
   Check (App.Auth.Authenticate ("admin", "admin123") = "d.principal.admin",
          "auth: admin authenticates to its principal");
   Check (App.Auth.Authenticate ("viewer", "viewer123") = "d.principal.viewer",
          "auth: viewer authenticates to its principal");
   Check (App.Auth.Authenticate ("admin", "bad") = "",
          "auth: a wrong password fails closed");
   Check (App.Auth.Authenticate ("ghost", "x") = "",
          "auth: an unknown user fails closed");

   --  Identity sessions: create, validate on every request, revoke.
   declare
      Token : constant String := App.Auth.Create_Session ("d.principal.admin");
   begin
      Check (Token /= "", "session: created for a valid principal");
      Check (App.Auth.Validate_Session (Token) = "d.principal.admin",
             "session: a live token validates to its principal");
      Check (App.Auth.Session_Assurance (Token) = "INTERACTIVE",
             "session: a password login yields an INTERACTIVE session");
      App.Auth.Revoke_Session (Token);
      Check (App.Auth.Validate_Session (Token) = "",
             "session: a revoked token no longer validates");
      Check (App.Auth.Session_Assurance (Token) = "",
             "session: a revoked token has no assurance");
      Check (App.Auth.Validate_Session ("garbage") = "",
             "session: a malformed token is rejected");
      Check (App.Auth.Session_Assurance ("garbage") = "",
             "session: a malformed token has no assurance");
      Check (App.Auth.Create_Session ("d.principal.ghost") = "",
             "session: no session for an unknown principal");
   end;

   --  A remembered (remember-me cookie) session is only BASIC assurance.
   declare
      R_Token : constant String :=
        App.Auth.Create_Remembered_Session ("d.principal.admin");
   begin
      Check (App.Auth.Validate_Session (R_Token) = "d.principal.admin",
             "session: a remembered token validates to its principal");
      Check (App.Auth.Session_Assurance (R_Token) = "BASIC",
             "session: a remembered login yields a BASIC session");
      App.Auth.Revoke_Session (R_Token);
   end;

   --  Role-based authorization.
   App.Authz.Initialize;
   Check (Allowed ("d.principal.admin", View_Req),
          "authz: admin may view");
   Check (Allowed ("d.principal.viewer", View_Req),
          "authz: viewer may view");
   Check (Allowed ("d.principal.admin", Manage_Req),
          "authz: admin may manage projects");
   Check (not Allowed ("d.principal.viewer", Manage_Req),
          "authz: viewer may NOT manage projects");
   Check (not Allowed ("", View_Req),
          "authz: an absent principal is denied");
   Check (not Allowed ("d.principal.ghost", Manage_Req),
          "authz: an unknown principal cannot manage");

   --  Assurance step-up gate: managing needs an interactive login, not just a
   --  high clearance. An administrator's clearance on a low-assurance session
   --  (e.g. a remembered cookie) may view but must not manage.
   Check (Allowed_At ("d.principal.admin", Manage_Req, "INTERACTIVE"),
          "authz: admin on an interactive session may manage");
   Check (not Allowed_At ("d.principal.admin", Manage_Req, "BASIC"),
          "authz: admin on a low-assurance session may NOT manage (step-up)");
   Check (Allowed_At ("d.principal.admin", View_Req, "BASIC"),
          "authz: a low-assurance session may still view");

   --  The assurance mapping's upper levels (identity ladder -> the engine's).
   --  Sensitive, Administrative and Service all clear the Substantial step-up;
   --  Anonymous and an unrecognised level do not (fail-closed).
   Check (Allowed_At ("d.principal.admin", Manage_Req, "SENSITIVE"),
          "authz: a SENSITIVE session may manage");
   Check (Allowed_At ("d.principal.admin", Manage_Req, "ADMINISTRATIVE"),
          "authz: an ADMINISTRATIVE session may manage");
   Check (Allowed_At ("d.principal.admin", Manage_Req, "SERVICE"),
          "authz: a SERVICE session may manage");
   Check (not Allowed_At ("d.principal.admin", Manage_Req, "ANONYMOUS"),
          "authz: an ANONYMOUS session may NOT manage");
   Check (not Allowed_At ("d.principal.admin", Manage_Req, "not-a-level"),
          "authz: an unrecognised assurance fails closed");

   --  The tables plan, resolved per role.
   Check (Plan_For ("d.principal.admin").Ready,
          "plan: admin gets a ready plan");
   Check (not Plan_For ("d.principal.admin").Mask_Functions,
          "plan: admin sees the functions column");
   Check (Plan_For ("d.principal.viewer").Mask_Functions,
          "plan: viewer gets the functions column masked");
   Check (Plan_For ("d.principal.viewer").Scope_Applied,
          "plan: the authorization scope survives into the plan");

   --  The scope is enforced in the query, not after: the scoped listing returns
   --  strictly fewer rows than the unscoped one, and every row it returns is
   --  Alire-tracked. (The seed mixes Alire and non-Alire projects.)
   App.Projects.Initialize;
   declare
      use type Ada.Containers.Count_Type;
      All_Rows : constant App.Projects.Project_Vectors.Vector :=
        App.Projects.Get_Projects (Alire_Only => False);
      Scoped   : constant App.Projects.Project_Vectors.Vector :=
        App.Projects.Get_Projects (Alire_Only => True);
      All_Alire : Boolean := True;
   begin
      for R of Scoped loop
         if not R.Has_Alire then
            All_Alire := False;
         end if;
      end loop;
      Check (Scoped.Length > 0, "scope: the scoped query returns rows");
      Check (Scoped.Length < All_Rows.Length,
             "scope: the Alire scope drops out-of-scope rows in the query");
      Check (All_Alire,
             "scope: every row the scoped query returns is Alire-tracked");
   end;

   --  Web.Binding: a typed query binder for the projects listing.
   declare
      use type App.Query_Binding.Page_Number;
      Full : constant App.Query_Binding.Projects_Query :=
        App.Query_Binding.Bind
          (Web.Request.Create ("GET", "/projects", "page=3&alire_only=true"));
      Empty : constant App.Query_Binding.Projects_Query :=
        App.Query_Binding.Bind (Web.Request.Create ("GET", "/projects"));
      Bad_Page : constant App.Query_Binding.Projects_Query :=
        App.Query_Binding.Bind
          (Web.Request.Create ("GET", "/projects", "page=abc"));
   begin
      Check (Full.Page = 3 and then Full.Alire_Only,
             "binding: typed query binds page and flag");
      Check (Empty.Page = 1 and then not Empty.Alire_Only,
             "binding: absent params use defaults");
      Check (Bad_Page.Page = 1,
             "binding: malformed page falls back to the default");
   end;

   --  The live (WebSocket) privileged action guard: like the HTTP manage path,
   --  it needs clearance AND an interactive session, not a remembered one.
   declare
      Dummy : constant Web.Events.Event :=
        Web.Events.Create
          (Web.Events.Click_Event, Element_Id => "btn",
           Action => "profile.save");
      Fresh_Tok : constant String :=
        App.Auth.Create_Session ("d.principal.admin");
      Remem_Tok : constant String :=
        App.Auth.Create_Remembered_Session ("d.principal.admin");
      Fresh_State : App.State.App_State;
      Remem_State : App.State.App_State;
   begin
      App.State.Set_Authenticated
        (Fresh_State, "d.principal.admin", "admin", 100, Fresh_Tok);
      App.State.Set_Authenticated
        (Remem_State, "d.principal.admin", "admin", 100, Remem_Tok);
      Check (App.Guards.Require_Admin_Action (Fresh_State, Dummy),
             "live: admin on an interactive session may run a privileged action");
      Check (not App.Guards.Require_Admin_Action (Remem_State, Dummy),
             "live: admin on a remembered session may NOT (step-up)");
      App.Auth.Revoke_Session (Fresh_Tok);
      App.Auth.Revoke_Session (Remem_Tok);
   end;

   --  Add-project form validation via the standalone Validation library.
   declare
      use App.Project_Validation;
      Good : constant Project_Input :=
        (Name         => To_Unbounded_String ("Ada Web"),
         Status       => To_Unbounded_String ("active"),
         Project_Type => To_Unbounded_String ("library"),
         Functions    => To_Unbounded_String ("http"));
      Bad : constant Project_Input :=
        (Name         => Null_Unbounded_String,   --  required
         Status       => To_Unbounded_String ("active"),
         Project_Type => Null_Unbounded_String,
         Functions    => Null_Unbounded_String);
      Good_Result : constant Validation.Results.Result := Validate (Good);
      Bad_Result  : constant Validation.Results.Result := Validate (Bad);
   begin
      Check (not Validation.Results.Has_Errors (Good_Result),
             "validation: a well-formed project passes");
      Check (Validation.Results.Has_Errors (Bad_Result),
             "validation: an empty name is rejected");
      Check (Validation.Results.Error_Count (Bad_Result) = 1,
             "validation: exactly the name/required error");
   end;

   --  Delete-command and login-input validation.
   declare
      use App.Project_Validation;
      Del_Ok  : constant Validation.Results.Result := Validate_Delete ((Id => 7));
      Del_Bad : constant Validation.Results.Result := Validate_Delete ((Id => 0));
      User_Ok : constant Validation.Results.Result :=
        App.Login_Validation.Validate_Username ("alice");
      User_Bad : constant Validation.Results.Result :=
        App.Login_Validation.Validate_Username ("   ");
   begin
      Check (not Validation.Results.Has_Errors (Del_Ok),
             "validation: a positive delete id passes");
      Check (Validation.Results.Has_Errors (Del_Bad),
             "validation: a non-positive delete id is rejected");
      Check (not Validation.Results.Has_Errors (User_Ok),
             "validation: a well-formed username passes");
      Check (Validation.Results.Has_Errors (User_Bad),
             "validation: a blank username is rejected");
   end;

   New_Line;
   Put_Line ("Failures:" & Natural'Image (Failures));
   if Failures > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end App_Tests;
