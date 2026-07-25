with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions;
with AUnit.Test_Caller;

with Web.Binding;
with Web.Binding.Errors;
with Web.Binding.Streams.Memory;
with Web.Binding.Codecs.JSON;

package body Web_Binding_JSON_Tests is

   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;
   use Web.Binding;
   use Web.Binding.Errors;

   package JSON renames Web.Binding.Codecs.JSON;
   package Mem renames Web.Binding.Streams.Memory;
   use JSON;

   DQ : constant Character := '"';
   LF : constant Character := Character'Val (10);

   --  Tokenize Data (in Chunk-sized reads), producing a compact trace, the
   --  terminal token kind, and any error id.
   procedure Run
     (Data     : String;
      Chunk    : Positive;
      Settings : JSON.Config;
      Terminal : out JSON.Token_Kind;
      E        : out Web.Binding.Errors.Error_Id;
      Trace    : out Unbounded_String)
   is
      S : aliased Mem.Memory_Stream := Mem.Create (Data, Chunk);
      R : JSON.Reader (S'Access);
   begin
      Trace := Null_Unbounded_String;
      JSON.Start (R, Settings);
      loop
         JSON.Advance (R);
         case JSON.Kind (R) is
            when Start_Object  => Append (Trace, "{ ");
            when End_Object    => Append (Trace, "} ");
            when Start_Array   => Append (Trace, "[ ");
            when End_Array     => Append (Trace, "] ");
            when Key           => Append (Trace, "k:" & JSON.Text (R) & " ");
            when String_Value  => Append (Trace, "s:" & JSON.Text (R) & " ");
            when Number_Value  => Append (Trace, "n:" & JSON.Text (R) & " ");
            when Boolean_Value =>
               Append (Trace, (if JSON.Bool_Value (R) then "T " else "F "));
            when Null_Value    => Append (Trace, "z ");
            when End_Document | Error_Token => exit;
         end case;
      end loop;
      Terminal := JSON.Kind (R);
      E := JSON.Error_Id (R);
   end Run;

   function Trace_Of
     (Data : String; Chunk : Positive := Positive'Last) return String
   is
      T : JSON.Token_Kind;
      E : Web.Binding.Errors.Error_Id;
      Tr : Unbounded_String;
   begin
      Run (Data, Chunk, JSON.Default_Config, T, E, Tr);
      return To_String (Tr);
   end Trace_Of;

   function Valid (Data : String) return Boolean is
      T : JSON.Token_Kind;
      E : Web.Binding.Errors.Error_Id;
      Tr : Unbounded_String;
   begin
      Run (Data, Positive'Last, JSON.Default_Config, T, E, Tr);
      return T = End_Document;
   end Valid;

   function Err_Of
     (Data : String; Settings : JSON.Config := JSON.Default_Config)
      return Web.Binding.Errors.Error_Id
   is
      T : JSON.Token_Kind;
      E : Web.Binding.Errors.Error_Id;
      Tr : Unbounded_String;
   begin
      Run (Data, Positive'Last, Settings, T, E, Tr);
      return E;
   end Err_Of;

   --  The decoded text of the first String_Value token.
   function First_String (Data : String) return String is
      S : aliased Mem.Memory_Stream := Mem.Create (Data);
      R : JSON.Reader (S'Access);
   begin
      JSON.Start (R, JSON.Default_Config);
      loop
         JSON.Advance (R);
         exit when JSON.Kind (R) in String_Value | End_Document | Error_Token;
      end loop;
      return JSON.Text (R);
   end First_String;

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("json structure", Test_Structure'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("json escapes", Test_Escapes'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("json numbers", Test_Numbers'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("json strict", Test_Strict'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("json limits", Test_Limits'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("json location", Test_Location'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("json fragmentation", Test_Fragmentation'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("json fuzz", Test_Fuzz'Access));
   end Add_Tests;

   procedure Test_Structure (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Obj : constant String :=
        "{" & DQ & "a" & DQ & ":1," & DQ & "b" & DQ & ":[true,null," & DQ & "x"
        & DQ & "]}";
   begin
      Assert (Trace_Of (Obj) = "{ k:a n:1 k:b [ T z s:x ] } ",
              "object/array token stream");
      Assert (Trace_Of ("{}") = "{ } ", "empty object");
      Assert (Trace_Of ("[]") = "[ ] ", "empty array");
   end Test_Structure;

   procedure Test_Escapes (Item : in out Fixture) is
      pragma Unreferenced (Item);
   begin
      Assert (First_String (DQ & "\n" & DQ) = [1 => LF], "newline escape");
      Assert (First_String (DQ & "\t" & DQ) = [1 => Character'Val (9)],
              "tab escape");
      Assert (First_String (DQ & "A" & DQ) = "A", "\\u escape");
      --  Surrogate pair for U+1F600 encodes to four UTF-8 bytes.
      Assert (First_String (DQ & "\uD83D\uDE00" & DQ)'Length = 4,
              "surrogate pair -> 4-byte utf8");
      Assert (Err_Of (DQ & "\x" & DQ) = Json_Malformed, "invalid escape");
      Assert (Err_Of (DQ & "\uD800" & DQ) = Json_Malformed, "lone high surrogate");
      Assert (Err_Of (DQ & "\uDC00" & DQ) = Json_Malformed, "lone low surrogate");
   end Test_Escapes;

   procedure Test_Numbers (Item : in out Fixture) is
      pragma Unreferenced (Item);
   begin
      Assert (Valid ("0"), "0");
      Assert (Valid ("-0"), "-0");
      Assert (Valid ("123"), "123");
      Assert (Valid ("-1.5"), "-1.5");
      Assert (Valid ("1e10"), "1e10");
      Assert (Valid ("1.5E-3"), "1.5E-3");
      Assert (not Valid ("01"), "leading zero");
      Assert (not Valid ("1."), "trailing dot");
      Assert (not Valid (".5"), "leading dot");
      Assert (not Valid ("1e"), "empty exponent");
      Assert (not Valid ("+1"), "leading plus");
      Assert (not Valid ("NaN"), "NaN rejected");
   end Test_Numbers;

   procedure Test_Strict (Item : in out Fixture) is
      pragma Unreferenced (Item);
   begin
      Assert (Err_Of ("{}x") = Json_Trailing_Content, "trailing content");
      Assert (Err_Of ("[1,]") = Json_Malformed, "trailing comma");
      Assert (Err_Of ("[1 2]") = Json_Malformed, "missing comma");
      Assert (Err_Of ("{/*c*/}") = Json_Malformed, "comment rejected");
      Assert (Err_Of ("") = Json_Malformed, "empty document");
   end Test_Strict;

   procedure Test_Limits (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Shallow : JSON.Config := JSON.Default_Config;
      Short_S : JSON.Config := JSON.Default_Config;
      Short_N : JSON.Config := JSON.Default_Config;
   begin
      Shallow.Max_Depth := 3;
      Assert (Err_Of ("[[[[1]]]]", Shallow) = Json_Depth_Exceeded, "depth limit");
      Short_S.Max_String := 3;
      Assert (Err_Of (DQ & "abcdef" & DQ, Short_S) = Decode_Value_Too_Long,
              "string too long");
      Short_N.Max_Number := 3;
      Assert (Err_Of ("123456", Short_N) = Json_Number_Out_Of_Range,
              "number too long");
   end Test_Limits;

   procedure Test_Location (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Data : constant String := "[" & LF & "true]";
      S : aliased Mem.Memory_Stream := Mem.Create (Data);
      R : JSON.Reader (S'Access);
   begin
      JSON.Start (R, JSON.Default_Config);
      JSON.Advance (R);  --  Start_Array at line 1
      Assert (JSON.Line (R) = 1 and then JSON.Column (R) = 1, "array at 1:1");
      JSON.Advance (R);  --  true at line 2
      Assert (JSON.Kind (R) = Boolean_Value, "boolean token");
      Assert (JSON.Line (R) = 2 and then JSON.Column (R) = 1
                and then JSON.Offset (R) = 2, "boolean at 2:1 offset 2");
   end Test_Location;

   procedure Test_Fragmentation (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Data : constant String :=
        "{" & DQ & "a" & DQ & ":[1,-2.5,true," & DQ & "xAy" & DQ
        & ",null]}";
      Full : constant String := Trace_Of (Data);
      Chunks : constant array (1 .. 5) of Positive := [1, 2, 3, 7, 1000];
   begin
      for K of Chunks loop
         Assert (Trace_Of (Data, K) = Full,
                 "fragmentation-invariant at chunk" & K'Image);
      end loop;
   end Test_Fragmentation;

   procedure Test_Fuzz (Item : in out Fixture) is
      pragma Unreferenced (Item);
      type U32 is mod 2 ** 32;
      Seed : U32 := 987_654_321;

      function Next return Natural is
      begin
         Seed := Seed * 1_103_515_245 + 12_345;
         return Natural (Seed mod (2 ** 31));
      end Next;

      procedure Check (Data : String) is
         T : JSON.Token_Kind;
         E : Web.Binding.Errors.Error_Id;
         Tr : Unbounded_String;
      begin
         for K in Positive range 1 .. 3 loop
            Run (Data, K, JSON.Default_Config, T, E, Tr);
            --  Reaching here = terminated without exception.
            Assert (T in End_Document | Error_Token, "terminates cleanly");
         end loop;
      end Check;

   begin
      Check ("");
      Check ("{");
      Check ("[");
      Check ("}");
      Check ("[[[[[[[[[[");
      Check (DQ & "unterminated");
      Check (DQ & "\u");
      Check (DQ & "\uD800");
      Check ("{" & DQ & "k" & DQ & ":");
      Check ("-");
      Check ("1e+");
      Check ("truX");
      Check ("[1,2,3" & [1 .. 100 => ',']);

      declare
         Alpha : constant String := "{}[],:0123456789.eE-+tfn \" & DQ;
      begin
         for Trial in 1 .. 200 loop
            declare
               Len  : constant Natural := Next mod 40;
               Data : String (1 .. Len);
            begin
               for I in Data'Range loop
                  --  Bias toward JSON-significant bytes to exercise the grammar.
                  if Next mod 3 = 0 then
                     Data (I) := Alpha (1 + (Next mod Alpha'Length));
                  else
                     Data (I) := Character'Val (Next mod 256);
                  end if;
               end loop;
               Check (Data);
            end;
         end loop;
      end;
   end Test_Fuzz;

end Web_Binding_JSON_Tests;
