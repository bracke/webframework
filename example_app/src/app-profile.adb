package body App.Profile is
   --  Persist profile state in-memory for now; returns user-visible validation feedback.
   function Save
     (State : in out App.State.App_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List
   is
      pragma Unreferenced (State);
      Name : constant String := Web.Events.Field_Or_Default (Event, "name", "");
   begin
      --  Minimal validation with explicit error message patch.
      if not Web.Events.Has_Non_Empty_Field (Event, "name") then
         return Web.Patch.Single (Web.Patch.Set_Text ("profile-status", "Name is required"));
      end if;

      --  Example success path returns only a textual confirmation patch.
      return Web.Patch.Single (Web.Patch.Set_Text ("profile-status", "Saved " & Name));
   end Save;
end App.Profile;
