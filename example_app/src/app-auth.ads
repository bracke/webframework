--  Credential store for the example app.
--
--  Passwords are verified through the identity library (App.Identity); no
--  plaintext password is stored or compared. A successful authentication yields
--  a stable authorization principal id that the rest of the app carries as an
--  opaque reference and hands to the authorization engine.
package App.Auth is

   --  Prepare the credential store. Hashes the seeded demo password once so no
   --  plaintext ever lives in the process beyond this call.
   --  @return No return value.
   procedure Initialize;

   --  Authenticate a username and password. On success returns the caller's
   --  authorization principal id; on any failure returns an empty string.
   --  Fail-closed.
   --  @param Username Presented username.
   --  @param Password Presented password.
   --  @return Authorization principal id, or an empty string.
   function Authenticate (Username : String; Password : String) return String;

end App.Auth;
