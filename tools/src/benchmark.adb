with Ada.Calendar;
with Ada.Command_Line;
with Ada.Directories;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Benchmark_Handlers;
with GNAT.Sockets;
with Interfaces;
with Web.Config;
with Web.Html;
with Web.Events;
with Web.Patch;
with Web.Protocol;
with Web.Request;
with Web.Response;
with Web.Server;
with Web.Static;
with Web.WebSocket;

procedure Benchmark is
   use Ada.Strings.Fixed;
   use type Ada.Calendar.Time;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_8;
   use type Web.Events.Event_Kind;

   CRLF : constant String := Character'Val (13) & Character'Val (10);

   function Iterations return Positive is
   begin
      if Ada.Command_Line.Argument_Count >= 1 then
         return Positive'Value (Ada.Command_Line.Argument (1));
      end if;
      return 20_000;
   end Iterations;

   function Worker_Count return Positive is
   begin
      if Ada.Command_Line.Argument_Count >= 2 then
         return Positive'Value (Ada.Command_Line.Argument (2));
      end if;
      return 4;
   end Worker_Count;

   function Depth_Count return Positive is
   begin
      if Ada.Command_Line.Argument_Count >= 3 then
         return Positive'Value (Ada.Command_Line.Argument (3));
      end if;
      return 1;
   end Depth_Count;

   function Mode return String is
   begin
      if Ada.Command_Line.Argument_Count >= 4 then
         return Ada.Command_Line.Argument (4);
      end if;
      return "normal";
   end Mode;

   Repeat_Count : constant Positive := Iterations;
   Concurrent_Workers : constant Positive := Worker_Count;
   Benchmark_Depth : constant Positive := Depth_Count;
   Benchmark_Mode : constant String := Mode;
   Server_Port : Natural := 0;

   procedure Report
     (Name    : String;
      Elapsed : Duration;
      Count   : Positive)
   is
      Per_Second : constant Long_Float :=
        (if Elapsed > 0.0 then Long_Float (Count) / Long_Float (Elapsed) else 0.0);
   begin
      Ada.Text_IO.Put_Line
        (Name
         & ": "
         & Trim (Duration'Image (Elapsed), Ada.Strings.Both)
         & "s, "
         & Trim (Long_Float'Image (Per_Second), Ada.Strings.Both)
         & "/s");
   end Report;

   procedure Time_Count
     (Name    : String;
      Count   : Positive;
      Process : not null access procedure)
   is
      Start_Time : constant Ada.Calendar.Time := Ada.Calendar.Clock;
   begin
      for Index_Value in 1 .. Count loop
         Process.all;
      end loop;
      Report (Name, Ada.Calendar.Clock - Start_Time, Count);
   end Time_Count;

   procedure Time
     (Name    : String;
      Process : not null access procedure)
   is
   begin
      Time_Count (Name, Repeat_Count, Process);
   end Time;

   Request_Text : constant String :=
     "GET /bench?x=1 HTTP/1.1" & CRLF
     & "Host: 127.0.0.1" & CRLF
     & "Accept-Encoding: gzip, deflate" & CRLF
     & "Connection: close" & CRLF
     & CRLF;

   WebSocket_Frame : constant String :=
     Character'Val (16#81#)
     & Character'Val (16#82#)
     & Character'Val (16#37#)
     & Character'Val (16#FA#)
     & Character'Val (16#21#)
     & Character'Val (16#3D#)
     & Character'Val (16#7F#)
     & Character'Val (16#93#);

   Live_Message : constant String :=
     "{""type"":""click"",""version"":1,""id"":""counter-inc"",""action"":""counter.increment""}";

   Patch_List : Web.Patch.Patch_List;
   Static_Directory : constant String := "/tmp/webframework-benchmark-static";
   Static_Path      : constant String := Static_Directory & "/style.css";
   Static_Variant_Count : constant Positive := 128;
   Static_Cold_Index : Natural := 0;
   Compression_Miss_Index : Natural := 0;
   Live_Counter : Natural := 0;

   function Trimmed_Natural (Value : Natural) return String is
   begin
      return Trim (Natural'Image (Value), Ada.Strings.Both);
   end Trimmed_Natural;

   function Static_Variant_Path (Index_Value : Positive) return String is
   begin
      return Static_Directory & "/style-" & Trimmed_Natural (Index_Value) & ".css";
   end Static_Variant_Path;

   function Static_Variant_Url (Index_Value : Positive) return String is
   begin
      return "/assets/style-" & Trimmed_Natural (Index_Value) & ".css";
   end Static_Variant_Url;

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
         if Last < First then
            raise Program_Error with "socket send failed";
         end if;
         First := Last + 1;
      end loop;
   end Send_All;

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

   function Read_Until (Socket : GNAT.Sockets.Socket_Type; Marker : String) return String is
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 4096);
      Last   : Ada.Streams.Stream_Element_Offset;
      Result : Ada.Strings.Unbounded.Unbounded_String;
   begin
      loop
         GNAT.Sockets.Receive_Socket (Socket, Buffer, Last);
         exit when Last < Buffer'First;
         Ada.Strings.Unbounded.Append (Result, Stream_To_String (Buffer, Last));
         exit when Index (Ada.Strings.Unbounded.To_String (Result), Marker) > 0;
      end loop;
      return Ada.Strings.Unbounded.To_String (Result);
   end Read_Until;

   function Read_Until_Close (Socket : GNAT.Sockets.Socket_Type) return String is
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 4096);
      Last   : Ada.Streams.Stream_Element_Offset;
      Result : Ada.Strings.Unbounded.Unbounded_String;
   begin
      loop
         GNAT.Sockets.Receive_Socket (Socket, Buffer, Last);
         exit when Last < Buffer'First;
         Ada.Strings.Unbounded.Append (Result, Stream_To_String (Buffer, Last));
      end loop;
      return Ada.Strings.Unbounded.To_String (Result);
   exception
      when others =>
         return Ada.Strings.Unbounded.To_String (Result);
   end Read_Until_Close;

   function Client_Text_Frame (Text : String) return String is
      Mask : constant String :=
        Character'Val (16#12#)
        & Character'Val (16#34#)
        & Character'Val (16#56#)
        & Character'Val (16#78#);
      Result : String (1 .. 6 + Text'Length);
   begin
      if Text'Length > 125 then
         raise Program_Error with "benchmark frame too large";
      end if;

      Result (1) := Character'Val (16#81#);
      Result (2) := Character'Val (16#80# + Text'Length);
      Result (3 .. 6) := Mask;
      for Offset in 0 .. Text'Length - 1 loop
         declare
            Data_Byte : constant Interfaces.Unsigned_8 :=
              Interfaces.Unsigned_8 (Character'Pos (Text (Text'First + Offset)));
            Mask_Byte : constant Interfaces.Unsigned_8 :=
              Interfaces.Unsigned_8 (Character'Pos (Mask (Mask'First + Offset mod 4)));
         begin
            Result (7 + Offset) := Character'Val (Natural (Data_Byte xor Mask_Byte));
         end;
      end loop;
      return Result;
   end Client_Text_Frame;

   function Client_Close_Frame return String is
      Mask : constant String :=
        Character'Val (16#12#)
        & Character'Val (16#34#)
        & Character'Val (16#56#)
        & Character'Val (16#78#);
   begin
      return Character'Val (16#88#) & Character'Val (16#80#) & Mask;
   end Client_Close_Frame;

   task type Benchmark_Server (Port : Natural);

   task body Benchmark_Server is
   begin
      Web.Server.Run ("127.0.0.1", Port);
   end Benchmark_Server;

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

   procedure Set_Timeouts (Socket : GNAT.Sockets.Socket_Type) is
   begin
      GNAT.Sockets.Set_Socket_Option
        (Socket,
         GNAT.Sockets.Socket_Level,
         (Name    => GNAT.Sockets.Receive_Timeout,
          Timeout => 3.0));
      GNAT.Sockets.Set_Socket_Option
        (Socket,
         GNAT.Sockets.Socket_Level,
         (Name    => GNAT.Sockets.Send_Timeout,
          Timeout => 3.0));
   end Set_Timeouts;

   procedure Ensure_Static_File is
      File : Ada.Text_IO.File_Type;
   begin
      if not Ada.Directories.Exists (Static_Directory) then
         Ada.Directories.Create_Directory (Static_Directory);
      end if;

      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Static_Path);
      for Index_Value in 1 .. 100 loop
         Ada.Text_IO.Put_Line (File, ".item { color: #123456; padding: 4px; }");
      end loop;
      Ada.Text_IO.Close (File);

      for File_Index in 1 .. Static_Variant_Count loop
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Static_Variant_Path (File_Index));
         Ada.Text_IO.Put_Line
           (File,
            ".item-" & Trimmed_Natural (File_Index) & " { color: #123456; padding: 4px; }");
         Ada.Text_IO.Close (File);
      end loop;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Ensure_Static_File;

   procedure Bench_Request_Parse is
      Request : constant Web.Request.Request_Type := Web.Server.Parse_Request (Request_Text);
      procedure Check_Path (Value : String);

      procedure Check_Path (Value : String) is
      begin
         if Value /= "/bench" then
            raise Program_Error with "bad parse";
         end if;
      end Check_Path;

      procedure With_Path is new Web.Request.With_Path (Check_Path);
   begin
      With_Path (Request);
   end Bench_Request_Parse;

   procedure Bench_WebSocket_Decode is
      Frame : constant Web.WebSocket.Frame := Web.WebSocket.Decode_Frame (WebSocket_Frame, 128);
   begin
      if Web.WebSocket.Payload (Frame) /= "Hi" then
         raise Program_Error with "bad websocket decode";
      end if;
   end Bench_WebSocket_Decode;

   procedure Bench_Patch_Encode is
      Encoded : constant String := Web.Protocol.Encode_Patches (Patch_List);
   begin
      if Index (Encoded, """patches""") = 0 then
         raise Program_Error with "bad patch encode";
      end if;
   end Bench_Patch_Encode;

   procedure Bench_Route_Dispatch is
      Request : constant Web.Request.Request_Type := Web.Request.Create ("GET", "/bench");
      Response : constant Web.Response.Response_Type := Web.Server.Dispatch (Request);
   begin
      if Web.Response.Status (Response) /= 200 then
         raise Program_Error with "bad dispatch";
      end if;
   end Bench_Route_Dispatch;

   procedure Bench_Static_Serve is
      Response : constant Web.Response.Response_Type :=
        Web.Static.Serve ("/assets", Static_Directory, "/assets/style.css");
   begin
      if Web.Response.Status (Response) /= 200 then
         raise Program_Error with "bad static serve";
      end if;
   end Bench_Static_Serve;

   procedure Bench_Static_Cache_Churn is
      File_Index : Positive;
   begin
      Static_Cold_Index := Static_Cold_Index mod Static_Variant_Count + 1;
      File_Index := Positive (Static_Cold_Index);
      declare
         Response : constant Web.Response.Response_Type :=
           Web.Static.Serve ("/assets", Static_Directory, Static_Variant_Url (File_Index));
      begin
         if Web.Response.Status (Response) /= 200 then
            raise Program_Error with "bad static churn serve";
         end if;
      end;
   end Bench_Static_Cache_Churn;

   procedure Bench_Compression_Cache is
      Response : Web.Response.Response_Type :=
        Web.Response.Html ((1 .. 512 => 'x'));
   begin
      Web.Response.Set_Cache_Key (Response, "benchmark:html:512");
      Response := Web.Response.Compressed (Response, Web.Response.GZip);
      if not Web.Response.Has_Header (Response, "Content-Encoding") then
         raise Program_Error with "bad compression";
      end if;
   end Bench_Compression_Cache;

   procedure Bench_Compression_Cache_Miss is
      Response : Web.Response.Response_Type :=
        Web.Response.Html ((1 .. 512 => 'y'));
   begin
      Compression_Miss_Index := Compression_Miss_Index + 1;
      Web.Response.Set_Cache_Key
        (Response,
         "benchmark:html:miss:" & Trimmed_Natural (Compression_Miss_Index));
      Response := Web.Response.Compressed (Response, Web.Response.GZip);
      if not Web.Response.Has_Header (Response, "Content-Encoding") then
         raise Program_Error with "bad compression miss";
      end if;
   end Bench_Compression_Cache_Miss;

   procedure Bench_Protocol_Submit is
      Event : constant Web.Events.Event :=
        Web.Protocol.Decode_Client_Message
          ("{""type"":""submit"",""version"":1,""id"":""profile-form"","
           & """action"":""profile.save"",""fields"":{""name"":""Bent"",""email"":""b@example.test""}}");
   begin
      if Web.Events.Kind (Event) /= Web.Events.Submit_Event
        or else Web.Events.Field (Event, "name") /= "Bent"
      then
         raise Program_Error with "bad submit decode";
      end if;
   end Bench_Protocol_Submit;

   procedure Bench_Live_Session_Flow is
      Event   : constant Web.Events.Event := Web.Protocol.Decode_Client_Message (Live_Message);
      Patches : Web.Patch.Patch_List;
      Encoded : Ada.Strings.Unbounded.Unbounded_String;
   begin
      if Web.Events.Kind (Event) /= Web.Events.Click_Event then
         raise Program_Error with "bad live event kind";
      end if;

      Live_Counter := Live_Counter + 1;
      Web.Patch.Append
        (Patches,
         Web.Patch.Set_Text ("counter", Trimmed_Natural (Live_Counter)));
      Encoded := Ada.Strings.Unbounded.To_Unbounded_String (Web.Protocol.Encode_Patches (Patches));
      if Index (Ada.Strings.Unbounded.To_String (Encoded), """patches""") = 0 then
         raise Program_Error with "bad live flow encode";
      end if;
   end Bench_Live_Session_Flow;

   procedure Report_Allocation_Audit is
      Request : constant Web.Request.Request_Type := Web.Server.Parse_Request (Request_Text);
      Frame : constant Web.WebSocket.Frame := Web.WebSocket.Decode_Frame (WebSocket_Frame, 128);
      Encoded_Patches : constant String := Web.Protocol.Encode_Patches (Patch_List);
      Dispatched : constant Web.Response.Response_Type :=
        Web.Server.Dispatch (Web.Request.Create ("GET", "/bench"));
      Serialized : constant String := Web.Response.Serialize (Dispatched);
      Compress_Source : Web.Response.Response_Type :=
        Web.Response.Html ((1 .. 512 => 'x'));
      Compressed : Web.Response.Response_Type;
   begin
      Web.Response.Set_Cache_Key (Compress_Source, "benchmark:audit:compression");
      Compressed := Web.Response.Compressed (Compress_Source, Web.Response.GZip);

      Ada.Text_IO.Put_Line ("allocation_audit.request_wire_bytes=" & Trimmed_Natural (Request_Text'Length));
      Ada.Text_IO.Put_Line
        ("allocation_audit.request_path_bytes="
         & Trimmed_Natural (Web.Request.Path (Request)'Length));
      Ada.Text_IO.Put_Line
        ("allocation_audit.request_accept_encoding_bytes="
         & Trimmed_Natural (Web.Request.Header (Request, "Accept-Encoding")'Length));
      Ada.Text_IO.Put_Line ("allocation_audit.websocket_frame_bytes=" & Trimmed_Natural (WebSocket_Frame'Length));
      Ada.Text_IO.Put_Line ("allocation_audit.websocket_payload_bytes=" & Trimmed_Natural (Frame.Payload_Length));
      Ada.Text_IO.Put_Line ("allocation_audit.protocol_event_bytes=" & Trimmed_Natural (Live_Message'Length));
      Ada.Text_IO.Put_Line ("allocation_audit.patch_json_bytes=" & Trimmed_Natural (Encoded_Patches'Length));
      Ada.Text_IO.Put_Line
        ("allocation_audit.response_body_bytes="
         & Trimmed_Natural (Web.Response.Body_Length (Dispatched)));
      Ada.Text_IO.Put_Line ("allocation_audit.response_serialized_bytes=" & Trimmed_Natural (Serialized'Length));
      Ada.Text_IO.Put_Line ("allocation_audit.compression_input_bytes=" & Trimmed_Natural (512));
      Ada.Text_IO.Put_Line
        ("allocation_audit.compression_output_bytes=" & Trimmed_Natural (Web.Response.Body_Length (Compressed)));
   end Report_Allocation_Audit;

   procedure Run_Profile is
      Profile_Count : constant Positive := Positive'Max (Repeat_Count, 50_000) * Benchmark_Depth;
   begin
      Ada.Text_IO.Put_Line ("profile_iterations=" & Trimmed_Natural (Profile_Count));
      Time_Count ("profile_request_parse", Profile_Count, Bench_Request_Parse'Access);
      Time_Count ("profile_websocket_decode", Profile_Count, Bench_WebSocket_Decode'Access);
      Time_Count ("profile_protocol_submit_decode", Profile_Count, Bench_Protocol_Submit'Access);
      Time_Count ("profile_live_session_flow", Profile_Count, Bench_Live_Session_Flow'Access);
      Time_Count ("profile_patch_encode", Profile_Count, Bench_Patch_Encode'Access);
      Time_Count ("profile_route_dispatch", Profile_Count, Bench_Route_Dispatch'Access);
      Time_Count ("profile_static_warm_serve", Profile_Count, Bench_Static_Serve'Access);
      Time_Count ("profile_compression_cache_hit", Profile_Count, Bench_Compression_Cache'Access);
      Time_Count ("profile_compression_cache_miss", Profile_Count, Bench_Compression_Cache_Miss'Access);
   end Run_Profile;

   protected Completion is
      procedure Reset (Target : Positive);
      procedure Mark_Done;
      entry Wait_All;
   private
      Target_Count : Natural := 0;
      Done_Count   : Natural := 0;
   end Completion;

   protected body Completion is
      procedure Reset (Target : Positive) is
      begin
         Target_Count := Target;
         Done_Count := 0;
      end Reset;

      procedure Mark_Done is
      begin
         Done_Count := Done_Count + 1;
      end Mark_Done;

      entry Wait_All when Target_Count > 0 and then Done_Count >= Target_Count is
      begin
         null;
      end Wait_All;
   end Completion;

   task type Concurrent_HTTP_Worker is
      entry Start (Count : Positive);
   end Concurrent_HTTP_Worker;

   task body Concurrent_HTTP_Worker is
      Local_Count : Positive;
   begin
      accept Start (Count : Positive) do
         Local_Count := Count;
      end Start;

      for Index_Value in 1 .. Local_Count loop
         Bench_Route_Dispatch;
      end loop;
      Completion.Mark_Done;
   exception
      when others =>
         Completion.Mark_Done;
         raise;
   end Concurrent_HTTP_Worker;

   task type Concurrent_Live_Worker is
      entry Start (Count : Positive);
   end Concurrent_Live_Worker;

   task body Concurrent_Live_Worker is
      Local_Count : Positive;
   begin
      accept Start (Count : Positive) do
         Local_Count := Count;
      end Start;

      for Index_Value in 1 .. Local_Count loop
         declare
            Frame   : constant Web.WebSocket.Frame :=
              Web.WebSocket.Decode_Frame (WebSocket_Frame, 128);
            Event   : constant Web.Events.Event :=
              Web.Protocol.Decode_Client_Message (Live_Message);
            Encoded : constant String := Web.Protocol.Encode_Patches (Patch_List);
         begin
            if Web.WebSocket.Payload (Frame) /= "Hi"
              or else Web.Events.Action (Event) /= "counter.increment"
              or else Index (Encoded, """patches""") = 0
            then
               raise Program_Error with "bad concurrent live flow";
            end if;
         end;
      end loop;
      Completion.Mark_Done;
   exception
      when others =>
         Completion.Mark_Done;
         raise;
   end Concurrent_Live_Worker;

   type Concurrent_HTTP_Worker_Access is access Concurrent_HTTP_Worker;
   type Concurrent_Live_Worker_Access is access Concurrent_Live_Worker;

   procedure Bench_Concurrent_HTTP_With (Worker_Total : Positive; Name : String) is
      Per_Worker : constant Positive := Positive'Max (1, Repeat_Count / Worker_Total);
      Workers    : array (1 .. Worker_Total) of Concurrent_HTTP_Worker_Access;
      Start_Time : Ada.Calendar.Time;
   begin
      Completion.Reset (Worker_Total);
      for Index_Value in Workers'Range loop
         Workers (Index_Value) := new Concurrent_HTTP_Worker;
      end loop;

      Start_Time := Ada.Calendar.Clock;
      for Index_Value in Workers'Range loop
         Workers (Index_Value).Start (Per_Worker);
      end loop;
      Completion.Wait_All;
      Report (Name, Ada.Calendar.Clock - Start_Time, Per_Worker * Worker_Total);
   end Bench_Concurrent_HTTP_With;

   procedure Bench_Concurrent_HTTP is
   begin
      Bench_Concurrent_HTTP_With (Concurrent_Workers, "concurrent_http_dispatch");
   end Bench_Concurrent_HTTP;

   procedure Bench_Concurrent_Live_WebSocket_With (Worker_Total : Positive; Name : String) is
      Per_Worker : constant Positive := Positive'Max (1, Repeat_Count / Worker_Total);
      Workers    : array (1 .. Worker_Total) of Concurrent_Live_Worker_Access;
      Start_Time : Ada.Calendar.Time;
   begin
      Completion.Reset (Worker_Total);
      for Index_Value in Workers'Range loop
         Workers (Index_Value) := new Concurrent_Live_Worker;
      end loop;

      Start_Time := Ada.Calendar.Clock;
      for Index_Value in Workers'Range loop
         Workers (Index_Value).Start (Per_Worker);
      end loop;
      Completion.Wait_All;
      Report
        (Name,
         Ada.Calendar.Clock - Start_Time,
         Per_Worker * Worker_Total);
   end Bench_Concurrent_Live_WebSocket_With;

   procedure Bench_Concurrent_Live_WebSocket is
   begin
      Bench_Concurrent_Live_WebSocket_With (Concurrent_Workers, "concurrent_live_websocket");
   end Bench_Concurrent_Live_WebSocket;

   procedure Bench_Real_HTTP is
      Socket  : GNAT.Sockets.Socket_Type;
      Address : GNAT.Sockets.Sock_Addr_Type;
      Request : constant String :=
        "GET /bench HTTP/1.1" & CRLF
        & "Host: 127.0.0.1" & CRLF
        & "Connection: close" & CRLF
        & CRLF;
   begin
      Address.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
      Address.Port := GNAT.Sockets.Port_Type (Server_Port);
      GNAT.Sockets.Create_Socket (Socket);
      Set_Timeouts (Socket);
      GNAT.Sockets.Connect_Socket (Socket, Address);
      Send_All (Socket, Request);
      declare
         Response : constant String := Read_Until (Socket, "ok");
      begin
         GNAT.Sockets.Close_Socket (Socket);
         if Index (Response, "HTTP/1.1 200") /= Response'First then
            raise Program_Error with "bad real http response";
         end if;
      end;
   exception
      when others =>
         begin
            GNAT.Sockets.Close_Socket (Socket);
         exception
            when others =>
               null;
         end;
         raise;
   end Bench_Real_HTTP;

   procedure Bench_Real_WebSocket is
      Socket  : GNAT.Sockets.Socket_Type;
      Address : GNAT.Sockets.Sock_Addr_Type;
      Request : constant String :=
        "GET /bench-ws HTTP/1.1" & CRLF
        & "Host: 127.0.0.1" & CRLF
        & "Upgrade: websocket" & CRLF
        & "Connection: Upgrade" & CRLF
        & "Sec-WebSocket-Version: 13" & CRLF
        & "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" & CRLF
        & CRLF;
   begin
      Address.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
      Address.Port := GNAT.Sockets.Port_Type (Server_Port);
      GNAT.Sockets.Create_Socket (Socket);
      Set_Timeouts (Socket);
      GNAT.Sockets.Connect_Socket (Socket, Address);
      Send_All (Socket, Request);
      declare
         Handshake : constant String := Read_Until (Socket, CRLF & CRLF);
      begin
         if Index (Handshake, "HTTP/1.1 101") /= Handshake'First then
            raise Program_Error with "bad websocket handshake";
         end if;
      end;

      Send_All (Socket, Client_Text_Frame (Live_Message));
      declare
         Response : constant String := Read_Until (Socket, "]}");
      begin
         Send_All (Socket, Client_Close_Frame);
         GNAT.Sockets.Close_Socket (Socket);
         if Index (Response, """patches""") = 0 then
            raise Program_Error with "bad websocket response";
         end if;
      end;
   exception
      when others =>
         begin
            GNAT.Sockets.Close_Socket (Socket);
         exception
            when others =>
               null;
         end;
         raise;
   end Bench_Real_WebSocket;

   procedure Bench_Real_WebSocket_Persistent is
      Socket  : GNAT.Sockets.Socket_Type;
      Address : GNAT.Sockets.Sock_Addr_Type;
      Event_Total : constant Positive := Positive'Min (Repeat_Count, 100);
      Request : constant String :=
        "GET /bench-ws HTTP/1.1" & CRLF
        & "Host: 127.0.0.1" & CRLF
        & "Upgrade: websocket" & CRLF
        & "Connection: Upgrade" & CRLF
        & "Sec-WebSocket-Version: 13" & CRLF
        & "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" & CRLF
        & CRLF;
      Start_Time : Ada.Calendar.Time;
   begin
      Address.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
      Address.Port := GNAT.Sockets.Port_Type (Server_Port);
      GNAT.Sockets.Create_Socket (Socket);
      Set_Timeouts (Socket);
      GNAT.Sockets.Connect_Socket (Socket, Address);
      Send_All (Socket, Request);
      declare
         Handshake : constant String := Read_Until (Socket, CRLF & CRLF);
      begin
         if Index (Handshake, "HTTP/1.1 101") /= Handshake'First then
            raise Program_Error with "bad persistent websocket handshake";
         end if;
      end;

      Start_Time := Ada.Calendar.Clock;
      for Index_Value in 1 .. Event_Total loop
         Send_All (Socket, Client_Text_Frame (Live_Message));
         declare
            Response : constant String := Read_Until (Socket, "]}");
         begin
            if Index (Response, """patches""") = 0 then
               raise Program_Error with "bad persistent websocket response";
            end if;
         end;
      end loop;
      Report ("real_websocket_persistent_events", Ada.Calendar.Clock - Start_Time, Event_Total);
      Send_All (Socket, Client_Close_Frame);
      GNAT.Sockets.Close_Socket (Socket);
   exception
      when others =>
         begin
            GNAT.Sockets.Close_Socket (Socket);
         exception
            when others =>
               null;
         end;
         raise;
   end Bench_Real_WebSocket_Persistent;

begin
   Ensure_Static_File;

   declare
      Config : Web.Config.Config_Type := Web.Config.Default_Config;
   begin
      Config.Max_Connections := 32;
      Web.Server.Configure (Config);
   end;
   Web.Server.Get ("/bench", Benchmark_Handlers.Bench_Handler'Access);
   Web.Server.WebSocket ("/bench-ws", Benchmark_Handlers.Bench_WebSocket'Access);

   Web.Patch.Append
     (Patch_List,
      Web.Patch.Replace_HTML
        ("target",
         Web.Html.Trusted ("<p>hello</p>")));
   Web.Patch.Append (Patch_List, Web.Patch.Set_Text ("counter", "42"));
   Web.Patch.Append (Patch_List, Web.Patch.Set_Attribute ("counter", "data-count", "42"));

   Ada.Text_IO.Put_Line
     ("iterations="
      & Trim (Positive'Image (Repeat_Count), Ada.Strings.Both)
      & " workers="
      & Trim (Positive'Image (Concurrent_Workers), Ada.Strings.Both)
      & " depth="
      & Trim (Positive'Image (Benchmark_Depth), Ada.Strings.Both)
      & " mode="
      & Benchmark_Mode);

   if Benchmark_Mode = "audit" then
      Report_Allocation_Audit;
      return;
   elsif Benchmark_Mode = "profile" then
      Run_Profile;
      return;
   end if;

   Time ("request_parse", Bench_Request_Parse'Access);
   Time ("websocket_decode", Bench_WebSocket_Decode'Access);
   Time ("protocol_submit_decode", Bench_Protocol_Submit'Access);
   Time ("live_session_flow", Bench_Live_Session_Flow'Access);
   Time ("patch_encode", Bench_Patch_Encode'Access);
   Time ("route_dispatch", Bench_Route_Dispatch'Access);
   Time ("static_warm_serve", Bench_Static_Serve'Access);
   Time ("static_cache_churn", Bench_Static_Cache_Churn'Access);
   Time ("compression_cache_hit", Bench_Compression_Cache'Access);
   Time ("compression_cache_miss", Bench_Compression_Cache_Miss'Access);
   Bench_Concurrent_HTTP;
   Bench_Concurrent_Live_WebSocket;

   if Benchmark_Depth > 1 then
      for Phase in 2 .. Benchmark_Depth loop
         declare
            Suffix : constant String := "_phase_" & Trimmed_Natural (Phase);
            Worker_Total : Positive := 1;
         begin
            Time ("protocol_submit_decode" & Suffix, Bench_Protocol_Submit'Access);
            Time ("live_session_flow" & Suffix, Bench_Live_Session_Flow'Access);
            Time ("static_warm_serve" & Suffix, Bench_Static_Serve'Access);
            Time ("static_cache_churn" & Suffix, Bench_Static_Cache_Churn'Access);
            Time ("compression_cache_hit" & Suffix, Bench_Compression_Cache'Access);
            Time ("compression_cache_miss" & Suffix, Bench_Compression_Cache_Miss'Access);

            loop
               Bench_Concurrent_HTTP_With
                 (Worker_Total,
                  "concurrent_http_dispatch_w" & Trimmed_Natural (Worker_Total) & Suffix);
               Bench_Concurrent_Live_WebSocket_With
                 (Worker_Total,
                  "concurrent_live_websocket_w" & Trimmed_Natural (Worker_Total) & Suffix);
               exit when Worker_Total >= Concurrent_Workers;
               Worker_Total := Positive'Min (Concurrent_Workers, Worker_Total * 2);
            end loop;
         end;
      end loop;
   end if;

   declare
      Socket_Count : constant Positive := Positive'Min (Repeat_Count, 1_000);
   begin
      Server_Port := Free_Port;
      declare
         Server : Benchmark_Server (Server_Port);
         pragma Unreferenced (Server);
      begin
         delay 0.10;
         Time_Count ("real_http_socket", Socket_Count, Bench_Real_HTTP'Access);
         Time_Count ("real_websocket_session", Socket_Count, Bench_Real_WebSocket'Access);
         Bench_Real_WebSocket_Persistent;
         Web.Server.Stop;
      end;
   exception
      when others =>
         Web.Server.Stop;
         raise;
   end;
end Benchmark;
