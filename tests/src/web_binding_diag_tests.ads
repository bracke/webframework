with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

--  Diagnostics tests: structured events emitted at the dispatch and upload-abort
--  seams, carrying only redaction-safe fields (ids, counts, rendered paths),
--  never raw request data.
package Web_Binding_Diag_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add the diagnostics tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  Dispatch emits Bind_Succeeded / Bind_Failed with redacted fields.
   --  @param Item AUnit fixture.
   procedure Test_Dispatch_Events (Item : in out Fixture);

   --  An aborted upload emits an Upload_Aborted event on session cleanup.
   --  @param Item AUnit fixture.
   procedure Test_Upload_Event (Item : in out Fixture);

end Web_Binding_Diag_Tests;
