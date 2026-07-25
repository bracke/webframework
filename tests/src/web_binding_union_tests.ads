with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

--  Phase 8 tests: tagged discriminated-union binding from JSON with safe
--  construction (the discriminated value is built once with the resolved
--  discriminant, never mutated), the discriminator error cases (missing,
--  invalid, wrong-alternative field), and structural-union ambiguity resolution.
package Web_Binding_Union_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add the union tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  Both alternatives bind and construct correctly.
   --  @param Item AUnit fixture.
   procedure Test_Tagged (Item : in out Fixture);

   --  Missing / invalid discriminator and wrong-alternative field.
   --  @param Item AUnit fixture.
   procedure Test_Discriminator_Errors (Item : in out Fixture);

   --  Structural union resolution: exactly-one, ambiguous, no-match.
   --  @param Item AUnit fixture.
   procedure Test_Structural (Item : in out Fixture);

end Web_Binding_Union_Tests;
