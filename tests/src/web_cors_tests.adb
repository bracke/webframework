with AUnit.Assertions; use AUnit.Assertions;
with AUnit.Test_Caller;

with Web.Request;
with Web.Response;
with Web.Server;
with Web.CORS;

package body Web_CORS_Tests is

   CRLF : constant String := Character'Val (13) & Character'Val (10);

   --  A request with the given method and an optional Origin / preflight method.
   function Req
     (Method : String;
      Origin : String := "";
      Preflight_Method : String := "") return Web.Request.Request_Type
   is
      Origin_Line : constant String :=
        (if Origin'Length > 0 then "Origin: " & Origin & CRLF else "");
      Pre_Line : constant String :=
        (if Preflight_Method'Length > 0
         then "Access-Control-Request-Method: " & Preflight_Method & CRLF
         else "");
   begin
      return Web.Server.Parse_Request
        (Method & " /x HTTP/1.1" & CRLF & "Host: localhost" & CRLF
         & Origin_Line & Pre_Line & CRLF);
   end Req;

   ACAO : constant String := "Access-Control-Allow-Origin";

   procedure Test_Any_Origin (T : in out Fixture) is
      pragma Unreferenced (T);
      P : constant Web.CORS.Policy := Web.CORS.Make (Origins => "*");
      R : Web.Response.Response_Type := Web.Response.Text ("ok");
   begin
      Web.CORS.Apply (P, Req ("GET", "https://a.example"), R);
      Assert (Web.Response.Header (R, ACAO) = "*",
              "any-origin echoes *: " & Web.Response.Header (R, ACAO));
   end Test_Any_Origin;

   procedure Test_Allowlist_Hit (T : in out Fixture) is
      pragma Unreferenced (T);
      P : constant Web.CORS.Policy :=
        Web.CORS.Make (Origins => "https://a.example, https://b.example");
      R : Web.Response.Response_Type := Web.Response.Text ("ok");
   begin
      Web.CORS.Apply (P, Req ("GET", "https://b.example"), R);
      Assert (Web.Response.Header (R, ACAO) = "https://b.example",
              "allowed origin echoed");
      Assert (Web.Response.Has_Header (R, "Vary"), "response varies by origin");
   end Test_Allowlist_Hit;

   procedure Test_Allowlist_Miss (T : in out Fixture) is
      pragma Unreferenced (T);
      P : constant Web.CORS.Policy :=
        Web.CORS.Make (Origins => "https://a.example");
      R : Web.Response.Response_Type := Web.Response.Text ("ok");
   begin
      Web.CORS.Apply (P, Req ("GET", "https://evil.example"), R);
      Assert (not Web.Response.Has_Header (R, ACAO),
              "a disallowed origin gets no CORS header");
   end Test_Allowlist_Miss;

   procedure Test_No_Origin (T : in out Fixture) is
      pragma Unreferenced (T);
      P : constant Web.CORS.Policy := Web.CORS.Make (Origins => "*");
      R : Web.Response.Response_Type := Web.Response.Text ("ok");
   begin
      Web.CORS.Apply (P, Req ("GET"), R);
      Assert (not Web.Response.Has_Header (R, ACAO),
              "a same-origin request (no Origin) gets no CORS header");
   end Test_No_Origin;

   procedure Test_Credentials (T : in out Fixture) is
      pragma Unreferenced (T);
      P : constant Web.CORS.Policy :=
        Web.CORS.Make (Origins => "https://a.example", Credentials => True);
      R : Web.Response.Response_Type := Web.Response.Text ("ok");
   begin
      Web.CORS.Apply (P, Req ("GET", "https://a.example"), R);
      Assert (Web.Response.Header (R, ACAO) = "https://a.example",
              "credentials echo the specific origin, never *");
      Assert (Web.Response.Header (R, "Access-Control-Allow-Credentials") = "true",
              "allow-credentials set");
   end Test_Credentials;

   procedure Test_Preflight (T : in out Fixture) is
      pragma Unreferenced (T);
      P : constant Web.CORS.Policy :=
        Web.CORS.Make (Origins => "*", Max_Age => 600);
      R : Web.Response.Response_Type := Web.Response.Text ("");
   begin
      Web.CORS.Apply
        (P, Req ("OPTIONS", "https://a.example", Preflight_Method => "DELETE"), R);
      Assert (Web.Response.Has_Header (R, "Access-Control-Allow-Methods"),
              "preflight advertises allowed methods");
      Assert (Web.Response.Header (R, "Access-Control-Max-Age") = "600",
              "preflight max-age set");
   end Test_Preflight;

   package Caller is new AUnit.Test_Caller (Fixture);

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Suite.Add_Test (Caller.Create ("CORS: any origin", Test_Any_Origin'Access));
      Suite.Add_Test (Caller.Create ("CORS: allowlist hit", Test_Allowlist_Hit'Access));
      Suite.Add_Test (Caller.Create ("CORS: allowlist miss", Test_Allowlist_Miss'Access));
      Suite.Add_Test (Caller.Create ("CORS: no origin", Test_No_Origin'Access));
      Suite.Add_Test (Caller.Create ("CORS: credentials", Test_Credentials'Access));
      Suite.Add_Test (Caller.Create ("CORS: preflight", Test_Preflight'Access));
   end Add_Tests;

end Web_CORS_Tests;
