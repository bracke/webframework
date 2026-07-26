with Web.Guard;
with Web.Context;
with Web.Request;
with Web.Response;
with Authorization.Evaluator;

--  Bridge from the authorization engine to the webframework guard seam.
--
--  webframework's guard mechanism (Web.Guard) is deliberately decoupled: a
--  guard returns Proceed or Halt and the framework never inspects the reason.
--  This crate is the adapter that turns an authorization decision into that
--  outcome, fail-closed, so an application can gate routes with the
--  authorization engine without the framework core depending on it. It is the
--  only unit that depends on both libraries; webframework depends on neither
--  authorization nor identity.
package Webframework_Authorization is

   package Ev renames Authorization.Evaluator;

   --  Map an authorization decision to a guard outcome, fail-closed. Only an
   --  authorized decision -- with or without requirements -- proceeds; every
   --  other enforcement outcome (a denial, or an indeterminate rejection) halts
   --  the request with On_Deny, which defaults to 403 Forbidden.
   function Outcome_Of
     (Decision : Ev.Decision;
      On_Deny  : Web.Response.Response_Type := Web.Response.Forbidden)
      return Web.Guard.Guard_Outcome;

   --  Build a route guard from an application decision function. The guard
   --  reads the principal the upstream resolved into the context: when the
   --  context is anonymous it halts with Anonymous without consulting the
   --  policy, otherwise it asks Decide for a decision and maps it fail-closed
   --  with Denied. Decide also receives the context, so it can read derived
   --  facts an upstream guard attached (a role, tenant, or assurance) rather
   --  than re-deriving them from the principal. Instantiate once per protected
   --  resource and register the instance's 'Access as a Web.Guard.Guard_Access.
   generic
      Denied    : Web.Response.Response_Type;
      Anonymous : Web.Response.Response_Type;
      with function Decide
        (Principal : String;
         Request   : Web.Request.Request_Type;
         Context   : Web.Context.Request_Context) return Ev.Decision;
   function Guarded
     (Request : Web.Request.Request_Type;
      Context : in out Web.Context.Request_Context)
      return Web.Guard.Guard_Outcome;

end Webframework_Authorization;
