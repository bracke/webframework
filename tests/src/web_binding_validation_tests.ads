with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

--  Phase 13 tests for the Validation adapter: the typed handoff where decoding
--  succeeds but a semantic rule fails, and a merged presentation that preserves
--  each entry's origin (decoding vs validation).
package Web_Binding_Validation_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add the validation tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  Decoding succeeds, a semantic rule fails: a validation-origin entry only.
   --  @param Item AUnit fixture.
   procedure Test_Semantic_Failure (Item : in out Fixture);

   --  Decoding and validation errors merge, preserving origin and order.
   --  @param Item AUnit fixture.
   procedure Test_Merged_Origin (Item : in out Fixture);

end Web_Binding_Validation_Tests;
