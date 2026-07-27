with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

package Bridge_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   procedure Test_Location (T : in out Fixture);
   procedure Test_Redirect (T : in out Fixture);
   procedure Test_Active (T : in out Fixture);
   procedure Test_Render_Menu (T : in out Fixture);
   procedure Test_Breadcrumbs (T : in out Fixture);
   procedure Test_Filtered_Menu (T : in out Fixture);
   procedure Test_Hardening (T : in out Fixture);

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

end Bridge_Tests;
