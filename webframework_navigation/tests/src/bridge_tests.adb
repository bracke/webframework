with AUnit.Assertions; use AUnit.Assertions;
with AUnit.Test_Caller;
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

package body Bridge_Tests is

   package WN renames Webframework_Navigation;
   package R  renames Navigation.Routes;
   package P  renames Navigation.Params;

   use Navigation.Visibility;

   function Contains (Haystack, Needle : String) return Boolean is
     (Ada.Strings.Fixed.Index (Haystack, Needle) > 0);

   CRLF : constant String := (Character'Val (13), Character'Val (10));

   type Role is (Guest, Admin);
   function Can_See (Key : String; V : Role) return Visibility is
     (if Key = "admin" then (if V = Admin then Visible else Hidden) else Visible);
   package FM is new WN.Filtered_Menu (Role, Can_See);

   --  A finalized route table: home "/", user.show "/users/:id".
   procedure Build_Routes (Tbl : in out R.Table) is
      Added : Boolean;
   begin
      R.Add (Tbl, "home", "/", Added);
      R.Add (Tbl, "user.show", "/users/:id", Added);
      R.Finalize (Tbl);
   end Build_Routes;

   function Get (Path : String) return Web.Request.Request_Type is
     (Web.Server.Parse_Request
        ("GET " & Path & " HTTP/1.1" & CRLF & "Host: x" & CRLF & CRLF));

   procedure Test_Location (T : in out Fixture) is
      pragma Unreferenced (T);
      Tbl : R.Table (8, 256);
      Ps  : P.Set (2, 64);
      Ok  : Boolean;
   begin
      Build_Routes (Tbl);
      P.Add (Ps, "id", "42", Ok);
      Assert (WN.Location_Of (Tbl, "user.show", Ps) = "/users/42",
              "Location_Of builds the reverse URL");
      Assert (WN.Location_Of (Tbl, "nope", Ps) = "",
              "Location_Of is empty for an unknown route");
   end Test_Location;

   procedure Test_Redirect (T : in out Fixture) is
      pragma Unreferenced (T);
      Tbl : R.Table (8, 256);
      Ps  : P.Set (2, 64);
      Ok  : Boolean;
   begin
      Build_Routes (Tbl);
      P.Add (Ps, "id", "7", Ok);
      declare
         Resp : constant Web.Response.Response_Type :=
           WN.Redirect_To (Tbl, "user.show", Ps);
      begin
         Assert (Web.Response.Status (Resp) = 303, "redirect status is 303");
         Assert (Web.Response.Header (Resp, "Location") = "/users/7",
                 "Location header is the reverse URL");
      end;
      declare
         Resp : constant Web.Response.Response_Type :=
           WN.Redirect_To (Tbl, "home", Status => 302);
      begin
         Assert (Web.Response.Status (Resp) = 302
                 and then Web.Response.Header (Resp, "Location") = "/",
                 "parameterless redirect");
      end;
      declare
         Empty : P.Set (0, 0);
      begin
         Assert (Web.Response.Status (WN.Redirect_To (Tbl, "user.show", Empty)) = 500,
                 "missing param yields the error response, not a redirect");
      end;
   end Test_Redirect;

   procedure Test_Active (T : in out Fixture) is
      pragma Unreferenced (T);
      Tbl : R.Table (8, 256);
      M   : Menu (8, 256);
      Docs, Ig : Item_Ref;
   begin
      Build_Routes (Tbl);
      Add_Link (M, No_Item, "Home", "/", Ig);
      Add_Link (M, No_Item, "Docs", "/docs", Docs);
      Finalize (M);
      Assert (WN.Active_For (M, Tbl, Get ("/docs/guides")) = Docs,
              "Active_For resolves the section match from the path");
   end Test_Active;

   procedure Test_Render_Menu (T : in out Fixture) is
      pragma Unreferenced (T);
      Tbl : R.Table (8, 256);
      M   : Menu (16, 512);
      Dv, Adm, Ig : Item_Ref;
   begin
      Build_Routes (Tbl);
      Add_Link (M, No_Item, "Home", "/", Ig);
      Add_Link (M, No_Item, "Docs & More", "/docs", Dv);
      Add_Link (M, Dv, "Intro", "/docs/intro", Ig);
      Add_Heading (M, No_Item, "Admin", Adm, Visibility_Key => "admin");
      Add_Link (M, Adm, "Settings", "/admin/settings", Ig);
      Finalize (M);
      declare
         HTML : constant String := WN.Render_Menu (M, Tbl, Dv);
      begin
         Assert (Contains (HTML, "<a href=""/docs"">Docs &amp; More</a>"),
                 "menu links items and escapes labels");
         Assert (Contains (HTML, "<li class=""active""><a href=""/docs"""),
                 "menu marks the active item");
         Assert (Contains (HTML, "<span>Admin</span>"),
                 "heading renders as a span");
      end;
   end Test_Render_Menu;

   procedure Test_Breadcrumbs (T : in out Fixture) is
      pragma Unreferenced (T);
      Tbl : R.Table (8, 256);
      M   : Menu (8, 512);
      Dv, Ig : Item_Ref;
      Crumbs : Navigation.Breadcrumbs.Trail (8, 512);
   begin
      Build_Routes (Tbl);
      Add_Link (M, No_Item, "Docs", "/docs", Dv);
      Add_Link (M, Dv, "Intro", "/docs/intro", Ig);
      Finalize (M);
      Navigation.Breadcrumbs.Build_For_Path (Crumbs, M, Tbl, "/docs/intro");
      declare
         HTML : constant String := WN.Render_Breadcrumbs (Crumbs);
      begin
         Assert (Contains (HTML, "<nav class=""breadcrumbs""><ol>"),
                 "breadcrumbs wrap in nav/ol");
         Assert (Contains (HTML, "<a href=""/docs"">Docs</a>")
                 and then Contains (HTML, "<a href=""/docs/intro"">Intro</a>"),
                 "breadcrumbs link each crumb");
      end;
   end Test_Breadcrumbs;

   procedure Test_Filtered_Menu (T : in out Fixture) is
      pragma Unreferenced (T);
      Tbl : R.Table (8, 256);
      M   : Menu (16, 512);
      Adm, Ig : Item_Ref;
   begin
      Build_Routes (Tbl);
      Add_Link (M, No_Item, "Home", "/", Ig);
      Add_Heading (M, No_Item, "Admin", Adm, Visibility_Key => "admin");
      Add_Link (M, Adm, "Settings", "/admin/settings", Ig);
      Finalize (M);
      Assert (not Contains (FM.Render (M, Tbl, Guest), "Settings")
              and then not Contains (FM.Render (M, Tbl, Guest), "<span>Admin</span>"),
              "filtered menu hides the gated section + subtree from a guest");
      Assert (Contains (FM.Render (M, Tbl, Admin), "<span>Admin</span>")
              and then Contains (FM.Render (M, Tbl, Admin), "/admin/settings"),
              "filtered menu shows the gated section to an admin");
   end Test_Filtered_Menu;

   procedure Test_Hardening (T : in out Fixture) is
      pragma Unreferenced (T);
      Tbl : R.Table (8, 256);
      HM  : Menu (8, 512);
      Ig  : Item_Ref;
      Evil_Label : constant String := "Hi<script>alert(1)</script>";
      Evil_Url   : constant String := "/x"" onmouseover=""evil()";
   begin
      Build_Routes (Tbl);
      Add_Link (HM, No_Item, Evil_Label, Evil_Url, Ig);
      Finalize (HM);
      declare
         HTML : constant String := WN.Render_Menu (HM, Tbl);
      begin
         Assert (not Contains (HTML, "<script>")
                 and then Contains (HTML, "&lt;script&gt;"),
                 "a script-tag label is escaped, not raw");
         Assert (not Contains (HTML, """ onmouseover=""evil"),
                 "a quote-breaking URL cannot inject an attribute");
      end;

      declare
         Tiny : constant Navigation.Limits.Limits :=
           (Max_Params => 8, Max_Param_Bytes => 256, Max_Url_Bytes => 4,
            Max_Template_Bytes => 64, Max_Depth => 8, Max_Label_Bytes => 64);
         Ps : P.Set (2, 64);
         Ok : Boolean;
      begin
         P.Add (Ps, "id", "1234567890", Ok);
         Assert (Web.Response.Status
                   (WN.Redirect_To (Tbl, "user.show", Ps, Limits => Tiny)) = 500,
                 "redirect fail-closed on an over-budget URL");
      end;

      declare
         EM : Menu (2, 32);
      begin
         Finalize (EM);
         Assert (WN.Render_Menu (EM, Tbl) = "", "empty menu renders to nothing");
      end;
   end Test_Hardening;

   package Caller is new AUnit.Test_Caller (Fixture);

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Suite.Add_Test (Caller.Create ("Bridge: Location_Of", Test_Location'Access));
      Suite.Add_Test (Caller.Create ("Bridge: Redirect_To", Test_Redirect'Access));
      Suite.Add_Test (Caller.Create ("Bridge: Active_For", Test_Active'Access));
      Suite.Add_Test (Caller.Create ("Bridge: Render_Menu", Test_Render_Menu'Access));
      Suite.Add_Test (Caller.Create ("Bridge: Breadcrumbs", Test_Breadcrumbs'Access));
      Suite.Add_Test
        (Caller.Create ("Bridge: Filtered_Menu", Test_Filtered_Menu'Access));
      Suite.Add_Test (Caller.Create ("Bridge: hardening", Test_Hardening'Access));
   end Add_Tests;

end Bridge_Tests;
