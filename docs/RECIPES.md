# Recipes

## Auth/Login

Keep authentication state server-side. Store only an opaque `wf_session` cookie
in the browser.

Recommended shape:

- `App.Store`: persistent user lookup and password verification.
- `App.Auth`: submit handler for `auth.login`.
- `App.State`: current user id or anonymous marker.
- `App.Pages`: full-page rendering based on current session state.

Patch login status with `Set_Text` for plain messages. Do not store roles,
permissions, or profile data in cookies.

## File Downloads And Static Assets

Use `Web.Server.Static` for ordinary static assets:

```ada
Web.Server.Static ("/static", "static");
```

For generated downloads, return a `Web.Response.Response_Type` from a route and
set an application-specific content type. Keep `Content-Length` server-owned;
it is generated during serialization.

## Production TLS

Configure TLS through `Web.Config`:

```ada
Config.Mode := Web.Config.Production;
Config.Secure_Cookies := True;
Web.Config.Set_Allowed_Host (Config, "example.com");
Config.TLS_Minimum_Version := Web.TLS.TLS_1_2;
Web.Server.Configure (Config);
Web.Server.Run_TLS ("0.0.0.0", 443, Config);
```

Use deployment-specific certificate/key files, cipher policy, and client
verification settings where appropriate.

## Reverse Proxy

The framework speaks HTTP/1.1 and WebSocket upgrades. Configure the proxy to:

- forward `Host`;
- forward `Origin` unchanged for WebSocket requests;
- allow `Upgrade: websocket`;
- avoid request-body compression;
- keep `/static` cache policy consistent with the app.

Set `Allowed_Host` to the external host or origin seen by the framework.

## Health And Readiness

Register a route that returns `Web.Server.Health_Response`:

```ada
function Health
  (Request : Web.Request.Request_Type) return Web.Response.Response_Type
is
   pragma Unreferenced (Request);
begin
   return Web.Server.Health_Response;
end Health;
```

Log `Web.Server.Configuration_Report` at startup.

## Server-Sent Events

Push a one-way stream (progress, logs, live updates) to a browser `EventSource`.
Register the route with `Server_Sent_Events`; the handler owns the connection and
sends events until the client disconnects (a `Send` then reports `Ok => False`).
It holds a worker for the stream's lifetime, like a WebSocket.

```ada
procedure Ticks
  (Conn    : in out Web.Connection.Connection_Type;
   Request : Web.Request.Request_Type)
is
   pragma Unreferenced (Request);
   Ok : Boolean;
begin
   loop
      Web.SSE.Send_Event (Conn, "hello", Event => "tick", Ok => Ok);
      exit when not Ok;              --  client disconnected
      Web.SSE.Send_Comment (Conn, "keep-alive", Ok);  --  optional heartbeat
      exit when not Ok;
      --  ... wait for the next update ...
   end loop;
end Ticks;

--  at startup:
Web.Server.Server_Sent_Events ("/events", Ticks'Access);
```

On the client: `new EventSource("/events")` and listen for the `tick` event.
`Web.SSE` splits multi-line data into one `data:` line each and strips CR/LF from
the event name/id, so caller data cannot forge SSE fields.

## REST resources

Register the HTTP verbs and capture path parameters. A `:name` segment matches
one path segment; read it from the request context. Path-parameter routes use
the context-aware form (a plain handler has no context to read from). An exact
route always beats a pattern for the same path.

```ada
function Show_User
  (Request : Web.Request.Request_Type;
   Context : Web.Context.Request_Context) return Web.Response.Response_Type is
begin
   return Web.Response.Text ("user " & Web.Context.Path_Param (Context, "id"));
end Show_User;

--  at startup:
Web.Server.Get    ("/users/:id", Show_User'Access, Require_Auth'Access);
Web.Server.Delete ("/users/:id", Delete_User'Access, Require_Auth'Access);
```

`OPTIONS` is answered automatically with an `Allow` header, and a request to a
known path under an unregistered method returns `405` with `Allow`..

## CORS

Allow cross-origin browser calls. Install a policy once; the server adds the
matching Access-Control-* headers to every response (including the auto-answered
OPTIONS preflight), and lets a request from an allowed origin past its
same-origin gate so a preflight or a cross-origin write is not rejected first.
The route's own CSRF/auth still gates any mutation.

```ada
--  Allow two front-end origins to call the API, with cookies.
Web.Server.Set_CORS
  (Web.CORS.Make
     (Origins     => "https://app.example, https://admin.example",
      Credentials => True,
      Max_Age     => 600));
```

Use `Origins => "*"` for any origin (not combinable with `Credentials => True`,
per the spec -- the matched origin is echoed instead). A request with no `Origin`
(same-origin) is left untouched.

## HTTP rate limiting

Cap how many requests a single client IP may make in a window. Over the limit,
the server answers `429 Too Many Requests` with a `Retry-After` header (seconds
until the window resets) before the request reaches any route.

```ada
--  At most 240 requests per client IP per minute; 0 would disable it.
Web.Server.Set_Rate_Limit (Max_Requests => 240, Per_Seconds => 60);
```

The client key is the forwarded client address when the connection carries one,
otherwise the socket peer. Counting is a fixed-window over a bounded slot table
(oldest entry evicted when full), so memory stays constant regardless of how
many distinct IPs appear. This is the HTTP-request limiter; the WebSocket
message limiter (`Set_Rate_Limit (Count)` on the application instance) is
separate. On a `Web.Application` instance the HTTP limiter is
`Set_HTTP_Rate_Limit (Max_Requests, Per_Seconds)`, named apart from the
WebSocket `Set_Rate_Limit (Count)`.
