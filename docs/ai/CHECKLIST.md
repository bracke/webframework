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

Authorization (apps that authenticate and authorize):

- Framework core depends on neither `identity` nor `authorization`; it carries
  an opaque principal it never interprets. The meaning lives only in app code
  (`App.Auth`, `App.Authz`, `App.Guards`).
- Authorization is deny-by-default and fail-closed: a deny, a not-applicable, an
  indeterminate result, a missing fact, and an unparseable principal all deny.
- The policy is the single decision authority; the guard asks it and enforces
  the answer. Presentation (what a page renders) is never authority — every
  privileged execution re-authorizes.
- The policy reads its facts (clearance, assurance) from the request context an
  upstream guard attached; it does not map principals to roles itself.
- Sessions validate against the `identity` repository on every request, so
  revocation and expiry take effect at once; a stored principal is trusted only
  while its session is live.
- Privileged actions demand a step-up (an interactive-or-stronger assurance),
  not merely a sufficient clearance.
- Caches and plans never cross authorization contexts: principal, tenant and
  security-revision handles are threaded into every `tables` result.
- Passwords are never stored or compared in the clear; authentication runs
  through the `identity` repository's verification.

Request binding (apps that decode typed input — see `BINDING.md`):

- Decode with `Web.Binding.*`, never ad-hoc string parsing; a malformed value is
  a structured error, never an exception.
- Binding is syntactic only: no validation, auth, storage or rendering in
  decoders or descriptors; semantic rules live in the Validation seam.
- Credential fields use Secret_Value; secrets are never retained or logged.
- Duplicates are rejected by default; missing, empty and JSON null stay distinct;
  bounds apply to every attacker-controlled dimension.
- Body codec is chosen from Content-Type via the immutable registry; no sniffing;
  the body has one owner; uploads stream and abort on failure.
