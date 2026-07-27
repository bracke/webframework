with Ada.Command_Line; use Ada.Command_Line;
with Ada.Directories;
with Ada.Text_IO;      use Ada.Text_IO;

with GNAT.OS_Lib;

with Project_Tools.Files;
with Project_Tools.Processes;

--  Integration gate for the whole web-stack slice: build + test each component
--  in dependency order, so a change in an upstream library (representation, ...)
--  that breaks a downstream (forms, navigation, webframework, the bridges, the
--  example app) is caught by one command. The path-pin web has no other gate
--  that spans repos. This is the single canonical full-stack verifier -- it
--  supersedes the former scripts/verify_full_stack.sh (whose example_app and CLI
--  checks are folded in below).
--
--  Each library is verified via its own `alr test` action; webframework, the
--  bridges, the example app, and the CLI checker are run explicitly. Run from
--  anywhere inside the webframework checkout.
procedure Stack_Check is

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
   Alr      : constant String := Proc.Locate_Command ("alr");

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
        Proc.Run_Status (Label => Label, Dir => Dir, Program => Program, Args => Args);
      if Status /= 0 then
         Fail (Label & " failed (status" & Integer'Image (Status) & ")");
         return False;
      end if;
      return True;
   end Run;

   Ignored : Boolean;
   pragma Unreferenced (Ignored);

   Test : constant GNAT.OS_Lib.Argument_List :=
     [new String'("--non-interactive"), new String'("test")];
   Build : constant GNAT.OS_Lib.Argument_List :=
     [new String'("--non-interactive"), new String'("build")];
   No_Args : constant GNAT.OS_Lib.Argument_List := [];

   --  A sibling library, verified through its own `alr test` action.
   procedure Gate_Library (Name : String) is
   begin
      Put_Line ("== " & Name & " ==");
      Ignored := Run (Name & " test", The_Root & "/../" & Name, Alr, Test);
   end Gate_Library;

begin
   --  Dependency order: leaves first, then the consumers.
   Gate_Library ("representation");
   Gate_Library ("validation");
   Gate_Library ("forms");
   Gate_Library ("navigation");

   --  webframework (no test action): build the library, then its AUnit suite.
   Put_Line ("== webframework ==");
   if Run ("webframework build", The_Root, Alr, Build) then
      if Run ("webframework tests build", The_Root & "/tests", Alr, Build) then
         Ignored := Run ("webframework tests", The_Root & "/tests",
                         The_Root & "/tests/bin/tests", No_Args);
      end if;
   end if;

   --  The bridge integration gate (surface + boundary + build/test all bridges,
   --  including the webframework_authorization bridge and the demo).
   Put_Line ("== bridges ==");
   if Run ("bridge_tools build", The_Root & "/bridge_tools", Alr, Build) then
      Ignored := Run ("bridges gate", The_Root & "/bridge_tools",
                      The_Root & "/bridge_tools/bin/check_bridges",
                      [new String'("--release")]);
   end if;

   --  The reference application + its integration tests (folded in from the
   --  former scripts/verify_full_stack.sh).
   Put_Line ("== example_app ==");
   if Run ("example_app build", The_Root & "/example_app", Alr, Build) then
      if Run ("example_app tests", The_Root & "/example_app",
              The_Root & "/example_app/bin/app_tests", No_Args)
      then
         Ignored := Run ("example_app http tests", The_Root & "/example_app",
                         The_Root & "/example_app/bin/app_http_tests", No_Args);
      end if;
   end if;

   --  The framework CLI checker run against the example app.
   Put_Line ("== webframework_cli ==");
   if Run ("webframework_cli build", The_Root & "/webframework_cli", Alr, Build)
   then
      Ignored := Run ("cli check example_app", The_Root & "/webframework_cli",
                      The_Root & "/webframework_cli/bin/webframework",
                      [new String'("check"), new String'("../example_app")]);
   end if;

   New_Line;
   if Errors = 0 then
      Put_Line ("stack_check: whole slice builds and tests green");
   else
      Put_Line (Standard_Error,
                "stack_check:" & Natural'Image (Errors) & " component(s) failed");
      Set_Exit_Status (Failure);
   end if;
end Stack_Check;
