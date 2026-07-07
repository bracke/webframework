with App.Store;
with App.Templates;
with Ada.Exceptions;
with Web.Logging;
with Web.Html;

package body App.Todo is
   --  Add action is a short write path:
   --  validate input, persist one item, refresh todo list fragment.
   function Add
     (State : in out App.State.App_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List
   is
      pragma Unreferenced (State);
      Title : constant String :=
        Web.Events.Field_Or_Default (Event, "title", "");
      Patches : Web.Patch.Patch_List;
   begin
      --  Keep user-visible validation local to one status target.
      if not Web.Events.Has_Non_Empty_Field (Event, "title") then
         return Web.Patch.Single (Web.Patch.Set_Text ("todo-status", "Todo text is required"));
      end if;

      --  Store through App.Store to keep persistence policy out of the handler.
      App.Store.Add_Todo (Title);
      Patches :=
        Web.Patch.Single
          (Web.Patch.Replace_HTML
             ("todo-list",
              Web.Html.Trusted (App.Templates.Render_Todo_Items)));

      --  Return multiple small patches to avoid unnecessary full-page updates.
      Web.Patch.Append (Patches, Web.Patch.Set_Text ("todo-status", "Added " & Title));
      Web.Patch.Append (Patches, Web.Patch.Set_Value ("title", ""));
      return Patches;
   exception
      when Error : others =>
         --  Do not leak persistence details to client; keep a stable error message.
         Web.Logging.Error
           ("todo.add failed: " & Ada.Exceptions.Exception_Message (Error));
         return Web.Patch.Single
           (Web.Patch.Set_Text
              ("todo-status", "Unable to save todo item; please retry"));
   end Add;
end App.Todo;
