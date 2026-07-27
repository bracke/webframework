with Web.Request;

--  CSRF protection for the app's state-changing HTTP POST endpoints, over the
--  webframework_forms bridge. Tokens are session-bound (an HMAC of the session
--  under a server key), so a token is valid only for the session it was issued
--  to. Every page carries the token in a <meta> tag; the page JS echoes it in
--  the POST body, and the handler verifies it before acting.
--
--  The signing key is resolved once at startup from the APP_CSRF_KEY
--  environment variable; when it is unset the app generates a strong
--  per-process key so a shipped constant is never used. A per-process key is
--  invalidated on restart and differs across instances, so a real (restart-
--  stable, horizontally-scaled) deployment must set APP_CSRF_KEY to a shared
--  secret.
package App.Csrf is

   --  The form/body field (and meta tag) carrying the token.
   Field : constant String := "csrf_token";

   --  A CSRF token bound to Session_Id (hex), for embedding in a page.
   function Token (Session_Id : String) return String;

   --  A short description of where the signing key came from, for a startup
   --  diagnostic: the environment variable name when a key was configured, or
   --  a "per-process (ephemeral)" note otherwise. Never reveals the key itself.
   function Key_Source return String;

   --  True iff the request's urlencoded body carries a valid token for
   --  Session_Id. Fail-closed: an empty session, or a missing/mismatched token,
   --  returns False.
   function Verify
     (Request : Web.Request.Request_Type; Session_Id : String) return Boolean;

end App.Csrf;
