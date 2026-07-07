with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

package Web_Core_Tests is
   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add core primitive tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  Test cookie parsing.
   --  @param Item AUnit fixture.
   procedure Test_Cookie_Parse (Item : in out Fixture);

   --  Test Set-Cookie generation.
   --  @param Item AUnit fixture.
   procedure Test_Set_Cookie (Item : in out Fixture);

   --  Test HTML escaping and validation helpers.
   --  @param Item AUnit fixture.
   procedure Test_HTML (Item : in out Fixture);

   --  Test request header helpers.
   --  @param Item AUnit fixture.
   procedure Test_Request_Headers (Item : in out Fixture);

   --  Test response construction and serialization.
   --  @param Item AUnit fixture.
   procedure Test_Response (Item : in out Fixture);

   --  Test logging configuration helpers.
   --  @param Item AUnit fixture.
   procedure Test_Logging (Item : in out Fixture);

   --  Test security helpers.
   --  @param Item AUnit fixture.
   procedure Test_Security (Item : in out Fixture);

   --  Test strict Origin and Host validation.
   --  @param Item AUnit fixture.
   procedure Test_Origin_Validation (Item : in out Fixture);
end Web_Core_Tests;
