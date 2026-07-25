with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

--  Phase 6 tests for the streaming JSON tokenizer: structural token stream,
--  the escape matrix (incl. surrogate pairs), the number grammar matrix, strict
--  rejections (trailing content/comma, comments), bounds (depth, string and
--  number length), source locations, fragmentation invariance, and a fuzz
--  harness.
package Web_Binding_JSON_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add the JSON tokenizer tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  Structural token stream for objects and arrays.
   --  @param Item AUnit fixture.
   procedure Test_Structure (Item : in out Fixture);

   --  Escape handling and surrogate pairs; invalid escapes rejected.
   --  @param Item AUnit fixture.
   procedure Test_Escapes (Item : in out Fixture);

   --  The strict number grammar: valid and invalid literals.
   --  @param Item AUnit fixture.
   procedure Test_Numbers (Item : in out Fixture);

   --  Strict rejections: trailing content, trailing comma, comments.
   --  @param Item AUnit fixture.
   procedure Test_Strict (Item : in out Fixture);

   --  Depth, string-length and number-length bounds.
   --  @param Item AUnit fixture.
   procedure Test_Limits (Item : in out Fixture);

   --  Token source locations (line, column, offset).
   --  @param Item AUnit fixture.
   procedure Test_Location (Item : in out Fixture);

   --  Identical token stream regardless of stream fragmentation.
   --  @param Item AUnit fixture.
   procedure Test_Fragmentation (Item : in out Fixture);

   --  Fuzz: adversarial and pseudo-random inputs always terminate, no crash.
   --  @param Item AUnit fixture.
   procedure Test_Fuzz (Item : in out Fixture);

end Web_Binding_JSON_Tests;
