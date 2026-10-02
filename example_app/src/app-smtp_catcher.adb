with Ada.Streams;    use Ada.Streams;
with GNAT.Sockets;   use GNAT.Sockets;

with SSL;
with SSL.Blocking;
with SSL.Clocks;
with SSL.Configurations;
with SSL.Connections;
with SSL.Credentials;
with SSL.Errors;
with SSL.Limits;
with SSL.Servers;
with SSL.Transports;

with App.Tls_Fixture;

package body App.Smtp_Catcher is

   CRLF : constant String := ASCII.CR & ASCII.LF;

   --  Bounds: a dev catcher, so cap everything to keep memory bounded even
   --  against a misbehaving client.
   Max_Line    : constant := 8 * 1024;
   Max_Message : constant := 256 * 1024;
   Max_Stored  : constant := 20;

   --  How long any single blocking TLS operation may take.
   Io_Deadline : constant := 10_000;   --  milliseconds

   ---------------------------------------------------------------------------
   --  Captured-mail store (protected: the accept task writes, request handlers
   --  and the test read concurrently).
   ---------------------------------------------------------------------------
   type Mail_Array is array (1 .. Max_Stored) of Captured_Mail;

   protected Mailbox is
      procedure Add (Mail : Captured_Mail);
      function  Size return Natural;
      procedure Fetch (Index : Positive; Mail : out Captured_Mail; Found : out Boolean);
   private
      Items : Mail_Array;
      Used  : Natural := 0;
   end Mailbox;

   protected body Mailbox is
      procedure Add (Mail : Captured_Mail) is
      begin
         if Used < Max_Stored then
            Used := Used + 1;
            Items (Used) := Mail;
         else
            for I in 1 .. Max_Stored - 1 loop
               Items (I) := Items (I + 1);
            end loop;
            Items (Max_Stored) := Mail;
         end if;
      end Add;

      function Size return Natural is (Used);

      procedure Fetch (Index : Positive; Mail : out Captured_Mail; Found : out Boolean) is
      begin
         if Index <= Used then
            Mail  := Items (Index);
            Found := True;
         else
            Mail  := (others => Null_Unbounded_String);
            Found := False;
         end if;
      end Fetch;
   end Mailbox;

   ---------------------------------------------------------------------------
   --  Lifecycle flag (protected: written by Stop, read by the accept task).
   ---------------------------------------------------------------------------
   protected Life is
      procedure Request_Stop;
      function  Stopping return Boolean;
   private
      Stop_Flag : Boolean := False;
   end Life;

   protected body Life is
      procedure Request_Stop is
      begin
         Stop_Flag := True;
      end Request_Stop;
      function Stopping return Boolean is (Stop_Flag);
   end Life;

   ---------------------------------------------------------------------------
   --  TLS server state (library level: a configuration holds references to its
   --  credential, and connections hold one to the configuration, so both must
   --  outlive every connection -- Ada's accessibility rules enforce it).
   ---------------------------------------------------------------------------
   Credential   : aliased SSL.Credentials.Credential;
   Server_Setup : aliased SSL.Configurations.Server_Configuration;
   Tls_Ready    : Boolean := False;

   ---------------------------------------------------------------------------
   --  A transport that drives ssllib over one accepted GNAT.Sockets stream.
   ---------------------------------------------------------------------------
   type Socket_Transport is limited new SSL.Transports.Transport with record
      Peer   : Socket_Type := No_Socket;
      Closed : Boolean := False;
   end record;

   overriding procedure Receive
     (Item   : in out Socket_Transport;
      Into   : out SSL.Byte_Array;
      Count  : out SSL.Byte_Index;
      Status : out SSL.Transports.Transport_Status);

   overriding procedure Send
     (Item   : in out Socket_Transport;
      Data   : SSL.Byte_Array;
      Count  : out SSL.Byte_Index;
      Status : out SSL.Transports.Transport_Status);

   overriding function Description (Item : Socket_Transport) return String is
     ("loopback socket");

   overriding procedure Receive
     (Item   : in out Socket_Transport;
      Into   : out SSL.Byte_Array;
      Count  : out SSL.Byte_Index;
      Status : out SSL.Transports.Transport_Status)
   is
      Last : Stream_Element_Offset;
   begin
      Count := 0;
      if Item.Closed then
         Status := SSL.Transports.End_Of_Stream;
         return;
      end if;
      Receive_Socket (Item.Peer, Into, Last);
      if Last < Into'First then
         Item.Closed := True;
         Status := SSL.Transports.End_Of_Stream;
         return;
      end if;
      Count  := SSL.Byte_Index (Last - Into'First + 1);
      Status := SSL.Transports.Ok;
   exception
      when Socket_Error =>
         Status := SSL.Transports.Failed;
   end Receive;

   overriding procedure Send
     (Item   : in out Socket_Transport;
      Data   : SSL.Byte_Array;
      Count  : out SSL.Byte_Index;
      Status : out SSL.Transports.Transport_Status)
   is
      Last : Stream_Element_Offset;
   begin
      Count := 0;
      if Item.Closed then
         Status := SSL.Transports.End_Of_Stream;
         return;
      end if;
      Send_Socket (Item.Peer, Data, Last);
      Count  := SSL.Byte_Index (Last - Data'First + 1);
      Status := SSL.Transports.Ok;
   exception
      when Socket_Error =>
         Status := SSL.Transports.Failed;
   end Send;

   ---------------------------------------------------------------------------
   --  SMTP I/O over the encrypted connection.
   ---------------------------------------------------------------------------
   procedure Send_Reply
     (Conn : in out SSL.Connections.Connection; Line : String; Ok : out Boolean)
   is
      Payload : SSL.Byte_Array (1 .. SSL.Byte_Index (Line'Length + 2));
      Err     : SSL.Errors.Error_Information;
      Cursor  : SSL.Byte_Index := Payload'First;
   begin
      for C of Line loop
         Payload (Cursor) := SSL.Byte (Character'Pos (C));
         Cursor := Cursor + 1;
      end loop;
      Payload (Cursor)     := SSL.Byte (Character'Pos (ASCII.CR));
      Payload (Cursor + 1) := SSL.Byte (Character'Pos (ASCII.LF));
      SSL.Blocking.Write_All
        (Conn, Payload, SSL.Clocks.In_Milliseconds (Io_Deadline), Err);
      Ok := not SSL.Errors.Is_Error (Err);
   end Send_Reply;

   --  A buffered line reader over one encrypted connection.
   type Line_Reader (Conn : access SSL.Connections.Connection) is limited record
      Pending : Unbounded_String;
      Closed  : Boolean := False;
   end record;

   procedure Read_Line
     (R : in out Line_Reader; Line : out Unbounded_String; Ok : out Boolean)
   is
      Chunk : SSL.Byte_Array (1 .. 1024);
      Count : SSL.Byte_Index;
      Err   : SSL.Errors.Error_Information;
      LF    : Natural;
   begin
      Line := Null_Unbounded_String;
      loop
         LF := Index (R.Pending, "" & ASCII.LF);
         if LF > 0 then
            declare
               Raw        : constant String := Slice (R.Pending, 1, LF - 1);
               Rest_First : constant Natural := LF + 1;
               Rest_Last  : constant Natural := Length (R.Pending);
            begin
               if Raw'Length > 0 and then Raw (Raw'Last) = ASCII.CR then
                  Line := To_Unbounded_String (Raw (Raw'First .. Raw'Last - 1));
               else
                  Line := To_Unbounded_String (Raw);
               end if;
               if Rest_First <= Rest_Last then
                  R.Pending :=
                    To_Unbounded_String (Slice (R.Pending, Rest_First, Rest_Last));
               else
                  R.Pending := Null_Unbounded_String;
               end if;
            end;
            Ok := True;
            return;
         end if;

         if Length (R.Pending) > Max_Line then
            Ok := False;
            return;
         end if;

         SSL.Blocking.Read_Some
           (R.Conn.all, Chunk, Count,
            SSL.Clocks.In_Milliseconds (Io_Deadline), Err);
         if SSL.Errors.Is_Error (Err) or else Count = 0 then
            R.Closed := True;
            Ok := False;
            return;
         end if;

         declare
            S : String (1 .. Natural (Count));
         begin
            for I in 1 .. Count loop
               S (Natural (I)) := Character'Val (Natural (Chunk (I)));
            end loop;
            Append (R.Pending, S);
         end;
      end loop;
   end Read_Line;

   function Starts_With (Line : Unbounded_String; Word : String) return Boolean is
      L : constant String := To_String (Line);
      function Up (C : Character) return Character is
        (if C in 'a' .. 'z' then Character'Val (Character'Pos (C) - 32) else C);
   begin
      if L'Length < Word'Length then
         return False;
      end if;
      for I in Word'Range loop
         if Up (L (L'First + (I - Word'First))) /= Up (Word (I)) then
            return False;
         end if;
      end loop;
      return True;
   end Starts_With;

   function Path_Address (Line : Unbounded_String) return String is
      L  : constant String := To_String (Line);
      LB : constant Natural := Index (Line, "<");
      RB : constant Natural := Index (Line, ">");
   begin
      if LB > 0 and then RB > LB then
         return L (L'First + LB .. L'First + RB - 2);
      end if;
      declare
         Colon : constant Natural := Index (Line, ":");
      begin
         if Colon > 0 and then Colon < L'Length then
            return L (L'First + Colon .. L'Last);
         end if;
      end;
      return "";
   end Path_Address;

   procedure Read_Message
     (R : in out Line_Reader; Raw : out Unbounded_String; Ok : out Boolean)
   is
      Line : Unbounded_String;
      Got  : Boolean;
   begin
      Raw := Null_Unbounded_String;
      loop
         Read_Line (R, Line, Got);
         if not Got then
            Ok := False;
            return;
         end if;
         exit when Line = "." & "";
         declare
            Text : constant String := To_String (Line);
         begin
            if Text'Length >= 1 and then Text (Text'First) = '.' then
               if Length (Raw) < Max_Message then
                  Append (Raw, Text (Text'First + 1 .. Text'Last) & CRLF);
               end if;
            else
               if Length (Raw) < Max_Message then
                  Append (Raw, Text & CRLF);
               end if;
            end if;
         end;
      end loop;
      Ok := True;
   end Read_Message;

   ---------------------------------------------------------------------------
   --  The SMTP dialogue over an established TLS connection.
   ---------------------------------------------------------------------------
   procedure Serve (Conn : aliased in out SSL.Connections.Connection) is
      R        : Line_Reader (Conn'Access);
      Line     : Unbounded_String;
      Got, Ok  : Boolean;
      Env_From : Unbounded_String := Null_Unbounded_String;
      Env_To   : Unbounded_String := Null_Unbounded_String;
   begin
      Send_Reply (Conn, "220 localhost example_app SMTP catcher ready", Ok);
      loop
         Read_Line (R, Line, Got);
         exit when not Got;

         if Starts_With (Line, "EHLO") or else Starts_With (Line, "HELO") then
            Send_Reply (Conn, "250 localhost at your service", Ok);
         elsif Starts_With (Line, "MAIL FROM") then
            Env_From := To_Unbounded_String (Path_Address (Line));
            Send_Reply (Conn, "250 2.1.0 Sender OK", Ok);
         elsif Starts_With (Line, "RCPT TO") then
            if Env_To = Null_Unbounded_String then
               Env_To := To_Unbounded_String (Path_Address (Line));
            end if;
            Send_Reply (Conn, "250 2.1.5 Recipient OK", Ok);
         elsif Starts_With (Line, "DATA") then
            Send_Reply (Conn, "354 End data with <CR><LF>.<CR><LF>", Ok);
            declare
               Raw     : Unbounded_String;
               Data_Ok : Boolean;
            begin
               Read_Message (R, Raw, Data_Ok);
               exit when not Data_Ok;
               Mailbox.Add
                 ((Envelope_From => Env_From,
                   Envelope_To   => Env_To,
                   Raw_Message   => Raw));
               Send_Reply (Conn, "250 2.0.0 Ok: message captured", Ok);
            end;
         elsif Starts_With (Line, "RSET") then
            Env_From := Null_Unbounded_String;
            Env_To   := Null_Unbounded_String;
            Send_Reply (Conn, "250 2.0.0 OK", Ok);
         elsif Starts_With (Line, "NOOP") then
            Send_Reply (Conn, "250 2.0.0 OK", Ok);
         elsif Starts_With (Line, "QUIT") then
            Send_Reply (Conn, "221 2.0.0 Bye", Ok);
            exit;
         else
            Send_Reply (Conn, "250 2.0.0 OK", Ok);
         end if;
      end loop;
   end Serve;

   ---------------------------------------------------------------------------
   --  Handle one accepted socket: TLS handshake, then the SMTP dialogue.
   ---------------------------------------------------------------------------
   procedure Handle (Sock : Socket_Type) is
      Transport : aliased Socket_Transport := (Peer => Sock, Closed => False);
      Conn      : aliased SSL.Connections.Connection;
      Error     : SSL.Errors.Error_Information;
   begin
      Set_Socket_Option
        (Sock, Socket_Level, (Name => Receive_Timeout, Timeout => 10.0));

      SSL.Servers.Accept_Connection
        (Item   => Conn,
         Config => Server_Setup'Access,
         Medium => Transport'Unchecked_Access,
         Now    => SSL.Clocks.Current_UTC,
         Error  => Error);
      if not SSL.Errors.Is_Error (Error) then
         SSL.Blocking.Handshake
           (Conn, SSL.Clocks.In_Milliseconds (Io_Deadline), Error);
      end if;

      if not SSL.Errors.Is_Error (Error) then
         Serve (Conn);
         declare
            Closing : SSL.Errors.Error_Information;
         begin
            SSL.Blocking.Shutdown
              (Conn, SSL.Clocks.In_Milliseconds (5_000), Closing,
               Await_Peer => False);
         end;
      end if;

      SSL.Connections.Wipe (Conn);
   exception
      when others =>
         begin
            SSL.Connections.Wipe (Conn);
         exception
            when others => null;
         end;
   end Handle;

   ---------------------------------------------------------------------------
   --  Long-lived listener state.
   ---------------------------------------------------------------------------
   Server_Sock : Socket_Type;
   Selector    : aliased Selector_Type;
   Started     : Boolean := False;

   task Listener is
      entry Startup;
   end Listener;

   task body Listener is
      R_Set : Socket_Set_Type;
      W_Set : Socket_Set_Type;
      Stat  : Selector_Status;
      Conn  : Socket_Type;
      Peer  : Sock_Addr_Type;
   begin
      select
         accept Startup;
      or
         terminate;
      end select;

      loop
         exit when Life.Stopping;
         Empty (R_Set);
         Empty (W_Set);
         Set (R_Set, Server_Sock);
         begin
            Check_Selector (Selector, R_Set, W_Set, Stat, Timeout => 0.5);
         exception
            when others =>
               exit;
         end;
         exit when Life.Stopping;
         if Stat = Completed and then Is_Set (R_Set, Server_Sock) then
            begin
               Accept_Socket (Server_Sock, Conn, Peer);
               Handle (Conn);
               Close_Socket (Conn);
            exception
               when others =>
                  null;
            end;
         end if;
      end loop;
   end Listener;

   ---------------------------------------------------------------------------
   --  Build the TLS server configuration from the test fixture.
   ---------------------------------------------------------------------------
   procedure Setup_Tls (Ok : out Boolean) is
      Builder : SSL.Configurations.Server_Builder;
      Error   : SSL.Errors.Error_Information;
      Added   : Boolean;
   begin
      if Tls_Ready then
         Ok := True;
         return;
      end if;
      SSL.Credentials.Load_PEM
        (Credential, App.Tls_Fixture.Certificate_PEM,
         App.Tls_Fixture.Private_Key_PEM, SSL.Limits.Default_Limits, Error);
      if SSL.Errors.Is_Error (Error) then
         Ok := False;
         return;
      end if;
      SSL.Configurations.Secure_Server_Defaults (Builder);
      SSL.Configurations.Add_Credential (Builder, Credential'Access, Added);
      if not Added then
         Ok := False;
         return;
      end if;
      SSL.Configurations.Build (Builder, Server_Setup, Error);
      if SSL.Errors.Is_Error (Error) then
         Ok := False;
         return;
      end if;
      Tls_Ready := True;
      Ok := True;
   end Setup_Tls;

   ---------------------------------------------------------------------------
   --  Public API.
   ---------------------------------------------------------------------------
   procedure Start (Status : out Start_Status) is
      Address : Sock_Addr_Type;
      Tls_Ok  : Boolean;
   begin
      if Started then
         Status := Already_Started;
         return;
      end if;
      Setup_Tls (Tls_Ok);
      if not Tls_Ok then
         Status := Bind_Error;
         return;
      end if;
      begin
         Create_Selector (Selector);
         Create_Socket (Server_Sock, Family_Inet, Socket_Stream);
         Set_Socket_Option
           (Server_Sock, Socket_Level, (Name => Reuse_Address, Enabled => True));
         Address :=
           (Family => Family_Inet,
            Addr   => Inet_Addr ("127.0.0.1"),
            Port   => Port_Type (Listen_Port));
         Bind_Socket (Server_Sock, Address);
         Listen_Socket (Server_Sock, 8);
      exception
         when others =>
            Status := Bind_Error;
            return;
      end;
      Started := True;
      Listener.Startup;
      Status := Ready;
   end Start;

   procedure Stop is
   begin
      if not Started then
         return;
      end if;
      Life.Request_Stop;
      begin
         Abort_Selector (Selector);
      exception
         when others => null;
      end;
      begin
         Close_Socket (Server_Sock);
      exception
         when others => null;
      end;
      begin
         Close_Selector (Selector);
      exception
         when others => null;
      end;
      Started := False;
   end Stop;

   function Port return Positive is (Listen_Port);

   function Count return Natural is (Mailbox.Size);

   procedure Get (Index : Positive; Mail : out Captured_Mail; Found : out Boolean) is
   begin
      Mailbox.Fetch (Index, Mail, Found);
   end Get;

end App.Smtp_Catcher;
