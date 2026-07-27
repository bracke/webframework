with AUnit.Test_Fixtures;
with AUnit.Test_Suites;
package Web_Multipart_Tests is
   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;
   procedure Test_Boundary_Of (T : in out Fixture);
   procedure Test_Parse (T : in out Fixture);
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);
end Web_Multipart_Tests;
