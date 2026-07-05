with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with AUnit.Assertions;
with AUnit.Test_Caller;
with GNAT.Sockets;
with Interfaces;
with Web.Connection;
with Web.Config;
with Web.Events;
with Web.Live;
with Web.Patch;
with Web.Request;
with Web.Response;
with Web.Server;
with Web.TLS;
with Zlib;

package body Web_E2E_Tests is
   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;
   use Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_8;
   use type Zlib.Status_Code;

   CRLF : constant String := Character'Val (13) & Character'Val (10);
   LF : constant String := (1 => Character'Val (10));
   Test_Cert_Path : constant String := "/tmp/webframework-test-cert.pem";
   Test_Key_Path : constant String := "/tmp/webframework-test-key.pem";
   Test_Certificate : constant String :=
     "-----BEGIN CERTIFICATE-----" & LF
     & "MIIDCTCCAfGgAwIBAgIUW4pBchTw00Odpz3pMkmmX7gYyP8wDQYJKoZIhvcNAQEL" & LF
     & "BQAwFDESMBAGA1UEAwwJbG9jYWxob3N0MB4XDTI2MDcwNDE2NDkzOFoXDTI2MDcw" & LF
     & "NTE2NDkzOFowFDESMBAGA1UEAwwJbG9jYWxob3N0MIIBIjANBgkqhkiG9w0BAQEF" & LF
     & "AAOCAQ8AMIIBCgKCAQEAs8eL1UQUcMyqKzDmbPeGk8maLIBeTwwJb2HiQZaBAPcP" & LF
     & "hpC+3WYIeH9Q9nyF7g4pSkGC03bgit73UdB8me5/ULYVJ4kyVGCZlihBWIZgiZ0x" & LF
     & "SSZ8m+lm9TWaFC6III6pThjMHTvU1Y6CL8uM76n6kJncIBctBWI1+y4moDRcJtYR" & LF
     & "yT/B9VhbpU13uANIwCjaK+a5VzcqOWhXpvEIEqq+exhFoahVKjaS6a2UgHRUTINL" & LF
     & "CLu9xlU0mP3OuV9BB4jBZSbFZZwSFCcD8SECvuSGzFWc1dM4QBkiPz5lxFX0IE70" & LF
     & "LGVwrgLVUbsGOWb6AtjKU4yo8LeWY7t2qXu2yn2yrQIDAQABo1MwUTAdBgNVHQ4E" & LF
     & "FgQUhYicQEbjJy2+dix7KX2xGMvMA0wwHwYDVR0jBBgwFoAUhYicQEbjJy2+dix7" & LF
     & "KX2xGMvMA0wwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAPuJH" & LF
     & "iRF85f1JPd+kE1mmLsQgNv2TctMZugCT+A9GE5g5Ye9pLQIHm6txMSxQascoioH+" & LF
     & "Yn7+hPjP60BBWHoZV56WNgYGvlpL7SOWSoMHfYNEH3mfZG2kTmgbnlyhCZDEjjkx" & LF
     & "F8P13DVN4vJ6OhtLPY9lvwUH/SSdTL45QtQgVABbAe29ASK7XvwZFA9f+sUzZPM3" & LF
     & "zMkvZ4N01OoxEBCa7QhYyPgS2+eHuL0b05+dt/hpS1fbIf3VhSvsgGmUJfIFcpf0" & LF
     & "MbohDxzhRZTdqbNxidCXv3Vm055Q+8czOUNJQRfXMbdG0YfMyK9a+SQ7p+AVvV4Z" & LF
     & "GyLT4/fJ+g9wnu9e+g==" & LF
     & "-----END CERTIFICATE-----" & LF;
   Test_Private_Key : constant String :=
     "-----BEGIN PRIVATE KEY-----" & LF
     & "MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCzx4vVRBRwzKor" & LF
     & "MOZs94aTyZosgF5PDAlvYeJBloEA9w+GkL7dZgh4f1D2fIXuDilKQYLTduCK3vdR" & LF
     & "0HyZ7n9QthUniTJUYJmWKEFYhmCJnTFJJnyb6Wb1NZoULoggjqlOGMwdO9TVjoIv" & LF
     & "y4zvqfqQmdwgFy0FYjX7LiagNFwm1hHJP8H1WFulTXe4A0jAKNor5rlXNyo5aFem" & LF
     & "8QgSqr57GEWhqFUqNpLprZSAdFRMg0sIu73GVTSY/c65X0EHiMFlJsVlnBIUJwPx" & LF
     & "IQK+5IbMVZzV0zhAGSI/PmXEVfQgTvQsZXCuAtVRuwY5ZvoC2MpTjKjwt5Zju3ap" & LF
     & "e7bKfbKtAgMBAAECggEAAJBy6hVD7MV7i7Ksi1/AWWV2Do+q1vKTvXScBApDnTpW" & LF
     & "s8wc/Pyc8oxCEnTAZ0+5+GKc7gEkJCXDSz8SevqvoovHwXFhzzPTYeb2Be5IfdUM" & LF
     & "OoEk0o8Yo4Q5Ll4p7FeXUS+T/yKnV4BxRta09EKETOPq3Ripp37Ah34EegSZ2/VG" & LF
     & "hO+g3O95f9ZWZko5AVNTfE/Vkqp7NZ9t2didMXTN+3tuj7WVpvicLhwxp8/SRJOH" & LF
     & "zMxmFn1adkVocgLjmbk3h8thqZRQtL1J7fBSkM9gGmbsELjyPx3JAGZ+a7bLyP9e" & LF
     & "SQnTRqhyaEccYGsNDoeLz7ueUFZeKn6ZH31C037KswKBgQD77pIw7kLtrgxrLx6K" & LF
     & "kprzFVGktMjIS3AMYJIeuIlOYvYU/1RnDPzKpEqsv0WG4DwfEFpWMPM2OvFwNi+d" & LF
     & "7sytYTxeEiGq4NoNMS8iub6EYafe/TBScN0dKzMUqc+nrXnu1H/2gccReSQkZrVm" & LF
     & "QzYTh8F0Bhn7i1QJf9tulo78PwKBgQC2rramJWV22gyVKIxVEoER38347rlfVLxE" & LF
     & "Jbv8CJLpH4HJevE4KC5AnrC936nV3GEzY7+NI8dOOeq3mYNtGUh6k+ngCbHknPR9" & LF
     & "V4JHotxTlzsfBha90zWwvRIQOkW49oaAeJ6RKGxNX1d1MCqnHrJy9gQJl5sH/y3J" & LF
     & "/rt9pCiGEwKBgFh0/OmnTuKrYPrlcYDQVw2Q57jALVt+eVovMj8NJlDamHLo79a7" & LF
     & "DauNIhcjlaL06scxc7adu1fIPGvc6r02UrFx2cNh9GZOSuGk6lr0AvvyWgIGvkfE" & LF
     & "Dy8lsurHcPz8ATsla8S+7ompElKhqYG9iagz224EkmzrD9fCB+b9gDj7AoGBAKY0" & LF
     & "qwTavUe29v+2FodIAJosjw9O0uUDCQ7PbgrOGitzePfAnTrEg+BTAOafWbuzd9Pz" & LF
     & "itF0nd50HzLPvp1CBYlQjdZBu9INYvuu5F8cs2xyCV4egg5O3WhhfM+61LiFwrWc" & LF
     & "CFh0+KQkfEOogQXvjde+MMoxXuGVryk6U4bqFdx1AoGAAYWusuz8tchgI5Wgj+eU" & LF
     & "aVczknapO3fcAv4t2tYTUQnNxTK1dhjYJD+JeWE4BI9VEtUWfLypzyF+jWimrgWV" & LF
     & "jwe+apeMPzvjR7yEQNyXB2u5cA8/kcxv1OowGnuXKN3keHzO4Nuc+SIIXCFrm1+0" & LF
     & "jTnXGhv7GguL3uYxWOFmShI=" & LF
     & "-----END PRIVATE KEY-----" & LF;

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

   task type Server_Task is
      entry Start (Port : Natural);
   end Server_Task;

   task type TLS_Server_Task is
      entry Start (Port : Natural);
   end TLS_Server_Task;

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("real server live flow", Test_Server_Live_Flow'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("native tls server flow", Test_TLS_Server_Flow'Access));
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

   function Home (Request : Web.Request.Request_Type) return Web.Response.Response_Type is
      Session : constant String := Test_Live.Find_Or_Create_Session (Request);
   begin
      return Test_Live.Html_Response
        (Session,
         "<!doctype html><html><body><span id=""counter-value"">0</span></body></html>");
   end Home;

   task body Server_Task is
      Server_Port : Natural;
   begin
      accept Start (Port : Natural) do
         Server_Port := Port;
      end Start;

      Web.Server.Run ("127.0.0.1", Server_Port);
   end Server_Task;

   task body TLS_Server_Task is
      Server_Port : Natural;
   begin
      accept Start (Port : Natural) do
         Server_Port := Port;
      end Start;

      Web.Server.Run_TLS
        ("127.0.0.1",
         Server_Port,
         Web.TLS.Configure_Server
           (Certificate_File => Test_Cert_Path,
            Private_Key_File => Test_Key_Path,
            Cipher_Suites    => "TLS_AES_256_GCM_SHA384:TLS_AES_128_GCM_SHA256"));
   end TLS_Server_Task;

   procedure Write_Text_File (Path : String; Content : String) is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put (File, Content);
      Ada.Text_IO.Close (File);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Write_Text_File;

   function Free_Port return Natural is
      Socket  : GNAT.Sockets.Socket_Type;
      Address : GNAT.Sockets.Sock_Addr_Type;
   begin
      GNAT.Sockets.Initialize;
      GNAT.Sockets.Create_Socket (Socket);
      Address.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
      Address.Port := 0;
      GNAT.Sockets.Bind_Socket (Socket, Address);
      Address := GNAT.Sockets.Get_Socket_Name (Socket);
      GNAT.Sockets.Close_Socket (Socket);
      return Natural (Address.Port);
   end Free_Port;

   procedure Send_All (Socket : GNAT.Sockets.Socket_Type; Data : String) is
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
   end Send_All;

   function Connect (Port : Natural) return GNAT.Sockets.Socket_Type is
      Socket  : GNAT.Sockets.Socket_Type;
      Address : GNAT.Sockets.Sock_Addr_Type;
   begin
      Address.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
      Address.Port := GNAT.Sockets.Port_Type (Port);

      for Attempt in 1 .. 100 loop
         begin
            GNAT.Sockets.Create_Socket (Socket);
            GNAT.Sockets.Connect_Socket (Socket, Address);
            GNAT.Sockets.Set_Socket_Option
              (Socket,
               GNAT.Sockets.Socket_Level,
               (Name    => GNAT.Sockets.Receive_Timeout,
                Timeout => 2.0));
            return Socket;
         exception
            when GNAT.Sockets.Socket_Error =>
               begin
                  GNAT.Sockets.Close_Socket (Socket);
               exception
                  when others =>
                     null;
               end;
               delay 0.02;
         end;
      end loop;

      Assert (False, "server did not accept connections");
      return Socket;
   end Connect;

   function Stream_To_String
     (Data : Ada.Streams.Stream_Element_Array;
      Last : Ada.Streams.Stream_Element_Offset) return String
   is
      Result : String (1 .. Natural (Last - Data'First + 1));
   begin
      for Offset in Result'Range loop
         Result (Offset) :=
           Character'Val (Data (Data'First + Ada.Streams.Stream_Element_Offset (Offset - 1)));
      end loop;
      return Result;
   end Stream_To_String;

   function To_Bytes (Value : String) return Zlib.Byte_Array is
   begin
      if Value'Length = 0 then
         return Zlib.Byte_Array'(1 .. 0 => 0);
      end if;

      declare
         Result : Zlib.Byte_Array (0 .. Value'Length - 1);
      begin
         for Offset in Result'Range loop
            Result (Offset) := Zlib.Byte (Character'Pos (Value (Value'First + Offset)));
         end loop;
         return Result;
      end;
   end To_Bytes;

   function To_String (Value : Zlib.Byte_Array) return String is
      Result : String (1 .. Value'Length);
   begin
      for Offset in Value'Range loop
         Result (Offset - Value'First + Result'First) := Character'Val (Value (Offset));
      end loop;
      return Result;
   end To_String;

   function Response_Body (Response : String) return String is
      Header_End : constant Natural := Ada.Strings.Fixed.Index (Response, CRLF & CRLF);
   begin
      Assert (Header_End > 0, "response has headers");
      return Response (Header_End + 4 .. Response'Last);
   end Response_Body;

   function Read_Until_Close (Socket : GNAT.Sockets.Socket_Type) return String;

   function Get_Response (Port : Natural; Encoding : String := "") return String is
      Socket : GNAT.Sockets.Socket_Type := Connect (Port);
      Header : Unbounded_String :=
        To_Unbounded_String
          ("GET /e2e HTTP/1.1" & CRLF
           & "Host: 127.0.0.1" & CRLF);
   begin
      if Encoding'Length > 0 then
         Append (Header, "Accept-Encoding: " & Encoding & CRLF);
      end if;

      Append (Header, "Connection: close" & CRLF & CRLF);
      Send_All (Socket, To_String (Header));

      declare
         Response : constant String := Read_Until_Close (Socket);
      begin
         GNAT.Sockets.Close_Socket (Socket);
         return Response;
      end;
   end Get_Response;

   procedure Assert_Inflates
     (Response : String;
      Header   : Zlib.Header_Type;
      Name     : String)
   is
      Status   : Zlib.Status_Code;
      Inflated : constant Zlib.Byte_Array :=
        Zlib.Inflate_With_Header (To_Bytes (Response_Body (Response)), Header, Status);
   begin
      Assert (Status = Zlib.Ok, Name & " response inflates");
      Assert
        (Ada.Strings.Fixed.Index (To_String (Inflated), "id=""counter-value""") > 0,
         Name & " response body");
   end Assert_Inflates;

   function Read_Until_Close (Socket : GNAT.Sockets.Socket_Type) return String is
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 4096);
      Last   : Ada.Streams.Stream_Element_Offset;
      Result : Unbounded_String;
   begin
      loop
         GNAT.Sockets.Receive_Socket (Socket, Buffer, Last);
         exit when Last < Buffer'First;
         Append (Result, Stream_To_String (Buffer, Last));
      end loop;
      return To_String (Result);
   end Read_Until_Close;

   function Read_Until_Close
     (Conn : in out Web.Connection.Connection_Type) return String
   is
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 4096);
      Last   : Ada.Streams.Stream_Element_Offset;
      Result : Unbounded_String;
   begin
      loop
         Web.Connection.Receive (Conn, Buffer, Last);
         exit when Last < Buffer'First;
         Append (Result, Stream_To_String (Buffer, Last));
      end loop;
      return To_String (Result);
   end Read_Until_Close;

   function Read_Headers (Socket : GNAT.Sockets.Socket_Type) return String is
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 512);
      Last   : Ada.Streams.Stream_Element_Offset;
      Result : Unbounded_String;
   begin
      loop
         GNAT.Sockets.Receive_Socket (Socket, Buffer, Last);
         exit when Last < Buffer'First;
         Append (Result, Stream_To_String (Buffer, Last));
         exit when Ada.Strings.Fixed.Index (To_String (Result), CRLF & CRLF) > 0;
      end loop;
      return To_String (Result);
   end Read_Headers;

   function Read_Headers
     (Conn : in out Web.Connection.Connection_Type) return String
   is
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 512);
      Last   : Ada.Streams.Stream_Element_Offset;
      Result : Unbounded_String;
   begin
      loop
         Web.Connection.Receive (Conn, Buffer, Last);
         exit when Last < Buffer'First;
         Append (Result, Stream_To_String (Buffer, Last));
         exit when Ada.Strings.Fixed.Index (To_String (Result), CRLF & CRLF) > 0;
      end loop;
      return To_String (Result);
   end Read_Headers;

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

   function Read_Exact
     (Conn  : in out Web.Connection.Connection_Type;
      Count : Natural) return String
   is
      Buffer : Ada.Streams.Stream_Element_Array (1 .. Ada.Streams.Stream_Element_Offset (Count));
      Last   : Ada.Streams.Stream_Element_Offset;
      Cursor : Ada.Streams.Stream_Element_Offset := Buffer'First;
      Result : String (1 .. Count);
   begin
      while Cursor <= Buffer'Last loop
         Web.Connection.Receive (Conn, Buffer (Cursor .. Buffer'Last), Last);
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
      Length_Code : constant Natural := Character'Pos (Header (Header'First + 1)) mod 16#80#;
      Length : Natural := Length_Code;
      Extra : Unbounded_String;
   begin
      if Length_Code = 126 then
         declare
            Bytes : constant String := Read_Exact (Socket, 2);
         begin
            Length :=
              Character'Pos (Bytes (Bytes'First)) * 256
              + Character'Pos (Bytes (Bytes'First + 1));
            Append (Extra, Bytes);
         end;
      end if;

      return Header & To_String (Extra) & Read_Exact (Socket, Length);
   end Receive_Server_Frame;

   function Receive_Server_Frame
     (Conn : in out Web.Connection.Connection_Type) return String
   is
      Header : constant String := Read_Exact (Conn, 2);
      Length_Code : constant Natural := Character'Pos (Header (Header'First + 1)) mod 16#80#;
      Length : Natural := Length_Code;
      Extra : Unbounded_String;
   begin
      if Length_Code = 126 then
         declare
            Bytes : constant String := Read_Exact (Conn, 2);
         begin
            Length :=
              Character'Pos (Bytes (Bytes'First)) * 256
              + Character'Pos (Bytes (Bytes'First + 1));
            Append (Extra, Bytes);
         end;
      end if;

      return Header & To_String (Extra) & Read_Exact (Conn, Length);
   end Receive_Server_Frame;

   function Cookie_Header (Response : String) return String is
      Prefix : constant String := "Set-Cookie:";
      Start_Pos : constant Natural := Ada.Strings.Fixed.Index (Response, Prefix);
      Stop_Pos : Natural;
      Value : Unbounded_String;
   begin
      Assert (Start_Pos > 0, "GET response includes Set-Cookie");
      Stop_Pos := Ada.Strings.Fixed.Index (Response (Start_Pos .. Response'Last), CRLF);
      Assert (Stop_Pos > Start_Pos, "Set-Cookie line terminates");
      Value := To_Unbounded_String
        (Ada.Strings.Fixed.Trim
           (Response (Start_Pos + Prefix'Length .. Stop_Pos - 1), Ada.Strings.Both));

      declare
         Full : constant String := To_String (Value);
         Separator : constant Natural := Ada.Strings.Fixed.Index (Full, ";");
      begin
         if Separator > 0 then
            return Full (Full'First .. Separator - 1);
         end if;
         return Full;
      end;
   end Cookie_Header;

   procedure Test_Server_Live_Flow (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Port : constant Natural := Free_Port;
      Worker : Server_Task;
      Http : GNAT.Sockets.Socket_Type;
      Websocket : GNAT.Sockets.Socket_Type;
      Config : Web.Config.Config_Type := Web.Config.Default_Config;
   begin
      Web.Server.Configure (Web.Config.Default_Config);
      Config.Compression_Min_Size := 0;
      Web.Server.Configure (Config);
      Web.Server.Get ("/e2e", Home'Access);
      Web.Server.WebSocket ("/e2e-ws", Test_Live.WebSocket_Handler'Access);
      Worker.Start (Port);

      Http := Connect (Port);
      Send_All
        (Http,
         "GET /e2e HTTP/1.1" & CRLF
         & "Host: 127.0.0.1" & CRLF
         & "Connection: close" & CRLF
         & CRLF);

      declare
         Response : constant String := Read_Until_Close (Http);
         Cookie : constant String := Cookie_Header (Response);
      begin
         GNAT.Sockets.Close_Socket (Http);
         Assert (Ada.Strings.Fixed.Index (Response, "HTTP/1.1 200") > 0, "GET returned 200");
         Assert (Ada.Strings.Fixed.Index (Response, "id=""counter-value""") > 0, "page body");

         declare
            Gzip_Response : constant String := Get_Response (Port, "gzip");
            Deflate_Response : constant String := Get_Response (Port, "deflate");
            Wildcard_Response : constant String := Get_Response (Port, "*");
            Disabled_Response : constant String := Get_Response (Port, "gzip;q=0, *;q=0");
            Explicit_Response : constant String := Get_Response (Port, "gzip;q=0, *");
            Weighted_Response : constant String := Get_Response (Port, "gzip;q=0.3, deflate;q=0.8");
            Tie_Response : constant String := Get_Response (Port, "gzip;q=0.5, deflate;q=0.5");
            Precise_Response : constant String := Get_Response (Port, "gzip;q=1.000, deflate;q=0.999");
            Junk_Q_Response : constant String := Get_Response (Port, "gzip;q=0.900x, deflate;q=0.100");
            Long_Q_Response : constant String := Get_Response (Port, "gzip;q=0.9000, deflate;q=0.100");
            Empty_Q_Response : constant String := Get_Response (Port, "gzip;q=0., deflate;q=0.100");
            No_Representation_Response : constant String :=
              Get_Response (Port, "gzip;q=0, deflate;q=0, identity;q=0");
            Bad_Identity_Response : constant String :=
              Get_Response (Port, "gzip;q=0, deflate;q=0, identity;q=0.000x");
         begin
            Assert
              (Ada.Strings.Fixed.Index (Gzip_Response, "Content-Encoding: gzip") > 0,
               "gzip response header");
            Assert
              (Ada.Strings.Fixed.Index (Gzip_Response, "Vary: Accept-Encoding") > 0,
               "gzip vary response header");
            Assert
              (Ada.Strings.Fixed.Index (Deflate_Response, "Content-Encoding: deflate") > 0,
               "deflate response header");
            Assert
              (Ada.Strings.Fixed.Index (Wildcard_Response, "Content-Encoding: gzip") > 0,
               "wildcard prefers gzip");
            Assert
              (Ada.Strings.Fixed.Index (Disabled_Response, "Content-Encoding:") = 0,
               "q zero disables response compression");
            Assert
              (Ada.Strings.Fixed.Index (Explicit_Response, "Content-Encoding: deflate") > 0,
               "explicit gzip q zero falls through to wildcard deflate");
            Assert
              (Ada.Strings.Fixed.Index (Weighted_Response, "Content-Encoding: deflate") > 0,
               "higher q value selects deflate");
            Assert
              (Ada.Strings.Fixed.Index (Tie_Response, "Content-Encoding: gzip") > 0,
               "equal q value prefers gzip");
            Assert
              (Ada.Strings.Fixed.Index (Precise_Response, "Content-Encoding: gzip") > 0,
               "three digit q value is accepted");
            Assert
              (Ada.Strings.Fixed.Index (Junk_Q_Response, "Content-Encoding: deflate") > 0,
               "trailing q junk disables encoding");
            Assert
              (Ada.Strings.Fixed.Index (Long_Q_Response, "Content-Encoding: deflate") > 0,
               "overprecise q value disables encoding");
            Assert
              (Ada.Strings.Fixed.Index (Empty_Q_Response, "Content-Encoding: deflate") > 0,
               "empty fractional q value disables encoding");
            Assert
              (Ada.Strings.Fixed.Index (No_Representation_Response, "HTTP/1.1 406 Not Acceptable") > 0,
               "identity q zero returns not acceptable");
            Assert
              (Ada.Strings.Fixed.Index (Bad_Identity_Response, "HTTP/1.1 406 Not Acceptable") > 0,
               "malformed identity q value returns not acceptable");
            Assert_Inflates (Gzip_Response, Zlib.GZip, "gzip");
            Assert_Inflates (Deflate_Response, Zlib.Zlib_Header, "deflate");
         end;

         Config.Enable_Compression := False;
         Web.Server.Configure (Config);
         declare
            Disabled_By_Config : constant String := Get_Response (Port, "gzip");
         begin
            Assert
              (Ada.Strings.Fixed.Index (Disabled_By_Config, "Content-Encoding:") = 0,
               "config disables response compression");
         end;

         Config.Enable_Compression := True;
         Config.Compression_Min_Size := 8_192;
         Web.Server.Configure (Config);
         declare
            Below_Threshold : constant String := Get_Response (Port, "gzip");
         begin
            Assert
              (Ada.Strings.Fixed.Index (Below_Threshold, "Content-Encoding:") = 0,
               "compression threshold skips small response");
            Assert
              (Ada.Strings.Fixed.Index (Below_Threshold, "HTTP/1.1 200 OK") > 0,
               "identity fallback remains acceptable by default");
         end;

         Config.Compression_Min_Size := 0;
         Web.Server.Configure (Config);

         Websocket := Connect (Port);
         Send_All
           (Websocket,
            "GET /e2e-ws HTTP/1.1" & CRLF
            & "Host: 127.0.0.1" & CRLF
            & "Upgrade: websocket" & CRLF
            & "Connection: Upgrade" & CRLF
            & "Sec-WebSocket-Version: 13" & CRLF
            & "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" & CRLF
            & "Cookie: " & Cookie & CRLF
            & CRLF);

         declare
            Handshake : constant String := Read_Headers (Websocket);
         begin
            Assert
              (Ada.Strings.Fixed.Index (Handshake, "HTTP/1.1 101 Switching Protocols") > 0,
               "WebSocket upgrade succeeded");
         end;

         Send_All (Websocket, Masked_Frame (9, "q"));
         declare
            Pong_Frame : constant String := Receive_Server_Frame (Websocket);
         begin
            Assert (Character'Pos (Pong_Frame (Pong_Frame'First)) = 16#8A#, "real server pong");
         end;

         Send_All
           (Websocket,
            Masked_Frame
              (1,
               "{""type"":""click"",""version"":1,""id"":""counter-inc"","
               & """action"":""counter.increment""}"));

         declare
            Patch_Frame : constant String := Receive_Server_Frame (Websocket);
         begin
            Assert (Character'Pos (Patch_Frame (Patch_Frame'First)) = 16#81#, "patch text frame");
            Assert
              (Ada.Strings.Fixed.Index (Patch_Frame, """type"":""patches""") > 0,
               "patch message type");
            Assert
              (Ada.Strings.Fixed.Index (Patch_Frame, """target"":""counter-value""") > 0,
               "patch target");
            Assert (Ada.Strings.Fixed.Index (Patch_Frame, """value"":""1""") > 0, "patch value");
         end;

         Send_All (Websocket, Masked_Frame (8, ""));
         declare
            Close_Frame : constant String := Receive_Server_Frame (Websocket);
         begin
            Assert (Character'Pos (Close_Frame (Close_Frame'First)) = 16#88#, "close response");
         end;
         GNAT.Sockets.Close_Socket (Websocket);
      end;

      Web.Server.Stop;
      Web.Server.Configure (Web.Config.Default_Config);
   exception
      when others =>
         Web.Server.Stop;
         Web.Server.Configure (Web.Config.Default_Config);
         raise;
   end Test_Server_Live_Flow;

   procedure Test_TLS_Server_Flow (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Port : constant Natural := Free_Port;
      Worker : TLS_Server_Task;
      Socket : GNAT.Sockets.Socket_Type;
      Conn : Web.Connection.Connection_Type;
      Client_Context : Web.TLS.Context;
   begin
      Write_Text_File (Test_Cert_Path, Test_Certificate);
      Write_Text_File (Test_Key_Path, Test_Private_Key);
      Web.Server.Get ("/tls-e2e", Home'Access);
      Web.Server.WebSocket ("/tls-e2e-ws", Test_Live.WebSocket_Handler'Access);
      Worker.Start (Port);

      Web.TLS.Initialize_Client_No_Verify (Client_Context);
      Socket := Connect (Port);
      Web.Connection.Open_TLS
        (Conn,
         Socket,
         Web.TLS.Connect_Connection (Client_Context, Socket));

      Web.Connection.Send_All
        (Conn,
         "GET /tls-e2e HTTP/1.1" & CRLF
         & "Host: 127.0.0.1" & CRLF
         & "Connection: close" & CRLF
         & CRLF);

      declare
         Response : constant String := Read_Until_Close (Conn);
         Cookie : constant String := Cookie_Header (Response);
      begin
         Assert (Ada.Strings.Fixed.Index (Response, "HTTP/1.1 200") > 0, "HTTPS GET returned 200");
         Assert (Ada.Strings.Fixed.Index (Response, "id=""counter-value""") > 0, "HTTPS body");

         Web.Connection.Close (Conn);
         Web.Server.Reload_TLS
           (Web.TLS.Configure_Server
              (Certificate_File => Test_Cert_Path,
               Private_Key_File => Test_Key_Path,
               Cipher_Suites    => "TLS_AES_256_GCM_SHA384:TLS_AES_128_GCM_SHA256"));
         Socket := Connect (Port);
         Web.Connection.Open_TLS
           (Conn,
            Socket,
            Web.TLS.Connect_Connection (Client_Context, Socket));

         Web.Connection.Send_All
           (Conn,
            "GET /tls-e2e-ws HTTP/1.1" & CRLF
            & "Host: 127.0.0.1" & CRLF
            & "Upgrade: websocket" & CRLF
            & "Connection: Upgrade" & CRLF
            & "Sec-WebSocket-Version: 13" & CRLF
            & "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" & CRLF
            & "Cookie: " & Cookie & CRLF
            & CRLF);

         declare
            Handshake : constant String := Read_Headers (Conn);
         begin
            Assert
              (Ada.Strings.Fixed.Index (Handshake, "HTTP/1.1 101 Switching Protocols") > 0,
               "WSS upgrade succeeded");
         end;

         Web.Connection.Send_All (Conn, Masked_Frame (9, "q"));
         declare
            Pong_Frame : constant String := Receive_Server_Frame (Conn);
         begin
            Assert (Character'Pos (Pong_Frame (Pong_Frame'First)) = 16#8A#, "WSS pong");
         end;

         Web.Connection.Send_All
           (Conn,
            Masked_Frame
              (1,
               "{""type"":""click"",""version"":1,""id"":""counter-inc"","
               & """action"":""counter.increment""}"));

         declare
            Patch_Frame : constant String := Receive_Server_Frame (Conn);
         begin
            Assert (Character'Pos (Patch_Frame (Patch_Frame'First)) = 16#81#, "WSS patch frame");
            Assert
              (Ada.Strings.Fixed.Index (Patch_Frame, """target"":""counter-value""") > 0,
               "WSS patch target");
         end;

         Web.Connection.Send_All (Conn, Masked_Frame (8, ""));
         declare
            Close_Frame : constant String := Receive_Server_Frame (Conn);
         begin
            Assert (Character'Pos (Close_Frame (Close_Frame'First)) = 16#88#, "WSS close response");
         end;
      end;

      Web.Connection.Close (Conn);
      Web.TLS.Finalize (Client_Context);
      Web.Server.Stop;
   exception
      when others =>
         Web.Connection.Close (Conn);
         Web.TLS.Finalize (Client_Context);
         Web.Server.Stop;
         raise;
   end Test_TLS_Server_Flow;
end Web_E2E_Tests;
