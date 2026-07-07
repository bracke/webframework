with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

package Web_Protocol_Tests is
   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add protocol and patch tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  Test patch constructors and list append.
   --  @param Item AUnit fixture.
   procedure Test_Patches (Item : in out Fixture);

   --  Test protocol decode for hello, click, and submit.
   --  @param Item AUnit fixture.
   procedure Test_Decode (Item : in out Fixture);

   --  Test JSON escapes and nested unknown values.
   --  @param Item AUnit fixture.
   procedure Test_JSON_Robustness (Item : in out Fixture);

   --  Test malformed protocol rejection.
   --  @param Item AUnit fixture.
   procedure Test_Malformed_Rejection (Item : in out Fixture);

   --  Test server patch encoding.
   --  @param Item AUnit fixture.
   procedure Test_Encode (Item : in out Fixture);

   --  Test helper functions for event field access.
   --  @param Item AUnit fixture.
   procedure Test_Event_Helpers (Item : in out Fixture);

   --  Test generic dispatcher behavior.
   --  @param Item AUnit fixture.
   procedure Test_Dispatcher (Item : in out Fixture);
end Web_Protocol_Tests;
