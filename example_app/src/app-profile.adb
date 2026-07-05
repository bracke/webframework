with Web.Html;

package body App.Profile is
   function Save
     (State : in out App.State.App_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List
   is
      pragma Unreferenced (State);
      Name : constant String := Web.Events.Field (Event, "name");
   begin
      if Name'Length = 0 then
         return Web.Patch.Single (Web.Patch.Set_Text ("profile-status", "Name is required"));
      end if;

      return Web.Patch.Single
        (Web.Patch.Set_Text ("profile-status", "Saved " & Web.Html.Escape_Text (Name)));
   end Save;
end App.Profile;
