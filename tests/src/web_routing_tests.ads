with AUnit.Test_Fixtures;
with AUnit.Test_Suites;
package Web_Routing_Tests is
   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;
   procedure Test_New_Verbs (T : in out Fixture);
   procedure Test_Path_Param (T : in out Fixture);
   procedure Test_Multi_Param (T : in out Fixture);
   procedure Test_Static_Beats_Pattern (T : in out Fixture);
   procedure Test_Method_Not_Allowed (T : in out Fixture);
   procedure Test_Auto_Options (T : in out Fixture);
   procedure Test_Not_Found (T : in out Fixture);
   procedure Test_Plain_Param_Rejected (T : in out Fixture);
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);
end Web_Routing_Tests;
