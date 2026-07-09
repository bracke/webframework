with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with App.Auth;
with App.State;
with Web.Events;
with Web.Patch;

package body App.Auth_Handlers is
   use Ada.Strings.Fixed;
   use Ada.Strings.Unbounded;
   use Web.Patch;

   --  Handle login WebSocket action.
   function Handle_Login
     (State : in out App.State.App_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List is
      use App.Auth;
      Username : constant String := Web.Events.Field_Or_Default (Event, "username", "");
      Password : constant String := Web.Events.Field_Or_Default (Event, "password", "");
      User_Id : Natural;
      Result : Auth_Result;
   begin
      --  Authenticate user
      Authenticate (Username, Password, User_Id, Result);
      
      if Result = Success then
         --  Set authentication in state
         App.State.Set_Authenticated (State, User_Id, Username);
         --  Return empty patch list (state was modified directly)
         return Patch_List'(Items => <>);
      else
         --  Authentication failed, return error in patch
         return Web.Patch.Single (Web.Patch.Set_Text ("error", "Invalid username or password"));
      end if;
   exception
      when others =>
         return Web.Patch.Single (Web.Patch.Set_Text ("error", "Login failed"));
   end Handle_Login;

   --  Handle logout WebSocket action.
   function Handle_Logout
     (State : in out App.State.App_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List is
   begin
      --  Clear authentication from session state
      App.State.Clear_Authentication (State);
      --  Return empty patch list (state was modified directly)
      return Patch_List'(Items => <>);
   end Handle_Logout;
end App.Auth_Handlers;
