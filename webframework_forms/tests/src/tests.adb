with Ada.Command_Line;
with AUnit;
use type AUnit.Status;
with AUnit.Reporter.Text;
with AUnit.Run;
with All_Suites;

procedure Tests is
   function Runner is new AUnit.Run.Test_Runner_With_Status (All_Suites.Suite);
   Reporter : AUnit.Reporter.Text.Text_Reporter;
   Status   : AUnit.Status;
begin
   Status := Runner (Reporter);
   Ada.Command_Line.Set_Exit_Status
     (if Status = AUnit.Success
      then Ada.Command_Line.Success
      else Ada.Command_Line.Failure);
end Tests;
