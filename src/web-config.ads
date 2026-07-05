with Web.TLS;

package Web.Config is
   type Mode_Type is (Development, Production);

   type Config_Type is record
      Mode                  : Mode_Type := Development;
      Host                  : String (1 .. 9) := "127.0.0.1";
      Port                  : Natural := 8080;
      WebSocket_Path        : String (1 .. 3) := "/ws";
      Static_Url_Prefix     : String (1 .. 7) := "/static";
      Static_Directory      : String (1 .. 6) := "static";
      Allowed_Host          : String (1 .. 9) := "127.0.0.1";
      Max_Request_Size      : Natural := 1_048_576;
      Max_WebSocket_Message : Natural := 65_536;
      Enable_Compression    : Boolean := True;
      Compression_Min_Size  : Natural := 256;
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
end Web.Config;
