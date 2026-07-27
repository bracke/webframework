with GNAT.Sockets;
with Web.Connection;
with Web.Config;
with Web.Dispatcher;
with Web.Guard;
with Web.Live;
with Web.Request;
with Web.Response;
with Web.Server;

--  High-level façade for a websocket-aware application.
--
--  The package combines a typed `Web.Dispatcher` with a matching `Web.Live`
--  instance so callers only instantiate one generic at startup.
generic
   type App_State is private;
   with function Initial_State return App_State;
package Web.Application is
   --  Re-export the underlying dispatcher for direct access when needed.
   package Dispatcher is new Web.Dispatcher (App_State);

   --  Re-export the underlying session/live layer for direct access when needed.
   package Live is new Web.Live
     (App_State     => App_State,
      Initial_State => Initial_State,
      Dispatch      => Dispatcher.Dispatch);

   --  Convenience aliases for the server handler types.
   subtype Route_Handler_Access is Web.Server.Route_Handler;

   subtype Stream_Handler_Access is Web.Server.Stream_Handler;

   subtype WebSocket_Handler_Access is Web.Server.WebSocket_Handler;

   --  Register an action handler.
   --  @param Action Action string that client events must send.
   --  @param Handler Handler function that mutates session state.
   --  @return No return value.
   procedure Register (Action : String; Handler : Dispatcher.Handler_Access);

   --  Register an action handler protected by a per-action authorization guard.
   --  The guard runs before the handler on every dispatch; a rejected action
   --  produces no patches. Use to gate live actions by the session's role.
   --  @param Action Action string that client events must send.
   --  @param Handler Handler function that mutates session state.
   --  @param Guard Authorization guard; must not be null.
   --  @return No return value.
   procedure Register
     (Action  : String;
      Handler : Dispatcher.Handler_Access;
      Guard   : Dispatcher.Action_Guard);

   --  Find or create a session for a request.
   --  @param Request Parsed HTTP request.
   --  @return Session identifier.
   function Find_Or_Create_Session (Request : Web.Request.Request_Type) return String;

   --  Require a session from a request cookie.
   --  @param Request Parsed HTTP request.
   --  @return Session identifier or empty string when no cookie exists.
   function Require_Session (Request : Web.Request.Request_Type) return String;

   --  Invalidate a session immediately (drops state, closes any socket). Logout.
   --  @param Id Session identifier to invalidate.
   --  @return No return value.
   procedure Invalidate_Session (Id : String);

   --  Rotate a session id, preserving its state, and return the new id. Use on
   --  privilege change (after login) to defeat session fixation.
   --  @param Old_Id Current session identifier.
   --  @return New session identifier, or empty string when Old_Id is unknown.
   function Regenerate_Session (Old_Id : String) return String;

   --  Build the session cookie header value.
   --  @param Id Session identifier.
   --  @return Set-Cookie header value.
   function Session_Cookie_Header (Id : String) return String;

   --  Build an HTML response with the session cookie attached, for a session
   --  the caller has already resolved (once) via Find_Or_Create_Session. Pass
   --  that same id anywhere else the session is needed (e.g. a CSRF token) so
   --  the cookie and the token always name the same session.
   --  @param Session Session identifier.
   --  @param Content HTML content.
   --  @return HTTP response.
   function Html_Response
     (Session : String; Content : String) return Web.Response.Response_Type;

   --  Configure session and websocket behavior.
   --  @param Config Framework configuration.
   --  @return No return value.
   procedure Configure (Config : Web.Config.Config_Type);

   --  Set the session cookie secure flag.
   --  @param Enabled True to include `Secure` on session cookies.
   --  @return No return value.
   procedure Set_Secure_Cookies (Enabled : Boolean);

   --  Check session cookie security mode.
   --  @return True when Secure session cookies are enabled.
   function Secure_Cookies return Boolean;

   --  Serialize access to a session state value.
   --  @param Id Session identifier.
   --  @param Process Callback for in-place mutable state access.
   --  @return No return value.
   procedure With_State (Id : String; Process : Live.State_Process);

   --  Serialize access to a session state value, running a visitor that carries
   --  its own per-call data (see Live.State_Visitor) -- use this instead of the
   --  State_Process overload when the update depends on request-specific data,
   --  so concurrent requests never share a mutable global.
   --  @param Id Session identifier.
   --  @param Visitor Visitor whose Apply runs with mutable state.
   --  @return No return value.
   procedure With_State
     (Id : String; Visitor : in out Live.State_Visitor'Class);

   --  Return number of active sessions.
   --  @return Count of sessions tracked by this application.
   function Session_Count return Natural;

   --  Return number of sessions with an attached websocket.
   --  @return Count of sessions with an active socket.
   function Active_WebSocket_Count return Natural;

   --  Remove expired sessions and detach sockets.
   --  @return Number of removed sessions.
   function Cleanup_Sessions return Natural;

   --  Connection hardening functions
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

   --  Run the websocket loop for a connected socket.
   --  @param Conn Existing websocket transport connection.
   --  @param Id Session identifier.
   --  @return No return value.
   procedure Run_Connection (Conn : in out Web.Connection.Connection_Type; Id : String);

   --  Run the websocket loop for a raw socket.
   --  @param Socket Connected TCP socket.
   --  @param Id Session identifier.
   --  @return No return value.
   procedure Run_Connection (Socket : GNAT.Sockets.Socket_Type; Id : String);

   --  Route-compatible websocket handler.
   --  @param Conn Connected transport.
   --  @param Request Parsed websocket upgrade request.
   --  @return No return value.
   procedure WebSocket_Handler
     (Conn    : in out Web.Connection.Connection_Type;
      Request : Web.Request.Request_Type);

   --  Register HTTP and websocket routes through the façade for reduced import set.
   --  @param Path Exact route path.
   --  @param Handler Route handler.
   --  @return No return value.
   procedure Get (Path : String; Handler : Route_Handler_Access);

   --  Register a POST route through the façade for reduced import set.
   --  @param Path Exact route path.
   --  @param Handler Route handler.
   --  @return No return value.
   procedure Post (Path : String; Handler : Route_Handler_Access);

   --  Register a streaming POST route (e.g. a large upload). The handler pulls
   --  the body from a reader instead of receiving it buffered; guards run first.
   procedure Post_Stream
     (Path    : String;
      Handler : Stream_Handler_Access;
      Guard   : Web.Guard.Guard_Access := null);

   --  Install a global guard that runs before every request (see
   --  Web.Server.Use_Guard). This is where an application resolves the request
   --  principal once for all routes.
   --  @param Guard Guard to install; must not be null.
   --  @return No return value.
   procedure Use_Guard (Guard : Web.Guard.Guard_Access);

   --  Register a context-aware GET route, optionally guarded. The handler
   --  receives the request context the guards populated (for example the
   --  resolved principal), so authorization gating composes cleanly.
   --  @param Path Exact route path.
   --  @param Handler Context-aware route handler.
   --  @param Guard Optional per-route guard; null installs none.
   --  @return No return value.
   procedure Get
     (Path    : String;
      Handler : Web.Guard.Contextual_Handler;
      Guard   : Web.Guard.Guard_Access := null);

   --  Register a context-aware POST route, optionally guarded.
   --  @param Path Exact route path.
   --  @param Handler Context-aware route handler.
   --  @param Guard Optional per-route guard; null installs none.
   --  @return No return value.
   procedure Post
     (Path    : String;
      Handler : Web.Guard.Contextual_Handler;
      Guard   : Web.Guard.Guard_Access := null);

   --  Register a websocket route through the façade for reduced import set.
   --  @param Path Exact websocket path.
   --  @param Handler WebSocket handler.
   --  @return No return value.
   procedure WebSocket (Path : String; Handler : WebSocket_Handler_Access);

   --  Guard a websocket route: global guards and this guard run before the
   --  upgrade, and a halting guard rejects the handshake. Register the route
   --  with WebSocket first, then guard it here.
   --  @param Path Exact websocket path.
   --  @param Guard Guard to install; must not be null.
   --  @return No return value.
   procedure Guard_WebSocket (Path : String; Guard : Web.Guard.Guard_Access);

   --  Register static assets through the façade for reduced import set.
   --  @param Url_Prefix URL path prefix.
   --  @param Directory File system directory.
   --  @return No return value.
   procedure Static (Url_Prefix : String; Directory : String);

   --  Register static assets with versioning support through the façade.
   --  @param Url_Prefix URL path prefix.
   --  @param Directory File system directory.
   --  @return No return value.
   procedure Static_Versioned (Url_Prefix : String; Directory : String);

   --  Register a custom HTTP error handler.
   --  @param Status HTTP status code in the range 100 .. 599.
   --  @param Handler Error response handler.
   --  @return No return value.
   procedure Register_Error_Handler
     (Status  : Positive;
      Handler : Web.Server.Error_Handler);

   --  Remove a registered custom HTTP error handler.
   --  @param Status HTTP status code in the range 100 .. 599.
   --  @return No return value.
   procedure Clear_Error_Handler (Status : Positive);

   --  Run the configured server loop.
   --  @param Host Listen host.
   --  @param Port Listen port.
   --  @return No return value.
   procedure Run (Host : String; Port : Natural);

   --  Run the configured HTTPS server loop from configuration.
   --  @param Host Listen host.
   --  @param Port Listen port.
   --  @param Config Runtime configuration containing TLS policy.
   --  @return No return value.
   procedure Run_TLS (Host : String; Port : Natural; Config : Web.Config.Config_Type);

   --  Return a short configuration summary.
   --  @return Human-readable configuration summary.
   function Configuration_Report return String;

   --  Return server running state.
   --  @return True when the server loop is currently active.
   function Server_Running return Boolean;

   --  Request server stop.
   --  @return No return value.
   procedure Stop;

   --  Return a preconfigured health response.
   --  @return HTTP response with a simple health body.
   function Health_Response return Web.Response.Response_Type;
end Web.Application;
