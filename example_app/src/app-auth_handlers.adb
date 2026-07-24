with App.Auth;

package body App.Auth_Handlers is
   use Web.Patch;

   --  Handle login WebSocket action.
   function Handle_Login
     (State : in out App.State.App_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List is
      Username  : constant String :=
        Web.Events.Field_Or_Default (Event, "username", "");
      Password  : constant String :=
        Web.Events.Field_Or_Default (Event, "password", "");
      Principal : constant String := App.Auth.Authenticate (Username, Password);
   begin
      if Principal /= "" then
         --  Authenticated: open an identity session and record the principal,
         --  clearance and session token in state.
         App.State.Set_Authenticated
           (State, Principal, Username, App.Auth.Clearance_Of (Principal),
            App.Auth.Create_Session (Principal));
         return Patch_List'(Items => <>);
      else
         return Web.Patch.Single
           (Web.Patch.Set_Text ("error", "Invalid username or password"));
      end if;
   exception
      when others =>
         return Web.Patch.Single (Web.Patch.Set_Text ("error", "Login failed"));
   end Handle_Login;

   --  Handle logout WebSocket action.
   function Handle_Logout
     (State : in out App.State.App_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List is
      pragma Unreferenced (Event);
   begin
      App.State.Clear_Authentication (State);
      return Patch_List'(Items => <>);
   end Handle_Logout;
end App.Auth_Handlers;
