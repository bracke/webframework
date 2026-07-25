with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

--  Tests for the two follow-on additions: the URI-component decoder and the
--  typed multipart binding helpers (Read_Field + Field_Tracker), the latter
--  binding a multipart form into a record with text fields and a file handle.
package Web_Binding_Extra_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add the tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  URI parsing: components and invalid forms.
   --  @param Item AUnit fixture.
   procedure Test_URI (Item : in out Fixture);

   --  Bind a multipart form into a record: text fields + a streamed file.
   --  @param Item AUnit fixture.
   procedure Test_Multipart_Bind (Item : in out Fixture);

   --  The multipart field tracker (duplicate detection, seen check).
   --  @param Item AUnit fixture.
   procedure Test_Field_Tracker (Item : in out Fixture);

end Web_Binding_Extra_Tests;
