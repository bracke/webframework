with Ada.Text_IO;      use Ada.Text_IO;
with Ada.Command_Line;
with Ada.Strings;
with Ada.Strings.Fixed;

with Web.Request;
with Web.Server;
with Web.Response;

with Forms.Submission;
with Forms.Urlencoded;
with Forms.CSRF;
with Forms.Form;
with Forms.Fields;
with Forms.Binding;

with Representation.Diagnostics;

with Webframework_Forms;

--  Verifies the forms -> webframework bridge: decoding a urlencoded request
--  body into a submission, and the CSRF double-submit cookie round-trip
--  (fail-closed on a missing or mismatched cookie).
procedure Test_Bridge is

   package WF renames Webframework_Forms;

   use type Forms.Urlencoded.Decode_Status;

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Label : String) is
   begin
      if Cond then
         Put_Line ("ok   " & Label);
      else
         Put_Line ("FAIL " & Label);
         Failures := Failures + 1;
      end if;
   end Check;

   CRLF : constant String := (Character'Val (13), Character'Val (10));

   --  A urlencoded POST with the given body and optional Cookie header.
   function Post (Body_S : String; Cookie : String := "") return String is
      Len : constant String :=
        Ada.Strings.Fixed.Trim (Integer'Image (Body_S'Length), Ada.Strings.Left);
   begin
      return "POST / HTTP/1.1" & CRLF
        & "Host: x" & CRLF
        & (if Cookie = "" then "" else "Cookie: " & Cookie & CRLF)
        & "Content-Type: application/x-www-form-urlencoded" & CRLF
        & "Content-Length: " & Len & CRLF & CRLF & Body_S;
   end Post;

