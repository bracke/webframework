with Web.Response;

--  Navigation for the app, over the navigation library + webframework_navigation
--  bridge. One named route table drives reverse URLs (so a redirect targets a
--  route name, not a hand-typed path), and one menu drives the nav bar: the
--  active page is highlighted from the request path, and items are filtered by
--  the viewer's clearance (fail-closed for anonymous) -- navigation's visibility
--  seam wired to the app's authorization.
package App.Nav is

   --  Build the route table and menu once, at startup.
   procedure Setup;

   --  A redirect response to a named route (reverse URL building).
   function Redirect
     (Name : String; Status : Positive := 303) return Web.Response.Response_Type;

   --  The menu HTML for a request path: the active item highlighted, items the
   --  viewer's Clearance does not meet omitted.
   function Menu_Html
     (Current_Path : String; Clearance : Natural) return String;

end App.Nav;
