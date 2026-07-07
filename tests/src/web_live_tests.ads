with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

package Web_Live_Tests is
   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add live session tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  Test the live WebSocket event loop.
   --  @param Item AUnit fixture.
   procedure Test_Run_Connection (Item : in out Fixture);

   --  Test that a new socket replaces the previous session socket.
   --  @param Item AUnit fixture.
   procedure Test_Socket_Replacement (Item : in out Fixture);

   --  Test that expired sessions are removed.
   --  @param Item AUnit fixture.
   procedure Test_Session_Cleanup (Item : in out Fixture);

   --  Test secure cookie session settings.
   --  @param Item AUnit fixture.
   procedure Test_Secure_Cookie_Settings (Item : in out Fixture);

   --  Test live session resource counters.
   --  @param Item AUnit fixture.
   procedure Test_Resource_Counters (Item : in out Fixture);

   --  Test configured WebSocket message size limits.
   --  @param Item AUnit fixture.
   procedure Test_WebSocket_Message_Limit (Item : in out Fixture);

   --  Test that malformed session cookie values are ignored.
   --  @param Item AUnit fixture.
   procedure Test_Invalid_Session_Cookie (Item : in out Fixture);

   --  Test background cleanup removes expired sessions.
   --  @param Item AUnit fixture.
   procedure Test_Background_Cleanup (Item : in out Fixture);

   --  Test that cleanup closes active expired session sockets.
   --  @param Item AUnit fixture.
   procedure Test_Cleanup_Closes_Socket (Item : in out Fixture);
end Web_Live_Tests;
