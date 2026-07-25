with AUnit.Assertions;
with AUnit.Test_Caller;

with Web.Binding;
with Web.Binding.Errors;
with Web.Binding.Paths;
with Web.Binding.Limits;
with Web.Binding.Results;

package body Web_Binding_Tests is

   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;

   use Web.Binding;
   use Web.Binding.Paths;

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("binding path rendering", Test_Path_Rendering'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("binding error keys", Test_Error_Keys'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("binding error collection", Test_Error_Collection'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("binding limit layering", Test_Limit_Layering'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("binding result shape", Test_Result_Shape'Access));
   end Add_Tests;

   procedure Test_Path_Rendering (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Query   : constant Field_Path :=
        Append_Field (Rooted (Query_Parameter), "page");
      Route   : constant Field_Path :=
        Append_Field (Rooted (Route_Parameter), "project_id");
      Header  : constant Field_Path :=
        Append_Field (Rooted (Header_Value), "If-Match");
      Nested  : constant Field_Path :=
        Append_Field (Append_Field (Rooted (Structured_Body), "user"), "email");
      Indexed : constant Field_Path :=
        Append_Field
          (Append_Index
             (Append_Field (Rooted (Structured_Body), "items"), 3),
           "quantity");
      Union   : constant Field_Path :=
        Append_Field
          (Append_Alternative
             (Append_Field (Rooted (Structured_Body), "payment"), "card"),
           "expiry");
      Upload  : constant Field_Path :=
        Append_Field (Rooted (Multipart_Upload), "avatar");
   begin
      Assert (Render (Query) = "query.page", "query.page");
      Assert (Render (Route) = "route.project_id", "route.project_id");
      Assert (Render (Header) = "headers.If-Match", "headers.If-Match");
      Assert (Render (Nested) = "body.user.email", "body.user.email");
      Assert (Render (Indexed) = "body.items[3].quantity", "body.items[3].quantity");
      Assert
        (Render (Union) = "body.payment<card>.expiry", "body.payment<card>.expiry");
      Assert (Render (Upload) = "multipart.avatar", "multipart.avatar");
   end Test_Path_Rendering;

   procedure Test_Error_Keys (Item : in out Fixture) is
      pragma Unreferenced (Item);
      use Web.Binding.Errors;
   begin
      Assert (Id_Key (Binding_Missing) = "binding.missing", "binding.missing");
      Assert
        (Id_Key (Decode_Integer_Out_Of_Range) = "decode.integer_out_of_range",
         "decode.integer_out_of_range");
      Assert (Id_Key (Decode_Invalid_UTF8) = "decode.invalid_utf8", "utf8");
      Assert
        (Id_Key (Json_Duplicate_Member) = "json.duplicate_member", "json dup");
      Assert
        (Id_Key (Form_Malformed_URL_Encoding) = "form.malformed_url_encoding",
         "form enc");
      Assert
        (Id_Key (Multipart_Too_Many_Parts) = "multipart.too_many_parts",
         "multipart parts");
      Assert
        (Id_Key (Internal_Binding_Definition_Error)
           = "internal.binding_definition_error",
         "internal def");
   end Test_Error_Keys;

   procedure Test_Error_Collection (Item : in out Fixture) is
      pragma Unreferenced (Item);
      use Web.Binding.Errors;
      Ids : constant array (1 .. 5) of Error_Id :=
        [Binding_Missing, Binding_Duplicate, Binding_Empty_Not_Allowed,
         Binding_Unknown_Field, Binding_Source_Unavailable];
      C : Error_Collection := Empty_Collection (Limit => 3);
   begin
      for I in Ids'Range loop
         Append
           (C,
            Make_Error
              (Id     => Ids (I),
               Path   => Append_Field (Rooted (Query_Parameter), "f"),
               Source => Query_Parameter));
      end loop;

      Assert (Length (C) = 3, "retains exactly the limit");
      Assert (Omitted (C) = 2, "counts the overflow");
      --  Deterministic: the first three inserted are retained, in order.
      Assert (Element (C, 1).Id = Binding_Missing, "first retained");
      Assert (Element (C, 2).Id = Binding_Duplicate, "second retained");
      Assert (Element (C, 3).Id = Binding_Empty_Not_Allowed, "third retained");
   end Test_Error_Collection;

   procedure Test_Limit_Layering (Item : in out Fixture) is
      pragma Unreferenced (Item);
      use Web.Binding.Limits;
      Outer   : constant Binding_Limits := Default_Limits;
      Tighter : Binding_Limits := Default_Limits;
      Wider   : Binding_Limits := Default_Limits;
   begin
      Tighter.Max_Body_Bytes := 1_024;
      Wider.Max_Body_Bytes := Outer.Max_Body_Bytes + 1_000_000;

      Assert
        (Tighten (Outer, Tighter).Max_Body_Bytes = 1_024,
         "an inner layer may reduce a bound");
      Assert
        (Tighten (Outer, Wider).Max_Body_Bytes = Outer.Max_Body_Bytes,
         "an inner layer may not raise a bound");
      Assert (Is_Within (Tighter, Outer), "tighter is within outer");
      Assert (not Is_Within (Wider, Outer), "wider is not within outer");
   end Test_Limit_Layering;

   procedure Test_Result_Shape (Item : in out Fixture) is
      pragma Unreferenced (Item);
      package Int_Results is new Web.Binding.Results (Integer);
      use Web.Binding.Errors;
      Failed : Error_Collection := Empty_Collection;
      Ok     : constant Int_Results.Result := Int_Results.Make_Success (42);
      Bad    : Int_Results.Result;
   begin
      Append
        (Failed,
         Make_Error
           (Binding_Missing,
            Append_Field (Rooted (Query_Parameter), "page"), Query_Parameter));
      Bad := Int_Results.Make_Failure (Failed);

      Assert (Int_Results.Succeeded (Ok), "success is successful");
      Assert (Int_Results.Value_Of (Ok) = 42, "success carries the value");
      Assert (not Int_Results.Succeeded (Bad), "failure is not successful");
      Assert
        (Length (Int_Results.Errors_Of (Bad)) = 1, "failure carries the errors");
   end Test_Result_Shape;

end Web_Binding_Tests;
