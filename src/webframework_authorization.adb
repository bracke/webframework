with Authorization.Results;

package body Webframework_Authorization is

   package Results renames Authorization.Results;

   function Outcome_Of
     (Decision : Ev.Decision;
      On_Deny  : Web.Response.Response_Type := Web.Response.Forbidden)
      return Web.Guard.Guard_Outcome
   is
   begin
      --  Fail-closed: only an explicit authorization proceeds. A rejection --
      --  a definite deny or an indeterminate "could not decide" -- halts.
      case Ev.Enforcement_Of (Decision) is
         when Results.Authorized | Results.Authorized_With_Requirements =>
            return Web.Guard.Proceed;
         when Results.Rejected =>
            return Web.Guard.Halt (On_Deny);
      end case;
   end Outcome_Of;

   function Guarded
     (Request : Web.Request.Request_Type;
      Context : in out Web.Context.Request_Context)
      return Web.Guard.Guard_Outcome
   is
   begin
      --  No principal means the upstream never authenticated this request; deny
      --  before consulting the policy so an anonymous caller cannot probe it.
      if not Web.Context.Has_Principal (Context) then
         return Web.Guard.Halt (Anonymous);
      end if;

      return Outcome_Of
        (Decide (Web.Context.Principal (Context), Request), Denied);
   end Guarded;

end Webframework_Authorization;
