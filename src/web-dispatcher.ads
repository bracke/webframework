with Ada.Containers.Indefinite_Ordered_Maps;
with Web.Events;
with Web.Patch;

generic
   type App_State is private;
package Web.Dispatcher is
   type Handler_Access is access function
     (State : in out App_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List;

   --  Register an action handler.
   --  @param Action Action name from browser events.
   --  @param Handler Handler function.
   --  @return No return value.
   procedure Register (Action : String; Handler : Handler_Access);

   --  Dispatch an event to a registered handler.
   --  @param State Typed application state.
   --  @param Event Browser event.
   --  @return Patches produced by the handler, or an empty list.
   function Dispatch
     (State : in out App_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List;
end Web.Dispatcher;
