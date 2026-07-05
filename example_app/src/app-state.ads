package App.State is
   type App_State is record
      Counter : Natural := 0;
      User_Id : Natural := 1;
   end record;

   --  Create initial per-session UI state.
   --  @return Initial app state.
   function Initial_State return App_State;
end App.State;
