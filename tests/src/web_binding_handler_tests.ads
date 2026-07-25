with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

--  Phase 15 tests for the typed-handler adapter: failure classification into
--  HTTP status classes, the per-request binding context, and dispatch that runs
--  the application handler only on success (with the complete typed value).
package Web_Binding_Handler_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add the handler tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  Error-to-status classification, worst-wins and route 404 policy.
   --  @param Item AUnit fixture.
   procedure Test_Classify (Item : in out Fixture);

   --  The per-request binding context.
   --  @param Item AUnit fixture.
   procedure Test_Context (Item : in out Fixture);

   --  Dispatch runs the handler only on success; failures go to the mapper.
   --  @param Item AUnit fixture.
   procedure Test_Dispatch (Item : in out Fixture);

end Web_Binding_Handler_Tests;
