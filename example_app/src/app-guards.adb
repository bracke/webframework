with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Web.Response;
with Webframework_Authorization;
with Identity.Assurance.Levels;
with App.Runtime;
with App.Auth;
with App.Authz;
with App.Nav;
pragma Elaborate_All (App.Nav);
--  App.Nav's routes must be built before this body instantiates the guard,
--  which captures the anonymous->login reverse-URL redirect at elaboration.

package body App.Guards is

   --  A 303 redirect to the login page (by route name), used when an anonymous
   --  caller hits a protected route.
   function Login_Redirect return Web.Response.Response_Type is
     (App.Nav.Redirect ("login"));

   --  The authorization guard: anonymous -> /login, denied -> 403, allowed ->
   --  proceed. The decision itself comes from App.Authz through the bridge.
   function App_Guard is new Webframework_Authorization.Guarded
     (Denied    => Web.Response.Forbidden,
      Anonymous => Login_Redirect,
      Decide    => App.Authz.Decide);

   --  The same policy for API endpoints: a JSON/XHR caller gets 401/403, not a
   --  page redirect.
   function App_Guard_Api is new Webframework_Authorization.Guarded
     (Denied    => Web.Response.Forbidden,
      Anonymous => Web.Response.Unauthorized,
      Decide    => App.Authz.Decide);

   --  Extraction channel for Resolve_Principal. With_State cannot return a
   --  value, so the callback writes here. Fine for this single-user example;
   --  a concurrent multi-user deployment would resolve the principal through a
   --  value-returning session query instead.
   Resolved_Principal : Unbounded_String;
   Resolved_Clearance : Natural := 0;
   Resolved_Token     : Unbounded_String;

   procedure Read_Principal (State : in out App.State.App_State) is
   begin
      Resolved_Principal := To_Unbounded_String (App.State.Get_Principal (State));
      Resolved_Clearance := App.State.Get_Clearance (State);
      Resolved_Token := To_Unbounded_String (App.State.Get_Session_Token (State));
   end Read_Principal;

   function Resolve_Principal
     (Request : Web.Request.Request_Type;
      Context : in out Web.Context.Request_Context) return Web.Guard.Guard_Outcome
   is
      Session_Id : constant String := App.Runtime.Require_Session (Request);
   begin
      if Session_Id'Length > 0 then
         Web.Context.Set_Session (Context, Session_Id);
         Resolved_Principal := Null_Unbounded_String;
         Resolved_Clearance := 0;
         Resolved_Token := Null_Unbounded_String;
         App.Runtime.With_State (Session_Id, Read_Principal'Access);
         --  The stored principal is trusted only while its identity session is
         --  still live: validate the token against the identity repository on
         --  every request, so a revoked or expired session is anonymous at once.
         if Length (Resolved_Principal) > 0
           and then Length (Resolved_Token) > 0
           and then App.Auth.Validate_Session (To_String (Resolved_Token))
                      = To_String (Resolved_Principal)
         then
            Web.Context.Set_Principal (Context, To_String (Resolved_Principal));
            --  Carry the role as a derived fact; the authorization guard reads
            --  it from the context rather than mapping principals to roles.
            Web.Context.Set_Attribute
              (Context, "clearance", Natural'Image (Resolved_Clearance));
            --  Carry the session's assurance level as a second derived fact, so
            --  the policy can demand a step-up (an interactive login) for a
            --  privileged action -- not merely a high enough clearance.
            Web.Context.Set_Attribute
              (Context, "assurance",
               App.Auth.Session_Assurance (To_String (Resolved_Token)));
         end if;
      end if;

      return Web.Guard.Proceed;
   end Resolve_Principal;

   function Require_App_Access
     (Request : Web.Request.Request_Type;
      Context : in out Web.Context.Request_Context) return Web.Guard.Guard_Outcome
      renames App_Guard;

   function Require_App_Access_Api
     (Request : Web.Request.Request_Type;
      Context : in out Web.Context.Request_Context) return Web.Guard.Guard_Outcome
      renames App_Guard_Api;

   Admin_Clearance : constant Natural := 100;

   package ILvl renames Identity.Assurance.Levels;
   use type ILvl.Assurance_Level;

   --  True iff Text names an identity assurance level of at least Interactive.
   --  Fail-closed: an empty, revoked-session ("") or unrecognised level is not
   --  enough for a step-up.
   function Interactive_Or_Stronger (Text : String) return Boolean is
   begin
      return ILvl.Assurance_Level'Value (Text) >= ILvl.Interactive;
   exception
      when others =>
         return False;
   end Interactive_Or_Stronger;

   function Require_Admin_Action
     (State : App.State.App_State;
      Event : Web.Events.Event) return Boolean
   is
      pragma Unreferenced (Event);
      --  Read the session's assurance live, so a revoked session also fails.
      Assurance : constant String :=
        App.Auth.Session_Assurance (App.State.Get_Session_Token (State));
   begin
      --  Clearance AND a step-up: the live privileged action, like the HTTP
      --  manage path, needs an interactive session -- not merely admin
      --  clearance on a remembered, low-assurance one.
      return App.State.Get_Clearance (State) >= Admin_Clearance
        and then Interactive_Or_Stronger (Assurance);
   end Require_Admin_Action;

end App.Guards;
