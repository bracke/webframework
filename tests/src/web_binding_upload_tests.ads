with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

--  Phase 11 tests for the Files and Uploads adapter: streaming a multipart file
--  part into an upload sink (byte count + checksum, never fully buffered),
--  per-upload and aggregate limits, an injected sink write failure, and
--  deterministic abort/cleanup of an uncommitted upload on session scope exit.
package Web_Binding_Upload_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add the upload tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  Stream a file part; verify byte count, checksum, finished, committed.
   --  @param Item AUnit fixture.
   procedure Test_Stream (Item : in out Fixture);

   --  Per-upload and aggregate byte limits abort the upload.
   --  @param Item AUnit fixture.
   procedure Test_Limits (Item : in out Fixture);

   --  An injected sink write failure aborts the upload.
   --  @param Item AUnit fixture.
   procedure Test_Sink_Failure (Item : in out Fixture);

   --  An uncommitted upload is aborted when the session goes out of scope.
   --  @param Item AUnit fixture.
   procedure Test_Cleanup (Item : in out Fixture);

end Web_Binding_Upload_Tests;
