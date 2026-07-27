with AUnit.Test_Fixtures;
with AUnit.Test_Suites;
package Web_Stream_Tests is
   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;
   procedure Test_Stream_Upload (T : in out Fixture);
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);
end Web_Stream_Tests;
