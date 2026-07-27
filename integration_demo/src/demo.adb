with Ada.Text_IO;      use Ada.Text_IO;
with Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;

with Web.Request;
with Web.Response;
with Web.Server;

with Forms.CSRF;
with Webframework_Forms;

with Site;

--  Registers the Site handlers with the framework and drives them through the
--  real router (Web.Server.Dispatch) with synthetic requests (via the
--  Parse_Request test seam -- no socket), demonstrating the full loop end to
--  end: a GET establishes a session + a session-bound CSRF token and renders the
--  chrome + form; a valid POST verifies CSRF, validates, and redirects; an
--  invalid POST re-renders sticky with errors; a CSRF token replayed under
--  another session is refused; and a POST with no session is refused.
procedure Demo is

   CRLF : constant String := (Character'Val (13), Character'Val (10));

   Csrf_Field : constant String :=
     Webframework_Forms.To_String (Forms.CSRF.Default_Field);

   function Get (Path : String) return Web.Request.Request_Type is
     (Web.Server.Parse_Request
        ("GET " & Path & " HTTP/1.1" & CRLF & "Host: x" & CRLF & CRLF));

   function Post (Body_S : String; Cookie : String := "")
                  return Web.Request.Request_Type
   is
      Len : constant String :=
        Trim (Integer'Image (Body_S'Length), Ada.Strings.Left);
   begin
      return Web.Server.Parse_Request
        ("POST /contact HTTP/1.1" & CRLF & "Host: x" & CRLF
         & (if Cookie = "" then "" else "Cookie: " & Cookie & CRLF)
         & "Content-Type: application/x-www-form-urlencoded" & CRLF
         & "Content-Length: " & Len & CRLF & CRLF & Body_S);
   end Post;

   --  Value of the named cookie in a Set-Cookie header ("" if absent).
   function Cookie_Value (Header : String; Name : String) return String is
      Key : constant String := Name & "=";
      P   : constant Natural := Index (Header, Key);
   begin
      if P = 0 then
         return "";
      end if;
      declare
         S : constant Positive := P + Key'Length;
         E : constant Natural := Index (Header (S .. Header'Last), ";");
      begin
         return (if E = 0 then Header (S .. Header'Last) else Header (S .. E - 1));
      end;
   end Cookie_Value;

   --  Value of a hidden input in the rendered form ("" if absent).
   function Hidden_Field (Body_S : String; Field : String) return String is
      Key : constant String := "name=""" & Field & """ value=""";
      P   : constant Natural := Index (Body_S, Key);
   begin
      if P = 0 then
         return "";
      end if;
      declare
         S : constant Positive := P + Key'Length;
         E : constant Natural := Index (Body_S (S .. Body_S'Last), """");
      begin
         return (if E = 0 then "" else Body_S (S .. E - 1));
      end;
   end Hidden_Field;

   procedure Show (Label : String; Cond : Boolean) is
   begin
      Put_Line ((if Cond then "  ok   " else "  FAIL ") & Label);
   end Show;

begin
   Site.Setup;

   --  Register the handlers with the framework and drive them through the real
   --  router (Web.Server.Dispatch) -- not by calling the handlers directly.
   Web.Server.Get ("/contact", Site.Contact_Get'Access);
   Web.Server.Post ("/contact", Site.Contact_Post'Access);

   --  1. GET /contact -- render chrome + form, establish a session + a
   --  session-bound CSRF token.
   Put_Line ("GET /contact");
   declare
      Resp : constant Web.Response.Response_Type :=
        Web.Server.Dispatch (Get ("/contact"));
      Body_S : constant String := Web.Response.Content_Body (Resp);
      Cookie : constant String := Web.Response.Header (Resp, "Set-Cookie");
      Sid    : constant String := Cookie_Value (Cookie, "sid");
      Csrf   : constant String := Hidden_Field (Body_S, Csrf_Field);
   begin
      Show ("200 OK", Web.Response.Status (Resp) = 200);
      Show ("menu marks the active Contact item",
            Index (Body_S, "<li class=""active""><a href=""/contact"">") > 0);
      Show ("breadcrumbs rendered", Index (Body_S, "breadcrumbs") > 0);
      Show ("Set-Cookie establishes a session", Sid'Length > 0);
      Show ("form carries a session-bound CSRF token", Csrf'Length > 0);

      --  2. Valid POST -- session cookie + its CSRF token + valid fields.
      New_Line;
      Put_Line ("POST /contact (valid, session-bound CSRF)");
      declare
         Body_S : constant String :=
           "name=Ada+Lovelace&email=ada%40example.com&" & Csrf_Field & "=" & Csrf;
         Resp : constant Web.Response.Response_Type :=
           Web.Server.Dispatch (Post (Body_S, Cookie => "sid=" & Sid));
      begin
         Show ("303 redirect", Web.Response.Status (Resp) = 303);
         Show ("Location is the reverse URL for 'thanks'",
               Web.Response.Header (Resp, "Location") = "/thanks");
      end;

      --  3. Invalid POST -- missing email, valid CSRF: re-render sticky + errors.
      New_Line;
      Put_Line ("POST /contact (invalid: missing email)");
      declare
         Body_S : constant String :=
           "name=Ada+Lovelace&" & Csrf_Field & "=" & Csrf;
         Resp : constant Web.Response.Response_Type :=
           Web.Server.Dispatch (Post (Body_S, Cookie => "sid=" & Sid));
         Page : constant String := Web.Response.Content_Body (Resp);
      begin
         Show ("400 with a re-rendered form", Web.Response.Status (Resp) = 400);
         Show ("name is sticky", Index (Page, "value=""Ada Lovelace""") > 0);
         Show ("a diagnostic is shown", Index (Page, "errors") > 0);
      end;

      --  4. Forged POST -- the CSRF token but a DIFFERENT session -- refused
      --  (this is what session binding buys over pure double-submit).
      New_Line;
      Put_Line ("POST /contact (CSRF token, wrong session)");
      declare
         Body_S : constant String :=
           "name=Ada&email=ada%40example.com&" & Csrf_Field & "=" & Csrf;
         Resp : constant Web.Response.Response_Type :=
           Web.Server.Dispatch (Post (Body_S, Cookie => "sid=attacker-session"));
      begin
         Show ("403 Forbidden (token not valid for this session)",
               Web.Response.Status (Resp) = 403);
      end;

      --  5. POST without a session cookie -- refused.
      New_Line;
      Put_Line ("POST /contact (no session cookie)");
      declare
         Body_S : constant String :=
           "name=Ada&email=ada%40example.com&" & Csrf_Field & "=" & Csrf;
         Resp : constant Web.Response.Response_Type :=
           Web.Server.Dispatch (Post (Body_S));   --  no session cookie
      begin
         Show ("403 Forbidden", Web.Response.Status (Resp) = 403);
      end;
   end;

   New_Line;
   Put_Line ("demo complete");
end Demo;
