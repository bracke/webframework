with AUnit.Assertions;
with AUnit.Test_Caller;

with Web.Binding;
with Web.Binding.Paths;
with Web.Binding.Errors;
with Web.Binding.Results;
with Web.Binding.Requests;
with Web.Binding.Contexts;
with Web.Binding.Policies;

package body Web_Binding_Handler_Tests is

   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;
   use Web.Binding;
   use Web.Binding.Paths;
   use Web.Binding.Errors;
   use Web.Binding.Requests;

   package Int_Results is new Web.Binding.Results (Integer);

   --  Handler outcomes captured for assertion.
   Success_Called : Boolean := False;
   Failure_Called : Boolean := False;
   Last_Value     : Integer := 0;
   Last_Class     : Failure_Class := Internal_Error;

   procedure On_Ok (Value : Integer) is
   begin
      Success_Called := True;
      Last_Value := Value;
   end On_Ok;

   procedure On_Err
     (Class : Failure_Class; Errors : Error_Collection) is
      pragma Unreferenced (Errors);
   begin
      Failure_Called := True;
      Last_Class := Class;
   end On_Err;

   procedure Do_Dispatch is new Web.Binding.Requests.Dispatch
     (Integer, Int_Results, On_Ok, On_Err);

   function One (Id : Error_Id; Source : Source_Kind := Structured_Body)
      return Error_Collection
   is
      C : Error_Collection := Empty_Collection;
   begin
      Append (C, Make_Error (Id, Rooted (Source), Source));
      return C;
   end One;

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("handler classify", Test_Classify'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("handler context", Test_Context'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("handler dispatch", Test_Dispatch'Access));
   end Add_Tests;

   procedure Test_Classify (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Mixed : Error_Collection := Empty_Collection;
      Route : Error_Collection := Empty_Collection;
   begin
      Assert (Classify (Decode_Invalid_Integer) = Bad_Request, "400 malformed");
      Assert (Classify (Binding_Missing) = Bad_Request, "400 missing");
      Assert (Classify (Body_Unsupported_Media_Type) = Unsupported_Media_Type,
              "415 media");
      Assert (Classify (Body_Too_Large) = Payload_Too_Large, "413 too large");
      Assert (Classify (Internal_Binding_Definition_Error) = Internal_Error,
              "500 internal");

      --  Worst class wins across a collection.
      Append (Mixed, Make_Error (Decode_Invalid_Integer, Rooted (Structured_Body),
                                 Structured_Body));
      Append (Mixed, Make_Error (Body_Too_Large, Rooted (Structured_Body),
                                 Structured_Body));
      Assert (Classify (Mixed) = Payload_Too_Large, "worst class wins");

      --  A route-parameter Bad_Request may map to 404 under route policy.
      Append (Route, Make_Error (Binding_Missing, Rooted (Route_Parameter),
                                 Route_Parameter));
      Assert (Classify (Route) = Bad_Request, "route default 400");
      Assert (Classify (Route, Route_Not_Found => True) = Not_Found,
              "route policy 404");
   end Test_Classify;

   procedure Test_Context (Item : in out Fixture) is
      pragma Unreferenced (Item);
      use Web.Binding.Contexts;
      use type Web.Binding.Policies.Aggregation_Mode;
      Ctx : constant Binding_Context :=
        New_Context (Correlation => "req-42");
   begin
      Assert (Correlation_Strings.To_String (Ctx.Correlation) = "req-42",
              "correlation carried");
      Assert (Ctx.Mode = Web.Binding.Policies.Aggregate_Fields, "default mode");
      Assert (not Ctx.Diagnostics, "diagnostics off by default");
   end Test_Context;

   procedure Test_Dispatch (Item : in out Fixture) is
      pragma Unreferenced (Item);
   begin
      --  Success: the handler runs with the typed value; the mapper does not.
      Success_Called := False;
      Failure_Called := False;
      Do_Dispatch (Int_Results.Make_Success (42));
      Assert (Success_Called and then Last_Value = 42, "handler got typed value");
      Assert (not Failure_Called, "no failure on success");

      --  Failure: the handler does not run; the mapper gets the class.
      Success_Called := False;
      Failure_Called := False;
      Do_Dispatch (Int_Results.Make_Failure (One (Body_Too_Large)));
      Assert (Failure_Called and then Last_Class = Payload_Too_Large,
              "mapper got classification");
      Assert (not Success_Called, "handler not run on failure");
   end Test_Dispatch;

end Web_Binding_Handler_Tests;
