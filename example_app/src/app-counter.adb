with Ada.Strings.Fixed;

package body App.Counter is
   function Increment
     (State : in out App.State.App_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List
   is
      pragma Unreferenced (Event);
   begin
      State.Counter := State.Counter + 1;
      return Web.Patch.Single
        (Web.Patch.Set_Text
           ("counter-value",
            Ada.Strings.Fixed.Trim (Natural'Image (State.Counter), Ada.Strings.Both)));
   end Increment;
end App.Counter;
