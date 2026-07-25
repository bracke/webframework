with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

--  Phase 10 tests for the streaming multipart parser: parsing text and file
--  parts, fragmentation invariance across chunk sizes (boundary split anywhere),
--  the part/header/field limits, malformed framing, and a fuzz harness.
package Web_Binding_Multipart_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add the multipart tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  Parse fields and a file part; names, filename, content-type, values.
   --  @param Item AUnit fixture.
   procedure Test_Parse (Item : in out Fixture);

   --  Identical result regardless of stream fragmentation.
   --  @param Item AUnit fixture.
   procedure Test_Fragmentation (Item : in out Fixture);

   --  Part-count, header-size and field-size limits, and malformed framing.
   --  @param Item AUnit fixture.
   procedure Test_Limits (Item : in out Fixture);

   --  Fuzz: adversarial and pseudo-random inputs always terminate, no crash.
   --  @param Item AUnit fixture.
   procedure Test_Fuzz (Item : in out Fixture);

end Web_Binding_Multipart_Tests;
