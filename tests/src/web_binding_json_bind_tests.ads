with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

--  Phase 7 tests for typed JSON binding: an object bound into a record through
--  deterministic member dispatch, with an array field and a nested object, plus
--  duplicate/unknown members, null and type-mismatch handling, missing-required,
--  exact JSON paths, and error aggregation within a structurally valid object.
package Web_Binding_JSON_Bind_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add the typed JSON binding tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  A full object with array and nested object binds to typed fields.
   --  @param Item AUnit fixture.
   procedure Test_Bind (Item : in out Fixture);

   --  Duplicate, unknown, null, type-mismatch and missing-required members.
   --  @param Item AUnit fixture.
   procedure Test_Member_Errors (Item : in out Fixture);

   --  Exact JSON paths and error aggregation across members.
   --  @param Item AUnit fixture.
   procedure Test_Paths_And_Aggregation (Item : in out Fixture);

end Web_Binding_JSON_Bind_Tests;
