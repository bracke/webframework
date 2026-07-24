with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Web.Response;
with Webframework_Authorization;
with App.Runtime;
with App.State;
with App.Authz;

package body App.Guards is

   --  A 303 redirect to the login page, used when an anonymous caller hits a
   --  protected route.
   function Login_Redirect return Web.Response.Response_Type is
      Result : Web.Response.Response_Type :=
        Web.Response.Create (303, "", "text/plain; charset=utf-8");
   begin
      Web.Response.Set_Header (Result, "Location", "/login");
      return Result;
   end Login_Redirect;

   --  The authorization guard: anonymous -> /login, denied -> 403, allowed ->
   --  proceed. The decision itself comes from App.Authz through the bridge.
   function App_Guard is new Webframework_Authorization.Guarded
     (Denied    => Web.Response.Forbidden,
      Anonymous => Login_Redirect,
      Decide    => App.Authz.Decide);

   --  Extraction channel for Resolve_Principal. With_State cannot return a
   --  value, so the callback writes here. Fine for this single-user example;
   --  a concurrent multi-user deployment would resolve the principal through a
   --  value-returning session query instead.
   Resolved_Principal : Unbounded_String;

   procedure Read_Principal (State : in out App.State.App_State) is
   begin
      Resolved_Principal := To_Unbounded_String (App.State.Get_Principal (State));
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
         App.Runtime.With_State (Session_Id, Read_Principal'Access);
         if Length (Resolved_Principal) > 0 then
            Web.Context.Set_Principal (Context, To_String (Resolved_Principal));
         end if;
      end if;

      return Web.Guard.Proceed;
   end Resolve_Principal;

   function Require_App_Access
     (Request : Web.Request.Request_Type;
      Context : in out Web.Context.Request_Context) return Web.Guard.Guard_Outcome
      renames App_Guard;

end App.Guards;
