package body Web.Application is
   procedure Register (Action : String; Handler : Dispatcher.Handler_Access) is
   begin
      Dispatcher.Register (Action, Handler);
   end Register;

   procedure Register
     (Action  : String;
      Handler : Dispatcher.Handler_Access;
      Guard   : Dispatcher.Action_Guard) is
   begin
      Dispatcher.Register (Action, Handler, Guard);
   end Register;

   function Find_Or_Create_Session (Request : Web.Request.Request_Type) return String is
   begin
      return Live.Find_Or_Create_Session (Request);
   end Find_Or_Create_Session;

   function Require_Session (Request : Web.Request.Request_Type) return String is
   begin
      return Live.Require_Session (Request);
   end Require_Session;

   procedure Invalidate_Session (Id : String) is
   begin
      Live.Invalidate_Session (Id);
   end Invalidate_Session;

   function Regenerate_Session (Old_Id : String) return String is
   begin
      return Live.Regenerate_Session (Old_Id);
   end Regenerate_Session;

   function Session_Cookie_Header (Id : String) return String is
   begin
      return Live.Session_Cookie_Header (Id);
   end Session_Cookie_Header;

   function Html_Response
     (Session : String; Content : String) return Web.Response.Response_Type is
   begin
      return Live.Html_Response (Session, Content);
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

   procedure With_State
     (Id : String; Visitor : in out Live.State_Visitor'Class) is
   begin
      Live.With_State (Id, Visitor);
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

   procedure Post (Path : String; Handler : Route_Handler_Access) is
   begin
      Web.Server.Post (Path, Handler);
   end Post;

   procedure Put (Path : String; Handler : Route_Handler_Access) is
   begin
      Web.Server.Put (Path, Handler);
   end Put;

   procedure Patch (Path : String; Handler : Route_Handler_Access) is
   begin
      Web.Server.Patch (Path, Handler);
   end Patch;

   procedure Delete (Path : String; Handler : Route_Handler_Access) is
   begin
      Web.Server.Delete (Path, Handler);
   end Delete;

   procedure Post_Stream
     (Path    : String;
      Handler : Stream_Handler_Access;
      Guard   : Web.Guard.Guard_Access := null) is
   begin
      Web.Server.Post_Stream (Path, Handler, Guard);
   end Post_Stream;

   procedure Use_Guard (Guard : Web.Guard.Guard_Access) is
   begin
      Web.Server.Use_Guard (Guard);
   end Use_Guard;

   procedure Get
     (Path    : String;
      Handler : Web.Guard.Contextual_Handler;
      Guard   : Web.Guard.Guard_Access := null) is
   begin
      Web.Server.Get (Path, Handler, Guard);
   end Get;

   procedure Post
     (Path    : String;
      Handler : Web.Guard.Contextual_Handler;
      Guard   : Web.Guard.Guard_Access := null) is
   begin
      Web.Server.Post (Path, Handler, Guard);
   end Post;

   procedure Put
     (Path    : String;
      Handler : Web.Guard.Contextual_Handler;
      Guard   : Web.Guard.Guard_Access := null) is
   begin
      Web.Server.Put (Path, Handler, Guard);
   end Put;

   procedure Patch
     (Path    : String;
      Handler : Web.Guard.Contextual_Handler;
      Guard   : Web.Guard.Guard_Access := null) is
   begin
      Web.Server.Patch (Path, Handler, Guard);
   end Patch;

   procedure Delete
     (Path    : String;
      Handler : Web.Guard.Contextual_Handler;
      Guard   : Web.Guard.Guard_Access := null) is
   begin
      Web.Server.Delete (Path, Handler, Guard);
   end Delete;

   procedure WebSocket (Path : String; Handler : WebSocket_Handler_Access) is
   begin
      Web.Server.WebSocket (Path, Handler);
   end WebSocket;

   procedure Guard_WebSocket (Path : String; Guard : Web.Guard.Guard_Access) is
   begin
      Web.Server.Guard_WebSocket (Path, Guard);
   end Guard_WebSocket;

   procedure Server_Sent_Events (Path : String; Handler : SSE_Handler_Access) is
   begin
      Web.Server.Server_Sent_Events (Path, Handler);
   end Server_Sent_Events;

   procedure Guard_Server_Sent_Events
     (Path : String; Guard : Web.Guard.Guard_Access) is
   begin
      Web.Server.Guard_Server_Sent_Events (Path, Guard);
   end Guard_Server_Sent_Events;

   procedure Static (Url_Prefix : String; Directory : String) is
   begin
      Web.Server.Static (Url_Prefix, Directory);
   end Static;

   procedure Static_Versioned (Url_Prefix : String; Directory : String) is
   begin
      --  For versioned static files, we use the standard static handler
      --  since the versioning is handled by the Web.Assets package
      --  when generating URLs and by the modified Web.Static.Serve
      --  which now includes cache headers
      Web.Server.Static (Url_Prefix, Directory);
   end Static_Versioned;

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

   --  Connection hardening functions
   procedure Set_Ping_Interval (Seconds : Natural) is
   begin
      Live.Set_Ping_Interval (Seconds);
   end Set_Ping_Interval;

   function Ping_Interval return Natural is
   begin
      return Live.Ping_Interval;
   end Ping_Interval;

   procedure Set_Rate_Limit (Count : Natural) is
   begin
      Live.Set_Rate_Limit (Count);
   end Set_Rate_Limit;

   function Rate_Limit return Natural is
   begin
      return Live.Rate_Limit;
   end Rate_Limit;

   procedure Set_Deduplication_Window (Seconds : Natural) is
   begin
      Live.Set_Deduplication_Window (Seconds);
   end Set_Deduplication_Window;

   function Deduplication_Window return Natural is
   begin
      return Live.Deduplication_Window;
   end Deduplication_Window;

   function Is_Connected (Id : String) return Boolean is
   begin
      return Live.Is_Connected (Id);
   end Is_Connected;

   function Connection_Stats (Id : String) return String is
   begin
      return Live.Connection_Stats (Id);
   end Connection_Stats;
end Web.Application;
