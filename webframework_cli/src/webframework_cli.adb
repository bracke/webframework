with Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Terminal_Styles;
with Web.Logging;
with Project_Tools.Files;
with Project_Tools.Text;

package body Webframework_Cli is
   use Ada.Strings.Unbounded;
   use type Ada.Directories.File_Kind;

   LF : constant String := Character'Val (10) & "";
   Exit_OK : constant Natural := 0;
   Exit_Usage_Error : constant Natural := 2;
   Exit_Failure : constant Natural := 1;

   procedure Print_Info (Message : String) is
   begin
      Web.Logging.Info (Message);
      Ada.Text_IO.Put_Line (Terminal_Styles.Line (Message, Terminal_Styles.Role_Info));
   end Print_Info;

   procedure Print_Warn (Message : String) is
   begin
      Web.Logging.Warn (Message);
      Ada.Text_IO.Put_Line (Terminal_Styles.Line (Message, Terminal_Styles.Role_Warning));
   end Print_Warn;

   procedure Print_Error (Message : String) is
   begin
      Web.Logging.Error (Message);
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         Terminal_Styles.Line (Message, Terminal_Styles.Role_Error));
   end Print_Error;

   type Check_Result is record
      Errors : Natural := 0;
      Warnings : Natural := 0;
   end record;

   function Arg (Position : Positive) return String is
   begin
      if Ada.Command_Line.Argument_Count < Position then
         return "";
      end if;
      return Ada.Command_Line.Argument (Position);
   end Arg;

   function To_Package_Name (Name : String) return String is
      Result : Unbounded_String;
      Upper_Next : Boolean := True;
   begin
      for Ch of Name loop
         if Ch in 'a' .. 'z' then
            if Upper_Next then
               Append (Result, Character'Val (Character'Pos (Ch) - 32));
            else
               Append (Result, Ch);
            end if;
            Upper_Next := False;
         elsif Ch in 'A' .. 'Z' then
            Append (Result, Ch);
            Upper_Next := False;
         elsif Ch in '0' .. '9' then
            Append (Result, Ch);
            Upper_Next := False;
         else
            Upper_Next := True;
         end if;
      end loop;

      if Length (Result) = 0 then
         return "Generated";
      end if;
      return To_String (Result);
   end To_Package_Name;

   function To_File_Stem (Name : String) return String is
      Result : Unbounded_String;
   begin
      for Ch of Name loop
         if Ch in 'A' .. 'Z' then
            Append (Result, Character'Val (Character'Pos (Ch) + 32));
         elsif Ch in 'a' .. 'z' or else Ch in '0' .. '9' then
            Append (Result, Ch);
         elsif Length (Result) > 0
           and then Element (Result, Length (Result)) /= '-'
         then
            Append (Result, '-');
         end if;
      end loop;

      if Length (Result) = 0 then
         return "generated";
      end if;
      return To_String (Result);
   end To_File_Stem;

   function To_Project_Name (Name : String) return String is
      Result : Unbounded_String;
      Upper_Next : Boolean := True;
      Last_Was_Separator : Boolean := False;
   begin
      for Ch of Name loop
         if Ch in 'a' .. 'z' then
            if Upper_Next then
               Append (Result, Character'Val (Character'Pos (Ch) - 32));
            else
               Append (Result, Ch);
            end if;
            Upper_Next := False;
            Last_Was_Separator := False;
         elsif Ch in 'A' .. 'Z' or else Ch in '0' .. '9' then
            Append (Result, Ch);
            Upper_Next := False;
            Last_Was_Separator := False;
         elsif Length (Result) > 0 and then not Last_Was_Separator then
            Append (Result, '_');
            Upper_Next := True;
            Last_Was_Separator := True;
         end if;
      end loop;

      if Length (Result) > 0 and then Element (Result, Length (Result)) = '_' then
         Delete (Result, Length (Result), Length (Result));
      end if;
      if Length (Result) = 0 then
         return "Generated_App";
      end if;
      return To_String (Result);
   end To_Project_Name;

   function Handler_Package (Action : String) return String is
      Dot : constant Natural := Ada.Strings.Fixed.Index (Action, ".");
   begin
      if Dot = 0 then
         return "App." & To_Package_Name (Action);
      end if;
      return "App." & To_Package_Name (Action (Action'First .. Dot - 1));
   end Handler_Package;

   function Handler_Name (Action : String) return String is
      Dot : constant Natural := Ada.Strings.Fixed.Index (Action, ".");
   begin
      if Dot = 0 then
         return "Handle";
      end if;
      return To_Package_Name (Action (Dot + 1 .. Action'Last));
   end Handler_Name;

   function Handler_Full_Name (Action : String) return String is
   begin
      return Handler_Package (Action) & "." & Handler_Name (Action);
   end Handler_Full_Name;

   function Source_Path (Root : String; Relative : String) return String is
   begin
      return Project_Tools.Files.Join (Project_Tools.Files.Join (Root, "src"), Relative);
   end Source_Path;

   procedure Ensure_Dir (Path : String) is
   begin
      if not Project_Tools.Files.Directory_Exists (Path) then
         Ada.Directories.Create_Directory (Path);
      end if;
   end Ensure_Dir;

   procedure Ensure_Tree (Root : String) is
   begin
      Ensure_Dir (Root);
      Ensure_Dir (Project_Tools.Files.Join (Root, "src"));
      Ensure_Dir (Project_Tools.Files.Join (Root, "templates"));
      Ensure_Dir (Project_Tools.Files.Join (Root, "static"));
   end Ensure_Tree;

   function Normalized_Text (Content : String) return String is
      Result : Unbounded_String;
      Line_Feeds : Natural := 0;
   begin
      for Ch of Content loop
         if Ch = Character'Val (10) then
            if Line_Feeds < 2 then
               Append (Result, Ch);
            end if;
            Line_Feeds := Line_Feeds + 1;
         else
            Append (Result, Ch);
            Line_Feeds := 0;
         end if;
      end loop;

      while Length (Result) > 0
        and then Element (Result, Length (Result)) = Character'Val (10)
      loop
         Delete (Result, Length (Result), Length (Result));
      end loop;

      Append (Result, Character'Val (10));
      return To_String (Result);
   end Normalized_Text;

   procedure Write_Text (Path : String; Content : String) is
   begin
      Project_Tools.Files.Write_Text_File (Path, Normalized_Text (Content));
   end Write_Text;

   procedure Write_If_Missing (Path : String; Content : String) is
   begin
      if Project_Tools.Files.File_Exists (Path) then
         return;
      end if;
      Write_Text (Path, Content);
   end Write_If_Missing;

   function Manifest_Array_Line (Key : String; Values : String) return String is
   begin
      return Key & " = [" & Values & "]" & LF;
   end Manifest_Array_Line;

   function Framework_Project_With return String is
      Command : constant String := Ada.Command_Line.Command_Name;
      Marker : constant String := "/webframework_cli/bin/";
      Marker_Pos : constant Natural := Project_Tools.Text.Index (Command, Marker);
      Relative_Marker : constant String := "webframework_cli/bin/";
      Relative_Pos : constant Natural := Project_Tools.Text.Index (Command, Relative_Marker);
      Root : Unbounded_String;
   begin
      if Marker_Pos > Command'First then
         return "with """ & Command (Command'First .. Marker_Pos - 1) & "/webframework.gpr"";";
      elsif Relative_Pos > 0 then
         if Relative_Pos = Command'First then
            Root := To_Unbounded_String (Ada.Directories.Full_Name ("."));
         else
            Root :=
              To_Unbounded_String
                (Ada.Directories.Full_Name (Command (Command'First .. Relative_Pos - 2)));
         end if;
         return "with """ & To_String (Root) & "/webframework.gpr"";";
      elsif Project_Tools.Files.File_Exists ("webframework.gpr") then
         return "with """ & Ada.Directories.Full_Name (".") & "/webframework.gpr"";";
      elsif Project_Tools.Files.File_Exists ("../webframework.gpr") then
         return "with """ & Ada.Directories.Full_Name ("..") & "/webframework.gpr"";";
      end if;
      return "with ""../webframework.gpr"";";
   end Framework_Project_With;

   function Framework_Root return String is
      Command : constant String := Ada.Command_Line.Command_Name;
      Marker : constant String := "/webframework_cli/bin/";
      Marker_Pos : constant Natural := Project_Tools.Text.Index (Command, Marker);
   begin
      if Marker_Pos > Command'First then
         return Command (Command'First .. Marker_Pos - 1);
      end if;

      if Project_Tools.Files.File_Exists ("../static/webframework.js") then
         return "..";
      end if;

      return ".";
   end Framework_Root;

   function Absolute_Framework_Root return String is
      Root : constant String := Framework_Root;
   begin
      if Ada.Directories.Exists (Root) then
         return Ada.Directories.Full_Name (Root);
      end if;
      return Root;
   end Absolute_Framework_Root;

   function Sibling_Root (Name : String) return String is
      Root : constant String := Absolute_Framework_Root;
   begin
      if Ada.Directories.Exists (Project_Tools.Files.Join (Root, "../" & Name)) then
         return Ada.Directories.Full_Name (Project_Tools.Files.Join (Root, "../" & Name));
      end if;
      return Project_Tools.Files.Join (Root, "../" & Name);
   end Sibling_Root;

   function Base_Manifest (Name : String) return String is
   begin
      return "name = """ & Name & """" & LF
        & Manifest_Array_Line ("routes", """" & "/" & """, ""/health""")
        & Manifest_Array_Line ("actions", "")
        & Manifest_Array_Line ("handlers", "")
        & Manifest_Array_Line ("templates", """" & "layout.html" & """, """ & "home.html" & """")
        & Manifest_Array_Line ("patch_targets", "")
        & Manifest_Array_Line ("static_files", """" & "webframework.js" & """, """ & "style.css" & """");
   end Base_Manifest;

   function Base_Alire_Manifest (Name : String) return String is
   begin
      return "name = """ & Name & """" & LF
        & "description = ""Generated webframework application""" & LF
        & "version = ""0.1.0-dev""" & LF
        & "licenses = ""MIT""" & LF
        & "executables = [""" & Name & """]" & LF
        & "project-files = [""" & Name & ".gpr""]" & LF
        & LF
        & "[[depends-on]]" & LF
        & "gnat_native = ""=15.2.1""" & LF
        & LF
        & "[[depends-on]]" & LF
        & "webframework = ""*""" & LF
        & LF
        & "[[pins]]" & LF
        & "webframework = { path = """ & Absolute_Framework_Root & """ }" & LF
        & LF
        & "[[pins]]" & LF
        & "cryptolib = { path = """ & Sibling_Root ("cryptolib") & """ }" & LF
        & LF
        & "[[pins]]" & LF
        & "ssh_lib = { path = """ & Sibling_Root ("sshlib") & """ }" & LF
        & LF
        & "[[pins]]" & LF
        & "zlib = { path = """ & Sibling_Root ("zlib") & """ }" & LF;
   end Base_Alire_Manifest;

   function Read_File (Path : String) return String is
   begin
      if not Project_Tools.Files.File_Exists (Path) then
         return "";
      end if;
      return Project_Tools.Files.Read_Raw_File (Path);
   end Read_File;

   procedure Replace_File (Path : String; Old_Text : String; New_Text : String) is
      Content : constant String := Read_File (Path);
      Place : constant Natural := Project_Tools.Text.Index (Content, Old_Text);
      Result : Unbounded_String;
   begin
      if Place = 0 then
         return;
      end if;

      if Place > Content'First then
         Append (Result, Content (Content'First .. Place - 1));
      end if;
      Append (Result, New_Text);
      if Place + Old_Text'Length <= Content'Last then
         Append (Result, Content (Place + Old_Text'Length .. Content'Last));
      end if;
      Write_Text (Path, To_String (Result));
   end Replace_File;

   function Array_Line (Manifest : String; Key : String) return String is
      Prefix : constant String := Key & " = [";
      Start_Pos : constant Natural := Project_Tools.Text.Index (Manifest, Prefix);
      Stop_Pos : Natural;
   begin
      if Start_Pos = 0 then
         return "";
      end if;
      Stop_Pos := Project_Tools.Text.Index_From (Manifest, "]", Start_Pos + Prefix'Length);
      if Stop_Pos = 0 then
         return "";
      end if;
      return Manifest (Start_Pos .. Stop_Pos);
   end Array_Line;

   function Array_Has_Values (Manifest : String; Key : String) return Boolean is
      Line : constant String := Array_Line (Manifest, Key);
   begin
      return Project_Tools.Text.Contains (Line, """");
   end Array_Has_Values;

   function Scalar_Value (Manifest : String; Key : String) return String is
      Prefix : constant String := Key & " = """;
      Start_Pos : constant Natural := Project_Tools.Text.Index (Manifest, Prefix);
      Stop_Pos : Natural;
   begin
      if Start_Pos = 0 then
         return "";
      end if;
      Stop_Pos := Project_Tools.Text.Index_From (Manifest, """", Start_Pos + Prefix'Length);
      if Stop_Pos = 0 then
         return "";
      end if;
      return Manifest (Start_Pos + Prefix'Length .. Stop_Pos - 1);
   end Scalar_Value;

   procedure Add_Manifest_Value (Root : String; Key : String; Value : String) is
      Path : constant String := Project_Tools.Files.Join (Root, "webframework.toml");
      Manifest : constant String := Read_File (Path);
      Line : constant String := Array_Line (Manifest, Key);
      Quoted : constant String := """" & Value & """";
      Replacement : Unbounded_String;
   begin
      if Line'Length = 0 or else Project_Tools.Text.Contains (Line, Quoted) then
         return;
      end if;

      if Project_Tools.Text.Contains (Line, "[]") then
         Replacement := To_Unbounded_String (Key & " = [" & Quoted & "]");
      else
         Replacement := To_Unbounded_String (Line (Line'First .. Line'Last - 1) & ", " & Quoted & "]");
      end if;
      Replace_File (Path, Line, To_String (Replacement));
   end Add_Manifest_Value;

   procedure Register_With (Root : String; With_Line : String) is
      Path : constant String := Source_Path (Root, "main.adb");
      Content : constant String := Read_File (Path);
   begin
      if not Project_Tools.Text.Contains (Content, With_Line) then
         Write_Text (Path, With_Line & LF & Content);
      end if;
   end Register_With;

   procedure Insert_Before_Run (Root : String; Line : String) is
      Path : constant String := Source_Path (Root, "main.adb");
      Content : constant String := Read_File (Path);
      Marker : constant String :=
        (if Project_Tools.Text.Contains (Content, "   App.Runtime.Run")
         then "   App.Runtime.Run"
         else "   Web.Server.Run");
   begin
      if Project_Tools.Text.Contains (Content, Line) then
         return;
      end if;
      if not Project_Tools.Text.Contains (Content, Marker) then
         raise Constraint_Error with "no run marker found in generated main";
      end if;
      Replace_File (Path, Marker, Line & LF & Marker);
   end Insert_Before_Run;

   procedure Write_Static_Runtime (Root : String) is
      Static_Dir : constant String := Project_Tools.Files.Join (Root, "static");
      Canonical_Runtime : constant String :=
        Project_Tools.Files.Join (Project_Tools.Files.Join (Framework_Root, "static"), "webframework.js");
      Runtime : constant String :=
        "(function () {" & LF
        & "  ""use strict"";" & LF
        & LF
        & "  var socket = null;" & LF
        & LF
        & "  function connect() {" & LF
        & "    if (socket" & LF
        & "        && (socket.readyState === WebSocket.OPEN" & LF
        & "            || socket.readyState === WebSocket.CONNECTING)) {" & LF
        & "      return;" & LF
        & "    }" & LF
        & "    var path = document.body.getAttribute(""data-wf-ws"") || ""/ws"";" & LF
        & "    var scheme = window.location.protocol === ""https:"" ? ""wss:"" : ""ws:"";" & LF
        & "    socket = new WebSocket(scheme + ""//"" + window.location.host + path);" & LF
        & "    socket.addEventListener(""open"", function () {" & LF
        & "      socket.send(JSON.stringify({ type: ""hello"", version: 1 }));" & LF
        & "    });" & LF
        & "    socket.addEventListener(""message"", function (event) {" & LF
        & "      var message = null;" & LF
        & "      try {" & LF
        & "        message = JSON.parse(event.data);" & LF
        & "      } catch (error) {" & LF
        & "        return;" & LF
        & "      }" & LF
        & "      if (message.type === ""patches"" && Array.isArray(message.patches)) {" & LF
        & "        applyPatches(message.patches);" & LF
        & "      }" & LF
        & "    });" & LF
        & "  }" & LF
        & LF
        & "  function send(message) {" & LF
        & "    message.version = 1;" & LF
        & "    if (socket && socket.readyState === WebSocket.OPEN) {" & LF
        & "      socket.send(JSON.stringify(message));" & LF
        & "    }" & LF
        & "  }" & LF
        & LF
        & "  function applyPatches(patches) {" & LF
        & "    patches.forEach(function (patch) {" & LF
        & "      var target = document.getElementById(patch.target);" & LF
        & "      if (!target) {" & LF
        & "        return;" & LF
        & "      }" & LF
        & "      if (patch.op === ""replace_html"") {" & LF
        & "        if (!patch.force && target.contains(document.activeElement)) {" & LF
        & "          return;" & LF
        & "        }" & LF
        & "        target.innerHTML = patch.value || """";" & LF
        & "      } else if (patch.op === ""set_text"") {" & LF
        & "        target.textContent = patch.value || """";" & LF
        & "      } else if (patch.op === ""set_attr"") {" & LF
        & "        target.setAttribute(patch.name, patch.value || """");" & LF
        & "      } else if (patch.op === ""remove_attr"") {" & LF
        & "        target.removeAttribute(patch.name);" & LF
        & "      } else if (patch.op === ""add_class"") {" & LF
        & "        target.classList.add(patch.name);" & LF
        & "      } else if (patch.op === ""remove_class"") {" & LF
        & "        target.classList.remove(patch.name);" & LF
        & "      } else if (patch.op === ""set_value"") {" & LF
        & "        target.value = patch.value || """";" & LF
        & "      }" & LF
        & "    });" & LF
        & "  }" & LF
        & LF
        & "  document.addEventListener(""click"", function (event) {" & LF
        & "    var element = event.target.closest(""[data-wf-click]"");" & LF
        & "    if (element) {" & LF
        & "      send({ type: ""click"", id: element.id, action: element.getAttribute(""data-wf-click"") });" & LF
        & "    }" & LF
        & "  });" & LF
        & LF
        & "  document.addEventListener(""submit"", function (event) {" & LF
        & "    var form = event.target.closest(""form[data-wf-submit]"");" & LF
        & "    var fields = {};" & LF
        & "    if (!form) {" & LF
        & "      return;" & LF
        & "    }" & LF
        & "    event.preventDefault();" & LF
        & "    new FormData(form).forEach(function (value, key) {" & LF
        & "      fields[key] = String(value);" & LF
        & "    });" & LF
        & "    send({" & LF
        & "      type: ""submit""," & LF
        & "      id: form.id," & LF
        & "      action: form.getAttribute(""data-wf-submit"")," & LF
        & "      fields: fields" & LF
        & "    });" & LF
        & "  });" & LF
        & LF
        & "  window.WebFramework = { connect: connect, applyPatches: applyPatches };" & LF
        & "  if (document.readyState === ""loading"") {" & LF
        & "    document.addEventListener(""DOMContentLoaded"", connect);" & LF
        & "  } else {" & LF
        & "    connect();" & LF
        & "  }" & LF
        & "}());" & LF;
   begin
      if Project_Tools.Files.File_Exists (Canonical_Runtime) then
         Write_If_Missing
           (Project_Tools.Files.Join (Static_Dir, "webframework.js"),
            Read_File (Canonical_Runtime));
      else
         Write_If_Missing (Project_Tools.Files.Join (Static_Dir, "webframework.js"), Runtime);
      end if;
      Write_If_Missing
        (Project_Tools.Files.Join (Static_Dir, "style.css"),
         "body { font-family: sans-serif; margin: 2rem; }" & LF);
   end Write_Static_Runtime;

   procedure Write_Base_App (Root : String; Name : String) is
      App_Name : constant String := To_Project_Name (Name);
      Gpr : constant String :=
        "--  Generated project file for a webframework application." & LF
        & "--  Keep this file plain and predictable for manual review." & LF
        & Framework_Project_With & LF
        & "project " & App_Name & " is" & LF
        & "   --  Place source and artifact directories explicitly so output is" & LF
        & "   --  deterministic in both source and IDE contexts." & LF
        & "   for Source_Dirs use (""src"");" & LF
        & "   for Object_Dir use ""obj"";" & LF
        & "   for Exec_Dir use ""bin"";" & LF
        & "   for Main use (""main.adb"");" & LF
        & "   --  Compile with strict checks and Ada 2022 conformance settings." & LF
        & "   package Compiler is" & LF
        & "      for Default_Switches (""Ada"") use (""-gnat2022"", ""-gnata"", ""-gnatwe"", ""-gnatyM120"");"
        & LF
        & "   end Compiler;" & LF
        & "end " & App_Name & ";" & LF;
      State_Spec : constant String :=
        "--  Session state for the generated application." & LF
        & "--  The state type is session scoped and intentionally small." & LF
        & "package App.State is" & LF
        & "   --  A sample per-session counter used by generated demo routes." & LF
        & "   type State_Type is record" & LF
        & "      Counter : Natural := 0;" & LF
        & "   end record;" & LF
        & LF
        & "   --  Create a fresh session state for a new websocket session." & LF
        & "   --  @return Initial application state." & LF
        & "   function Initial return State_Type;" & LF
        & "end App.State;" & LF;
      State_Body : constant String :=
        "--  Implementation of default state construction." & LF
        & "package body App.State is" & LF
        & "   --  Return deterministic defaults for any newly created session." & LF
        & "   function Initial return State_Type is" & LF
        & "   begin" & LF
        & "      return (Counter => 0);" & LF
        & "   end Initial;" & LF
        & "end App.State;" & LF;
      Dispatcher : constant String :=
        "--  Dispatcher wiring for action handlers." & LF
        & "with Web.Application;" & LF
        & "with App.State;" & LF
        & LF
        & "--  The generated app keeps action registration in App.Runtime." & LF
        & "--  This package is a direct renaming to the generated convenience façade." & LF
        & "--" & LF
        & "--  Registration is done in generated main.adb using action strings and" & LF
        & "--  handler references produced by webframework-cli commands." & LF
        & "--" & LF
        & "--  Example registration line in main.adb:" & LF
        & "--     App.Runtime.Register (""counter.increment"", Handler.Function'Access);" & LF
        & "package App.Runtime is new Web.Application" & LF
        & "  (App_State     => App.State.State_Type," & LF
        & "   Initial_State => App.State.Initial);" & LF;
      Live : constant String :=
        "--  Live instance for websocket and session management." & LF
        & "with App.Runtime;" & LF
        & LF
        & "--  Instantiate the generic live layer with typed session state." & LF
        & "--  App.Live remains available for compatibility; runtime behavior is" & LF
        & "--  driven through App.Runtime now." & LF
        & "--  App.Live controls session lookup/creation, websocket wiring, and" & LF
        & "--  handler dispatch against the active per-session state." & LF
        & "--" & LF
        & "--  Rendered pages should call App.Runtime.Html_Response so session" & LF
        & "--  cookies and state handoff are always consistent with framework" & LF
        & "--  conventions." & LF
        & "--" & LF
        & "--  Websocket events are processed through this package, and the app" & LF
        & "--  only provides a typed state type plus the dispatch function." & LF
        & "package App.Live renames App.Runtime.Live;" & LF;
      Pages_Spec : constant String :=
        "with Web.Request;" & LF
        & "with Web.Response;" & LF
        & LF
        "--  Page rendering entry points for HTTP routes." & LF
        & "package App.Pages is" & LF
        & "   --  Render the home page." & LF
        & "   --  @param Request HTTP request." & LF
        & "   --  @return HTTP response." & LF
        & "   function Home (Request : Web.Request.Request_Type) return Web.Response.Response_Type;" & LF
        & LF
        & "   --  Render the health-check route." & LF
        & "   --  @param Request HTTP request." & LF
        & "   --  @return HTTP response." & LF
        & "   function Health (Request : Web.Request.Request_Type) return Web.Response.Response_Type;" & LF
        & "end App.Pages;" & LF;
      Pages_Body : constant String :=
        "with Ada.Exceptions;" & LF
        & "with App.Runtime;" & LF
        & "with Web.Logging;" & LF
        & "with Web.Response;" & LF
        & LF
        & "--  Route handlers are intentionally defensive and return clear errors." & LF
        & "package body App.Pages is" & LF
        & "   --  Handle the default root route." & LF
        & "   --  Uses App.Runtime.Html_Response so cookie/session behavior is automatic." & LF
        & "   function Home (Request : Web.Request.Request_Type) return Web.Response.Response_Type is" & LF
        & "   begin" & LF
        & "      return App.Runtime.Html_Response" & LF
        & "        (Request, ""<!doctype html><html><body><main id=""""app"""">Home</main></body></html>"");" & LF
        & "   --  Defensive fallback: keep process alive if this route has a bug." & LF
        & "   exception" & LF
        & "      when Error : others =>" & LF
        & "         Web.Logging.Error" & LF
        & "           (""home page render failed: "" & Ada.Exceptions.Exception_Message (Error));" & LF
        & "         return Web.Response.Internal_Server_Error" & LF
        & "           (""Home page is temporarily unavailable."");" & LF
        & "   end Home;" & LF
        & LF
        & "   --  Handle GET /health." & LF
        & "   --  Exposed for orchestration checks and availability probes." & LF
        & "   function Health (Request : Web.Request.Request_Type) return Web.Response.Response_Type is" & LF
        & "      pragma Unreferenced (Request);" & LF
        & "   begin" & LF
        & "      return App.Runtime.Health_Response;" & LF
        & "   --  If health logic is changed later, do not crash the server." & LF
        & "   exception" & LF
        & "      when Error : others =>" & LF
        & "         Web.Logging.Error" & LF
        & "           (""health route failed: "" & Ada.Exceptions.Exception_Message (Error));" & LF
        & "         return Web.Response.Internal_Server_Error" & LF
        & "           (""Health endpoint is temporarily unavailable."");" & LF
        & "   end Health;" & LF
        & "end App.Pages;" & LF;
      Main : constant String :=
        "with Ada.Characters.Handling;" & LF
        & "with Ada.Command_Line;" & LF
        & "with Ada.Exceptions;" & LF
        & "with Ada.Strings.Unbounded;" & LF
        & "with Ada.Text_IO;" & LF
        & "with App.Runtime;" & LF
        & "with App.Pages;" & LF
        & "with Web.Config;" & LF
        & "with Web.Logging;" & LF
        & LF
        & "--  Generated main for the scaffolded application." & LF
        & "--  This file is intentionally explicit and easy to edit." & LF
        & "procedure Main is" & LF
        & "   use Ada.Strings.Unbounded;" & LF
        & "   " & LF
        & "   --  Print informational messages to both logging and stdout." & LF
        & "   procedure Print_Info (Message : String) is" & LF
        & "   begin" & LF
        & "      Web.Logging.Info (Message);" & LF
        & "      Ada.Text_IO.Put_Line (Message);" & LF
        & "   end Print_Info;" & LF
        & LF
        & "   --  Print fatal/usage errors to logging and stderr." & LF
        & "   procedure Print_Error (Message : String) is" & LF
        & "   begin" & LF
        & "      Web.Logging.Error (Message);" & LF
        & "      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Message);" & LF
        & "   end Print_Error;" & LF
        & LF
        & "   --  Supported runtime settings for this generated executable." & LF
        & "   type Settings_Type is record" & LF
        & "      --  Network bind and server mode settings." & LF
        & "      Host : Unbounded_String := To_Unbounded_String (""127.0.0.1"");" & LF
        & "      Port : Natural := 8080;" & LF
        & "      Production : Boolean := False;" & LF
        & "      --  Cookie and state management settings." & LF
        & "      Secure_Cookies : Boolean := False;" & LF
        & "      Session_Timeout : Natural := 3_600;" & LF
        & "      --  Request and websocket transport size limits." & LF
        & "      Max_Request_Size : Natural := 1_048_576;" & LF
        & "      Max_WebSocket_Message : Natural := 65_536;" & LF
        & "      Max_Connections : Natural := 1_024;" & LF
        & "      --  Optional response compression options." & LF
        & "      Compression : Boolean := True;" & LF
        & "      Compression_Min_Size : Natural := 256;" & LF
        & "      --  Logging controls." & LF
        & "      Log_Level : Web.Logging.Level_Type := Web.Logging.Debug_Level;" & LF
        & "      Structured_Log : Boolean := False;" & LF
        & "      --  Session cleanup frequency in seconds." & LF
        & "      Cleanup_Interval : Positive := 60;" & LF
        & "      --  Help-only mode stops after printing usage text." & LF
        & "      Help_Only : Boolean := False;" & LF
        & "   end record;" & LF
        & "   " & LF
        & "   --  Stable startup exit codes for tooling and supervisors." & LF
       & "   Exit_Usage : constant Natural := 2;" & LF
        & "   Exit_Failure : constant Natural := 1;" & LF
        & "   Exit_Startup : constant Natural := 3;" & LF
        & "   " & LF
        & LF
        & "   --  Print CLI usage and supported flags." & LF
        & "   procedure Usage is" & LF
        & "   begin" & LF
        & "      Print_Info (""usage: main [options]"");" & LF
        & "      Print_Info (""  --host HOST"");" & LF
        & "      Print_Info (""  --port PORT"");" & LF
        & "      Print_Info (""  --production"");" & LF
        & "      Print_Info (""  --secure-cookies"");" & LF
        & "      Print_Info (""  --session-timeout SECONDS"");" & LF
        & "      Print_Info (""  --max-request-size BYTES"");" & LF
        & "      Print_Info (""  --max-websocket-message BYTES"");" & LF
        & "      Print_Info (""  --max-connections COUNT"");" & LF
        & "      Print_Info (""  --no-compression"");" & LF
        & "      Print_Info (""  --compression-min-size BYTES"");" & LF
        & "      Print_Info (""  --log-level [debug|info|warn|error]"");" & LF
        & "      Print_Info (""  --log-structured"");" & LF
        & "      Print_Info (""  --cleanup-interval SECONDS"");" & LF
        & "   end Usage;" & LF
        & LF
        & "   --  Parse string log levels from CLI into typed values." & LF
        & "   function Parse_Log_Level (Value : String) return Web.Logging.Level_Type is" & LF
        & "      Normalized : constant String := Ada.Characters.Handling.To_Lower (Value);" & LF
        & "   begin" & LF
        & "      if Normalized = ""debug"" then" & LF
        & "         return Web.Logging.Debug_Level;" & LF
        & "      elsif Normalized = ""info"" then" & LF
        & "         return Web.Logging.Info_Level;" & LF
        & "      elsif Normalized = ""warn"" then" & LF
        & "         return Web.Logging.Warn_Level;" & LF
        & "      elsif Normalized = ""error"" then" & LF
        & "         return Web.Logging.Error_Level;" & LF
        & "      end if;" & LF
        & "      raise Constraint_Error with ""invalid log level: "" & Value;" & LF
        & "   end Parse_Log_Level;" & LF
        & LF
        & "   --  Parse command line flags and produce validated settings." & LF
        & "   function Parse_Settings return Settings_Type is" & LF
        & "      Result : Settings_Type;" & LF
        & "      Index : Positive := 1;" & LF
        & LF
        & "      --  Consume and validate an option value argument." & LF
        & "      function Next_Value (Option : String) return String is" & LF
        & "      begin" & LF
        & "         if Index >= Ada.Command_Line.Argument_Count then" & LF
        & "            raise Constraint_Error with Option & "" requires a value"";" & LF
        & "         end if;" & LF
        & "         Index := Index + 1;" & LF
        & "         return Ada.Command_Line.Argument (Index);" & LF
        & "      end Next_Value;" & LF
        & "   begin" & LF
        & "      while Index <= Ada.Command_Line.Argument_Count loop" & LF
        & "         declare" & LF
        & "            Argument : constant String := Ada.Command_Line.Argument (Index);" & LF
        & "         begin" & LF
        & "            if Argument = ""--help"" then" & LF
        & "               Usage;" & LF
        & "               Result.Help_Only := True;" & LF
        & "               return Result;" & LF
        & "            elsif Argument = ""--host"" then" & LF
        & "               Result.Host := To_Unbounded_String (Next_Value (Argument));" & LF
        & "            elsif Argument = ""--port"" then" & LF
        & "               Result.Port := Natural'Value (Next_Value (Argument));" & LF
        & "            elsif Argument = ""--production"" then" & LF
        & "               Result.Production := True;" & LF
        & "            elsif Argument = ""--secure-cookies"" then" & LF
        & "               Result.Secure_Cookies := True;" & LF
        & "            elsif Argument = ""--session-timeout"" then" & LF
        & "               Result.Session_Timeout := Natural'Value (Next_Value (Argument));" & LF
        & "            elsif Argument = ""--max-request-size"" then" & LF
        & "               Result.Max_Request_Size := Natural'Value (Next_Value (Argument));" & LF
        & "            elsif Argument = ""--max-websocket-message"" then" & LF
        & "               Result.Max_WebSocket_Message := Natural'Value (Next_Value (Argument));" & LF
        & "            elsif Argument = ""--max-connections"" then" & LF
        & "               Result.Max_Connections := Natural'Value (Next_Value (Argument));" & LF
        & "            elsif Argument = ""--no-compression"" then" & LF
        & "               Result.Compression := False;" & LF
        & "            elsif Argument = ""--compression-min-size"" then" & LF
        & "               Result.Compression_Min_Size := Natural'Value (Next_Value (Argument));" & LF
        & "            elsif Argument = ""--log-level"" then" & LF
        & "               Result.Log_Level := Parse_Log_Level (Next_Value (Argument));" & LF
        & "            elsif Argument = ""--log-structured"" then" & LF
        & "               Result.Structured_Log := True;" & LF
        & "            elsif Argument = ""--cleanup-interval"" then" & LF
        & "               Result.Cleanup_Interval := Positive'Value (Next_Value (Argument));" & LF
        & "            else" & LF
        & "               raise Constraint_Error with ""unknown option: "" & Argument;" & LF
        & "            end if;" & LF
        & "         end;" & LF
        & "         Index := Index + 1;" & LF
        & "      end loop;" & LF
        & "      return Result;" & LF
        & "   end Parse_Settings;" & LF
        & LF
        & "   --  Apply validated settings to framework and live layer." & LF
        & "   procedure Configure (Settings : Settings_Type) is" & LF
        & "      Config : Web.Config.Config_Type := Web.Config.Default_Config;" & LF
        & "   begin" & LF
        & "      Config.Mode :=" & LF
        & "        (if Settings.Production then Web.Config.Production else Web.Config.Development);" & LF
        & "      Config.Secure_Cookies := Settings.Secure_Cookies or else Settings.Production;" & LF
        & "      Config.Session_Timeout := Settings.Session_Timeout;" & LF
        & "      Config.Max_Request_Size := Settings.Max_Request_Size;" & LF
        & "      Config.Max_WebSocket_Message := Settings.Max_WebSocket_Message;" & LF
        & "      Config.Max_Connections := Settings.Max_Connections;" & LF
        & "      Config.Enable_Compression := Settings.Compression;" & LF
        & "      Config.Compression_Min_Size := Settings.Compression_Min_Size;" & LF
        & "      Web.Config.Set_Host (Config, To_String (Settings.Host));" & LF
        & "      Web.Config.Set_Allowed_Host (Config, To_String (Settings.Host));" & LF
        & "      App.Runtime.Configure (Config);" & LF
        & "   end Configure;" & LF
        & "   --  Configure logging from CLI values before server startup." & LF
        & "   procedure Apply_Logging (Settings : Settings_Type) is" & LF
        & "   begin" & LF
        & "      Web.Logging.Set_Minimum_Level (Settings.Log_Level);" & LF
        & "      Web.Logging.Set_Structured (Settings.Structured_Log);" & LF
        & "   end Apply_Logging;" & LF
        & LF
        & "   --  Bind all pieces and start serving." & LF
        & "   Settings : Settings_Type;" & LF
        & "begin" & LF
        & "   Settings := Parse_Settings;" & LF
        & "   if Settings.Help_Only then" & LF
        & "      return;" & LF
        & "   end if;" & LF
        & "   Apply_Logging (Settings);" & LF
        & "   Configure (Settings);" & LF
        & "   -- webframework:begin actions" & LF
        & "   -- webframework:end actions" & LF
        & "   App.Runtime.Get (""/"", App.Pages.Home'Access);" & LF
        & "   App.Runtime.Get (""/health"", App.Pages.Health'Access);" & LF
        & "   App.Runtime.WebSocket (""/ws"", App.Runtime.WebSocket_Handler'Access);" & LF
        & "   App.Runtime.Static (""/static"", ""static"");" & LF
        & "   App.Runtime.Start_Cleanup_Task (Settings.Cleanup_Interval);" & LF
        & "   Web.Logging.Info (""webframework: "" & App.Runtime.Configuration_Report);" & LF
        & "   App.Runtime.Run (To_String (Settings.Host), Settings.Port);" & LF
        & "exception" & LF
        & "   --  Preserve diagnostics for command-line validation and startup failures." & LF
        & "   --  Never let an error crash without a clear process exit code." & LF
        & "   when Error : Constraint_Error =>" & LF
        & "      Print_Error (""main: "" & Ada.Exceptions.Exception_Message (Error));" & LF
        & "      Usage;" & LF
        & "      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status'Val (Exit_Usage));" & LF
        & "   when Error : others =>" & LF
        & "      Print_Error (""main: "" & Ada.Exceptions.Exception_Message (Error));" & LF
        & "      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Exit_Status'Val (Exit_Startup));" & LF
        & "end Main;" & LF;
   begin
      Write_If_Missing (Project_Tools.Files.Join (Root, Name & ".gpr"), Gpr);
      Write_If_Missing
        (Source_Path (Root, "app.ads"),
         "--  Package root for the generated application." & LF
         & "--  Keep global declarations here instead of hiding them in package bodies." & LF
         & "package App is" & LF
         & "end App;" & LF);
      Write_If_Missing (Source_Path (Root, "app-state.ads"), State_Spec);
      Write_If_Missing (Source_Path (Root, "app-state.adb"), State_Body);
      Write_If_Missing (Source_Path (Root, "app-dispatcher.ads"), Dispatcher);
      Write_If_Missing (Source_Path (Root, "app-live.ads"), Live);
      Write_If_Missing (Source_Path (Root, "app-pages.ads"), Pages_Spec);
      Write_If_Missing (Source_Path (Root, "app-pages.adb"), Pages_Body);
      Write_If_Missing (Source_Path (Root, "main.adb"), Main);
      Write_If_Missing (Project_Tools.Files.Join (Project_Tools.Files.Join (Root, "templates"), "layout.html"), "");
      Write_If_Missing (Project_Tools.Files.Join (Project_Tools.Files.Join (Root, "templates"), "home.html"), "");
   end Write_Base_App;

   procedure Command_New (Name : String) is
      Root : constant String := Name;
      App_Name : constant String := Ada.Directories.Simple_Name (Name);
   begin
      Ensure_Tree (Root);
      Write_Base_App (Root, App_Name);
      Write_Static_Runtime (Root);
      Write_If_Missing (Project_Tools.Files.Join (Root, "webframework.toml"), Base_Manifest (App_Name));
      Write_If_Missing (Project_Tools.Files.Join (Root, "alire.toml"), Base_Alire_Manifest (App_Name));
      Print_Info ("created " & Root);
   end Command_New;

   procedure Command_Add_Page (Root : String; Page_Name : String; Route : String) is
      Package_Name : constant String := "App." & To_Package_Name (Page_Name) & "_Page";
      File_Stem : constant String := "app-" & To_File_Stem (Page_Name) & "_page";
      Spec_Path : constant String := Source_Path (Root, File_Stem & ".ads");
      Body_Path : constant String := Source_Path (Root, File_Stem & ".adb");
      Function_Name : constant String := "Render";
      Spec : constant String :=
        "with Web.Request;" & LF
        & "with Web.Response;" & LF
        & LF
        & "package " & Package_Name & " is" & LF
        & "   --  Route handler for the " & Page_Name & " page." & LF
        & "   --  Keep the return value deterministic for easier test coverage." & LF
        & "   --  @param Request HTTP request." & LF
        & "   --  @return HTTP response." & LF
        & "   function " & Function_Name
        & " (Request : Web.Request.Request_Type) return Web.Response.Response_Type;" & LF
        & "end " & Package_Name & ";" & LF;
      Unit_Body : constant String :=
        "with Ada.Exceptions;" & LF
        & "with App.Runtime;" & LF
        & "with Web.Logging;" & LF
        & "with Web.Response;" & LF
        & LF
        & "--  Rendering stays minimal and readable for first-party edits." & LF
        & "package body " & Package_Name & " is" & LF
        & "   --  Render the page and convert any failures into HTTP 500." & LF
        & "   function " & Function_Name
        & " (Request : Web.Request.Request_Type) return Web.Response.Response_Type is" & LF
        & "   begin" & LF
        & "      return App.Runtime.Html_Response (Request, ""<main id="""""
        & To_File_Stem (Page_Name) & """"">" & Page_Name & "</main>"");" & LF
        & "   --  Preserve process availability when a template/markup error happens." & LF
        & "   exception" & LF
        & "      when Error : others =>" & LF
        & "         Web.Logging.Error" & LF
        & "           (""page render failed for " & Page_Name & ": "" &" & LF
        & "              Ada.Exceptions.Exception_Message (Error));" & LF
        & "         return Web.Response.Internal_Server_Error" & LF
        & "           (""Page is temporarily unavailable."");" & LF
        & "   end " & Function_Name & ";" & LF
        & "end " & Package_Name & ";" & LF;
      begin
         Write_If_Missing (Spec_Path, Spec);
      Write_If_Missing (Body_Path, Unit_Body);
      Write_If_Missing
        (Project_Tools.Files.Join (Project_Tools.Files.Join (Root, "templates"), To_File_Stem (Page_Name) & ".html"),
         "<main id=""" & To_File_Stem (Page_Name) & """>" & Page_Name & "</main>" & LF);
      Register_With (Root, "with " & Package_Name & ";");
      Insert_Before_Run
        (Root,
         "   App.Runtime.Get (""" & Route & """, " & Package_Name & "." & Function_Name & "'Access);");
      Add_Manifest_Value (Root, "routes", Route);
      Add_Manifest_Value (Root, "templates", To_File_Stem (Page_Name) & ".html");
      Print_Info ("added page " & Page_Name);
   end Command_Add_Page;

   procedure Command_Add_Handler (Root : String; Action : String) is
      Package_Name : constant String := Handler_Package (Action);
      Function_Name : constant String := Handler_Name (Action);
      Unit_Name : constant String := Package_Name (Package_Name'First + 4 .. Package_Name'Last);
      File_Stem : constant String := "app-" & To_File_Stem (Unit_Name);
      Spec_Path : constant String := Source_Path (Root, File_Stem & ".ads");
      Body_Path : constant String := Source_Path (Root, File_Stem & ".adb");
      Spec : constant String :=
        "with App.State;" & LF
        & "with Web.Events;" & LF
        & "with Web.Patch;" & LF
        & LF
        & "package " & Package_Name & " is" & LF
        & "   --  Handler for websocket action: " & Action & "." & LF
        & "   --  Implement business logic here; return only patch updates." & LF
        & "   --  @param State Session application state." & LF
        & "   --  @param Event Browser event." & LF
        & "   --  @return Patches to send to the browser." & LF
        & "   function " & Function_Name & LF
        & "     (State : in out App.State.State_Type;" & LF
        & "      Event : Web.Events.Event) return Web.Patch.Patch_List;" & LF
        & "end " & Package_Name & ";" & LF;
      Unit_Body : constant String :=
        "with Ada.Exceptions;" & LF
        & "with Web.Logging;" & LF
        & "package body " & Package_Name & " is" & LF
        & "   --  Handle event by updating State and returning a patch list." & LF
        & "   --  Use small, focused patches to keep client updates predictable." & LF
        & "   function " & Function_Name & LF
        & "     (State : in out App.State.State_Type;" & LF
        & "      Event : Web.Events.Event) return Web.Patch.Patch_List" & LF
        & "   is" & LF
        & "      pragma Unreferenced (State, Event);" & LF
        & "   begin" & LF
        & "      return Web.Patch.Single (Web.Patch.Set_Text (""status"", ""ok""));" & LF
        & "   exception" & LF
        & "      when Error : others =>" & LF
        & "         Web.Logging.Error" & LF
        & "           (""" & Handler_Full_Name (Action) & """: "" &" & LF
        & "              Ada.Exceptions.Exception_Message (Error));" & LF
        & "         return Web.Patch.Single" & LF
        & "           (Web.Patch.Set_Text (""status"", ""Unable to process this action.""));" & LF
        & "   end " & Function_Name & ";" & LF
        & "end " & Package_Name & ";" & LF;
      begin
      Write_If_Missing (Spec_Path, Spec);
      Write_If_Missing (Body_Path, Unit_Body);
      Register_With (Root, "with " & Package_Name & ";");
      Insert_Before_Run
        (Root,
         "   App.Runtime.Register (""" & Action & """, " & Handler_Full_Name (Action) & "'Access);");
      Add_Manifest_Value (Root, "actions", Action);
      Add_Manifest_Value (Root, "handlers", Handler_Full_Name (Action));
      Add_Manifest_Value (Root, "patch_targets", "status");
      Print_Info ("added handler " & Action);
   end Command_Add_Handler;

   procedure Command_Add_Feature (Root : String; Name : String) is
      Action : constant String := To_File_Stem (Name) & ".update";
   begin
      Command_Add_Handler (Root, Action);
      Command_Add_Page (Root, Name, "/" & To_File_Stem (Name));
   end Command_Add_Feature;

   procedure Command_Add_Form (Root : String; Name : String) is
      Stem : constant String := To_File_Stem (Name);
      Action : constant String := Stem & ".submit";
   begin
      Command_Add_Handler (Root, Action);
      Add_Manifest_Value (Root, "patch_targets", Stem & "-status");
      Write_If_Missing
        (Project_Tools.Files.Join (Project_Tools.Files.Join (Root, "templates"), Stem & "-form.html"),
         "<form id=""" & Stem & "-form"" data-wf-submit=""" & Action & """>" & LF
         & "  <input name=""name"">" & LF
         & "  <button type=""submit"">Save</button>" & LF
         & "</form>" & LF
         & "<p id=""" & Stem & "-status""></p>" & LF);
      Add_Manifest_Value (Root, "templates", Stem & "-form.html");
      Print_Info ("added form " & Name);
   end Command_Add_Form;

   procedure Report_Missing (Result : in out Check_Result; Message : String) is
   begin
      Result.Errors := Result.Errors + 1;
      Print_Error ("error: " & Message);
   end Report_Missing;

   procedure Report_Warning (Result : in out Check_Result; Message : String) is
   begin
      Result.Warnings := Result.Warnings + 1;
      Print_Warn ("warning: " & Message);
   end Report_Warning;

   procedure Check_File (Result : in out Check_Result; Path : String; Message : String) is
   begin
      if not Project_Tools.Files.File_Exists (Path) then
         Report_Missing (Result, Message & ": " & Path);
      end if;
   end Check_File;

   procedure Check_Directory (Result : in out Check_Result; Path : String; Message : String) is
   begin
      if not Project_Tools.Files.Directory_Exists (Path) then
         Report_Missing (Result, Message & ": " & Path);
      end if;
   end Check_Directory;

   procedure Check_Array_Files
     (Result    : in out Check_Result;
      Root      : String;
      Manifest  : String;
      Key       : String;
      Directory : String)
   is
      Line : constant String := Array_Line (Manifest, Key);
      Cursor : Natural := Line'First;
      Start_Pos : Natural;
      Stop_Pos : Natural;
   begin
      while Cursor <= Line'Last loop
         Start_Pos := Ada.Strings.Fixed.Index (Line (Cursor .. Line'Last), """");
         exit when Start_Pos = 0;
         Stop_Pos := Ada.Strings.Fixed.Index (Line (Start_Pos + 1 .. Line'Last), """");
         exit when Stop_Pos = 0;
         Check_File
           (Result,
            Project_Tools.Files.Join
              (Project_Tools.Files.Join (Root, Directory),
               Line (Start_Pos + 1 .. Stop_Pos - 1)),
            Key & " entry is missing");
         Cursor := Stop_Pos + 1;
      end loop;
   end Check_Array_Files;

   function Tree_Text (Path : String) return String is
      Result : Unbounded_String;
      Search : Ada.Directories.Search_Type;
      Dir_Entry : Ada.Directories.Directory_Entry_Type;
   begin
      if Project_Tools.Files.File_Exists (Path) then
         return Read_File (Path);
      end if;
      if not Project_Tools.Files.Directory_Exists (Path) then
         return "";
      end if;

      Ada.Directories.Start_Search (Search, Path, "");
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Dir_Entry);
         declare
            Name : constant String := Ada.Directories.Simple_Name (Dir_Entry);
            Full : constant String := Project_Tools.Files.Join (Path, Name);
         begin
            if Name /= "." and then Name /= ".." then
               if Ada.Directories.Kind (Dir_Entry) = Ada.Directories.Directory then
                  Append (Result, Tree_Text (Full));
               elsif Ada.Directories.Kind (Dir_Entry) = Ada.Directories.Ordinary_File then
                  Append (Result, Read_File (Full));
               end if;
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
      return To_String (Result);
   exception
      when others =>
         if Ada.Directories.More_Entries (Search) then
            Ada.Directories.End_Search (Search);
         end if;
         return To_String (Result);
   end Tree_Text;

   procedure Check_Array_Values
     (Result   : in out Check_Result;
      Manifest : String;
      Key      : String;
      Content  : String;
      Label    : String)
   is
      Line : constant String := Array_Line (Manifest, Key);
      Cursor : Natural := Line'First;
      Start_Pos : Natural;
      Stop_Pos : Natural;
      Value : Unbounded_String;
   begin
      while Cursor <= Line'Last loop
         Start_Pos := Ada.Strings.Fixed.Index (Line (Cursor .. Line'Last), """");
         exit when Start_Pos = 0;
         Stop_Pos := Ada.Strings.Fixed.Index (Line (Start_Pos + 1 .. Line'Last), """");
         exit when Stop_Pos = 0;
         Value := To_Unbounded_String (Line (Start_Pos + 1 .. Stop_Pos - 1));
         if Project_Tools.Text.Count (Line, """" & To_String (Value) & """") > 1 then
            Report_Missing (Result, "duplicate " & Key & " entry: " & To_String (Value));
         end if;
         if Content'Length > 0 and then not Project_Tools.Text.Contains (Content, To_String (Value)) then
            Report_Missing (Result, Label & " is not referenced: " & To_String (Value));
         end if;
         Cursor := Stop_Pos + 1;
      end loop;
   end Check_Array_Values;

   procedure Check_Manifest_Items
     (Result   : in out Check_Result;
      Root     : String;
      Manifest : String)
   is
      Source_Text : constant String := Tree_Text (Project_Tools.Files.Join (Root, "src"));
      Visible_App_Text : constant String :=
        Tree_Text (Project_Tools.Files.Join (Root, "templates"))
        & Source_Text;
   begin
      if Array_Line (Manifest, "routes")'Length = 0 then
         Report_Missing (Result, "manifest missing routes");
      end if;
      if Array_Line (Manifest, "actions")'Length = 0 then
         Report_Missing (Result, "manifest missing actions");
      end if;
      if Array_Line (Manifest, "handlers")'Length = 0 then
         Report_Missing (Result, "manifest missing handlers");
      end if;
      if not Project_Tools.Text.Contains (Source_Text, "App.Runtime.WebSocket_Handler") then
         Report_Missing (Result, "application does not register App.Runtime websocket handler");
      end if;
      if not Project_Tools.Text.Contains (Source_Text, "App.Runtime.Get")
        and then not Project_Tools.Text.Contains (Source_Text, "Web.Server.Get")
      then
         Report_Missing (Result, "application does not register routes");
      end if;
      if not Project_Tools.Text.Contains (Source_Text, "/health") then
         Report_Warning (Result, "application does not expose a /health route");
      end if;
      if not Project_Tools.Text.Contains (Source_Text, "App.Runtime.Health_Response")
        and then not Project_Tools.Text.Contains (Source_Text, "Web.Server.Health_Response")
      then
         Report_Warning (Result, "application does not expose a health response");
      end if;
      if Array_Has_Values (Manifest, "actions")
        and then not Project_Tools.Text.Contains (Source_Text, "App.Runtime.Register")
      then
         Report_Missing (Result, "application does not register actions");
      end if;
      Check_Array_Values (Result, Manifest, "actions", Source_Text, "action");
      Check_Array_Values (Result, Manifest, "handlers", Source_Text, "handler");
      Check_Array_Values (Result, Manifest, "routes", Source_Text, "route");
      Check_Array_Values (Result, Manifest, "patch_targets", Visible_App_Text, "patch target");
   end Check_Manifest_Items;

   function Has_Main_Program (Root : String) return Boolean is
      Source_Text : constant String := Tree_Text (Project_Tools.Files.Join (Root, "src"));
   begin
      return Project_Tools.Files.File_Exists (Source_Path (Root, "main.adb"))
        or else Project_Tools.Text.Contains (Source_Text, "App.Runtime.Run")
        or else Project_Tools.Text.Contains (Source_Text, "Web.Server.Run");
   end Has_Main_Program;

   function Command_Check (Root : String) return Natural is
      Result : Check_Result;
      Manifest_Path : constant String := Project_Tools.Files.Join (Root, "webframework.toml");
      Manifest : constant String := Read_File (Manifest_Path);
      App_Root : constant String := Scalar_Value (Manifest, "app_root");
   begin
      if App_Root'Length > 0 then
         return Command_Check (Project_Tools.Files.Join (Root, App_Root));
      end if;

      Check_File (Result, Manifest_Path, "manifest is missing");
      Check_Directory (Result, Source_Path (Root, ""), "src directory is missing");
      Check_Directory (Result, Project_Tools.Files.Join (Root, "templates"), "templates directory is missing");
      Check_Directory (Result, Project_Tools.Files.Join (Root, "static"), "static directory is missing");
      if not Has_Main_Program (Root) then
         Report_Missing (Result, "main program is missing");
      end if;
      Check_File (Result, Source_Path (Root, "app-dispatcher.ads"), "dispatcher instantiation is missing");
      Check_File (Result, Source_Path (Root, "app-live.ads"), "live instantiation is missing");
      Check_File
        (Result,
         Project_Tools.Files.Join (Project_Tools.Files.Join (Root, "static"), "webframework.js"),
         "browser runtime is missing");

      if Manifest'Length > 0 then
         Check_Manifest_Items (Result, Root, Manifest);
         Check_Array_Files (Result, Root, Manifest, "templates", "templates");
         Check_Array_Files (Result, Root, Manifest, "static_files", "static");
      end if;

      if Result.Errors = 0 then
         Print_Info ("webframework check: ok");
      else
         Print_Error ("webframework check: failed");
      end if;
      return Result.Errors;
   end Command_Check;

   procedure Usage is
   begin
      Print_Info ("usage:");
      Print_Info ("  webframework new NAME");
      Print_Info ("  webframework add page ROOT NAME ROUTE");
      Print_Info ("  webframework add feature ROOT NAME");
      Print_Info ("  webframework add handler ROOT ACTION");
      Print_Info ("  webframework add form ROOT NAME");
      Print_Info ("  webframework check [ROOT]");
   end Usage;

   function Run return Natural is
      Command : constant String := Arg (1);
      Subcommand : constant String := Arg (2);
   begin
      if Command = "new" and then Arg (2)'Length > 0 then
         Command_New (Arg (2));
         return Exit_OK;
      elsif Command = "add" and then Subcommand = "page" and then Arg (5)'Length > 0 then
         Command_Add_Page (Arg (3), Arg (4), Arg (5));
         return Exit_OK;
      elsif Command = "add" and then Subcommand = "feature" and then Arg (4)'Length > 0 then
         Command_Add_Feature (Arg (3), Arg (4));
         return Exit_OK;
      elsif Command = "add" and then Subcommand = "handler" and then Arg (4)'Length > 0 then
         Command_Add_Handler (Arg (3), Arg (4));
         return Exit_OK;
      elsif Command = "add" and then Subcommand = "form" and then Arg (4)'Length > 0 then
         Command_Add_Form (Arg (3), Arg (4));
         return Exit_OK;
      elsif Command = "check" then
         return Command_Check ((if Arg (2)'Length = 0 then "." else Arg (2)));
      else
         Usage;
         return Exit_Usage_Error;
      end if;
   exception
      when Error : others =>
         Print_Error ("error: " & Ada.Exceptions.Exception_Message (Error));
         return Exit_Failure;
   end Run;
end Webframework_Cli;
