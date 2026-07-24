--  Credential store for the example app, backed by the identity library's
--  in-memory repository.
--
--  Users are real identity principals (with accounts, username bindings and
--  enrolled password credentials); authentication runs through the repository's
--  password verification, so no plaintext password is stored or compared. A
--  successful authentication yields a stable authorization principal id that
--  the rest of the app carries as an opaque reference.
package App.Auth is

   --  Seed the identity repository (principals, accounts, bindings, passwords).
   --  Call once before serving.
   --  @return No return value.
   procedure Initialize;

   --  Authenticate a username and password. On success returns the caller's
   --  authorization principal id; on any failure returns an empty string.
   --  Fail-closed.
   --  @param Username Presented username.
   --  @param Password Presented password.
   --  @return Authorization principal id, or an empty string.
   function Authenticate (Username : String; Password : String) return String;

   --  The clearance (role) a principal carries, as recorded in the user store.
   --  Resolved once at login and then carried in the session/request context,
   --  so the authorization policy reads it as a request fact rather than
   --  mapping principals to roles itself.
   --  @param Principal Authorization principal id.
   --  @return Clearance value, or 0 for an unknown principal.
   function Clearance_Of (Principal : String) return Natural;

   --  Create an identity session for the just-authenticated principal and
   --  return an opaque token (public reference + bearer secret) to keep in the
   --  framework session. The identity repository is the source of truth for the
   --  session's validity (idle/absolute expiry, revocation).
   --  @param Principal Authorization principal id.
   --  @return Opaque session token, or an empty string on failure.
   function Create_Session (Principal : String) return String;

   --  Validate a session token against the identity repository. Returns the
   --  authorization principal of the session when it is live, or an empty
   --  string when the token is malformed, expired, or revoked. Called on every
   --  request, so revocation and expiry take effect immediately.
   --  @param Token Opaque session token.
   --  @return Authorization principal id, or an empty string.
   function Validate_Session (Token : String) return String;

   --  Revoke a session token (logout); its id can never be replayed.
   --  @param Token Opaque session token.
   --  @return No return value.
   procedure Revoke_Session (Token : String);

end App.Auth;
