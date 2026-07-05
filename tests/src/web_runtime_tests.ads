with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

package Web_Runtime_Tests is
   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add browser runtime tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  Test the tiny browser runtime with a DOM harness.
   --  @param Item AUnit fixture.
   procedure Test_Runtime_Behavior (Item : in out Fixture);
end Web_Runtime_Tests;
