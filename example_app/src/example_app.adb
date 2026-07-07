with Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Characters.Handling;
with Ada.Strings.Unbounded;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Terminal_Styles;
with App.Counter;
with App.Database;
with App.Runtime;
with App.Pages;
with App.Profile;
with App.Todo;
with Web.Config;
with Web.Logging;

--  Main example application entry point.
--  Demonstrates full-page rendering, websocket action dispatch, and persistence.
procedure Example_App is
   use Ada.Strings.Unbounded;

   --  Group all runtime configuration in one record for validation and reuse.
   type Settings_Type is record
      Host            : Unbounded_String := To_Unbounded_String ("127.0.0.1");
      Port            : Natural := 8080;
      TLS_Enabled     : Boolean := False;
      Production      : Boolean := False;
      Secure_Cookies  : Boolean := False;
      Allowed_Host    : Unbounded_String;
      Help_Only       : Boolean := False;
      Session_Timeout : Natural := 3_600;
      Max_Request_Size : Natural := 1_048_576;
      Max_Connections : Natural := 1_024;
      Compression_Enabled : Boolean := True;
      Compression_Min_Size : Natural := 256;
      Use_Forwarded_For : Boolean := False;
      Certificate     : Unbounded_String;
      Private_Key     : Unbounded_String;
      Log_Level      : Web.Logging.Level_Type := Web.Logging.Debug_Level;
      Structured_Log : Boolean := False;
   end record;

   --  Stable process exit codes used by startup checks and wrappers.
   Exit_OK : constant Ada.Command_Line.Exit_Status := Ada.Command_Line.Success;
   Exit_Usage : constant Ada.Command_Line.Exit_Status :=
     Ada.Command_Line.Exit_Status'Val (2);
   Exit_Startup_Failure : constant Ada.Command_Line.Exit_Status :=
     Ada.Command_Line.Exit_Status'Val (3);

   procedure Log_Message (Message : String; Role : Terminal_Styles.Style_Role);
   procedure Log_Info (Message : String);
   procedure Log_Error (Message : String);

   --  Print command line usage and supported switches.
   procedure Usage is
   begin
      Log_Message
        ("usage: example_app [PORT] [options]", Terminal_Styles.Role_Header);
      Log_Message ("  --host HOST", Terminal_Styles.Role_Muted);
      Log_Message ("  --port PORT", Terminal_Styles.Role_Muted);
      Log_Message ("  --production", Terminal_Styles.Role_Muted);
      Log_Message ("  --secure-cookies", Terminal_Styles.Role_Muted);
      Log_Message ("  --session-timeout SECONDS", Terminal_Styles.Role_Muted);
      Log_Message ("  --max-request-size BYTES", Terminal_Styles.Role_Muted);
      Log_Message ("  --max-connections COUNT", Terminal_Styles.Role_Muted);
      Log_Message ("  --no-compression", Terminal_Styles.Role_Muted);
      Log_Message ("  --compression-min-size BYTES", Terminal_Styles.Role_Muted);
      Log_Message ("  --allowed-host ALLOWED_HOST", Terminal_Styles.Role_Muted);
      Log_Message ("  --use-forwarded-for", Terminal_Styles.Role_Muted);
      Log_Message ("  --tls --cert CERT.pem --key KEY.pem", Terminal_Styles.Role_Muted);
      Log_Message
        ("  --log-level [debug|info|warn|error]", Terminal_Styles.Role_Muted);
      Log_Message ("  --log-structured", Terminal_Styles.Role_Muted);
   end Usage;

   --  Helper to keep logging visible in both framework sink and console output.
   procedure Log_Message (Message : String; Role : Terminal_Styles.Style_Role) is
   begin
      Web.Logging.Info (Message);
      Ada.Text_IO.Put_Line (Terminal_Styles.Line (Message, Role));
   end Log_Message;

   procedure Log_Info (Message : String) is
   begin
      Log_Message (Message, Terminal_Styles.Role_Info);
   end Log_Info;

   procedure Log_Error (Message : String) is
   begin
      Web.Logging.Error (Message);
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         Terminal_Styles.Line (Message, Terminal_Styles.Role_Error));
   end Log_Error;

   function Static_Directory return String is
   begin
      --  Prefer explicit project-root static path first for standalone invocation.
      if Ada.Directories.Exists ("example_app/static") then
         return "example_app/static";
      end if;

      return "static";
   end Static_Directory;

   function Port_Image (Port : Natural) return String is
      Result : constant String := Natural'Image (Port);
   begin
      --  Drop Ada's leading space in numeric image for clean logging/URLs.
      return Result (Result'First + 1 .. Result'Last);
   end Port_Image;

   function Has_Scheme (Value : String) return Boolean is
   begin
      --  Check for fully-qualified value such as "http://host:port".
      return Ada.Strings.Fixed.Index (Value, "://") > 0;
   end Has_Scheme;

   function Effective_Allowed_Host (Settings : Settings_Type) return String is
      Host  : constant String := To_String (Settings.Host);
      Port  : constant String := Port_Image (Settings.Port);
   begin
      --  Build a deterministic host form used by Web.Security checks.
      if Length (Settings.Allowed_Host) > 0 then
         return To_String (Settings.Allowed_Host);
      end if;

      if Settings.Port = 80 or else Settings.Port = 443 then
         return Host;
      end if;

      return Host & ":" & Port;
   end Effective_Allowed_Host;

   function Allowed_Origin (Settings : Settings_Type) return String is
      Host : constant String := Effective_Allowed_Host (Settings);
   begin
      --  Ensure scheme exists when required by websocket/origin matching.
      if Has_Scheme (Host) then
         return Host;
      end if;

      return "http://" & Host;
   end Allowed_Origin;

   function Parse_Log_Level (Value : String) return Web.Logging.Level_Type is
      Normalized : constant String := Ada.Characters.Handling.To_Lower (Value);
   begin
      --  Map CLI text to strongly-typed logging level; reject unknown values early.
      if Normalized = "debug" then
         return Web.Logging.Debug_Level;
      elsif Normalized = "info" then
         return Web.Logging.Info_Level;
      elsif Normalized = "warn" then
         return Web.Logging.Warn_Level;
      elsif Normalized = "error" then
         return Web.Logging.Error_Level;
      end if;

      raise Constraint_Error with "invalid log level: " & Value;
   end Parse_Log_Level;

   --  Parse all flags before startup; fail fast on malformed or unknown options.
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
            elsif Argument = "--max-request-size" then
               Result.Max_Request_Size := Natural'Value (Next_Value (Argument));
            elsif Argument = "--max-connections" then
               Result.Max_Connections := Natural'Value (Next_Value (Argument));
            elsif Argument = "--no-compression" then
               Result.Compression_Enabled := False;
            elsif Argument = "--compression-min-size" then
               Result.Compression_Min_Size := Natural'Value (Next_Value (Argument));
            elsif Argument = "--allowed-host" then
               Result.Allowed_Host := To_Unbounded_String (Next_Value (Argument));
            elsif Argument = "--use-forwarded-for" then
               Result.Use_Forwarded_For := True;
            elsif Argument = "--tls" then
               Result.TLS_Enabled := True;
            elsif Argument = "--cert" then
               Result.Certificate := To_Unbounded_String (Next_Value (Argument));
            elsif Argument = "--key" then
               Result.Private_Key := To_Unbounded_String (Next_Value (Argument));
            elsif Argument = "--log-level" then
               Result.Log_Level := Parse_Log_Level (Next_Value (Argument));
            elsif Argument = "--log-structured" then
               Result.Structured_Log := True;
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

   procedure Apply_Logging (Settings : Settings_Type) is
   begin
      Web.Logging.Set_Minimum_Level (Settings.Log_Level);
      Web.Logging.Set_Structured (Settings.Structured_Log);
   end Apply_Logging;

   --  Build a complete application configuration from CLI settings.
   function Build_Config (Settings : Settings_Type) return Web.Config.Config_Type is
      Config : Web.Config.Config_Type := Web.Config.Default_Config;
   begin
      Config.Mode :=
        (if Settings.Production then Web.Config.Production else Web.Config.Development);
      Config.Secure_Cookies :=
        Settings.Secure_Cookies or else Settings.TLS_Enabled or else Settings.Production;
      Config.Session_Timeout := Settings.Session_Timeout;
      Config.Max_Request_Size := Settings.Max_Request_Size;
      Config.Max_WebSocket_Message := Web.Config.Default_Config.Max_WebSocket_Message;
      Config.Max_Connections := Settings.Max_Connections;
      Config.Enable_Compression := Settings.Compression_Enabled;
      Config.Compression_Min_Size := Settings.Compression_Min_Size;
      Web.Config.Set_Use_X_Forwarded_For (Config, Settings.Use_Forwarded_For);
      Web.Config.Set_TLS_Certificate_File (Config, To_String (Settings.Certificate));
      Web.Config.Set_TLS_Private_Key_File (Config, To_String (Settings.Private_Key));
      Web.Config.Set_Allowed_Host (Config, Effective_Allowed_Host (Settings));
      return Config;
   end Build_Config;

   --  Configure HTTP server transport and start serving requests.
   procedure Run_Server (Settings : Settings_Type) is
      Config : constant Web.Config.Config_Type := Build_Config (Settings);
      Host   : constant String := To_String (Settings.Host);
   begin
      App.Runtime.Configure (Config);

      --  Emit a compact startup report with resolved routing/security values.
      Log_Info ("webframework: " & App.Runtime.Configuration_Report);
      Log_Info
        ("webframework: allowed_host=" & Effective_Allowed_Host (Settings)
         & " allowed_origin=" & Allowed_Origin (Settings));

      if Settings.TLS_Enabled then
         if Length (Settings.Certificate) = 0 or else Length (Settings.Private_Key) = 0 then
            raise Constraint_Error with "--tls requires --cert and --key";
         end if;

         App.Runtime.Run_TLS (Host, Settings.Port, Config);
      else
         App.Runtime.Run (Host, Settings.Port);
      end if;
   end Run_Server;

   Settings : Settings_Type;
   begin
      --  Startup sequence: parse settings, initialize logging and DB,
      --  configure live sessions, register routes/handlers, run server.
      Settings := Parse_Settings;
      if Settings.Help_Only then
         return;
      end if;

      Apply_Logging (Settings);
      --  Initialize persistence before accepting connections.
      App.Database.Initialize;
      null;
      --  Action-to-handler mapping for websocket events.
      App.Runtime.Register ("counter.increment", App.Counter.Increment'Access);
      App.Runtime.Register ("profile.save", App.Profile.Save'Access);
      App.Runtime.Register ("todo.add", App.Todo.Add'Access);
      App.Runtime.Register_Error_Handler (404, App.Pages.Error_Not_Found'Access);
      App.Runtime.Register_Error_Handler (400, App.Pages.Error_Bad_Request'Access);
      App.Runtime.Register_Error_Handler (500, App.Pages.Error_Server'Access);
      --  HTTP + websocket + static route wiring.
      App.Runtime.Get ("/", App.Pages.Home'Access);
      App.Runtime.Get ("/health", App.Pages.Health'Access);
      App.Runtime.WebSocket ("/ws", App.Runtime.WebSocket_Handler'Access);
      App.Runtime.Static ("/static", Static_Directory);
      --  Blocking call that owns the main process lifetime.
      Run_Server (Settings);
   exception
      --  Convert startup failures to a nonzero exit with readable diagnostics.
   when Error : Constraint_Error =>
      Log_Error ("error: example_app: " & Ada.Exceptions.Exception_Message (Error));
      Usage;
      Ada.Command_Line.Set_Exit_Status (Exit_Usage);
   when Error : others =>
      Log_Error ("error: example_app: " & Ada.Exceptions.Exception_Message (Error));
      Ada.Command_Line.Set_Exit_Status (Exit_Startup_Failure);
   end Example_App;
