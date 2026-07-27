with Navigation.Routes;
with Navigation.Menu;
with Navigation.Active;
with Navigation.Visibility;
with Webframework_Navigation;
with Webframework_Navigation.Filtered_Menu;

package body App.Nav is

   package NR renames Navigation.Routes;
   package NM renames Navigation.Menu;
   package WN renames Webframework_Navigation;

   use Navigation.Visibility;

   --  The viewer is the request's clearance; a menu item's visibility key is the
   --  minimum clearance it needs. Fail-closed: an unparseable key hides the item.
   function Can_See (Key : String; Clearance : Natural) return Visibility is
   begin
      return (if Clearance >= Natural'Value (Key) then Visible else Hidden);
   exception
      when others =>
         return Hidden;
   end Can_See;

   package Filtered is new WN.Filtered_Menu (Natural, Can_See);

   Routes : NR.Table (16, 512);
   Menu   : NM.Menu (16, 512);
   Ready  : Boolean := False;

   procedure Setup is
      Added  : Boolean;
      Ignore : NM.Item_Ref;
   begin
      if Ready then          --  idempotent; built once at elaboration
         return;
      end if;
      NR.Add (Routes, "home", "/", Added);
      NR.Add (Routes, "login", "/login", Added);
      NR.Add (Routes, "projects", "/projects", Added);
      NR.Add (Routes, "todo", "/todo", Added);
      NR.Add (Routes, "attachments", "/attachments", Added);
      NR.Add (Routes, "health", "/health", Added);
      NR.Finalize (Routes);

      --  The pages all need viewing clearance (>= 10); an anonymous caller
      --  (clearance 0) sees an empty nav.
      NM.Add_Route
        (Menu, NM.No_Item, "Home", "home", Ignore, Visibility_Key => "10");
      NM.Add_Route
        (Menu, NM.No_Item, "Projects", "projects", Ignore, Visibility_Key => "10");
      NM.Add_Route
        (Menu, NM.No_Item, "To-Do", "todo", Ignore, Visibility_Key => "10");
      NM.Add_Route
        (Menu, NM.No_Item, "Attachments", "attachments", Ignore,
         Visibility_Key => "10");
      NM.Finalize (Menu);
      Ready := True;
   end Setup;

   function Redirect
     (Name : String; Status : Positive := 303) return Web.Response.Response_Type
   is (WN.Redirect_To (Routes, Name, Status => Status));

   function Menu_Html
     (Current_Path : String; Clearance : Natural) return String
   is
      Active : constant NM.Item_Ref :=
        Navigation.Active.Resolve (Menu, Routes, Current_Path);
   begin
      return Filtered.Render (Menu, Routes, Clearance, Active);
   end Menu_Html;

begin
   --  Build the routes/menu at elaboration, so anything that captures a
   --  reverse-URL redirect during its own elaboration (e.g. the auth guard's
   --  anonymous->login response) sees a populated route table.
   Setup;
end App.Nav;
