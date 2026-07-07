with Ada.Command_Line;
with Ada.Text_IO;
with Web.Errors;
with Web.Events;
with Web.Protocol;
with Web.Request;
with Web.Security;
with Web.Server;
with Web.Static;
with Web.WebSocket;

procedure Fuzz_Corpus is
   CRLF : constant String := Character'Val (13) & Character'Val (10);
   Failures : Natural := 0;

   procedure Fail (Name : String) is
   begin
      Failures := Failures + 1;
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "failed: " & Name);
   end Fail;

   procedure Expect_HTTP_Rejected (Name : String; Data : String) is
      Request : Web.Request.Request_Type;
      pragma Unreferenced (Request);
   begin
      Request := Web.Server.Parse_Request (Data);
      Fail (Name);
   exception
      when Web.Errors.Bad_Request_Error | Web.Errors.Security_Error | Constraint_Error =>
         null;
      when others =>
         Fail (Name & " unexpected exception");
   end Expect_HTTP_Rejected;

   procedure Expect_Protocol_Rejected (Name : String; Data : String) is
      Event : Web.Events.Event;
      pragma Unreferenced (Event);
   begin
      Event := Web.Protocol.Decode_Client_Message (Data);
      Fail (Name);
   exception
      when Web.Errors.Protocol_Error | Web.Errors.Security_Error | Constraint_Error =>
         null;
      when others =>
         Fail (Name & " unexpected exception");
   end Expect_Protocol_Rejected;

   procedure Expect_Frame_Rejected (Name : String; Data : String) is
      Frame : Web.WebSocket.Frame;
      pragma Unreferenced (Frame);
   begin
      Frame := Web.WebSocket.Decode_Frame (Data, 16);
      Fail (Name);
   exception
      when Web.Errors.Protocol_Error | Web.Errors.Security_Error | Constraint_Error =>
         null;
      when others =>
         Fail (Name & " unexpected exception");
   end Expect_Frame_Rejected;

   procedure Expect_Path_Rejected (Name : String; Path : String) is
   begin
      if Web.Security.Is_Safe_Path (Path) then
         Fail (Name);
      end if;
   end Expect_Path_Rejected;
begin
   Expect_HTTP_Rejected ("chunked request", "GET / HTTP/1.1" & CRLF & "Transfer-Encoding: chunked" & CRLF & CRLF);
   Expect_HTTP_Rejected ("missing host", "GET / HTTP/1.1" & CRLF & CRLF);
   Expect_HTTP_Rejected ("duplicate host", "GET / HTTP/1.1" & CRLF & "Host: a" & CRLF & "Host: b" & CRLF & CRLF);
   Expect_HTTP_Rejected ("bad method", "POST / HTTP/1.1" & CRLF & "Host: localhost" & CRLF & CRLF);
   Expect_HTTP_Rejected ("pipelined", "GET / HTTP/1.1" & CRLF & "Host: localhost" & CRLF & CRLF & "GET / HTTP/1.1");
   Expect_HTTP_Rejected ("encoded traversal", "GET /%2e%2e/x HTTP/1.1" & CRLF & "Host: localhost" & CRLF & CRLF);
   Expect_HTTP_Rejected ("encoded c1", "GET /%80 HTTP/1.1" & CRLF & "Host: localhost" & CRLF & CRLF);
   Expect_HTTP_Rejected ("encoded slash", "GET /a%2fb HTTP/1.1" & CRLF & "Host: localhost" & CRLF & CRLF);

   Expect_Protocol_Rejected ("bad json", "{");
   Expect_Protocol_Rejected ("wrong version", "{""type"":""hello"",""version"":2}");
   Expect_Protocol_Rejected ("missing action", "{""type"":""click"",""version"":1,""id"":""x""}");
   Expect_Protocol_Rejected ("duplicate type", "{""type"":""hello"",""type"":""click"",""version"":1}");

   Expect_Frame_Rejected ("unmasked text", Character'Val (16#81#) & Character'Val (1) & "x");
   Expect_Frame_Rejected ("binary", Character'Val (16#82#) & Character'Val (16#80#) & "abcd");
   Expect_Frame_Rejected ("fragment", Character'Val (16#01#) & Character'Val (16#80#) & "abcd");
   Expect_Frame_Rejected ("oversized control", Character'Val (16#89#) & Character'Val (16#FE#) & "abcd");

   Expect_Path_Rejected ("dotdot", "/../x");
   Expect_Path_Rejected ("backslash", "/a\b");

   declare
      Content : constant String := Web.Static.Content_Type ("bad.unknown");
   begin
      if Content /= "application/octet-stream" then
         Fail ("unknown static type");
      end if;
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("fuzz corpus passed");
   else
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Fuzz_Corpus;
