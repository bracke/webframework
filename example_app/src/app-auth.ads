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

end App.Auth;
