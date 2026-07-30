with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with AUnit.Assertions; use AUnit.Assertions;
with AUnit.Test_Caller;

with Web.Request;
with Web.Response;
with Web.Context;
with Web.Server;
with Web.Errors;

package body Web_Routing_Tests is

   --  A plain handler that echoes the request method.
   function Echo_Method
     (Request : Web.Request.Request_Type) return Web.Response.Response_Type is
     (Web.Response.Text ("m=" & Web.Request.Method (Request)));

   --  Context-aware handlers that echo captured path parameters.
   function Echo_Id
     (Request : Web.Request.Request_Type;
      Context : Web.Context.Request_Context) return Web.Response.Response_Type
   is
      pragma Unreferenced (Request);
   begin
      return Web.Response.Text ("id=" & Web.Context.Path_Param (Context, "id"));
   end Echo_Id;

   function Echo_Org_User
     (Request : Web.Request.Request_Type;
      Context : Web.Context.Request_Context) return Web.Response.Response_Type
   is
      pragma Unreferenced (Request);
   begin
      return Web.Response.Text
        ("o=" & Web.Context.Path_Param (Context, "org")
         & ",u=" & Web.Context.Path_Param (Context, "id"));
   end Echo_Org_User;

   function Say_Exact
     (Request : Web.Request.Request_Type;
      Context : Web.Context.Request_Context) return Web.Response.Response_Type
   is
      pragma Unreferenced (Request, Context);
   begin
      return Web.Response.Text ("exact");
   end Say_Exact;

   function Dispatch (Method, Path : String) return Web.Response.Response_Type is
     (Web.Server.Dispatch (Web.Request.Create (Method, Path)));

   function Body_Of (R : Web.Response.Response_Type) return String is
     (Web.Response.Content_Body (R));

   procedure Test_New_Verbs (T : in out Fixture) is
      pragma Unreferenced (T);
   begin
      Web.Server.Put ("/rt-verb", Echo_Method'Access);
      Web.Server.Patch ("/rt-verb", Echo_Method'Access);
      Web.Server.Delete ("/rt-verb", Echo_Method'Access);
      Assert (Body_Of (Dispatch ("PUT", "/rt-verb")) = "m=PUT", "PUT routed");
      Assert (Body_Of (Dispatch ("PATCH", "/rt-verb")) = "m=PATCH", "PATCH routed");
      Assert (Body_Of (Dispatch ("DELETE", "/rt-verb")) = "m=DELETE", "DELETE routed");
      Assert (Web.Response.Status (Dispatch ("PUT", "/rt-verb")) = 200, "200");
   end Test_New_Verbs;

   procedure Test_Path_Param (T : in out Fixture) is
      pragma Unreferenced (T);
   begin
      Web.Server.Get ("/rt-users/:id", Echo_Id'Access);
      Assert (Body_Of (Dispatch ("GET", "/rt-users/42")) = "id=42",
              "path parameter captured");
      Assert (Body_Of (Dispatch ("GET", "/rt-users/abc")) = "id=abc",
              "any segment captured");
      --  A different segment count does not match.
      Assert (Web.Response.Status (Dispatch ("GET", "/rt-users/42/x")) = 404,
              "extra segment does not match");
   end Test_Path_Param;

   procedure Test_Multi_Param (T : in out Fixture) is
      pragma Unreferenced (T);
   begin
      Web.Server.Delete ("/rt-org/:org/users/:id", Echo_Org_User'Access);
      Assert (Body_Of (Dispatch ("DELETE", "/rt-org/acme/users/7")) = "o=acme,u=7",
              "two parameters captured");
   end Test_Multi_Param;

   procedure Test_Static_Beats_Pattern (T : in out Fixture) is
      pragma Unreferenced (T);
   begin
      --  Register the pattern first; the exact route must still win for /me.
      Web.Server.Get ("/rt-acct/:id", Echo_Id'Access);
      Web.Server.Get ("/rt-acct/me", Say_Exact'Access);
      Assert (Body_Of (Dispatch ("GET", "/rt-acct/me")) = "exact",
              "exact route beats the pattern");
      Assert (Body_Of (Dispatch ("GET", "/rt-acct/99")) = "id=99",
              "pattern still matches other ids");
   end Test_Static_Beats_Pattern;

   procedure Test_Method_Not_Allowed (T : in out Fixture) is
      pragma Unreferenced (T);
      R : Web.Response.Response_Type;
   begin
      Web.Server.Get ("/rt-only", Echo_Method'Access);
      R := Dispatch ("POST", "/rt-only");
      Assert (Web.Response.Status (R) = 405, "405 for wrong method");
      Assert (Web.Response.Has_Header (R, "Allow"), "Allow header present");
      declare
         Allow : constant String := Web.Response.Header (R, "Allow");
      begin
         Assert (Index (Allow, "GET") > 0, "Allow lists GET: " & Allow);
         Assert (Index (Allow, "OPTIONS") > 0, "Allow lists OPTIONS: " & Allow);
      end;
   end Test_Method_Not_Allowed;

   procedure Test_Auto_Options (T : in out Fixture) is
      pragma Unreferenced (T);
      R : Web.Response.Response_Type;
   begin
      Web.Server.Get ("/rt-opt", Echo_Method'Access);
      Web.Server.Post ("/rt-opt", Echo_Method'Access);
      R := Dispatch ("OPTIONS", "/rt-opt");
      Assert (Web.Response.Status (R) = 204, "204 for OPTIONS");
      declare
         Allow : constant String := Web.Response.Header (R, "Allow");
      begin
         Assert (Index (Allow, "GET") > 0 and then Index (Allow, "POST") > 0
                 and then Index (Allow, "OPTIONS") > 0,
                 "Allow lists GET, POST, OPTIONS: " & Allow);
      end;
   end Test_Auto_Options;

   procedure Test_Not_Found (T : in out Fixture) is
      pragma Unreferenced (T);
   begin
      Assert (Web.Response.Status (Dispatch ("GET", "/rt-nope")) = 404,
              "unknown path is 404");
   end Test_Not_Found;

   procedure Test_Plain_Param_Rejected (T : in out Fixture) is
      pragma Unreferenced (T);
      Raised : Boolean := False;
   begin
      begin
         Web.Server.Put ("/rt-bad/:id", Echo_Method'Access);
      exception
         when Web.Errors.Security_Error =>
            Raised := True;
      end;
      Assert (Raised, "a plain-handler route with a path parameter is rejected");
   end Test_Plain_Param_Rejected;

   package Caller is new AUnit.Test_Caller (Fixture);

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Suite.Add_Test (Caller.Create ("Routing: new verbs", Test_New_Verbs'Access));
      Suite.Add_Test (Caller.Create ("Routing: path parameter", Test_Path_Param'Access));
      Suite.Add_Test (Caller.Create ("Routing: multiple parameters", Test_Multi_Param'Access));
      Suite.Add_Test (Caller.Create ("Routing: exact beats pattern", Test_Static_Beats_Pattern'Access));
      Suite.Add_Test (Caller.Create ("Routing: 405 + Allow", Test_Method_Not_Allowed'Access));
      Suite.Add_Test (Caller.Create ("Routing: auto OPTIONS", Test_Auto_Options'Access));
      Suite.Add_Test (Caller.Create ("Routing: not found", Test_Not_Found'Access));
      Suite.Add_Test (Caller.Create ("Routing: plain param rejected", Test_Plain_Param_Rejected'Access));
   end Add_Tests;

end Web_Routing_Tests;
