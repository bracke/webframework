with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

--  Phase 9 tests: structural media-type parsing (type/subtype/suffix/charset/
--  boundary, quoted params, invalid syntax) and the immutable codec registry
--  (deterministic exact/suffix/wildcard selection, missing-Content-Type policy,
--  and freeze-time ambiguity / invalid-wildcard detection).
package Web_Binding_Media_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add the media-type and registry tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  Media-type parsing, incl. charset, boundary, suffix and invalid syntax.
   --  @param Item AUnit fixture.
   procedure Test_Parse (Item : in out Fixture);

   --  Deterministic codec selection and the missing-Content-Type policy.
   --  @param Item AUnit fixture.
   procedure Test_Selection (Item : in out Fixture);

   --  Freeze-time validation: ambiguous patterns and invalid wildcards.
   --  @param Item AUnit fixture.
   procedure Test_Freeze (Item : in out Fixture);

end Web_Binding_Media_Tests;
