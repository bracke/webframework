with AUnit.Test_Fixtures;
with AUnit.Test_Suites;

package Web_Transport_Tests is
   type Fixture is new AUnit.Test_Fixtures.Test_Fixture with null record;

   --  Add transport tests to a suite.
   --  @param Suite Target AUnit suite.
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite);

   --  Test static content types.
   --  @param Item AUnit fixture.
   procedure Test_Static_Content_Types (Item : in out Fixture);

   --  Test static binary file serving.
   --  @param Item AUnit fixture.
   procedure Test_Static_Binary_Serving (Item : in out Fixture);

   --  Test large static files are represented as streamed file responses.
   --  @param Item AUnit fixture.
   procedure Test_Static_Large_File_Streaming (Item : in out Fixture);

   --  Test static traversal and read failure handling.
   --  @param Item AUnit fixture.
   procedure Test_Static_Read_Failures (Item : in out Fixture);

   --  Test HTTP request parsing.
   --  @param Item AUnit fixture.
   procedure Test_HTTP_Parse (Item : in out Fixture);

   --  Test HTTP request body parsing.
   --  @param Item AUnit fixture.
   procedure Test_HTTP_Body_Parse (Item : in out Fixture);

   --  Test hostile HTTP header and size inputs.
   --  @param Item AUnit fixture.
   procedure Test_HTTP_Hostile_Inputs (Item : in out Fixture);

   --  Test unsupported HTTP feature rejection.
   --  @param Item AUnit fixture.
   procedure Test_HTTP_Rejections (Item : in out Fixture);

   --  Test invalid route and static registrations.
   --  @param Item AUnit fixture.
   procedure Test_Invalid_Registrations (Item : in out Fixture);

   --  Test server runtime configuration enforcement.
   --  @param Item AUnit fixture.
   procedure Test_Server_Config (Item : in out Fixture);

   --  Test unsupported method dispatch.
   --  @param Item AUnit fixture.
   procedure Test_Method_Rejection (Item : in out Fixture);

   --  Test custom error response handlers.
   --  @param Item AUnit fixture.
   procedure Test_Error_Handlers (Item : in out Fixture);

   --  Test that pipelined requests are rejected over a socket.
   --  @param Item AUnit fixture.
   procedure Test_Pipelining_Rejection (Item : in out Fixture);

   --  Test WebSocket accept-key generation.
   --  @param Item AUnit fixture.
   procedure Test_WebSocket_Accept (Item : in out Fixture);

   --  Test WebSocket upgrade request detection.
   --  @param Item AUnit fixture.
   procedure Test_WebSocket_Upgrade_Detection (Item : in out Fixture);

   --  Test WebSocket masked frame decoding.
   --  @param Item AUnit fixture.
   procedure Test_WebSocket_Frame (Item : in out Fixture);

   --  Test hostile WebSocket frame rejection.
   --  @param Item AUnit fixture.
   procedure Test_WebSocket_Hostile_Frames (Item : in out Fixture);

   --  Test TLS server policy validation.
   --  @param Item AUnit fixture.
   procedure Test_TLS_Policy_Validation (Item : in out Fixture);

   --  Test connection wrapper handle validation.
   --  @param Item AUnit fixture.
   procedure Test_Connection_Validation (Item : in out Fixture);
end Web_Transport_Tests;
