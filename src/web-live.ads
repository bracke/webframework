with GNAT.Sockets;
with Web.Config;
with Web.Connection;
with Web.Events;
with Web.Patch;
with Web.Request;
with Web.Response;

generic
   type App_State is private;
   with function Initial_State return App_State;
   with function Dispatch
     (State : in out App_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List;
package Web.Live is
   subtype Session_Id is String;

   type State_Process is access procedure (State : in out App_State);

   --  Find or create a session for a request.
   --  @param Request HTTP request.
   --  @return Session id.
   function Find_Or_Create_Session (Request : Web.Request.Request_Type) return String;

   --  Require an existing session from a request cookie.
   --  @param Request HTTP request.
   --  @return Session id or an empty string.
   function Require_Session (Request : Web.Request.Request_Type) return String;

   --  Build the session Set-Cookie header.
   --  @param Id Session id.
   --  @return Set-Cookie header value.
   function Session_Cookie_Header (Id : String) return String;

   --  Build an HTML response that carries the session cookie.
   --  @param Session Session id.
   --  @param Content HTML body.
   --  @return HTTP response.
   function Html_Response (Session : String; Content : String) return Web.Response.Response_Type;

   --  Apply session settings from framework configuration.
   --  @param Config Framework configuration.
   --  @return No return value.
   procedure Configure (Config : Web.Config.Config_Type);

   --  Set whether session cookies include the Secure attribute.
   --  @param Enabled True to emit Secure session cookies.
   --  @return No return value.
   procedure Set_Secure_Cookies (Enabled : Boolean);

   --  Check whether session cookies include the Secure attribute.
   --  @return True when Secure cookies are enabled.
   function Secure_Cookies return Boolean;

   --  Serialize access to session state.
   --  @param Id Session id.
   --  @param Process Callback executed with mutable state.
   --  @return No return value.
   procedure With_State (Id : String; Process : State_Process);

   --  Set the inactivity timeout used by cleanup.
   --  @param Seconds Timeout in seconds; zero expires all sessions on cleanup.
   --  @return No return value.
   procedure Set_Session_Timeout (Seconds : Natural);

   --  Remove expired sessions and close their active sockets.
   --  @return Number of sessions removed.
   function Cleanup_Sessions return Natural;

   --  Start periodic background session cleanup.
   --  @param Interval_Seconds Cleanup interval in seconds.
   --  @return No return value.
   procedure Start_Cleanup_Task (Interval_Seconds : Positive := 60);

   --  Stop periodic background session cleanup when it is running.
   --  @return No return value.
   procedure Stop_Cleanup_Task;

   --  Run the WebSocket event loop for a session.
   --  @param Conn Connected transport.
   --  @param Id Session id.
   --  @return No return value.
   procedure Run_Connection
     (Conn : in out Web.Connection.Connection_Type;
      Id   : String);

   --  Run the WebSocket event loop for a plain socket.
   --  @param Socket Connected plain socket.
   --  @param Id Session id.
   --  @return No return value.
   procedure Run_Connection (Socket : GNAT.Sockets.Socket_Type; Id : String);

   --  Route-compatible WebSocket handler.
   --  @param Conn Connected transport.
   --  @param Request HTTP request.
   --  @return No return value.
   procedure WebSocket_Handler
     (Conn    : in out Web.Connection.Connection_Type;
      Request : Web.Request.Request_Type);
end Web.Live;
