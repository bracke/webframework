with Navigation.Menu;
with Navigation.Routes;
with Navigation.Limits;
with Navigation.Visibility;

--  Visibility-filtered menu rendering. Instantiate with your viewer/context type
--  and a Can_See predicate (the same seam Navigation.Visibility.Filter uses, so
--  an app wires Authorization.Capabilities in here); Render then emits the menu
--  HTML with hidden items — and their whole subtrees — omitted, fail-closed:
--  only a Visible verdict shows an item, Hidden and Indeterminate both hide it.
generic
   type Viewer (<>) is limited private;
   with function Can_See
     (Key : String; V : Viewer) return Navigation.Visibility.Visibility;
package Webframework_Navigation.Filtered_Menu is

   --  The menu as a nested <ul> containing only the items visible to Viewer_Value.
   --  Active highlighting works exactly as in Webframework_Navigation.Render_Menu.
   function Render
     (Menu         : Navigation.Menu.Menu;
      Routes       : Navigation.Routes.Table;
      Viewer_Value : Viewer;
      Active       : Navigation.Menu.Item_Ref := Navigation.Menu.No_Item;
      Limits       : Navigation.Limits.Limits :=
        Navigation.Limits.Default_Limits) return String;

end Webframework_Navigation.Filtered_Menu;
