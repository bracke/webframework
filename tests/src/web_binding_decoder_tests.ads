with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

--  Phase 1 tests for the scalar decoder framework: integer (invalid syntax vs
--  out of range, overflow, whitespace, separators, sign), Boolean, bounded text
--  (UTF-8, length), enumeration (wire mappings, case, aliases), UUID, and the
--  optional/default combinators. Confirms the acceptance rules: exact error
--  classification and no malformed-input exception flow.
package Web_Binding_Decoder_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add the decoder tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  Integer decoding: values, boundaries, invalid vs out-of-range, overflow.
   --  @param Item AUnit fixture.
   procedure Test_Integer (Item : in out Fixture);

   --  Boolean decoding: narrow default, optional sets, case folding.
   --  @param Item AUnit fixture.
   procedure Test_Boolean (Item : in out Fixture);

   --  Bounded text decoding: UTF-8 validation and length bounds.
   --  @param Item AUnit fixture.
   procedure Test_Text (Item : in out Fixture);

   --  Enumeration decoding: wire mappings, case modes, aliases.
   --  @param Item AUnit fixture.
   procedure Test_Enum (Item : in out Fixture);

   --  UUID decoding: canonical form and normalization.
   --  @param Item AUnit fixture.
   procedure Test_UUID (Item : in out Fixture);

   --  Optional and default combinators, including malformed-not-defaulted.
   --  @param Item AUnit fixture.
   procedure Test_Combinators (Item : in out Fixture);

end Web_Binding_Decoder_Tests;
