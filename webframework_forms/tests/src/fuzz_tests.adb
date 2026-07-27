with AUnit.Assertions; use AUnit.Assertions;
with AUnit.Test_Caller;
with Ada.Strings;
with Ada.Strings.Fixed;
with Interfaces; use Interfaces;

with Web.Request;
with Web.Server;

with Forms.Submission;
with Forms.Urlencoded;
with Forms.CSRF;

with Webframework_Forms;

--  Deterministic fuzz (a reproducible LCG) over the bridge's two request-facing
--  entry points: decoding a body and verifying CSRF must never raise and must be
--  deterministic on any input.
package body Fuzz_Tests is

   package WF renames Webframework_Forms;
   use type Forms.Urlencoded.Decode_Status;

   CRLF : constant String := (Character'Val (13), Character'Val (10));

   procedure Step (Seed : in out Unsigned_32) is
   begin
      Seed := Seed * 1103515245 + 12345;
   end Step;

   function Pick (Seed : Unsigned_32; Alpha : String) return Character is
     (Alpha (Alpha'First
             + Natural (Shift_Right (Seed, 16) and 16#FFFF#) mod Alpha'Length));

   function Post (Body_S : String; Cookie : String := "")
                  return Web.Request.Request_Type
   is
      Len : constant String :=
        Ada.Strings.Fixed.Trim (Integer'Image (Body_S'Length), Ada.Strings.Left);
   begin
      return Web.Server.Parse_Request
        ("POST / HTTP/1.1" & CRLF & "Host: x" & CRLF
         & (if Cookie = "" then "" else "Cookie: " & Cookie & CRLF)
         & "Content-Type: application/x-www-form-urlencoded" & CRLF
         & "Content-Length: " & Len & CRLF & CRLF & Body_S);
   end Post;

   procedure Test_Decode_Robust (T : in out Fixture) is
      pragma Unreferenced (T);
      --  Chars that stress the urlencoded decoder: escapes, delimiters, hex.
      Alpha : constant String := "abcAB012%%&&==++/ ";
      Seed  : Unsigned_32 := 4242;
   begin
      for Iter in 1 .. 2000 loop
         declare
            Body_S : String (1 .. 60);
            BL     : Natural;
            Sub1, Sub2 : Forms.Submission.Data (16, 2048);
            S1, S2 : Forms.Urlencoded.Decode_Status;
         begin
            Step (Seed); BL := Natural (Shift_Right (Seed, 8) and 16#3F#);  -- 0..63
            if BL > 60 then
               BL := 60;
            end if;
            for I in 1 .. BL loop
               Step (Seed); Body_S (I) := Pick (Seed, Alpha);
            end loop;
            declare
               Req : constant Web.Request.Request_Type := Post (Body_S (1 .. BL));
            begin
               WF.Read_Urlencoded (Req, Sub1, S1);
               WF.Read_Urlencoded (Req, Sub2, S2);
               --  Never raises; same input -> same status (determinism).
               Assert (S1 = S2, "decode is deterministic and total");
            end;
         end;
      end loop;
   end Test_Decode_Robust;

   procedure Test_Verify_Csrf_Robust (T : in out Fixture) is
      pragma Unreferenced (T);
      Alpha : constant String := "abcdef0123; =_csrftokenABCDEF";
      Seed  : Unsigned_32 := 7;
      Sub   : Forms.Submission.Data (4, 256);
      Added : Boolean;
   begin
      Forms.Submission.Add
        (Sub, Forms.CSRF.Default_Field, WF.To_Bytes ("00ff00ff"), Added);
      for Iter in 1 .. 2000 loop
         declare
            Cookie : String (1 .. 48);
            CL     : Natural;
         begin
            Step (Seed); CL := 1 + Natural (Shift_Right (Seed, 8) and 16#1F#); -- 1..32
            for I in 1 .. CL loop
               Step (Seed); Cookie (I) := Pick (Seed, Alpha);
            end loop;
            declare
               Req : constant Web.Request.Request_Type :=
                 Post ("x=1", Cookie => Cookie (1 .. CL));
               V1  : constant Boolean := WF.Verify_Csrf (Req, Sub);
               V2  : constant Boolean := WF.Verify_Csrf (Req, Sub);
            begin
               --  Never raises; deterministic. (A random cookie effectively
               --  never matches the fixed field, so this also stays fail-closed.)
               Assert (V1 = V2, "CSRF verification is deterministic and total");
            end;
         end;
      end loop;
   end Test_Verify_Csrf_Robust;

   package Caller is new AUnit.Test_Caller (Fixture);

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Suite.Add_Test
        (Caller.Create ("Fuzz: decode robust (2000x)", Test_Decode_Robust'Access));
      Suite.Add_Test
        (Caller.Create ("Fuzz: verify CSRF robust (2000x)",
         Test_Verify_Csrf_Robust'Access));
   end Add_Tests;

end Fuzz_Tests;
