with Navigation.Active;

package body Webframework_Navigation is

   use type Navigation.Routes.Build_Status;

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

end Webframework_Navigation;
