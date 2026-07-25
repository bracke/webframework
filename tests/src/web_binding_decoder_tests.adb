with Ada.Strings.Bounded;
with AUnit.Assertions;
with AUnit.Test_Caller;

with Web.Binding;
with Web.Binding.Errors;
with Web.Binding.Paths;
with Web.Binding.Decoders.Integer_Decoders;
with Web.Binding.Decoders.Boolean_Decoders;
with Web.Binding.Decoders.Text_Decoders;
with Web.Binding.Decoders.Enum_Decoders;
with Web.Binding.Decoders.UUID_Decoders;
with Web.Binding.Decoders.Optional_Decoders;
with Web.Binding.Decoders.Defaulted_Decoders;

package body Web_Binding_Decoder_Tests is

   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;

   use Web.Binding;
   use Web.Binding.Paths;
   use Web.Binding.Errors;

   Src  : constant Source_Kind := Query_Parameter;
   Path : constant Field_Path := Append_Field (Rooted (Query_Parameter), "f");

   --  Instantiations used across tests.
   package Int_Dec is new Web.Binding.Decoders.Integer_Decoders (Integer);

   type Byte_Range is range 0 .. 255;
   package Byte_Dec is new Web.Binding.Decoders.Integer_Decoders (Byte_Range);

   package B16 is new Ada.Strings.Bounded.Generic_Bounded_Length (16);
   package Text_Dec is new Web.Binding.Decoders.Text_Decoders (B16);

   type Color is (Red, Green, Blue);
   package Color_Dec is new Web.Binding.Decoders.Enum_Decoders (Color);

   package UUID_Dec renames Web.Binding.Decoders.UUID_Decoders;

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("decoder integer", Test_Integer'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("decoder boolean", Test_Boolean'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("decoder text", Test_Text'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("decoder enum", Test_Enum'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("decoder uuid", Test_UUID'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("decoder combinators", Test_Combinators'Access));
   end Add_Tests;

   procedure Test_Integer (Item : in out Fixture) is
      pragma Unreferenced (Item);

      function Int_Fail_Id (Text : String) return Error_Id is
        (Element (Int_Dec.Results.Errors_Of (Int_Dec.Decode (Text, Path, Src)), 1).Id);

      Loose : Int_Dec.Config := Int_Dec.Default_Config;
      Ok    : constant Int_Dec.Result := Int_Dec.Decode ("42", Path, Src);
      Neg   : constant Int_Dec.Result := Int_Dec.Decode ("-5", Path, Src);
   begin
      --  Valid values.
      Assert (Int_Dec.Results.Succeeded (Ok), "42 decodes");
      Assert (Int_Dec.Results.Value_Of (Ok) = 42, "42 = 42");
      Assert (Int_Dec.Results.Succeeded (Neg)
                and then Int_Dec.Results.Value_Of (Neg) = -5, "-5 decodes");

      --  Invalid syntax (distinct from out of range).
      Assert (Int_Fail_Id ("abc") = Decode_Invalid_Integer, "abc invalid");
      Assert (Int_Fail_Id ("") = Decode_Invalid_Integer, "empty invalid");
      Assert (Int_Fail_Id (" 42") = Decode_Invalid_Integer, "leading ws invalid");
      Assert (Int_Fail_Id ("42 ") = Decode_Invalid_Integer, "trailing ws invalid");
      Assert (Int_Fail_Id ("+5") = Decode_Invalid_Integer, "leading plus invalid");
      Assert (Int_Fail_Id ("1_000") = Decode_Invalid_Integer, "separator invalid");

      --  Out of range (distinct from invalid syntax), never an exception.
      Assert
        (Element
           (Byte_Dec.Results.Errors_Of (Byte_Dec.Decode ("256", Path, Src)), 1).Id
           = Decode_Integer_Out_Of_Range, "256 out of range for 0..255");
      Assert
        (Element
           (Byte_Dec.Results.Errors_Of (Byte_Dec.Decode ("-1", Path, Src)), 1).Id
           = Decode_Integer_Out_Of_Range, "-1 out of range for 0..255");
      Assert
        (Byte_Dec.Results.Succeeded (Byte_Dec.Decode ("255", Path, Src)),
         "255 is the boundary");
      Assert
        (Int_Fail_Id ("99999999999999999999999999")
           = Decode_Integer_Out_Of_Range, "huge value overflows to range error");

      --  Opt-in policies.
      Loose.Allow_Leading_Plus := True;
      Loose.Allow_Separators := True;
      Assert
        (Int_Dec.Results.Succeeded (Int_Dec.Decode ("+5", Path, Src, Loose))
           and then Int_Dec.Results.Value_Of
                      (Int_Dec.Decode ("+5", Path, Src, Loose)) = 5,
         "leading plus accepted when enabled");
      Assert
        (Int_Dec.Results.Value_Of (Int_Dec.Decode ("1_000", Path, Src, Loose))
           = 1_000,
         "separators accepted when enabled");
   end Test_Integer;

   procedure Test_Boolean (Item : in out Fixture) is
      pragma Unreferenced (Item);
      package Bool renames Web.Binding.Decoders.Boolean_Decoders;
      Ci : Bool.Config := Bool.Default_Config;
      Sets : Bool.Config := Bool.Default_Config;
   begin
      Assert (Bool.Results.Value_Of (Bool.Decode ("true", Path, Src)), "true");
      Assert (not Bool.Results.Value_Of (Bool.Decode ("false", Path, Src)), "false");
      Assert
        (Element (Bool.Results.Errors_Of (Bool.Decode ("1", Path, Src)), 1).Id
           = Decode_Invalid_Boolean, "1 not accepted by narrow default");
      Assert
        (not Bool.Results.Succeeded (Bool.Decode ("TRUE", Path, Src)),
         "TRUE rejected case-sensitively");

      Ci.Case_Insensitive := True;
      Assert (Bool.Results.Value_Of (Bool.Decode ("TRUE", Path, Src, Ci)),
              "TRUE accepted case-insensitively");

      Sets.Accept_Sets (Bool.One_Zero) := True;
      Sets.Accept_Sets (Bool.Yes_No) := True;
      Assert (Bool.Results.Value_Of (Bool.Decode ("1", Path, Src, Sets)), "1 true");
      Assert (not Bool.Results.Value_Of (Bool.Decode ("no", Path, Src, Sets)), "no false");
   end Test_Boolean;

   procedure Test_Text (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Bad_UTF8 : constant String := [1 => Character'Val (16#FF#)];
      Too_Long : constant String := [1 .. 17 => 'a'];
   begin
      Assert (Text_Dec.Results.Succeeded (Text_Dec.Decode ("hello", Path, Src)),
              "hello decodes");
      Assert
        (Element (Text_Dec.Results.Errors_Of (Text_Dec.Decode (Bad_UTF8, Path, Src)), 1).Id
           = Decode_Invalid_UTF8, "invalid utf8 detected");
      Assert
        (Element (Text_Dec.Results.Errors_Of (Text_Dec.Decode (Too_Long, Path, Src)), 1).Id
           = Decode_Value_Too_Long, "over capacity rejected");
   end Test_Text;

   procedure Test_Enum (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Table : constant Color_Dec.Mapping_Table :=
        Color_Dec.Add
          (Color_Dec.Add
             (Color_Dec.Add
                (Color_Dec.Add
                   (Color_Dec.Empty_Table (Color_Dec.ASCII_Case_Insensitive),
                    "red", Red),
                 "green", Green),
              "blue", Blue),
           "grn", Green, Deprecated => True);
   begin
      Assert (Color_Dec.Results.Value_Of (Color_Dec.Decode ("green", Path, Src, Table)) = Green,
              "green maps");
      Assert (Color_Dec.Results.Value_Of (Color_Dec.Decode ("GREEN", Path, Src, Table)) = Green,
              "case-insensitive match");
      Assert (Color_Dec.Results.Value_Of (Color_Dec.Decode ("grn", Path, Src, Table)) = Green,
              "deprecated alias still accepted");
      Assert
        (Element (Color_Dec.Results.Errors_Of (Color_Dec.Decode ("purple", Path, Src, Table)), 1).Id
           = Decode_Invalid_Enum, "unknown wire rejected");
   end Test_Enum;

   procedure Test_UUID (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Canonical : constant String := "550E8400-E29B-41D4-A716-446655440000";
      Ok        : constant UUID_Dec.Result := UUID_Dec.Decode (Canonical, Path, Src);
   begin
      Assert (UUID_Dec.Results.Succeeded (Ok), "canonical uuid decodes");
      Assert
        (UUID_Dec.Image (UUID_Dec.Results.Value_Of (Ok))
           = "550e8400-e29b-41d4-a716-446655440000",
         "normalized to lowercase");
      Assert
        (Element (UUID_Dec.Results.Errors_Of (UUID_Dec.Decode ("not-a-uuid", Path, Src)), 1).Id
           = Decode_Invalid_UUID, "non-uuid rejected");
      Assert
        (not UUID_Dec.Results.Succeeded
           (UUID_Dec.Decode ("550e8400e29b41d4a716446655440000", Path, Src)),
         "missing hyphens rejected");
   end Test_UUID;

   function Int_Base
     (Text   : String;
      P      : Field_Path;
      S      : Source_Kind) return Int_Dec.Results.Result is
     (Int_Dec.Decode (Text, P, S));

   package Int_Optional is new Web.Binding.Decoders.Optional_Decoders
     (Target => Integer, Base_Results => Int_Dec.Results, Base_Decode => Int_Base);

   package Int_Defaulted is new Web.Binding.Decoders.Defaulted_Decoders
     (Target => Integer, Base_Results => Int_Dec.Results, Base_Decode => Int_Base);

   procedure Test_Combinators (Item : in out Fixture) is
      pragma Unreferenced (Item);
      None    : constant Int_Optional.Result :=
        Int_Optional.Decode (Is_Present => False, Text => "", Path => Path, Source => Src);
      Some_Opt    : constant Int_Optional.Result :=
        Int_Optional.Decode (Is_Present => True, Text => "7", Path => Path, Source => Src);
      Bad_Opt : constant Int_Optional.Result :=
        Int_Optional.Decode (Is_Present => True, Text => "x", Path => Path, Source => Src);
      Absent  : constant Int_Dec.Results.Result :=
        Int_Defaulted.Decode (False, 1, "", Path, Src);
      Present : constant Int_Dec.Results.Result :=
        Int_Defaulted.Decode (True, 1, "7", Path, Src);
      Bad_Def : constant Int_Dec.Results.Result :=
        Int_Defaulted.Decode (True, 1, "x", Path, Src);
   begin
      --  Optional: absence is None, presence decodes, malformed is not None.
      Assert (Int_Optional.Results.Succeeded (None)
                and then not Int_Optional.Results.Value_Of (None).Present,
              "absent optional is None");
      Assert (Int_Optional.Results.Value_Of (Some_Opt).Present
                and then Int_Optional.Results.Value_Of (Some_Opt).Value = 7,
              "present optional decodes");
      Assert (not Int_Optional.Results.Succeeded (Bad_Opt),
              "malformed present optional is an error, not None");

      --  Default: absence uses the default, malformed is NOT defaulted.
      Assert (Int_Dec.Results.Value_Of (Absent) = 1, "absent uses default");
      Assert (Int_Dec.Results.Value_Of (Present) = 7, "present decodes");
      Assert (not Int_Dec.Results.Succeeded (Bad_Def),
              "malformed present is an error, not the default");
   end Test_Combinators;

end Web_Binding_Decoder_Tests;
