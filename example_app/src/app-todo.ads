with App.State;
with Web.Events;
with Web.Patch;

package App.Todo is
   --  Add a todo from a submitted form.
   --  @param State Typed session state.
   --  @param Event Submit event.
   --  @return Patch list replacing the todo list.
   function Add
     (State : in out App.State.App_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List;
end App.Todo;
