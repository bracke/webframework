with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

--  Phase 4 tests: collection binding (repeated values, exact indexed paths,
--  min/max item bounds, per-element errors), delimited-scalar collections,
--  nested record binding (composition, nested error aggregation, optional-None,
--  required-missing) and the depth guard.
package Web_Binding_Collection_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add the collection and nesting tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  Repeated-value collection: order, indexed paths, bounds, element errors.
   --  @param Item AUnit fixture.
   procedure Test_Collection (Item : in out Fixture);

   --  Delimited-scalar collection via Sources.Split.
   --  @param Item AUnit fixture.
   procedure Test_Delimited (Item : in out Fixture);

   --  Nested record: composition, aggregation, optional-None, required-missing.
   --  @param Item AUnit fixture.
   procedure Test_Nested (Item : in out Fixture);

   --  The nesting depth guard.
   --  @param Item AUnit fixture.
   procedure Test_Depth (Item : in out Fixture);

end Web_Binding_Collection_Tests;
