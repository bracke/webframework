with AUnit.Assertions;
with AUnit.Test_Caller;

with Web.Binding;
with Web.Binding.Paths;
with Web.Binding.Errors;
with Web.Binding.Policies;
with Web.Binding.Sources;
with Web.Binding.Query;
with Web.Binding.Decoders.Integer_Decoders;
with Web.Binding.Validation;

package body Web_Binding_Validation_Tests is

   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;
   use Web.Binding;
   use Web.Binding.Paths;
   use Web.Binding.Errors;
   use Web.Binding.Policies;
   use Web.Binding.Sources;
   use Web.Binding.Validation;

   package Int_Dec is new Web.Binding.Decoders.Integer_Decoders (Integer);

   Age_Path : constant Field_Path :=
     Append_Field (Rooted (Query_Parameter), "age");

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("validation semantic failure",
                               Test_Semantic_Failure'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("validation merged origin",
                               Test_Merged_Origin'Access));
   end Add_Tests;

   procedure Test_Semantic_Failure (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Q   : constant Web.Binding.Query.Query_Source :=
        Web.Binding.Query.Parse ("age=15");
      Occ : constant Occurrences := Web.Binding.Query.Lookup (Q, "age");
      Res : constant Scalar_Resolution :=
        Resolve_Scalar (Occ, Reject, Reject_Empty);
      Decoded : constant Int_Dec.Results.Result :=
        Int_Dec.Decode (Value (Occ, Res.Index), Age_Path, Query_Parameter);
      P   : Presentation;
   begin
      --  Decoding succeeds: a typed value handed to validation.
      Assert (Int_Dec.Results.Succeeded (Decoded), "age decodes");

      Reset (P);
      Add_Decoding_Errors (P, Empty_Collection);   --  no decoding errors
      --  Semantic rule (NOT a binding rule): age must be at least 18.
      if Int_Dec.Results.Value_Of (Decoded) < 18 then
         Add_Validation_Issue (P, "age", "validation.too_young", Render (Age_Path));
      end if;

      Assert (Count (P) = 1, "one issue");
      Assert (Decoding_Count (P) = 0, "no decoding issues");
      Assert (Validation_Count (P) = 1, "one validation issue");
      Assert (Origin_Of (P, 1) = From_Validation, "validation origin");
      Assert (Field_Of (P, 1) = "age", "field");
      Assert (Key_Of (P, 1) = "validation.too_young", "code");
      Assert (Path_Of (P, 1) = "query.age", "compatible path");
   end Test_Semantic_Failure;

   procedure Test_Merged_Origin (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Errs : Error_Collection := Empty_Collection;
      P    : Presentation;
   begin
      Append (Errs, Make_Error
                (Decode_Invalid_Integer,
                 Append_Field (Rooted (Structured_Body), "count"),
                 Structured_Body));

      Reset (P);
      Add_Decoding_Errors (P, Errs);
      Add_Validation_Issue (P, "email", "validation.email_taken", "body.email");

      Assert (Count (P) = 2, "two entries");
      Assert (Decoding_Count (P) = 1 and then Validation_Count (P) = 1,
              "one of each origin");
      --  Decoding entries come first, preserving origin and key.
      Assert (Origin_Of (P, 1) = From_Decoding, "first is decoding");
      Assert (Key_Of (P, 1) = "decode.invalid_integer", "decoding key");
      Assert (Path_Of (P, 1) = "body.count", "decoding path");
      Assert (Origin_Of (P, 2) = From_Validation, "second is validation");
      Assert (Key_Of (P, 2) = "validation.email_taken", "validation code");
   end Test_Merged_Origin;

end Web_Binding_Validation_Tests;
