--  Authentication handlers for login/logout actions.
with App.State;
with Web.Events;
with Web.Patch;

package App.Auth_Handlers is
   --  Handle login WebSocket action.
   --  @param State Session state.
   --  @param Event WebSocket event containing username and password.
   --  @return Patch list for state updates.
   function Handle_Login
     (State : in out App.State.App_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List;

   --  Handle logout WebSocket action.
   --  @param State Session state.
   --  @param Event WebSocket event.
   --  @return Patch list for state updates.
   function Handle_Logout
     (State : in out App.State.App_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List;
end App.Auth_Handlers;
