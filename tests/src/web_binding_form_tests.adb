with AUnit.Assertions;
with AUnit.Test_Caller;

with Web.Binding;
with Web.Binding.Paths;
with Web.Binding.Errors;
with Web.Binding.Policies;
with Web.Binding.Forms;

package body Web_Binding_Form_Tests is

   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;
   use Web.Binding;
   use Web.Binding.Paths;
   use Web.Binding.Errors;
   use Web.Binding.Policies;
   use Web.Binding.Forms;

   Body_Root : constant Field_Path := Rooted (Structured_Body);

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("form rerender", Test_Rerender'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("form states", Test_States'Access));
   end Add_Tests;

   procedure Test_Rerender (Item : in out Fixture) is
      pragma Unreferenced (Item);
      F    : Form;
      Errs : Error_Collection := Empty_Collection;
   begin
      Reset (F);
      Assert (State (F) = Not_Submitted, "starts unsubmitted");

      Begin_Submission (F);
      Record_Field (F, "name", "Alice", Public_Value);
      Record_Field (F, "age", "abc", Public_Value);       --  invalid input
      Record_Field (F, "password", "s3cret", Secret_Value);

      --  Bind produced a field error for age and a form-level error.
      Append (Errs, Make_Error
                (Decode_Invalid_Integer, Append_Field (Body_Root, "age"),
                 Structured_Body));
      Append (Errs, Make_Error (Json_Malformed, Body_Root, Structured_Body));
      Import_Errors (F, Errs);
      Finish_Decoding (F);

      Assert (State (F) = Decode_Failed, "decode failed");
      Assert (Was_Submitted (F), "submitted");
      --  Valid and invalid fields keep their submitted values for re-render.
      Assert (Field_Value (F, "name") = "Alice", "name retained");
      Assert (Field_Value (F, "age") = "abc", "invalid input retained");
      --  A secret field is never retained.
      Assert (Field_Value (F, "password") = "", "secret not retained");
      Assert (not Field_Retained (F, "password"), "secret marked not retained");
      --  Errors attach per field, and form-level errors are non-field.
      Assert (Field_Has_Error (F, "age"), "age has an error");
      Assert (Field_Error (F, "age") = Decode_Invalid_Integer, "age error id");
      Assert (not Field_Has_Error (F, "name"), "name has no error");
      Assert (Non_Field_Errors (F) = 1, "one non-field error");
      Assert (Web.Binding.Forms.Error_Count (F) = 2, "two errors total");
   end Test_Rerender;

   procedure Test_States (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Clean : Form;
      Bad   : Form;
   begin
      --  A clean submission: decoded then validated.
      Reset (Clean);
      Begin_Submission (Clean);
      Record_Field (Clean, "name", "Bob", Public_Value);
      Finish_Decoding (Clean);
      Assert (State (Clean) = Decoded, "decoded");
      Finish_Validation (Clean, Valid => True);
      Assert (State (Clean) = Validated, "validated");

      --  Decoded but semantic validation fails.
      Reset (Bad);
      Begin_Submission (Bad);
      Finish_Decoding (Bad);
      Finish_Validation (Bad, Valid => False);
      Assert (State (Bad) = Validation_Failed, "validation failed");
   end Test_States;

end Web_Binding_Form_Tests;
