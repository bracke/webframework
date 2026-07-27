with Web.Request;
with Web.Response;

with Navigation.Routes;
with Navigation.Params;
with Navigation.Menu;
with Navigation.Limits;

--  Bridge from the navigation library to the webframework HTTP handler seam.
--
--  navigation is headless: it builds URLs, resolves the active menu item, and
--  produces breadcrumb/menu data, but it knows nothing of requests or
--  responses. webframework, in turn, depends on none of navigation's crates.
--  This crate is the only unit that depends on both, so an application can:
--
--    * redirect to a named route (type-safe reverse URLs, never a hand-typed
--      path), and
--    * resolve the active menu item straight from the incoming request path.
--
--  Everything is fail-closed: a reverse-URL build that fails yields a caller
--  supplied error response (default 500), never a redirect to a wrong or empty
--  URL. Nothing here raises.
package Webframework_Navigation is

   --  The reverse URL for a named route, or "" if the route is unknown, a
   --  required param is missing, or the URL would exceed the limit. Prefer
   --  Redirect_To for redirects; use this when embedding a URL in a body.
   function Location_Of
     (Routes : Navigation.Routes.Table;
      Name   : String;
      Params : Navigation.Params.Set;
      Limits : Navigation.Limits.Limits :=
        Navigation.Limits.Default_Limits) return String;

   --  A redirect response to a named route (303 See Other by default; pass 302
   --  or 307 as needed). If the URL cannot be built the request is not
   --  redirected to a wrong target — On_Error is returned instead.
   function Redirect_To
     (Routes   : Navigation.Routes.Table;
      Name     : String;
      Params   : Navigation.Params.Set;
      Status   : Positive := 303;
      On_Error : Web.Response.Response_Type :=
        Web.Response.Internal_Server_Error;
      Limits   : Navigation.Limits.Limits :=
        Navigation.Limits.Default_Limits) return Web.Response.Response_Type;

   --  Redirect to a parameterless named route.
   function Redirect_To
     (Routes   : Navigation.Routes.Table;
      Name     : String;
      Status   : Positive := 303;
      On_Error : Web.Response.Response_Type :=
        Web.Response.Internal_Server_Error;
      Limits   : Navigation.Limits.Limits :=
        Navigation.Limits.Default_Limits) return Web.Response.Response_Type;

   --  The active menu item for this request (matched against its path), or
   --  Navigation.Menu.No_Item if nothing matches.
   function Active_For
     (Menu    : Navigation.Menu.Menu;
      Routes  : Navigation.Routes.Table;
      Request : Web.Request.Request_Type;
      Limits  : Navigation.Limits.Limits :=
        Navigation.Limits.Default_Limits) return Navigation.Menu.Item_Ref;

end Webframework_Navigation;
