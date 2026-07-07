with Ada.Command_Line;
with Ada.Directories;
with Ada.Text_IO;
with Project_Tools.Files;

procedure Release_Check is
   Root : constant String := Ada.Directories.Current_Directory;
   Failures : Natural := 0;
   Strict_Artifacts : constant Boolean :=
     Ada.Command_Line.Argument_Count >= 1
     and then Ada.Command_Line.Argument (1) = "--strict-artifacts";

   procedure Fail (Message : String) is
   begin
      Failures := Failures + 1;
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "release_check: " & Message);
   end Fail;

   function Join (Path : String) return String is
   begin
      return Project_Tools.Files.Join (Root, Path);
   end Join;

   procedure Require_File (Path : String) is
   begin
      if not Project_Tools.Files.File_Exists (Join (Path)) then
         Fail ("missing required file: " & Path);
      end if;
   end Require_File;

   procedure Require_Directory (Path : String) is
   begin
      if not Project_Tools.Files.Directory_Exists (Join (Path)) then
         Fail ("missing required directory: " & Path);
      end if;
   end Require_Directory;

   procedure Forbid_Path (Path : String) is
   begin
      if Project_Tools.Files.File_Exists (Join (Path))
        or else Project_Tools.Files.Directory_Exists (Join (Path))
      then
         Fail ("generated artifact must not be present: " & Path);
      end if;
   end Forbid_Path;

   procedure Require_Contains
     (Path    : String;
      Pattern : String;
      Message : String)
   is
   begin
      if not Project_Tools.Files.File_Exists (Join (Path)) then
         Fail ("missing required file: " & Path);
      elsif not Project_Tools.Files.File_Contains (Join (Path), Pattern) then
         Fail (Message);
      end if;
   end Require_Contains;
begin
   Require_File ("LICENSE");
   Require_File ("README.md");
   Require_File ("webframework.gpr");
   Require_File ("alire.toml");
   Require_File ("docs/API.md");
   Require_File ("docs/API_STABILITY.md");
   Require_File ("docs/ARCHITECTURE.md");
   Require_File ("docs/BUILD.md");
   Require_File ("docs/CLI.md");
   Require_File ("docs/DEPLOYMENT.md");
   Require_File ("docs/EXAMPLES.md");
   Require_File ("docs/RECIPES.md");
   Require_File ("docs/RELEASE.md");
   Require_File ("docs/SECURITY.md");
   Require_File ("docs/TUTORIAL.md");
   Require_Directory ("src");
   Require_Directory ("tests/src");
   Require_Directory ("example_app/src");
   Require_Directory ("webframework_cli/src");
   Require_Directory ("tools/src");

   Require_Contains ("alire.toml", "licenses = ""MIT""", "root manifest must declare MIT license");
   Require_Contains ("alire.toml", "gnat_native = ""=15.2.1""", "root manifest must pin GNAT 15.2.1");
   Require_Contains ("tests/alire.toml", "gnat_native = ""=15.2.1""", "tests manifest must pin GNAT 15.2.1");
   Require_Contains
     ("example_app/alire.toml",
      "gnat_native = ""=15.2.1""",
      "example app manifest must pin GNAT 15.2.1");
   Require_Contains
     ("webframework_cli/alire.toml",
      "gnat_native = ""=15.2.1""",
      "CLI manifest must pin GNAT 15.2.1");
   Require_Contains ("tools/alire.toml", "gnat_native = ""=15.2.1""", "tools manifest must pin GNAT 15.2.1");
   Require_Contains (".gitignore", "/tools/bin/", "tools build outputs must be ignored");
   Require_Contains (".gitignore", "*.ali", "Ada interface artifacts must be ignored");
   Require_Contains ("README.md", "docs/DEPLOYMENT.md", "README must link deployment guide");
   Require_Contains ("docs/RELEASE.md", "release_check", "release checklist must include release_check");

   if Strict_Artifacts then
      Forbid_Path ("alire");
      Forbid_Path ("bin");
      Forbid_Path ("config");
      Forbid_Path ("lib");
      Forbid_Path ("obj");
      Forbid_Path ("tests/alire");
      Forbid_Path ("tests/bin");
      Forbid_Path ("tests/config");
      Forbid_Path ("tests/obj");
      Forbid_Path ("example_app/alire");
      Forbid_Path ("example_app/bin");
      Forbid_Path ("example_app/config");
      Forbid_Path ("example_app/lib");
      Forbid_Path ("example_app/obj");
      Forbid_Path ("webframework_cli/alire");
      Forbid_Path ("webframework_cli/bin");
      Forbid_Path ("webframework_cli/config");
      Forbid_Path ("webframework_cli/obj");
      Forbid_Path ("tools/alire");
      Forbid_Path ("tools/bin");
      Forbid_Path ("tools/config");
      Forbid_Path ("tools/obj");
   end if;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("release_check passed");
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Release_Check;
