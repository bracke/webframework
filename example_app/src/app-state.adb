package body App.State is
   --  Construct a deterministic baseline for new websocket sessions.
   --  This function is called by Web.Live through the generic Initial_State hook.
   function Initial_State return App_State is
   begin
      return (Counter => 0, User_Id => 1);
   end Initial_State;
end App.State;
