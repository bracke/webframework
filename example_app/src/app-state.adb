with Ada.Strings.Fixed;

package body App.State is
   use Ada.Strings.Fixed;

   --  Construct a deterministic baseline for new websocket sessions.
   --  This function is called by Web.Live through the generic Initial_State hook.
   function Initial_State return App_State is
   begin
      return (Counter => 0, User_Id => 0, Username => (others => ' '), Is_Authenticated => False);
   end Initial_State;

   --  Set authentication information for a session.
   procedure Set_Authenticated (State : in out App_State; User_Id : Natural; Username : String) is
   begin
      State.User_Id := User_Id;
      State.Username := (1 .. State.Username'Length => ' ');
      if Username'Length <= State.Username'Length then
         State.Username (1 .. Username'Length) := Username;
      else
         State.Username (1 .. State.Username'Length) :=
           Username (Username'First .. Username'First + State.Username'Length - 1);
      end if;
      State.Is_Authenticated := True;
   end Set_Authenticated;

   --  Clear authentication information for a session.
   procedure Clear_Authentication (State : in out App_State) is
   begin
      State.User_Id := 0;
      State.Username := (others => ' ');
      State.Is_Authenticated := False;
   end Clear_Authentication;

   --  Check if a session is authenticated.
   function Is_Authenticated (State : App_State) return Boolean is
   begin
      return State.Is_Authenticated;
   end Is_Authenticated;

   --  Get the username from a session state.
   function Get_Username (State : App_State) return String is
   begin
      if State.Is_Authenticated then
         return Trim (State.Username, Ada.Strings.Both);
      else
         return "";
      end if;
   end Get_Username;

   --  Get the user ID from a session state.
   function Get_User_Id (State : App_State) return Natural is
   begin
      return State.User_Id;
   end Get_User_Id;
end App.State;
