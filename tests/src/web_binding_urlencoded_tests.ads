with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

--  Phase 5 tests for the URL-encoded body codec and the stream abstraction:
--  basic parse, fragmentation invariance across chunk sizes, malformed escape,
--  invalid UTF-8 (via the text decoder), field/pair/body limits, injected
--  stream faults, body ownership, and a fuzz harness.
package Web_Binding_URLEncoded_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add the URL-encoded codec tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  Basic parse: order, duplicates, percent and plus decoding.
   --  @param Item AUnit fixture.
   procedure Test_Basic (Item : in out Fixture);

   --  Identical results regardless of stream fragmentation.
   --  @param Item AUnit fixture.
   procedure Test_Fragmentation (Item : in out Fixture);

   --  Malformed escape flagged; a valid escape yielding invalid UTF-8 detected.
   --  @param Item AUnit fixture.
   procedure Test_Errors (Item : in out Fixture);

   --  Pair-count, field-length and body-size limits.
   --  @param Item AUnit fixture.
   procedure Test_Limits (Item : in out Fixture);

   --  Injected stream faults (premature EOF, read failure).
   --  @param Item AUnit fixture.
   procedure Test_Faults (Item : in out Fixture);

   --  Body ownership: a second claim is refused.
   --  @param Item AUnit fixture.
   procedure Test_Ownership (Item : in out Fixture);

   --  Adversarial corpus and pseudo-random fuzzing: always terminates, no
   --  exceptions, bounded output.
   --  @param Item AUnit fixture.
   procedure Test_Fuzz (Item : in out Fixture);

end Web_Binding_URLEncoded_Tests;
