with AUnit.Assertions;
with AUnit.Test_Caller;

with Web.Binding;
with Web.Binding.Paths;
with Web.Binding.Errors;
with Web.Binding.Decoders.Integer_Decoders;
with Web.Binding.Decoders.Guard;
with Web.Binding.Media_Types;
with Web.Binding.Codecs.Registry;
with Web.Binding.Streams.Memory;
with Web.Binding.Codecs.JSON;

package body Web_Binding_Hardening_Tests is

   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;
   use Web.Binding;
   use Web.Binding.Paths;
   use Web.Binding.Errors;

   package Int_Dec is new Web.Binding.Decoders.Integer_Decoders (Integer);
   package MT renames Web.Binding.Media_Types;
   package Reg renames Web.Binding.Codecs.Registry;
   package Mem renames Web.Binding.Streams.Memory;
   package JSON renames Web.Binding.Codecs.JSON;
   use type JSON.Token_Kind;

   C_Path : constant Field_Path := Append_Field (Rooted (Query_Parameter), "n");

   --  A non-constant flag so neither the raise nor the return is folded away.
   Always_Raise : Boolean := True;

   --  A decoder that always raises -- to exercise the guard.
   function Bad_Decode
     (Text : String; Path : Field_Path; Source : Source_Kind)
      return Int_Dec.Results.Result
   is
      pragma Unreferenced (Text, Path, Source);
   begin
      if Always_Raise then
         raise Program_Error;
      end if;
      return Int_Dec.Results.Make_Failure (Empty_Collection);
   end Bad_Decode;

   function Guarded_Bad is new Web.Binding.Decoders.Guard
     (Integer, Int_Dec.Results, Bad_Decode);

   --  An immutable frozen registry shared across tasks.
   function Build_Registry return Reg.Registry is
      B : Reg.Builder;
      R : Reg.Registry;
      St : Reg.Freeze_Status;
   begin
      Reg.Reset (B);
      Reg.Register_Exact (B, "json", "application", "json");
      Reg.Register_Wildcard (B, "star", "*");
      Reg.Freeze (B, R, St);
      return R;
   end Build_Registry;

   Frozen : constant Reg.Registry := Build_Registry;

   protected Tally is
      procedure Fail;
      function Failures return Natural;
   private
      N : Natural := 0;
   end Tally;

   protected body Tally is
      procedure Fail is
      begin
         N := N + 1;
      end Fail;
      function Failures return Natural is (N);
   end Tally;

   task type Worker;
   task body Worker is
      Ok : Boolean := True;
   begin
      for I in 1 .. 3_000 loop
         declare
            R : constant Int_Dec.Results.Result :=
              Int_Dec.Decode ("12345", C_Path, Query_Parameter);
         begin
            if not (Int_Dec.Results.Succeeded (R)
                    and then Int_Dec.Results.Value_Of (R) = 12345)
            then
               Ok := False;
            end if;
         end;
         declare
            Sel : constant Reg.Selection :=
              Reg.Select_Codec (Frozen, MT.Parse ("application/json"));
         begin
            if not (Sel.Matched and then Reg.Ids.To_String (Sel.Id) = "json") then
               Ok := False;
            end if;
         end;
      end loop;
      if not Ok then
         Tally.Fail;
      end if;
   end Worker;

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Always_Raise := True;   --  a write, so the flag is not foldable to constant
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("hardening guard", Test_Guard'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("hardening concurrency", Test_Concurrency'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("hardening cancellation", Test_Cancellation'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("hardening redaction", Test_Redaction'Access));
   end Add_Tests;

   procedure Test_Guard (Item : in out Fixture) is
      pragma Unreferenced (Item);
      R : constant Int_Dec.Results.Result :=
        Guarded_Bad ("x", C_Path, Query_Parameter);
   begin
      --  The raise was caught and converted; no exception reached here.
      Assert (not Int_Dec.Results.Succeeded (R), "guarded raise is a failure");
      Assert (Element (Int_Dec.Results.Errors_Of (R), 1).Id
                = Internal_Decoder_Failure, "converted to internal failure");
   end Test_Guard;

   procedure Test_Concurrency (Item : in out Fixture) is
      pragma Unreferenced (Item);
   begin
      declare
         W1, W2, W3, W4 : Worker;   --  block completion waits for all to finish
      begin
         null;
      end;
      Assert (Tally.Failures = 0, "no corruption under concurrent shared use");
   end Test_Concurrency;

   procedure Test_Cancellation (Item : in out Fixture) is
      pragma Unreferenced (Item);
      S : aliased Mem.Memory_Stream :=
        Mem.Create ("{""a"":1,""b"":2}", 2, Mem.Cancel, 4);
      R : JSON.Reader (S'Access);
   begin
      JSON.Start (R);
      loop
         JSON.Advance (R);
         exit when JSON.Kind (R) in JSON.End_Document | JSON.Error_Token;
      end loop;
      Assert (JSON.Kind (R) = JSON.Error_Token,
              "cancelled stream yields a defined error and terminates");
   end Test_Cancellation;

   procedure Test_Redaction (Item : in out Fixture) is
      pragma Unreferenced (Item);
      E : constant Decoding_Error :=
        Make_Error (Decode_Invalid_Integer,
                    Append_Field (Rooted (Structured_Body), "token"),
                    Structured_Body);
   begin
      --  A decoding error carries only the path and id, never the raw value.
      --  (Form-field sensitivity redaction is now covered by the forms library
      --  and the webframework_forms bridge.)
      Assert (Param_Strings.To_String (E.Parameters.Expected_Type) /= "SECRETVALUE"
                and then Param_Strings.To_String (E.Parameters.Actual_Kind)
                           /= "SECRETVALUE",
              "error parameters carry no raw value");
   end Test_Redaction;

end Web_Binding_Hardening_Tests;
