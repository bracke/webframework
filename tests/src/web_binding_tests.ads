with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

--  Phase 0 tests for the request binding foundations: structured paths, error
--  identifiers, bounded deterministic error collections, layered limits and the
--  typed result. These pin the foundational invariants (BIND-002, 004, 005, 006)
--  that later phases build on.
package Web_Binding_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add the binding foundation tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  Structured paths render to their canonical strings (BIND-006).
   --  @param Item AUnit fixture.
   procedure Test_Path_Rendering (Item : in out Fixture);

   --  Error identifiers render to stable dotted keys (BIND-005).
   --  @param Item AUnit fixture.
   procedure Test_Error_Keys (Item : in out Fixture);

   --  Error collections are bounded and truncate deterministically (BIND-004).
   --  @param Item AUnit fixture.
   procedure Test_Error_Collection (Item : in out Fixture);

   --  Limits tighten in layers and never widen an outer bound.
   --  @param Item AUnit fixture.
   procedure Test_Limit_Layering (Item : in out Fixture);

   --  A successful result carries a value; a failure carries errors (BIND-002).
   --  @param Item AUnit fixture.
   procedure Test_Result_Shape (Item : in out Fixture);

end Web_Binding_Tests;
