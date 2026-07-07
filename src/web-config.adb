with Web.Errors;

package body Web.Config is
   procedure Put_Field
     (Target : out String;
      Value  : String)
   is
   begin
      if Value'Length > Target'Length then
         raise Web.Errors.Security_Error with "configuration value is too long";
      end if;

      Target := (others => ' ');
      if Value'Length > 0 then
         Target (Target'First .. Target'First + Value'Length - 1) := Value;
      end if;
   end Put_Field;

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

   procedure Set_Host (Config : in out Config_Type; Value : String) is
   begin
      Put_Field (Config.Host, Value);
   end Set_Host;

   procedure Set_WebSocket_Path (Config : in out Config_Type; Value : String) is
   begin
      Put_Field (Config.WebSocket_Path, Value);
   end Set_WebSocket_Path;

   procedure Set_Static_Url_Prefix (Config : in out Config_Type; Value : String) is
   begin
      Put_Field (Config.Static_Url_Prefix, Value);
   end Set_Static_Url_Prefix;

   procedure Set_Static_Directory (Config : in out Config_Type; Value : String) is
   begin
      Put_Field (Config.Static_Directory, Value);
   end Set_Static_Directory;

   procedure Set_Allowed_Host (Config : in out Config_Type; Value : String) is
   begin
      Put_Field (Config.Allowed_Host, Value);
   end Set_Allowed_Host;

   procedure Set_Use_X_Forwarded_For (Config : in out Config_Type; Enabled : Boolean) is
   begin
      Config.Use_X_Forwarded_For := Enabled;
   end Set_Use_X_Forwarded_For;

   procedure Set_TLS_Certificate_File (Config : in out Config_Type; Value : String) is
   begin
      Put_Field (Config.TLS_Certificate_File, Value);
   end Set_TLS_Certificate_File;

   procedure Set_TLS_Private_Key_File (Config : in out Config_Type; Value : String) is
   begin
      Put_Field (Config.TLS_Private_Key_File, Value);
   end Set_TLS_Private_Key_File;

   procedure Set_TLS_CA_File (Config : in out Config_Type; Value : String) is
   begin
      Put_Field (Config.TLS_CA_File, Value);
   end Set_TLS_CA_File;

   procedure Set_TLS_Cipher_List (Config : in out Config_Type; Value : String) is
   begin
      Put_Field (Config.TLS_Cipher_List, Value);
   end Set_TLS_Cipher_List;

   procedure Set_TLS_Cipher_Suites (Config : in out Config_Type; Value : String) is
   begin
      Put_Field (Config.TLS_Cipher_Suites, Value);
   end Set_TLS_Cipher_Suites;
end Web.Config;
