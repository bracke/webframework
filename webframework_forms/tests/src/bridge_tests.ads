with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

package Bridge_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_Decode (T : in out Fixture);
   procedure Test_Content_Type_Dispatch (T : in out Fixture);
   procedure Test_Csrf_Roundtrip (T : in out Fixture);
   procedure Test_Session_Csrf (T : in out Fixture);
   procedure Test_Bind_Diagnostics (T : in out Fixture);
   procedure Test_Sticky (T : in out Fixture);
   procedure Test_Hardening (T : in out Fixture);

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

end Bridge_Tests;
