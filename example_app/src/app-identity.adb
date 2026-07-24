with Identity.Crypto.Password_Hashing;
with Identity.Secrets.Text;

package body App.Identity is

   --  Within App.Identity the simple name "Identity" denotes this package, so
   --  the identity library's root must be reached through Standard.
   package PH renames Standard.Identity.Crypto.Password_Hashing;
   package Secret_Text renames Standard.Identity.Secrets.Text;

   use type PH.Verification_Outcome;

   function Hash_Password (Plaintext : String) return String is
   begin
      return PH.Create_Verifier (Secret_Text.From_UTF_8 (Plaintext));
   end Hash_Password;

   function Verify_Password (Plaintext : String; Envelope : String) return Boolean is
      Result : constant PH.Verification_Result :=
        PH.Verify (Secret_Text.From_UTF_8 (Plaintext), Envelope);
   begin
      return Result.Outcome = PH.Verified;
   end Verify_Password;

end App.Identity;
