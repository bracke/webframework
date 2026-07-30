with AUnit.Test_Fixtures;
with AUnit.Test_Suites;
package Web_SSE_Tests is
   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;
   procedure Test_Simple (T : in out Fixture);
   procedure Test_Event_And_Id (T : in out Fixture);
   procedure Test_Multiline_Data (T : in out Fixture);
   procedure Test_Empty_Data (T : in out Fixture);
   procedure Test_Data_Injection (T : in out Fixture);
   procedure Test_Field_Injection (T : in out Fixture);
   procedure Test_Comment_And_Retry (T : in out Fixture);
   procedure Test_Response_Headers (T : in out Fixture);
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);
end Web_SSE_Tests;
