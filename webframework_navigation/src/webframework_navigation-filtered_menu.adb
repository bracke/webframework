with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Web.Html;

with Navigation.Active;
with Navigation.Visibility.Filter;

package body Webframework_Navigation.Filtered_Menu is

   package NM renames Navigation.Menu;

   use type NM.Item_Ref;
   use type NM.Item_Kind;

   package Vis is new Navigation.Visibility.Filter (Viewer, Can_See);

   function Render
     (Menu         : Navigation.Menu.Menu;
      Routes       : Navigation.Routes.Table;
      Viewer_Value : Viewer;
      Active       : Navigation.Menu.Item_Ref := Navigation.Menu.No_Item;
      Limits       : Navigation.Limits.Limits :=
        Navigation.Limits.Default_Limits) return String
   is
      Out_S : Unbounded_String;

      function Item_Class (Item : NM.Item_Ref) return String is
      begin
         if NM.Present (Active) and then Item = Active then
            return " class=""active""";
         elsif NM.Present (Active)
           and then Navigation.Active.On_Trail (Menu, Item, Active)
         then
            return " class=""active-trail""";
         else
            return "";
         end if;
      end Item_Class;

      --  Walk only the visible siblings (the filtered traversal skips hidden
      --  items; descending only into visible items hides subtrees fail-closed).
      procedure Render_List (First : NM.Item_Ref) is
         Cur : NM.Item_Ref := First;
      begin
         if not NM.Present (Cur) then
            return;
         end if;
         Append (Out_S, "<ul>");
         while NM.Present (Cur) loop
            Append (Out_S, "<li" & Item_Class (Cur) & ">");
            declare
               Label : constant String :=
                 Web.Html.Escape_Text (NM.Label (Menu, Cur));
            begin
               if NM.Kind (Menu, Cur) = NM.Heading then
                  Append (Out_S, "<span>" & Label & "</span>");
               else
                  Append (Out_S, "<a href="""
                          & Web.Html.Escape_Attribute
                              (Navigation.Active.Resolved_Url
                                 (Menu, Routes, Cur, Limits))
                          & """>" & Label & "</a>");
               end if;
            end;
            Render_List (Vis.First_Visible_Child (Menu, Cur, Viewer_Value));
            Append (Out_S, "</li>");
            Cur := Vis.Next_Visible_Sibling (Menu, Cur, Viewer_Value);
         end loop;
         Append (Out_S, "</ul>");
      end Render_List;

   begin
      Render_List (Vis.First_Visible_Top (Menu, Viewer_Value));
      return To_String (Out_S);
   end Render;

end Webframework_Navigation.Filtered_Menu;
