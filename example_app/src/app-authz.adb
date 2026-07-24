with Ada.Unchecked_Deallocation;
with Ada.Strings.Fixed;
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

   --  Clearance thresholds. A viewer may read; only an administrator may manage
   --  (add/delete) projects or see the sensitive "functions" column.
   Viewer_Clearance : constant Long_Long_Integer := 10;
   Admin_Clearance  : constant Long_Long_Integer := 100;

   --  The clearance an authorization principal carries. A real app resolves the
   --  role from identity; here the principal id encodes it.
   function Clearance_Of (Principal : String) return Long_Long_Integer is
   begin
      if Principal = "d.principal.admin" then
         return Admin_Clearance;
      elsif Principal = "d.principal.viewer" then
         return Viewer_Clearance;
      else
         return 0;
      end if;
   end Clearance_Of;

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

   View_Action    : constant K.Action_Id := Act ("d.action.view");
   App_Type       : constant K.Resource_Type_Id := Rt ("d.type.app");
   Tenant         : constant K.Tenant_Id := Ten ("d.tenant.main");
   Clearance_Attr : constant K.Attribute_Id := Att ("d.attribute.clearance");
   Alire_Attr     : constant K.Attribute_Id := Att ("d.attribute.alire");
   Reason         : constant K.Reason_Id := Rsn ("d.reason.allow");

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

   Snapshot     : Reg_Ref := null;
   View_Policy   : Set_Ref := null;  --  allows clearance >= Viewer_Clearance
   Manage_Policy : Set_Ref := null;  --  allows clearance >= Admin_Clearance

   --  Compile a policy whose single rule allows the action when the principal's
   --  clearance is at least Threshold.
   function Build_Policy (Threshold : Long_Long_Integer) return Set_Ref is
      CB : constant Cond_Builder_Ref := new C.Builder;
      CT : constant Cond_Tree_Ref := new C.Tree;
      PB : constant Pol_Builder_Ref := new Po.Builder;
      CS : constant Set_Ref := new Po.Compiled_Set;
      Cond : C.Node_Ref;
      Oo   : Po.Open_Outcome;
      Ao   : Po.Add_Outcome;
      Stat : Po.Compile_Status;
   begin
      Cond := C.Ordered_Greater_Or_Equal
        (CB.all, Clearance_Attr, V.Of_Integer (Threshold));
      C.Freeze (CB.all, CT.all);
      declare
         R : constant Ru.Rule :=
           Ru.Make (Rul ("d.rule.allow"), Ru.Allow_Effect, Cond, Reason);
      begin
         Po.Start (PB.all, Pst ("d.policyset.app"), 3, CT.all, Po.Deny_Overrides);
         Po.Open_Policy (PB.all, Pol ("d.policy.app"), Tg.Any_Target, Outcome => Oo);
         Po.Add_Rule (PB.all, R, Ao);
         Po.Compile (PB.all, CS.all, Stat);
      end;
      return CS;
   end Build_Policy;

   procedure Initialize is
   begin
      declare
         RB : constant Reg_Builder_Ref := new Reg.Builder;
         RO : Reg.Register_Outcome;
      begin
         Snapshot := new Reg.Snapshot;
         Reg.Register_Attribute
           (RB.all,
            D.Define_Attribute (Clearance_Attr, V.Integer_Kind, Ordered => True),
            RO);
         Reg.Seal (RB.all, Snapshot.all);
      end;

      View_Policy   := Build_Policy (Viewer_Clearance);
      Manage_Policy := Build_Policy (Admin_Clearance);
   end Initialize;

   --  Evaluate the chosen policy for Principal, supplying its clearance fact.
   --  The heavy request builder is released once the (self-contained) decision
   --  is produced.
   function Evaluate_For
     (Principal : String; Policy : Set_Ref) return Ev.Decision
   is
      Actor_Status : Identifier_Status;
      Actor_Id     : constant K.Principal_Id :=
        K.Principal_Ids.Create (Principal, Actor_Status);
      Denied : Ev.Decision;  --  Not_Applicable -> Rejected; fail-closed.
   begin
      if Actor_Status /= Valid_Identifier
        or else Snapshot = null
        or else Policy = null
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
            F.Make (Clearance_Attr, V.Of_Integer (Clearance_Of (Principal)),
                    F.Identity_Issued, 1),
            Fo);
         Req.Finalize (RB.all, RQ.all, Stat);

         Result := Ev.Evaluate (Policy.all, RQ.all, Snapshot.all);
         Free (RB);
         Free (RQ);
         return Result;
      end;
   end Evaluate_For;

   function Decide
     (Principal : String;
      Request   : Web.Request.Request_Type) return Ev.Decision
   is
      --  Managing projects (the /api/projects/* endpoints) needs administrator
      --  clearance; everything else is a view.
      Manage : constant Boolean :=
        Ada.Strings.Fixed.Index (Web.Request.Path (Request), "/api/projects/") > 0;
   begin
      return Evaluate_For
        (Principal, (if Manage then Manage_Policy else View_Policy));
   end Decide;

   function Plan_Projects_Listing (Principal : String) return Listing_Plan is
      use type Tables.Plan_Status;
      use type Tables.Column_Authorization;

      Result   : Listing_Plan;
      Decision : constant Ev.Decision := Evaluate_For (Principal, View_Policy);

      --  Column presentation is resolved per principal: only an administrator
      --  may see the sensitive "functions" column; a viewer gets it masked.
      Functions_Auth : constant Tables.Column_Authorization :=
        (if Clearance_Of (Principal) >= Admin_Clearance
         then Tables.Column_Visible else Tables.Column_Masked);
   begin
      if Snapshot = null or else View_Policy = null then
         return Result;  --  Ready => False; fail-closed.
      end if;

      declare
         SB   : Scope_Builder_Ref := new Sc.Scope_Builder;
         Node : Sc.Node_Ref;
         Cols : Tables.Column_List;
         Ops  : Tables.Operation_Authorization_List;

         RB   : Req_Builder_Ref := new Req.Request_Builder;
         RQ   : Req_Ref := new Req.Authorization_Request;
         Fo   : Req.Add_Fact_Outcome;
         Stat : Req.Validation_Status;
         Actor_Status : Identifier_Status;
         Actor_Id     : constant K.Principal_Id :=
           K.Principal_Ids.Create (Principal, Actor_Status);
      begin
         if Actor_Status /= Valid_Identifier then
            Free (SB);
            Free (RB);
            Free (RQ);
            return Result;
         end if;

         --  Rebuild the request the decision was evaluated for, so To_Result can
         --  thread the principal/tenant handles into the tables result.
         Req.Start
           (RB.all, Pn.Make (Actor_Id, Pn.User_Principal),
            View_Action, App_Type, Evaluation_Time => 1);
         Req.Set_Tenant (RB.all, Tn.Make (Tenant, Tenant));
         Req.Add_Fact
           (RB.all, Req.Principal_Facts,
            F.Make (Clearance_Attr, V.Of_Integer (Clearance_Of (Principal)),
                    F.Identity_Issued, 1),
            Fo);
         Req.Finalize (RB.all, RQ.all, Stat);

         --  Trusted data scope: only Alire-tracked projects. It rides into the
         --  plan (proving the scope survives) and the caller enforces the
         --  matching row restriction.
         Node := Sc.Attribute_Equals (SB.all, Alire_Attr, V.Of_Integer (1));

         Cols.Append (Tables.Column ("id", Tables.Column_Visible, "col-id"));
         Cols.Append (Tables.Column ("name", Tables.Column_Visible, "col-name"));
         Cols.Append (Tables.Column ("status", Tables.Column_Visible, "col-status"));
         Cols.Append (Tables.Column ("type", Tables.Column_Visible, "col-type"));
         Cols.Append (Tables.Column ("functions", Functions_Auth, "col-functions"));

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
            Result.Restrict_To_Alire := Result.Scope_Applied;
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

         Free (SB);
         Free (RB);
         Free (RQ);
      end;

      return Result;
   end Plan_Projects_Listing;

end App.Authz;
