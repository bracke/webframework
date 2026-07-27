with Webframework_Forms;
with Forms.Submission;
with Forms.Urlencoded;

package body App.Csrf is

   --  Server CSRF signing key. A real deployment loads this from a keyring or
   --  config (stable across restarts, shared across instances); it is not
   --  per-request randomness. A literal is fine for the example.
   Key : constant Webframework_Forms.Byte_Array :=
     Webframework_Forms.To_Bytes ("example-app-csrf-signing-key-change-me");

   function Token (Session_Id : String) return String is
     (Webframework_Forms.Token_Hex
        (Webframework_Forms.Session_Token (Key, Session_Id)));

   function Verify
     (Request : Web.Request.Request_Type; Session_Id : String) return Boolean
   is
      Sub    : Forms.Submission.Data (16, 16384);
      Status : Forms.Urlencoded.Decode_Status;
   begin
      if Session_Id'Length = 0 then
         return False;
      end if;
      --  Decode the (always urlencoded) body; a decode failure leaves the CSRF
      --  field absent, so Verify_Session_Csrf then fails closed.
      Webframework_Forms.Read_Urlencoded (Request, Sub, Status);
      return Webframework_Forms.Verify_Session_Csrf
        (Sub, Key, Session_Id, Webframework_Forms.To_Bytes (Field));
   end Verify;

end App.Csrf;
