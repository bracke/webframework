with Ada.Strings.Fixed;

package body App.Counter is
   --  Business logic for counter increment.
   --  This function mutates only session state and returns the minimum patch needed.
   function Increment
     (State : in out App.State.App_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List
   is
      pragma Unreferenced (Event);
   begin
      --  Keep arithmetic simple and deterministic; rendering is handled by patch.
      State.Counter := State.Counter + 1;
      return Web.Patch.Single
        (Web.Patch.Set_Text
           ("counter-value",
            Ada.Strings.Fixed.Trim (Natural'Image (State.Counter), Ada.Strings.Both)));
   end Increment;
end App.Counter;
