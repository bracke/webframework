with Web.Config;
with Web.Connection;
with Web.Guard;
with Web.Http_Body;
with Web.Request;
with Web.Response;
with Web.TLS;

package Web.Server is
   type Route_Handler is access function
     (Request : Web.Request.Request_Type) return Web.Response.Response_Type;

   --  A streaming POST handler. The request carries only the headers (the body
   --  is not buffered); the handler pulls the body incrementally from Body_R,
   --  typically into a webuploads session, so an arbitrarily large upload uses
   --  bounded memory. Any body-authenticating token (e.g. CSRF) must therefore
   --  travel in the request line/headers, not the body, since it is checked
   --  before the body is read.
   type Stream_Handler is access function
     (Request : Web.Request.Request_Type;
      Body_R  : in out Web.Http_Body.Reader) return Web.Response.Response_Type;

   --  Error page handler signature.
   --  @param Request Parsed request that caused the error.
   --  @param Status HTTP status code in the range 100 .. 599.
   --  @param Detail Optional status-specific error detail.
   --  @return Custom response to return for that status code.
   type Error_Handler is access function
     (Request : Web.Request.Request_Type;
      Status  : Positive;
      Detail  : String) return Web.Response.Response_Type;

   type WebSocket_Handler is access procedure
     (Conn    : in out Web.Connection.Connection_Type;
      Request : Web.Request.Request_Type);

   --  Register a GET route.
   --  @param Path Exact route path.
   --  @param Handler Route handler.
   --  @return No return value.
   procedure Get (Path : String; Handler : Route_Handler);

   --  Register a POST route.
   --  @param Path Exact route path.
   --  @param Handler Route handler.
   --  @return No return value.
   procedure Post (Path : String; Handler : Route_Handler);

   --  Register a streaming POST route (e.g. a large-file upload). The body is
   --  not buffered: the handler pulls it from the reader. Global guards and the
   --  optional route Guard run before the handler, exactly as for other routes.
   procedure Post_Stream
     (Path    : String;
      Handler : Stream_Handler;
      Guard   : Web.Guard.Guard_Access := null);

   --  Register a global guard that runs before every dispatched GET/POST
   --  request, ahead of any route guard. Guards run in registration order and
   --  the first to halt wins. Use for cross-cutting concerns such as resolving
   --  the request principal once for the whole application.
   --  @param Guard Guard to install; must not be null.
   --  @return No return value.
   procedure Use_Guard (Guard : Web.Guard.Guard_Access);

   --  Register a context-aware GET route, optionally protected by a guard.
   --  The handler receives the request context the guards populated.
   --  @param Path Exact route path.
   --  @param Handler Context-aware route handler.
   --  @param Guard Optional per-route guard; null installs none.
   --  @return No return value.
   procedure Get
     (Path    : String;
      Handler : Web.Guard.Contextual_Handler;
      Guard   : Web.Guard.Guard_Access := null);

   --  Register a context-aware POST route, optionally protected by a guard.
   --  @param Path Exact route path.
   --  @param Handler Context-aware route handler.
   --  @param Guard Optional per-route guard; null installs none.
   --  @return No return value.
   procedure Post
     (Path    : String;
      Handler : Web.Guard.Contextual_Handler;
      Guard   : Web.Guard.Guard_Access := null);

   --  Register a WebSocket route.
   --  @param Path Exact route path.
   --  @param Handler WebSocket handler.
   --  @return No return value.
   procedure WebSocket (Path : String; Handler : WebSocket_Handler);

   --  Attach a guard to a WebSocket route. Global guards and these guards run
   --  before the upgrade handshake; a halting guard rejects the upgrade with
   --  its response instead of opening the channel. Register the route with
   --  WebSocket first, then guard it here.
   --  @param Path Exact WebSocket route path.
   --  @param Guard Guard to install; must not be null.
   --  @return No return value.
   procedure Guard_WebSocket (Path : String; Guard : Web.Guard.Guard_Access);

   --  Register a custom error response handler.
   --  @param Status HTTP status code in the range 100 .. 599.
   --  @param Handler Error response handler.
   --  @return No return value.
   procedure Register_Error_Handler
     (Status  : Positive;
      Handler : Error_Handler);

   --  Remove a custom error response handler and restore default behavior.
   --  @param Status HTTP status code in the range 100 .. 599.
   --  @return No return value.
   procedure Clear_Error_Handler (Status : Positive);

   --  Register a static file mount.
   --  @param Url_Prefix URL path prefix.
   --  @param Directory Filesystem directory.
   --  @return No return value.
   procedure Static (Url_Prefix : String; Directory : String);

   --  Parse a minimal HTTP/1.1 request from text.
   --  @param Data HTTP request bytes.
   --  @param Allow_Missing_Body When True, a Content-Length header need not match
   --    the body present in Data (used to parse just the head before the body is
   --    streamed). Defaults to False -- the full-message check.
   --  @return Parsed request.
   function Parse_Request
     (Data : String; Allow_Missing_Body : Boolean := False)
      return Web.Request.Request_Type;

   --  Dispatch a parsed request without socket upgrade handling.
   --  @param Request Parsed request.
   --  @return HTTP response.
   function Dispatch (Request : Web.Request.Request_Type) return Web.Response.Response_Type;

   --  Apply server runtime configuration.
   --  @param Config Framework configuration.
   --  @return No return value.
   procedure Configure (Config : Web.Config.Config_Type);

   --  Return a stable health-check response for embedding applications.
   --  @return Plain text 200 response.
   function Health_Response return Web.Response.Response_Type;

   --  Return a short validated runtime configuration summary.
   --  @return Human-readable configuration report.
   function Configuration_Report return String;

   --  Run the GNAT.Sockets HTTP server.
   --  @param Host Bind host.
   --  @param Port Bind port.
   --  @return No return value.
   procedure Run (Host : String; Port : Natural);

   --  Run the GNAT.Sockets HTTPS/WSS server with TLS.
   --  @param Host Bind host.
   --  @param Port Bind port.
   --  @param Certificate_File PEM certificate file path.
   --  @param Private_Key_File PEM private-key file path.
   --  @return No return value.
   procedure Run_TLS
     (Host             : String;
      Port             : Natural;
      Certificate_File : String;
      Private_Key_File : String);

   --  Run the GNAT.Sockets HTTPS/WSS server with a TLS policy.
   --  @param Host Bind host.
   --  @param Port Bind port.
   --  @param TLS_Config TLS server configuration.
   --  @return No return value.
   procedure Run_TLS
     (Host       : String;
      Port       : Natural;
      TLS_Config : Web.TLS.Server_Config);

   --  Run the GNAT.Sockets HTTPS/WSS server with TLS settings from config.
   --  @param Host Bind host.
   --  @param Port Bind port.
   --  @param Config Framework configuration containing TLS policy.
   --  @return No return value.
   procedure Run_TLS
     (Host   : String;
      Port   : Natural;
      Config : Web.Config.Config_Type);

   --  Reload TLS certificate, key, CA, and policy for future handshakes.
   --  @param TLS_Config Replacement TLS server configuration.
   --  @return No return value.
   procedure Reload_TLS (TLS_Config : Web.TLS.Server_Config);

   --  Stop a running GNAT.Sockets HTTP server.
   --  @return No return value.
   procedure Stop;

   --  Check whether the server listener is currently running.
   --  @return True when a listener is active and stop has not been requested.
   function Running return Boolean;
end Web.Server;
