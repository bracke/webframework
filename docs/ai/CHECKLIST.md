# Checklist

- Every action is registered once.
- Every patch target has a stable DOM id.
- `static/webframework.js` exists.
- App state remains per-session UI state.
- Persistent data stays in app store/database packages.
- Framework packages do not depend on templates or databases.
- Framework hashes and random session ids use `../cryptolib`.
- Framework reusable security buffers use exported `../sshlib` APIs where they
  fit.
- HTTP response compression uses `../zlib`; request body compression and
  WebSocket compression/extensions remain rejected.
- Origin/Host policy uses exact origin or authority matches, never substring
  allow-list checks.
- Production live sessions enable `Secure_Cookies` through `Web.Live.Configure`
  or `Set_Secure_Cookies`.
- `wf_session` values are opaque framework ids only; app code does not store
  user data in cookies.
- Long-running apps call `Cleanup_Sessions` or start `Start_Cleanup_Task` with
  a bounded shutdown path.
- Hostile-input tests cover malformed or duplicate HTTP headers, oversized
  requests, static traversal/read failures, invalid registrations, and rejected
  WebSocket frame types.
- Native browser HTTPS/WSS uses `Web.Server.Run_TLS` and `Web.TLS`.
- Production TLS policy uses `Web.TLS.Configure_Server`, explicit version and
  cipher settings where needed, and `Reload_TLS` for certificate replacement.
