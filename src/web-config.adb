package body Web.Config is
   function Default_Config return Config_Type is
   begin
      return (others => <>);
   end Default_Config;

   function TLS_Config (Config : Config_Type) return Web.TLS.Server_Config is
   begin
      return Web.TLS.Configure_Server
        (Certificate_File => Config.TLS_Certificate_File,
         Private_Key_File => Config.TLS_Private_Key_File,
         CA_File          => Config.TLS_CA_File,
         Cipher_List      => Config.TLS_Cipher_List,
         Cipher_Suites    => Config.TLS_Cipher_Suites,
         Minimum_Version  => Config.TLS_Minimum_Version,
         Maximum_Version  => Config.TLS_Maximum_Version,
         Verify_Client    => Config.TLS_Verify_Client);
   end TLS_Config;
end Web.Config;
