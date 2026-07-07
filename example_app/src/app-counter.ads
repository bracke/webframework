with App.State;
with Web.Events;
with Web.Patch;

--  Counter feature handler.
package App.Counter is
   --  Increment the counter for the current session and return a single text patch.
   --  Increment the session counter.
   --  @param State Typed session state.
   --  @param Event Browser event.
   --  @return Patch list updating the counter text.
   function Increment
     (State : in out App.State.App_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List;
end App.Counter;
