with AUnit.Assertions;
with AUnit.Test_Caller;

with Web.Binding.Media_Types;
with Web.Binding.Codecs.Registry;

package body Web_Binding_Media_Tests is

   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;

   package MT renames Web.Binding.Media_Types;
   package Reg renames Web.Binding.Codecs.Registry;
   use type Reg.Freeze_Status;

   function Main_Of (M : MT.Media_Type) return String is
     (MT.Tokens.To_String (M.Main));
   function Sub_Of (M : MT.Media_Type) return String is
     (MT.Tokens.To_String (M.Sub));
   function Charset_Of (M : MT.Media_Type) return String is
     (MT.Tokens.To_String (M.Charset));
   function Boundary_Of (M : MT.Media_Type) return String is
     (MT.Boundaries.To_String (M.Boundary));

   --  Build a small registry for the selection tests.
   function Sample_Registry return Reg.Registry is
      B : Reg.Builder;
      R : Reg.Registry;
      Status : Reg.Freeze_Status;
   begin
      Reg.Reset (B);
      Reg.Register_Exact (B, "json", "application", "json");
      Reg.Register_Exact (B, "vnd", "application", "vnd.api+json");
      Reg.Register_Exact (B, "form", "application", "x-www-form-urlencoded");
      Reg.Register_Suffix (B, "suffix-json", "json");
      Reg.Register_Wildcard (B, "app-star", "application");
      Reg.Register_Wildcard (B, "star-star", "*");
      Reg.Set_Missing (B, Reg.Use_Default, "json");
      Reg.Freeze (B, R, Status);
      return R;
   end Sample_Registry;

   function Picked (R : Reg.Registry; Content_Type : String) return String is
      Sel : constant Reg.Selection :=
        Reg.Select_Codec (R, MT.Parse (Content_Type));
   begin
      return (if Sel.Matched then Reg.Ids.To_String (Sel.Id) else "");
   end Picked;

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("media parse", Test_Parse'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("media selection", Test_Selection'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("media freeze", Test_Freeze'Access));
   end Add_Tests;

   procedure Test_Parse (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Json  : constant MT.Media_Type := MT.Parse ("application/json");
      Chars : constant MT.Media_Type :=
        MT.Parse ("APPLICATION/JSON; charset=UTF-8");
      Vnd   : constant MT.Media_Type := MT.Parse ("application/vnd.api+json");
      Multi : constant MT.Media_Type :=
        MT.Parse ("multipart/form-data; boundary=" & '"' & "a b" & '"');
   begin
      Assert (MT.Is_Valid (Json) and then Main_Of (Json) = "application"
                and then Sub_Of (Json) = "json", "application/json");
      --  Case-insensitive; charset lowercased.
      Assert (Main_Of (Chars) = "application" and then Charset_Of (Chars) = "utf-8",
              "case and charset");
      Assert (MT.Has_Suffix (Vnd)
                and then MT.Tokens.To_String (Vnd.Suffix) = "json",
              "structured suffix");
      Assert (Boundary_Of (Multi) = "a b", "quoted boundary");
      Assert (MT.Normalized (Json) = "application/json", "normalized");
      --  Invalid syntax.
      Assert (not MT.Is_Valid (MT.Parse ("notamediatype")), "no slash");
      Assert (not MT.Is_Valid (MT.Parse ("application/")), "empty subtype");
      Assert (not MT.Is_Valid (MT.Parse ("")), "empty");
   end Test_Parse;

   procedure Test_Selection (Item : in out Fixture) is
      pragma Unreferenced (Item);
      R : constant Reg.Registry := Sample_Registry;
   begin
      --  Exact match.
      Assert (Picked (R, "application/json") = "json", "exact");
      --  Exact beats suffix (vnd.api+json is registered exactly).
      Assert (Picked (R, "application/vnd.api+json") = "vnd", "exact beats suffix");
      --  Suffix match when no exact (some/thing+json).
      Assert (Picked (R, "application/vnd.other+json") = "suffix-json", "suffix");
      --  Wildcard by type when neither exact nor suffix.
      Assert (Picked (R, "application/xml") = "app-star", "type wildcard");
      --  */* wildcard as the last resort.
      Assert (Picked (R, "text/plain") = "star-star", "star wildcard");
      --  Missing Content-Type uses the declared default.
      declare
         Sel : constant Reg.Selection := Reg.Missing_Selection (R);
      begin
         Assert (Sel.Matched and then Reg.Ids.To_String (Sel.Id) = "json",
                 "missing uses default");
      end;
   end Test_Selection;

   procedure Test_Freeze (Item : in out Fixture) is
      pragma Unreferenced (Item);
      B : Reg.Builder;
      R : Reg.Registry;
      Status : Reg.Freeze_Status;
   begin
      --  Two exact codecs for the same media type: ambiguous.
      Reg.Reset (B);
      Reg.Register_Exact (B, "a", "application", "json");
      Reg.Register_Exact (B, "b", "application", "json");
      Reg.Freeze (B, R, Status);
      Assert (Status = Reg.Ambiguous_Patterns, "ambiguous exact patterns");

      --  A wildcard with an illegal type.
      Reg.Reset (B);
      Reg.Register_Wildcard (B, "bad", "app lication");
      Reg.Freeze (B, R, Status);
      Assert (Status = Reg.Invalid_Wildcard, "invalid wildcard");

      --  A clean set freezes.
      Reg.Reset (B);
      Reg.Register_Exact (B, "json", "application", "json");
      Reg.Register_Wildcard (B, "star", "*");
      Reg.Freeze (B, R, Status);
      Assert (Status = Reg.Frozen_Ok, "clean set freezes");
   end Test_Freeze;

end Web_Binding_Media_Tests;
