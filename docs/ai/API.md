# AI API Notes

Use stable DOM ids for patch targets. Register actions explicitly through a
dispatcher instantiation. Keep route rendering and fragment rendering in app
code. Do not add hidden handler discovery or template dependencies to framework
packages.

Use `Web.Server.Run` for plain HTTP/WS and `Web.Server.Run_TLS` with PEM
certificate/key files for native HTTPS/WSS. WebSocket handlers receive
`Web.Connection.Connection_Type`, so live handlers work over both transports.
Use `Web.TLS.Configure_Server` or `Web.Config.TLS_Config` for TLS policy, and
`Web.Server.Reload_TLS` to replace certificate/key/CA/policy for new handshakes.

Configure the instantiated `Web.Live` package with `Web.Live.Configure` or call
`Set_Secure_Cookies` directly before serving production TLS traffic. Session
cookies carry only valid opaque ids; malformed `wf_session` values are ignored.
Use `Start_Cleanup_Task` only when the app wants automatic session expiration,
and stop it during bounded tests or controlled shutdown.

Authorize requests through the guard seam, which the framework core exposes
without depending on `identity` or `authorization`. `Web.Context` holds a
request-scoped **opaque principal** and string attributes; `Web.Guard` runs
guards that return `Proceed` or `Halt (Response)`, and the framework never
inspects why. Attach a global guard with `Use_Guard` and per-route guards with
the guarded `Get`/`Post` overloads; gate live actions with a `Web.Dispatcher`
action guard on `Register`. Build the route guards from
`webframework_authorization.Guarded` over an app decision function, and use
`Web.Response.Forbidden` / `Unauthorized` for denials. The decision function
receives the whole context, so the policy reads facts an upstream guard attached
(the principal's clearance, the session's assurance) without the framework
knowing what they mean. Regenerate the session on privilege change with
`Regenerate_Session` and drop it on logout with `Invalidate_Session`.
