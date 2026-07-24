with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line;

with Web.Request;
with Authorization.Evaluator;
with Authorization.Results;

with App.Identity;
with App.Auth;
with App.Authz;

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

   function Allowed
     (Principal : String; Request : Web.Request.Request_Type) return Boolean is
     (Ev.Enforcement_Of (App.Authz.Decide (Principal, Request)) in
        Rez.Authorized | Rez.Authorized_With_Requirements);
begin
   --  Identity password hashing (PBKDF2 verifier).
   declare
      Envelope : constant String := App.Identity.Hash_Password ("s3cret");
   begin
      Check (App.Identity.Verify_Password ("s3cret", Envelope),
             "identity: the correct password verifies");
      Check (not App.Identity.Verify_Password ("wrong", Envelope),
             "identity: a wrong password is rejected");
   end;

   --  The credential store: two users, fail-closed.
   App.Auth.Initialize;
   Check (App.Auth.Authenticate ("admin", "admin123") = "d.principal.admin",
          "auth: admin authenticates to its principal");
   Check (App.Auth.Authenticate ("viewer", "viewer123") = "d.principal.viewer",
          "auth: viewer authenticates to its principal");
   Check (App.Auth.Authenticate ("admin", "bad") = "",
          "auth: a wrong password fails closed");
   Check (App.Auth.Authenticate ("ghost", "x") = "",
          "auth: an unknown user fails closed");

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

   --  The tables plan, resolved per role.
   Check (App.Authz.Plan_Projects_Listing ("d.principal.admin").Ready,
          "plan: admin gets a ready plan");
   Check (not App.Authz.Plan_Projects_Listing ("d.principal.admin").Mask_Functions,
          "plan: admin sees the functions column");
   Check (App.Authz.Plan_Projects_Listing ("d.principal.viewer").Mask_Functions,
          "plan: viewer gets the functions column masked");
   Check (App.Authz.Plan_Projects_Listing ("d.principal.viewer").Scope_Applied,
          "plan: the authorization scope survives into the plan");

   New_Line;
   Put_Line ("Failures:" & Natural'Image (Failures));
   if Failures > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end App_Tests;
