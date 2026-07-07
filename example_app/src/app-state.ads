--  Session-scoped state for the generated example application.
--  Keep this state minimal because it is held in memory for each websocket session.
package App.State is
   --  Counter and user id are intentionally tiny and per-session.
   --  Any durable data is kept in the separate Database layer.
   type App_State is record
      Counter : Natural := 0;
      User_Id : Natural := 1;
   end record;

   --  Create initial per-session UI state.
   --  @return Initial app state.
   function Initial_State return App_State;
end App.State;
