with Ada.Environment_Variables;
with Web.Security;
with Webframework_Forms;
with Forms.Submission;
with Forms.Urlencoded;

pragma Elaborate_All (Web.Security);

package body App.Csrf is

   Key_Env_Var    : constant String := "APP_CSRF_KEY";
   Min_Key_Length : constant := 16;

   --  The configured key (if any), read once at elaboration.
   Configured_Key : constant String :=
     Ada.Environment_Variables.Value (Key_Env_Var, "");
   Use_Configured : constant Boolean := Configured_Key'Length >= Min_Key_Length;

   --  The server CSRF signing key. Either the configured secret, or a strong
   --  per-process key drawn from the stack CSPRNG (two session ids' worth of
   --  entropy) so tokens are never signed with a shipped constant. It is a
   --  stable server secret for the process's lifetime, not per-request
   --  randomness.
   Key : constant Webframework_Forms.Byte_Array :=
     (if Use_Configured
      then Webframework_Forms.To_Bytes (Configured_Key)
      else Webframework_Forms.To_Bytes
             (Web.Security.New_Session_Id & Web.Security.New_Session_Id));

   function Key_Source return String is
     (if Use_Configured then Key_Env_Var
      elsif Configured_Key'Length > 0
      then "per-process (ephemeral; " & Key_Env_Var & " set but too short)"
      else "per-process (ephemeral; set " & Key_Env_Var
           & " for multi-instance or restart-stable deployments)");

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
