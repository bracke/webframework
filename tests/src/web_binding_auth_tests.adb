with AUnit.Assertions;
with AUnit.Test_Caller;

with Web.Binding;
with Web.Binding.Paths;
with Web.Binding.Auth;
with Web.Binding.Decoders.UUID_Decoders;

package body Web_Binding_Auth_Tests is

   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;
   use Web.Binding;
   use Web.Binding.Paths;

   package Auth renames Web.Binding.Auth;
   package UUID renames Web.Binding.Decoders.UUID_Decoders;
   use type Auth.Auth_Scheme;

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("auth header", Test_Auth_Header'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("auth resource id", Test_Resource_Id'Access));
   end Add_Tests;

   procedure Test_Auth_Header (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Bearer : constant Auth.Credentials := Auth.Parse ("Bearer abc.def.ghi");
      Basic  : constant Auth.Credentials := Auth.Parse ("Basic dXNlcjpwYXNz");
      Other  : constant Auth.Credentials := Auth.Parse ("Negotiate xyz");
      Basic_Cred : constant Auth.Basic_Credentials := Auth.Decode_Basic (Basic);
   begin
      Assert (Bearer.Scheme = Auth.Scheme_Bearer, "bearer scheme");
      Assert (Auth.Token_Strings.To_String (Bearer.Token) = "abc.def.ghi",
              "bearer token");
      --  Basic base64 "dXNlcjpwYXNz" decodes to "user:pass".
      Assert (Basic.Scheme = Auth.Scheme_Basic, "basic scheme");
      Assert (Basic_Cred.Valid
                and then Auth.Field_Strings.To_String (Basic_Cred.User_Id) = "user"
                and then Auth.Field_Strings.To_String (Basic_Cred.Password) = "pass",
              "basic userid:password");
      Assert (Other.Scheme = Auth.Scheme_Other
                and then Auth.Scheme_Strings.To_String (Other.Raw_Scheme)
                           = "Negotiate", "other scheme kept raw");
      --  No verification: an unparseable header is just invalid, not "denied".
      Assert (not Auth.Parse ("").Valid, "empty header invalid");
      Assert (not Auth.Decode_Basic (Bearer).Valid, "bearer is not basic");
      Assert (not Auth.Decode_Basic (Auth.Parse ("Basic !!!")).Valid,
              "malformed basic base64 rejected");
   end Test_Auth_Header;

   procedure Test_Resource_Id (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Res_Path : constant Field_Path :=
        Append_Field (Rooted (Route_Parameter), "project_id");
      Decoded : constant UUID.Result :=
        UUID.Decode ("550E8400-E29B-41D4-A716-446655440000", Res_Path,
                     Route_Parameter);
   begin
      --  Binding produces the typed resource id; authorization (elsewhere)
      --  decides whether the principal may use it. Binding makes no such
      --  decision.
      Assert (UUID.Results.Succeeded (Decoded), "resource id decodes");
      Assert (UUID.Image (UUID.Results.Value_Of (Decoded))
                = "550e8400-e29b-41d4-a716-446655440000",
              "normalized resource id available to authorization");
   end Test_Resource_Id;

end Web_Binding_Auth_Tests;
