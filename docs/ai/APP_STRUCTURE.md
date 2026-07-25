# Canonical App Structure

Use:

- `src/main.adb`
- `src/app-state.ads`
- `src/app-dispatcher.ads`
- `src/app-live.ads`
- `src/app-pages.ads` and `src/app-pages.adb`
- `src/app-counter.ads` and `src/app-counter.adb`
- `src/app-profile.ads` and `src/app-profile.adb`
- `src/app-database.ads` and `src/app-database.adb`
- `src/app-store.ads` and `src/app-store.adb`
- `templates/`
- `static/`

## Authorization layer (optional)

An app that authenticates users and authorizes requests adds a thin layer that
the framework core knows nothing about. The framework only carries an **opaque
principal** on the request context and runs guards; it never interprets who the
principal is or why a guard halts. Keep the meaning in app code:

- `src/app-auth.ads` / `.adb` — the credential store and sessions, backed by the
  [`identity`](../../../identity) repository. Turns a username/password into an
  opaque principal id and issues/validates/revokes sessions. Also surfaces the
  facts the policy needs (the principal's clearance, the session's assurance).
- `src/app-authz.ads` / `.adb` — the authorization policy, over the
  [`authorization`](../../../authorization) engine. The **only** decision
  authority. Reads its facts from the request context (never maps principals to
  roles itself) and answers deny-by-default.
- `src/app-guards.ads` / `.adb` — the guard seam. A global guard resolves the
  session cookie into the context's principal plus derived facts; per-route
  guards, built from the [`webframework_authorization`](../../../webframework_authorization)
  bridge over `App.Authz`, turn the decision into proceed / 403 / login-redirect.

The engine's data scope and column masking reach a listing through the
[`tables`](../../../tables) plan via the
[`tables_authorization`](../../../tables_authorization) bridge, assembled in
`App.Authz` and applied by `App.Pages` / `App.Projects`.

See `example_app/` for the full chain wired end to end.
