--  Password hashing for the example app, backed by the identity library's
--  PBKDF2-HMAC-SHA256 verifier (Identity.Crypto.Password_Hashing). This is what
--  replaces the previous hard-coded plaintext credential: a stored password is
--  only ever a self-describing verifier envelope, never a recoverable secret.
package App.Identity is

   --  Hash a plaintext password into a storable verifier envelope. Intended for
   --  seeding/registration. Propagates a CSPRNG failure as fatal.
   --  @param Plaintext Password to hash.
   --  @return Verifier envelope string to persist.
   function Hash_Password (Plaintext : String) return String;

   --  Verify a presented plaintext password against a stored envelope.
   --  Fail-closed: returns True only on an exact cryptographic match.
   --  @param Plaintext Presented password.
   --  @param Envelope Stored verifier envelope.
   --  @return True when the password matches the envelope.
   function Verify_Password (Plaintext : String; Envelope : String) return Boolean;

end App.Identity;
