with Web.Request;
with Web.Context;
with Authorization.Evaluator;

--  Authorization policy for the example app.
--
--  Holds the compiled policy set and registry (built once at startup) and
--  answers, for a resolved principal, whether a request is authorized. This is
--  the only decision authority; App.Guards asks it and the webframework_
--  authorization bridge turns the answer into an allow/deny for the route.
package App.Authz is

   package Ev renames Authorization.Evaluator;

   --  Build the registry and policy set. Call once before serving.
   --  @return No return value.
   procedure Initialize;

   --  Decide whether Principal may proceed with Request. The principal's
   --  clearance (role) is read from the request context -- a fact an upstream
   --  guard attached from the session -- so the policy never maps principals to
   --  roles itself. Fail-closed: an unparseable principal, a missing clearance,
   --  or any policy result other than allow denies.
   --  @param Principal Authorization principal id (opaque string).
   --  @param Request The HTTP request being guarded.
   --  @param Context The request context carrying the clearance fact.
   --  @return The authorization decision.
   function Decide
     (Principal : String;
      Request   : Web.Request.Request_Type;
      Context   : Web.Context.Request_Context) return Ev.Decision;

   --  A tables-planned summary of the projects listing. Built by asking the
   --  authorization engine, translating its data scope, and running
   --  Tables.Build_Query_Plan through the tables_authorization bridge. The
   --  presentation the page renders is governed by this plan, not chosen ad hoc.
   type Listing_Plan is record
      Ready              : Boolean := False;
      Scope_Applied      : Boolean := False;
      Mask_Functions     : Boolean := False;
      Authorized_Columns : Natural := 0;
      --  The row restriction the authorization data scope imposes. In this
      --  example the scope authorizes only Alire-tracked projects; the caller
      --  (acting as the backend adapter) applies it, and a production adapter
      --  would instead push the plan's scope constraints into the SQL query.
      Restrict_To_Alire  : Boolean := False;
   end record;

   --  Plan the projects listing for Principal (with the given clearance)
   --  through tables. Fail-closed: an unusable principal or a non-ready plan
   --  yields Ready => False. The clearance governs column presentation.
   --  @param Principal Authorization principal id (opaque string).
   --  @param Clearance The principal's clearance (role).
   --  @return The tables-derived listing plan.
   function Plan_Projects_Listing
     (Principal : String; Clearance : Natural) return Listing_Plan;

end App.Authz;
