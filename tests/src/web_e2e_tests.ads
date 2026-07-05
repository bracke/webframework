with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

package Web_E2E_Tests is
   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add end-to-end server tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  Test GET, session cookie, WebSocket upgrade, event dispatch, and patch response.
   --  @param Item AUnit fixture.
   procedure Test_Server_Live_Flow (Item : in out Fixture);

   --  Test HTTPS GET over the native TLS transport.
   --  @param Item AUnit fixture.
   procedure Test_TLS_Server_Flow (Item : in out Fixture);
end Web_E2E_Tests;
