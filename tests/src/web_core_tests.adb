with Ada.Strings.Fixed;
with AUnit.Assertions;
with AUnit.Test_Caller;
with Web.Cookie;
with Web.Errors;
with Web.Html;
with Web.Logging;
with Web.Request;
with Web.Response;
with Web.Security;
with Zlib;

package body Web_Core_Tests is
   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;
   use type Web.Logging.Level_Type;
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
      AUnit.Test_Suites.Add_Test (Suite, Caller.Create ("logging configuration", Test_Logging'Access));
      AUnit.Test_Suites.Add_Test (Suite, Caller.Create ("security helpers", Test_Security'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("origin validation", Test_Origin_Validation'Access));
   end Add_Tests;

   procedure Test_Cookie_Parse (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Jar : constant Web.Cookie.Cookie_Jar := Web.Cookie.Parse ("a=1; wf_session=abc; theme=dark");
      Duplicate_Jar : constant Web.Cookie.Cookie_Jar := Web.Cookie.Parse ("wf_session=first; wf_session=second");
      Control_Jar : constant Web.Cookie.Cookie_Jar :=
        Web.Cookie.Parse ("safe=ok; bad=ab" & Character'Val (128) & "cd");
      Delimiter_Jar : constant Web.Cookie.Cookie_Jar :=
        Web.Cookie.Parse ("safe=ok; comma=a,b; quoted=""x""; slash=a\b");
      Raised : Boolean := False;
   begin
      Assert (Web.Cookie.Has (Jar, "wf_session"), "session cookie present");
      Assert (Web.Cookie.Value (Jar, "wf_session") = "abc", "session cookie value");
      Assert (Web.Cookie.Value (Jar, "missing") = "", "missing cookie is empty");
      Assert (Web.Cookie.Value (Duplicate_Jar, "wf_session") = "first", "first duplicate cookie wins");
      Assert (Web.Cookie.Count (Duplicate_Jar, "wf_session") = 2, "duplicate cookie count");
      Assert (Web.Cookie.Count (Duplicate_Jar, "missing") = 0, "missing cookie count");
      Assert (Web.Cookie.Value (Control_Jar, "safe") = "ok", "safe cookie parsed");
      Assert (not Web.Cookie.Has (Control_Jar, "bad"), "c1 cookie value ignored");
      Assert (Web.Cookie.Value (Delimiter_Jar, "safe") = "ok", "delimiter safe cookie parsed");
      Assert (not Web.Cookie.Has (Delimiter_Jar, "comma"), "comma cookie value ignored");
      Assert (not Web.Cookie.Has (Delimiter_Jar, "quoted"), "quoted cookie value ignored");
      Assert (not Web.Cookie.Has (Delimiter_Jar, "slash"), "backslash cookie value ignored");

      begin
         Assert (not Web.Cookie.Has (Jar, "bad name"), "unreachable");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "invalid cookie lookup name rejected");

      Raised := False;
      begin
         Assert (Web.Cookie.Value (Jar, "bad;name") = "", "unreachable");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "invalid cookie value lookup name rejected");
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
                (Name    => "prefs",
                 Value   => "dark",
                 Path    => "/",
                 Max_Age => -2);
         begin
            null;
         end;
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "set-cookie invalid negative max-age rejected");

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
                 "abc" & Character'Val (128),
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
      Assert (Raised, "set-cookie c1 value rejected");

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

      Raised := False;
      begin
         declare
            Ignored : constant String :=
              Web.Cookie.Set_Cookie (Name => "prefs", Value => "dark", Path => "relative");
         begin
            null;
         end;
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "set-cookie relative path rejected");

      Raised := False;
      begin
         declare
            Ignored : constant String :=
              Web.Cookie.Set_Cookie (Name => "prefs", Value => "dark", Path => "/%2e%2e/account");
         begin
            null;
         end;
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "set-cookie encoded traversal path rejected");
   end Test_Set_Cookie;

   procedure Test_HTML (Item : in out Fixture) is
      pragma Unreferenced (Item);
   begin
      Assert (Web.Html.Escape_Text ("<b>&</b>") = "&lt;b&gt;&amp;&lt;/b&gt;", "text escaped");
      Assert (Web.Html.Escape_Attribute ("'""&") = "&#39;&quot;&amp;", "attribute escaped");
      Assert
        (Web.Html.Escape_Text ("a" & Character'Val (0) & Character'Val (127) & Character'Val (128))
         = "a&#0;&#127;&#128;",
         "text controls escaped");
      Assert
        (Web.Html.Escape_Attribute ("x" & Character'Val (10) & "y")
         = "x&#10;y",
         "attribute controls escaped");
      Assert (Web.Html.To_String (Web.Html.Trusted ("<p>x</p>")) = "<p>x</p>", "trusted html");
      Assert (Web.Html.Is_Valid_Id ("counter-value"), "valid id");
      Assert (not Web.Html.Is_Valid_Id ("bad id"), "invalid id");
      Assert (Web.Html.Is_Valid_Class ("is-active"), "valid class");
   end Test_HTML;

   procedure Test_Request_Headers (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Request : Web.Request.Request_Type := Web.Request.Create ("GET", "/", "a=1", "body");
      Raised  : Boolean := False;
      Seen_Method : Boolean := False;
      Seen_Path   : Boolean := False;
      Seen_Query  : Boolean := False;
      Seen_Header : Boolean := False;
      Seen_Body   : Boolean := False;

      procedure Check_Method (Value : String);
      procedure Check_Path (Value : String);
      procedure Check_Query (Value : String);
      procedure Check_Header (Value : String);
      procedure Check_Body (Value : String);

      procedure Check_Method (Value : String) is
      begin
         Seen_Method := Value = "GET";
      end Check_Method;

      procedure Check_Path (Value : String) is
      begin
         Seen_Path := Value = "/";
      end Check_Path;

      procedure Check_Query (Value : String) is
      begin
         Seen_Query := Value = "a=1";
      end Check_Query;

      procedure Check_Header (Value : String) is
      begin
         Seen_Header := Value = "example.test";
      end Check_Header;

      procedure Check_Body (Value : String) is
      begin
         Seen_Body := Value = "body";
      end Check_Body;

      procedure With_Method is new Web.Request.With_Method (Check_Method);
      procedure With_Path is new Web.Request.With_Path (Check_Path);
      procedure With_Query is new Web.Request.With_Query_String (Check_Query);
      procedure With_Header is new Web.Request.With_Header (Check_Header);
      procedure With_Body is new Web.Request.With_Body (Check_Body);
   begin
      Web.Request.Set_Header (Request, "Host", "127.0.0.1");
      Web.Request.Set_Header (Request, "HOST", "example.test");
      Assert (Web.Request.Method (Request) = "GET", "method");
      Assert (Web.Request.Path (Request) = "/", "path");
      Assert (Web.Request.Path_Is (Request, "/"), "path predicate");
      Assert (Web.Request.Query_String (Request) = "a=1", "query");
      Assert (Web.Request.Request_Body (Request) = "body", "body");
      Assert (Web.Request.Has_Header (Request, "host"), "case-insensitive header exists");
      Assert (Web.Request.Header (Request, "host") = "example.test", "case-insensitive header replacement");
      With_Method (Request);
      With_Path (Request);
      With_Query (Request);
      With_Header (Request, "Host");
      With_Body (Request);
      Assert (Seen_Method, "method callback accessor");
      Assert (Seen_Path, "path callback accessor");
      Assert (Seen_Query, "query callback accessor");
      Assert (Seen_Header, "header callback accessor");
      Assert (Seen_Body, "body callback accessor");

      begin
         declare
            Ignored : constant Web.Request.Request_Type := Web.Request.Create ("BAD METHOD", "/");
         begin
            null;
         end;
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "direct invalid request method rejected");

      Raised := False;
      begin
         declare
            Ignored : constant Web.Request.Request_Type := Web.Request.Create ("GET", "relative");
         begin
            null;
         end;
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "direct relative request path rejected");

      Raised := False;
      begin
         declare
            Ignored : constant Web.Request.Request_Type := Web.Request.Create ("GET", "/%2e%2e/app");
         begin
            null;
         end;
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "direct encoded traversal request path rejected");

      Raised := False;
      begin
         declare
            Ignored : constant Web.Request.Request_Type :=
              Web.Request.Create ("GET", "/", "a=1" & Character'Val (128));
         begin
            null;
         end;
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "direct invalid request query rejected");

      Raised := False;
      begin
         Assert (not Web.Request.Has_Header (Request, "Bad Header"), "unreachable");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "request header lookup name with space rejected");

      Raised := False;
      begin
         Assert (Web.Request.Header (Request, "") = "", "unreachable");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "empty request header lookup name rejected");

      Raised := False;
      begin
         Web.Request.Set_Header (Request, "Bad Header", "ok");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "request header name with space rejected");

      Raised := False;
      begin
         Web.Request.Set_Header (Request, "", "ok");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "empty request header name rejected");

      Raised := False;
      begin
         Web.Request.Set_Header (Request, "X-Test", "ok" & Character'Val (9));
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "request header tab rejected");

      Raised := False;
      begin
         Web.Request.Set_Header (Request, "X-Test", "ok" & Character'Val (128));
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "request header c1 control rejected");
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
      Manual_Varying : Web.Response.Response_Type := Web.Response.Text ("manual vary");
      Connection_Response : Web.Response.Response_Type := Web.Response.Text ("connection");
      SVG_Response : constant Web.Response.Response_Type :=
        Web.Response.Create (200, "<svg></svg>", "image/svg+xml");
      PNG_Response : constant Web.Response.Response_Type :=
        Web.Response.Create (200, "png-bytes", "image/png");
      Font_Response : constant Web.Response.Response_Type :=
        Web.Response.Create (200, "font-bytes", "font/woff2");
      Encoded_Response : Web.Response.Response_Type := Web.Response.Text ("encoded");
      Content_Encoding_Response : Web.Response.Response_Type := Web.Response.Text ("content encoding");
      No_Transform_Response : Web.Response.Response_Type := Web.Response.Text ("no transform");
      Cache_Control_Response : Web.Response.Response_Type := Web.Response.Text ("cache control");
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

      begin
         declare
            Ignored : constant Web.Response.Response_Type :=
              Web.Response.Create (200, "", "text plain");
         begin
            null;
         end;
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "invalid response content type rejected");

      Raised := False;
      begin
         declare
            Ignored : constant Web.Response.Response_Type :=
              Web.Response.Create (200, "", "text/plain; charset");
         begin
            null;
         end;
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "malformed content type parameter rejected");

      Raised := False;
      begin
         declare
            Ignored : constant Web.Response.Response_Type := Web.Response.Create (99);
         begin
            null;
         end;
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "low response status rejected");

      Raised := False;
      begin
         declare
            Ignored : constant Web.Response.Response_Type := Web.Response.Create (600);
         begin
            null;
         end;
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "high response status rejected");

      Web.Response.Set_Header (Encoded_Response, "Content-Encoding", "gzip");
      Assert
        (not Web.Response.Is_Compressible (Encoded_Response),
         "encoded response is not compressible");

      Web.Response.Set_Header (Content_Encoding_Response, "Content-Encoding", "custom-coding");
      Assert
        (Web.Response.Header (Content_Encoding_Response, "Content-Encoding") = "custom-coding",
         "content encoding token accepted");

      Raised := False;
      begin
         Web.Response.Set_Header (Content_Encoding_Response, "Content-Encoding", "");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "empty content encoding rejected");

      Raised := False;
      begin
         Web.Response.Set_Header (Content_Encoding_Response, "Content-Encoding", "bad coding");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "content encoding token with space rejected");

      Raised := False;
      begin
         Web.Response.Set_Header (Content_Encoding_Response, "Content-Encoding", "gzip, br");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "multiple content encodings rejected");

      begin
         declare
            Ignored : constant Web.Response.Response_Type :=
              Web.Response.Compressed (Encoded_Response, Web.Response.GZip);
         begin
            null;
         end;
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "already encoded response compression rejected");

      Web.Response.Set_Header (No_Transform_Response, "Cache-Control", "private, no-transform");
      Assert
        (not Web.Response.Is_Compressible (No_Transform_Response),
         "no-transform response is not compressible");

      Web.Response.Set_Header
        (Cache_Control_Response,
         "Cache-Control",
         "private, no-transform, max-age=60, stale-while-revalidate=30");
      Assert
        (Web.Response.Header (Cache_Control_Response, "Cache-Control") =
         "private, no-transform, max-age=60, stale-while-revalidate=30",
         "cache-control directives accepted");

      Web.Response.Set_Header (Cache_Control_Response, "Cache-Control", "private=""Set-Cookie""");
      Assert
        (Web.Response.Header (Cache_Control_Response, "Cache-Control") = "private=""Set-Cookie""",
         "cache-control quoted value accepted");

      Raised := False;
      begin
         Web.Response.Set_Header (Cache_Control_Response, "Cache-Control", "");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "empty cache-control rejected");

      Raised := False;
      begin
         Web.Response.Set_Header (Cache_Control_Response, "Cache-Control", "private,");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "cache-control empty trailing directive rejected");

      Raised := False;
      begin
         Web.Response.Set_Header (Cache_Control_Response, "Cache-Control", "bad directive");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "cache-control directive with space rejected");

      Raised := False;
      begin
         Web.Response.Set_Header (Cache_Control_Response, "Cache-Control", "max-age=");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "cache-control empty value rejected");

      Raised := False;
      begin
         declare
            Ignored : constant Web.Response.Response_Type :=
              Web.Response.Compressed (No_Transform_Response, Web.Response.GZip);
         begin
            null;
         end;
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "no-transform response compression rejected");

      Raised := False;
      begin
         declare
            Ignored : constant Web.Response.Response_Type :=
              Web.Response.Compressed (PNG_Response, Web.Response.GZip);
         begin
            null;
         end;
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "binary response compression rejected");

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
         Web.Response.Set_Header (Mutable, "X-Test", "ok" & Character'Val (9));
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "response header tab rejected");

      Raised := False;
      begin
         Web.Response.Set_Header (Mutable, "X-Test", "ok" & Character'Val (127));
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "response header delete byte rejected");

      Raised := False;
      begin
         Web.Response.Set_Header (Mutable, "X-Test", "ok" & Character'Val (128));
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "response header c1 control rejected");

      Raised := False;
      begin
         Web.Response.Set_Header (Mutable, "Content-Type", "bad");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "invalid replacement content type rejected");

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
         Assert (not Web.Response.Has_Header (Mutable, "Bad Header"), "unreachable");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "response header lookup name with space rejected");

      Raised := False;
      begin
         Assert (Web.Response.Header (Mutable, "") = "", "unreachable");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "empty response header lookup name rejected");

      Raised := False;
      begin
         Web.Response.Set_Header (Mutable, "Content-Length", "1");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "content-length header is server-owned");

      Web.Response.Set_Header (Connection_Response, "Connection", "keep-alive, Upgrade");
      Assert
        (Web.Response.Header (Connection_Response, "Connection") = "keep-alive, Upgrade",
         "connection token list accepted");

      Raised := False;
      begin
         Web.Response.Set_Header (Connection_Response, "Connection", "bad token");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "connection token with space rejected");

      Raised := False;
      begin
         Web.Response.Set_Header (Connection_Response, "Connection", ", close");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "connection empty leading item rejected");

      Raised := False;
      begin
         Web.Response.Set_Header (Connection_Response, "Connection", "close,");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "connection empty trailing item rejected");

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

      Web.Response.Ensure_Vary (Manual_Varying, "Origin");
      Web.Response.Ensure_Vary (Manual_Varying, "Accept-Encoding");
      Web.Response.Ensure_Vary (Manual_Varying, "accept-encoding");
      declare
         Manual_Wire : constant String := Web.Response.Serialize (Manual_Varying);
      begin
         Assert
           (Ada.Strings.Fixed.Index (Manual_Wire, "Vary: Origin, Accept-Encoding") > 0,
            "manual vary preserves and appends token");
         Assert
           (Ada.Strings.Fixed.Index (Manual_Wire, "Accept-Encoding, accept-encoding") = 0,
            "manual vary does not duplicate case-insensitive token");
      end;

      Raised := False;
      begin
         Web.Response.Ensure_Vary (Manual_Varying, "Bad Token");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "vary token with space rejected");

      Raised := False;
      begin
         Web.Response.Ensure_Vary (Manual_Varying, "Bad,Token");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "vary token with comma rejected");

      Web.Response.Set_Header (Manual_Varying, "Vary", "Origin, Accept-Encoding");
      Assert
        (Web.Response.Header (Manual_Varying, "Vary") = "Origin, Accept-Encoding",
         "valid vary list accepted");

      Web.Response.Set_Header (Manual_Varying, "Vary", "*");
      Assert (Web.Response.Header (Manual_Varying, "Vary") = "*", "vary wildcard accepted");

      Raised := False;
      begin
         Web.Response.Set_Header (Manual_Varying, "Vary", "*, Origin");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "vary wildcard mixed with tokens rejected");

      Raised := False;
      begin
         Web.Response.Set_Header (Manual_Varying, "Vary", "Origin, ");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "vary list empty item rejected");

      Raised := False;
      begin
         Web.Response.Set_Header (Manual_Varying, "Vary", "Bad Token");
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "vary list invalid token rejected");

      declare
         Inflated : constant Zlib.Byte_Array :=
           Zlib.Inflate_With_Header
             (To_Bytes (Web.Response.Content_Body (Deflated)), Zlib.Zlib_Header, Status);
      begin
         Assert (Status = Zlib.Ok, "deflate body inflates");
         Assert (To_String (Inflated) = "hello hello hello", "deflate body round trip");
      end;
   end Test_Response;

   procedure Test_Logging (Item : in out Fixture) is
      pragma Unreferenced (Item);
   begin
      Web.Logging.Set_Minimum_Level (Web.Logging.Warn_Level);
      Web.Logging.Set_Structured (True);
      Assert (Web.Logging.Minimum_Level = Web.Logging.Warn_Level, "minimum logging level set");
      Assert (Web.Logging.Structured, "structured logging enabled");

      Web.Logging.Set_Minimum_Level (Web.Logging.Debug_Level);
      Web.Logging.Set_Structured (False);
      Assert (Web.Logging.Minimum_Level = Web.Logging.Debug_Level, "minimum logging level reset");
      Assert (not Web.Logging.Structured, "structured logging disabled");
   end Test_Logging;

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
      Assert
        (not Web.Security.Is_Safe_Path ("/static/" & Character'Val (128) & "app.js"),
         "c1 control path rejected");
      Assert
        (not Web.Security.Is_Safe_Decoded_Path ("/static/%2e%2e/app.js"),
         "decoded traversal path rejected");
      Assert
        (not Web.Security.Is_Safe_Decoded_Path ("/static/%80/app.js"),
         "decoded c1 control path rejected");
      Assert
        (not Web.Security.Is_Safe_Decoded_Path ("/static%5capp.js"),
         "decoded backslash path rejected");
      Assert
        (not Web.Security.Is_Safe_Decoded_Path ("/static%2fapp.js"),
         "decoded slash path rejected");
      Assert
        (not Web.Security.Is_Safe_Decoded_Path ("/static/%zz/app.js"),
         "invalid percent escape rejected");
      Assert
        (not Web.Security.Is_Safe_Decoded_Path ("//static/app.js"),
         "decoded double slash path rejected");
      Assert
        (not Web.Security.Is_Safe_Decoded_Path ("/static/%00/app.js"),
         "decoded nul path rejected");
      Assert (Web.Security.New_Session_Id'Length = 32, "session id length");
      Assert (Web.Security.Is_Valid_Session_Id (Web.Security.New_Session_Id), "session id format");
      Assert
        (not Web.Security.Is_Valid_Session_Id ("../../not-a-session"),
         "invalid session id rejected");
      Assert
        (Web.Security.Normalize_Authority ("Example.Test:8443") = "example.test:8443",
         "authority normalized");
      Assert
        (Web.Security.Normalize_Authority ("192.0.2.1") = "192.0.2.1",
         "ipv4 authority accepted");
      Assert
        (Web.Security.Normalize_Authority ("[2001:db8::1]") = "[2001:db8::1]",
         "ipv6 authority accepted");
      Assert
        (Web.Security.Normalize_Authority ("-bad.example") = "",
         "leading hyphen host rejected");
      Assert
        (Web.Security.Normalize_Authority ("bad-.example") = "",
         "trailing hyphen host rejected");
      Assert
        (Web.Security.Normalize_Authority ("999.1.2.3") = "",
         "invalid ipv4-like host rejected");
      Assert
        (Web.Security.Normalize_Authority ("[:::]") = "",
         "triple colon ipv6 rejected");
      Assert
        (Web.Security.Normalize_Authority ("[1:2:3]") = "",
         "short uncompressed ipv6 rejected");
      Assert
        (Web.Security.Normalize_Authority ("[gg::1]") = "",
         "invalid ipv6 hextet rejected");
      Assert
        (Web.Security.Normalize_Origin ("https://Example.Test:8443") = "https://example.test:8443",
         "origin normalized");
      Assert
        (Web.Security.Normalize_Origin ("ftp://example.test") = "",
         "non-http origin rejected");
      Assert
        (Web.Security.Normalize_Origin ("https://example.test/path") = "",
         "origin path rejected");

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
