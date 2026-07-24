with Ada.Unchecked_Deallocation;
with Ada.Containers;
with Ada.Strings.Unbounded;

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
with Authorization.Scopes;

with Tables;
with Tables_Authorization;

package body App.Authz is

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
   package Sc  renames Authorization.Scopes;
   package TA  renames Tables_Authorization;

   use type Identifier_Status;

   --  Id helpers: raise on an invalid literal (a build-time constant, not input).
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

   function Act is new Make_Id (K.Action_Id, K.Action_Ids.Create);
   function Rt  is new Make_Id (K.Resource_Type_Id, K.Resource_Type_Ids.Create);
   function Ten is new Make_Id (K.Tenant_Id, K.Tenant_Ids.Create);
   function Att is new Make_Id (K.Attribute_Id, K.Attribute_Ids.Create);
   function Rsn is new Make_Id (K.Reason_Id, K.Reason_Ids.Create);
   function Rul is new Make_Id (K.Rule_Id, K.Rule_Ids.Create);
   function Pol is new Make_Id (K.Policy_Id, K.Policy_Ids.Create);
   function Pst is new Make_Id (K.Policy_Set_Id, K.Policy_Set_Ids.Create);

   View_Action : constant K.Action_Id := Act ("d.action.view");
   App_Type    : constant K.Resource_Type_Id := Rt ("d.type.app");
   Tenant      : constant K.Tenant_Id := Ten ("d.tenant.main");
   Dept        : constant K.Attribute_Id := Att ("d.attribute.department");
   Reason      : constant K.Reason_Id := Rsn ("d.reason.allow");

   --  These structures are multi-megabyte; allocate rather than stacking.
   type Reg_Ref is access Reg.Snapshot;
   type Set_Ref is access Po.Compiled_Set;
   type Req_Ref is access Req.Authorization_Request;
   type Reg_Builder_Ref is access Reg.Builder;
   type Cond_Builder_Ref is access C.Builder;
   type Cond_Tree_Ref is access C.Tree;
   type Pol_Builder_Ref is access Po.Builder;
   type Req_Builder_Ref is access Req.Request_Builder;
   type Scope_Builder_Ref is access Sc.Scope_Builder;

   procedure Free is new Ada.Unchecked_Deallocation (Req.Request_Builder, Req_Builder_Ref);
   procedure Free is new Ada.Unchecked_Deallocation (Req.Authorization_Request, Req_Ref);
   procedure Free is new Ada.Unchecked_Deallocation (Sc.Scope_Builder, Scope_Builder_Ref);

   Snapshot   : Reg_Ref := null;
   Policy_Set : Set_Ref := null;

   procedure Initialize is
   begin
      declare
         RB : constant Reg_Builder_Ref := new Reg.Builder;
         RO : Reg.Register_Outcome;
      begin
         Snapshot := new Reg.Snapshot;
         Reg.Register_Attribute
           (RB.all, D.Define_Attribute (Dept, V.Integer_Kind), RO);
         Reg.Seal (RB.all, Snapshot.all);
      end;

      declare
         CB : constant Cond_Builder_Ref := new C.Builder;
         CT : constant Cond_Tree_Ref := new C.Tree;
         PB : constant Pol_Builder_Ref := new Po.Builder;
         Root : C.Node_Ref;
         Oo   : Po.Open_Outcome;
         Ao   : Po.Add_Outcome;
         Stat : Po.Compile_Status;
      begin
         Policy_Set := new Po.Compiled_Set;
         Root := C.Always (CB.all);
         C.Freeze (CB.all, CT.all);
         declare
            R : constant Ru.Rule :=
              Ru.Make (Rul ("d.rule.allow"), Ru.Allow_Effect, Root, Reason);
         begin
            Po.Start (PB.all, Pst ("d.policyset.app"), 3, CT.all, Po.Deny_Overrides);
            Po.Open_Policy (PB.all, Pol ("d.policy.app"), Tg.Any_Target, Outcome => Oo);
            Po.Add_Rule (PB.all, R, Ao);
            Po.Compile (PB.all, Policy_Set.all, Stat);
         end;
      end;
   end Initialize;

   function Decide
     (Principal : String;
      Request   : Web.Request.Request_Type) return Ev.Decision
   is
      pragma Unreferenced (Request);

      Actor_Status : Identifier_Status;
      Actor_Id     : constant K.Principal_Id :=
        K.Principal_Ids.Create (Principal, Actor_Status);

      --  A default decision is Not_Applicable, whose enforcement is a
      --  rejection: the fail-closed answer for an unusable principal or an
      --  uninitialized policy.
      Denied : Ev.Decision;
   begin
      if Actor_Status /= Valid_Identifier
        or else Snapshot = null
        or else Policy_Set = null
      then
         return Denied;
      end if;

      declare
         RB     : Req_Builder_Ref := new Req.Request_Builder;
         RQ     : Req_Ref := new Req.Authorization_Request;
         Fo     : Req.Add_Fact_Outcome;
         Stat   : Req.Validation_Status;
         Result : Ev.Decision;
      begin
         Req.Start
           (RB.all, Pn.Make (Actor_Id, Pn.User_Principal),
            View_Action, App_Type, Evaluation_Time => 1);
         Req.Set_Tenant (RB.all, Tn.Make (Tenant, Tenant));
         Req.Add_Fact
           (RB.all, Req.Principal_Facts,
            F.Make (Dept, V.Of_Integer (1), F.Identity_Issued, 1), Fo);
         Req.Finalize (RB.all, RQ.all, Stat);

         Result := Ev.Evaluate (Policy_Set.all, RQ.all, Snapshot.all);

         --  The decision is a self-contained value; release the heavy builders.
         Free (RB);
         Free (RQ);
         return Result;
      end;
   end Decide;

   function Plan_Projects_Listing (Principal : String) return Listing_Plan is
      use type Tables.Plan_Status;
      use type Tables.Column_Authorization;

      Result       : Listing_Plan;
      Actor_Status : Identifier_Status;
      Actor_Id     : constant K.Principal_Id :=
        K.Principal_Ids.Create (Principal, Actor_Status);
   begin
      if Actor_Status /= Valid_Identifier
        or else Snapshot = null
        or else Policy_Set = null
      then
         return Result;  --  Ready => False; fail-closed.
      end if;

      declare
         RB   : Req_Builder_Ref := new Req.Request_Builder;
         RQ   : Req_Ref := new Req.Authorization_Request;
         SB   : Scope_Builder_Ref := new Sc.Scope_Builder;
         Fo   : Req.Add_Fact_Outcome;
         Stat : Req.Validation_Status;
         Decision : Ev.Decision;
         Node : Sc.Node_Ref;
         Cols : Tables.Column_List;
         Ops  : Tables.Operation_Authorization_List;
      begin
         --  Evaluate the decision for this principal.
         Req.Start
           (RB.all, Pn.Make (Actor_Id, Pn.User_Principal),
            View_Action, App_Type, Evaluation_Time => 1);
         Req.Set_Tenant (RB.all, Tn.Make (Tenant, Tenant));
         Req.Add_Fact
           (RB.all, Req.Principal_Facts,
            F.Make (Dept, V.Of_Integer (1), F.Identity_Issued, 1), Fo);
         Req.Finalize (RB.all, RQ.all, Stat);
         Decision := Ev.Evaluate (Policy_Set.all, RQ.all, Snapshot.all);

         --  Trusted data scope: rows in this tenant. A real backend adapter
         --  applies these constraints to the SQL query; here they ride into the
         --  plan and prove the scope survives (Contains_Authorization_Scope).
         Node := Sc.Tenant_Equals (SB.all, Tenant);

         --  Resolved column presentation. "functions" is masked to show the
         --  tables plan -- not the handler -- governing what a cell may show; a
         --  real policy resolves these per principal.
         Cols.Append (Tables.Column ("id", Tables.Column_Visible, "col-id"));
         Cols.Append (Tables.Column ("name", Tables.Column_Visible, "col-name"));
         Cols.Append (Tables.Column ("status", Tables.Column_Visible, "col-status"));
         Cols.Append (Tables.Column ("type", Tables.Column_Visible, "col-type"));
         Cols.Append
           (Tables.Column ("functions", Tables.Column_Masked, "col-functions"));

         for Op in Tables.Operation_Kind loop
            Ops.Append
              (Tables.Operation_Permission
                 (Op, True, "op-" & Tables.Operation_Kind'Image (Op)));
         end loop;

         declare
            TS : constant Sc.Trusted_Scope :=
              Sc.Authorize (SB.all, [(Sc.Grant_Scope, Node)]);
            Auth_Result : constant Tables.Authorization_Result :=
              TA.To_Result
                (Decision, RQ.all,
                 Scope                  => TA.Translate_Scope (TS),
                 Scope_Fingerprint      => "projects-scope",
                 Capability_Fingerprint => "projects-cap",
                 Columns                => Cols,
                 Operations             => Ops,
                 Resource_Context_Fingerprint => "projects-resource");
            User : Tables.User_State;
            Plan : constant Tables.Query_Plan :=
              Tables.Build_Query_Plan
                (Auth_Result,
                 Tables.Application_Constraint_Vectors.Empty_Vector, User);
         begin
            Result.Ready := Tables.Query_Status (Plan) = Tables.Plan_Ready;
            Result.Scope_Applied := Tables.Contains_Authorization_Scope (Plan);
            Result.Authorized_Columns :=
              Natural (Tables.Query_Columns (Plan).Length);
            for Col of Tables.Query_Columns (Plan) loop
               if Ada.Strings.Unbounded.To_String (Col.Name) = "functions"
                 and then Col.Authorization = Tables.Column_Masked
               then
                  Result.Mask_Functions := True;
               end if;
            end loop;
         end;

         Free (RB);
         Free (RQ);
         Free (SB);
      end;

      return Result;
   end Plan_Projects_Listing;

end App.Authz;
