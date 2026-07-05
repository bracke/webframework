with Interfaces.C;
with Interfaces.C.Strings;
with Ada.Strings.Fixed;
with Web.Errors;

package body Web.TLS is
   package C renames Interfaces.C;
   package C_Strings renames Interfaces.C.Strings;
   use type Ada.Streams.Stream_Element_Offset;
   use type C.int;
   use type C.long;
   use type C.unsigned_long;
   use type C_Strings.chars_ptr;
   use type System.Address;

   SSL_Filetype_PEM : constant C.int := 1;
   SSL_Verify_None  : constant C.int := 0;
   SSL_Verify_Peer  : constant C.int := 1;
   SSL_Verify_Fail  : constant C.int := 2;
   SSL_Ctrl_Set_Min_Proto_Version : constant C.int := 123;
   SSL_Ctrl_Set_Max_Proto_Version : constant C.int := 124;
   TLS1_2_Version : constant C.long := 16#0303#;
   TLS1_3_Version : constant C.long := 16#0304#;

   function OpenSSL_Init_SSL
     (Options  : C.unsigned_long;
      Settings : System.Address) return C.int
   with Import, Convention => C, External_Name => "OPENSSL_init_ssl";

   function TLS_Server_Method return System.Address
   with Import, Convention => C, External_Name => "TLS_server_method";

   function TLS_Client_Method return System.Address
   with Import, Convention => C, External_Name => "TLS_client_method";

   function SSL_CTX_New (Method : System.Address) return System.Address
   with Import, Convention => C, External_Name => "SSL_CTX_new";

   procedure SSL_CTX_Free (Ctx : System.Address)
   with Import, Convention => C, External_Name => "SSL_CTX_free";

   procedure SSL_CTX_Set_Verify
     (Ctx         : System.Address;
      Verify_Mode : C.int;
      Callback    : System.Address)
   with Import, Convention => C, External_Name => "SSL_CTX_set_verify";

   function SSL_CTX_Ctrl
     (Ctx   : System.Address;
      Cmd   : C.int;
      LArg  : C.long;
      PArg  : System.Address) return C.long
   with Import, Convention => C, External_Name => "SSL_CTX_ctrl";

   function SSL_CTX_Set_Cipher_List
     (Ctx  : System.Address;
      Text : C_Strings.chars_ptr) return C.int
   with Import, Convention => C, External_Name => "SSL_CTX_set_cipher_list";

   function SSL_CTX_Set_Cipher_Suites
     (Ctx  : System.Address;
      Text : C_Strings.chars_ptr) return C.int
   with Import, Convention => C, External_Name => "SSL_CTX_set_ciphersuites";

   function SSL_CTX_Load_Verify_Locations
     (Ctx      : System.Address;
      CA_File  : C_Strings.chars_ptr;
      CA_Path  : System.Address) return C.int
   with Import, Convention => C, External_Name => "SSL_CTX_load_verify_locations";

   function SSL_CTX_Use_Certificate_File
     (Ctx       : System.Address;
      File_Name : C_Strings.chars_ptr;
      File_Type : C.int) return C.int
   with Import, Convention => C, External_Name => "SSL_CTX_use_certificate_file";

   function SSL_CTX_Use_Private_Key_File
     (Ctx       : System.Address;
      File_Name : C_Strings.chars_ptr;
      File_Type : C.int) return C.int
   with Import, Convention => C, External_Name => "SSL_CTX_use_PrivateKey_file";

   function SSL_CTX_Check_Private_Key (Ctx : System.Address) return C.int
   with Import, Convention => C, External_Name => "SSL_CTX_check_private_key";

   function SSL_New (Ctx : System.Address) return System.Address
   with Import, Convention => C, External_Name => "SSL_new";

   procedure SSL_Free (SSL : System.Address)
   with Import, Convention => C, External_Name => "SSL_free";

   function SSL_Set_FD
     (SSL : System.Address;
      FD  : C.int) return C.int
   with Import, Convention => C, External_Name => "SSL_set_fd";

   function SSL_Accept (SSL : System.Address) return C.int
   with Import, Convention => C, External_Name => "SSL_accept";

   function SSL_Connect (SSL : System.Address) return C.int
   with Import, Convention => C, External_Name => "SSL_connect";

   function SSL_Read
     (SSL    : System.Address;
      Buffer : System.Address;
      Length : C.int) return C.int
   with Import, Convention => C, External_Name => "SSL_read";

   function SSL_Write
     (SSL    : System.Address;
      Buffer : System.Address;
      Length : C.int) return C.int
   with Import, Convention => C, External_Name => "SSL_write";

   function SSL_Shutdown (SSL : System.Address) return C.int
   with Import, Convention => C, External_Name => "SSL_shutdown";

   function ERR_Get_Error return C.unsigned_long
   with Import, Convention => C, External_Name => "ERR_get_error";

   function ERR_Reason_Error_String
     (Error_Code : C.unsigned_long) return C_Strings.chars_ptr
   with Import, Convention => C, External_Name => "ERR_reason_error_string";

   function Clean (Value : String) return String is
   begin
      return Ada.Strings.Fixed.Trim (Value, Ada.Strings.Both);
   end Clean;

   procedure Require_TLS_Text (Value : String; Name : String) is
   begin
      for Ch of Value loop
         if Character'Pos (Ch) < 32 or else Character'Pos (Ch) = 127 then
            raise Web.Errors.Security_Error with "invalid TLS " & Name;
         end if;
      end loop;
   end Require_TLS_Text;

   procedure Put_Field
     (Target : out String;
      Value  : String;
      Name   : String) is
   begin
      Require_TLS_Text (Value, Name);

      if Value'Length > Target'Length then
         raise Web.Errors.Security_Error with "TLS configuration value is too long";
      end if;

      Target := (others => ' ');
      if Value'Length > 0 then
         Target (Target'First .. Target'First + Value'Length - 1) := Value;
      end if;
   end Put_Field;

   function Version_Code (Version : TLS_Version) return C.long is
   begin
      case Version is
         when TLS_Default =>
            return 0;
         when TLS_1_2 =>
            return TLS1_2_Version;
         when TLS_1_3 =>
            return TLS1_3_Version;
      end case;
   end Version_Code;

   function Verify_Mode (Mode : Client_Verification_Mode) return C.int is
   begin
      case Mode is
         when Verify_None =>
            return SSL_Verify_None;
         when Verify_If_Present =>
            return SSL_Verify_Peer;
         when Verify_Required =>
            return SSL_Verify_Peer + SSL_Verify_Fail;
      end case;
   end Verify_Mode;

   function OpenSSL_Error_Text return String is
      Error_Code : constant C.unsigned_long := ERR_Get_Error;
      Reason     : C_Strings.chars_ptr;
   begin
      if Error_Code = 0 then
         return "";
      end if;

      Reason := ERR_Reason_Error_String (Error_Code);
      if Reason = C_Strings.Null_Ptr then
         return "";
      end if;

      return C_Strings.Value (Reason);
   end OpenSSL_Error_Text;

   function Available return Boolean is
   begin
      return OpenSSL_Init_SSL (0, System.Null_Address) = 1;
   end Available;

   procedure Raise_TLS_Error (Message : String) is
      Details : constant String := OpenSSL_Error_Text;
   begin
      if Details'Length = 0 then
         raise Web.Errors.Security_Error with Message;
      else
         raise Web.Errors.Security_Error with Message & ": " & Details;
      end if;
   end Raise_TLS_Error;

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
      Put_Field (Result.Certificate_File, Certificate_File, "certificate path");
      Put_Field (Result.Private_Key_File, Private_Key_File, "private key path");
      Put_Field (Result.CA_File, CA_File, "CA path");
      Put_Field (Result.Cipher_List, Cipher_List, "cipher list");
      Put_Field (Result.Cipher_Suites, Cipher_Suites, "cipher suites");
      Result.Minimum_Version := Minimum_Version;
      Result.Maximum_Version := Maximum_Version;
      Result.Verify_Client := Verify_Client;
      return Result;
   end Configure_Server;

   procedure Apply_Server_Policy
     (Item   : in out Context;
      Config : Server_Config)
   is
      Cert_File : constant String := Clean (Config.Certificate_File);
      Key_File  : constant String := Clean (Config.Private_Key_File);
      CA_File   : constant String := Clean (Config.CA_File);
      Ciphers   : constant String := Clean (Config.Cipher_List);
      Suites    : constant String := Clean (Config.Cipher_Suites);
      Cert_Path : C_Strings.chars_ptr := C_Strings.New_String (Cert_File);
      Key_Path  : C_Strings.chars_ptr := C_Strings.New_String (Key_File);
      CA_Path   : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      Cipher_Text : C_Strings.chars_ptr := C_Strings.Null_Ptr;
      Suite_Text  : C_Strings.chars_ptr := C_Strings.Null_Ptr;
   begin
      if Cert_File'Length = 0 or else Key_File'Length = 0 then
         Raise_TLS_Error ("TLS certificate and private key are required");
      end if;

      if Config.Maximum_Version /= TLS_Default
        and then Version_Code (Config.Maximum_Version) < Version_Code (Config.Minimum_Version)
      then
         Raise_TLS_Error ("TLS maximum version is below minimum version");
      end if;

      if SSL_CTX_Ctrl
        (Item.Handle,
         SSL_Ctrl_Set_Min_Proto_Version,
         Version_Code (Config.Minimum_Version),
         System.Null_Address) /= 1
      then
         Raise_TLS_Error ("TLS minimum protocol version rejected");
      end if;

      if Config.Maximum_Version /= TLS_Default
        and then SSL_CTX_Ctrl
          (Item.Handle,
           SSL_Ctrl_Set_Max_Proto_Version,
           Version_Code (Config.Maximum_Version),
           System.Null_Address) /= 1
      then
         Raise_TLS_Error ("TLS maximum protocol version rejected");
      end if;

      if Ciphers'Length > 0 then
         Cipher_Text := C_Strings.New_String (Ciphers);
         if SSL_CTX_Set_Cipher_List (Item.Handle, Cipher_Text) /= 1 then
            Raise_TLS_Error ("TLS cipher list rejected");
         end if;
      end if;

      if Suites'Length > 0 then
         Suite_Text := C_Strings.New_String (Suites);
         if SSL_CTX_Set_Cipher_Suites (Item.Handle, Suite_Text) /= 1 then
            Raise_TLS_Error ("TLS 1.3 cipher suites rejected");
         end if;
      end if;

      if Config.Verify_Client /= Verify_None then
         if CA_File'Length = 0 then
            Raise_TLS_Error ("TLS client verification requires a CA file");
         end if;

         CA_Path := C_Strings.New_String (CA_File);
         if SSL_CTX_Load_Verify_Locations (Item.Handle, CA_Path, System.Null_Address) /= 1 then
            Raise_TLS_Error ("TLS client verification CA file rejected");
         end if;
      end if;

      SSL_CTX_Set_Verify (Item.Handle, Verify_Mode (Config.Verify_Client), System.Null_Address);

      if SSL_CTX_Use_Certificate_File (Item.Handle, Cert_Path, SSL_Filetype_PEM) /= 1 then
         Raise_TLS_Error ("TLS certificate file rejected");
      end if;

      if SSL_CTX_Use_Private_Key_File (Item.Handle, Key_Path, SSL_Filetype_PEM) /= 1 then
         Raise_TLS_Error ("TLS private key file rejected");
      end if;

      if SSL_CTX_Check_Private_Key (Item.Handle) /= 1 then
         Raise_TLS_Error ("TLS private key does not match certificate");
      end if;

      C_Strings.Free (Cert_Path);
      C_Strings.Free (Key_Path);
      C_Strings.Free (CA_Path);
      C_Strings.Free (Cipher_Text);
      C_Strings.Free (Suite_Text);
   exception
      when others =>
         C_Strings.Free (Cert_Path);
         C_Strings.Free (Key_Path);
         C_Strings.Free (CA_Path);
         C_Strings.Free (Cipher_Text);
         C_Strings.Free (Suite_Text);
         raise;
   end Apply_Server_Policy;

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
      Method    : constant System.Address := TLS_Server_Method;
   begin
      if not Available then
         Raise_TLS_Error ("TLS initialization failed");
      end if;

      Item.Handle := SSL_CTX_New (Method);
      if Item.Handle = System.Null_Address then
         Raise_TLS_Error ("TLS context allocation failed");
      end if;

      Apply_Server_Policy (Item, Config);
   exception
      when others =>
         Finalize (Item);
         raise;
   end Initialize_Server;

   procedure Reload_Server
     (Item   : in out Context;
      Config : Server_Config)
   is
      Replacement : Context;
   begin
      Initialize_Server (Replacement, Config);
      Finalize (Item);
      Item.Handle := Replacement.Handle;
      Replacement.Handle := System.Null_Address;
   end Reload_Server;

   procedure Initialize_Client_No_Verify (Item : in out Context) is
      Method : constant System.Address := TLS_Client_Method;
   begin
      if not Available then
         Raise_TLS_Error ("TLS initialization failed");
      end if;

      Item.Handle := SSL_CTX_New (Method);
      if Item.Handle = System.Null_Address then
         Raise_TLS_Error ("TLS client context allocation failed");
      end if;

      SSL_CTX_Set_Verify (Item.Handle, 0, System.Null_Address);
   exception
      when others =>
         Finalize (Item);
         raise;
   end Initialize_Client_No_Verify;

   function Accept_Connection
     (Item   : Context;
      Socket : GNAT.Sockets.Socket_Type) return System.Address
   is
      SSL : constant System.Address := SSL_New (Item.Handle);
   begin
      if Item.Handle = System.Null_Address then
         Raise_TLS_Error ("TLS context is not initialized");
      end if;

      if SSL = System.Null_Address then
         Raise_TLS_Error ("TLS connection allocation failed");
      end if;

      if SSL_Set_FD (SSL, C.int (GNAT.Sockets.To_C (Socket))) /= 1 then
         SSL_Free (SSL);
         Raise_TLS_Error ("TLS socket binding failed");
      end if;

      if SSL_Accept (SSL) /= 1 then
         SSL_Free (SSL);
         Raise_TLS_Error ("TLS handshake failed");
      end if;

      return SSL;
   end Accept_Connection;

   function Connect_Connection
     (Item   : Context;
      Socket : GNAT.Sockets.Socket_Type) return System.Address
   is
      SSL : constant System.Address := SSL_New (Item.Handle);
   begin
      if Item.Handle = System.Null_Address then
         Raise_TLS_Error ("TLS context is not initialized");
      end if;

      if SSL = System.Null_Address then
         Raise_TLS_Error ("TLS connection allocation failed");
      end if;

      if SSL_Set_FD (SSL, C.int (GNAT.Sockets.To_C (Socket))) /= 1 then
         SSL_Free (SSL);
         Raise_TLS_Error ("TLS socket binding failed");
      end if;

      if SSL_Connect (SSL) /= 1 then
         SSL_Free (SSL);
         Raise_TLS_Error ("TLS client handshake failed");
      end if;

      return SSL;
   end Connect_Connection;

   procedure Read
     (Handle : System.Address;
      Buffer : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset)
   is
      Count : C.int;
   begin
      Count := SSL_Read (Handle, Buffer'Address, C.int (Buffer'Length));
      if Count <= 0 then
         Last := Buffer'First - Ada.Streams.Stream_Element_Offset'(1);
      else
         Last := Buffer'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
      end if;
   end Read;

   procedure Write
     (Handle : System.Address;
      Buffer : Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset)
   is
      Count : C.int;
   begin
      Count := SSL_Write (Handle, Buffer'Address, C.int (Buffer'Length));
      if Count <= 0 then
         Last := Buffer'First - Ada.Streams.Stream_Element_Offset'(1);
      else
         Last := Buffer'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
      end if;
   end Write;

   procedure Close (Handle : in out System.Address) is
      Ignored : C.int;
   begin
      if Handle /= System.Null_Address then
         Ignored := SSL_Shutdown (Handle);
         pragma Unreferenced (Ignored);
         SSL_Free (Handle);
         Handle := System.Null_Address;
      end if;
   end Close;

   procedure Finalize (Item : in out Context) is
   begin
      if Item.Handle /= System.Null_Address then
         SSL_CTX_Free (Item.Handle);
         Item.Handle := System.Null_Address;
      end if;
   end Finalize;
end Web.TLS;
