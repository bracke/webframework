with Ada.Streams;    use Ada.Streams;
with GNAT.Sockets;   use GNAT.Sockets;

package body App.Smtp_Catcher is

   CRLF : constant String := ASCII.CR & ASCII.LF;

   --  Bounds: a dev catcher, so cap everything to keep memory bounded even
   --  against a misbehaving client.
   Max_Line    : constant := 8 * 1024;
   Max_Message : constant := 256 * 1024;
   Max_Stored  : constant := 20;

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
            --  Ring: drop the oldest, keep the last Max_Stored.
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
   --  Long-lived state.
   ---------------------------------------------------------------------------
   Server_Sock : Socket_Type;
   Selector    : aliased Selector_Type;
   Started     : Boolean := False;

   ---------------------------------------------------------------------------
   --  Socket helpers.
   ---------------------------------------------------------------------------
   procedure Send_Reply (Sock : Socket_Type; Line : String) is
      Payload : Stream_Element_Array (1 .. Line'Length + 2);
      Last    : Stream_Element_Offset;
      Cursor  : Stream_Element_Offset := Payload'First;
   begin
      for C of Line loop
         Payload (Cursor) := Stream_Element (Character'Pos (C));
         Cursor := Cursor + 1;
      end loop;
      Payload (Cursor)     := Stream_Element (Character'Pos (ASCII.CR));
      Payload (Cursor + 1) := Stream_Element (Character'Pos (ASCII.LF));
      Send_Socket (Sock, Payload, Last);
   end Send_Reply;

   --  A tiny buffered line reader over one connection.
   type Line_Reader is record
      Sock    : Socket_Type;
      Pending : Unbounded_String;
      Closed  : Boolean := False;
   end record;

   --  Read one CRLF/LF-terminated line (without the terminator). Ok is False on
   --  a closed connection, a read error, or a line that exceeds Max_Line.
   procedure Read_Line (R : in out Line_Reader; Line : out Unbounded_String; Ok : out Boolean) is
      Chunk : Stream_Element_Array (1 .. 1024);
      Last  : Stream_Element_Offset;
      LF    : Natural;
   begin
      Line := Null_Unbounded_String;
      loop
         LF := Index (R.Pending, "" & ASCII.LF);
         if LF > 0 then
            declare
               Raw : constant String := Slice (R.Pending, 1, LF - 1);
               Rest_First : constant Natural := LF + 1;
               Rest_Last  : constant Natural := Length (R.Pending);
            begin
               --  Strip a trailing CR, if present.
               if Raw'Length > 0 and then Raw (Raw'Last) = ASCII.CR then
                  Line := To_Unbounded_String (Raw (Raw'First .. Raw'Last - 1));
               else
                  Line := To_Unbounded_String (Raw);
               end if;
               if Rest_First <= Rest_Last then
                  R.Pending := To_Unbounded_String (Slice (R.Pending, Rest_First, Rest_Last));
               else
                  R.Pending := Null_Unbounded_String;
               end if;
            end;
            Ok := True;
            return;
         end if;

         if Length (R.Pending) > Max_Line then
            Ok := False;         --  runaway line: give up on this connection
            return;
         end if;

         begin
            Receive_Socket (R.Sock, Chunk, Last);
         exception
            when others =>
               R.Closed := True;
               Ok := False;
               return;
         end;

         if Last < Chunk'First then
            --  Peer closed the connection.
            R.Closed := True;
            Ok := False;
            return;
         end if;

         declare
            S : String (1 .. Natural (Last));
         begin
            for I in 1 .. Last loop
               S (Natural (I)) := Character'Val (Natural (Chunk (I)));
            end loop;
            Append (R.Pending, S);
         end;
      end loop;
   end Read_Line;

   --  True when Line (case-insensitive on its first Word'Length octets) begins
   --  with the SMTP verb Word.
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

   --  Extract the address between the first '<' and '>' of an SMTP path command
   --  (MAIL FROM:<a@b> / RCPT TO:<a@b>); the whole argument if there are no
   --  angle brackets.
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

   ---------------------------------------------------------------------------
   --  DATA capture: read the message body until the CRLF "." CRLF terminator,
   --  un-dot-stuffing each line (a line that is "." ends the body; a line
   --  starting with "." has that one leading dot removed). Bounded.
   ---------------------------------------------------------------------------
   procedure Read_Message (R : in out Line_Reader; Raw : out Unbounded_String; Ok : out Boolean) is
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
         exit when Line = "." & "";              --  the lone "." terminator
         declare
            Text : constant String := To_String (Line);
         begin
            --  Un-dot-stuff: a data line beginning with '.' had a dot prepended.
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
   --  Serve one connection: speak enough SMTP for a single submission.
   ---------------------------------------------------------------------------
   procedure Handle (Sock : Socket_Type) is
      R        : Line_Reader := (Sock => Sock, others => <>);
      Line     : Unbounded_String;
      Got      : Boolean;
      Env_From : Unbounded_String := Null_Unbounded_String;
      Env_To   : Unbounded_String := Null_Unbounded_String;
   begin
      --  Fail fast rather than hang shutdown if a peer stalls mid-command.
      Set_Socket_Option
        (Sock, Socket_Level, (Name => Receive_Timeout, Timeout => 10.0));

      Send_Reply (Sock, "220 localhost example_app SMTP catcher ready");
      loop
         Read_Line (R, Line, Got);
         exit when not Got;

         if Starts_With (Line, "EHLO") or else Starts_With (Line, "HELO") then
            --  Advertise nothing fancy: plaintext, no AUTH/STARTTLS/PIPELINING.
            Send_Reply (Sock, "250 localhost at your service");
         elsif Starts_With (Line, "MAIL FROM") then
            Env_From := To_Unbounded_String (Path_Address (Line));
            Send_Reply (Sock, "250 2.1.0 Sender OK");
         elsif Starts_With (Line, "RCPT TO") then
            if Env_To = Null_Unbounded_String then
               Env_To := To_Unbounded_String (Path_Address (Line));
            end if;
            Send_Reply (Sock, "250 2.1.5 Recipient OK");
         elsif Starts_With (Line, "DATA") then
            Send_Reply (Sock, "354 End data with <CR><LF>.<CR><LF>");
            declare
               Raw : Unbounded_String;
               Ok  : Boolean;
            begin
               Read_Message (R, Raw, Ok);
               exit when not Ok;
               Mailbox.Add
                 ((Envelope_From => Env_From,
                   Envelope_To   => Env_To,
                   Raw_Message   => Raw));
               Send_Reply (Sock, "250 2.0.0 Ok: message captured");
            end;
         elsif Starts_With (Line, "RSET") then
            Env_From := Null_Unbounded_String;
            Env_To   := Null_Unbounded_String;
            Send_Reply (Sock, "250 2.0.0 OK");
         elsif Starts_With (Line, "NOOP") then
            Send_Reply (Sock, "250 2.0.0 OK");
         elsif Starts_With (Line, "QUIT") then
            Send_Reply (Sock, "221 2.0.0 Bye");
            exit;
         else
            Send_Reply (Sock, "250 2.0.0 OK");
         end if;
      end loop;
   exception
      when others =>
         null;  --  never let a connection fault escape the accept loop
   end Handle;

   ---------------------------------------------------------------------------
   --  Accept loop task. Gated on Startup so it does not run before Start has
   --  bound the listener; the terminate alternative lets it exit cleanly if the
   --  catcher is never started.
   ---------------------------------------------------------------------------
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
                  null;  --  accept/handle fault: keep serving
            end;
         end if;
      end loop;
   end Listener;

   ---------------------------------------------------------------------------
   --  Public API.
   ---------------------------------------------------------------------------
   procedure Start (Status : out Start_Status) is
      Address : Sock_Addr_Type;
   begin
      if Started then
         Status := Already_Started;
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
      Listener.Startup;   --  release the accept loop
      Status := Ready;
   end Start;

   procedure Stop is
   begin
      if not Started then
         return;
      end if;
      Life.Request_Stop;
      begin
         Abort_Selector (Selector);   --  wake the accept loop immediately
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
