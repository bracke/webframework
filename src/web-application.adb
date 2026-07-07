package body Web.Application is
   procedure Register (Action : String; Handler : Dispatcher.Handler_Access) is
   begin
      Dispatcher.Register (Action, Handler);
   end Register;

   function Find_Or_Create_Session (Request : Web.Request.Request_Type) return String is
   begin
      return Live.Find_Or_Create_Session (Request);
   end Find_Or_Create_Session;

   function Require_Session (Request : Web.Request.Request_Type) return String is
   begin
      return Live.Require_Session (Request);
   end Require_Session;

   function Session_Cookie_Header (Id : String) return String is
   begin
      return Live.Session_Cookie_Header (Id);
   end Session_Cookie_Header;

   function Html_Response
     (Session : String; Content : String) return Web.Response.Response_Type is
   begin
      return Live.Html_Response (Session, Content);
   end Html_Response;

   function Html_Response
     (Request : Web.Request.Request_Type;
      Content : String) return Web.Response.Response_Type is
   begin
      return Live.Html_Response (Request, Content);
   end Html_Response;

   procedure Configure (Config : Web.Config.Config_Type) is
   begin
      Live.Configure (Config);
      Web.Server.Configure (Config);
   end Configure;

   procedure Set_Secure_Cookies (Enabled : Boolean) is
   begin
      Live.Set_Secure_Cookies (Enabled);
   end Set_Secure_Cookies;

   function Secure_Cookies return Boolean is
   begin
      return Live.Secure_Cookies;
   end Secure_Cookies;

   procedure With_State (Id : String; Process : Live.State_Process) is
   begin
      Live.With_State (Id, Process);
   end With_State;

   function Session_Count return Natural is
   begin
      return Live.Session_Count;
   end Session_Count;

   function Active_WebSocket_Count return Natural is
   begin
      return Live.Active_WebSocket_Count;
   end Active_WebSocket_Count;

   function Cleanup_Sessions return Natural is
   begin
      return Live.Cleanup_Sessions;
   end Cleanup_Sessions;

   procedure Run_Connection
     (Conn : in out Web.Connection.Connection_Type; Id : String)
   is
   begin
      Live.Run_Connection (Conn, Id);
   end Run_Connection;

   procedure Run_Connection (Socket : GNAT.Sockets.Socket_Type; Id : String) is
   begin
      Live.Run_Connection (Socket, Id);
   end Run_Connection;

   procedure WebSocket_Handler
     (Conn    : in out Web.Connection.Connection_Type;
      Request : Web.Request.Request_Type)
   is
   begin
      Live.WebSocket_Handler (Conn, Request);
   end WebSocket_Handler;

   procedure Get (Path : String; Handler : Route_Handler_Access) is
   begin
      Web.Server.Get (Path, Handler);
   end Get;

   procedure WebSocket (Path : String; Handler : WebSocket_Handler_Access) is
   begin
      Web.Server.WebSocket (Path, Handler);
   end WebSocket;

   procedure Static (Url_Prefix : String; Directory : String) is
   begin
      Web.Server.Static (Url_Prefix, Directory);
   end Static;

   procedure Register_Error_Handler
     (Status  : Positive;
      Handler : Web.Server.Error_Handler) is
   begin
      Web.Server.Register_Error_Handler (Status, Handler);
   end Register_Error_Handler;

   procedure Clear_Error_Handler (Status : Positive) is
   begin
      Web.Server.Clear_Error_Handler (Status);
   end Clear_Error_Handler;

   procedure Run (Host : String; Port : Natural) is
   begin
      Web.Server.Run (Host, Port);
   end Run;

   procedure Run_TLS (Host : String; Port : Natural; Config : Web.Config.Config_Type) is
   begin
      Web.Server.Run_TLS (Host, Port, Config);
   end Run_TLS;

   function Configuration_Report return String is
   begin
      return Web.Server.Configuration_Report;
   end Configuration_Report;

   function Server_Running return Boolean is
   begin
      return Web.Server.Running;
   end Server_Running;

   procedure Stop is
   begin
      Web.Server.Stop;
   end Stop;

   function Health_Response return Web.Response.Response_Type is
   begin
      return Web.Server.Health_Response;
   end Health_Response;
end Web.Application;
