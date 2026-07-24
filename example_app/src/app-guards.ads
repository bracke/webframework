with Web.Request;
with Web.Context;
with Web.Guard;

--  Route guards wiring the stack together for the example app.
--
--  Resolve_Principal is a global guard that turns the session cookie into the
--  session's stored principal on the request context. Require_App_Access is a
--  per-route guard, built from the webframework_authorization bridge over
--  App.Authz: it denies anonymous requests (redirect to /login) and asks the
--  authorization engine about everyone else.
package App.Guards is

   --  Populate the context with the session's principal (if any). Always
   --  proceeds -- it only enriches the context; the authorization guard decides.
   function Resolve_Principal
     (Request : Web.Request.Request_Type;
      Context : in out Web.Context.Request_Context) return Web.Guard.Guard_Outcome;

   --  Authorize the request against the app policy. Anonymous callers are sent
   --  to /login; authenticated-but-forbidden callers get 403; allowed callers
   --  proceed to the handler. For full-page routes and WebSocket upgrades.
   function Require_App_Access
     (Request : Web.Request.Request_Type;
      Context : in out Web.Context.Request_Context) return Web.Guard.Guard_Outcome;

   --  Same policy, but for API endpoints (fetch/XHR): anonymous callers get 401
   --  and forbidden callers 403, rather than an HTML login redirect.
   function Require_App_Access_Api
     (Request : Web.Request.Request_Type;
      Context : in out Web.Context.Request_Context) return Web.Guard.Guard_Outcome;

end App.Guards;
