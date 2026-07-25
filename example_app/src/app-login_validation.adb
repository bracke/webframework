with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Validation.Identifiers;
with Validation.Contexts;
with Validation.Validators;
with Validation.Standard.Text;

package body App.Login_Validation is

   package Ids renames Validation.Identifiers;

   type Login_Input is record
      Username : Unbounded_String;
   end record;

   function Get_Username (Input : Login_Input) return String is
     (To_String (Input.Username));

   package LV is new Validation.Validators (Login_Input);
   package Username_Text is
     new Validation.Standard.Text (Login_Input, LV, Get_Username);

   F_Username : constant Ids.Field_Id := Ids.Field_Ids.Make ("username");

   function Build return LV.Validator is
      B : LV.Builder := LV.Start (Ids.Validator_Ids.Make ("login"));
   begin
      LV.Add (B, Username_Text.Non_Blank
                   (F_Username, Ids.Rule_Ids.Make ("username/present")));
      LV.Add (B, Username_Text.Max_Length
                   (F_Username, 100, Ids.Rule_Ids.Make ("username/maxlen")));
      LV.Add (B, Username_Text.Valid_UTF8
                   (F_Username, Ids.Rule_Ids.Make ("username/utf8")));
      return LV.Get_Validator (LV.Finalize (B));
   end Build;

   The_Validator : constant LV.Validator := Build;
   Empty_Context : constant Validation.Contexts.Context :=
     Validation.Contexts.Freeze (Validation.Contexts.New_Builder);

   function Validate_Username
     (Username : String) return Validation.Results.Result is
     (LV.Validate ((Username => To_Unbounded_String (Username)),
      The_Validator, Empty_Context));

end App.Login_Validation;
