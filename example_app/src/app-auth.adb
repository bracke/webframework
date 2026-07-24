with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with App.Identity;

package body App.Auth is

   --  A single seeded demo account. A real deployment would resolve the
   --  username to a stored verifier envelope and principal from a repository.
   Demo_User      : constant String := "admin";
   Demo_Password  : constant String := "admin123";
   Demo_Principal : constant String := "d.principal.admin";

   --  The demo password's verifier envelope, computed once at Initialize.
   Verifier : Unbounded_String;

   procedure Initialize is
   begin
      Verifier := To_Unbounded_String (App.Identity.Hash_Password (Demo_Password));
   end Initialize;

   function Authenticate (Username : String; Password : String) return String is
   begin
      if Username = Demo_User
        and then Length (Verifier) > 0
        and then App.Identity.Verify_Password (Password, To_String (Verifier))
      then
         return Demo_Principal;
      end if;

      return "";
   end Authenticate;

end App.Auth;
