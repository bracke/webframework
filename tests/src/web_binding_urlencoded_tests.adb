with Ada.Strings.Bounded;
with AUnit.Assertions;
with AUnit.Test_Caller;

with Web.Binding;
with Web.Binding.Paths;
with Web.Binding.Errors;
with Web.Binding.Sources;
with Web.Binding.Streams;
with Web.Binding.Streams.Memory;
with Web.Binding.Bodies;
with Web.Binding.Codecs.URL_Encoded;
with Web.Binding.Decoders.Text_Decoders;

package body Web_Binding_URLEncoded_Tests is

   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;

   use Web.Binding;
   use Web.Binding.Paths;
   use Web.Binding.Errors;
   use Web.Binding.Sources;

   package URL renames Web.Binding.Codecs.URL_Encoded;
   package Mem renames Web.Binding.Streams.Memory;
   use type URL.Parse_Outcome;

   Path : constant Field_Path := Append_Field (Rooted (URL_Encoded_Field), "a");

   --  Parse Data delivered in chunks of the given size.
   function Parse_At
     (Data     : String;
      Chunk    : Positive := Positive'Last;
      Settings : URL.Config := URL.Default_Config;
      Limit    : Byte_Count := Byte_Count'Last) return URL.Form_Source
   is
      S : Mem.Memory_Stream := Mem.Create (Data, Chunk);
      R : URL.Form_Source;
      O : URL.Parse_Outcome;
   begin
      Web.Binding.Streams.Set_Limit (S, Limit);
      URL.Parse (S, R, O, Settings);
      return R;
   end Parse_At;

   --  Parse and return only the outcome.
   function Outcome_Of
     (Data     : String;
      Chunk    : Positive := Positive'Last;
      Settings : URL.Config := URL.Default_Config;
      Limit    : Byte_Count := Byte_Count'Last;
      Inject   : Mem.Fault_Kind := Mem.No_Fault;
      After    : Natural := 0) return URL.Parse_Outcome
   is
      S : Mem.Memory_Stream := Mem.Create (Data, Chunk, Inject, After);
      R : URL.Form_Source;
      O : URL.Parse_Outcome;
   begin
      Web.Binding.Streams.Set_Limit (S, Limit);
      URL.Parse (S, R, O, Settings);
      return O;
   end Outcome_Of;

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("urlencoded basic", Test_Basic'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("urlencoded fragmentation", Test_Fragmentation'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("urlencoded errors", Test_Errors'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("urlencoded limits", Test_Limits'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("urlencoded faults", Test_Faults'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("urlencoded ownership", Test_Ownership'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("urlencoded fuzz", Test_Fuzz'Access));
   end Add_Tests;

   procedure Test_Basic (Item : in out Fixture) is
      pragma Unreferenced (Item);
      R : constant URL.Form_Source := Parse_At ("a=1&b=2&a=3&c=x%20y&d=e+f");
      A : constant Occurrences := URL.Lookup (R, "a");
      C : constant Occurrences := URL.Lookup (R, "c");
      D : constant Occurrences := URL.Lookup (R, "d");
   begin
      Assert (Count (A) = 2 and then Value (A, 1) = "1" and then Value (A, 2) = "3",
              "duplicate fields in order");
      Assert (Value (C, 1) = "x y", "percent decode");
      Assert (Value (D, 1) = "e f", "plus to space");
   end Test_Basic;

   procedure Test_Fragmentation (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Data   : constant String := "a=1&b=2&a=3&c=x%20y&d=e+f";
      Chunks : constant array (1 .. 6) of Positive := [1, 2, 3, 5, 8, 1000];
   begin
      for K of Chunks loop
         declare
            R : constant URL.Form_Source := Parse_At (Data, K);
            A : constant Occurrences := URL.Lookup (R, "a");
            C : constant Occurrences := URL.Lookup (R, "c");
         begin
            Assert (Count (A) = 2 and then Value (A, 1) = "1"
                      and then Value (A, 2) = "3"
                      and then Value (C, 1) = "x y",
                    "fragmentation-invariant at chunk" & K'Image);
         end;
      end loop;
   end Test_Fragmentation;

   procedure Test_Errors (Item : in out Fixture) is
      pragma Unreferenced (Item);
      package B64 is new Ada.Strings.Bounded.Generic_Bounded_Length (64);
      package Txt is new Web.Binding.Decoders.Text_Decoders (B64);

      Bad_Esc   : constant URL.Form_Source := Parse_At ("a=%zz");
      Bad_UTF8  : constant URL.Form_Source := Parse_At ("a=%ff");
      M_Occ : constant Occurrences := URL.Lookup (Bad_Esc, "a");
      U_Occ : constant Occurrences := URL.Lookup (Bad_UTF8, "a");
      D : constant Txt.Result :=
        Txt.Decode (Value (U_Occ, 1), Path, URL_Encoded_Field);
   begin
      --  A malformed escape marks the value (percent error on resolution).
      Assert (Malformed (M_Occ, 1), "malformed escape flagged");
      --  A valid escape can still yield invalid UTF-8, caught by the decoder.
      Assert (not Malformed (U_Occ, 1), "valid escape not flagged");
      Assert (Element (Txt.Results.Errors_Of (D), 1).Id = Decode_Invalid_UTF8,
              "invalid utf8 detected at decode");
   end Test_Errors;

   procedure Test_Limits (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Few  : URL.Config := URL.Default_Config;
      Tiny : URL.Config := URL.Default_Config;
   begin
      Few.Max_Fields := 2;
      Assert (Outcome_Of ("a=1&b=2&c=3", Settings => Few) = URL.Too_Many_Fields,
              "too many fields");
      Tiny.Max_Value := 2;
      Assert (Outcome_Of ("a=xxxxx", Settings => Tiny) = URL.Field_Too_Large,
              "field too large");
      Assert (Outcome_Of ("a=1&b=2&c=3", Limit => 4) = URL.Body_Too_Large,
              "body too large");
   end Test_Limits;

   procedure Test_Faults (Item : in out Fixture) is
      pragma Unreferenced (Item);
   begin
      Assert
        (Outcome_Of ("a=1&b=2", Chunk => 1, Inject => Mem.Read_Failure, After => 3)
           = URL.Stream_Failed, "read failure surfaces");
      --  A premature EOF truncates the body but is not a framing error for a
      --  form: parsing ends cleanly with whatever arrived.
      Assert
        (Outcome_Of ("a=1&b=2", Chunk => 1, Inject => Mem.Premature_Eof, After => 3)
           = URL.Parsed, "premature eof ends cleanly");
   end Test_Faults;

   procedure Test_Ownership (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Body_Owner : Web.Binding.Bodies.Body_Claim :=
        Web.Binding.Bodies.New_Body;
      First, Second : Boolean;
      use type Web.Binding.Bodies.Body_State;
   begin
      Web.Binding.Bodies.Claim (Body_Owner, First);
      Web.Binding.Bodies.Release (Body_Owner, Success => True);
      Web.Binding.Bodies.Claim (Body_Owner, Second);
      Assert (First, "first claim granted");
      Assert (not Second, "second claim refused (already consumed)");
      Assert (Web.Binding.Bodies.State (Body_Owner) = Web.Binding.Bodies.Consumed,
              "state is consumed");
   end Test_Ownership;

   procedure Test_Fuzz (Item : in out Fixture) is
      pragma Unreferenced (Item);
      type U32 is mod 2 ** 32;
      Seed : U32 := 2_463_534;

      --  A wrapping LCG: modular arithmetic, so the multiply cannot overflow.
      function Next return Natural is
      begin
         Seed := Seed * 1_103_515_245 + 12_345;
         return Natural (Seed mod (2 ** 31));
      end Next;

      --  Crafted adversarial inputs that have historically broken parsers.
      procedure Check (Data : String) is
      begin
         for K in Positive range 1 .. 4 loop
            declare
               R : constant URL.Form_Source := Parse_At (Data, K);
            begin
               --  Reaching here means no exception and termination; output is
               --  bounded.
               Assert (URL.Field_Count (R) <= 512, "bounded field count");
            end;
         end loop;
      end Check;

   begin
      Check ("");
      Check ("&&&&");
      Check ("=");
      Check ("%");
      Check ("%%%%");
      Check ("a=%");
      Check ("a=%z");
      Check ("a==b==c");
      Check ("+++");
      Check ("a=" & [1 .. 200 => 'x']);
      Check ([1 .. 300 => '&']);

      --  Pseudo-random bytes at small chunk sizes.
      for Trial in 1 .. 150 loop
         declare
            Len  : constant Natural := Next mod 48;
            Data : String (1 .. Len);
         begin
            for I in Data'Range loop
               Data (I) := Character'Val (Next mod 256);
            end loop;
            declare
               R : constant URL.Form_Source := Parse_At (Data, 1 + (Next mod 5));
            begin
               Assert (URL.Field_Count (R) <= 512, "fuzz output bounded");
            end;
         end;
      end loop;
   end Test_Fuzz;

end Web_Binding_URLEncoded_Tests;
