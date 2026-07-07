with Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.OS_Lib;
with Project_Tools.Files;
with Project_Tools.Processes;

procedure Release_Smoke is
   use Ada.Strings.Unbounded;

   function Root return String is
      Current : constant String := Ada.Directories.Current_Directory;
   begin
      if Project_Tools.Files.File_Exists (Project_Tools.Files.Join (Current, "webframework.gpr")) then
         return Current;
      elsif Project_Tools.Files.File_Exists (Project_Tools.Files.Join (Current, "../webframework.gpr")) then
         return Ada.Directories.Full_Name (Project_Tools.Files.Join (Current, ".."));
      else
         return Current;
      end if;
   end Root;

   Project_Root : constant String := Root;
   Alr : constant String := Project_Tools.Processes.Locate_Command ("alr");
   Probe_Root : constant String := "/tmp/webframework_release_probe";

   function Has_Argument (Name : String) return Boolean renames Project_Tools.Processes.Has_Argument;

   procedure Require_Command (Name : String; Path : String) is
   begin
      if Path'Length = 0 then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Name & " is required");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         raise Program_Error;
      end if;
   end Require_Command;

   procedure Run
     (Label   : String;
      Dir     : String;
      Program : String;
      Args    : GNAT.OS_Lib.Argument_List)
   is
   begin
      Project_Tools.Processes.Run (Label, Dir, Program, Args);
   end Run;

begin
   Require_Command ("alr", Alr);

   Project_Tools.Files.Require_File
     (Project_Tools.Files.Join (Project_Root, "README.md"),
      "README is required");
   Project_Tools.Files.Require_File
     (Project_Tools.Files.Join (Project_Root, "docs/RELEASE.md"),
      "release checklist is required");
   Project_Tools.Files.Require_Contains
     (Project_Tools.Files.Join (Project_Root, "alire.toml"),
      "gnat_native = ""=15.2.1""",
      "root manifest must pin gnat_native = ""=15.2.1""");
   Project_Tools.Files.Require_Contains
     (Project_Tools.Files.Join (Project_Root, "tests/alire.toml"),
      "gnat_native = ""=15.2.1""",
      "tests manifest must pin gnat_native = ""=15.2.1""");
   Project_Tools.Files.Require_Contains
     (Project_Tools.Files.Join (Project_Root, "example_app/alire.toml"),
      "gnat_native = ""=15.2.1""",
      "example app manifest must pin gnat_native = ""=15.2.1""");
   Project_Tools.Files.Require_Contains
     (Project_Tools.Files.Join (Project_Root, "webframework_cli/alire.toml"),
      "gnat_native = ""=15.2.1""",
      "CLI manifest must pin gnat_native = ""=15.2.1""");
   Project_Tools.Files.Require_Contains
     (Project_Tools.Files.Join (Project_Root, "tools/alire.toml"),
      "gnat_native = ""=15.2.1""",
      "tools manifest must pin gnat_native = ""=15.2.1""");

   Run
     ("release check",
      Project_Root,
      Project_Tools.Files.Join (Project_Root, "tools/bin/release_check"),
      []);
   Run ("root build", Project_Root, Alr, [1 => new String'("build")]);
   Run ("test build", Project_Tools.Files.Join (Project_Root, "tests"), Alr, [1 => new String'("build")]);
   Run
     ("AUnit tests",
      Project_Root,
      Project_Tools.Files.Join (Project_Root, "tests/bin/tests"),
      []);
   Run
     ("CLI build",
      Project_Tools.Files.Join (Project_Root, "webframework_cli"),
      Alr,
      [1 => new String'("build")]);
   Run
     ("check root",
      Project_Root,
      Project_Tools.Files.Join (Project_Root, "webframework_cli/bin/webframework"),
      [1 => new String'("check"), 2 => new String'(".")]);
   Run
     ("check example app",
      Project_Root,
      Project_Tools.Files.Join (Project_Root, "webframework_cli/bin/webframework"),
      [1 => new String'("check"), 2 => new String'("example_app")]);

   Project_Tools.Files.Delete_Tree (Probe_Root);
   Run
     ("generate app",
      Project_Root,
      Project_Tools.Files.Join (Project_Root, "webframework_cli/bin/webframework"),
      [1 => new String'("new"), 2 => new String'(Probe_Root)]);
   Run
     ("check generated app",
      Project_Root,
      Project_Tools.Files.Join (Project_Root, "webframework_cli/bin/webframework"),
      [1 => new String'("check"), 2 => new String'(Probe_Root)]);
   Run ("alr build generated app", Probe_Root, Alr, [1 => new String'("build")]);

   if Has_Argument ("--include-example-build") then
      Run
        ("example app build",
         Project_Tools.Files.Join (Project_Root, "example_app"),
         Alr,
         [1 => new String'("build")]);
   end if;

   if Has_Argument ("--include-soak") then
      Run
        ("soak harness",
         Project_Root,
         Project_Tools.Files.Join (Project_Root, "tools/bin/soak_harness"),
         [1 => new String'("8"), 2 => new String'("50")]);
   end if;

   if Has_Argument ("--include-long-soak") then
      Run
        ("long soak harness",
         Project_Root,
         Project_Tools.Files.Join (Project_Root, "tools/bin/soak_harness"),
         [1 => new String'("16"), 2 => new String'("250")]);
   end if;

   Ada.Text_IO.Put_Line ("webframework release smoke passed");
exception
   when Error : others =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "release_smoke failed: " & Ada.Exceptions.Exception_Message (Error));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Release_Smoke;
