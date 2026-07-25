with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

--  Phase 12 tests for the Forms adapter: the submission state model and a full
--  form re-render (retained values for valid and invalid fields, secrets never
--  retained, per-field and non-field errors from the bind result).
package Web_Binding_Form_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add the form tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  A submission with an invalid field: re-render data and secret redaction.
   --  @param Item AUnit fixture.
   procedure Test_Rerender (Item : in out Fixture);

   --  The submission state transitions.
   --  @param Item AUnit fixture.
   procedure Test_States (Item : in out Fixture);

end Web_Binding_Form_Tests;
