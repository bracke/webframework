with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions;
with AUnit.Test_Caller;

with Web.Binding;
with Web.Binding.Paths;
with Web.Binding.Errors;
with Web.Binding.Results;
with Web.Binding.Union_Binders;
with Web.Binding.Streams.Memory;
with Web.Binding.Codecs.JSON;
with Web.Binding.Codecs.JSON.Binding;
with Web.Binding.Decoders.Integer_Decoders;

package body Web_Binding_Union_Tests is

   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;
   use Web.Binding;
   use Web.Binding.Paths;
   use Web.Binding.Errors;

   package JSON renames Web.Binding.Codecs.JSON;
   package JB renames Web.Binding.Codecs.JSON.Binding;
   package Mem renames Web.Binding.Streams.Memory;
   use type JB.Value_Shape;

   DQ : constant Character := '"';

   --  The discriminated union target.
   type Method is (Card, Cash);
   type Payment (Kind : Method := Cash) is record
      case Kind is
         when Card =>
            Number : Integer := 0;
         when Cash =>
            Amount : Integer := 0;
      end case;
   end record;

   package Pay_Results is new Web.Binding.Results (Payment);
   package UB is new Web.Binding.Union_Binders (Method);
   package Int_Dec is new Web.Binding.Decoders.Integer_Decoders (Integer);

   function Int_Decode
     (Text : String; P : Field_Path; S : Source_Kind)
      return Int_Dec.Results.Result is (Int_Dec.Decode (Text, P, S));
   function Read_Int is new JB.Read_Scalar
     (Integer, Int_Dec.Results, Int_Decode);

   Sel : constant UB.Selector :=
     UB.Map (UB.Map (UB.Empty_Selector, "card", Card), "cash", Cash);

   Body_Root : constant Field_Path := Rooted (Structured_Body);
   Type_Path   : constant Field_Path := Append_Field (Body_Root, "type");
   Number_Path : constant Field_Path := Append_Field (Body_Root, "number");
   Amount_Path : constant Field_Path := Append_Field (Body_Root, "amount");

   procedure Merge (Errs : in out Error_Collection; From : Error_Collection) is
   begin
      for I in 1 .. Natural (Length (From)) loop
         Append (Errs, Element (From, I));
      end loop;
   end Merge;

   --  Bind a Payment: collect the discriminator and candidate fields, then
   --  construct the discriminated value once with the resolved discriminant.
   function Bind_Payment (Data : String) return Pay_Results.Result is
      S    : aliased Mem.Memory_Stream := Mem.Create (Data);
      R    : JSON.Reader (S'Access);
      Errs : Error_Collection := Empty_Collection;
      Key  : Unbounded_String;
      Done : Boolean;
      Type_Seen : Boolean := False;
      Type_Val  : Unbounded_String;
      Num_Seen  : Boolean := False;
      Num_Val   : Integer := 0;
      Amt_Seen  : Boolean := False;
      Amt_Val   : Integer := 0;

      procedure Read_Field
        (Path : Field_Path; Seen : out Boolean; Val : out Integer)
      is
         Rr : constant Int_Dec.Results.Result := Read_Int (R, Path);
      begin
         if Int_Dec.Results.Succeeded (Rr) then
            Val := Int_Dec.Results.Value_Of (Rr);
            Seen := True;
         else
            Val := 0;
            Seen := False;
            Merge (Errs, Int_Dec.Results.Errors_Of (Rr));
         end if;
      end Read_Field;

   begin
      JSON.Start (R);
      JSON.Advance (R);
      if not JB.Begin_Object (R) then
         Append (Errs, Make_Error (Json_Unexpected_Kind, Body_Root, Structured_Body));
         return Pay_Results.Make_Failure (Errs);
      end if;

      loop
         JB.Next_Member (R, Key, Done);
         exit when Done;
         declare
            K : constant String := To_String (Key);
         begin
            if K = "type" then
               if JB.Current_Shape (R) = JB.Shape_String then
                  Type_Val := To_Unbounded_String (JSON.Text (R));
                  Type_Seen := True;
               else
                  Append (Errs, Make_Error (Json_Unexpected_Kind, Type_Path,
                                            Structured_Body));
               end if;
            elsif K = "number" then
               Read_Field (Number_Path, Num_Seen, Num_Val);
            elsif K = "amount" then
               Read_Field (Amount_Path, Amt_Seen, Amt_Val);
            else
               Append (Errs, Make_Error (Json_Unknown_Member,
                                         Append_Field (Body_Root, K),
                                         Structured_Body));
            end if;
            JB.Skip_Value (R);
         end;
      end loop;

      if not Type_Seen then
         Append (Errs, Make_Error (UB.Missing_Error, Type_Path, Structured_Body));
         return Pay_Results.Make_Failure (Errs);
      end if;

      declare
         Sn : constant UB.Selection := UB.Resolve (Sel, To_String (Type_Val));
      begin
         if not Sn.Found then
            Append (Errs,
                    Make_Error (UB.Invalid_Error, Type_Path, Structured_Body));
            return Pay_Results.Make_Failure (Errs);
         end if;

         case Sn.Alt is
            when Card =>
               if Amt_Seen then
                  Append (Errs, Make_Error (Json_Unknown_Member, Amount_Path,
                                            Structured_Body));
               end if;
               if not Num_Seen then
                  Append (Errs, Make_Error (Json_Missing_Member, Number_Path,
                                            Structured_Body));
               end if;
               if Is_Empty (Errs) then
                  return Pay_Results.Make_Success
                    ((Kind => Card, Number => Num_Val));
               end if;
            when Cash =>
               if Num_Seen then
                  Append (Errs, Make_Error (Json_Unknown_Member, Number_Path,
                                            Structured_Body));
               end if;
               if not Amt_Seen then
                  Append (Errs, Make_Error (Json_Missing_Member, Amount_Path,
                                            Structured_Body));
               end if;
               if Is_Empty (Errs) then
                  return Pay_Results.Make_Success
                    ((Kind => Cash, Amount => Amt_Val));
               end if;
         end case;
         return Pay_Results.Make_Failure (Errs);
      end;
   end Bind_Payment;

   function First_Err (R : Pay_Results.Result) return Error_Id is
     (Element (Pay_Results.Errors_Of (R), 1).Id);

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("union tagged", Test_Tagged'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("union discriminator errors",
                               Test_Discriminator_Errors'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("union structural", Test_Structural'Access));
   end Add_Tests;

   procedure Test_Tagged (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Card_R : constant Pay_Results.Result :=
        Bind_Payment ("{" & DQ & "type" & DQ & ":" & DQ & "card" & DQ & ","
                      & DQ & "number" & DQ & ":4111}");
      Cash_R : constant Pay_Results.Result :=
        Bind_Payment ("{" & DQ & "type" & DQ & ":" & DQ & "cash" & DQ & ","
                      & DQ & "amount" & DQ & ":100}");
   begin
      Assert (Pay_Results.Succeeded (Card_R), "card binds");
      Assert (Pay_Results.Value_Of (Card_R).Kind = Card
                and then Pay_Results.Value_Of (Card_R).Number = 4111,
              "card constructed");
      Assert (Pay_Results.Succeeded (Cash_R)
                and then Pay_Results.Value_Of (Cash_R).Kind = Cash
                and then Pay_Results.Value_Of (Cash_R).Amount = 100,
              "cash constructed");
   end Test_Tagged;

   procedure Test_Discriminator_Errors (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Missing : constant Pay_Results.Result :=
        Bind_Payment ("{" & DQ & "number" & DQ & ":4111}");
      Invalid : constant Pay_Results.Result :=
        Bind_Payment ("{" & DQ & "type" & DQ & ":" & DQ & "crypto" & DQ & "}");
      Wrong   : constant Pay_Results.Result :=
        Bind_Payment ("{" & DQ & "type" & DQ & ":" & DQ & "card" & DQ & ","
                      & DQ & "amount" & DQ & ":9}");
   begin
      Assert (First_Err (Missing) = Union_Missing_Discriminator,
              "missing discriminator");
      Assert (First_Err (Invalid) = Union_Invalid_Discriminator,
              "invalid discriminator");
      --  A field belonging to the other alternative is rejected.
      Assert (First_Err (Wrong) = Json_Unknown_Member, "wrong-alternative field");
      Assert (Render (Element (Pay_Results.Errors_Of (Wrong), 1).Path)
                = "body.amount", "at body.amount");
   end Test_Discriminator_Errors;

   procedure Test_Structural (Item : in out Fixture) is
      pragma Unreferenced (Item);
      One  : constant UB.Match_Array := [Card => True, Cash => False];
      Two  : constant UB.Match_Array := [Card => True, Cash => True];
      None : constant UB.Match_Array := [others => False];
      Chosen : Method;
      use type UB.Structural_Outcome;
   begin
      Assert (UB.Resolve_Structural (One, Chosen) = UB.Exactly_One, "exactly one");
      Assert (Chosen = Card, "chosen is card");
      Assert (UB.Resolve_Structural (Two, Chosen) = UB.Ambiguous, "ambiguous");
      Assert (Chosen'Valid, "ambiguous leaves a valid chosen");
      Assert (UB.Resolve_Structural (None, Chosen) = UB.No_Match, "no match");
      Assert (Chosen'Valid, "no-match leaves a valid chosen");
      Assert (UB.Ambiguous_Error = Union_Ambiguous_Alternative, "ambiguous id");
      Assert (UB.No_Match_Error = Union_No_Matching_Alternative, "no-match id");
   end Test_Structural;

end Web_Binding_Union_Tests;
