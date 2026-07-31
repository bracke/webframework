with Web.Request;
with Web.Context;
with Web.Guard;
with Web.Events;
with App.State;

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

   --  A per-action guard for the live (WebSocket) channel: admits only
   --  administrators. Used to gate a privileged live action; a viewer's
   --  attempt produces no patch.
   function Require_Admin_Action
     (State : App.State.App_State;
      Event : Web.Events.Event) return Boolean;

   --  Set the static bearer token the /metrics scrape guard requires. Call once
   --  at startup. An empty token leaves the endpoint locked (every scrape is
   --  denied) -- fail closed.
   procedure Set_Metrics_Token (Token : String);

   --  Guard the metrics scrape with a static bearer token: a request must send
   --  `Authorization: Bearer <token>` matching the configured token, else 401.
   --  This is the machine-to-machine pattern a Prometheus job uses
   --  (authorization.credentials); a session-cookie guard like Require_App_Access
   --  is wrong here because a scraper has no session. The token is compared in
   --  constant time.
   function Require_Metrics_Token
     (Request : Web.Request.Request_Type;
      Context : in out Web.Context.Request_Context) return Web.Guard.Guard_Outcome;

end App.Guards;
