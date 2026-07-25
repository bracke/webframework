with AUnit.Assertions;
with AUnit.Test_Caller;

with Web.Request;
with Web.Cookie;
with Web.Binding.Sources;
with Web.Binding.Policies;
with Web.Binding.Query;
with Web.Binding.Route;
with Web.Binding.Headers;
with Web.Binding.Cookies;

package body Web_Binding_Source_Tests is

   package Caller is new AUnit.Test_Caller (Fixture);
   use AUnit.Assertions;

   use Web.Binding.Sources;
   use Web.Binding.Policies;

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("source query", Test_Query'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("source resolution", Test_Resolution'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("source route", Test_Route'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("source headers", Test_Headers'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("source cookies", Test_Cookies'Access));
      AUnit.Test_Suites.Add_Test
        (Suite, Caller.Create ("source mixed", Test_Mixed'Access));
   end Add_Tests;

   procedure Test_Query (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Q : constant Web.Binding.Query.Query_Source :=
        Web.Binding.Query.Parse ("a=1&a=2&b=&c=x%20y&d=e+f&g=%zz&h");
      A : constant Occurrences := Web.Binding.Query.Lookup (Q, "a");
      B : constant Occurrences := Web.Binding.Query.Lookup (Q, "b");
      C : constant Occurrences := Web.Binding.Query.Lookup (Q, "c");
      D : constant Occurrences := Web.Binding.Query.Lookup (Q, "d");
      G : constant Occurrences := Web.Binding.Query.Lookup (Q, "g");
      H : constant Occurrences := Web.Binding.Query.Lookup (Q, "h");
      Z : constant Occurrences := Web.Binding.Query.Lookup (Q, "z");
   begin
      --  Duplicates preserved in order.
      Assert (Count (A) = 2 and then Card (A) = Present_Multiple, "a twice");
      Assert (Value (A, 1) = "1" and then Value (A, 2) = "2", "a order");
      --  Present-empty is distinct from missing.
      Assert (Count (B) = 1 and then Value (B, 1) = "", "b present empty");
      Assert (Count (Z) = 0 and then Card (Z) = Absent, "z missing");
      --  Percent-decoding and plus-to-space.
      Assert (Value (C, 1) = "x y", "percent decode");
      Assert (Value (D, 1) = "e f", "plus to space");
      --  Malformed escape flagged, not discarded.
      Assert (Count (G) = 1 and then Malformed (G, 1), "malformed percent flagged");
      --  A key with no '=' is present with an empty value.
      Assert (Count (H) = 1 and then Value (H, 1) = "", "bare key present empty");
   end Test_Query;

   procedure Test_Resolution (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Q : constant Web.Binding.Query.Query_Source :=
        Web.Binding.Query.Parse ("a=1&a=2&same=5&same=5&b=&g=%zz");
      A    : constant Occurrences := Web.Binding.Query.Lookup (Q, "a");
      Same : constant Occurrences := Web.Binding.Query.Lookup (Q, "same");
      B    : constant Occurrences := Web.Binding.Query.Lookup (Q, "b");
      G    : constant Occurrences := Web.Binding.Query.Lookup (Q, "g");
      Z    : constant Occurrences := Web.Binding.Query.Lookup (Q, "z");
   begin
      --  Deterministic duplicate handling.
      Assert (Resolve_Scalar (A, Reject, Reject_Empty).State = Resolved_Duplicate,
              "reject duplicate");
      declare
         First : constant Scalar_Resolution :=
           Resolve_Scalar (A, Use_First, Reject_Empty);
         Last  : constant Scalar_Resolution :=
           Resolve_Scalar (A, Use_Last, Reject_Empty);
      begin
         Assert (First.State = Resolved_Value and then Value (A, First.Index) = "1",
                 "use first");
         Assert (Last.State = Resolved_Value and then Value (A, Last.Index) = "2",
                 "use last");
      end;
      Assert
        (Resolve_Scalar (Same, Require_Identical, Reject_Empty).State
           = Resolved_Value, "identical duplicates accepted");
      Assert
        (Resolve_Scalar (A, Require_Identical, Reject_Empty).State
           = Resolved_Duplicate, "differing duplicates rejected");

      --  Empty and missing policies.
      Assert (Resolve_Scalar (B, Reject, Reject_Empty).State = Resolved_Empty,
              "reject empty");
      Assert (Resolve_Scalar (B, Reject, Treat_As_Missing).State = Resolved_Missing,
              "empty as missing");
      Assert (Resolve_Scalar (B, Reject, Allow_And_Decode).State = Resolved_Value,
              "empty allowed");
      Assert (Resolve_Scalar (Z, Reject, Reject_Empty).State = Resolved_Missing,
              "missing");
      Assert (Resolve_Scalar (G, Reject, Reject_Empty).State = Resolved_Malformed,
              "malformed surfaced");
   end Test_Resolution;

   procedure Test_Route (Item : in out Fixture) is
      pragma Unreferenced (Item);
      R : constant Web.Binding.Route.Route_Captures :=
        Web.Binding.Route.Add
          (Web.Binding.Route.Add (Web.Binding.Route.Empty, "id", "42"),
           "slug", "hello");
      Id   : constant Occurrences := Web.Binding.Route.Lookup (R, "id");
      Miss : constant Occurrences := Web.Binding.Route.Lookup (R, "nope");
   begin
      Assert (Count (Id) = 1 and then Value (Id, 1) = "42", "route capture");
      Assert (Count (Miss) = 0, "route miss");
   end Test_Route;

   procedure Test_Headers (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Req : Web.Request.Request_Type := Web.Request.Create ("GET", "/");
   begin
      Web.Request.Set_Header (Req, "X-Test", "hello");
      Assert (Web.Binding.Headers.Has (Req, "X-Test"), "header present");
      declare
         Occ : constant Occurrences :=
           Web.Binding.Headers.Lookup (Req, "X-Test");
      begin
         Assert (Count (Occ) = 1 and then Value (Occ, 1) = "hello", "header value");
      end;
      Assert (Count (Web.Binding.Headers.Lookup (Req, "X-Absent")) = 0,
              "header absent");
   end Test_Headers;

   procedure Test_Cookies (Item : in out Fixture) is
      pragma Unreferenced (Item);
      Jar  : constant Web.Cookie.Cookie_Jar :=
        Web.Cookie.Parse ("session=abc; theme=dark");
      Occ  : constant Occurrences := Web.Binding.Cookies.Lookup (Jar, "session");
      Dupe : constant Web.Cookie.Cookie_Jar := Web.Cookie.Parse ("x=1; x=2");
      Dx   : constant Occurrences := Web.Binding.Cookies.Lookup (Dupe, "x");
   begin
      Assert (Count (Occ) = 1 and then Value (Occ, 1) = "abc", "cookie value");
      --  The occurrence count mirrors the jar's reported duplicate count.
      Assert (Count (Dx) = Natural'Max (1, Web.Cookie.Count (Dupe, "x")),
              "duplicate count mirrored");
      if Count (Dx) > 1 then
         Assert (Resolve_Scalar (Dx, Reject, Reject_Empty).State
                   = Resolved_Duplicate, "duplicate cookie rejected");
      end if;
   end Test_Cookies;

   procedure Test_Mixed (Item : in out Fixture) is
      pragma Unreferenced (Item);
      --  Extraction from two sources with no body access at all.
      R : constant Web.Binding.Route.Route_Captures :=
        Web.Binding.Route.Add (Web.Binding.Route.Empty, "id", "7");
      Q : constant Web.Binding.Query.Query_Source :=
        Web.Binding.Query.Parse ("page=3");
      Id   : constant Scalar_Resolution :=
        Resolve_Scalar (Web.Binding.Route.Lookup (R, "id"), Reject, Reject_Empty);
      Page : constant Scalar_Resolution :=
        Resolve_Scalar (Web.Binding.Query.Lookup (Q, "page"), Reject, Reject_Empty);
   begin
      Assert (Id.State = Resolved_Value, "route id resolved");
      Assert (Page.State = Resolved_Value, "query page resolved");
   end Test_Mixed;

end Web_Binding_Source_Tests;
