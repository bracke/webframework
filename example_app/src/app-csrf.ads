with Web.Request;

--  CSRF protection for the app's state-changing HTTP POST endpoints, over the
--  webframework_forms bridge. Tokens are session-bound (an HMAC of the session
--  under a server key), so a token is valid only for the session it was issued
--  to. Every page carries the token in a <meta> tag; the page JS echoes it in
--  the POST body, and the handler verifies it before acting.
package App.Csrf is

   --  The form/body field (and meta tag) carrying the token.
   Field : constant String := "csrf_token";

   --  A CSRF token bound to Session_Id (hex), for embedding in a page.
   function Token (Session_Id : String) return String;

   --  True iff the request's urlencoded body carries a valid token for
   --  Session_Id. Fail-closed: an empty session, or a missing/mismatched token,
   --  returns False.
   function Verify
     (Request : Web.Request.Request_Type; Session_Id : String) return Boolean;

end App.Csrf;
