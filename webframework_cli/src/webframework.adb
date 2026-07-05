with Ada.Command_Line;
with Webframework_Cli;

procedure Webframework is
   Status : constant Natural := Webframework_Cli.Run;
begin
   Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status (Status));
end Webframework;
