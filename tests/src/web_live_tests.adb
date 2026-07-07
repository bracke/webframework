with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with AUnit.Assertions;
with AUnit.Test_Caller;
with GNAT.Sockets;
with Web.Config;
with Web.Connection;
with Web.Errors;
with Interfaces;
with Web.Events;
with Web.Live;
with Web.Patch;
with Web.Request;
with Web.Response;
with Web.Security;

package body Web_Live_Tests is
   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_8;

   type Test_State is record
      Count : Natural := 0;
   end record;

   function Initial_State return Test_State;

   function Dispatch
     (State : in out Test_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List;

   package Test_Live is new Web.Live
     (App_State     => Test_State,
      Initial_State => Initial_State,
      Dispatch      => Dispatch);

   Event_Loop_Session     : constant String := "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
   Replacement_Session    : constant String := "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB";
   Cleanup_Socket_Session : constant String := "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC";

   task type Server_Task is
      entry Start (Socket : GNAT.Sockets.Socket_Type; Session_Id : String);
   end Server_Task;

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("live websocket event loop", Test_Run_Connection'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("live websocket replacement", Test_Socket_Replacement'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("live session cleanup", Test_Session_Cleanup'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("live secure cookie settings", Test_Secure_Cookie_Settings'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("live resource counters", Test_Resource_Counters'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("live websocket message limit", Test_WebSocket_Message_Limit'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("live invalid session cookie", Test_Invalid_Session_Cookie'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("live background cleanup", Test_Background_Cleanup'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("live cleanup closes socket", Test_Cleanup_Closes_Socket'Access));
   end Add_Tests;

   function Initial_State return Test_State is
   begin
      return (Count => 0);
   end Initial_State;

   function Dispatch
     (State : in out Test_State;
      Event : Web.Events.Event) return Web.Patch.Patch_List
   is
      pragma Unreferenced (Event);
      Text : constant String :=
        Ada.Strings.Fixed.Trim (Natural'Image (State.Count + 1), Ada.Strings.Both);
   begin
      State.Count := State.Count + 1;
      return Web.Patch.Single (Web.Patch.Set_Text ("counter-value", Text));
   end Dispatch;

   task body Server_Task is
      use Ada.Strings.Unbounded;

      Connection : GNAT.Sockets.Socket_Type;
      Id         : Unbounded_String;
   begin
      accept Start (Socket : GNAT.Sockets.Socket_Type; Session_Id : String) do
         Connection := Socket;
         Id := To_Unbounded_String (Session_Id);
      end Start;

      Test_Live.Run_Connection (Connection, To_String (Id));
   end Server_Task;

   procedure Send_Raw (Socket : GNAT.Sockets.Socket_Type; Data : String) is
      Buffer : Ada.Streams.Stream_Element_Array (1 .. Data'Length);
      First  : Ada.Streams.Stream_Element_Offset := Buffer'First;
      Last   : Ada.Streams.Stream_Element_Offset;
   begin
      for Index_Value in Data'Range loop
         Buffer (Ada.Streams.Stream_Element_Offset (Index_Value - Data'First + 1)) :=
           Ada.Streams.Stream_Element (Character'Pos (Data (Index_Value)));
      end loop;

      while First <= Buffer'Last loop
         GNAT.Sockets.Send_Socket (Socket, Buffer (First .. Buffer'Last), Last);
         exit when Last < First;
         First := Last + 1;
      end loop;
   end Send_Raw;

   function Read_Exact (Socket : GNAT.Sockets.Socket_Type; Count : Natural) return String is
      Buffer : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Count));
      Last   : Ada.Streams.Stream_Element_Offset;
      Cursor : Ada.Streams.Stream_Element_Offset := Buffer'First;
      Result : String (1 .. Count);
   begin
      while Cursor <= Buffer'Last loop
         GNAT.Sockets.Receive_Socket (Socket, Buffer (Cursor .. Buffer'Last), Last);
         exit when Last < Cursor;
         Cursor := Last + 1;
      end loop;

      for Index_Value in Result'Range loop
         Result (Index_Value) :=
           Character'Val
             (Buffer (Buffer'First + Ada.Streams.Stream_Element_Offset (Index_Value - Result'First)));
      end loop;
      return Result;
   end Read_Exact;

   function Masked_Frame (Opcode : Natural; Payload : String) return String is
      Mask   : constant String :=
        Character'Val (16#01#)
        & Character'Val (16#02#)
        & Character'Val (16#03#)
        & Character'Val (16#04#);
      Result : String (1 .. 2 + 4 + Payload'Length);
      Cursor : Natural := Result'First;
   begin
      Result (Cursor) := Character'Val (16#80# + Opcode);
      Cursor := Cursor + 1;
      Result (Cursor) := Character'Val (16#80# + Payload'Length);
      Cursor := Cursor + 1;

      for Ch of Mask loop
         Result (Cursor) := Ch;
         Cursor := Cursor + 1;
      end loop;

      for Offset in 0 .. Payload'Length - 1 loop
         Result (Cursor) :=
           Character'Val
             (Natural
                (Interfaces.Unsigned_8 (Character'Pos (Payload (Payload'First + Offset)))
                 xor Interfaces.Unsigned_8 (Character'Pos (Mask (Offset mod 4 + 1)))));
         Cursor := Cursor + 1;
      end loop;

      return Result;
   end Masked_Frame;

   function Receive_Server_Frame (Socket : GNAT.Sockets.Socket_Type) return String is
      Header : constant String := Read_Exact (Socket, 2);
      Length : constant Natural := Character'Pos (Header (Header'First + 1)) mod 16#80#;
   begin
      return Header & Read_Exact (Socket, Length);
   end Receive_Server_Frame;

   function Is_Closed (Socket : GNAT.Sockets.Socket_Type) return Boolean is
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 1);
      Last   : Ada.Streams.Stream_Element_Offset;
   begin
      GNAT.Sockets.Receive_Socket (Socket, Buffer, Last);
      return Last < Buffer'First;
   exception
      when GNAT.Sockets.Socket_Error =>
         return True;
   end Is_Closed;

   procedure Test_Run_Connection (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Server : GNAT.Sockets.Socket_Type;
      Client : GNAT.Sockets.Socket_Type;
      Worker : Server_Task;
      Pong   : String (1 .. 3);
   begin
      GNAT.Sockets.Initialize;
      GNAT.Sockets.Create_Socket_Pair (Server, Client);
      Worker.Start (Server, Event_Loop_Session);

      Send_Raw (Client, Masked_Frame (9, "x"));
      Pong := Receive_Server_Frame (Client);
      Assert (Character'Pos (Pong (Pong'First)) = 16#8A#, "pong opcode");
      Assert (Pong (Pong'Last) = 'x', "pong payload");

      Send_Raw
        (Client,
         Masked_Frame
           (1,
            "{""type"":""click"",""version"":1,""id"":""counter-inc"","
            & """action"":""counter.increment""}"));
      declare
         Response : constant String := Receive_Server_Frame (Client);
      begin
         Assert (Character'Pos (Response (Response'First)) = 16#81#, "text response opcode");
         Assert
           (Ada.Strings.Fixed.Index (Response, """op"":""set_text""") > 0,
            "patch operation encoded");
         Assert
           (Ada.Strings.Fixed.Index (Response, """target"":""counter-value""") > 0,
            "patch target encoded");
         Assert
           (Ada.Strings.Fixed.Index (Response, """value"":""1""") > 0,
            "state patch encoded");
      end;

      Send_Raw (Client, Masked_Frame (8, ""));
      declare
         Close_Frame : constant String := Receive_Server_Frame (Client);
      begin
         Assert (Character'Pos (Close_Frame (Close_Frame'First)) = 16#88#, "close response");
      end;

      GNAT.Sockets.Close_Socket (Client);
   end Test_Run_Connection;

   procedure Test_Socket_Replacement (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Server_One : GNAT.Sockets.Socket_Type;
      Client_One : GNAT.Sockets.Socket_Type;
      Server_Two : GNAT.Sockets.Socket_Type;
      Client_Two : GNAT.Sockets.Socket_Type;
      Worker_One : Server_Task;
      Worker_Two : Server_Task;
   begin
      GNAT.Sockets.Initialize;
      GNAT.Sockets.Create_Socket_Pair (Server_One, Client_One);
      Worker_One.Start (Server_One, Replacement_Session);

      GNAT.Sockets.Create_Socket_Pair (Server_Two, Client_Two);
      Worker_Two.Start (Server_Two, Replacement_Session);

      Assert (Is_Closed (Client_One), "first client closed after replacement");

      Send_Raw
        (Client_Two,
         Masked_Frame
           (1,
            "{""type"":""click"",""version"":1,""id"":""counter-inc"","
            & """action"":""counter.increment""}"));
      declare
         Response : constant String := Receive_Server_Frame (Client_Two);
      begin
         Assert (Character'Pos (Response (Response'First)) = 16#81#, "second socket still active");
         Assert (Ada.Strings.Fixed.Index (Response, """value"":""1""") > 0, "second socket patch");
      end;

      Send_Raw (Client_Two, Masked_Frame (8, ""));
      declare
         Close_Frame : constant String := Receive_Server_Frame (Client_Two);
      begin
         Assert (Character'Pos (Close_Frame (Close_Frame'First)) = 16#88#, "second close response");
      end;

      GNAT.Sockets.Close_Socket (Client_One);
      GNAT.Sockets.Close_Socket (Client_Two);
   end Test_Socket_Replacement;

   procedure Increment_State (State : in out Test_State) is
   begin
      State.Count := State.Count + 1;
   end Increment_State;

   procedure Test_Session_Cleanup (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Initial_Request : constant Web.Request.Request_Type :=
        Web.Request.Create ("GET", "/");
      Session : constant String := Test_Live.Find_Or_Create_Session (Initial_Request);
      Cookie_Request : Web.Request.Request_Type := Web.Request.Create ("GET", "/");
      Removed : Natural;
      Raised  : Boolean := False;
   begin
      Test_Live.With_State (Session, Increment_State'Access);
      Web.Request.Set_Header (Cookie_Request, "Cookie", "wf_session=" & Session);
      Assert (Test_Live.Require_Session (Cookie_Request) = Session, "session exists before cleanup");

      begin
         Test_Live.With_State ("../../not-a-session", Increment_State'Access);
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "invalid with_state session rejected");

      Raised := False;
      begin
         Test_Live.With_State (Session, null);
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "null with_state process rejected");

      Test_Live.Set_Session_Timeout (0);
      Removed := Test_Live.Cleanup_Sessions;
      Test_Live.Set_Session_Timeout (3_600);

      Assert (Removed >= 1, "expired session removed");
      Assert (Test_Live.Require_Session (Cookie_Request) = "", "expired session cookie rejected");
   end Test_Session_Cleanup;

   procedure Test_Secure_Cookie_Settings (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Config  : Web.Config.Config_Type := Web.Config.Default_Config;
      Session : constant String := Test_Live.Find_Or_Create_Session (Web.Request.Create ("GET", "/"));
      Response : Web.Response.Response_Type;
   begin
      Test_Live.Set_Secure_Cookies (False);
      Assert
        (Ada.Strings.Fixed.Index (Test_Live.Session_Cookie_Header (Session), "; Secure") = 0,
         "secure cookie disabled by default setting");

      Test_Live.Set_Secure_Cookies (True);
      Assert (Test_Live.Secure_Cookies, "secure cookie setting enabled");
      Assert
        (Ada.Strings.Fixed.Index (Test_Live.Session_Cookie_Header (Session), "; Secure") > 0,
         "secure cookie attribute emitted");
      Response := Test_Live.Html_Response (Web.Request.Create ("GET", "/"), "<p>ok</p>");
      Assert
        (Ada.Strings.Fixed.Index (Web.Response.Header (Response, "Set-Cookie"), "wf_session=") = 1,
         "request html response helper sets session cookie");

      Config.Secure_Cookies := False;
      Config.Session_Timeout := 3_600;
      Test_Live.Configure (Config);
      Assert (not Test_Live.Secure_Cookies, "secure cookie setting follows config");
   end Test_Secure_Cookie_Settings;

   procedure Test_Resource_Counters (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Request : constant Web.Request.Request_Type := Web.Request.Create ("GET", "/");
      Session : String (1 .. 32);
      Server  : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
      Client  : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
      Worker  : Server_Task;
   begin
      Test_Live.Set_Session_Timeout (0);
      declare
         Ignored : constant Natural := Test_Live.Cleanup_Sessions;
      begin
         null;
      end;
      Assert (Test_Live.Session_Count = 0, "initial session count");
      Assert (Test_Live.Active_WebSocket_Count = 0, "initial websocket count");

      Session := Test_Live.Find_Or_Create_Session (Request);
      Assert (Test_Live.Session_Count = 1, "session counter increments");
      Assert (Test_Live.Active_WebSocket_Count = 0, "no websocket before attach");

      GNAT.Sockets.Initialize;
      GNAT.Sockets.Create_Socket_Pair (Server, Client);
      Worker.Start (Server, Session);
      delay 0.05;

      Assert (Test_Live.Session_Count = 1, "session remains counted");
      Assert (Test_Live.Active_WebSocket_Count = 1, "websocket counter increments");

      Send_Raw (Client, Masked_Frame (8, ""));
      declare
         Close_Frame : constant String := Receive_Server_Frame (Client);
      begin
         Assert (Character'Pos (Close_Frame (Close_Frame'First)) = 16#88#, "counter close response");
      end;

      GNAT.Sockets.Close_Socket (Client);
      delay 0.05;

      Assert (Test_Live.Active_WebSocket_Count = 0, "websocket counter decrements");
      Assert (Test_Live.Cleanup_Sessions = 1, "counter session cleaned");
      Assert (Test_Live.Session_Count = 0, "session counter after cleanup");
      Test_Live.Configure (Web.Config.Default_Config);
   exception
      when others =>
         begin
            GNAT.Sockets.Close_Socket (Client);
         exception
            when others =>
               null;
         end;
         Test_Live.Configure (Web.Config.Default_Config);
         raise;
   end Test_Resource_Counters;

   procedure Test_WebSocket_Message_Limit (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Server : GNAT.Sockets.Socket_Type;
      Client : GNAT.Sockets.Socket_Type;
      Worker : Server_Task;
      Config : Web.Config.Config_Type := Web.Config.Default_Config;
   begin
      Config.Max_WebSocket_Message := 8;
      Test_Live.Configure (Config);

      GNAT.Sockets.Initialize;
      GNAT.Sockets.Create_Socket_Pair (Server, Client);
      Worker.Start (Server, "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD");

      Send_Raw
        (Client,
         Masked_Frame
           (1,
            "{""type"":""click"",""version"":1,""id"":""counter-inc"","
            & """action"":""counter.increment""}"));

      declare
         Close_Frame : constant String := Receive_Server_Frame (Client);
      begin
         Assert (Character'Pos (Close_Frame (Close_Frame'First)) = 16#88#, "oversized message closed");
      end;

      GNAT.Sockets.Close_Socket (Client);
      Test_Live.Configure (Web.Config.Default_Config);
   exception
      when others =>
         Test_Live.Configure (Web.Config.Default_Config);
         raise;
   end Test_WebSocket_Message_Limit;

   procedure Test_Invalid_Session_Cookie (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Initial_Request : constant Web.Request.Request_Type :=
        Web.Request.Create ("GET", "/");
      Session : constant String := Test_Live.Find_Or_Create_Session (Initial_Request);
      Cookie_Request : Web.Request.Request_Type := Web.Request.Create ("GET", "/");
      New_Session : String (1 .. 32);
      Conn : Web.Connection.Connection_Type;
      Raised : Boolean := False;
   begin
      Web.Request.Set_Header (Cookie_Request, "Cookie", "wf_session=" & Session);
      Assert (Test_Live.Require_Session (Cookie_Request) = Session, "valid session cookie accepted");

      Web.Request.Set_Header (Cookie_Request, "Cookie", "wf_session=../../not-a-session");
      Assert (Test_Live.Require_Session (Cookie_Request) = "", "invalid session cookie ignored");

      Web.Request.Set_Header (Cookie_Request, "Cookie", "wf_session=" & Session & "; wf_session=" & Session);
      Assert (Test_Live.Require_Session (Cookie_Request) = "", "duplicate session cookie rejected");

      New_Session := Test_Live.Find_Or_Create_Session (Cookie_Request);
      Assert (Web.Security.Is_Valid_Session_Id (New_Session), "replacement session id is valid");
      Assert (New_Session /= "../../not-a-session", "replacement does not reuse invalid cookie");

      begin
         Test_Live.Run_Connection (Conn, "../../not-a-session");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "invalid websocket session rejected before socket use");
   end Test_Invalid_Session_Cookie;

   procedure Test_Background_Cleanup (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Initial_Request : constant Web.Request.Request_Type :=
        Web.Request.Create ("GET", "/");
      Session : constant String := Test_Live.Find_Or_Create_Session (Initial_Request);
      Cookie_Request : Web.Request.Request_Type := Web.Request.Create ("GET", "/");
   begin
      Test_Live.Stop_Cleanup_Task;
      Assert (not Test_Live.Cleanup_Task_Running, "cleanup task initially stopped");

      Web.Request.Set_Header (Cookie_Request, "Cookie", "wf_session=" & Session);
      Assert (Test_Live.Require_Session (Cookie_Request) = Session, "session exists before worker");

      Test_Live.Set_Session_Timeout (0);
      Test_Live.Start_Cleanup_Task (1);
      Assert (Test_Live.Cleanup_Task_Running, "cleanup task running after start");
      Test_Live.Start_Cleanup_Task (1);
      Assert (Test_Live.Cleanup_Task_Running, "cleanup task still running after repeated start");
      delay 1.20;
      Test_Live.Stop_Cleanup_Task;
      Assert (not Test_Live.Cleanup_Task_Running, "cleanup task stopped");
      Test_Live.Stop_Cleanup_Task;
      Assert (not Test_Live.Cleanup_Task_Running, "cleanup task stop is idempotent");
      Test_Live.Set_Session_Timeout (3_600);

      Assert (Test_Live.Require_Session (Cookie_Request) = "", "background cleanup expired session");
   exception
      when others =>
         Test_Live.Stop_Cleanup_Task;
         Test_Live.Set_Session_Timeout (3_600);
         raise;
   end Test_Background_Cleanup;

   procedure Test_Cleanup_Closes_Socket (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Server : GNAT.Sockets.Socket_Type;
      Client : GNAT.Sockets.Socket_Type;
      Worker : Server_Task;
      Removed : Natural;
   begin
      GNAT.Sockets.Initialize;
      GNAT.Sockets.Create_Socket_Pair (Server, Client);
      Worker.Start (Server, Cleanup_Socket_Session);

      Send_Raw (Client, Masked_Frame (9, "z"));
      declare
         Pong : constant String := Receive_Server_Frame (Client);
      begin
         Assert (Character'Pos (Pong (Pong'First)) = 16#8A#, "cleanup test pong");
      end;

      Test_Live.Set_Session_Timeout (0);
      Removed := Test_Live.Cleanup_Sessions;
      Test_Live.Set_Session_Timeout (3_600);

      Assert (Removed >= 1, "active expired session removed");
      Assert (Is_Closed (Client), "active expired socket closed");
      GNAT.Sockets.Close_Socket (Client);
   end Test_Cleanup_Closes_Socket;
end Web_Live_Tests;
