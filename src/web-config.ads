with Web.TLS;

package Web.Config is
   type Mode_Type is (Development, Production);

   type Config_Type is record
      Mode                  : Mode_Type := Development;
      Host                  : String (1 .. 256) := "127.0.0.1" & (10 .. 256 => ' ');
      Port                  : Natural := 8080;
      WebSocket_Path        : String (1 .. 128) := "/ws" & (4 .. 128 => ' ');
      Static_Url_Prefix     : String (1 .. 128) := "/static" & (8 .. 128 => ' ');
      Static_Directory      : String (1 .. 256) := "static" & (7 .. 256 => ' ');
      Allowed_Host          : String (1 .. 256) := "127.0.0.1" & (10 .. 256 => ' ');
      Use_X_Forwarded_For   : Boolean := False;
      Max_Request_Size      : Natural := 1_048_576;
      Max_WebSocket_Message : Natural := 65_536;
      Max_Connections       : Natural := 1_024;
      Enable_Compression    : Boolean := True;
      Compression_Min_Size  : Natural := 256;
      Compression_Level     : Natural := 6;
      Static_File_Buffer_Size : Natural := 65_536;
      Secure_Cookies        : Boolean := False;
      Session_Timeout       : Natural := 3_600;
      TLS_Certificate_File  : String (1 .. 256) := (others => ' ');
      TLS_Private_Key_File  : String (1 .. 256) := (others => ' ');
      TLS_CA_File           : String (1 .. 256) := (others => ' ');
      TLS_Cipher_List       : String (1 .. 256) := (others => ' ');
      TLS_Cipher_Suites     : String (1 .. 256) := (others => ' ');
      TLS_Minimum_Version   : Web.TLS.TLS_Version := Web.TLS.TLS_1_2;
      TLS_Maximum_Version   : Web.TLS.TLS_Version := Web.TLS.TLS_Default;
      TLS_Verify_Client     : Web.TLS.Client_Verification_Mode := Web.TLS.Verify_None;
   end record;

   --  Return the default framework configuration.
   --  @return Default configuration.
   function Default_Config return Config_Type;

   --  Build a TLS server configuration from framework config fields.
   --  @param Config Framework configuration.
   --  @return TLS server configuration.
   function TLS_Config (Config : Config_Type) return Web.TLS.Server_Config;

   --  Set the bind host field.
   --  @param Config Configuration to update.
   --  @param Value Bind host value.
   --  @return No return value.
   procedure Set_Host (Config : in out Config_Type; Value : String);

   --  Set the WebSocket path field.
   --  @param Config Configuration to update.
   --  @param Value WebSocket path value.
   --  @return No return value.
   procedure Set_WebSocket_Path (Config : in out Config_Type; Value : String);

   --  Set the static URL prefix field.
   --  @param Config Configuration to update.
   --  @param Value Static URL prefix value.
   --  @return No return value.
   procedure Set_Static_Url_Prefix (Config : in out Config_Type; Value : String);

   --  Set the static directory field.
   --  @param Config Configuration to update.
   --  @param Value Static directory value.
   --  @return No return value.
   procedure Set_Static_Directory (Config : in out Config_Type; Value : String);

   --  Set the allowed host or origin field.
   --  @param Config Configuration to update.
   --  @param Value Allowed host or origin value.
   --  @return No return value.
   procedure Set_Allowed_Host (Config : in out Config_Type; Value : String);

   --  Enable/disable client IP trust from `X-Forwarded-For`.
   --  @param Config Configuration to update.
   --  @param Enabled True to use `X-Forwarded-For`, False to use socket peer IP.
   --  @return No return value.
   procedure Set_Use_X_Forwarded_For (Config : in out Config_Type; Enabled : Boolean);

   --  Set the TLS certificate file field.
   --  @param Config Configuration to update.
   --  @param Value Certificate file path.
   --  @return No return value.
   procedure Set_TLS_Certificate_File (Config : in out Config_Type; Value : String);

   --  Set the TLS private key file field.
   --  @param Config Configuration to update.
   --  @param Value Private key file path.
   --  @return No return value.
   procedure Set_TLS_Private_Key_File (Config : in out Config_Type; Value : String);

   --  Set the TLS CA file field.
   --  @param Config Configuration to update.
   --  @param Value CA file path.
   --  @return No return value.
   procedure Set_TLS_CA_File (Config : in out Config_Type; Value : String);

   --  Set the TLS cipher list field.
   --  @param Config Configuration to update.
   --  @param Value TLS 1.2 cipher list.
   --  @return No return value.
   procedure Set_TLS_Cipher_List (Config : in out Config_Type; Value : String);

   --  Set the TLS cipher suites field.
   --  @param Config Configuration to update.
   --  @param Value TLS 1.3 cipher suites.
   --  @return No return value.
   procedure Set_TLS_Cipher_Suites (Config : in out Config_Type; Value : String);
end Web.Config;
