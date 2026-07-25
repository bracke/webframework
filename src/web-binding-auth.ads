with Ada.Strings.Bounded;

--  Authorization-header syntax decoding (identity/authorization adapter).
--
--  Decodes the SYNTAX of an Authorization header only: the scheme and the raw
--  credentials, and for Basic the base64 userid:password split. It verifies
--  nothing -- no password check, no token signature, no session lookup, no
--  identity assignment. Authentication and authorization consume these bound
--  values elsewhere. Credential fields (the Basic password, a bearer token) are
--  secrets: callers must record them with Secret_Value so they are never
--  retained or logged.
package Web.Binding.Auth is

   type Auth_Scheme is
     (Scheme_None, Scheme_Basic, Scheme_Bearer, Scheme_Digest, Scheme_Other);

   Max_Scheme : constant := 32;
   Max_Token  : constant := 8_192;
   Max_Field  : constant := 512;

   package Scheme_Strings is
     new Ada.Strings.Bounded.Generic_Bounded_Length (Max_Scheme);
   package Token_Strings is
     new Ada.Strings.Bounded.Generic_Bounded_Length (Max_Token);
   package Field_Strings is
     new Ada.Strings.Bounded.Generic_Bounded_Length (Max_Field);

   type Credentials is record
      Valid      : Boolean := False;
      Scheme     : Auth_Scheme := Scheme_None;
      Raw_Scheme : Scheme_Strings.Bounded_String;
      Token      : Token_Strings.Bounded_String;   --  secret when a token
   end record;

   --  Parse an Authorization header into scheme + raw credentials. Syntax only.
   --  @param Header The header value.
   --  @return The parsed credentials (Valid => False if empty).
   function Parse (Header : String) return Credentials;

   type Basic_Credentials is record
      Valid    : Boolean := False;
      User_Id  : Field_Strings.Bounded_String;
      Password : Field_Strings.Bounded_String;   --  SECRET
   end record;

   --  Decode Basic credentials: base64-decode the token and split on the first
   --  ':'. No verification of the userid or password.
   --  @param C The parsed credentials (must be Scheme_Basic).
   --  @return The userid and password (Valid => False if not Basic or malformed).
   function Decode_Basic (C : Credentials) return Basic_Credentials;

end Web.Binding.Auth;
