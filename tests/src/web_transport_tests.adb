with Ada.Directories;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with AUnit.Assertions;
with AUnit.Test_Caller;
with Web.Config;
with Web.Connection;
with Web.Errors;
with Web.Request;
with Web.Response;
with Web.Server;
with Web.Security;
with Web.Static;
with Web.TLS;
with Web.WebSocket;

package body Web_Transport_Tests is
   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;
   use type Web.WebSocket.Opcode;

   function Raising_Handler
     (Request : Web.Request.Request_Type) return Web.Response.Response_Type
   is
      pragma Unreferenced (Request);
   begin
      raise Constraint_Error with "secret production detail";
      return Web.Response.Text ("unreachable");
   end Raising_Handler;

   procedure Noop_WebSocket
     (Conn    : in out Web.Connection.Connection_Type;
      Request : Web.Request.Request_Type)
   is
      pragma Unreferenced (Conn, Request);
   begin
      null;
   end Noop_WebSocket;

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("static content types", Test_Static_Content_Types'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("static binary serving", Test_Static_Binary_Serving'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("static read failures", Test_Static_Read_Failures'Access));
      AUnit.Test_Suites.Add_Test (Suite, Caller.Create ("http parse", Test_HTTP_Parse'Access));
      AUnit.Test_Suites.Add_Test (Suite, Caller.Create ("http body parse", Test_HTTP_Body_Parse'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("http hostile inputs", Test_HTTP_Hostile_Inputs'Access));
      AUnit.Test_Suites.Add_Test (Suite, Caller.Create ("http rejection policy", Test_HTTP_Rejections'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("invalid registration", Test_Invalid_Registrations'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("server config", Test_Server_Config'Access));
      AUnit.Test_Suites.Add_Test (Suite, Caller.Create ("http method rejection", Test_Method_Rejection'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("http pipelining rejection", Test_Pipelining_Rejection'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("websocket accept", Test_WebSocket_Accept'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("websocket upgrade detection", Test_WebSocket_Upgrade_Detection'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("websocket frame", Test_WebSocket_Frame'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("websocket hostile frames", Test_WebSocket_Hostile_Frames'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("tls policy validation", Test_TLS_Policy_Validation'Access));
   end Add_Tests;

   procedure Test_Static_Content_Types (Item : in out Fixture) is
      pragma Unreferenced (Item);
   begin
      Assert (Web.Static.Content_Type ("index.html") = "text/html; charset=utf-8", "html");
      Assert (Web.Static.Content_Type ("app.css") = "text/css; charset=utf-8", "css");
      Assert (Web.Static.Content_Type ("app.js") = "application/javascript; charset=utf-8", "js");
      Assert (Web.Static.Content_Type ("logo.png") = "image/png", "png");
      Assert (Web.Static.Content_Type ("font.woff2") = "font/woff2", "woff2");
   end Test_Static_Content_Types;

   procedure Write_Binary_File (Path : String) is
      File   : Ada.Streams.Stream_IO.File_Type;
      Buffer : constant Ada.Streams.Stream_Element_Array :=
        (1 => 16#00#,
         2 => 16#50#,
         3 => 16#4E#,
         4 => 16#47#,
         5 => 16#80#,
         6 => 16#FF#);
   begin
      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Path);
      Ada.Streams.Stream_IO.Write (File, Buffer);
      Ada.Streams.Stream_IO.Close (File);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         raise;
   end Write_Binary_File;

   procedure Test_Static_Binary_Serving (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Directory : constant String := "/tmp/webframework-static-test";
      Path      : constant String := Directory & "/image.png";
   begin
      if not Ada.Directories.Exists (Directory) then
         Ada.Directories.Create_Directory (Directory);
      end if;

      Write_Binary_File (Path);

      declare
         Response : constant Web.Response.Response_Type :=
           Web.Static.Serve ("/static", Directory, "/static/image.png");
         Payload  : constant String := Web.Response.Content_Body (Response);
      begin
         Assert (Web.Response.Status (Response) = 200, "binary response status");
         Assert (Payload'Length = 6, "binary length");
         Assert (Character'Pos (Payload (Payload'First)) = 16#00#, "nul byte preserved");
         Assert (Character'Pos (Payload (Payload'First + 4)) = 16#80#, "high byte preserved");
         Assert (Character'Pos (Payload (Payload'First + 5)) = 16#FF#, "ff byte preserved");
         Assert
           (Web.Response.Serialize (Response)'Length > Payload'Length,
            "binary response serializes");
      end;

      Ada.Directories.Delete_File (Path);
   end Test_Static_Binary_Serving;

   procedure Test_Static_Read_Failures (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Directory : constant String := "/tmp/webframework-static-failure";
      Nested    : constant String := Directory & "/nested";
      Response  : Web.Response.Response_Type;
   begin
      if not Ada.Directories.Exists (Directory) then
         Ada.Directories.Create_Directory (Directory);
      end if;

      if not Ada.Directories.Exists (Nested) then
         Ada.Directories.Create_Directory (Nested);
      end if;

      Response := Web.Static.Serve ("/static", Directory, "/static/../secret.txt");
      Assert (Web.Response.Status (Response) = 400, "static traversal rejected");

      Response := Web.Static.Serve ("/static", Directory, "/staticx/nested");
      Assert (Web.Response.Status (Response) = 404, "static prefix boundary enforced");

      Response := Web.Static.Serve ("/static", Directory, "/static");
      Assert (Web.Response.Status (Response) = 400, "static prefix without file rejected");

      Response := Web.Static.Serve ("/static", Directory, "/static/nested");
      Assert (Web.Response.Status (Response) = 404, "static directories are not served");
   end Test_Static_Read_Failures;

   procedure Test_HTTP_Parse (Item : in out Fixture) is
      pragma Unreferenced (Item);
      CRLF    : constant String := Character'Val (13) & Character'Val (10);
      Request : constant Web.Request.Request_Type :=
        Web.Server.Parse_Request
          ("GET /?a=1 HTTP/1.1" & CRLF
           & "Host: localhost" & CRLF
           & "Connection: close" & CRLF
           & CRLF);
   begin
      Assert (Web.Request.Method (Request) = "GET", "method");
      Assert (Web.Request.Path (Request) = "/", "path");
      Assert (Web.Request.Query_String (Request) = "a=1", "query");
      Assert (Web.Request.Header (Request, "host") = "localhost", "header");
   end Test_HTTP_Parse;

   procedure Test_HTTP_Body_Parse (Item : in out Fixture) is
      pragma Unreferenced (Item);
      CRLF    : constant String := Character'Val (13) & Character'Val (10);
      Request : constant Web.Request.Request_Type :=
        Web.Server.Parse_Request
          ("GET /submit HTTP/1.1" & CRLF
           & "Host: localhost" & CRLF
           & "Content-Length: 7" & CRLF
           & CRLF
           & "a=b&c=d");
   begin
      Assert (Web.Request.Path (Request) = "/submit", "path");
      Assert (Web.Request.Request_Body (Request) = "a=b&c=d", "body");
   end Test_HTTP_Body_Parse;

   function Oversized_Request return String is
      use Ada.Strings.Unbounded;

      Result : Unbounded_String;
   begin
      Append (Result, "GET / HTTP/1.1");
      while Length (Result) <= Web.Security.Max_Request_Size loop
         Append (Result, "x");
      end loop;
      return To_String (Result);
   end Oversized_Request;

   procedure Expect_Bad_Request (Raw : String; Name : String) is
      Raised : Boolean := False;
   begin
      begin
         declare
            Request : constant Web.Request.Request_Type := Web.Server.Parse_Request (Raw);
         begin
            Assert (Web.Request.Path (Request)'Length = 0, Name & " unexpectedly parsed");
         end;
      exception
         when Web.Errors.Bad_Request_Error =>
            Raised := True;
      end;
      Assert (Raised, Name);
   end Expect_Bad_Request;

   procedure Expect_Parses (Raw : String; Name : String) is
      Request : constant Web.Request.Request_Type := Web.Server.Parse_Request (Raw);
   begin
      Assert (Web.Request.Path (Request)'Length > 0, Name);
   end Expect_Parses;

   procedure Test_HTTP_Hostile_Inputs (Item : in out Fixture) is
      pragma Unreferenced (Item);
      CRLF : constant String := Character'Val (13) & Character'Val (10);
   begin
      Expect_Bad_Request
        ("GET / HTTP/1.1" & CRLF
         & "Host: one.test" & CRLF
         & "host: two.test" & CRLF
         & CRLF,
         "duplicate headers rejected");
      Expect_Bad_Request
        ("GET / HTTP/1.1" & CRLF
         & "Host localhost" & CRLF
         & CRLF,
         "malformed header rejected");
      Expect_Bad_Request
        ("GET / HTTP/1.1" & CRLF
         & "Host : localhost" & CRLF
         & CRLF,
         "header whitespace before colon rejected");
      Expect_Bad_Request
        ("GET / HTTP/1.1" & CRLF
         & ": value" & CRLF
         & CRLF,
         "empty header name rejected");
      Expect_Bad_Request
        ("GET / HTTP/1.1" & CRLF
         & "Host: local" & Character'Val (1) & "host" & CRLF
         & CRLF,
         "control character in header value rejected");
      Expect_Bad_Request
        ("GET / HTTP/1.1" & CRLF
         & "Host: local" & Character'Val (127) & "host" & CRLF
         & CRLF,
         "delete byte in header value rejected");
      Expect_Bad_Request
        ("GET / HTTP/1.1" & CRLF
         & CRLF,
         "missing host rejected");
      Expect_Bad_Request
        ("GET http://example.test/ HTTP/1.1" & CRLF
         & "Host: example.test" & CRLF
         & CRLF,
         "absolute request target rejected");
      Expect_Bad_Request
        ("GET /bad/../target HTTP/1.1" & CRLF
         & "Host: localhost" & CRLF
         & CRLF,
         "unsafe request target rejected");
      Expect_Bad_Request
        ("GET /?q=bad" & Character'Val (1) & "query HTTP/1.1" & CRLF
         & "Host: localhost" & CRLF
         & CRLF,
         "control character in query rejected");
      Expect_Bad_Request (Oversized_Request, "oversized parsed request rejected");
   end Test_HTTP_Hostile_Inputs;

   procedure Test_HTTP_Rejections (Item : in out Fixture) is
      pragma Unreferenced (Item);
      CRLF : constant String := Character'Val (13) & Character'Val (10);
   begin
      Expect_Bad_Request
        ("PRI * HTTP/2.0" & CRLF & CRLF & "SM" & CRLF & CRLF,
         "http2 preface rejected");
      Expect_Bad_Request
        ("GET / HTTP/1.0" & CRLF & "Host: localhost" & CRLF & CRLF,
         "http10 rejected");
      Expect_Bad_Request
        ("GET / HTTP/1.1x" & CRLF & "Host: localhost" & CRLF & CRLF,
         "http version suffix rejected");
      Expect_Bad_Request
        ("GET / HTTP/1.1 extra" & CRLF & "Host: localhost" & CRLF & CRLF,
         "http request line extra token rejected");
      Expect_Bad_Request
        ("GET / HTTP/1.1" & CRLF & "Transfer-Encoding: chunked" & CRLF & CRLF,
         "chunked rejected");
      Expect_Bad_Request
        ("GET / HTTP/1.1" & CRLF & "Content-Encoding: gzip" & CRLF & CRLF,
         "content encoding rejected");
      Expect_Bad_Request
        ("GET / HTTP/1.1" & CRLF & "Content-Type: multipart/form-data" & CRLF & CRLF,
         "multipart rejected");
      Expect_Bad_Request
        ("GET / HTTP/1.1" & CRLF & "Content-Length: nope" & CRLF & CRLF,
         "bad content length rejected");
      Expect_Bad_Request
        ("GET / HTTP/1.1" & CRLF & "Content-Length: +7" & CRLF & CRLF,
         "signed content length rejected");
      Expect_Bad_Request
        ("GET / HTTP/1.1" & CRLF
         & "Host: localhost" & CRLF
         & "Content-Length : 7" & CRLF
         & CRLF
         & "a=b&c=d",
         "content length whitespace before colon rejected");
      Expect_Parses
        ("GET / HTTP/1.1" & CRLF
         & "Host: localhost" & CRLF
         & "Accept-Encoding: gzip, deflate, br" & CRLF
         & CRLF,
         "response compression encodings accepted");
      Expect_Parses
        ("GET / HTTP/1.1" & CRLF
         & "Host: localhost" & CRLF
         & "Accept-Encoding: xgzipx" & CRLF
         & CRLF,
         "encoding token substrings ignored");
      Expect_Parses
        ("GET / HTTP/1.1" & CRLF
         & "Host: localhost" & CRLF
         & "Transfer-Encoding: notchunked" & CRLF
         & CRLF,
         "transfer token substrings ignored");
   end Test_HTTP_Rejections;

   procedure Test_Invalid_Registrations (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Raised : Boolean;
   begin
      Raised := False;
      begin
         Web.Server.Get ("relative", null);
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "relative route rejected");

      Raised := False;
      begin
         Web.Server.Get ("/bad/../route", null);
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "route traversal rejected");

      Web.Server.Get ("/duplicate-route-test", Raising_Handler'Access);
      Raised := False;
      begin
         Web.Server.Get ("/duplicate-route-test", Raising_Handler'Access);
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "duplicate route rejected");

      Raised := False;
      begin
         Web.Server.WebSocket ("/ws?x=1", null);
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "websocket path with query rejected");

      Web.Server.WebSocket ("/duplicate-ws-test", Noop_WebSocket'Access);
      Raised := False;
      begin
         Web.Server.WebSocket ("/duplicate-ws-test", Noop_WebSocket'Access);
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "duplicate websocket route rejected");

      Raised := False;
      begin
         Web.Server.Static ("static", "public");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "relative static prefix rejected");

      Raised := False;
      begin
         Web.Server.Static ("/static", "../secret");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "unsafe static directory rejected");
   end Test_Invalid_Registrations;

   procedure Test_Server_Config (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Config : Web.Config.Config_Type := Web.Config.Default_Config;
      Raised : Boolean := False;
   begin
      Web.Server.Get ("/prod-boom", Raising_Handler'Access);
      Config.Mode := Web.Config.Production;
      Web.Server.Configure (Config);

      declare
         Response : constant Web.Response.Response_Type :=
           Web.Server.Dispatch (Web.Request.Create ("GET", "/prod-boom"));
      begin
         Assert (Web.Response.Status (Response) = 500, "production handler failure status");
         Assert
           (Ada.Strings.Fixed.Index (Web.Response.Content_Body (Response), "secret") = 0,
            "production response hides exception detail");
      end;

      Config := Web.Config.Default_Config;
      Config.Max_Request_Size := 0;
      begin
         Web.Server.Configure (Config);
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "zero request limit rejected");

      Config := Web.Config.Default_Config;
      Config.Enable_Compression := False;
      Config.Compression_Min_Size := 8_192;
      Web.Server.Configure (Config);
      Assert (not Config.Enable_Compression, "compression can be disabled in config");
      Assert (Config.Compression_Min_Size = 8_192, "compression threshold can be configured");

      Web.Server.Configure (Web.Config.Default_Config);
   exception
      when others =>
         Web.Server.Configure (Web.Config.Default_Config);
         raise;
   end Test_Server_Config;

   procedure Test_Method_Rejection (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Request : constant Web.Request.Request_Type := Web.Request.Create ("POST", "/");
   begin
      Assert (Web.Response.Status (Web.Server.Dispatch (Request)) = 400, "post rejected");
   end Test_Method_Rejection;

   procedure Test_Pipelining_Rejection (Item : in out Fixture) is
      pragma Unreferenced (Item);
      CRLF : constant String := Character'Val (13) & Character'Val (10);
   begin
      Expect_Bad_Request
        (
         "GET /one HTTP/1.1" & CRLF & "Host: localhost" & CRLF & CRLF
         & "GET /two HTTP/1.1" & CRLF & "Host: localhost" & CRLF & CRLF,
         "pipelining rejected");
   end Test_Pipelining_Rejection;

   procedure Test_WebSocket_Accept (Item : in out Fixture) is
      pragma Unreferenced (Item);
   begin
      Assert
        (Web.WebSocket.Accept_Key ("dGhlIHNhbXBsZSBub25jZQ==") =
         "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=",
         "RFC6455 accept key");
   end Test_WebSocket_Accept;

   procedure Test_WebSocket_Upgrade_Detection (Item : in out Fixture) is
      pragma Unreferenced (Item);
      CRLF    : constant String := Character'Val (13) & Character'Val (10);
      Request : Web.Request.Request_Type :=
        Web.Server.Parse_Request
          ("GET /ws HTTP/1.1" & CRLF
           & "Host: localhost" & CRLF
           & "Upgrade: websocket" & CRLF
           & "Connection: Upgrade" & CRLF
           & "Sec-WebSocket-Version: 13" & CRLF
           & "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" & CRLF
           & CRLF);
   begin
      Assert (Web.WebSocket.Is_Upgrade (Request), "upgrade detected");
      Request := Web.Request.Create ("GET", "/");
      Assert (not Web.WebSocket.Is_Upgrade (Request), "normal request is not upgrade");

      Request := Web.Request.Create ("GET", "/ws");
      Web.Request.Set_Header (Request, "Upgrade", "websocket");
      Web.Request.Set_Header (Request, "Connection", "close");
      Web.Request.Set_Header (Request, "Sec-WebSocket-Version", "13");
      Web.Request.Set_Header (Request, "Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==");
      Assert (not Web.WebSocket.Is_Upgrade (Request), "connection upgrade token required");

      Request := Web.Request.Create ("GET", "/ws");
      Web.Request.Set_Header (Request, "Upgrade", "websocket");
      Web.Request.Set_Header (Request, "Connection", "Upgrade");
      Web.Request.Set_Header (Request, "Sec-WebSocket-Version", "12");
      Web.Request.Set_Header (Request, "Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==");
      Assert (not Web.WebSocket.Is_Upgrade (Request), "websocket version 13 required");

      Request := Web.Request.Create ("GET", "/ws");
      Web.Request.Set_Header (Request, "Upgrade", "websocket");
      Web.Request.Set_Header (Request, "Connection", "Upgrade");
      Web.Request.Set_Header (Request, "Sec-WebSocket-Version", "13");
      Web.Request.Set_Header (Request, "Sec-WebSocket-Key", "short");
      Assert (not Web.WebSocket.Is_Upgrade (Request), "websocket key shape required");

      Request := Web.Request.Create ("GET", "/ws");
      Web.Request.Set_Header (Request, "Upgrade", "websocket");
      Web.Request.Set_Header (Request, "Connection", "Upgrade");
      Web.Request.Set_Header (Request, "Sec-WebSocket-Version", "13");
      Web.Request.Set_Header (Request, "Sec-WebSocket-Key", "AAAAAAAAAAAAAAAAAAAAAAA=");
      Assert (not Web.WebSocket.Is_Upgrade (Request), "17-byte websocket key rejected");

      Request := Web.Request.Create ("GET", "/ws");
      Web.Request.Set_Header (Request, "Upgrade", "websocket");
      Web.Request.Set_Header (Request, "Connection", "Upgrade");
      Web.Request.Set_Header (Request, "Sec-WebSocket-Version", "13");
      Web.Request.Set_Header (Request, "Sec-WebSocket-Key", "AAAAAAAAAAAAAAAAAAAAAAAA");
      Assert (not Web.WebSocket.Is_Upgrade (Request), "18-byte websocket key rejected");

      Request := Web.Request.Create ("GET", "/ws");
      Web.Request.Set_Header (Request, "Upgrade", "notwebsocket");
      Web.Request.Set_Header (Request, "Connection", "Upgrade");
      Web.Request.Set_Header (Request, "Sec-WebSocket-Version", "13");
      Web.Request.Set_Header (Request, "Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==");
      Assert (not Web.WebSocket.Is_Upgrade (Request), "upgrade token must match exactly");

      Request := Web.Request.Create ("GET", "/ws");
      Web.Request.Set_Header (Request, "Upgrade", "websocket");
      Web.Request.Set_Header (Request, "Connection", "keep-upgrade");
      Web.Request.Set_Header (Request, "Sec-WebSocket-Version", "13");
      Web.Request.Set_Header (Request, "Sec-WebSocket-Key", "dGhlIHNhbXBsZSBub25jZQ==");
      Assert (not Web.WebSocket.Is_Upgrade (Request), "connection token must match exactly");
   end Test_WebSocket_Upgrade_Detection;

   procedure Test_WebSocket_Frame (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Frame_Data : constant String :=
        Character'Val (16#81#)
        & Character'Val (16#82#)
        & Character'Val (16#37#)
        & Character'Val (16#FA#)
        & Character'Val (16#21#)
        & Character'Val (16#3D#)
        & Character'Val (16#7F#)
        & Character'Val (16#93#);
      Frame : constant Web.WebSocket.Frame := Web.WebSocket.Decode_Frame (Frame_Data, 128);
   begin
      Assert (Frame.Frame_Type = Web.WebSocket.Text_Frame, "text frame");
      Assert (Web.WebSocket.Payload (Frame) = "Hi", "payload unmasked");
      Assert (Web.WebSocket.Encode_Text ("Hi")'Length = 4, "server frame encoded");
   end Test_WebSocket_Frame;

   procedure Expect_Protocol_Error (Data : String; Max_Size : Natural; Name : String) is
      Raised : Boolean := False;
   begin
      begin
         declare
            Frame : constant Web.WebSocket.Frame := Web.WebSocket.Decode_Frame (Data, Max_Size);
         begin
            Assert (Web.WebSocket.Payload (Frame)'Length = 0, Name & " unexpectedly decoded");
         end;
      exception
         when Web.Errors.Protocol_Error =>
            Raised := True;
      end;
      Assert (Raised, Name);
   end Expect_Protocol_Error;

   procedure Test_WebSocket_Hostile_Frames (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Mask : constant String :=
        Character'Val (16#01#)
        & Character'Val (16#02#)
        & Character'Val (16#03#)
        & Character'Val (16#04#);
   begin
      Expect_Protocol_Error
        (Character'Val (16#81#) & Character'Val (2) & "Hi",
         128,
         "unmasked client frame rejected");
      Expect_Protocol_Error
        (Character'Val (16#01#) & Character'Val (16#80#) & Mask,
         128,
         "fragmented client frame rejected");
      Expect_Protocol_Error
        (Character'Val (16#82#) & Character'Val (16#80#) & Mask,
         128,
         "binary websocket frame rejected");
      Expect_Protocol_Error
        (Character'Val (16#81#) & Character'Val (16#83#) & Mask & "abc",
         2,
         "oversized websocket message rejected");
      Expect_Protocol_Error
        (Character'Val (16#81#) & Character'Val (16#FF#),
         128,
         "64-bit websocket length rejected");
      Expect_Protocol_Error
        (Character'Val (16#81#) & Character'Val (16#FE#) & Character'Val (0),
         128,
         "short extended websocket length rejected");
      Expect_Protocol_Error
        (Character'Val (16#81#)
         & Character'Val (16#FE#)
         & Character'Val (0)
         & Character'Val (2)
         & Mask
         & "ab",
         128,
         "non-minimal websocket length rejected");
      Expect_Protocol_Error
        (Character'Val (16#C1#) & Character'Val (16#80#) & Mask,
         128,
         "websocket rsv bits rejected");
      Expect_Protocol_Error
        (Character'Val (16#88#) & Character'Val (16#81#) & Mask & "x",
         128,
         "one-byte close payload rejected");
      Expect_Protocol_Error
        (Character'Val (16#88#)
         & Character'Val (16#82#)
         & Mask
         & Character'Val (16#02#)
         & Character'Val (16#EF#),
         128,
         "reserved close code rejected");
      Expect_Protocol_Error
        (Character'Val (16#89#) & Character'Val (16#FE#) & Character'Val (0) & Character'Val (126),
         256,
         "extended ping control frame rejected");
   end Test_WebSocket_Hostile_Frames;

   procedure Test_TLS_Policy_Validation (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Context : Web.TLS.Context;
      Raised  : Boolean;
   begin
      Raised := False;
      begin
         Web.TLS.Initialize_Server
           (Context,
            Web.TLS.Configure_Server
              (Certificate_File => "/tmp/no-such-cert.pem",
               Private_Key_File => "/tmp/no-such-key.pem",
               Verify_Client    => Web.TLS.Verify_Required));
      exception
         when Error : Web.Errors.Security_Error =>
            Raised := True;
            Assert
              (Ada.Strings.Fixed.Index
                 (Ada.Exceptions.Exception_Message (Error), "requires a CA file") > 0,
               "client verification fails closed without CA");
      end;
      Web.TLS.Finalize (Context);
      Assert (Raised, "client verification without CA rejected");

      Raised := False;
      begin
         Web.TLS.Initialize_Server
           (Context,
            Web.TLS.Configure_Server
              (Certificate_File => "/tmp/no-such-cert.pem",
               Private_Key_File => "/tmp/no-such-key.pem",
               Minimum_Version  => Web.TLS.TLS_1_3,
               Maximum_Version  => Web.TLS.TLS_1_2));
      exception
         when Error : Web.Errors.Security_Error =>
            Raised := True;
            Assert
              (Ada.Strings.Fixed.Index
                 (Ada.Exceptions.Exception_Message (Error), "below minimum") > 0,
               "version range rejected");
      end;
      Web.TLS.Finalize (Context);
      Assert (Raised, "invalid TLS version range rejected");

      Raised := False;
      begin
         Web.TLS.Initialize_Server
           (Context,
            Web.TLS.Configure_Server
              (Certificate_File => "/tmp/no-such-cert.pem",
               Private_Key_File => "/tmp/no-such-key.pem",
               Cipher_List      => "NO_SUCH_CIPHER"));
      exception
         when Error : Web.Errors.Security_Error =>
            Raised := True;
            Assert
              (Ada.Strings.Fixed.Index
                 (Ada.Exceptions.Exception_Message (Error), "cipher") > 0,
               "cipher error includes detail");
      end;
      Web.TLS.Finalize (Context);
      Assert (Raised, "invalid cipher rejected");

      Raised := False;
      begin
         declare
            Ignored : constant Web.TLS.Server_Config :=
              Web.TLS.Configure_Server
                (Certificate_File => "/tmp/cert" & Character'Val (0) & ".pem",
                 Private_Key_File => "/tmp/key.pem");
         begin
            null;
         end;
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "TLS configuration control bytes rejected");
   end Test_TLS_Policy_Validation;
end Web_Transport_Tests;
