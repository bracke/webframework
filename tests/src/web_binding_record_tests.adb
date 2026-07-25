with AUnit.Assertions;
with AUnit.Test_Caller;

with Web.Binding;
with Web.Binding.Paths;
with Web.Binding.Policies;
with Web.Binding.Errors;
with Web.Binding.Query;
with Web.Binding.Record_Binders;
with Web.Binding.Decoders.Integer_Decoders;
with Web.Binding.Decoders.Boolean_Decoders;

package body Web_Binding_Record_Tests is

   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;

   use Web.Binding;
   use Web.Binding.Paths;
   use Web.Binding.Policies;
   use Web.Binding.Errors;

   --  Target record: Page is optional-with-default, Active is required.
   type Params is record
      Page   : Integer := 1;
      Active : Boolean := False;
   end record;

   procedure Set_Page (Rec : in out Params; Value : Integer) is
   begin
      Rec.Page := Value;
   end Set_Page;

   procedure Set_Active (Rec : in out Params; Value : Boolean) is
   begin
      Rec.Active := Value;
   end Set_Active;

   package RB is new Web.Binding.Record_Binders (Params);
   package Int_Dec is new Web.Binding.Decoders.Integer_Decoders (Integer);
   package Bool_Dec renames Web.Binding.Decoders.Boolean_Decoders;

   function Int_Decode
     (Text : String; P : Field_Path; S : Source_Kind)
      return Int_Dec.Results.Result is (Int_Dec.Decode (Text, P, S));

   function Bool_Decode
     (Text : String; P : Field_Path; S : Source_Kind)
      return Bool_Dec.Results.Result is (Bool_Dec.Decode (Text, P, S));

   procedure Bind_Page is new RB.Bind_Scalar
     (Integer, Int_Dec.Results, Int_Decode, Set_Page);
   procedure Bind_Active is new RB.Bind_Scalar
     (Boolean, Bool_Dec.Results, Bool_Decode, Set_Active);

   Page_Path   : constant Field_Path :=
     Append_Field (Rooted (Query_Parameter), "page");
   Active_Path : constant Field_Path :=
     Append_Field (Rooted (Query_Parameter), "active");

   --  Bind the two fields from a query string.
   function Bind
     (Q    : String;
      Mode : Aggregation_Mode := Aggregate_Fields) return RB.Results.Result
   is
      Src : constant Web.Binding.Query.Query_Source := Web.Binding.Query.Parse (Q);
      B   : RB.Builder := RB.Start ((Page => 1, Active => False), Mode);
   begin
      Bind_Page
        (B, Web.Binding.Query.Lookup (Src, "page"), Page_Path, Query_Parameter,
         Optional_With_Default);
      Bind_Active
        (B, Web.Binding.Query.Lookup (Src, "active"), Active_Path, Query_Parameter,
         Required);
      return RB.Finish (B);
   end Bind;

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("record success", Test_Success'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("record errors", Test_Errors'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("record aggregation", Test_Aggregation'Access));
   end Add_Tests;

   procedure Test_Success (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Full : constant RB.Results.Result := Bind ("page=5&active=true");
      Dflt : constant RB.Results.Result := Bind ("active=true");
   begin
      Assert (RB.Results.Succeeded (Full), "full bind succeeds");
      Assert (RB.Results.Value_Of (Full).Page = 5
                and then RB.Results.Value_Of (Full).Active, "assembled fields");
      --  Optional field absent keeps its seeded default.
      Assert (RB.Results.Succeeded (Dflt)
                and then RB.Results.Value_Of (Dflt).Page = 1,
              "absent optional keeps default");
   end Test_Success;

   procedure Test_Errors (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Missing   : constant RB.Results.Result := Bind ("page=5");
      Malformed : constant RB.Results.Result := Bind ("page=abc&active=true");
   begin
      --  Missing required field: a failure, not a partial value.
      Assert (not RB.Results.Succeeded (Missing), "missing required fails");
      Assert (Length (RB.Results.Errors_Of (Missing)) = 1, "one error");
      Assert (Element (RB.Results.Errors_Of (Missing), 1).Id = Binding_Missing,
              "binding.missing");
      --  Malformed present value is an error and is NOT replaced by a default.
      Assert (not RB.Results.Succeeded (Malformed), "malformed fails");
      Assert (Element (RB.Results.Errors_Of (Malformed), 1).Id
                = Decode_Invalid_Integer, "malformed is a decode error");
   end Test_Errors;

   procedure Test_Aggregation (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Agg : constant RB.Results.Result :=
        Bind ("page=abc&active=maybe", Aggregate_Fields);
      FF  : constant RB.Results.Result :=
        Bind ("page=abc&active=maybe", Fail_Fast);
   begin
      --  Aggregate collects both, in field-declaration (call) order.
      Assert (Length (RB.Results.Errors_Of (Agg)) = 2, "two aggregated errors");
      Assert (Element (RB.Results.Errors_Of (Agg), 1).Id = Decode_Invalid_Integer,
              "page error first");
      Assert (Element (RB.Results.Errors_Of (Agg), 2).Id = Decode_Invalid_Boolean,
              "active error second");
      --  Fail-fast stops after the first.
      Assert (Length (RB.Results.Errors_Of (FF)) = 1, "fail-fast stops at one");
   end Test_Aggregation;

end Web_Binding_Record_Tests;
