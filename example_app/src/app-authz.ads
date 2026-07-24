with Web.Request;
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

   --  Decide whether Principal may proceed with Request. Fail-closed: an
   --  unparseable principal, or any policy result other than allow, denies.
   --  @param Principal Authorization principal id (opaque string).
   --  @param Request The HTTP request being guarded.
   --  @return The authorization decision.
   function Decide
     (Principal : String;
      Request   : Web.Request.Request_Type) return Ev.Decision;

end App.Authz;
