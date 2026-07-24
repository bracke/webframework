with Ada.Text_IO;            use Ada.Text_IO;
with Ada.Command_Line;

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

--  Verifies that the bridge maps authorization decisions to guard outcomes
--  fail-closed: an authorized decision proceeds, and any rejection halts with a
--  denial response (403 by default, or a caller-supplied override).
procedure Test_Bridge is
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

   Failures : Natural := 0;

   procedure Check (Cond : Boolean; Label : String) is
   begin
      if Cond then
         Put_Line ("OK   " & Label);
      else
         Put_Line ("FAIL " & Label);
         Failures := Failures + 1;
      end if;
   end Check;

   --  Id helpers: raise on an invalid literal (a test bug, not input).
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

   --  These structures are multi-megabyte; allocate them rather than stacking.
   type Reg_Ref is access Reg.Snapshot;
   type Set_Ref is access Po.Compiled_Set;
   type Req_Ref is access Req.Authorization_Request;
   type Reg_Builder_Ref is access Reg.Builder;
   type Cond_Builder_Ref is access C.Builder;
   type Cond_Tree_Ref is access C.Tree;
   type Pol_Builder_Ref is access Po.Builder;
   type Req_Builder_Ref is access Req.Request_Builder;

   RS : constant Reg_Ref := new Reg.Snapshot;

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

begin
   declare
      RB : constant Reg_Builder_Ref := new Reg.Builder;
      RO : Reg.Register_Outcome;
   begin
      Reg.Register_Attribute
        (RB.all, D.Define_Attribute (Dept, V.Integer_Kind), RO);
      Reg.Seal (RB.all, RS.all);
   end;

   --  1. An allow decision proceeds -- the request reaches the handler.
   declare
      Allow : constant Set_Ref := Build_Set (Ru.Allow_Effect);
      RQ    : constant Req_Ref := Build_Request;
      Dec   : constant Ev.Decision := Ev.Evaluate (Allow.all, RQ.all, RS.all);
      Outcome : constant Web.Guard.Guard_Outcome := WA.Outcome_Of (Dec);
   begin
      Check (Outcome.Decision = Web.Guard.Proceed,
             "an authorized decision proceeds");
   end;

   --  2. A deny decision halts, defaulting to 403 Forbidden.
   declare
      Deny : constant Set_Ref := Build_Set (Ru.Deny_Effect);
      RQ   : constant Req_Ref := Build_Request;
      Dec  : constant Ev.Decision := Ev.Evaluate (Deny.all, RQ.all, RS.all);
      Outcome : constant Web.Guard.Guard_Outcome := WA.Outcome_Of (Dec);
   begin
      Check (Outcome.Decision = Web.Guard.Halt, "a denied decision halts");
      if Outcome.Decision = Web.Guard.Halt then
         Check (Web.Response.Status (Outcome.Response) = 403,
                "a denial defaults to 403 Forbidden");
      end if;
   end;

   --  3. On_Deny overrides the halt response (fail-closed, caller's choice).
   declare
      Deny : constant Set_Ref := Build_Set (Ru.Deny_Effect);
      RQ   : constant Req_Ref := Build_Request;
      Dec  : constant Ev.Decision := Ev.Evaluate (Deny.all, RQ.all, RS.all);
      Outcome : constant Web.Guard.Guard_Outcome :=
        WA.Outcome_Of (Dec, Web.Response.Unauthorized);
   begin
      Check (Outcome.Decision = Web.Guard.Halt
             and then Web.Response.Status (Outcome.Response) = 401,
             "On_Deny overrides the halt response");
   end;

   New_Line;
   Put_Line ("Failures:" & Natural'Image (Failures));
   if Failures > 0 then
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Test_Bridge;
