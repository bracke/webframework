with Ada.Strings.Unbounded;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with App.Auth;
with App.Runtime;
with App.State;
with App.Templates;
with Templates.Values;
with Web.Html;
with Web.Server;
with Web.Logging;
with Web.Response;
with Web.Request;

package body App.Pages is
   use Ada.Strings.Unbounded;

   function Home_Content return String is
      use Standard.Templates.Values;

      Home_Context    : Value := Object;
      Counter_Context : Value := Object;
      Content         : Unbounded_String;
      Todo_Content    : Unbounded_String;
   begin
      --  Build fragment contexts in a single render pass to keep output stable.
      Set (Home_Context, "title", String_Item ("Ada Webframework Example"));
      Set (Counter_Context, "counter", String_Item ("0"));

      --  Load the base page and compose each fragment in deterministic order.
      Content := To_Unbounded_String (App.Templates.Render ("home.html", Home_Context));
      Todo_Content :=
        To_Unbounded_String
          (App.Templates.Replace_Marker
             (App.Templates.Render ("todo.html", Object),
              "<!-- wf:todos -->",
              App.Templates.Render_Todo_Items));
      Content :=
        To_Unbounded_String
          (App.Templates.Replace_Marker
             (To_String (Content),
              "<!-- wf:counter -->",
              App.Templates.Render ("counter.html", Counter_Context)));
      Content :=
        To_Unbounded_String
          (App.Templates.Replace_Marker
             (To_String (Content),
              "<!-- wf:profile -->",
              App.Templates.Render ("profile.html", Object)));
      Content :=
        To_Unbounded_String
          (App.Templates.Replace_Marker
             (To_String (Content),
              "<!-- wf:todo -->",
              To_String (Todo_Content)));

      return To_String (Content);
   end Home_Content;

   --  Type to hold authentication data for state updates
   type Auth_Data is record
      User_Id : Natural;
      Username : String (1 .. 50) := (others => ' ');
   end record;

   --  Global variable to pass auth data to state processor
   --  Note: This is a temporary workaround. In a real application, use a better design.
   Current_Auth_Data : Auth_Data;

   --  Global variable to store authentication check result
   Is_Authenticated_Result : Boolean := False;

   --  State process for checking authentication
   procedure Check_Auth_Process (State : in out App.State.App_State) is
   begin
      Is_Authenticated_Result := App.State.Is_Authenticated (State);
   end Check_Auth_Process;

   function Home (Request : Web.Request.Request_Type) return Web.Response.Response_Type is
      use Standard.Templates.Values;
      Context : Value := Object;
      Page    : Unbounded_String;
      Session_Id : constant String := App.Runtime.Find_Or_Create_Session (Request);
   begin
      --  Check if user is authenticated
      --  Always check authentication since we created/ensured a session above
      Is_Authenticated_Result := False;
      App.Runtime.With_State (Session_Id, Check_Auth_Process'Access);
      
      if not Is_Authenticated_Result then
         --  User not authenticated, redirect to login
         return Redirect_To_Login (Request, Session_Id);
      end if;

      --  Build the full HTML page through templates and inject the composed body fragment.
      Set (Context, "title", String_Item ("Ada Webframework Example"));
      Page := To_Unbounded_String (App.Templates.Render ("layout.html", Context));
      
      --  Add navigation bar for authenticated pages
      declare
         Nav_Bar : constant String := 
           "<header><nav>" &
           "<a href=""/"" class=""nav-home"">Home</a>" &
           "<button id=""logout-btn"" class=""nav-logout"" onclick=""logout()"">Logout</button>" &
           "</nav></header>" &
           "<script>" &
           "function logout(){fetch(" & 
           "'/api/logout',{method:'POST',credentials:'include'})" &
           ".then(r=>{if(r.ok){window.location.href='/login'}})" &
           ".catch(e=>console.error('Logout failed:',e))}</script>";
      begin
         --  Insert nav bar before the main content
         Page := To_Unbounded_String
           (App.Templates.Replace_Marker
              (To_String (Page),
               "<main>",
               Nav_Bar & "<main>"));
      end;
      
      Page :=
        To_Unbounded_String
          (App.Templates.Replace_Marker
             (To_String (Page),
              "<!-- wf:body -->",
              Home_Content));

      --  Ensure cookie-backed session response is used for /, so websocket state is consistent.
      return App.Runtime.Html_Response (Request, To_String (Page));
      exception
         when Error : others =>
            --  Keep route stable and return explicit HTTP 500 on any rendering failure.
            Web.Logging.Error
              ("home route render failed: " & Ada.Exceptions.Exception_Message (Error));
         return Web.Response.Internal_Server_Error;
   end Home;

   function Health (Request : Web.Request.Request_Type) return Web.Response.Response_Type is
      pragma Unreferenced (Request);
   begin
      --  Health is intentionally delegated to framework helper for compatibility
      --  with orchestration and smoke checks.
      return Web.Server.Health_Response;
   end Health;

   function Error_Not_Found
     (Request : Web.Request.Request_Type;
      Status  : Positive;
      Detail  : String) return Web.Response.Response_Type
   is
      pragma Unreferenced (Status);
      pragma Unreferenced (Detail);
      Path : constant String := Web.Request.Path (Request);
      Escaped_Path : constant String :=
        Web.Html.Escape_Text ((if Path'Length = 0 then "/" else Path));
   begin
      return
        Web.Response.Html
          ("<!doctype html>"
           & "<html><head><title>Page not found</title></head>"
           & "<body><h1>Page not found</h1><p>Path: "
           & Escaped_Path
           & "</p></body></html>");
   end Error_Not_Found;

   function Error_Bad_Request
     (Request : Web.Request.Request_Type;
      Status  : Positive;
      Detail  : String) return Web.Response.Response_Type
   is
      pragma Unreferenced (Status);
      pragma Unreferenced (Request);
      Detail_Line : constant String :=
        (if Detail'Length = 0
         then ""
         else "<p>" & Web.Html.Escape_Text (Detail) & "</p>");
   begin
      return
        Web.Response.Html
          ("<!doctype html>"
           & "<html><head><title>Bad request</title></head>"
           & "<body><h1>Bad request</h1>" & Detail_Line & "</body></html>");
   end Error_Bad_Request;

   function Error_Server
     (Request : Web.Request.Request_Type;
      Status  : Positive;
      Detail  : String) return Web.Response.Response_Type
   is
      pragma Unreferenced (Request);
      pragma Unreferenced (Status);
      Detail_Line : constant String :=
        (if Detail'Length = 0
         then ""
         else "<p>" & Web.Html.Escape_Text (Detail) & "</p>");
   begin
      return
        Web.Response.Html
          ("<!doctype html>"
           & "<html><head><title>Server error</title></head>"
           & "<body><h1>Server error</h1>" & Detail_Line
           & "</body></html>");
   end Error_Server;

   --  State process for setting authentication
   procedure Set_Auth_Process (State : in out App.State.App_State) is
   begin
      App.State.Set_Authenticated (State, Current_Auth_Data.User_Id, Current_Auth_Data.Username);
   end Set_Auth_Process;

   --  State process for clearing authentication
   procedure Clear_Auth_Process (State : in out App.State.App_State) is
   begin
      App.State.Clear_Authentication (State);
   end Clear_Auth_Process;

   --  Parse form data from request content (application/x-www-form-urlencoded)
   procedure Parse_Form_Data
     (Content : String;
      Username : out Unbounded_String;
      Password : out Unbounded_String) is
   begin
      Username := To_Unbounded_String ("");
      Password := To_Unbounded_String ("");

      --  Simple parsing for username=value&password=value
      declare
         Username_Start : constant Natural := Ada.Strings.Fixed.Index (Content, "username=") + 9;
         Username_End : Natural;
         Password_Start : constant Natural := Ada.Strings.Fixed.Index (Content, "password=") + 9;
      begin
         if Username_Start > 9 and Username_Start <= Content'Last then
            Username_End := Ada.Strings.Fixed.Index (Content, "&", Username_Start);
            if Username_End = 0 then
               Username_End := Content'Last + 1;
            end if;
            Username := To_Unbounded_String (Content (Username_Start .. Username_End - 1));
         end if;

         if Password_Start > 9 and Password_Start <= Content'Last then
            declare
               Password_End : Natural := Ada.Strings.Fixed.Index (Content, "&", Password_Start);
            begin
               if Password_End = 0 then
                  Password_End := Content'Last + 1;
               end if;
               Password := To_Unbounded_String (Content (Password_Start .. Password_End - 1));
            end;
         end if;
      end;
   end Parse_Form_Data;

   --  Render the login page with the login form template.
   function Login (Request : Web.Request.Request_Type) return Web.Response.Response_Type is
      Context : Standard.Templates.Values.Value := Standard.Templates.Values.Object;
      Page    : Unbounded_String;
   begin
      --  Build the full HTML page through templates and inject the login form.
      Standard.Templates.Values.Set
        (Context, "title", Standard.Templates.Values.String_Item ("Login - Ada Webframework Example"));
      Page := To_Unbounded_String (App.Templates.Render ("layout.html", Context));
      Page := To_Unbounded_String
        (App.Templates.Replace_Marker
           (To_String (Page),
            "<!-- wf:body -->",
            App.Templates.Render ("login.html", Standard.Templates.Values.Object)));

      --  Return HTML response with session cookie
      return App.Runtime.Html_Response (Request, To_String (Page));
      exception
         when Error : others =>
            Web.Logging.Error
              ("login route render failed: " & Ada.Exceptions.Exception_Message (Error));
            return Web.Response.Internal_Server_Error;
   end Login;

   --  Handle login API endpoint.
   function Api_Login (Request : Web.Request.Request_Type) return Web.Response.Response_Type is
      use App.Auth;
      Body_Content : constant String := Web.Request.Request_Body (Request);
      Username : Unbounded_String;
      Password : Unbounded_String;
      User_Id : Natural;
      Result : Auth_Result;
      Session_Id : constant String := App.Runtime.Find_Or_Create_Session (Request);
      Username_Str : String (1 .. 50) := (others => ' ');
   begin
      --  Parse username and password from form data
      Parse_Form_Data (Body_Content, Username, Password);

      if Length (Username) = 0 or Length (Password) = 0 then
         return Web.Response.Bad_Request ("Username and password are required");
      end if;

      --  Authenticate user
      Authenticate (To_String (Username), To_String (Password), User_Id, Result);

      if Result = Success then
         --  Set authentication in session state
         --  Copy username to fixed-length string
         declare
            Source : constant String := To_String (Username);
            Length : constant Natural := Source'Length;
         begin
            if Length <= Username_Str'Length then
               Username_Str (1 .. Length) := Source;
            end if;
            Current_Auth_Data := Auth_Data'(User_Id => User_Id, Username => Username_Str);
            App.Runtime.With_State (Session_Id, Set_Auth_Process'Access);
            --  Return success with session cookie
            return App.Runtime.Html_Response (Session_Id, "{""status"": ""success""}");
         end;
      else
         --  Authentication failed
         return Web.Response.Unauthorized ("Invalid username or password");
      end if;
      exception
         when Error : others =>
            Web.Logging.Error
              ("login API failed: " & Ada.Exceptions.Exception_Message (Error));
            return Web.Response.Internal_Server_Error;
   end Api_Login;

   --  Handle logout API endpoint.
   function Api_Logout (Request : Web.Request.Request_Type) return Web.Response.Response_Type is
      Session_Id : constant String := App.Runtime.Require_Session (Request);
   begin
      if Session_Id'Length > 0 then
         --  Clear authentication from session state
         App.Runtime.With_State (Session_Id, Clear_Auth_Process'Access);
      end if;

      --  Return success response
      return App.Runtime.Html_Response (Session_Id, "{""status"": ""success""}");
      exception
         when Error : others =>
            Web.Logging.Error
              ("logout API failed: " & Ada.Exceptions.Exception_Message (Error));
            return Web.Response.Internal_Server_Error;
   end Api_Logout;

   --  Redirect to login page.
   function Redirect_To_Login
     (Request : Web.Request.Request_Type; Session_Id : String) return Web.Response.Response_Type is
      pragma Unreferenced (Request);
   begin
      --  Return a redirect response to /login with session cookie
      return App.Runtime.Html_Response
        (Session_Id,
         "<!doctype html>"
         & "<html><head><meta http-equiv=""refresh"" content=""0;url=/login"">"
         & "<title>Redirecting...</title></head>"
         & "<body><p>Please <a href=""/login"">login</a>.</p></body></html>");
   end Redirect_To_Login;
end App.Pages;
