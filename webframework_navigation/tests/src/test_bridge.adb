with Ada.Text_IO;     use Ada.Text_IO;
with Ada.Command_Line;

with Web.Request;
with Web.Response;
with Web.Server;

with Navigation.Routes;
with Navigation.Params;
with Navigation.Menu;  use Navigation.Menu;

with Webframework_Navigation;

--  Verifies the navigation -> webframework bridge: type-safe reverse-URL
--  redirects (fail-closed on a bad build) and active-item resolution straight
--  from a request path.
procedure Test_Bridge is

   package WN renames Webframework_Navigation;
   package R  renames Navigation.Routes;
   package P  renames Navigation.Params;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Label : String) is
   begin
      if Cond then
         Put_Line ("ok   " & Label);
      else
         Put_Line ("FAIL " & Label);
         Failures := Failures + 1;
      end if;
   end Check;

   CRLF : constant String := (Character'Val (13), Character'Val (10));

   Routes : R.Table (8, 256);
   Menu   : Navigation.Menu.Menu (8, 256);
   Added  : Boolean;
   Docs, Ignored : Item_Ref;

begin
   R.Add (Routes, "home", "/", Added);
   R.Add (Routes, "user.show", "/users/:id", Added);
   R.Finalize (Routes);

   --  Location_Of: reverse URL with a param.
   declare
      Ps : P.Set (2, 64);
   begin
      P.Add (Ps, "id", "42", Added);
      Check (WN.Location_Of (Routes, "user.show", Ps) = "/users/42",
             "Location_Of builds the reverse URL");
      Check (WN.Location_Of (Routes, "nope", Ps) = "",
             "Location_Of is empty for an unknown route");
   end;

   --  Redirect_To (with params): 303 + Location header.
   declare
      Ps   : P.Set (2, 64);
      Resp : Web.Response.Response_Type;
   begin
      P.Add (Ps, "id", "7", Added);
      Resp := WN.Redirect_To (Routes, "user.show", Ps);
      Check (Web.Response.Status (Resp) = 303, "redirect status is 303");
      Check (Web.Response.Header (Resp, "Location") = "/users/7",
             "redirect sets the Location header to the reverse URL");
   end;

   --  Redirect_To (no params): parameterless route.
   declare
      Resp : constant Web.Response.Response_Type :=
        WN.Redirect_To (Routes, "home", Status => 302);
   begin
      Check (Web.Response.Status (Resp) = 302
             and then Web.Response.Header (Resp, "Location") = "/",
             "parameterless redirect");
   end;

   --  Fail-closed: a missing required param never redirects to a wrong URL.
   declare
      Empty : P.Set (0, 0);
      Resp  : constant Web.Response.Response_Type :=
        WN.Redirect_To (Routes, "user.show", Empty);
   begin
      Check (Web.Response.Status (Resp) = 500,
             "missing param yields the error response, not a redirect");
   end;

   --  Active_For: resolve the active menu item from the request path.
   Add_Link (Menu, No_Item, "Home", "/", Ignored);
   Add_Link (Menu, No_Item, "Docs", "/docs", Docs);
   Navigation.Menu.Finalize (Menu);

   declare
      Req : constant Web.Request.Request_Type :=
        Web.Server.Parse_Request
          ("GET /docs/guides HTTP/1.1" & CRLF & "Host: x" & CRLF & CRLF);
      Active : constant Item_Ref := WN.Active_For (Menu, Routes, Req);
   begin
      Check (Web.Request.Path (Req) = "/docs/guides", "request path parsed");
      Check (Active = Docs, "Active_For resolves the section match from the path");
   end;

   New_Line;
   if Failures = 0 then
      Put_Line ("all bridge tests passed");
      Ada.Command_Line.Set_Exit_Status (0);
   else
      Put_Line (Natural'Image (Failures) & " failure(s)");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Test_Bridge;
