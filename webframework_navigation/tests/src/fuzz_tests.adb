with AUnit.Assertions; use AUnit.Assertions;
with AUnit.Test_Caller;
with Ada.Strings.Fixed;
with Interfaces; use Interfaces;

with Web.Response;

with Navigation.Routes;
with Navigation.Params;
with Navigation.Menu; use Navigation.Menu;

with Webframework_Navigation;

--  Deterministic fuzz (a reproducible LCG -- no clock, no real randomness) over
--  the bridge's security-sensitive surface: HTML rendering must stay injection
--  safe and reproducible, and a reverse-URL redirect must never let a param
--  value inject an HTTP header (response splitting).
package body Fuzz_Tests is

   package WN renames Webframework_Navigation;
   package R  renames Navigation.Routes;
   package P  renames Navigation.Params;

   procedure Step (Seed : in out Unsigned_32) is
   begin
      Seed := Seed * 1103515245 + 12345;
   end Step;

   function Byte (Seed : Unsigned_32) return Natural is
     (Natural (Shift_Right (Seed, 16) and 16#FF#));

   function Count_Char (S : String; C : Character) return Natural is
      N : Natural := 0;
   begin
      for Ch of S loop
         if Ch = C then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Count_Char;

   procedure Test_Render_Injection_Safe (T : in out Fixture) is
      pragma Unreferenced (T);
      Empty_Routes : R.Table (1, 8);
      Seed : Unsigned_32 := 12345;
   begin
      for Iter in 1 .. 2000 loop
         declare
            M   : Menu (2, 512);
            Ig  : Item_Ref;
            Lab : String (1 .. 24);
            Url : String (1 .. 24);
            LL, UL : Natural;
         begin
            Step (Seed); LL := 1 + Byte (Seed) mod 24;
            Step (Seed); UL := 1 + Byte (Seed) mod 24;
            for I in 1 .. LL loop
               Step (Seed); Lab (I) := Character'Val (Byte (Seed));
            end loop;
            for I in 1 .. UL loop
               Step (Seed); Url (I) := Character'Val (Byte (Seed));
            end loop;

            Add_Link (M, No_Item, Lab (1 .. LL), Url (1 .. UL), Ig);
            Finalize (M);

            declare
               H1 : constant String := WN.Render_Menu (M, Empty_Routes);
               H2 : constant String := WN.Render_Menu (M, Empty_Routes);
            begin
               --  For one link item, all '<', '>' and '"' are structural; a
               --  leaked one would mean the label/URL broke out of the markup.
               Assert (Count_Char (H1, '<') = 6, "no injected '<' in rendered menu");
               Assert (Count_Char (H1, '>') = 6, "no injected '>' in rendered menu");
               Assert (Count_Char (H1, '"') = 2, "no injected attribute quote");
               Assert (H1 = H2, "rendering is deterministic");
            end;
         end;
      end loop;
   end Test_Render_Injection_Safe;

   procedure Test_Redirect_No_Header_Injection (T : in out Fixture) is
      pragma Unreferenced (T);
      Tbl   : R.Table (4, 64);
      Added : Boolean;
      Seed  : Unsigned_32 := 999;
   begin
      R.Add (Tbl, "show", "/users/:id", Added);
      R.Finalize (Tbl);

      for Iter in 1 .. 2000 loop
         declare
            Ps  : P.Set (2, 128);
            Val : String (1 .. 40);
            VL  : Natural;
            Ok  : Boolean;
         begin
            Step (Seed); VL := Byte (Seed) mod 41;   --  0 .. 40 (incl. empty)
            for I in 1 .. VL loop
               Step (Seed);
               Val (I) := Character'Val (Byte (Seed));  --  any byte incl CR/LF
            end loop;
            P.Add (Ps, "id", Val (1 .. VL), Ok);

            declare
               Resp : constant Web.Response.Response_Type :=
                 WN.Redirect_To (Tbl, "show", Ps);
               Loc  : constant String := Web.Response.Header (Resp, "Location");
            begin
               --  A param value can never inject a header: no raw CR/LF reaches
               --  the Location (navigation percent-encodes on build).
               Assert (Ada.Strings.Fixed.Index (Loc, (1 => Character'Val (13))) = 0
                       and then
                       Ada.Strings.Fixed.Index (Loc, (1 => Character'Val (10))) = 0,
                       "no CR/LF in the Location header (no response splitting)");
            end;
         end;
      end loop;
   end Test_Redirect_No_Header_Injection;

   package Caller is new AUnit.Test_Caller (Fixture);

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Suite.Add_Test
        (Caller.Create ("Fuzz: render injection-safe (2000x)",
         Test_Render_Injection_Safe'Access));
      Suite.Add_Test
        (Caller.Create ("Fuzz: redirect no header injection (2000x)",
         Test_Redirect_No_Header_Injection'Access));
   end Add_Tests;

end Fuzz_Tests;
