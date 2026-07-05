with AUnit.Reporter.Text;
with AUnit.Run;
with Web_Test_Suite;

procedure Tests is
   procedure Run is new AUnit.Run.Test_Runner (Web_Test_Suite.Suite);
   Reporter : AUnit.Reporter.Text.Text_Reporter;
begin
   Run (Reporter);
end Tests;
