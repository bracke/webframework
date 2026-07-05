with App.State;
with Web.Events;
with Web.Patch;

package App.Profile is
   --  Save a demo profile form.
   --  @param State Typed session state.
   --  @param Event Submit event.
   --  @return Patch list updating profile status.
   function Save
     (State : in out App.State.App_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List;
end App.Profile;
