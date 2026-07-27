with AUnit.Assertions; use AUnit.Assertions;
with AUnit.Test_Caller;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Web.Multipart;

package body Web_Multipart_Tests is

   use type Web.Multipart.Part_Kind;
   use type Web.Multipart.Parse_Status;

   CRLF : constant String := ASCII.CR & ASCII.LF;
   B    : constant String := "XBOUND";

   function Body_Text return String is
     ("--" & B & CRLF
      & "Content-Disposition: form-data; name=""title""" & CRLF
      & CRLF
      & "Hello" & CRLF
      & "--" & B & CRLF
      & "Content-Disposition: form-data; name=""file""; filename=""a.txt""" & CRLF
      & "Content-Type: text/plain" & CRLF
      & CRLF
      & "file-content" & CRLF
      & "--" & B & "--" & CRLF);

   procedure Test_Boundary_Of (T : in out Fixture) is
      pragma Unreferenced (T);
   begin
      Assert (Web.Multipart.Boundary_Of
                ("multipart/form-data; boundary=XBOUND") = "XBOUND",
              "boundary extracted");
      Assert (Web.Multipart.Boundary_Of
                ("multipart/form-data; boundary=""quoted""") = "quoted",
              "quoted boundary extracted");
      Assert (Web.Multipart.Boundary_Of ("text/plain") = "", "no boundary");
   end Test_Boundary_Of;

   procedure Test_Parse (T : in out Fixture) is
      pragma Unreferenced (T);
      Text   : constant String := Body_Text;
      Parts  : Web.Multipart.Part_Array (1 .. 8);
      Count  : Natural;
      Status : Web.Multipart.Parse_Status;
   begin
      Web.Multipart.Parse (Text, B, Parts, Count, Status);
      Assert (Status = Web.Multipart.Ok, "parse ok");
      Assert (Count = 2, "two parts");

      Assert (Parts (1).Kind = Web.Multipart.Field_Part, "part 1 is a field");
      Assert (To_String (Parts (1).Name) = "title", "part 1 name");
      Assert (Text (Parts (1).First .. Parts (1).Last) = "Hello", "part 1 content");

      Assert (Parts (2).Kind = Web.Multipart.File_Part, "part 2 is a file");
      Assert (To_String (Parts (2).Name) = "file", "part 2 name");
      Assert (To_String (Parts (2).Filename) = "a.txt", "part 2 filename");
      Assert (To_String (Parts (2).Content_Type) = "text/plain", "part 2 type");
      Assert (Text (Parts (2).First .. Parts (2).Last) = "file-content",
              "part 2 content");
   end Test_Parse;

   package Caller is new AUnit.Test_Caller (Fixture);
   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Suite.Add_Test (Caller.Create ("Multipart: boundary", Test_Boundary_Of'Access));
      Suite.Add_Test (Caller.Create ("Multipart: parse", Test_Parse'Access));
   end Add_Tests;

end Web_Multipart_Tests;
