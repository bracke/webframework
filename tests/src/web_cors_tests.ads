with AUnit.Test_Fixtures;
with AUnit.Test_Suites;
package Web_CORS_Tests is
   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;
   procedure Test_Any_Origin (T : in out Fixture);
   procedure Test_Allowlist_Hit (T : in out Fixture);
   procedure Test_Allowlist_Miss (T : in out Fixture);
   procedure Test_No_Origin (T : in out Fixture);
   procedure Test_Credentials (T : in out Fixture);
   procedure Test_Preflight (T : in out Fixture);
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);
end Web_CORS_Tests;
