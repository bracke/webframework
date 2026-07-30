with AUnit.Test_Fixtures;
with AUnit.Test_Suites;
package Web_Rate_Limit_Tests is
   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;
   procedure Test_Under_Limit (T : in out Fixture);
   procedure Test_Over_Limit (T : in out Fixture);
   procedure Test_Window_Reset (T : in out Fixture);
   procedure Test_Per_Client (T : in out Fixture);
   procedure Test_Disabled (T : in out Fixture);
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);
end Web_Rate_Limit_Tests;
