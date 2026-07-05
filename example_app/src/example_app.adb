with Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with App.Counter;
with App.Database;
with App.Dispatcher;
with App.Live;
with App.Pages;
with App.Profile;
with App.Todo;
with Web.Config;
with Web.Server;

procedure Example_App is
   use Ada.Strings.Unbounded;

   type Settings_Type is record
      Host            : Unbounded_String := To_Unbounded_String ("127.0.0.1");
      Port            : Natural := 8080;
      TLS_Enabled     : Boolean := False;
      Production      : Boolean := False;
      Secure_Cookies  : Boolean := False;
      Help_Only       : Boolean := False;
      Session_Timeout : Natural := 3_600;
      Certificate     : Unbounded_String;
      Private_Key     : Unbounded_String;
   end record;

   procedure Usage is
   begin
      Ada.Text_IO.Put_Line ("usage: example_app [PORT] [options]");
      Ada.Text_IO.Put_Line ("  --host HOST");
      Ada.Text_IO.Put_Line ("  --port PORT");
      Ada.Text_IO.Put_Line ("  --production");
      Ada.Text_IO.Put_Line ("  --secure-cookies");
      Ada.Text_IO.Put_Line ("  --session-timeout SECONDS");
      Ada.Text_IO.Put_Line ("  --tls --cert CERT.pem --key KEY.pem");
   end Usage;

   function Static_Directory return String is
   begin
      if Ada.Directories.Exists ("example_app/static") then
         return "example_app/static";
      end if;

      return "static";
   end Static_Directory;

   procedure Put_Field
     (Target : out String;
      Value  : String) is
   begin
      if Value'Length > Target'Length then
         raise Constraint_Error with "configuration value is too long";
      end if;

      Target := (others => ' ');
      if Value'Length > 0 then
         Target (Target'First .. Target'First + Value'Length - 1) := Value;
      end if;
   end Put_Field;

   function Parse_Settings return Settings_Type is
      Result : Settings_Type;
      Index  : Positive := 1;

      function Has_Value return Boolean is
      begin
         return Index < Ada.Command_Line.Argument_Count;
      end Has_Value;

      function Next_Value (Option : String) return String is
      begin
         if not Has_Value then
            raise Constraint_Error with Option & " requires a value";
         end if;

         Index := Index + 1;
         return Ada.Command_Line.Argument (Index);
      end Next_Value;
   begin
      while Index <= Ada.Command_Line.Argument_Count loop
         declare
            Argument : constant String := Ada.Command_Line.Argument (Index);
         begin
            if Argument = "--help" then
               Usage;
               Result.Help_Only := True;
               return Result;
            elsif Argument = "--host" then
               Result.Host := To_Unbounded_String (Next_Value (Argument));
            elsif Argument = "--port" then
               Result.Port := Natural'Value (Next_Value (Argument));
            elsif Argument = "--production" then
               Result.Production := True;
            elsif Argument = "--secure-cookies" then
               Result.Secure_Cookies := True;
            elsif Argument = "--session-timeout" then
               Result.Session_Timeout := Natural'Value (Next_Value (Argument));
            elsif Argument = "--tls" then
               Result.TLS_Enabled := True;
            elsif Argument = "--cert" then
               Result.Certificate := To_Unbounded_String (Next_Value (Argument));
            elsif Argument = "--key" then
               Result.Private_Key := To_Unbounded_String (Next_Value (Argument));
            elsif Argument'Length > 0 and then Argument (Argument'First) = '-' then
               raise Constraint_Error with "unknown option: " & Argument;
            elsif Index = 1 then
               Result.Port := Natural'Value (Argument);
            else
               raise Constraint_Error with "unexpected argument: " & Argument;
            end if;
         end;

         Index := Index + 1;
      end loop;

      return Result;
   end Parse_Settings;

   procedure Configure_Live (Settings : Settings_Type) is
      Config : Web.Config.Config_Type := Web.Config.Default_Config;
   begin
      Config.Mode :=
        (if Settings.Production then Web.Config.Production else Web.Config.Development);
      Config.Secure_Cookies :=
        Settings.Secure_Cookies or else Settings.TLS_Enabled or else Settings.Production;
      Config.Session_Timeout := Settings.Session_Timeout;
      Put_Field (Config.TLS_Certificate_File, To_String (Settings.Certificate));
      Put_Field (Config.TLS_Private_Key_File, To_String (Settings.Private_Key));
      App.Live.Configure (Config);
   end Configure_Live;

   procedure Run_Server (Settings : Settings_Type) is
      Config : Web.Config.Config_Type := Web.Config.Default_Config;
      Host   : constant String := To_String (Settings.Host);
   begin
      Config.Mode :=
        (if Settings.Production then Web.Config.Production else Web.Config.Development);
      Config.Secure_Cookies :=
        Settings.Secure_Cookies or else Settings.TLS_Enabled or else Settings.Production;
      Config.Session_Timeout := Settings.Session_Timeout;
      Put_Field (Config.Allowed_Host, Host);
      Put_Field (Config.TLS_Certificate_File, To_String (Settings.Certificate));
      Put_Field (Config.TLS_Private_Key_File, To_String (Settings.Private_Key));
      Web.Server.Configure (Config);

      if Settings.TLS_Enabled then
         if Length (Settings.Certificate) = 0 or else Length (Settings.Private_Key) = 0 then
            raise Constraint_Error with "--tls requires --cert and --key";
         end if;

         Web.Server.Run_TLS (Host, Settings.Port, Config);
      else
         Web.Server.Run (Host, Settings.Port);
      end if;
   end Run_Server;

   Settings : Settings_Type;
begin
   Settings := Parse_Settings;
   if Settings.Help_Only then
      return;
   end if;

   App.Database.Initialize;
   Configure_Live (Settings);
   App.Dispatcher.Register ("counter.increment", App.Counter.Increment'Access);
   App.Dispatcher.Register ("profile.save", App.Profile.Save'Access);
   App.Dispatcher.Register ("todo.add", App.Todo.Add'Access);
   Web.Server.Get ("/", App.Pages.Home'Access);
   Web.Server.WebSocket ("/ws", App.Live.WebSocket_Handler'Access);
   Web.Server.Static ("/static", Static_Directory);
   Run_Server (Settings);
exception
   when Error : Constraint_Error =>
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "example_app: " & Ada.Exceptions.Exception_Message (Error));
      Usage;
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   when Error : others =>
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "example_app: " & Ada.Exceptions.Exception_Message (Error));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Example_App;
