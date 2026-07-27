with Ada.Command_Line;      use Ada.Command_Line;
with Ada.Directories;
with Ada.Text_IO;           use Ada.Text_IO;

with GNAT.OS_Lib;

with Project_Tools.Files;
with Project_Tools.Processes;

--  Release gate for the webframework bridge crates (webframework_navigation,
--  webframework_forms, integration_demo). Enforces the surface, the dependency
--  boundary (each bridge may touch webframework + its own sibling only, never
--  the other sibling or auth/identity/persistence), and -- with --release --
--  that every crate builds and its test driver / demo passes.
procedure Check_Bridges is

   package Files renames Project_Tools.Files;
   package Proc  renames Project_Tools.Processes;

   Errors : Natural := 0;

   procedure Fail (Message : String) is
   begin
      Errors := Errors + 1;
      Put_Line (Standard_Error, "error: " & Message);
   end Fail;

   function Root return String is
      Current : constant String := Ada.Directories.Current_Directory;
      Found   : constant String :=
        Files.Find_Root_Upward (Current, "webframework.gpr");
   begin
      if Found = "" then
         Put_Line (Standard_Error, "webframework root not found from " & Current);
         Set_Exit_Status (Failure);
         raise Program_Error;
      end if;
      return Found;
   end Root;

   The_Root : constant String := Root;

   procedure Need_File (Relative : String) is
   begin
      if not Files.File_Exists (The_Root & "/" & Relative) then
         Fail ("missing required file: " & Relative);
      end if;
   end Need_File;

   procedure Need_Directory (Relative : String) is
   begin
      if not Files.Directory_Exists (The_Root & "/" & Relative) then
         Fail ("missing required directory: " & Relative);
      end if;
   end Need_Directory;

   --  Surface every bridge crate must present.
   procedure Check_Surface (Bridge : String) is
   begin
      Need_Directory (Bridge);
      Need_File (Bridge & "/alire.toml");
      Need_File (Bridge & "/" & Bridge & ".gpr");
      Need_Directory (Bridge & "/src");
      Need_File (Bridge & "/README.md");
      Need_File (Bridge & "/tests/test_bridge.gpr");
   end Check_Surface;

   --  Dependency-boundary audit: scan a bridge's src for forbidden with-clauses.
   --  Sibling is the OTHER sibling this bridge must not reach.
   procedure Audit (Bridge : String; Sibling : String) is
      Src    : constant String := The_Root & "/" & Bridge & "/src";
      Search : Ada.Directories.Search_Type;
      Item   : Ada.Directories.Directory_Entry_Type;

      procedure Check_File (Full : String; Name : String) is
         procedure Forbid (Pkg : String) is
         begin
            if Files.File_Contains (Full, "with " & Pkg) then
               Fail (Bridge & "/" & Name
                     & ": forbidden dependency 'with " & Pkg & "'");
            end if;
         end Forbid;
      begin
         Forbid (Sibling);           --  no cross-sibling coupling
         Forbid ("Authorization");
         Forbid ("Identity");
         Forbid ("Database");
         Forbid ("Tables");
         Forbid ("Jobs");
         Forbid ("Notifications");
         Forbid ("Audit");
         Forbid ("Templates");
         Forbid ("I18n");
         Forbid ("Httpclient");
         Forbid ("AWS");
         Forbid ("GNAT.Sockets");
         Forbid ("Ada.Directories");
      end Check_File;
   begin
      if not Files.Directory_Exists (Src) then
         return;   --  surface check already reported the missing dir
      end if;
      Ada.Directories.Start_Search
        (Search, Src, "*.ad*",
         Filter => [Ada.Directories.Ordinary_File => True, others => False]);
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item);
         Check_File
           (Ada.Directories.Full_Name (Item),
            Ada.Directories.Simple_Name (Item));
      end loop;
      Ada.Directories.End_Search (Search);
   end Audit;

   function Run
     (Label   : String;
      Dir     : String;
      Program : String;
      Args    : GNAT.OS_Lib.Argument_List) return Boolean
   is
      Status : Integer;
   begin
      if Program = "" then
         Fail (Label & ": program not found");
         return False;
      end if;
      Status :=
        Proc.Run_Status
          (Label => Label, Dir => Dir, Program => Program, Args => Args);
      if Status /= 0 then
         Fail (Label & " failed (status" & Integer'Image (Status) & ")");
         return False;
      end if;
      return True;
   end Run;

   Ignored : Boolean;
   pragma Unreferenced (Ignored);

   procedure Build_And_Test (Crate : String; Has_Tests : Boolean; Exe : String) is
      Alr   : constant String := Proc.Locate_Command ("alr");
      Dir   : constant String := The_Root & "/" & Crate;
      Tests : constant String := Dir & "/tests";
      No_Args : constant GNAT.OS_Lib.Argument_List := [];
      Build   : constant GNAT.OS_Lib.Argument_List :=
        [new String'("--non-interactive"), new String'("build")];
   begin
      if not Run ("build " & Crate, Dir, Alr, Build) then
         return;
      end if;
      if Has_Tests then
         if Run ("build " & Crate & " tests", Tests, Alr, Build) then
            Ignored :=
              Run ("run " & Crate & " tests", Tests, Tests & "/bin/" & Exe,
                   No_Args);
         end if;
      else
         Ignored := Run ("run " & Crate, Dir, Dir & "/bin/" & Exe, No_Args);
      end if;
   end Build_And_Test;

begin
   Check_Surface ("webframework_navigation");
   Check_Surface ("webframework_forms");
   Need_Directory ("integration_demo");
   Need_File ("integration_demo/src/demo.adb");
   Need_File ("docs/BRIDGES.md");

   Audit ("webframework_navigation", Sibling => "Forms");
   Audit ("webframework_forms",      Sibling => "Navigation");

   if Proc.Has_Argument ("--release") then
      Build_And_Test ("webframework_navigation", Has_Tests => True,  Exe => "test_bridge");
      Build_And_Test ("webframework_forms",      Has_Tests => True,  Exe => "test_bridge");
      Build_And_Test ("integration_demo",        Has_Tests => False, Exe => "demo");
   end if;

   if Errors = 0 then
      Put_Line ("check_bridges: all checks passed");
   else
      Put_Line (Standard_Error,
                "check_bridges:" & Natural'Image (Errors) & " error(s)");
      Set_Exit_Status (Failure);
   end if;
end Check_Bridges;
