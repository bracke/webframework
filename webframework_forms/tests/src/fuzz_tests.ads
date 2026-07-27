with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

package Fuzz_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_Decode_Robust (T : in out Fixture);
   procedure Test_Verify_Csrf_Robust (T : in out Fixture);

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

end Fuzz_Tests;
