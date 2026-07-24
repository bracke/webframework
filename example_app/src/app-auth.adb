with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with App.Identity;

package body App.Auth is

   --  A small seeded user table. Each user carries an authorization principal
   --  id (which encodes the role -- App.Authz derives a clearance from it) and
   --  a password verifier envelope computed once at Initialize. A real
   --  deployment resolves these from an identity repository per login.
   type User is record
      Username  : Unbounded_String;
      Plain     : Unbounded_String;  --  seed password; hashed and cleared at init
      Verifier  : Unbounded_String;  --  PBKDF2 verifier envelope (identity)
      Principal : Unbounded_String;  --  authorization principal id
   end record;

   function U (Value : String) return Unbounded_String
     renames To_Unbounded_String;

   Users : array (1 .. 2) of User :=
     [1 => (U ("admin"),  U ("admin123"),  Null_Unbounded_String,
            U ("d.principal.admin")),
      2 => (U ("viewer"), U ("viewer123"), Null_Unbounded_String,
            U ("d.principal.viewer"))];

   procedure Initialize is
   begin
      for Item of Users loop
         Item.Verifier := U (App.Identity.Hash_Password (To_String (Item.Plain)));
         Item.Plain := Null_Unbounded_String;  --  no plaintext lingers
      end loop;
   end Initialize;

   function Authenticate (Username : String; Password : String) return String is
   begin
      for Item of Users loop
         if To_String (Item.Username) = Username
           and then Length (Item.Verifier) > 0
           and then App.Identity.Verify_Password
                      (Password, To_String (Item.Verifier))
         then
            return To_String (Item.Principal);
         end if;
      end loop;

      return "";
   end Authenticate;

end App.Auth;
