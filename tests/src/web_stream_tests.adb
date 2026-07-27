with AUnit.Assertions; use AUnit.Assertions;
with AUnit.Test_Caller;

with Ada.Streams; use Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with GNAT.Sockets;

with Web.Server;
with Web.Http_Body;
with Web.Request;
with Web.Response;
with Web.Config;

--  Live-socket test for the streaming upload lane: it starts a real server with a
--  Post_Stream route whose handler drains the body from the reader and echoes the
--  byte count, then sends a 40 KB request over a socket and confirms every body
--  byte was streamed (leftover from the head read plus multiple socket reads).
package body Web_Stream_Tests is

   CRLF : constant String := ASCII.CR & ASCII.LF;

   function Echo_Size
     (Request : Web.Request.Request_Type;
      Body_R  : in out Web.Http_Body.Reader) return Web.Response.Response_Type
   is
      pragma Unreferenced (Request);
      Buf   : Stream_Element_Array (1 .. 1024);
      Last  : Stream_Element_Offset;
      Done  : Boolean;
      Closed : Boolean;
      Total : Natural := 0;
   begin
      loop
         Web.Http_Body.Read (Body_R, Buf, Last, Done, Closed);
         if Last >= Buf'First then
            Total := Total + Natural (Last - Buf'First + 1);
         end if;
         exit when Done or else Closed;
      end loop;
      return Web.Response.Text ("got" & Natural'Image (Total));
   end Echo_Size;

   task type Server_Task is
      entry Start (Port : Natural);
   end Server_Task;

   task body Server_Task is
      P : Natural;
   begin
      accept Start (Port : Natural) do
         P := Port;
      end Start;
      Web.Server.Run ("127.0.0.1", P);
   end Server_Task;

   function Free_Port return Natural is
      Socket  : GNAT.Sockets.Socket_Type;
      Address : GNAT.Sockets.Sock_Addr_Type;
      Bound   : GNAT.Sockets.Sock_Addr_Type;
   begin
      GNAT.Sockets.Create_Socket (Socket);
      Address.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
      Address.Port := 0;
      GNAT.Sockets.Bind_Socket (Socket, Address);
      Bound := GNAT.Sockets.Get_Socket_Name (Socket);
      GNAT.Sockets.Close_Socket (Socket);
      return Natural (Bound.Port);
   end Free_Port;

   function Connect (Port : Natural) return GNAT.Sockets.Socket_Type is
      Socket  : GNAT.Sockets.Socket_Type;
      Address : GNAT.Sockets.Sock_Addr_Type;
      Tries   : Natural := 0;
   begin
      Address.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
      Address.Port := GNAT.Sockets.Port_Type (Port);
      loop
         begin
            GNAT.Sockets.Create_Socket (Socket);
            GNAT.Sockets.Connect_Socket (Socket, Address);
            return Socket;
         exception
            when others =>
               begin
                  GNAT.Sockets.Close_Socket (Socket);
               exception
                  when others => null;
               end;
               Tries := Tries + 1;
               exit when Tries > 500;
         end;
      end loop;
      raise Program_Error with "could not connect to the test server";
   end Connect;

   procedure Send_All (Socket : GNAT.Sockets.Socket_Type; Data : String) is
      Buffer : Stream_Element_Array (1 .. Data'Length);
      First  : Stream_Element_Offset := Buffer'First;
      Last   : Stream_Element_Offset;
   begin
      for I in Data'Range loop
         Buffer (Stream_Element_Offset (I - Data'First + 1)) :=
           Stream_Element (Character'Pos (Data (I)));
      end loop;
      while First <= Buffer'Last loop
         GNAT.Sockets.Send_Socket (Socket, Buffer (First .. Buffer'Last), Last);
         exit when Last < First;
         First := Last + 1;
      end loop;
   end Send_All;

   function Read_All (Socket : GNAT.Sockets.Socket_Type) return String is
      Result : Unbounded_String;
      Buffer : Stream_Element_Array (1 .. 4096);
      Last   : Stream_Element_Offset;
   begin
      loop
         GNAT.Sockets.Receive_Socket (Socket, Buffer, Last);
         exit when Last < Buffer'First;
         for I in Buffer'First .. Last loop
            Append (Result, Character'Val (Integer (Buffer (I))));
         end loop;
      end loop;
      return To_String (Result);
   end Read_All;

   procedure Test_Stream_Upload (T : in out Fixture) is
      pragma Unreferenced (T);
      Port    : constant Natural := Free_Port;
      Worker  : Server_Task;
      Http    : GNAT.Sockets.Socket_Type;
      Payload : constant String := [1 .. 40_000 => 'x'];
   begin
      Web.Server.Stop;
      Web.Server.Configure (Web.Config.Default_Config);
      Web.Server.Post_Stream ("/stream-echo", Echo_Size'Access);
      Worker.Start (Port);

      Http := Connect (Port);
      Send_All
        (Http,
         "POST /stream-echo HTTP/1.1" & CRLF
         & "Host: 127.0.0.1" & CRLF
         & "Content-Type: application/octet-stream" & CRLF
         & "Content-Length:" & Natural'Image (Payload'Length) & CRLF
         & "Connection: close" & CRLF
         & CRLF
         & Payload);

      declare
         Response : constant String := Read_All (Http);
      begin
         GNAT.Sockets.Close_Socket (Http);
         Assert (Ada.Strings.Fixed.Index (Response, "HTTP/1.1 200") > 0,
                 "streaming upload returns 200");
         Assert (Ada.Strings.Fixed.Index (Response, "got 40000") > 0,
                 "the handler streamed all 40000 body bytes from the socket");
      end;

      Web.Server.Stop;
   end Test_Stream_Upload;

   package Caller is new AUnit.Test_Caller (Fixture);
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("streaming upload live socket", Test_Stream_Upload'Access));
   end Add_Tests;

end Web_Stream_Tests;
