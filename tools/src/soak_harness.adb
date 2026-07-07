with Ada.Command_Line;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.Sockets;
with Tool_Soak_Handlers;
with Web.Config;
with Web.Logging;
with Web.Server;

procedure Soak_Harness is
   use type Ada.Streams.Stream_Element_Offset;

   CRLF : constant String := Character'Val (13) & Character'Val (10);

   function Argument (Index : Positive; Default : String) return String is
   begin
      if Ada.Command_Line.Argument_Count >= Index then
         return Ada.Command_Line.Argument (Index);
      end if;

      return Default;
   end Argument;

   Client_Count : constant Positive := Positive'Value (Argument (1, "16"));
   Requests_Per_Client : constant Positive := Positive'Value (Argument (2, "100"));
   Expected_Total : constant Natural := Client_Count * Requests_Per_Client;

   protected Counters is
      procedure Add_Success;
      procedure Add_Failure;
      function Successes return Natural;
      function Failures return Natural;
   private
      Success_Count : Natural := 0;
      Failure_Count : Natural := 0;
   end Counters;

   protected Completion is
      procedure Mark_Done;
      entry Wait_All;
   private
      Done_Count : Natural := 0;
   end Completion;

   protected body Counters is
      procedure Add_Success is
      begin
         Success_Count := Success_Count + 1;
      end Add_Success;

      procedure Add_Failure is
      begin
         Failure_Count := Failure_Count + 1;
      end Add_Failure;

      function Successes return Natural is
      begin
         return Success_Count;
      end Successes;

      function Failures return Natural is
      begin
         return Failure_Count;
      end Failures;
   end Counters;

   protected body Completion is
      procedure Mark_Done is
      begin
         Done_Count := Done_Count + 1;
      end Mark_Done;

      entry Wait_All when Done_Count = Client_Count is
      begin
         null;
      end Wait_All;
   end Completion;

   task type Server_Task is
      entry Start (Port : Natural);
   end Server_Task;

   task body Server_Task is
      Server_Port : Natural;
   begin
      accept Start (Port : Natural) do
         Server_Port := Port;
      end Start;

      Web.Server.Run ("127.0.0.1", Server_Port);
   end Server_Task;

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

   function One_Request (Port : Natural) return Boolean is
      Socket  : GNAT.Sockets.Socket_Type;
      Address : GNAT.Sockets.Sock_Addr_Type;
      Request : constant String :=
        "GET /health HTTP/1.1" & CRLF
        & "Host: 127.0.0.1" & CRLF
        & "Connection: close" & CRLF
        & CRLF;
   begin
      Address.Addr := GNAT.Sockets.Inet_Addr ("127.0.0.1");
      Address.Port := GNAT.Sockets.Port_Type (Port);
      GNAT.Sockets.Create_Socket (Socket);
      GNAT.Sockets.Set_Socket_Option
        (Socket,
         GNAT.Sockets.Socket_Level,
         (Name    => GNAT.Sockets.Receive_Timeout,
          Timeout => 5.0));
      GNAT.Sockets.Connect_Socket (Socket, Address);
      Send_All (Socket, Request);

      declare
         Response : constant String := Read_Until_Close (Socket);
      begin
         GNAT.Sockets.Close_Socket (Socket);
         return Ada.Strings.Fixed.Index (Response, "HTTP/1.1 200") = Response'First
           and then Ada.Strings.Fixed.Index (Response, CRLF & CRLF & "ok") > 0;
      end;
   exception
      when others =>
         begin
            GNAT.Sockets.Close_Socket (Socket);
         exception
            when others =>
               null;
         end;

         return False;
   end One_Request;

   procedure Wait_For_Server (Port : Natural) is
   begin
      for Attempt in 1 .. 100 loop
         if One_Request (Port) then
            return;
         end if;

         delay 0.05;
      end loop;

      raise Program_Error with "server did not start";
   end Wait_For_Server;

   task type Client is
      entry Start (Port : Natural);
   end Client;

   task body Client is
      Server_Port : Natural;
   begin
      accept Start (Port : Natural) do
         Server_Port := Port;
      end Start;

      for Request_Index in 1 .. Requests_Per_Client loop
         if One_Request (Server_Port) then
            Counters.Add_Success;
         else
            Counters.Add_Failure;
         end if;
      end loop;

      Completion.Mark_Done;
   end Client;

   type Client_Access is access Client;
   Clients : array (1 .. Client_Count) of Client_Access;
   Server : Server_Task;
   Port   : constant Natural := Free_Port;
   Config : Web.Config.Config_Type := Web.Config.Default_Config;
begin
   Web.Logging.Set_Minimum_Level (Web.Logging.Warn_Level);
   Config.Max_Connections := Client_Count + 8;
   Web.Server.Stop;
   Web.Server.Configure (Config);
   Web.Server.Get ("/health", Tool_Soak_Handlers.Health'Access);
   Server.Start (Port);
   Wait_For_Server (Port);

   Ada.Text_IO.Put_Line
     ("soak start clients="
      & Positive'Image (Client_Count)
      & " requests_per_client="
      & Positive'Image (Requests_Per_Client)
      & " port="
      & Natural'Image (Port));

   for Index_Value in Clients'Range loop
      Clients (Index_Value) := new Client;
      Clients (Index_Value).Start (Port);
   end loop;

   Completion.Wait_All;

   Ada.Text_IO.Put_Line
     ("soak result success="
      & Natural'Image (Counters.Successes)
      & " failure="
      & Natural'Image (Counters.Failures)
      & " expected="
      & Natural'Image (Expected_Total));
   Ada.Text_IO.Put_Line ("soak server " & Web.Server.Configuration_Report);

   Web.Server.Stop;
   delay 0.10;

   if Counters.Failures > 0 or else Counters.Successes /= Expected_Total then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
exception
   when Constraint_Error =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "usage: soak_harness [clients] [requests-per-client]");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      Web.Server.Stop;
   when others =>
      Web.Server.Stop;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      raise;
end Soak_Harness;
