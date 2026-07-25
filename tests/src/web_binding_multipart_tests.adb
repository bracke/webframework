with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with AUnit.Assertions;
with AUnit.Test_Caller;

with Web.Binding.Streams.Memory;
with Web.Binding.Multipart;

package body Web_Binding_Multipart_Tests is

   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;

   package MP renames Web.Binding.Multipart;
   package Mem renames Web.Binding.Streams.Memory;
   use type MP.Outcome;

   NL : constant String := [Character'Val (13), Character'Val (10)];

   Body_Text : constant String :=
     "--BND" & NL
     & "Content-Disposition: form-data; name=""field1""" & NL & NL
     & "value1" & NL
     & "--BND" & NL
     & "Content-Disposition: form-data; name=""field2""" & NL & NL
     & "value2" & NL
     & "--BND" & NL
     & "Content-Disposition: form-data; name=""file1""; filename=""a.txt""" & NL
     & "Content-Type: text/plain" & NL & NL
     & "FILEDATA" & NL
     & "--BND--" & NL;

   --  Walk every part, producing a compact trace, and report the final status.
   procedure Run
     (Data     : String;
      Chunk    : Positive;
      Settings : MP.Config;
      Trace    : out Unbounded_String;
      Final    : out MP.Outcome)
   is
      S    : aliased Mem.Memory_Stream := Mem.Create (Data, Chunk);
      R    : MP.Multipart_Reader (S'Access);
      Info : MP.Part_Info;
      Avail : Boolean;
      Val  : Unbounded_String;
   begin
      Trace := Null_Unbounded_String;
      MP.Start (R, "BND", Settings);
      loop
         MP.Next_Part (R, Info, Avail);
         exit when not Avail;
         MP.Read_Text (R, Val);
         Append (Trace, MP.Meta_Strings.To_String (Info.Name) & "=");
         Append (Trace, To_String (Val));
         if Info.Is_File then
            Append (Trace, "(file:" & MP.Meta_Strings.To_String (Info.Filename)
                    & "," & MP.Meta_Strings.To_String (Info.Content_Type) & ")");
         end if;
         Append (Trace, " ");
      end loop;
      Final := MP.Status (R);
   end Run;

   function Trace_Of
     (Data : String; Chunk : Positive := Positive'Last) return String
   is
      T : Unbounded_String;
      F : MP.Outcome;
   begin
      Run (Data, Chunk, MP.Default_Config, T, F);
      return To_String (T);
   end Trace_Of;

   function Final_Of
     (Data : String; Settings : MP.Config; Chunk : Positive := Positive'Last)
      return MP.Outcome
   is
      T : Unbounded_String;
      F : MP.Outcome;
   begin
      Run (Data, Chunk, Settings, T, F);
      return F;
   end Final_Of;

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("multipart parse", Test_Parse'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("multipart fragmentation", Test_Fragmentation'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("multipart limits", Test_Limits'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("multipart fuzz", Test_Fuzz'Access));
   end Add_Tests;

   procedure Test_Parse (Item : in out Fixture) is
      pragma Unreferenced (Item);
   begin
      Assert (Trace_Of (Body_Text)
                = "field1=value1 field2=value2 "
                & "file1=FILEDATA(file:a.txt,text/plain) ",
              "fields and file part parsed");
   end Test_Parse;

   procedure Test_Fragmentation (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Full   : constant String := Trace_Of (Body_Text);
      Chunks : constant array (1 .. 6) of Positive := [1, 2, 3, 5, 13, 5000];
   begin
      for K of Chunks loop
         Assert (Trace_Of (Body_Text, K) = Full,
                 "fragmentation-invariant at chunk" & K'Image);
      end loop;
   end Test_Fragmentation;

   procedure Test_Limits (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Few    : MP.Config := MP.Default_Config;
      Small_H : MP.Config := MP.Default_Config;
      Small_F : MP.Config := MP.Default_Config;
      Unterminated : constant String :=
        "--BND" & NL
        & "Content-Disposition: form-data; name=""x""" & NL & NL
        & "novalueterminator";
   begin
      Few.Max_Parts := 2;
      Assert (Final_Of (Body_Text, Few) = MP.Too_Many_Parts, "too many parts");
      Small_H.Max_Header_Bytes := 10;
      Assert (Final_Of (Body_Text, Small_H) = MP.Header_Too_Large,
              "header too large");
      Small_F.Max_Field_Bytes := 3;
      Assert (Final_Of (Body_Text, Small_F) = MP.Field_Too_Large,
              "field too large");
      Assert (Final_Of (Unterminated, MP.Default_Config) = MP.Malformed,
              "unterminated part");
   end Test_Limits;

   procedure Test_Fuzz (Item : in out Fixture) is
      pragma Unreferenced (Item);
      type U32 is mod 2 ** 32;
      Seed : U32 := 424_242;

      function Next return Natural is
      begin
         Seed := Seed * 1_103_515_245 + 12_345;
         return Natural (Seed mod (2 ** 31));
      end Next;

      procedure Check (Data : String) is
         T : Unbounded_String;
         F : MP.Outcome;
      begin
         for K in Positive range 1 .. 3 loop
            Run (Data, K, MP.Default_Config, T, F);
            Assert (F'Valid, "terminates with a defined outcome");
         end loop;
      end Check;

      Alpha : constant String := "-BND" & NL & "Cotn:; =""x." & Character'Val (0);
   begin
      Check ("");
      Check ("--BND");
      Check ("--BND--");
      Check ("--BND" & NL);
      Check ("--BND" & NL & NL);
      Check (Body_Text (Body_Text'First .. Body_Text'First + 40));

      for Trial in 1 .. 150 loop
         declare
            Len  : constant Natural := Next mod 60;
            Data : String (1 .. Len);
         begin
            for I in Data'Range loop
               if Next mod 2 = 0 then
                  Data (I) := Alpha (1 + (Next mod Alpha'Length));
               else
                  Data (I) := Character'Val (Next mod 256);
               end if;
            end loop;
            Check (Data);
         end;
      end loop;
   end Test_Fuzz;

end Web_Binding_Multipart_Tests;
