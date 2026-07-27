with AUnit.Assertions; use AUnit.Assertions;
with AUnit.Test_Caller;
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

package body Bridge_Tests is

   package WF renames Webframework_Forms;
   use type Forms.Urlencoded.Decode_Status;

   CRLF : constant String := (Character'Val (13), Character'Val (10));

   function Post (Body_S : String; Cookie : String := "")
                  return Web.Request.Request_Type
   is
      Len : constant String :=
        Ada.Strings.Fixed.Trim (Integer'Image (Body_S'Length), Ada.Strings.Left);
   begin
      return Web.Server.Parse_Request
        ("POST / HTTP/1.1" & CRLF & "Host: x" & CRLF
         & (if Cookie = "" then "" else "Cookie: " & Cookie & CRLF)
         & "Content-Type: application/x-www-form-urlencoded" & CRLF
         & "Content-Length: " & Len & CRLF & CRLF & Body_S);
   end Post;

   procedure Test_Decode (T : in out Fixture) is
      pragma Unreferenced (T);
      Req : constant Web.Request.Request_Type := Post ("name=Ada&city=Aarhus+C");
      Sub : Forms.Submission.Data (16, 1024);
      St  : Forms.Urlencoded.Decode_Status;
   begin
      WF.Read_Urlencoded (Req, Sub, St);
      Assert (St = Forms.Urlencoded.Decode_Ok, "urlencoded body decodes");
      Assert (WF.To_String (Forms.Submission.Value_Of (Sub, WF.To_Bytes ("name")))
              = "Ada", "decoded field 'name'");
      Assert (WF.To_String (Forms.Submission.Value_Of (Sub, WF.To_Bytes ("city")))
              = "Aarhus C", "'+' decoded to space");
   end Test_Decode;

   procedure Test_Csrf_Roundtrip (T : in out Fixture) is
      pragma Unreferenced (T);
      Tok : Forms.CSRF.Token;
      Ok  : Boolean;
   begin
      WF.New_Token (Tok, Ok);
      Assert (Ok, "CSRF token generated from the stack CSPRNG");
      declare
         Hex   : constant String := WF.Token_Hex (Tok);
         Sub   : Forms.Submission.Data (4, 256);
         Added : Boolean;
         Good  : constant Web.Request.Request_Type :=
           Post ("x=1", Cookie => WF.Default_Cookie & "=" & Hex);
         Bad   : constant Web.Request.Request_Type :=
           Post ("x=1", Cookie => WF.Default_Cookie & "=deadbeef");
         None  : constant Web.Request.Request_Type := Post ("x=1");
      begin
         Forms.Submission.Add
           (Sub, Forms.CSRF.Default_Field, WF.To_Bytes (Hex), Added);
         Assert (WF.Verify_Csrf (Good, Sub), "matching cookie + field verifies");
         Assert (not WF.Verify_Csrf (Bad, Sub), "mismatched cookie fails closed");
         Assert (not WF.Verify_Csrf (None, Sub), "absent cookie fails closed");
         declare
            SC : constant String := WF.Set_Cookie (Tok, Secure => False);
         begin
            Assert (Ada.Strings.Fixed.Index (SC, Hex) > 0,
                    "Set_Cookie carries the token hex");
            Assert (Ada.Strings.Fixed.Index (SC, "HttpOnly") > 0
                    and then Ada.Strings.Fixed.Index (SC, "SameSite=Strict") > 0,
                    "Set_Cookie is HttpOnly + SameSite=Strict");
         end;
      end;
   end Test_Csrf_Roundtrip;

   procedure Test_Bind_Diagnostics (T : in out Fixture) is
      pragma Unreferenced (T);
      Def   : Forms.Form.Definition (4);
      Added : Boolean;
   begin
      Forms.Form.Start (Def);
      Forms.Form.Add_Field
        (Def, Forms.Fields.Make (WF.To_Bytes ("name"),
                                 Presence => Forms.Fields.Required), Added);
      Forms.Form.Finalize (Def);
      declare
         Empty  : Forms.Submission.Data (4, 256);
         Report : Representation.Diagnostics.Diagnostic_Set;
         Ok     : Boolean;
      begin
         Representation.Diagnostics.Clear (Report);
         Forms.Binding.Bind (Def, Empty, Report, Ok);
         Assert (not Ok, "missing required field does not bind");
         Assert (WF.Diagnostics_Text (Report)'Length > 0,
                 "Diagnostics_Text renders the failure");
         Assert (Web.Response.Status (WF.Error_Response (Report)) = 400,
                 "Error_Response is 400");
      end;
   end Test_Bind_Diagnostics;

   procedure Test_Sticky (T : in out Fixture) is
      pragma Unreferenced (T);
      Def   : Forms.Form.Definition (4);
      Added : Boolean;
      Sub   : Forms.Submission.Data (4, 256);
      AddOk : Boolean;
   begin
      Forms.Form.Start (Def);
      Forms.Form.Add_Field
        (Def, Forms.Fields.Make (WF.To_Bytes ("name")), Added);
      Forms.Form.Finalize (Def);
      Forms.Submission.Add
        (Sub, WF.To_Bytes ("name"), WF.To_Bytes ("Ada<b>"), AddOk);
      Assert (WF.Sticky (Def, Sub, WF.To_Bytes ("name")) = "Ada<b>",
              "Sticky returns the submitted value for re-render");
   end Test_Sticky;

   procedure Test_Hardening (T : in out Fixture) is
      pragma Unreferenced (T);
      Tok : Forms.CSRF.Token;
      Ok  : Boolean;
   begin
      --  A malformed percent-escape decodes to an error status, not a crash.
      declare
         Req : constant Web.Request.Request_Type := Post ("name=%ZZ&x=%A");
         Sub : Forms.Submission.Data (8, 512);
         St  : Forms.Urlencoded.Decode_Status;
      begin
         WF.Read_Urlencoded (Req, Sub, St);
         Assert (St /= Forms.Urlencoded.Decode_Ok,
                 "malformed percent-escape is a value error, not a crash");
      end;

      WF.New_Token (Tok, Ok);
      declare
         Hex   : constant String := WF.Token_Hex (Tok);
         Sub   : Forms.Submission.Data (4, 8192);
         Added : Boolean;
         Big   : constant String (1 .. 5000) := (others => 'a');
         function Req_With (Cookie : String) return Web.Request.Request_Type is
           (Post ("x=1", Cookie => Cookie));
      begin
         Forms.Submission.Add
           (Sub, Forms.CSRF.Default_Field, WF.To_Bytes (Hex), Added);
         Assert (not WF.Verify_Csrf (Req_With ("csrf_token=nothex!!"), Sub),
                 "malformed-hex cookie fails closed");
         Assert (not WF.Verify_Csrf (Req_With ("csrf_token="), Sub),
                 "empty cookie value fails closed");
         Assert (not WF.Verify_Csrf (Req_With ("csrf_token=" & Big), Sub),
                 "oversized cookie fails closed (no crash)");
         Assert (not WF.Verify_Csrf (Req_With ("other=1; another=2"), Sub),
                 "no csrf_token cookie fails closed");
         Assert (not WF.Verify_Csrf (Req_With ("csrf_token=" & Hex & "00"), Sub),
                 "wrong-length token fails closed");
      end;
   end Test_Hardening;

   package Caller is new AUnit.Test_Caller (Fixture);

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Suite.Add_Test (Caller.Create ("Bridge: decode", Test_Decode'Access));
      Suite.Add_Test
        (Caller.Create ("Bridge: CSRF round-trip", Test_Csrf_Roundtrip'Access));
      Suite.Add_Test
        (Caller.Create ("Bridge: bind diagnostics", Test_Bind_Diagnostics'Access));
      Suite.Add_Test (Caller.Create ("Bridge: sticky", Test_Sticky'Access));
      Suite.Add_Test (Caller.Create ("Bridge: hardening", Test_Hardening'Access));
   end Add_Tests;

end Bridge_Tests;
