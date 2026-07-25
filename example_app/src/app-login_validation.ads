with Validation.Results;

--  Login INPUT-format validation only, kept strictly within the credential
--  boundary: it checks that the submitted username is well-formed transport
--  input (present, non-blank, bounded, valid UTF-8). It never inspects the
--  password contents, never places credential material in a validation value,
--  and reveals nothing about whether an account exists — the handler keeps its
--  generic failure response. Credential VERIFICATION remains entirely with
--  Identity.
package App.Login_Validation is

   function Validate_Username
     (Username : String) return Validation.Results.Result;

end App.Login_Validation;
