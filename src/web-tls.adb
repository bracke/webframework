with Ada.Unchecked_Conversion;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;

with SSL;
with SSL.Authentication;
with SSL.Blocking;
with SSL.Cipher_Suites;
with SSL.Clocks;
with SSL.Configurations;
with SSL.Connections;
with SSL.Credentials;
with SSL.Clients;
with SSL.Errors;
with SSL.Limits;
with SSL.Server_Names;
with SSL.Servers;
with SSL.Transports;
with SSL.Trust;
with SSL.Versions;

with Web.Errors;

--  TLS through `ssllib`, not OpenSSL.
--
--  This package used to be twenty-odd C bindings into libssl. It is now Ada
--  calling Ada: `ssllib` does the protocol and this does the socket, which is
--  the split `ssllib` is built for -- it performs no input or output of any
--  kind and is handed a transport instead.
--
--  What changed for callers is written down in the specification. The short
--  version is that a client cannot be told to skip verification any more,
--  because there is no longer anything to tell.
package body Web.TLS is
   use type Ada.Streams.Stream_Element_Offset;
   use type System.Address;

   ---------------------------------------------------------------------------
   --  The transport ssllib is handed
   ---------------------------------------------------------------------------

   type Socket_Transport is limited new SSL.Transports.Transport with record
      Peer   : GNAT.Sockets.Socket_Type := GNAT.Sockets.No_Socket;
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

   overriding function Description (Item : Socket_Transport) return String;

   overriding procedure Receive
     (Item   : in out Socket_Transport;
      Into   : out SSL.Byte_Array;
      Count  : out SSL.Byte_Index;
      Status : out SSL.Transports.Transport_Status)
   is
      Last : Ada.Streams.Stream_Element_Offset;
   begin
      Into := [others => 0];
      Count := 0;

      if Item.Closed then
         Status := SSL.Transports.End_Of_Stream;
         return;
      end if;

      GNAT.Sockets.Receive_Socket (Item.Peer, Into, Last);

      if Last < Into'First then
         --  A zero-length read on a stream socket is the peer having closed.
         Item.Closed := True;
         Status := SSL.Transports.End_Of_Stream;
         return;
      end if;

      Count := SSL.Byte_Index (Last - Into'First + 1);
      Status := SSL.Transports.Ok;
   exception
      when others =>
         Status := SSL.Transports.Failed;
   end Receive;

   overriding procedure Send
     (Item   : in out Socket_Transport;
      Data   : SSL.Byte_Array;
      Count  : out SSL.Byte_Index;
      Status : out SSL.Transports.Transport_Status)
   is
      Last : Ada.Streams.Stream_Element_Offset;
   begin
      Count := 0;

      if Item.Closed then
         Status := SSL.Transports.End_Of_Stream;
         return;
      end if;

      GNAT.Sockets.Send_Socket (Item.Peer, Data, Last);
      Count := SSL.Byte_Index (Last - Data'First + 1);
      Status := SSL.Transports.Ok;
   exception
      when others =>
         Status := SSL.Transports.Failed;
   end Send;

   overriding function Description (Item : Socket_Transport) return String is
     ("webframework socket" & (if Item.Closed then " (closed)" else ""));

   ---------------------------------------------------------------------------
   --  What a context and a connection actually are
   ---------------------------------------------------------------------------

   type Role_Kind is (Server_Role, Client_Role);

   type Context_State is limited record
      Role : Role_Kind := Server_Role;

      Anchors     : aliased SSL.Trust.Snapshot;
      Has_Anchors : Boolean := False;

      Credential     : aliased SSL.Credentials.Credential;
      Has_Credential : Boolean := False;

      Server_Policy : aliased SSL.Configurations.Server_Configuration;
      Client_Policy : aliased SSL.Configurations.Client_Configuration;

      Ready : Boolean := False;
   end record;

   type Context_Access is access Context_State;

   type Session_State is limited record
      Medium  : aliased Socket_Transport;
      Session : SSL.Connections.Connection;
      Open    : Boolean := False;
   end record;

   type Session_Access is access Session_State;

   procedure Free is new Ada.Unchecked_Deallocation (Context_State, Context_Access);
   procedure Free is new Ada.Unchecked_Deallocation (Session_State, Session_Access);

   function To_Context (Item : Context) return Context_Access;
   function To_Session (Handle : System.Address) return Session_Access;

   function To_Context (Item : Context) return Context_Access is
      function Convert is new
        Ada.Unchecked_Conversion (System.Address, Context_Access);
   begin
      return Convert (Item.Handle);
   end To_Context;

   function To_Session (Handle : System.Address) return Session_Access is
      function Convert is new
        Ada.Unchecked_Conversion (System.Address, Session_Access);
   begin
      return Convert (Handle);
   end To_Session;

   --  How long a handshake, a read or a write may take.
   --
   --  The old bridge inherited whatever the socket was set to, which was
   --  nothing: a peer that sent one octet and stopped held a worker for ever.
   --  A bound is better than none, and thirty seconds is long enough that no
   --  correct peer meets it.
   Operation_Timeout_MS : constant := 30_000;

   ---------------------------------------------------------------------------
   --  Reading files
   ---------------------------------------------------------------------------

   function Read_File (Path : String) return String;

   function Read_File (Path : String) return String is
      package Streams_IO renames Ada.Streams.Stream_IO;

      Handle : Streams_IO.File_Type;
      Result : Ada.Strings.Unbounded.Unbounded_String;
      Chunk  : Ada.Streams.Stream_Element_Array (1 .. 8_192);
      Last   : Ada.Streams.Stream_Element_Offset;
   begin
      Streams_IO.Open (Handle, Streams_IO.In_File, Path, Form => "shared=no");
      loop
         Streams_IO.Read (Handle, Chunk, Last);
         exit when Last < Chunk'First;
         declare
            Text : String (1 .. Natural (Last - Chunk'First + 1));
         begin
            for Index in Text'Range loop
               Text (Index) :=
                 Character'Val
                   (Natural (Chunk (Chunk'First
                                    + Ada.Streams.Stream_Element_Offset (Index - 1))));
            end loop;
            Ada.Strings.Unbounded.Append (Result, Text);
         end;
         exit when Last < Chunk'Last;
      end loop;
      Streams_IO.Close (Handle);
      return Ada.Strings.Unbounded.To_String (Result);
   exception
      when others =>
         if Streams_IO.Is_Open (Handle) then
            Streams_IO.Close (Handle);
         end if;
         return "";
   end Read_File;

   function Trimmed (Value : String) return String;

   function Trimmed (Value : String) return String is
      First : Positive := Value'First;
      Last  : Natural  := Value'Last;
   begin
      while First <= Last and then Value (First) = ' ' loop
         First := First + 1;
      end loop;
      while Last >= First and then Value (Last) = ' ' loop
         Last := Last - 1;
      end loop;
      return Value (First .. Last);
   end Trimmed;

   ---------------------------------------------------------------------------
   --  Cipher policy
   ---------------------------------------------------------------------------

   --  Translate an OpenSSL cipher name into this library's suite.
   --
   --  The two configuration fields are OpenSSL's spellings, because that is
   --  what they were written against. They are honoured rather than ignored: a
   --  field whose whole purpose is to *narrow* what a server accepts must not
   --  become a no-op, because the deployment that set it would then be running
   --  wider than it asked to. A name with no equivalent here fails the
   --  initialization instead, which is the same answer OpenSSL gives for a
   --  cipher string it cannot parse.
   function Suite_For_Name
     (Name  : String;
      Suite : out SSL.Cipher_Suites.Cipher_Suite) return Boolean;

   function Suite_For_Name
     (Name  : String;
      Suite : out SSL.Cipher_Suites.Cipher_Suite) return Boolean
   is
      package Suites renames SSL.Cipher_Suites;
   begin
      Suite := Suites.TLS_AES_128_GCM_SHA256;

      --  TLS 1.3, whose OpenSSL names are the RFC ones.
      if Name = "TLS_AES_128_GCM_SHA256" then
         Suite := Suites.TLS_AES_128_GCM_SHA256;
      elsif Name = "TLS_AES_256_GCM_SHA384" then
         Suite := Suites.TLS_AES_256_GCM_SHA384;
      elsif Name = "TLS_CHACHA20_POLY1305_SHA256" then
         Suite := Suites.TLS_CHACHA20_POLY1305_SHA256;

      --  TLS 1.2, whose OpenSSL names are its own. Only the six this library
      --  implements appear: ECDHE with an AEAD and nothing else.
      elsif Name = "ECDHE-ECDSA-AES128-GCM-SHA256" then
         Suite := Suites.TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256;
      elsif Name = "ECDHE-ECDSA-AES256-GCM-SHA384" then
         Suite := Suites.TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384;
      elsif Name = "ECDHE-RSA-AES128-GCM-SHA256" then
         Suite := Suites.TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256;
      elsif Name = "ECDHE-RSA-AES256-GCM-SHA384" then
         Suite := Suites.TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384;
      elsif Name = "ECDHE-ECDSA-CHACHA20-POLY1305" then
         Suite := Suites.TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256;
      elsif Name = "ECDHE-RSA-CHACHA20-POLY1305" then
         Suite := Suites.TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256;
      else
         return False;
      end if;

      return True;
   end Suite_For_Name;

   --  Add every suite named in an OpenSSL-style list to Into.
   --
   --  `Ok` is False when any name has no equivalent, because a partly honoured
   --  restriction is not a restriction.
   procedure Add_Named_Suites
     (Names : String;
      Into  : in out SSL.Cipher_Suites.Suite_List;
      Ok    : out Boolean);

   procedure Add_Named_Suites
     (Names : String;
      Into  : in out SSL.Cipher_Suites.Suite_List;
      Ok    : out Boolean)
   is
      First : Positive := Names'First;
      Suite : SSL.Cipher_Suites.Cipher_Suite;
      Added : Boolean;
   begin
      Ok := True;

      for Index in Names'First .. Names'Last + 1 loop
         if Index > Names'Last
           or else Names (Index) = ':'
           or else Names (Index) = ','
         then
            if Index > First then
               declare
                  One : constant String := Trimmed (Names (First .. Index - 1));
               begin
                  if One'Length > 0 then
                     if not Suite_For_Name (One, Suite) then
                        Ok := False;
                        return;
                     end if;
                     SSL.Cipher_Suites.Append (Into, Suite, Added);
                     if not Added then
                        Ok := False;
                        return;
                     end if;
                  end if;
               end;
            end if;
            First := Index + 1;
         end if;
      end loop;
   end Add_Named_Suites;

   ---------------------------------------------------------------------------
   --  Availability
   ---------------------------------------------------------------------------

   function Available return Boolean is
   begin
      return True;
   end Available;

   ---------------------------------------------------------------------------
   --  Configuration
   ---------------------------------------------------------------------------

   --  A configuration field is checked before it is stored, not when it is
   --  used.
   --
   --  A control byte in a file path is how a path becomes two paths, and a
   --  value longer than the field would be silently truncated into a different
   --  path. Both are refused where the caller can still see which field it
   --  was, rather than at a handshake three layers away.
   procedure Require_TLS_Text (Value : String; Name : String);

   procedure Require_TLS_Text (Value : String; Name : String) is
   begin
      for Ch of Value loop
         if Character'Pos (Ch) < 32 or else Character'Pos (Ch) = 127 then
            raise Web.Errors.Security_Error with "invalid TLS " & Name;
         end if;
      end loop;
   end Require_TLS_Text;

   procedure Put_Field (Target : out String; Value : String; Label : String);

   procedure Put_Field (Target : out String; Value : String; Label : String) is
   begin
      Require_TLS_Text (Value, Label);

      if Value'Length > Target'Length then
         raise Web.Errors.Security_Error with "TLS configuration value is too long";
      end if;

      Target := [others => ' '];
      if Value'Length > 0 then
         Target (Target'First .. Target'First + Value'Length - 1) := Value;
      end if;
   end Put_Field;

   function Configure_Server
     (Certificate_File : String;
      Private_Key_File : String;
      CA_File          : String := "";
      Cipher_List      : String := "";
      Cipher_Suites    : String := "";
      Minimum_Version  : TLS_Version := TLS_1_2;
      Maximum_Version  : TLS_Version := TLS_Default;
      Verify_Client    : Client_Verification_Mode := Verify_None)
      return Server_Config
   is
      Result : Server_Config;
   begin
      Put_Field (Result.Certificate_File, Certificate_File, "certificate file");
      Put_Field (Result.Private_Key_File, Private_Key_File, "private key file");
      Put_Field (Result.CA_File, CA_File, "ca file");
      Put_Field (Result.Cipher_List, Cipher_List, "cipher list");
      Put_Field (Result.Cipher_Suites, Cipher_Suites, "cipher suites");
      Result.Minimum_Version := Minimum_Version;
      Result.Maximum_Version := Maximum_Version;
      Result.Verify_Client := Verify_Client;
      return Result;
   end Configure_Server;

   ---------------------------------------------------------------------------
   --  Building a server context
   ---------------------------------------------------------------------------

   --  Every configuration failure is an exception with a message naming it.
   --
   --  That is this package's contract and it is what callers branch on: a
   --  server that could not load its key must say which of the several things
   --  went wrong, because the operator reading the log is the one who has to
   --  fix it.
   procedure Raise_TLS_Error (Message : String) with No_Return;

   procedure Raise_TLS_Error (Message : String) is
   begin
      raise Web.Errors.Security_Error with Message;
   end Raise_TLS_Error;

   procedure Build_Server (State : Context_Access; Config : Server_Config);

   procedure Build_Server (State : Context_Access; Config : Server_Config) is
      Builder : SSL.Configurations.Server_Builder;
      Error   : SSL.Errors.Error_Information;
      Ok      : Boolean;

      Certificate : constant String := Trimmed (Config.Certificate_File);
      Private_Key : constant String := Trimmed (Config.Private_Key_File);
      Anchors_At  : constant String := Trimmed (Config.CA_File);
   begin
      State.Ready := False;

      --  Policy first, files second.
      --
      --  Everything decidable from the configuration alone is decided before
      --  anything is read from disk: a configuration that contradicts itself
      --  is wrong whether or not the certificate exists, and reporting the
      --  missing file instead would send the operator after the wrong problem.
      if Certificate'Length = 0 or else Private_Key'Length = 0 then
         Raise_TLS_Error ("TLS certificate and private key are required");
      end if;

      if Config.Maximum_Version = TLS_1_2 and then Config.Minimum_Version = TLS_1_3 then
         Raise_TLS_Error ("TLS maximum version is below minimum version");
      end if;

      if Config.Verify_Client /= Verify_None and then Anchors_At'Length = 0 then
         Raise_TLS_Error ("TLS client verification requires a CA file");
      end if;

      --  A version range that includes TLS 1.2 asks for the restricted TLS 1.2
      --  profile as well; one that does not is TLS 1.3 alone.
      if Config.Minimum_Version = TLS_1_3 then
         SSL.Configurations.Secure_Server_Defaults (Builder);
      else
         SSL.Configurations.Modern_Compatibility_Server (Builder);
         if Config.Maximum_Version = TLS_1_2 then
            SSL.Configurations.Set_Versions
              (Builder, SSL.Versions.Only (SSL.Versions.TLS_1_2), Ok);
            if not Ok then
               Raise_TLS_Error ("TLS maximum protocol version rejected");
            end if;
         end if;
      end if;

      --  The cipher policy, when the caller stated one.
      --
      --  The two fields are separate knobs and are kept separate here, because
      --  that is what they mean in the library they were written against:
      --  `Cipher_Suites` restricts TLS 1.3 and `Cipher_List` restricts TLS 1.2,
      --  and setting one leaves the other alone. Merging them into a single
      --  list -- which is what this did at first -- narrows one version to
      --  nothing and makes the whole configuration unbuildable.
      --
      --  A field left empty keeps every suite this library has for that
      --  version, which is a short list on purpose: TLS 1.3's three, and
      --  TLS 1.2's six ECDHE-with-AEAD ones. There is nothing weaker to fall
      --  back to.
      declare
         package Suites renames SSL.Cipher_Suites;
         use type SSL.Versions.Protocol_Version;

         Chosen   : Suites.Suite_List;
         Listed   : constant String := Trimmed (Config.Cipher_List);
         Suited   : constant String := Trimmed (Config.Cipher_Suites);
         Honoured : Boolean;
         Added    : Boolean;

         --  Every suite of one version, in registry order.
         procedure Add_Defaults (For_Version : SSL.Versions.Protocol_Version);

         procedure Add_Defaults (For_Version : SSL.Versions.Protocol_Version) is
         begin
            for Suite in Suites.Cipher_Suite'Range loop
               if Suites.Version_Of (Suite) = For_Version then
                  Suites.Append (Chosen, Suite, Added);
               end if;
            end loop;
         end Add_Defaults;

         Serves_1_2 : constant Boolean := Config.Minimum_Version /= TLS_1_3;
         Serves_1_3 : constant Boolean := Config.Maximum_Version /= TLS_1_2;
      begin
         --  TLS 1.3 first: this library refuses a configuration that orders a
         --  TLS 1.2 suite ahead of a TLS 1.3 one, because a server preferring
         --  the older protocol is a server nobody meant to configure.
         if Serves_1_3 then
            if Suited'Length > 0 then
               Add_Named_Suites (Suited, Chosen, Honoured);
               if not Honoured then
                  Raise_TLS_Error ("TLS 1.3 cipher suites rejected");
               end if;
            else
               Add_Defaults (SSL.Versions.TLS_1_3);
            end if;
         end if;

         if Serves_1_2 then
            if Listed'Length > 0 then
               Add_Named_Suites (Listed, Chosen, Honoured);
               if not Honoured then
                  Raise_TLS_Error ("TLS cipher list rejected");
               end if;
            else
               Add_Defaults (SSL.Versions.TLS_1_2);
            end if;
         end if;

         if Suites.Length (Chosen) = 0 then
            Raise_TLS_Error ("TLS cipher list rejected");
         end if;

         SSL.Configurations.Set_Cipher_Suites (Builder, Chosen, Ok);
         if not Ok then
            Raise_TLS_Error ("TLS cipher list rejected");
         end if;
      end;

      --  Now the files.
      declare
         Certificate_PEM : constant String := Read_File (Certificate);
         Key_PEM         : constant String := Read_File (Private_Key);
      begin
         if Certificate_PEM'Length = 0 then
            Raise_TLS_Error ("TLS certificate file rejected");
         end if;
         if Key_PEM'Length = 0 then
            Raise_TLS_Error ("TLS private key file rejected");
         end if;

         SSL.Credentials.Load_PEM
           (State.Credential, Certificate_PEM, Key_PEM,
            SSL.Limits.Default_Limits, Error);
         if SSL.Errors.Is_Error (Error) then
            --  `ssllib` checks that the key belongs to the certificate as part
            --  of loading them, so a mismatch and an unusable key arrive here
            --  together. The message names the likelier of the two.
            Raise_TLS_Error ("TLS private key does not match certificate");
         end if;
         State.Has_Credential := True;
      end;

      SSL.Configurations.Add_Credential (Builder, State.Credential'Access, Ok);
      if not Ok then
         Raise_TLS_Error ("TLS certificate file rejected");
      end if;

      --  Client certificates, and the anchors to check them against. A server
      --  that asked for a certificate with nothing to validate it against
      --  would be asking for a decoration.
      if Config.Verify_Client /= Verify_None then
         declare
            Bundle : constant String := Read_File (Anchors_At);
         begin
            if Bundle'Length = 0 then
               Raise_TLS_Error ("TLS client verification CA file rejected");
            end if;

            SSL.Trust.Load_Explicit_Anchors
              (State.Anchors, Bundle, SSL.Clocks.Current_UTC,
               SSL.Limits.Default_Limits, Error);
            if SSL.Errors.Is_Error (Error) then
               Raise_TLS_Error ("TLS client verification CA file rejected");
            end if;
            State.Has_Anchors := True;
         end;

         SSL.Configurations.Set_Anchors (Builder, State.Anchors'Access, Ok);
         if not Ok then
            Raise_TLS_Error ("TLS client verification CA file rejected");
         end if;

         SSL.Configurations.Set_Client_Authentication
           (Builder,
            (case Config.Verify_Client is
                when Verify_If_Present => SSL.Authentication.Requested_Optional,
                when Verify_Required   => SSL.Authentication.Required,
                when others            => SSL.Authentication.Not_Requested));
      end if;

      SSL.Configurations.Build (Builder, State.Server_Policy, Error);
      if SSL.Errors.Is_Error (Error) then
         Raise_TLS_Error ("TLS initialization failed");
      end if;

      State.Role := Server_Role;
      State.Ready := True;
   end Build_Server;

   ---------------------------------------------------------------------------
   --  Contexts
   ---------------------------------------------------------------------------

   procedure Initialize_Server
     (Item             : in out Context;
      Certificate_File : String;
      Private_Key_File : String)
   is
   begin
      Initialize_Server
        (Item,
         Configure_Server
           (Certificate_File => Certificate_File,
            Private_Key_File => Private_Key_File));
   end Initialize_Server;

   procedure Initialize_Server
     (Item   : in out Context;
      Config : Server_Config)
   is
      function Convert is new
        Ada.Unchecked_Conversion (Context_Access, System.Address);

      State : constant Context_Access := new Context_State;
   begin
      Finalize (Item);

      begin
         Build_Server (State, Config);
      exception
         when others =>
            --  Freed before the exception leaves: a context that failed to
            --  build must not leak the credential it had already loaded.
            declare
               Doomed : Context_Access := State;
            begin
               SSL.Credentials.Wipe (Doomed.Credential);
               Free (Doomed);
            end;
            raise;
      end;

      if not State.Ready then
         --  A context that could not be built is not handed back half-made:
         --  the handle stays null and every use of it answers "no TLS", which
         --  is what the caller checks.
         declare
            Doomed : Context_Access := State;
         begin
            Free (Doomed);
         end;
         return;
      end if;

      Item.Handle := Convert (State);
   end Initialize_Server;

   procedure Reload_Server
     (Item   : in out Context;
      Config : Server_Config)
   is
   begin
      --  Replaced rather than mutated. An `ssllib` configuration is immutable
      --  after Build -- that is the point of it -- and connections already open
      --  keep the one they were made with, which is what a reload should mean.
      Initialize_Server (Item, Config);
   end Reload_Server;

   procedure Initialize_Client
     (Item          : in out Context;
      CA_File       : String;
      Expected_Name : String)
   is
      function Convert is new
        Ada.Unchecked_Conversion (Context_Access, System.Address);

      State   : constant Context_Access := new Context_State;
      Builder : SSL.Configurations.Client_Builder;
      Error   : SSL.Errors.Error_Information;
      Ok      : Boolean;

      Bundle : constant String := Read_File (CA_File);
   begin
      Finalize (Item);
      State.Role := Client_Role;

      if Bundle'Length > 0 then
         SSL.Trust.Load_Explicit_Anchors
           (State.Anchors, Bundle, SSL.Clocks.Current_UTC,
            SSL.Limits.Default_Limits, Error);

         if not SSL.Errors.Is_Error (Error) then
            State.Has_Anchors := True;

            SSL.Configurations.Modern_Compatibility_Client (Builder);
            SSL.Configurations.Set_Anchors (Builder, State.Anchors'Access, Ok);

            declare
               Name   : SSL.Server_Names.DNS_Name;
               Status : SSL.Server_Names.Name_Status;
               Where  : SSL.Server_Names.IP_Address;
            begin
               if SSL.Server_Names.Looks_Like_Address (Expected_Name) then
                  if SSL.Server_Names.Parse_Address (Expected_Name, Where) then
                     SSL.Configurations.Set_Expected_Address (Builder, Where, Ok);
                  else
                     Ok := False;
                  end if;
               else
                  SSL.Server_Names.Parse (Expected_Name, Name, Status);
                  if SSL.Server_Names.Is_Present (Name) then
                     SSL.Configurations.Set_Expected_Name (Builder, Name, Ok => Ok);
                  else
                     Ok := False;
                  end if;
               end if;
            end;

            if Ok then
               SSL.Configurations.Build (Builder, State.Client_Policy, Error);
               State.Ready := not SSL.Errors.Is_Error (Error);
            end if;
         end if;
      end if;

      if not State.Ready then
         declare
            Doomed : Context_Access := State;
         begin
            Free (Doomed);
         end;
         return;
      end if;

      Item.Handle := Convert (State);
   end Initialize_Client;

   procedure Initialize_Client_No_Verify (Item : in out Context) is
   begin
      --  Refused. See the specification: there is no way to build a client
      --  that verifies nothing, so this leaves the context unusable rather
      --  than building one that verifies less than the caller thinks.
      Finalize (Item);
   end Initialize_Client_No_Verify;

   ---------------------------------------------------------------------------
   --  Connections
   ---------------------------------------------------------------------------

   function Start_Session
     (Item   : Context;
      Socket : GNAT.Sockets.Socket_Type;
      Serve  : Boolean) return System.Address;

   function Start_Session
     (Item   : Context;
      Socket : GNAT.Sockets.Socket_Type;
      Serve  : Boolean) return System.Address
   is
      function Convert is new
        Ada.Unchecked_Conversion (Session_Access, System.Address);

      State : constant Context_Access := To_Context (Item);
      Error : SSL.Errors.Error_Information;
   begin
      if State = null or else not State.Ready then
         return System.Null_Address;
      end if;

      declare
         Session : Session_Access := new Session_State;
      begin
         Session.Medium.Peer := Socket;

         if Serve then
            SSL.Servers.Accept_Connection
              (Item   => Session.Session,
               Config => State.Server_Policy'Access,
               Medium => Session.Medium'Unchecked_Access,
               Now    => SSL.Clocks.Current_UTC,
               Error  => Error);
         else
            SSL.Clients.Connect
              (Item   => Session.Session,
               Config => State.Client_Policy'Access,
               Medium => Session.Medium'Unchecked_Access,
               Now    => SSL.Clocks.Current_UTC,
               Error  => Error);
         end if;

         if not SSL.Errors.Is_Error (Error) then
            SSL.Blocking.Handshake
              (Session.Session,
               SSL.Clocks.In_Milliseconds (Operation_Timeout_MS), Error);
         end if;

         if SSL.Errors.Is_Error (Error) then
            SSL.Connections.Wipe (Session.Session);
            Free (Session);
            return System.Null_Address;
         end if;

         Session.Open := True;
         return Convert (Session);
      end;
   end Start_Session;

   function Accept_Connection
     (Item   : Context;
      Socket : GNAT.Sockets.Socket_Type) return System.Address
   is
   begin
      return Start_Session (Item, Socket, Serve => True);
   end Accept_Connection;

   function Connect_Connection
     (Item   : Context;
      Socket : GNAT.Sockets.Socket_Type) return System.Address
   is
   begin
      return Start_Session (Item, Socket, Serve => False);
   end Connect_Connection;

   procedure Read
     (Handle : System.Address;
      Buffer : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset)
   is
      Session : constant Session_Access := To_Session (Handle);
      Error   : SSL.Errors.Error_Information;
      Taken   : SSL.Byte_Index;
   begin
      Buffer := [others => 0];
      Last := Buffer'First - 1;

      if Session = null or else not Session.Open or else Buffer'Length = 0 then
         return;
      end if;

      SSL.Blocking.Read_Some
        (Session.Session, Buffer, Taken,
         SSL.Clocks.In_Milliseconds (Operation_Timeout_MS), Error);

      if SSL.Errors.Is_Error (Error) or else Taken = 0 then
         --  End of stream and failure look the same to this interface, which
         --  reports both as "nothing was read". That is what it always did.
         return;
      end if;

      Last := Buffer'First + Ada.Streams.Stream_Element_Offset (Taken) - 1;
   end Read;

   procedure Write
     (Handle : System.Address;
      Buffer : Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset)
   is
      Session : constant Session_Access := To_Session (Handle);
      Error   : SSL.Errors.Error_Information;
   begin
      Last := Buffer'First - 1;

      if Session = null or else not Session.Open then
         return;
      end if;

      if Buffer'Length = 0 then
         Last := Buffer'Last;
         return;
      end if;

      SSL.Blocking.Write_All
        (Session.Session, Buffer,
         SSL.Clocks.In_Milliseconds (Operation_Timeout_MS), Error);

      if SSL.Errors.Is_Error (Error) then
         return;
      end if;

      Last := Buffer'Last;
   end Write;

   procedure Close (Handle : in out System.Address) is
      Session : Session_Access := To_Session (Handle);
   begin
      if Session = null then
         Handle := System.Null_Address;
         return;
      end if;

      if Session.Open then
         declare
            Closing : SSL.Errors.Error_Information;
         begin
            --  An orderly close_notify rather than a dropped socket. A peer
            --  that sees the stream end without one reports a truncation
            --  attack, correctly, and every stack this is tested against does.
            SSL.Blocking.Shutdown
              (Session.Session, SSL.Clocks.In_Milliseconds (2_000),
               Closing, Await_Peer => False);
         end;
      end if;

      SSL.Connections.Wipe (Session.Session);
      Free (Session);
      Handle := System.Null_Address;
   end Close;

   procedure Finalize (Item : in out Context) is
      State : Context_Access := To_Context (Item);
   begin
      if State /= null then
         SSL.Credentials.Wipe (State.Credential);
         Free (State);
      end if;
      Item.Handle := System.Null_Address;
   end Finalize;

end Web.TLS;
