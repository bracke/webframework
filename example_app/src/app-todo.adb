with App.Store;
with App.Templates;
with Web.Html;

package body App.Todo is
   function Add
     (State : in out App.State.App_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List
   is
      pragma Unreferenced (State);
      Title : constant String := Web.Events.Field (Event, "title");
   begin
      if Title'Length > 0 then
         App.Store.Add_Todo (Title);
      end if;

      return Web.Patch.Single
        (Web.Patch.Replace_HTML
           ("todo-list",
            Web.Html.Trusted (App.Templates.Render_Todo_Items)));
   end Add;
end App.Todo;
