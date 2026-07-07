with Ada.Command_Line;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.Sockets;

procedure Stress_Harness is
   use Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Offset;

   CRLF : constant String := Character'Val (13) & Character'Val (10);

   function Argument (Index : Positive; Default : String) return String is
   begin
      if Ada.Command_Line.Argument_Count >= Index then
         return Ada.Command_Line.Argument (Index);
      end if;
      return Default;
   end Argument;

   Host : constant String := Argument (1, "127.0.0.1");
   Port : constant Natural := Natural'Value (Argument (2, "8080"));
   Path : constant String := Argument (3, "/health");
   Client_Count : constant Positive := Positive'Value (Argument (4, "8"));
   Requests_Per_Client : constant Positive := Positive'Value (Argument (5, "50"));

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
      Result : Unbounded_String;
   begin
      loop
         GNAT.Sockets.Receive_Socket (Socket, Buffer, Last);
         exit when Last < Buffer'First;
         Append (Result, Stream_To_String (Buffer, Last));
      end loop;
      return To_String (Result);
   exception
      when others =>
         return To_String (Result);
   end Read_Until_Close;

   function One_Request return Boolean is
      Socket  : GNAT.Sockets.Socket_Type;
      Address : GNAT.Sockets.Sock_Addr_Type;
      Request : constant String :=
        "GET " & Path & " HTTP/1.1" & CRLF
        & "Host: " & Host & CRLF
        & "Connection: close" & CRLF
        & CRLF;
   begin
      Address.Addr := GNAT.Sockets.Inet_Addr (Host);
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
         return Ada.Strings.Fixed.Index (Response, "HTTP/1.1 200") = Response'First;
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

   task type Client;

   task body Client is
   begin
      for Request_Index in 1 .. Requests_Per_Client loop
         if One_Request then
            Counters.Add_Success;
         else
            Counters.Add_Failure;
         end if;
      end loop;
      Completion.Mark_Done;
   end Client;

   type Client_Access is access Client;
   Clients : array (1 .. Client_Count) of Client_Access;
begin
   GNAT.Sockets.Initialize;
   for Index in Clients'Range loop
      Clients (Index) := new Client;
   end loop;

   Completion.Wait_All;
   Ada.Text_IO.Put_Line
     ("success="
      & Natural'Image (Counters.Successes)
      & " failure="
      & Natural'Image (Counters.Failures));

   if Counters.Failures > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
exception
   when Constraint_Error =>
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "usage: stress_harness [host] [port] [path] [clients] [requests-per-client]");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Stress_Harness;
