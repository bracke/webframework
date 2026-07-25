with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

--  Phase 14 tests for the identity/authorization adapters: Authorization-header
--  syntax decoding (no verification), a login input with secret redaction, and a
--  resource-identifier binding that authorization would consume elsewhere.
package Web_Binding_Auth_Tests is

   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add the auth adapter tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  Authorization header parsing and Basic credential decoding.
   --  @param Item AUnit fixture.
   procedure Test_Auth_Header (Item : in out Fixture);

   --  Login input: username retained, password (secret) redacted.
   --  @param Item AUnit fixture.
   procedure Test_Login (Item : in out Fixture);

   --  Resource-identifier binding yields a typed value for authorization.
   --  @param Item AUnit fixture.
   procedure Test_Resource_Id (Item : in out Fixture);

end Web_Binding_Auth_Tests;
