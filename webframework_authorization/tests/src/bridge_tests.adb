with AUnit.Assertions; use AUnit.Assertions;
with AUnit.Test_Caller;

with Authorization.Identifiers;          use Authorization.Identifiers;
with Authorization.Identifiers.Kinds;
with Authorization.Definitions;
with Authorization.Definitions.Registry;
with Authorization.Conditions;
with Authorization.Rules;
with Authorization.Policies;
with Authorization.Targets;
with Authorization.Requests;
with Authorization.Principals;
with Authorization.Tenancy;
with Authorization.Facts;
with Authorization.Values;
with Authorization.Evaluator;

with Web.Guard;
with Web.Response;
with Webframework_Authorization;

--  Verifies the authorization -> webframework guard bridge is fail-closed: an
--  authorized decision proceeds; a denial halts (403 by default, or a caller
--  override).
package body Bridge_Tests is

   package K   renames Authorization.Identifiers.Kinds;
   package D   renames Authorization.Definitions;
   package Reg renames Authorization.Definitions.Registry;
   package C   renames Authorization.Conditions;
   package Ru  renames Authorization.Rules;
   package Po  renames Authorization.Policies;
   package Tg  renames Authorization.Targets;
   package Req renames Authorization.Requests;
   package Pn  renames Authorization.Principals;
   package Tn  renames Authorization.Tenancy;
   package F   renames Authorization.Facts;
   package V   renames Authorization.Values;
   package Ev  renames Authorization.Evaluator;
   package WA  renames Webframework_Authorization;

   use type Web.Guard.Guard_Decision;

   generic
      type Id is private;
      with function Create (S : String; St : out Identifier_Status) return Id;
   function Make_Id (S : String) return Id;
   function Make_Id (S : String) return Id is
      St : Identifier_Status;
      X  : constant Id := Create (S, St);
   begin
      if St /= Valid_Identifier then
         raise Program_Error;
      end if;
      return X;
   end Make_Id;

   function Prn is new Make_Id (K.Principal_Id, K.Principal_Ids.Create);
   function Act is new Make_Id (K.Action_Id, K.Action_Ids.Create);
   function Rt  is new Make_Id (K.Resource_Type_Id, K.Resource_Type_Ids.Create);
   function Ten is new Make_Id (K.Tenant_Id, K.Tenant_Ids.Create);
   function Att is new Make_Id (K.Attribute_Id, K.Attribute_Ids.Create);
   function Rsn is new Make_Id (K.Reason_Id, K.Reason_Ids.Create);
   function Rul is new Make_Id (K.Rule_Id, K.Rule_Ids.Create);
   function Pol is new Make_Id (K.Policy_Id, K.Policy_Ids.Create);
   function Pst is new Make_Id (K.Policy_Set_Id, K.Policy_Set_Ids.Create);

   Alice  : constant K.Principal_Id := Prn ("d.principal.alice");
   Read   : constant K.Action_Id := Act ("d.action.read");
   Doc    : constant K.Resource_Type_Id := Rt ("d.type.document");
   Acme   : constant K.Tenant_Id := Ten ("d.tenant.acme");
   Dept   : constant K.Attribute_Id := Att ("d.attribute.department");
   Reason : constant K.Reason_Id := Rsn ("d.reason.ok");

   type Reg_Ref is access Reg.Snapshot;
   type Set_Ref is access Po.Compiled_Set;
   type Req_Ref is access Req.Authorization_Request;
   type Reg_Builder_Ref is access Reg.Builder;
   type Cond_Builder_Ref is access C.Builder;
   type Cond_Tree_Ref is access C.Tree;
   type Pol_Builder_Ref is access Po.Builder;
   type Req_Builder_Ref is access Req.Request_Builder;

   function Fresh_Registry return Reg_Ref is
      RS : constant Reg_Ref := new Reg.Snapshot;
      RB : constant Reg_Builder_Ref := new Reg.Builder;
      RO : Reg.Register_Outcome;
   begin
      Reg.Register_Attribute
        (RB.all, D.Define_Attribute (Dept, V.Integer_Kind), RO);
      Reg.Seal (RB.all, RS.all);
      return RS;
   end Fresh_Registry;

   --  A compiled policy set whose single rule has the given effect.
   function Build_Set (Effect : Ru.Effect) return Set_Ref is
      CB : constant Cond_Builder_Ref := new C.Builder;
      CT : constant Cond_Tree_Ref := new C.Tree;
      PB : constant Pol_Builder_Ref := new Po.Builder;
      CS : constant Set_Ref := new Po.Compiled_Set;
      Root : C.Node_Ref;
      Oo : Po.Open_Outcome;
      Ao : Po.Add_Outcome;
      Stat : Po.Compile_Status;
   begin
      Root := C.Always (CB.all);
      C.Freeze (CB.all, CT.all);
      declare
         R : constant Ru.Rule := Ru.Make (Rul ("d.rule.only"), Effect, Root, Reason);
      begin
         Po.Start (PB.all, Pst ("d.policyset.main"), 3, CT.all, Po.Deny_Overrides);
         Po.Open_Policy (PB.all, Pol ("d.policy.only"), Tg.Any_Target, Outcome => Oo);
         Po.Add_Rule (PB.all, R, Ao);
         Po.Compile (PB.all, CS.all, Stat);
      end;
      return CS;
   end Build_Set;

   function Build_Request return Req_Ref is
      RB : constant Req_Builder_Ref := new Req.Request_Builder;
      RQ : constant Req_Ref := new Req.Authorization_Request;
      Fo : Req.Add_Fact_Outcome;
      Stat : Req.Validation_Status;
   begin
      Req.Start (RB.all, Pn.Make (Alice, Pn.User_Principal), Read, Doc,
                 Evaluation_Time => 1);
      Req.Set_Tenant (RB.all, Tn.Make (Acme, Acme));
      Req.Add_Fact (RB.all, Req.Principal_Facts,
        F.Make (Dept, V.Of_Integer (2), F.Identity_Issued, 1), Fo);
      Req.Finalize (RB.all, RQ.all, Stat);
      return RQ;
   end Build_Request;

   function Decide (Effect : Ru.Effect) return Ev.Decision is
      RS : constant Reg_Ref := Fresh_Registry;
      S  : constant Set_Ref := Build_Set (Effect);
      RQ : constant Req_Ref := Build_Request;
   begin
      return Ev.Evaluate (S.all, RQ.all, RS.all);
   end Decide;

   procedure Test_Authorized_Proceeds (T : in out Fixture) is
      pragma Unreferenced (T);
      Outcome : constant Web.Guard.Guard_Outcome :=
        WA.Outcome_Of (Decide (Ru.Allow_Effect));
   begin
      Assert (Outcome.Decision = Web.Guard.Proceed,
              "an authorized decision proceeds");
   end Test_Authorized_Proceeds;

   procedure Test_Denied_Halts (T : in out Fixture) is
      pragma Unreferenced (T);
      Outcome : constant Web.Guard.Guard_Outcome :=
        WA.Outcome_Of (Decide (Ru.Deny_Effect));
   begin
      Assert (Outcome.Decision = Web.Guard.Halt, "a denied decision halts");
      if Outcome.Decision = Web.Guard.Halt then
         Assert (Web.Response.Status (Outcome.Response) = 403,
                 "a denial defaults to 403 Forbidden");
      end if;
   end Test_Denied_Halts;

   procedure Test_On_Deny_Override (T : in out Fixture) is
      pragma Unreferenced (T);
      Outcome : constant Web.Guard.Guard_Outcome :=
        WA.Outcome_Of (Decide (Ru.Deny_Effect), Web.Response.Unauthorized);
   begin
      Assert (Outcome.Decision = Web.Guard.Halt
              and then Web.Response.Status (Outcome.Response) = 401,
              "On_Deny overrides the halt response (fail-closed, caller's choice)");
   end Test_On_Deny_Override;

   package Caller is new AUnit.Test_Caller (Fixture);

   procedure Add_Tests (Suite : AUnit.Test_Suites.Access_Test_Suite) is
   begin
      Suite.Add_Test
        (Caller.Create ("Authz: authorized proceeds", Test_Authorized_Proceeds'Access));
      Suite.Add_Test
        (Caller.Create ("Authz: denied halts (403)", Test_Denied_Halts'Access));
      Suite.Add_Test
        (Caller.Create ("Authz: On_Deny override", Test_On_Deny_Override'Access));
   end Add_Tests;

end Bridge_Tests;
