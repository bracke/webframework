--  Session-scoped state for the example application.
--  Keep this state minimal because it is held in memory for each session.
with Ada.Strings.Unbounded;

package App.State is
   --  The principal is the authorization principal id established at login; an
   --  empty principal means the session is anonymous. It is an opaque reference
   --  the app carries -- the framework never sees it.
   type App_State is record
      Counter       : Natural := 0;
      Principal     : Ada.Strings.Unbounded.Unbounded_String;
      Username      : Ada.Strings.Unbounded.Unbounded_String;
      Clearance     : Natural := 0;  --  the principal's role, resolved at login
      Session_Token : Ada.Strings.Unbounded.Unbounded_String;
      --  Opaque identity-session token, validated against the identity
      --  repository on every request (revocation/expiry take effect at once).
   end record;

   --  Create initial per-session UI state.
   --  @return Initial app state.
   function Initial_State return App_State;

   --  Record a successful authentication.
   --  @param State Session state to update.
   --  @param Principal The authorization principal id.
   --  @param Username The user's display name.
   --  @param Clearance The principal's clearance (role).
   --  @param Token The identity-session token.
   --  @return No return value.
   procedure Set_Authenticated
     (State     : in out App_State;
      Principal : String;
      Username  : String;
      Clearance : Natural;
      Token     : String);

   --  Clear authentication information for a session.
   --  @param State Session state to update.
   --  @return No return value.
   procedure Clear_Authentication (State : in out App_State);

   --  Check if a session is authenticated (carries a principal).
   --  @param State Session state.
   --  @return True if authenticated.
   function Is_Authenticated (State : App_State) return Boolean;

   --  Get the username from a session state.
   --  @param State Session state.
   --  @return Username or empty string if not authenticated.
   function Get_Username (State : App_State) return String;

   --  Get the authorization principal id from a session state.
   --  @param State Session state.
   --  @return Principal id or empty string if not authenticated.
   function Get_Principal (State : App_State) return String;

   --  Get the principal's clearance (role) from a session state.
   --  @param State Session state.
   --  @return Clearance, or 0 if not authenticated.
   function Get_Clearance (State : App_State) return Natural;

   --  Get the identity-session token from a session state.
   --  @param State Session state.
   --  @return Token, or empty string if not authenticated.
   function Get_Session_Token (State : App_State) return String;
end App.State;