begin
   --  Decode a urlencoded body into a submission.
   declare
      Req : constant Web.Request.Request_Type :=
        Web.Server.Parse_Request (Post ("name=Ada&city=Aarhus+C"));
      Sub : Forms.Submission.Data (16, 1024);
      St  : Forms.Urlencoded.Decode_Status;
   begin
      WF.Read_Urlencoded (Req, Sub, St);
      Check (St = Forms.Urlencoded.Decode_Ok, "urlencoded body decodes");
      Check (WF.To_String (Forms.Submission.Value_Of (Sub, WF.To_Bytes ("name")))
             = "Ada", "decoded field 'name'");
      Check (WF.To_String (Forms.Submission.Value_Of (Sub, WF.To_Bytes ("city")))
             = "Aarhus C", "'+' decoded to space in 'city'");
   end;

   --  CSRF double-submit: token in the cookie AND the submitted field verifies.
   declare
      Tok : Forms.CSRF.Token;
      Ok  : Boolean;
   begin
      WF.New_Token (Tok, Ok);
      Check (Ok, "CSRF token generated from the stack CSPRNG");

      declare
         Hex : constant String := WF.Token_Hex (Tok);
         Sub : Forms.Submission.Data (4, 256);
         Added : Boolean;
         Good : constant Web.Request.Request_Type :=
           Web.Server.Parse_Request
             (Post ("x=1", Cookie => WF.Default_Cookie & "=" & Hex));
         Bad_Cookie : constant Web.Request.Request_Type :=
           Web.Server.Parse_Request
             (Post ("x=1", Cookie => WF.Default_Cookie & "=deadbeef"));
         No_Cookie : constant Web.Request.Request_Type :=
           Web.Server.Parse_Request (Post ("x=1"));
      begin
         --  The submitted hidden field carries the token hex.
         Forms.Submission.Add
           (Sub, Forms.CSRF.Default_Field, WF.To_Bytes (Hex), Added);

         Check (WF.Verify_Csrf (Good, Sub),
                "matching cookie + field verifies");
         Check (not WF.Verify_Csrf (Bad_Cookie, Sub),
                "mismatched cookie fails closed");
         Check (not WF.Verify_Csrf (No_Cookie, Sub),
                "absent cookie fails closed");

         --  The Set-Cookie header value carries the same hex, HttpOnly+Strict.
         declare
            SC : constant String := WF.Set_Cookie (Tok, Secure => False);
         begin
            Check (Ada.Strings.Fixed.Index (SC, Hex) > 0,
                   "Set_Cookie carries the token hex");
            Check (Ada.Strings.Fixed.Index (SC, "HttpOnly") > 0
                   and then Ada.Strings.Fixed.Index (SC, "SameSite=Strict") > 0,
                   "Set_Cookie is HttpOnly + SameSite=Strict");
         end;
      end;
   end;

   --  Bind -> diagnostics -> sticky: a required field that is missing fails to
   --  bind and produces a diagnostic; a submitted value re-renders (sticky).
   declare
      Def   : Forms.Form.Definition (4);
      Added : Boolean;
   begin
      Forms.Form.Start (Def);
      Forms.Form.Add_Field
        (Def,
         Forms.Fields.Make (WF.To_Bytes ("name"),
                            Presence => Forms.Fields.Required),
         Added);
      Forms.Form.Finalize (Def);

      --  Missing required field -> not Ok, with a diagnostic.
      declare
         Empty  : Forms.Submission.Data (4, 256);
         Report : Representation.Diagnostics.Diagnostic_Set;
         Ok     : Boolean;
      begin
         Representation.Diagnostics.Clear (Report);
         Forms.Binding.Bind (Def, Empty, Report, Ok);
         Check (not Ok, "missing required field does not bind");
         Check (WF.Diagnostics_Text (Report)'Length > 0,
                "Diagnostics_Text renders the failure");
         Check (Web.Response.Status (WF.Error_Response (Report)) = 400,
                "Error_Response is 400 with the diagnostics body");
      end;

      --  Sticky re-render echoes the submitted value verbatim (caller escapes).
      declare
         Sub   : Forms.Submission.Data (4, 256);
         AddOk : Boolean;
      begin
         Forms.Submission.Add
           (Sub, WF.To_Bytes ("name"), WF.To_Bytes ("Ada<b>"), AddOk);
         Check (WF.Sticky (Def, Sub, WF.To_Bytes ("name")) = "Ada<b>",
                "Sticky returns the submitted value for re-render");
      end;
   end;

   --  Hardening: malformed bodies decode to a value error (no crash), and
   --  hostile cookies fail CSRF closed.
   declare
      Tok : Forms.CSRF.Token;
      Ok  : Boolean;
   begin
      --  A malformed percent-escape decodes to an error status, not a crash.
      declare
         Req : constant Web.Request.Request_Type :=
           Web.Server.Parse_Request (Post ("name=%ZZ&x=%A"));
         Sub : Forms.Submission.Data (8, 512);
         St  : Forms.Urlencoded.Decode_Status;
      begin
         WF.Read_Urlencoded (Req, Sub, St);
         Check (St /= Forms.Urlencoded.Decode_Ok,
                "malformed percent-escape is a value error, not a crash");
      end;

      --  Adversarial cookies into Verify_Csrf all fail closed.
      WF.New_Token (Tok, Ok);
      declare
         Hex : constant String := WF.Token_Hex (Tok);
         Sub : Forms.Submission.Data (4, 8192);
         Added : Boolean;
         Big   : constant String (1 .. 5000) := (others => 'a');

         function Req_With (Cookie : String) return Web.Request.Request_Type is
           (Web.Server.Parse_Request (Post ("x=1", Cookie => Cookie)));
      begin
         Forms.Submission.Add
           (Sub, Forms.CSRF.Default_Field, WF.To_Bytes (Hex), Added);

         Check (not WF.Verify_Csrf (Req_With ("csrf_token=nothex!!"), Sub),
                "malformed-hex cookie fails closed");
         Check (not WF.Verify_Csrf (Req_With ("csrf_token="), Sub),
                "empty cookie value fails closed");
         Check (not WF.Verify_Csrf (Req_With ("csrf_token=" & Big), Sub),
                "oversized cookie fails closed (no crash)");
         Check (not WF.Verify_Csrf (Req_With ("other=1; another=2"), Sub),
                "cookie present but no csrf_token fails closed");
         Check (not WF.Verify_Csrf (Req_With ("csrf_token=" & Hex & "00"), Sub),
                "wrong-length token fails closed");

         --  Submission field present but empty also fails closed.
         declare
            Empty_Sub : Forms.Submission.Data (4, 64);
            A2 : Boolean;
         begin
            Forms.Submission.Add
              (Empty_Sub, Forms.CSRF.Default_Field, WF.To_Bytes (""), A2);
            Check (not WF.Verify_Csrf
                     (Req_With ("csrf_token=" & Hex), Empty_Sub),
                   "empty submitted CSRF field fails closed");
         end;
      end;
   end;

   New_Line;
   if Failures = 0 then
      Put_Line ("all bridge tests passed");
      Ada.Command_Line.Set_Exit_Status (0);
   else
      Put_Line (Natural'Image (Failures) & " failure(s)");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Test_Bridge;
