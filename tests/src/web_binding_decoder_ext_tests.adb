with Ada.Strings.Bounded;
with AUnit.Assertions;
with AUnit.Test_Caller;

with Web.Binding;
with Web.Binding.Errors;
with Web.Binding.Paths;
with Web.Binding.Decoders.Date_Decoders;
with Web.Binding.Decoders.Time_Decoders;
with Web.Binding.Decoders.DateTime_Decoders;
with Web.Binding.Decoders.Modular_Decoders;
with Web.Binding.Decoders.Float_Decoders;
with Web.Binding.Decoders.Base64_Decoders;

package body Web_Binding_Decoder_Ext_Tests is

   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;

   use Web.Binding;
   use Web.Binding.Paths;
   use Web.Binding.Errors;

   Src  : constant Source_Kind := Query_Parameter;
   Path : constant Field_Path := Append_Field (Rooted (Query_Parameter), "f");

   package Date_Dec renames Web.Binding.Decoders.Date_Decoders;
   package Time_Dec renames Web.Binding.Decoders.Time_Decoders;
   package DT_Dec   renames Web.Binding.Decoders.DateTime_Decoders;

   type Mod256 is mod 256;
   package Mod_Dec is new Web.Binding.Decoders.Modular_Decoders (Mod256);

   package Flt_Dec is new Web.Binding.Decoders.Float_Decoders (Float);

   package B32 is new Ada.Strings.Bounded.Generic_Bounded_Length (32);
   package B64_Dec is new Web.Binding.Decoders.Base64_Decoders (B32);

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("decoder date", Test_Date'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("decoder time", Test_Time'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("decoder datetime", Test_DateTime'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("decoder modular", Test_Modular'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("decoder float", Test_Float'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("decoder base64", Test_Base64'Access));
   end Add_Tests;

   procedure Test_Date (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Ok : constant Date_Dec.Result := Date_Dec.Decode ("2026-07-25", Path, Src);

      function Bad (Text : String) return Boolean is
        (Element (Date_Dec.Results.Errors_Of (Date_Dec.Decode (Text, Path, Src)), 1).Id
           = Decode_Invalid_Date);
   begin
      Assert (Date_Dec.Results.Succeeded (Ok), "valid date decodes");
      Assert (Date_Dec.Results.Value_Of (Ok).Year = 2026
                and then Date_Dec.Results.Value_Of (Ok).Month = 7
                and then Date_Dec.Results.Value_Of (Ok).Day = 25, "fields");
      Assert (Bad ("2026-02-31"), "impossible date is a decode failure");
      Assert (Date_Dec.Results.Succeeded (Date_Dec.Decode ("2024-02-29", Path, Src)),
              "leap day valid in a leap year");
      Assert (Bad ("2025-02-29"), "leap day invalid in a common year");
      Assert (Bad ("2026-13-01"), "bad month");
      Assert (Bad ("2026-7-5"), "non-canonical format");
      Assert (Bad (""), "empty");
   end Test_Date;

   procedure Test_Time (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Frac : constant Time_Dec.Result := Time_Dec.Decode ("13:45:30.5", Path, Src);

      function Bad (Text : String) return Boolean is
        (Element (Time_Dec.Results.Errors_Of (Time_Dec.Decode (Text, Path, Src)), 1).Id
           = Decode_Invalid_Time);
   begin
      Assert (Time_Dec.Results.Succeeded (Time_Dec.Decode ("13:45:30", Path, Src)),
              "valid time");
      Assert (Time_Dec.Results.Succeeded (Frac)
                and then Time_Dec.Results.Value_Of (Frac).Milli = 500,
              "fractional seconds keep millis");
      Assert (Bad ("24:00:00"), "hour out of range");
      Assert (Bad ("12:60:00"), "minute out of range");
      Assert (Time_Dec.Results.Succeeded (Time_Dec.Decode ("12:00:60", Path, Src)),
              "leap second permitted");
      Assert (Bad ("1:2:3"), "non-canonical format");
   end Test_Time;

   procedure Test_DateTime (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Zulu : constant DT_Dec.Result :=
        DT_Dec.Decode ("2026-07-25T13:45:30Z", Path, Src);
      Off  : constant DT_Dec.Result :=
        DT_Dec.Decode ("2026-07-25T13:45:30.123-05:30", Path, Src);

      function Bad (Text : String) return Boolean is
        (Element (DT_Dec.Results.Errors_Of (DT_Dec.Decode (Text, Path, Src)), 1).Id
           = Decode_Invalid_Datetime);
   begin
      Assert (DT_Dec.Results.Succeeded (Zulu)
                and then DT_Dec.Results.Value_Of (Zulu).Offset_Minutes = 0,
              "Z offset");
      Assert (DT_Dec.Results.Succeeded (Off)
                and then DT_Dec.Results.Value_Of (Off).Offset_Minutes = -330
                and then DT_Dec.Results.Value_Of (Off).Time.Milli = 123,
              "fraction and negative offset");
      Assert (DT_Dec.Results.Succeeded
                (DT_Dec.Decode ("2026-07-25 13:45:30Z", Path, Src)),
              "space separator accepted");
      Assert (Bad ("2026-02-31T00:00:00Z"), "impossible instant");
      Assert (Bad ("2026-07-25T13:45:30"), "missing required offset");
      Assert (Bad ("2026-07-25T13:45:30Zx"), "trailing content");
   end Test_DateTime;

   procedure Test_Modular (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Hex : Mod_Dec.Config := Mod_Dec.Default_Config;
   begin
      Assert (Mod_Dec.Results.Value_Of (Mod_Dec.Decode ("200", Path, Src)) = 200,
              "value");
      Assert
        (Element (Mod_Dec.Results.Errors_Of (Mod_Dec.Decode ("256", Path, Src)), 1).Id
           = Decode_Integer_Out_Of_Range, "at modulus is out of range");
      Assert
        (Element (Mod_Dec.Results.Errors_Of (Mod_Dec.Decode ("zz", Path, Src)), 1).Id
           = Decode_Invalid_Integer, "invalid syntax");
      Hex.Base := Mod_Dec.Hexadecimal;
      Assert (Mod_Dec.Results.Value_Of (Mod_Dec.Decode ("ff", Path, Src, Hex)) = 255,
              "hex radix");
   end Test_Modular;

   procedure Test_Float (Item : in out Fixture) is
      pragma Unreferenced (Item);
      A : constant Flt_Dec.Result := Flt_Dec.Decode ("1.5", Path, Src);
      B : constant Flt_Dec.Result := Flt_Dec.Decode ("-3.14e2", Path, Src);
   begin
      Assert (Flt_Dec.Results.Succeeded (A)
                and then abs (Flt_Dec.Results.Value_Of (A) - 1.5) < 0.0001, "1.5");
      Assert (Flt_Dec.Results.Succeeded (B)
                and then abs (Flt_Dec.Results.Value_Of (B) + 314.0) < 0.01, "-3.14e2");
      Assert
        (Element (Flt_Dec.Results.Errors_Of (Flt_Dec.Decode ("abc", Path, Src)), 1).Id
           = Decode_Invalid_Float, "abc invalid");
      Assert
        (Element (Flt_Dec.Results.Errors_Of (Flt_Dec.Decode ("1.", Path, Src)), 1).Id
           = Decode_Invalid_Float, "trailing dot invalid");
      Assert
        (Element (Flt_Dec.Results.Errors_Of (Flt_Dec.Decode ("nan", Path, Src)), 1).Id
           = Decode_Non_Finite_Float, "nan non-finite");
      Assert
        (Element (Flt_Dec.Results.Errors_Of (Flt_Dec.Decode ("inf", Path, Src)), 1).Id
           = Decode_Non_Finite_Float, "inf non-finite");
   end Test_Float;

   procedure Test_Base64 (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Ok      : constant B64_Dec.Result := B64_Dec.Decode ("aGVsbG8=", Path, Src);
      No_Pad  : B64_Dec.Config := B64_Dec.Default_Config;
   begin
      Assert (B64_Dec.Results.Succeeded (Ok)
                and then B32.To_String (B64_Dec.Results.Value_Of (Ok)) = "hello",
              "hello decodes");
      Assert
        (Element (B64_Dec.Results.Errors_Of (B64_Dec.Decode ("aGVsbG8", Path, Src)), 1).Id
           = Decode_Invalid_Base64, "missing padding rejected by default");
      No_Pad.Require_Padding := False;
      Assert
        (B32.To_String (B64_Dec.Results.Value_Of
           (B64_Dec.Decode ("aGVsbG8", Path, Src, No_Pad))) = "hello",
         "unpadded accepted when configured");
      Assert
        (Element (B64_Dec.Results.Errors_Of (B64_Dec.Decode ("!!!!", Path, Src)), 1).Id
           = Decode_Invalid_Base64, "bad alphabet rejected");
   end Test_Base64;

end Web_Binding_Decoder_Ext_Tests;
