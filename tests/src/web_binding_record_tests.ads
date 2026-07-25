with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

--  Phase 3 tests for builder-based record binding: typed assembly without
--  reflection, required/optional/default fields, malformed-not-defaulted, no
--  partial success, and deterministic aggregation vs fail-fast ordering.
package Web_Binding_Record_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add the record-binding tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  Successful binding and optional-default behaviour.
   --  @param Item AUnit fixture.
   procedure Test_Success (Item : in out Fixture);

   --  Missing-required and malformed-value errors; no partial success.
   --  @param Item AUnit fixture.
   procedure Test_Errors (Item : in out Fixture);

   --  Aggregation error order vs fail-fast.
   --  @param Item AUnit fixture.
   procedure Test_Aggregation (Item : in out Fixture);

end Web_Binding_Record_Tests;
