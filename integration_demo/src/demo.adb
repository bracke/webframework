with Ada.Text_IO;      use Ada.Text_IO;
with Ada.Strings;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;

with Web.Request;
with Web.Response;
with Web.Server;

with Forms.CSRF;
with Webframework_Forms;

with Site;

--  Drives the Site handlers with synthetic requests (via the Parse_Request test
--  seam -- no socket) to demonstrate the full loop end to end: a GET issues a
--  CSRF cookie and renders the chrome + form; a valid POST verifies CSRF,
--  validates, and redirects; an invalid POST re-renders sticky with errors; a
--  POST without the cookie is refused.
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

   --  Pull the csrf_token value out of a Set-Cookie header.
   function Cookie_Token (Set_Cookie : String) return String is
      Key : constant String := "csrf_token=";
      P   : constant Natural := Index (Set_Cookie, Key);
   begin
      if P = 0 then
         return "";
      end if;
      declare
         S : constant Positive := P + Key'Length;
         E : constant Natural := Index (Set_Cookie (S .. Set_Cookie'Last), ";");
      begin
         return (if E = 0 then Set_Cookie (S .. Set_Cookie'Last)
                 else Set_Cookie (S .. E - 1));
      end;
   end Cookie_Token;

   procedure Show (Label : String; Cond : Boolean) is
   begin
      Put_Line ((if Cond then "  ok   " else "  FAIL ") & Label);
   end Show;

begin
   Site.Setup;

   --  1. GET /contact -- render chrome + form, issue a CSRF cookie.
   Put_Line ("GET /contact");
   declare
      Resp : constant Web.Response.Response_Type :=
        Site.Contact_Get (Get ("/contact"));
      Body_S : constant String := Web.Response.Content_Body (Resp);
      Cookie : constant String := Web.Response.Header (Resp, "Set-Cookie");
      Token  : constant String := Cookie_Token (Cookie);
   begin
      Show ("200 OK", Web.Response.Status (Resp) = 200);
      Show ("menu marks the active Contact item",
            Index (Body_S, "<li class=""active""><a href=""/contact"">") > 0);
      Show ("breadcrumbs rendered", Index (Body_S, "breadcrumbs") > 0);
      Show ("Set-Cookie issues a CSRF token", Token'Length > 0);
      Show ("form carries the matching hidden CSRF field",
            Index (Body_S, "name=""" & Csrf_Field & """ value=""" & Token) > 0);

      --  2. Valid POST -- correct cookie + echoed token + valid fields.
      New_Line;
      Put_Line ("POST /contact (valid, with CSRF)");
      declare
         Body_S : constant String :=
           "name=Ada+Lovelace&email=ada%40example.com&"
           & Csrf_Field & "=" & Token;
         Resp : constant Web.Response.Response_Type :=
           Site.Contact_Post (Post (Body_S, Cookie => "csrf_token=" & Token));
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
           "name=Ada+Lovelace&" & Csrf_Field & "=" & Token;
         Resp : constant Web.Response.Response_Type :=
           Site.Contact_Post (Post (Body_S, Cookie => "csrf_token=" & Token));
         Page : constant String := Web.Response.Content_Body (Resp);
      begin
         Show ("400 with a re-rendered form", Web.Response.Status (Resp) = 400);
         Show ("name is sticky", Index (Page, "value=""Ada Lovelace""") > 0);
         Show ("a diagnostic is shown", Index (Page, "errors") > 0);
      end;

      --  4. POST without the CSRF cookie -- refused.
      New_Line;
      Put_Line ("POST /contact (no CSRF cookie)");
      declare
         Body_S : constant String :=
           "name=Ada&email=ada%40example.com&" & Csrf_Field & "=" & Token;
         Resp : constant Web.Response.Response_Type :=
           Site.Contact_Post (Post (Body_S));   --  no cookie
      begin
         Show ("403 Forbidden", Web.Response.Status (Resp) = 403);
      end;
   end;

   New_Line;
   Put_Line ("demo complete");
end Demo;
