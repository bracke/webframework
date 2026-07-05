with GNAT.Sockets;
with Web.Config;
with Web.Connection;
with Web.Request;
with Web.Response;
with Web.TLS;

package Web.Server is
   type Route_Handler is access function
     (Request : Web.Request.Request_Type) return Web.Response.Response_Type;

   type WebSocket_Handler is access procedure
     (Conn    : in out Web.Connection.Connection_Type;
      Request : Web.Request.Request_Type);

   --  Register a GET route.
   --  @param Path Exact route path.
   --  @param Handler Route handler.
   --  @return No return value.
   procedure Get (Path : String; Handler : Route_Handler);

   --  Register a WebSocket route.
   --  @param Path Exact route path.
   --  @param Handler WebSocket handler.
   --  @return No return value.
   procedure WebSocket (Path : String; Handler : WebSocket_Handler);

   --  Register a static file mount.
   --  @param Url_Prefix URL prefix.
   --  @param Directory Filesystem directory.
   --  @return No return value.
   procedure Static (Url_Prefix : String; Directory : String);

   --  Parse a minimal HTTP/1.1 request from text.
   --  @param Data HTTP request bytes.
   --  @return Parsed request.
   function Parse_Request (Data : String) return Web.Request.Request_Type;

   --  Dispatch a parsed request without socket upgrade handling.
   --  @param Request Parsed request.
   --  @return HTTP response.
   function Dispatch (Request : Web.Request.Request_Type) return Web.Response.Response_Type;

   --  Apply server runtime configuration.
   --  @param Config Framework configuration.
   --  @return No return value.
   procedure Configure (Config : Web.Config.Config_Type);

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
end Web.Server;
