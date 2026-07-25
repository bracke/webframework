with Ada.Strings.Bounded;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions;
with AUnit.Test_Caller;

with Web.Binding;
with Web.Binding.Paths;
with Web.Binding.Errors;
with Web.Binding.Record_Binders;
with Web.Binding.Streams.Memory;
with Web.Binding.Codecs.JSON;
with Web.Binding.Codecs.JSON.Binding;
with Web.Binding.Decoders.Integer_Decoders;
with Web.Binding.Decoders.Boolean_Decoders;
with Web.Binding.Decoders.Text_Decoders;

package body Web_Binding_JSON_Bind_Tests is

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

   package B16 is new Ada.Strings.Bounded.Generic_Bounded_Length (16);

   --  Target record.
   type Tag_Array is array (1 .. 8) of B16.Bounded_String;
   type Req is record
      Page      : Integer := 0;
      Active    : Boolean := False;
      Tag_Count : Natural := 0;
      Tags      : Tag_Array;
      User_Age  : Integer := 0;
   end record;

   procedure Set_Page (Rec : in out Req; Value : Integer) is
   begin
      Rec.Page := Value;
   end Set_Page;

   procedure Set_Active (Rec : in out Req; Value : Boolean) is
   begin
      Rec.Active := Value;
   end Set_Active;

   procedure Set_User_Age (Rec : in out Req; Value : Integer) is
   begin
      Rec.User_Age := Value;
   end Set_User_Age;

   procedure Append_Tag (Rec : in out Req; Value : B16.Bounded_String) is
   begin
      if Rec.Tag_Count < Rec.Tags'Last then
         Rec.Tag_Count := Rec.Tag_Count + 1;
         Rec.Tags (Rec.Tag_Count) := Value;
      end if;
   end Append_Tag;

   package RB is new Web.Binding.Record_Binders (Req);
   package Int_Dec is new Web.Binding.Decoders.Integer_Decoders (Integer);
   package Bool_Dec renames Web.Binding.Decoders.Boolean_Decoders;
   package Txt is new Web.Binding.Decoders.Text_Decoders (B16);

   function Int_Decode
     (Text : String; P : Field_Path; S : Source_Kind)
      return Int_Dec.Results.Result is (Int_Dec.Decode (Text, P, S));
   function Bool_Decode
     (Text : String; P : Field_Path; S : Source_Kind)
      return Bool_Dec.Results.Result is (Bool_Dec.Decode (Text, P, S));
   function Txt_Decode
     (Text : String; P : Field_Path; S : Source_Kind)
      return Txt.Results.Result is (Txt.Decode (Text, P, S));

   function Read_Int is new JB.Read_Scalar
     (Integer, Int_Dec.Results, Int_Decode);
   function Read_Bool is new JB.Read_Scalar
     (Boolean, Bool_Dec.Results, Bool_Decode);
   function Read_Text is new JB.Read_Scalar
     (B16.Bounded_String, Txt.Results, Txt_Decode);

   procedure Assign_Page is new RB.Assign (Integer, Int_Dec.Results, Set_Page);
   procedure Assign_Active is new RB.Assign
     (Boolean, Bool_Dec.Results, Set_Active);
   procedure Assign_User_Age is new RB.Assign
     (Integer, Int_Dec.Results, Set_User_Age);
   procedure Assign_Tag is new RB.Assign
     (B16.Bounded_String, Txt.Results, Append_Tag);

   Body_Root : constant Field_Path := Rooted (Structured_Body);
   Page_Path : constant Field_Path := Append_Field (Body_Root, "page");
   Active_Path : constant Field_Path := Append_Field (Body_Root, "active");
   Tags_Path : constant Field_Path := Append_Field (Body_Root, "tags");
   User_Path : constant Field_Path := Append_Field (Body_Root, "user");
   User_Age_Path : constant Field_Path := Append_Field (User_Path, "age");

   --  Bind a JSON request object into a Req record via deterministic dispatch.
   function Bind_Request (Data : String) return RB.Results.Result is
      S   : aliased Mem.Memory_Stream := Mem.Create (Data);
      R   : JSON.Reader (S'Access);
      B   : RB.Builder := RB.Start ((others => <>));
      T   : JB.Member_Tracker := JB.New_Tracker;
      Key : Unbounded_String;
      Done, Dup : Boolean;

      procedure Bad_Kind (Path : Field_Path) is
      begin
         RB.Add_Error (B, Make_Error (Json_Unexpected_Kind, Path, Structured_Body));
         JB.Skip_Value (R);
      end Bad_Kind;

   begin
      JSON.Start (R);
      JSON.Advance (R);  --  to the top value
      if not JB.Begin_Object (R) then
         RB.Add_Error
           (B, Make_Error (Json_Unexpected_Kind, Body_Root, Structured_Body));
         return RB.Finish (B);
      end if;

      loop
         JB.Next_Member (R, Key, Done);
         exit when Done;
         declare
            K : constant String := To_String (Key);
         begin
            JB.Note (T, K, Dup);
            if Dup then
               RB.Add_Error
                 (B, Make_Error (Json_Duplicate_Member,
                                 Append_Field (Body_Root, K), Structured_Body));
               JB.Skip_Value (R);
            elsif K = "page" then
               if JB.Current_Shape (R) = JB.Shape_Null then
                  RB.Add_Error
                    (B, Make_Error (Json_Unexpected_Kind, Page_Path,
                                    Structured_Body));
               else
                  Assign_Page (B, Read_Int (R, Page_Path));
               end if;
               JB.Skip_Value (R);
            elsif K = "active" then
               Assign_Active (B, Read_Bool (R, Active_Path));
               JB.Skip_Value (R);
            elsif K = "tags" then
               if JB.Begin_Array (R) then
                  declare
                     E_Done : Boolean;
                     Idx    : Natural := 0;
                  begin
                     loop
                        JB.Next_Element (R, E_Done);
                        exit when E_Done;
                        Assign_Tag
                          (B, Read_Text
                             (R, Append_Index (Tags_Path, Index_Number (Idx))));
                        JB.Skip_Value (R);
                        Idx := Idx + 1;
                     end loop;
                  end;
               else
                  Bad_Kind (Tags_Path);
               end if;
            elsif K = "user" then
               if JB.Begin_Object (R) then
                  declare
                     U_Key  : Unbounded_String;
                     U_Done : Boolean;
                  begin
                     loop
                        JB.Next_Member (R, U_Key, U_Done);
                        exit when U_Done;
                        if To_String (U_Key) = "age" then
                           Assign_User_Age (B, Read_Int (R, User_Age_Path));
                           JB.Skip_Value (R);
                        else
                           JB.Skip_Value (R);
                        end if;
                     end loop;
                  end;
               else
                  Bad_Kind (User_Path);
               end if;
            else
               RB.Add_Error
                 (B, Make_Error (Json_Unknown_Member,
                                 Append_Field (Body_Root, K), Structured_Body));
               JB.Skip_Value (R);
            end if;
         end;
      end loop;

      if not JB.Seen (T, "page") then
         RB.Add_Error
           (B, Make_Error (Json_Missing_Member, Page_Path, Structured_Body));
      end if;
      return RB.Finish (B);
   end Bind_Request;

   function First_Err (R : RB.Results.Result) return Error_Id is
     (Element (RB.Results.Errors_Of (R), 1).Id);

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("json bind object", Test_Bind'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("json member errors", Test_Member_Errors'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("json paths + aggregation",
                               Test_Paths_And_Aggregation'Access));
   end Add_Tests;

   procedure Test_Bind (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Data : constant String :=
        "{" & DQ & "page" & DQ & ":5," & DQ & "active" & DQ & ":true,"
        & DQ & "tags" & DQ & ":[" & DQ & "a" & DQ & "," & DQ & "b" & DQ & "],"
        & DQ & "user" & DQ & ":{" & DQ & "age" & DQ & ":30}}";
      R : constant RB.Results.Result := Bind_Request (Data);
   begin
      Assert (RB.Results.Succeeded (R), "full object binds");
      declare
         V : constant Req := RB.Results.Value_Of (R);
      begin
         Assert (V.Page = 5 and then V.Active, "scalars");
         Assert (V.Tag_Count = 2
                   and then B16.To_String (V.Tags (1)) = "a"
                   and then B16.To_String (V.Tags (2)) = "b", "array");
         Assert (V.User_Age = 30, "nested object");
      end;
   end Test_Bind;

   procedure Test_Member_Errors (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Dupe : constant RB.Results.Result :=
        Bind_Request ("{" & DQ & "page" & DQ & ":1," & DQ & "page" & DQ & ":2}");
      Unk  : constant RB.Results.Result :=
        Bind_Request ("{" & DQ & "page" & DQ & ":1," & DQ & "x" & DQ & ":9}");
      Nul  : constant RB.Results.Result :=
        Bind_Request ("{" & DQ & "page" & DQ & ":null}");
      Mism : constant RB.Results.Result :=
        Bind_Request ("{" & DQ & "page" & DQ & ":[1]}");
      Miss : constant RB.Results.Result :=
        Bind_Request ("{" & DQ & "active" & DQ & ":true}");
   begin
      Assert (First_Err (Dupe) = Json_Duplicate_Member, "duplicate member");
      Assert (First_Err (Unk) = Json_Unknown_Member, "unknown member");
      Assert (First_Err (Nul) = Json_Unexpected_Kind, "null rejected");
      Assert (First_Err (Mism) = Json_Unexpected_Kind, "type mismatch");
      Assert (First_Err (Miss) = Json_Missing_Member, "missing required");
   end Test_Member_Errors;

   procedure Test_Paths_And_Aggregation (Item : in out Fixture) is
      pragma Unreferenced (Item);
      --  Two bad scalars plus a bad array element: three aggregated errors.
      Agg : constant RB.Results.Result :=
        Bind_Request
          ("{" & DQ & "page" & DQ & ":" & DQ & "x" & DQ & ","
           & DQ & "active" & DQ & ":" & DQ & "y" & DQ & ","
           & DQ & "tags" & DQ & ":[" & DQ & "ok" & DQ & ",[1]]}");
   begin
      Assert (not RB.Results.Succeeded (Agg), "aggregated failure");
      Assert (Length (RB.Results.Errors_Of (Agg)) = 3, "three aggregated errors");
      --  Errors in member/element order with exact paths.
      Assert (Render (Element (RB.Results.Errors_Of (Agg), 1).Path) = "body.page",
              "body.page");
      Assert (Render (Element (RB.Results.Errors_Of (Agg), 2).Path) = "body.active",
              "body.active");
      Assert (Render (Element (RB.Results.Errors_Of (Agg), 3).Path)
                = "body.tags[1]", "body.tags[1]");
   end Test_Paths_And_Aggregation;

end Web_Binding_JSON_Bind_Tests;
