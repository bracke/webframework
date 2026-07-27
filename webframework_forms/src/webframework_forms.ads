with Web.Request;
with Web.Response;

with Representation;
with Representation.Diagnostics;
with Forms.Submission;
with Forms.Form;
with Forms.Urlencoded;
with Forms.CSRF;
with Forms.Limits;

--  Bridge from the forms library to the webframework HTTP handler seam.
--
--  forms is headless and byte-oriented: it decodes a wire body into a
--  submission multimap, binds it against a form definition, and runs CSRF —
--  but it never touches a request or a response. webframework core depends on
--  none of forms' crates. This crate is the only unit that depends on both, so
--  a handler can turn a Web.Request straight into a bound submission and enforce
--  CSRF using the request's cookies.
--
--  Everything is fail-closed and nothing raises. String request data is
--  converted to Representation.Byte_Array (forms' currency) at the boundary.
package Webframework_Forms is

   subtype Byte_Array is Representation.Byte_Array;

   --  Convert between a webframework String and forms' Byte_Array (Latin-1,
   --  byte-wise — a UTF-8 body round-trips unchanged).
   function To_Bytes (S : String) return Byte_Array;
   function To_String (B : Byte_Array) return String;

   --  Decode an application/x-www-form-urlencoded request body into Into.
   --  Status is the forms decode result (Decode_Ok on success); on any decode
   --  error Into holds whatever was decoded before the failure.
   procedure Read_Urlencoded
     (Request        : Web.Request.Request_Type;
      Into           : in out Forms.Submission.Data;
      Status         : out Forms.Urlencoded.Decode_Status;
      Name_Capacity  : Positive := 256;
      Value_Capacity : Positive := 4096;
      Limits         : Forms.Limits.Limits := Forms.Limits.Default_Limits);

   ----------------------------------------------------------------------
   --  CSRF (double-submit cookie): the server binds a fresh token into both a
   --  cookie and a hidden form field when rendering, then verifies on submit
   --  that the submitted field matches the cookie. Constant-time; fails closed.
   ----------------------------------------------------------------------

   Default_Cookie : constant String := "csrf_token";

   --  A fresh CSRF token from the stack CSPRNG. Ok is False only if OS entropy
   --  is unavailable — do not render the form then.
   procedure New_Token (Tok : out Forms.CSRF.Token; Ok : out Boolean);

   --  The token as hex, for the hidden form field (also the cookie value).
   function Token_Hex (Tok : Forms.CSRF.Token) return String;

   --  A Set-Cookie header value binding the token: HttpOnly, SameSite=Strict,
   --  Path=/. Set Secure => False only for plain-HTTP local testing.
   function Set_Cookie
     (Tok    : Forms.CSRF.Token;
      Name   : String := Default_Cookie;
      Secure : Boolean := True) return String;

   --  Verify the submission's CSRF field against the token in the request's
   --  cookie. False (fail-closed) if the cookie is absent, malformed, or the
   --  values differ.
   function Verify_Csrf
     (Request : Web.Request.Request_Type;
      Sub     : Forms.Submission.Data;
      Field   : Byte_Array := Forms.CSRF.Default_Field;
      Name    : String := Default_Cookie) return Boolean;

   ----------------------------------------------------------------------
   --  Session-bound CSRF (signed synchronizer token). Stronger than the
   --  double-submit cookie above: the token is HMAC-SHA256 (Key, Session_Id),
   --  so an attacker who can plant a cookie still cannot forge a valid token
   --  without the server signing Key. No CSRF cookie is needed -- verification
   --  recomputes the expected token from the session, which the server derives
   --  from its own (authenticated) session, not from client-controlled input.
   --
   --  Key is a STABLE server secret (deployment config -- a keyring value that
   --  survives restarts and is shared across instances), NOT per-request
   --  randomness. Bind Session_Id to the user's session (e.g.
   --  Web.Context.Session).
   ----------------------------------------------------------------------

   --  The CSRF token bound to Session_Id under the signing Key. Put its
   --  Token_Hex in the hidden field when rendering the form.
   function Session_Token
     (Key : Byte_Array; Session_Id : String) return Forms.CSRF.Token;

   --  Verify the submission's CSRF field against the token derived from
   --  Session_Id and Key. Constant-time; fail-closed on any mismatch (wrong
   --  session, wrong key, tampered field). No cookie is consulted.
   function Verify_Session_Csrf
     (Sub        : Forms.Submission.Data;
      Key        : Byte_Array;
      Session_Id : String;
      Field      : Byte_Array := Forms.CSRF.Default_Field) return Boolean;

   ----------------------------------------------------------------------
   --  Diagnostics and sticky re-render. After Forms.Binding.Bind (and any
   --  Forms.Rules.Merge of validation results) populates a shared
   --  Diagnostic_Set, these turn it into a response or feed a re-render.
   ----------------------------------------------------------------------

   --  The diagnostics as plain text, one line per entry
   --  ("error_id at path: message").
   function Diagnostics_Text
     (Report : Representation.Diagnostics.Diagnostic_Set) return String;

   --  A response carrying Diagnostics_Text (400 Bad Request by default). Use
   --  when a submission fails to bind/validate and you are not re-rendering the
   --  form itself.
   function Error_Response
     (Report : Representation.Diagnostics.Diagnostic_Set;
      Status : Positive := 400) return Web.Response.Response_Type;

   --  The value to re-display for a field when re-rendering a form after a
   --  failed submission (Forms.Binding.Sticky_Value). Returns "" for a
   --  redacted (sensitive) field. NOT HTML-escaped — escape before embedding
   --  in markup.
   function Sticky
     (Def       : Forms.Form.Definition;
      Sub       : Forms.Submission.Data;
      Name      : Byte_Array;
      Max_Bytes : Positive := 4096) return String;

end Webframework_Forms;
