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
