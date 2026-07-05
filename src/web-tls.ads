with GNAT.Sockets;
with Ada.Streams;
with System;

package Web.TLS is
   type Context is limited private;
   type TLS_Version is
     (TLS_Default,
      TLS_1_2,
      TLS_1_3);

   type Client_Verification_Mode is
     (Verify_None,
      Verify_If_Present,
      Verify_Required);

   type Server_Config is record
      Certificate_File : String (1 .. 256) := (others => ' ');
      Private_Key_File : String (1 .. 256) := (others => ' ');
      CA_File          : String (1 .. 256) := (others => ' ');
      Cipher_List      : String (1 .. 256) := (others => ' ');
      Cipher_Suites    : String (1 .. 256) := (others => ' ');
      Minimum_Version  : TLS_Version := TLS_1_2;
      Maximum_Version  : TLS_Version := TLS_Default;
      Verify_Client    : Client_Verification_Mode := Verify_None;
   end record;

   --  Report whether OpenSSL TLS support is linked and can be initialized.
   --  @return True when TLS initialization succeeds.
   function Available return Boolean;

   --  Initialize a server TLS context from PEM certificate and key files.
   --  @param Item TLS context to initialize.
   --  @param Certificate_File PEM certificate file path.
   --  @param Private_Key_File PEM private-key file path.
   --  @return No return value.
   procedure Initialize_Server
     (Item             : in out Context;
      Certificate_File : String;
      Private_Key_File : String);

   --  Build a server TLS configuration.
   --  @param Certificate_File PEM certificate file path.
   --  @param Private_Key_File PEM private-key file path.
   --  @param CA_File PEM CA bundle for client certificate verification.
   --  @param Cipher_List TLS 1.2 and below cipher policy; empty keeps OpenSSL default.
   --  @param Cipher_Suites TLS 1.3 cipher policy; empty keeps OpenSSL default.
   --  @param Minimum_Version Minimum allowed TLS protocol version.
   --  @param Maximum_Version Maximum allowed TLS protocol version.
   --  @param Verify_Client Client certificate verification policy.
   --  @return Server TLS configuration.
   function Configure_Server
     (Certificate_File : String;
      Private_Key_File : String;
      CA_File          : String := "";
      Cipher_List      : String := "";
      Cipher_Suites    : String := "";
      Minimum_Version  : TLS_Version := TLS_1_2;
      Maximum_Version  : TLS_Version := TLS_Default;
      Verify_Client    : Client_Verification_Mode := Verify_None)
      return Server_Config;

   --  Initialize a server TLS context from a TLS configuration.
   --  @param Item TLS context to initialize.
   --  @param Config TLS server configuration.
   --  @return No return value.
   procedure Initialize_Server
     (Item   : in out Context;
      Config : Server_Config);

   --  Reload certificate, key, CA, and policy into an existing server context.
   --  @param Item TLS context to replace.
   --  @param Config New TLS server configuration.
   --  @return No return value.
   procedure Reload_Server
     (Item   : in out Context;
      Config : Server_Config);

   --  Initialize a client TLS context without peer verification.
   --  @param Item TLS context to initialize.
   --  @return No return value.
   procedure Initialize_Client_No_Verify (Item : in out Context);

   --  Accept a TLS handshake on an already accepted TCP socket.
   --  @param Item Initialized TLS context.
   --  @param Socket Accepted TCP socket.
   --  @return Opaque TLS connection handle.
   function Accept_Connection
     (Item   : Context;
      Socket : GNAT.Sockets.Socket_Type) return System.Address;

   --  Connect a TLS client handshake on an already connected TCP socket.
   --  @param Item Initialized client TLS context.
   --  @param Socket Connected TCP socket.
   --  @return Opaque TLS connection handle.
   function Connect_Connection
     (Item   : Context;
      Socket : GNAT.Sockets.Socket_Type) return System.Address;

   --  Read decrypted TLS bytes.
   --  @param Handle TLS connection handle.
   --  @param Buffer Destination buffer.
   --  @param Last Last written element, or before Buffer'First on close.
   --  @return No return value.
   procedure Read
     (Handle : System.Address;
      Buffer : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset);

   --  Write encrypted TLS bytes.
   --  @param Handle TLS connection handle.
   --  @param Buffer Source buffer.
   --  @param Last Last written element, or before Buffer'First on close.
   --  @return No return value.
   procedure Write
     (Handle : System.Address;
      Buffer : Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset);

   --  Close and free a TLS connection handle.
   --  @param Handle TLS connection handle.
   --  @return No return value.
   procedure Close (Handle : in out System.Address);

   --  Free a TLS context.
   --  @param Item TLS context to finalize.
   --  @return No return value.
   procedure Finalize (Item : in out Context);

private
   type Context is limited record
      Handle : System.Address := System.Null_Address;
   end record;
end Web.TLS;
