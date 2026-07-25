with AUnit.Assertions;
with AUnit.Test_Caller;

with Web.Binding;
with Web.Binding.Paths;
with Web.Binding.Policies;
with Web.Binding.Errors;
with Web.Binding.Sources;
with Web.Binding.Query;
with Web.Binding.Record_Binders;
with Web.Binding.Decoders.Integer_Decoders;

package body Web_Binding_Collection_Tests is

   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;

   use Web.Binding;
   use Web.Binding.Paths;
   use Web.Binding.Policies;
   use Web.Binding.Errors;
   use Web.Binding.Sources;

   package Int_Dec is new Web.Binding.Decoders.Integer_Decoders (Integer);
   function Int_Decode
     (Text : String; P : Field_Path; S : Source_Kind)
      return Int_Dec.Results.Result is (Int_Dec.Decode (Text, P, S));

   --  Collection target: a small bounded list of integers.
   type Int_Array is array (1 .. 8) of Integer;
   type Coll is record
      Len   : Natural := 0;
      Items : Int_Array := [others => 0];
   end record;

   procedure Append_Int (Rec : in out Coll; Value : Integer) is
   begin
      if Rec.Len < Rec.Items'Last then
         Rec.Len := Rec.Len + 1;
         Rec.Items (Rec.Len) := Value;
      end if;
   end Append_Int;

   package RB_Coll is new Web.Binding.Record_Binders (Coll);
   procedure Bind_Ints is new RB_Coll.Bind_Collection
     (Integer, Int_Dec.Results, Int_Decode, Append_Int);

   N_Path : constant Field_Path := Append_Field (Rooted (Query_Parameter), "n");

   function Bind_Coll
     (Occ : Occurrences; Min, Max : Natural) return RB_Coll.Results.Result
   is
      B : RB_Coll.Builder := RB_Coll.Start ((Len => 0, Items => [others => 0]));
   begin
      Bind_Ints (B, Occ, N_Path, Query_Parameter, Min, Max);
      return RB_Coll.Finish (B);
   end Bind_Coll;

   --  Nested target: Parent has a nested User.
   type User is record
      Age   : Integer := 0;
      Score : Integer := 0;
   end record;

   procedure Set_Age (Rec : in out User; Value : Integer) is
   begin
      Rec.Age := Value;
   end Set_Age;

   procedure Set_Score (Rec : in out User; Value : Integer) is
   begin
      Rec.Score := Value;
   end Set_Score;

   package RB_User is new Web.Binding.Record_Binders (User);
   procedure Bind_Age is new RB_User.Bind_Scalar
     (Integer, Int_Dec.Results, Int_Decode, Set_Age);
   procedure Bind_Score is new RB_User.Bind_Scalar
     (Integer, Int_Dec.Results, Int_Decode, Set_Score);

   Nested_Query : Web.Binding.Query.Query_Source;

   User_Age_Path : constant Field_Path :=
     Append_Field (Append_Field (Rooted (Query_Parameter), "user"), "age");
   User_Score_Path : constant Field_Path :=
     Append_Field (Append_Field (Rooted (Query_Parameter), "user"), "score");
   User_Path : constant Field_Path :=
     Append_Field (Rooted (Query_Parameter), "user");

   --  Sub-bind: assemble a User from the flat "user.*" query keys.
   function Bind_User return RB_User.Results.Result is
      B : RB_User.Builder := RB_User.Start ((Age => 0, Score => 0));
   begin
      Bind_Age
        (B, Web.Binding.Query.Lookup (Nested_Query, "user.age"),
         User_Age_Path, Query_Parameter, Required);
      Bind_Score
        (B, Web.Binding.Query.Lookup (Nested_Query, "user.score"),
         User_Score_Path, Query_Parameter, Required);
      return RB_User.Finish (B);
   end Bind_User;

   function User_Present return Boolean is
     (Count (Web.Binding.Query.Lookup (Nested_Query, "user.age")) > 0
        or else Count (Web.Binding.Query.Lookup (Nested_Query, "user.score")) > 0);

   type Parent is record
      Tag      : Integer := 0;
      The_User : User;
   end record;

   procedure Set_User (Rec : in out Parent; Value : User) is
   begin
      Rec.The_User := Value;
   end Set_User;

   package RB_Parent is new Web.Binding.Record_Binders (Parent);
   procedure Bind_The_User is new RB_Parent.Bind_Nested
     (User, RB_User.Results, Bind_User, Set_User);

   function Bind_Parent (Optional : Boolean) return RB_Parent.Results.Result is
      B : RB_Parent.Builder := RB_Parent.Start ((Tag => 0, The_User => (0, 0)));
   begin
      Bind_The_User
        (B, User_Present, User_Path, Query_Parameter, Optional => Optional);
      return RB_Parent.Finish (B);
   end Bind_Parent;

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("collection bind", Test_Collection'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("collection delimited", Test_Delimited'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("collection nested", Test_Nested'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("collection depth", Test_Depth'Access));
   end Add_Tests;

   procedure Test_Collection (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Ok      : constant RB_Coll.Results.Result :=
        Bind_Coll (Web.Binding.Query.Lookup
                     (Web.Binding.Query.Parse ("n=1&n=2&n=3"), "n"), 0, 8);
      Bad_Elt : constant RB_Coll.Results.Result :=
        Bind_Coll (Web.Binding.Query.Lookup
                     (Web.Binding.Query.Parse ("n=1&n=x&n=3"), "n"), 0, 8);
      Too_Many : constant RB_Coll.Results.Result :=
        Bind_Coll (Web.Binding.Query.Lookup
                     (Web.Binding.Query.Parse ("n=1&n=2&n=3"), "n"), 0, 2);
      Too_Few  : constant RB_Coll.Results.Result :=
        Bind_Coll (Web.Binding.Query.Lookup
                     (Web.Binding.Query.Parse ("n=1"), "n"), 5, 8);
   begin
      Assert (RB_Coll.Results.Succeeded (Ok)
                and then RB_Coll.Results.Value_Of (Ok).Len = 3
                and then RB_Coll.Results.Value_Of (Ok).Items (2) = 2,
              "ordered collection");
      --  Element error at an exact indexed (0-based) path; others still bind.
      Assert (not RB_Coll.Results.Succeeded (Bad_Elt), "bad element fails");
      Assert (Element (RB_Coll.Results.Errors_Of (Bad_Elt), 1).Id
                = Decode_Invalid_Integer, "element decode error");
      Assert (Render (Element (RB_Coll.Results.Errors_Of (Bad_Elt), 1).Path)
                = "query.n[1]", "exact indexed path");
      Assert (Element (RB_Coll.Results.Errors_Of (Too_Many), 1).Id
                = Decode_Too_Many_Items, "too many items");
      Assert (Element (RB_Coll.Results.Errors_Of (Too_Few), 1).Id
                = Decode_Invalid_List, "too few items");
   end Test_Collection;

   procedure Test_Delimited (Item : in out Fixture) is
      pragma Unreferenced (Item);
      R : constant RB_Coll.Results.Result :=
        Bind_Coll (Split ("10,20,30", ','), 0, 8);
   begin
      Assert (RB_Coll.Results.Succeeded (R)
                and then RB_Coll.Results.Value_Of (R).Len = 3
                and then RB_Coll.Results.Value_Of (R).Items (3) = 30,
              "delimited scalar collection");
   end Test_Delimited;

   procedure Test_Nested (Item : in out Fixture) is
      pragma Unreferenced (Item);
   begin
      --  Present and valid: composed into the parent.
      Nested_Query := Web.Binding.Query.Parse ("user.age=30&user.score=99");
      declare
         R : constant RB_Parent.Results.Result := Bind_Parent (Optional => False);
      begin
         Assert (RB_Parent.Results.Succeeded (R)
                   and then RB_Parent.Results.Value_Of (R).The_User.Age = 30
                   and then RB_Parent.Results.Value_Of (R).The_User.Score = 99,
                 "nested composed");
      end;

      --  Present but malformed: nested error aggregates with its nested path.
      Nested_Query := Web.Binding.Query.Parse ("user.age=abc&user.score=99");
      declare
         R : constant RB_Parent.Results.Result := Bind_Parent (Optional => False);
      begin
         Assert (not RB_Parent.Results.Succeeded (R), "nested error fails parent");
         Assert (Element (RB_Parent.Results.Errors_Of (R), 1).Id
                   = Decode_Invalid_Integer, "nested decode error");
         Assert (Render (Element (RB_Parent.Results.Errors_Of (R), 1).Path)
                   = "query.user.age", "exact nested path");
      end;

      --  Absent + optional: None (parent keeps the default user).
      Nested_Query := Web.Binding.Query.Parse ("");
      declare
         R : constant RB_Parent.Results.Result := Bind_Parent (Optional => True);
      begin
         Assert (RB_Parent.Results.Succeeded (R)
                   and then RB_Parent.Results.Value_Of (R).The_User.Age = 0,
                 "absent optional nested is None");
      end;

      --  Absent + required: the whole object is missing.
      Nested_Query := Web.Binding.Query.Parse ("");
      declare
         R : constant RB_Parent.Results.Result := Bind_Parent (Optional => False);
      begin
         Assert (not RB_Parent.Results.Succeeded (R), "absent required nested fails");
         Assert (Element (RB_Parent.Results.Errors_Of (R), 1).Id = Binding_Missing,
                 "required nested missing");
      end;
   end Test_Nested;

   procedure Test_Depth (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Deep : constant Field_Path :=
        Append_Field (Append_Field (Rooted (Query_Parameter), "a"), "b");
      Shallow_Ok : RB_Coll.Builder :=
        RB_Coll.Start ((Len => 0, Items => [others => 0]));
      Too_Deep   : RB_Coll.Builder :=
        RB_Coll.Start ((Len => 0, Items => [others => 0]));
   begin
      --  Depth of "query.a.b" is 3.
      RB_Coll.Guard_Depth (Shallow_Ok, Deep, Query_Parameter, Max_Depth => 5);
      RB_Coll.Guard_Depth (Too_Deep, Deep, Query_Parameter, Max_Depth => 2);
      Assert (not RB_Coll.Has_Errors (Shallow_Ok), "within depth limit");
      Assert (RB_Coll.Has_Errors (Too_Deep), "exceeds depth limit");
   end Test_Depth;

end Web_Binding_Collection_Tests;
