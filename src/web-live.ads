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

   --  A visitor carries per-call data into the (serialized) state update
   --  without a shared global: the concrete visitor's own fields hold the
   --  inputs, so two concurrent updates never clobber one another. Prefer this
   --  over State_Process whenever the update depends on request-specific data
   --  (a State_Process access value can only reach such data through a global,
   --  which races under concurrent requests).
   type State_Visitor is abstract tagged null record;
   procedure Apply
     (Self : in out State_Visitor; State : in out App_State) is abstract;

   --  Find or create a session for a request.
   --
   --  This is side-effecting: for a request that carries no (valid) session
   --  cookie it CREATES a fresh session and returns a new id, so two calls for
   --  the same cookieless request return DIFFERENT ids. Resolve the session
   --  ONCE per request into a local and reuse that id -- both to set the cookie
   --  (Html_Response) and to derive anything bound to the session (e.g. a CSRF
   --  token). Resolving twice would bind the token to one session and the
   --  cookie to another.
   --  @param Request HTTP request.
   --  @return Session id.
   function Find_Or_Create_Session (Request : Web.Request.Request_Type) return String;

   --  Require an existing session from a request cookie.
   --  @param Request HTTP request.
   --  @return Session id or an empty string.
   function Require_Session (Request : Web.Request.Request_Type) return String;

   --  Invalidate a session immediately, dropping its server-side state and
   --  closing any attached websocket. Use on logout. A null or unknown id is a
   --  no-op.
   --  @param Id Session id to invalidate.
   --  @return No return value.
   procedure Invalidate_Session (Id : String);

   --  Rotate a session's id while preserving its state, returning the new id.
   --  Use on privilege change (for example right after login) to defeat session
   --  fixation: the old id stops working and any socket bound to it is dropped.
   --  @param Old_Id Current session id.
   --  @return New session id, or an empty string when Old_Id names no session.
   function Regenerate_Session (Old_Id : String) return String;

   --  Build the session Set-Cookie header.
   --  @param Id Session id.
   --  @return Set-Cookie header value.
   function Session_Cookie_Header (Id : String) return String;

   --  Build an HTML response that carries the session cookie for an
   --  already-resolved session. The caller resolves the session once (see
   --  Find_Or_Create_Session) and passes that id, so the cookie and anything
   --  else derived from the session always name the same session.
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

   --  Return the number of currently stored sessions.
   --  @return Current session count.
   function Session_Count return Natural;

   --  Return the number of sessions with an active WebSocket.
   --  @return Current active WebSocket count.
   function Active_WebSocket_Count return Natural;

   --  Serialize access to session state.
   --  @param Id Session id.
   --  @param Process Callback executed with mutable state.
   --  @return No return value.
   procedure With_State (Id : String; Process : State_Process);

   --  Serialize access to session state, running a visitor that carries its
   --  own per-call data (see State_Visitor). Use this instead of the
   --  State_Process overload when the update depends on request-specific data.
   --  @param Id Session id.
   --  @param Visitor Visitor whose Apply runs with mutable state.
   --  @return No return value.
   procedure With_State (Id : String; Visitor : in out State_Visitor'Class);

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

   --  Check whether periodic background cleanup is currently started.
   --  @return True when the cleanup task has been started and not stopped.
   function Cleanup_Task_Running return Boolean;

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

   --  Set the ping interval for connection health checks.
   --  @param Seconds Ping interval in seconds; zero disables ping.
   --  @return No return value.
   procedure Set_Ping_Interval (Seconds : Natural);

   --  Get the current ping interval.
   --  @return Ping interval in seconds.
   function Ping_Interval return Natural;

   --  Set the maximum number of messages per minute allowed from a client.
   --  @param Count Maximum messages per minute; zero disables rate limiting.
   --  @return No return value.
   procedure Set_Rate_Limit (Count : Natural);

   --  Get the current rate limit.
   --  @return Maximum messages per minute.
   function Rate_Limit return Natural;

   --  Set the message retention window for deduplication (in seconds).
   --  @param Seconds Deduplication window; zero disables deduplication.
   --  @return No return value.
   procedure Set_Deduplication_Window (Seconds : Natural);

   --  Get the current deduplication window.
   --  @return Deduplication window in seconds.
   function Deduplication_Window return Natural;

   --  Check if a session is currently connected via WebSocket.
   --  @param Id Session id.
   --  @return True if session has active WebSocket connection.
   function Is_Connected (Id : String) return Boolean;

   --  Get connection statistics for a session.
   --  @param Id Session id.
   --  @return Statistics string or empty if not found.
   function Connection_Stats (Id : String) return String;
end Web.Live;
