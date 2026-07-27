with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Web.Html;

with Navigation.Active;

package body Webframework_Navigation is

   use type Navigation.Routes.Build_Status;
   use type Navigation.Menu.Item_Ref;
   use type Navigation.Menu.Item_Kind;

   package NM renames Navigation.Menu;
   package NB renames Navigation.Breadcrumbs;

   function Location_Of
     (Routes : Navigation.Routes.Table;
      Name   : String;
      Params : Navigation.Params.Set;
      Limits : Navigation.Limits.Limits :=
        Navigation.Limits.Default_Limits) return String
   is
      Buf    : String (1 .. Natural (Limits.Max_Url_Bytes));
      Last   : Natural;
      Status : Navigation.Routes.Build_Status;
   begin
      Navigation.Routes.Build (Routes, Name, Params, Buf, Last, Status, Limits);
      if Status = Navigation.Routes.Build_Ok then
         return Buf (1 .. Last);
      else
         return "";
      end if;
   end Location_Of;

   function Redirect_To
     (Routes   : Navigation.Routes.Table;
      Name     : String;
      Params   : Navigation.Params.Set;
      Status   : Positive := 303;
      On_Error : Web.Response.Response_Type :=
        Web.Response.Internal_Server_Error;
      Limits   : Navigation.Limits.Limits :=
        Navigation.Limits.Default_Limits) return Web.Response.Response_Type
   is
      Url : constant String := Location_Of (Routes, Name, Params, Limits);
   begin
      if Url'Length = 0 then
         return On_Error;
      end if;
      declare
         R : Web.Response.Response_Type := Web.Response.Create (Status, "");
      begin
         Web.Response.Set_Header (R, "Location", Url);
         return R;
      end;
   end Redirect_To;

   function Redirect_To
     (Routes   : Navigation.Routes.Table;
      Name     : String;
      Status   : Positive := 303;
      On_Error : Web.Response.Response_Type :=
        Web.Response.Internal_Server_Error;
      Limits   : Navigation.Limits.Limits :=
        Navigation.Limits.Default_Limits) return Web.Response.Response_Type
   is
      Empty : Navigation.Params.Set (0, 0);
   begin
      return Redirect_To (Routes, Name, Empty, Status, On_Error, Limits);
   end Redirect_To;

   function Active_For
     (Menu    : Navigation.Menu.Menu;
      Routes  : Navigation.Routes.Table;
      Request : Web.Request.Request_Type;
      Limits  : Navigation.Limits.Limits :=
        Navigation.Limits.Default_Limits) return Navigation.Menu.Item_Ref is
     (Navigation.Active.Resolve
        (Menu, Routes, Web.Request.Path (Request), Limits));

   function Render_Breadcrumbs
     (Trail : Navigation.Breadcrumbs.Trail;
      Class : String := "breadcrumbs") return String
   is
      Out_S : Unbounded_String;
   begin
      Append (Out_S, "<nav class=""" & Web.Html.Escape_Attribute (Class)
              & """><ol>");
      for I in 1 .. NB.Count (Trail) loop
         Append (Out_S, "<li>");
         if NB.Has_Link (Trail, I) then
            Append (Out_S, "<a href="""
                    & Web.Html.Escape_Attribute (NB.Url (Trail, I)) & """>"
                    & Web.Html.Escape_Text (NB.Label (Trail, I)) & "</a>");
         else
            Append (Out_S, Web.Html.Escape_Text (NB.Label (Trail, I)));
         end if;
         Append (Out_S, "</li>");
      end loop;
      Append (Out_S, "</ol></nav>");
      return To_String (Out_S);
   end Render_Breadcrumbs;

   function Render_Menu
     (Menu   : Navigation.Menu.Menu;
      Routes : Navigation.Routes.Table;
      Active : Navigation.Menu.Item_Ref := Navigation.Menu.No_Item;
      Limits : Navigation.Limits.Limits :=
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

      --  Render a sibling list and each item's descendants.
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
            Render_List (NM.First_Child (Menu, Cur));
            Append (Out_S, "</li>");
            Cur := NM.Next_Sibling (Menu, Cur);
         end loop;
         Append (Out_S, "</ul>");
      end Render_List;

   begin
      Render_List (NM.First_Top (Menu));
      return To_String (Out_S);
   end Render_Menu;

end Webframework_Navigation;
