with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

--  Phase 16 hardening tests: the defensive decode boundary (an exception becomes
--  internal.decoder_failure), concurrent shared use of immutable decoders and a
--  frozen registry (BIND-012), stream cancellation yielding a defined error with
--  no hang, and secret redaction (BIND-011).
package Web_Binding_Hardening_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add the hardening tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  A decoder that raises is caught and converted, no exception escapes.
   --  @param Item AUnit fixture.
   procedure Test_Guard (Item : in out Fixture);

   --  Many tasks share immutable decoders and a frozen registry without harm.
   --  @param Item AUnit fixture.
   procedure Test_Concurrency (Item : in out Fixture);

   --  A cancelled stream produces a defined error and terminates.
   --  @param Item AUnit fixture.
   procedure Test_Cancellation (Item : in out Fixture);

   --  Secret values are never retained or carried in errors.
   --  @param Item AUnit fixture.
   procedure Test_Redaction (Item : in out Fixture);

end Web_Binding_Hardening_Tests;
