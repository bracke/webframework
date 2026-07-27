with Ada.Text_IO;     use Ada.Text_IO;
with Ada.Command_Line;
with Ada.Strings.Fixed;

with Web.Request;
with Web.Response;
with Web.Server;

with Navigation.Routes;
with Navigation.Params;
with Navigation.Menu;  use Navigation.Menu;
with Navigation.Breadcrumbs;
with Navigation.Visibility;
with Navigation.Limits;

with Webframework_Navigation;
with Webframework_Navigation.Filtered_Menu;

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

   function Contains (Haystack, Needle : String) return Boolean is
     (Ada.Strings.Fixed.Index (Haystack, Needle) > 0);

   CRLF : constant String := (Character'Val (13), Character'Val (10));

   --  A viewer + predicate for the filtered-menu test: "admin" needs Admin.
   use Navigation.Visibility;
   type Role is (Guest, Admin);
   function Can_See (Key : String; V : Role) return Visibility is
     (if Key = "admin" then (if V = Admin then Visible else Hidden)
      else Visible);
   package FM is new Webframework_Navigation.Filtered_Menu (Role, Can_See);

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

   --  Menu for rendering tests: Home, Docs (>Intro), and a gated Admin heading.
   declare
      RMenu : Navigation.Menu.Menu (16, 512);
      Dv, Adm, Ig : Item_Ref;
   begin
      Add_Link (RMenu, No_Item, "Home", "/", Ig);
      Add_Link (RMenu, No_Item, "Docs & More", "/docs", Dv);
      Add_Link (RMenu, Dv, "Intro", "/docs/intro", Ig);
      Add_Heading (RMenu, No_Item, "Admin", Adm, Visibility_Key => "admin");
      Add_Link (RMenu, Adm, "Settings", "/admin/settings", Ig);
      Navigation.Menu.Finalize (RMenu);

      --  Render_Menu with active highlighting + escaping of "&".
      declare
         HTML : constant String :=
           Webframework_Navigation.Render_Menu (RMenu, Routes, Dv);
      begin
         Check (Contains (HTML, "<a href=""/docs"">Docs &amp; More</a>"),
                "Render_Menu links items and escapes labels");
         Check (Contains (HTML, "<li class=""active""><a href=""/docs"""),
                "Render_Menu marks the active item");
         Check (Contains (HTML, "<span>Admin</span>"),
                "Render_Menu renders a heading as a span");
      end;

      --  Breadcrumbs for /docs/intro.
      declare
         Crumbs : Navigation.Breadcrumbs.Trail (8, 512);
      begin
         Navigation.Breadcrumbs.Build_For_Path
           (Crumbs, RMenu, Routes, "/docs/intro");
         declare
            HTML : constant String :=
              Webframework_Navigation.Render_Breadcrumbs (Crumbs);
         begin
            Check (Contains (HTML, "<nav class=""breadcrumbs""><ol>"),
                   "Render_Breadcrumbs wraps in nav/ol");
            Check (Contains (HTML, "<a href=""/docs"">Docs &amp; More</a>")
                   and then Contains (HTML, "<a href=""/docs/intro"">Intro</a>"),
                   "Render_Breadcrumbs links each crumb");
         end;
      end;

      --  Filtered_Menu: the Admin section is hidden from a Guest, shown to Admin.
      declare
         Guest_HTML : constant String := FM.Render (RMenu, Routes, Guest);
         Admin_HTML : constant String := FM.Render (RMenu, Routes, Admin);
      begin
         Check (not Contains (Guest_HTML, "Settings")
                and then not Contains (Guest_HTML, "<span>Admin</span>"),
                "Filtered_Menu hides the gated section and its subtree from a guest");
         Check (Contains (Admin_HTML, "<span>Admin</span>")
                and then Contains (Admin_HTML, "/admin/settings"),
                "Filtered_Menu shows the gated section to an admin");
         Check (Contains (Guest_HTML, "Home") and then Contains (Guest_HTML, "Docs"),
                "Filtered_Menu still shows public items to a guest");
      end;
   end;

   --  Hardening: adversarial labels/URLs must never break out of the markup,
   --  and a redirect must stay fail-closed under a hostile URL budget.
   declare
      HM : Navigation.Menu.Menu (8, 512);
      Ig : Item_Ref;
      --  A label carrying a script tag and a URL trying to break the href
      --  attribute and add an event handler.
      Evil_Label : constant String := "Hi<script>alert(1)</script>";
      Evil_Url   : constant String := "/x"" onmouseover=""evil()";
   begin
      Add_Link (HM, No_Item, Evil_Label, Evil_Url, Ig);
      Navigation.Menu.Finalize (HM);
      declare
         HTML : constant String := Webframework_Navigation.Render_Menu (HM, Routes);
      begin
         Check (not Contains (HTML, "<script>"),
                "render escapes a script-tag label (no raw <script>)");
         Check (Contains (HTML, "&lt;script&gt;"),
                "the label survives, neutralized");
         Check (not Contains (HTML, """ onmouseover=""evil"),
                "render escapes a quote-breaking URL (no attribute injection)");
      end;

      --  Breadcrumb labels are escaped the same way.
      declare
         BM : Navigation.Menu.Menu (4, 256);
         Crumbs : Navigation.Breadcrumbs.Trail (4, 256);
      begin
         Add_Link (BM, No_Item, "X<b>", "/evilpath", Ig);
         Navigation.Menu.Finalize (BM);
         Navigation.Breadcrumbs.Build_For_Path (Crumbs, BM, Routes, "/evilpath");
         declare
            HTML : constant String :=
              Webframework_Navigation.Render_Breadcrumbs (Crumbs);
         begin
            Check (not Contains (HTML, "<b>") and then Contains (HTML, "&lt;b&gt;"),
                   "breadcrumb labels are escaped");
         end;
      end;

      --  Redirect stays fail-closed when the URL would blow a tiny budget.
      declare
         Tiny : constant Navigation.Limits.Limits :=
           (Max_Params => 8, Max_Param_Bytes => 256, Max_Url_Bytes => 4,
            Max_Template_Bytes => 64, Max_Depth => 8, Max_Label_Bytes => 64);
         Ps : P.Set (2, 64);
         Ok : Boolean;
      begin
         P.Add (Ps, "id", "1234567890", Ok);
         Check (Web.Response.Status
                  (WN.Redirect_To (Routes, "user.show", Ps, Limits => Tiny)) = 500,
                "redirect fail-closed on an over-budget URL");
      end;

      --  Rendering an empty menu never crashes.
      declare
         EM : Navigation.Menu.Menu (2, 32);
      begin
         Navigation.Menu.Finalize (EM);
         Check (Webframework_Navigation.Render_Menu (EM, Routes) = "",
                "empty menu renders to nothing");
      end;
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
