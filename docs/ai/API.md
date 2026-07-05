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
