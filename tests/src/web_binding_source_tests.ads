with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

--  Phase 2 tests for the non-body request sources: query parsing (order,
--  duplicates, empty vs missing, percent-decoding), deterministic scalar
--  resolution under the duplicate and empty policies, route captures, headers,
--  cookies, and mixed-source extraction without touching the body.
package Web_Binding_Source_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add the source tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  Query parsing: order, duplicates, empty/missing, percent and plus.
   --  @param Item AUnit fixture.
   procedure Test_Query (Item : in out Fixture);

   --  Deterministic scalar resolution across duplicate and empty policies.
   --  @param Item AUnit fixture.
   procedure Test_Resolution (Item : in out Fixture);

   --  Route captures.
   --  @param Item AUnit fixture.
   procedure Test_Route (Item : in out Fixture);

   --  Header lookup.
   --  @param Item AUnit fixture.
   procedure Test_Headers (Item : in out Fixture);

   --  Cookie lookup and duplicate detection.
   --  @param Item AUnit fixture.
   procedure Test_Cookies (Item : in out Fixture);

   --  Mixed-source extraction (route + query) without body access.
   --  @param Item AUnit fixture.
   procedure Test_Mixed (Item : in out Fixture);

end Web_Binding_Source_Tests;
