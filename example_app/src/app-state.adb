with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body App.State is

   --  Construct a deterministic baseline for new sessions. Called by Web.Live
   --  through the generic Initial_State hook.
   function Initial_State return App_State is
   begin
      return (Counter => 0, Principal => Null_Unbounded_String,
              Username => Null_Unbounded_String);
   end Initial_State;

   procedure Set_Authenticated
     (State : in out App_State; Principal : String; Username : String) is
   begin
      State.Principal := To_Unbounded_String (Principal);
      State.Username  := To_Unbounded_String (Username);
   end Set_Authenticated;

   procedure Clear_Authentication (State : in out App_State) is
   begin
      State.Principal := Null_Unbounded_String;
      State.Username  := Null_Unbounded_String;
   end Clear_Authentication;

   function Is_Authenticated (State : App_State) return Boolean is
   begin
      return Length (State.Principal) > 0;
   end Is_Authenticated;

   function Get_Username (State : App_State) return String is
   begin
      return To_String (State.Username);
   end Get_Username;

   function Get_Principal (State : App_State) return String is
   begin
      return To_String (State.Principal);
   end Get_Principal;

end App.State;
