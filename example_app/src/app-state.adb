package body App.State is
   function Initial_State return App_State is
   begin
      return (Counter => 0, User_Id => 1);
   end Initial_State;
end App.State;
