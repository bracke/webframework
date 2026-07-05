with Ada.Strings.Fixed;
with AUnit.Assertions;
with AUnit.Test_Caller;
with Web.Cookie;
with Web.Errors;
with Web.Html;
with Web.Request;
with Web.Response;
with Web.Security;
with Zlib;

package body Web_Core_Tests is
   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;
   use type Zlib.Status_Code;

   function To_Bytes (Value : String) return Zlib.Byte_Array is
   begin
      if Value'Length = 0 then
         return Zlib.Byte_Array'(1 .. 0 => 0);
      end if;

      declare
         Result : Zlib.Byte_Array (0 .. Value'Length - 1);
      begin
         for Offset in Result'Range loop
            Result (Offset) := Zlib.Byte (Character'Pos (Value (Value'First + Offset)));
         end loop;
         return Result;
      end;
   end To_Bytes;

   function To_String (Value : Zlib.Byte_Array) return String is
      Result : String (1 .. Value'Length);
   begin
      for Offset in Value'Range loop
         Result (Offset - Value'First + Result'First) := Character'Val (Value (Offset));
      end loop;
      return Result;
   end To_String;

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test (Suite, Caller.Create ("cookie parsing", Test_Cookie_Parse'Access));
      AUnit.Test_Suites.Add_Test (Suite, Caller.Create ("set-cookie generation", Test_Set_Cookie'Access));
      AUnit.Test_Suites.Add_Test (Suite, Caller.Create ("html helpers", Test_HTML'Access));
      AUnit.Test_Suites.Add_Test (Suite, Caller.Create ("request headers", Test_Request_Headers'Access));
      AUnit.Test_Suites.Add_Test (Suite, Caller.Create ("response serialization", Test_Response'Access));
      AUnit.Test_Suites.Add_Test (Suite, Caller.Create ("security helpers", Test_Security'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("origin validation", Test_Origin_Validation'Access));
   end Add_Tests;

   procedure Test_Cookie_Parse (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Jar : constant Web.Cookie.Cookie_Jar := Web.Cookie.Parse ("a=1; wf_session=abc; theme=dark");
      Duplicate_Jar : constant Web.Cookie.Cookie_Jar := Web.Cookie.Parse ("wf_session=first; wf_session=second");
   begin
      Assert (Web.Cookie.Has (Jar, "wf_session"), "session cookie present");
      Assert (Web.Cookie.Value (Jar, "wf_session") = "abc", "session cookie value");
      Assert (Web.Cookie.Value (Jar, "missing") = "", "missing cookie is empty");
      Assert (Web.Cookie.Value (Duplicate_Jar, "wf_session") = "first", "first duplicate cookie wins");
   end Test_Cookie_Parse;

   procedure Test_Set_Cookie (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Header : constant String :=
        Web.Cookie.Set_Cookie
          ("wf_session",
           "abc",
           Web.Cookie.Cookie_Options'
             (Path      => "/",
              Http_Only => True,
              Secure    => False,
              Same_Site => Web.Cookie.Lax,
              Max_Age   => -1));
      Scoped_Header : constant String :=
        Web.Cookie.Set_Cookie
          (Name      => "prefs",
           Value     => "dark",
           Path      => "/account/settings",
           Http_Only => False,
           Secure    => True,
           Same_Site => Web.Cookie.Strict,
           Max_Age   => 3600);
      Raised : Boolean;
   begin
      Assert (Header = "wf_session=abc; Path=/; HttpOnly; SameSite=Lax", "set-cookie value");
      Assert
        (Scoped_Header = "prefs=dark; Path=/account/settings; Secure; SameSite=Strict; Max-Age=3600",
         "set-cookie explicit path value");

      Raised := False;
      begin
         declare
            Ignored : constant String :=
              Web.Cookie.Set_Cookie
                ("wf_session",
                 "abc" & Character'Val (13) & Character'Val (10) & "Injected: yes",
                 Web.Cookie.Cookie_Options'
                   (Path      => "/",
                    Http_Only => True,
                    Secure    => False,
                    Same_Site => Web.Cookie.Lax,
                    Max_Age   => -1));
         begin
            null;
         end;
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "set-cookie injection rejected");

      Raised := False;
      begin
         declare
            Ignored : constant String :=
              Web.Cookie.Set_Cookie
                ("wf_session",
                 "abc",
                 Web.Cookie.Cookie_Options'
                   (Path      => "/",
                    Http_Only => True,
                    Secure    => False,
                    Same_Site => Web.Cookie.None,
                    Max_Age   => -1));
         begin
            null;
         end;
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "samesite none requires secure cookie");

      Raised := False;
      begin
         declare
            Ignored : constant String :=
              Web.Cookie.Set_Cookie
                (Name  => "prefs",
                 Value => "dark",
                 Path  => "/account" & Character'Val (13) & Character'Val (10) & "Injected: yes");
         begin
            null;
         end;
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "set-cookie path injection rejected");
   end Test_Set_Cookie;

   procedure Test_HTML (Item : in out Fixture) is
      pragma Unreferenced (Item);
   begin
      Assert (Web.Html.Escape_Text ("<b>&</b>") = "&lt;b&gt;&amp;&lt;/b&gt;", "text escaped");
      Assert (Web.Html.Escape_Attribute ("'""&") = "&#39;&quot;&amp;", "attribute escaped");
      Assert (Web.Html.To_String (Web.Html.Trusted ("<p>x</p>")) = "<p>x</p>", "trusted html");
      Assert (Web.Html.Is_Valid_Id ("counter-value"), "valid id");
      Assert (not Web.Html.Is_Valid_Id ("bad id"), "invalid id");
      Assert (Web.Html.Is_Valid_Class ("is-active"), "valid class");
   end Test_HTML;

   procedure Test_Request_Headers (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Request : Web.Request.Request_Type := Web.Request.Create ("GET", "/", "a=1", "body");
   begin
      Web.Request.Set_Header (Request, "Host", "127.0.0.1");
      Assert (Web.Request.Method (Request) = "GET", "method");
      Assert (Web.Request.Path (Request) = "/", "path");
      Assert (Web.Request.Query_String (Request) = "a=1", "query");
      Assert (Web.Request.Request_Body (Request) = "body", "body");
      Assert (Web.Request.Has_Header (Request, "host"), "case-insensitive header exists");
      Assert (Web.Request.Header (Request, "HOST") = "127.0.0.1", "case-insensitive header value");
   end Test_Request_Headers;

   procedure Test_Response (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Response : constant Web.Response.Response_Type := Web.Response.Html ("<p>ok</p>");
      Wire     : constant String := Web.Response.Serialize (Response);
      Mutable  : Web.Response.Response_Type := Web.Response.Text ("ok");
      Gzipped  : constant Web.Response.Response_Type :=
        Web.Response.Compressed (Web.Response.Text ("hello hello hello"), Web.Response.GZip);
      Deflated : constant Web.Response.Response_Type :=
        Web.Response.Compressed (Web.Response.Text ("hello hello hello"), Web.Response.Deflate);
      Varying  : Web.Response.Response_Type := Web.Response.Text ("hello hello hello");
      Already_Varying : Web.Response.Response_Type := Web.Response.Text ("hello hello hello");
      SVG_Response : constant Web.Response.Response_Type :=
        Web.Response.Create (200, "<svg></svg>", "image/svg+xml");
      PNG_Response : constant Web.Response.Response_Type :=
        Web.Response.Create (200, "png-bytes", "image/png");
      Font_Response : constant Web.Response.Response_Type :=
        Web.Response.Create (200, "font-bytes", "font/woff2");
      Encoded_Response : Web.Response.Response_Type := Web.Response.Text ("encoded");
      No_Transform_Response : Web.Response.Response_Type := Web.Response.Text ("no transform");
      Raised   : Boolean := False;
      Status   : Zlib.Status_Code;
   begin
      Assert (Web.Response.Status (Response) = 200, "status");
      Assert (Web.Response.Content_Body (Response) = "<p>ok</p>", "body");
      Assert (Wire'Length > 0, "serialized");
      Assert (Web.Response.Status (Web.Response.Not_Found) = 404, "not found");
      Assert (Web.Response.Status (Web.Response.Bad_Request) = 400, "bad request");
      Assert (Web.Response.Status (Web.Response.Not_Acceptable) = 406, "not acceptable");
      Assert (Web.Response.Is_Compressible (Response), "html response is compressible");
      Assert (Web.Response.Is_Compressible (SVG_Response), "svg response is compressible");
      Assert (not Web.Response.Is_Compressible (PNG_Response), "png response is not compressible");
      Assert (not Web.Response.Is_Compressible (Font_Response), "font response is not compressible");

      Web.Response.Set_Header (Encoded_Response, "Content-Encoding", "gzip");
      Assert
        (not Web.Response.Is_Compressible (Encoded_Response),
         "encoded response is not compressible");

      Web.Response.Set_Header (No_Transform_Response, "Cache-Control", "private, no-transform");
      Assert
        (not Web.Response.Is_Compressible (No_Transform_Response),
         "no-transform response is not compressible");

      begin
         Web.Response.Set_Header
           (Mutable,
            "X-Test",
            "ok" & Character'Val (13) & Character'Val (10) & "Injected: yes");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "response header injection rejected");

      Raised := False;
      begin
         Web.Response.Set_Header (Mutable, "X-Test", "ok" & Character'Val (127));
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "response header delete byte rejected");

      Web.Response.Set_Header (Mutable, "content-type", "text/custom");
      declare
         Custom_Wire : constant String := Web.Response.Serialize (Mutable);
      begin
         Assert (Web.Response.Has_Header (Mutable, "CONTENT-TYPE"), "response header exists");
         Assert (Web.Response.Header (Mutable, "Content-Type") = "text/custom", "response header lookup");
         Assert
           (Ada.Strings.Fixed.Index (Custom_Wire, "Content-Type: text/custom") > 0,
            "content-type replacement is case-insensitive");
         Assert
           (Ada.Strings.Fixed.Index (Custom_Wire, "Content-Type: text/plain") = 0,
            "old content-type header is replaced");
      end;

      Raised := False;
      begin
         Web.Response.Set_Header (Mutable, "Content-Length", "1");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "content-length header is server-owned");

      declare
         Inflated : constant Zlib.Byte_Array :=
           Zlib.Inflate_With_Header (To_Bytes (Web.Response.Content_Body (Gzipped)), Zlib.GZip, Status);
         Gzip_Wire : constant String := Web.Response.Serialize (Gzipped);
      begin
         Assert (Status = Zlib.Ok, "gzip body inflates");
         Assert (To_String (Inflated) = "hello hello hello", "gzip body round trip");
         Assert
           (Ada.Strings.Fixed.Index (Gzip_Wire, "Content-Encoding: gzip") > 0,
            "gzip content encoding");
         Assert
           (Ada.Strings.Fixed.Index (Gzip_Wire, "Vary: Accept-Encoding") > 0,
            "gzip vary header");
      end;

      Web.Response.Set_Header (Varying, "Vary", "Origin");
      declare
         Varying_Wire : constant String :=
           Web.Response.Serialize (Web.Response.Compressed (Varying, Web.Response.GZip));
      begin
         Assert
           (Ada.Strings.Fixed.Index (Varying_Wire, "Vary: Origin, Accept-Encoding") > 0,
            "gzip preserves existing vary");
      end;

      Web.Response.Set_Header (Already_Varying, "Vary", "Accept-Encoding");
      declare
         Already_Wire : constant String :=
           Web.Response.Serialize (Web.Response.Compressed (Already_Varying, Web.Response.GZip));
      begin
         Assert
           (Ada.Strings.Fixed.Index (Already_Wire, "Vary: Accept-Encoding, Accept-Encoding") = 0,
            "gzip does not duplicate vary");
      end;

      declare
         Inflated : constant Zlib.Byte_Array :=
           Zlib.Inflate_With_Header
             (To_Bytes (Web.Response.Content_Body (Deflated)), Zlib.Zlib_Header, Status);
      begin
         Assert (Status = Zlib.Ok, "deflate body inflates");
         Assert (To_String (Inflated) = "hello hello hello", "deflate body round trip");
      end;
   end Test_Response;

   procedure Test_Security (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Request : Web.Request.Request_Type := Web.Request.Create ("GET", "/");

      protected Check_State is
         procedure Mark_Failure;
         function Is_Ok return Boolean;
      private
         Passed : Boolean := True;
      end Check_State;

      protected body Check_State is
         procedure Mark_Failure is
         begin
            Passed := False;
         end Mark_Failure;

         function Is_Ok return Boolean is
         begin
            return Passed;
         end Is_Ok;
      end Check_State;

      task type Session_Id_Worker;

      task body Session_Id_Worker is
      begin
         for Iteration in 1 .. 40 loop
            if not Web.Security.Is_Valid_Session_Id (Web.Security.New_Session_Id) then
               Check_State.Mark_Failure;
            end if;
         end loop;
      exception
         when others =>
            Check_State.Mark_Failure;
      end Session_Id_Worker;
   begin
      Web.Request.Set_Header (Request, "Host", "example.test");
      Assert (Web.Security.Is_Safe_Path ("/static/app.js"), "safe path");
      Assert (not Web.Security.Is_Safe_Path ("../secret"), "path traversal rejected");
      Assert (not Web.Security.Is_Safe_Path ("/static\app.js"), "backslash path rejected");
      Assert
        (not Web.Security.Is_Safe_Path ("/static/" & Character'Val (127) & "app.js"),
         "delete control path rejected");
      Assert (Web.Security.New_Session_Id'Length = 32, "session id length");
      Assert (Web.Security.Is_Valid_Session_Id (Web.Security.New_Session_Id), "session id format");
      Assert
        (not Web.Security.Is_Valid_Session_Id ("../../not-a-session"),
         "invalid session id rejected");

      declare
         Workers : array (1 .. 8) of Session_Id_Worker;
      begin
         null;
      end;

      Assert (Check_State.Is_Ok, "concurrent session ids are valid");
      Assert (Web.Security.Require_Allowed_Origin (Request, "example.test"), "host allowed");
      Assert (not Web.Security.Require_Allowed_Origin (Request, "other.test"), "host rejected");
   end Test_Security;

   procedure Test_Origin_Validation (Item : in out Fixture) is
      pragma Unreferenced (Item);

      Request : Web.Request.Request_Type := Web.Request.Create ("GET", "/");
   begin
      Web.Request.Set_Header (Request, "Host", "Example.Test:8443");
      Assert
        (Web.Security.Require_Allowed_Origin (Request, "example.test:8443"),
         "host authority is case-insensitive");
      Assert
        (not Web.Security.Require_Allowed_Origin (Request, "example.test"),
         "host port must match");

      Web.Request.Set_Header (Request, "Origin", "https://Example.Test:8443");
      Assert
        (Web.Security.Require_Allowed_Origin (Request, "https://example.test:8443"),
         "exact origin allowed");
      Assert
        (not Web.Security.Require_Allowed_Origin (Request, "http://example.test:8443"),
         "origin scheme must match");
      Assert
        (Web.Security.Require_Allowed_Origin (Request, "example.test:8443"),
         "host-only policy compares origin authority exactly");
      Assert
        (not Web.Security.Require_Allowed_Origin (Request, "ample.test:8443"),
         "substring origin does not match");

      Web.Request.Set_Header (Request, "Origin", "https://example.test:8443/path");
      Assert
        (not Web.Security.Require_Allowed_Origin (Request, "https://example.test:8443"),
         "origin with path rejected");

      Web.Request.Set_Header (Request, "Origin", "https://user@example.test:8443");
      Assert
        (not Web.Security.Require_Allowed_Origin (Request, "https://example.test:8443"),
         "origin userinfo rejected");

      Web.Request.Set_Header (Request, "Origin", "null");
      Assert
        (not Web.Security.Require_Allowed_Origin (Request, "example.test"),
         "null origin rejected");

      Web.Request.Set_Header (Request, "Origin", "https://[2001:db8::1]:9443");
      Assert
        (Web.Security.Require_Allowed_Origin (Request, "https://[2001:db8::1]:9443"),
         "ipv6 origin accepted");
      Assert
        (not Web.Security.Require_Allowed_Origin (Request, "https://[2001:db8::2]:9443"),
         "different ipv6 origin rejected");
   end Test_Origin_Validation;
end Web_Core_Tests;
