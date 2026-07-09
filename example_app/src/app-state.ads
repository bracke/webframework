--  Session-scoped state for the generated example application.
--  Keep this state minimal because it is held in memory for each websocket session.
package App.State is
   --  Counter and user id are intentionally tiny and per-session.
   --  Any durable data is kept in the separate Database layer.
   type App_State is record
      Counter : Natural := 0;
      User_Id : Natural := 0;  --  0 means not authenticated
      Username : String (1 .. 50) := (others => ' ');
      Is_Authenticated : Boolean := False;
   end record;

   --  Create initial per-session UI state.
   --  @return Initial app state.
   function Initial_State return App_State;

   --  Set authentication information for a session.
   --  @param State Session state to update.
   --  @param User_Id The user's ID.
   --  @param Username The user's username.
   --  @return No return value.
   procedure Set_Authenticated (State : in out App_State; User_Id : Natural; Username : String);

   --  Clear authentication information for a session.
   --  @param State Session state to update.
   --  @return No return value.
   procedure Clear_Authentication (State : in out App_State);

   --  Check if a session is authenticated.
   --  @param State Session state.
   --  @return True if authenticated.
   function Is_Authenticated (State : App_State) return Boolean;

   --  Get the username from a session state.
   --  @param State Session state.
   --  @return Username or empty string if not authenticated.
   function Get_Username (State : App_State) return String;

   --  Get the user ID from a session state.
   --  @param State Session state.
   --  @return User ID or 0 if not authenticated.
   function Get_User_Id (State : App_State) return Natural;
end App.State;
