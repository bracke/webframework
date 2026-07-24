with Ada.Strings.Hash;
with Web.Events;
with Web.Patch;

generic
   type App_State is private;
package Web.Dispatcher is
   type Handler_Access is access function
     (State : in out App_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List;

   --  A per-action authorization guard: returns True to allow the handler to
   --  run, False to reject the action (Dispatch then produces no patches). It
   --  reads the session state and the event but does not mutate state.
   type Action_Guard is access function
     (State : App_State;
      Event : Web.Events.Event) return Boolean;

   --  Register an action handler.
   --  @param Action Action name from browser events.
   --  @param Handler Handler function.
   --  @return No return value.
   procedure Register (Action : String; Handler : Handler_Access);

   --  Register an action handler protected by an authorization guard. The guard
   --  runs before the handler on every dispatch of the action; a rejected action
   --  produces no patches.
   --  @param Action Action name from browser events.
   --  @param Handler Handler function.
   --  @param Guard Authorization guard; must not be null.
   --  @return No return value.
   procedure Register
     (Action  : String;
      Handler : Handler_Access;
      Guard   : Action_Guard);

   --  Dispatch an event to a registered handler.
   --  @param State Typed application state.
   --  @param Event Browser event.
   --  @return Patches produced by the handler, or an empty list.
   function Dispatch
     (State : in out App_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List;
end Web.Dispatcher;
