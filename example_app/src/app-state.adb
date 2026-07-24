with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body App.State is

   --  Construct a deterministic baseline for new sessions. Called by Web.Live
   --  through the generic Initial_State hook.
   function Initial_State return App_State is
   begin
      return (Counter => 0, Principal => Null_Unbounded_String,
              Username => Null_Unbounded_String, Clearance => 0,
              Session_Token => Null_Unbounded_String);
   end Initial_State;

   procedure Set_Authenticated
     (State     : in out App_State;
      Principal : String;
      Username  : String;
      Clearance : Natural;
      Token     : String) is
   begin
      State.Principal     := To_Unbounded_String (Principal);
      State.Username      := To_Unbounded_String (Username);
      State.Clearance     := Clearance;
      State.Session_Token := To_Unbounded_String (Token);
   end Set_Authenticated;

   procedure Clear_Authentication (State : in out App_State) is
   begin
      State.Principal     := Null_Unbounded_String;
      State.Username      := Null_Unbounded_String;
      State.Clearance     := 0;
      State.Session_Token := Null_Unbounded_String;
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

   function Get_Clearance (State : App_State) return Natural is
   begin
      return State.Clearance;
   end Get_Clearance;

   function Get_Session_Token (State : App_State) return String is
   begin
      return To_String (State.Session_Token);
   end Get_Session_Token;

end App.State;
