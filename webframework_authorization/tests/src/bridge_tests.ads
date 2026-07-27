with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

package Bridge_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_Authorized_Proceeds (T : in out Fixture);
   procedure Test_Denied_Halts (T : in out Fixture);
   procedure Test_On_Deny_Override (T : in out Fixture);

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

end Bridge_Tests;
