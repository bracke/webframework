# example_app

A small web application that wires the **whole stack** together: the
[`webframework`](..) transport, the [`identity`](../../identity) repository for
authentication and sessions, the [`authorization`](../../authorization) engine
for policy, and [`tables`](../../tables) for authorization-aware data planning —
joined by the two bridges,
[`webframework_authorization`](../../webframework_authorization) (decision → HTTP
guard) and [`tables_authorization`](../../tables_authorization) (decision → query
plan). The add-project endpoint runs the decode → **validate** step through the
standalone [`validation`](../../validation) library.

The point of the example is the **layering**: the framework core depends on
neither `identity` nor `authorization`; it only carries an opaque principal and
runs guards. All the meaning lives in the app packages below.

## What it demonstrates

- **Identity-backed login.** `App.Auth` seeds real identity principals with
  username bindings and enrolled password credentials; authentication runs
  through the repository's password verification — no plaintext password is ever
  stored or compared.
- **Sessions as the source of truth.** Login opens an identity session; every
  request re-validates the session token against the repository, so revocation
  and expiry take effect immediately. The framework cookie carries only an
  opaque id.
- **Role via a request fact.** `App.Auth` resolves a principal's *clearance* at
  login; `App.Guards` carries it (and the session's *assurance*) into the
  request context. `App.Authz` — the single decision authority — reads them as
  facts and never maps principals to roles itself.
- **Deny-by-default authorization.** `App.Authz` compiles a policy set over the
  `authorization` engine. Viewing needs clearance ≥ 10; managing needs ≥ 100.
  Everything fails closed.
- **Step-up assurance.** Managing also demands an *interactive* session. An
  administrator returning on a remembered (low-assurance) cookie may view but
  must re-authenticate to manage — enforced on the HTTP manage routes and on the
  live privileged action alike.
- **Authorization-aware data.** The `/projects` listing is planned through
  `tables`: the authorization data scope (Alire-tracked projects only) survives
  into the query, and the sensitive `functions` column is masked for viewers.
- **Decode → validate.** The add-project API decodes the `x-www-form-urlencoded`
  body with `Web.Binding` (`App.Project_Binding`: the URL-encoded codec over the
  buffered body, per-field scalar resolution), then `App.Project_Validation`
  validates the typed fields with the standalone `validation` library (name
  required + bounded, status required, fields within the column widths). Invalid
  input returns an HTTP 400 with the structured issues as JSON; only valid input
  reaches the database. Validation is headless — it reports issues, and the
  handler chooses the status code. The delete endpoint decodes its `id` as a
  typed integer (`Web.Binding`) and validates it is positive; login validates the
  username's input format only, staying within the credential boundary (it never
  inspects the password or reveals account existence). Covered by `app_http_tests`
  reject-path checks and `app_tests` unit checks.
- **Session-bound CSRF.** Every state-changing HTTP POST (login, logout, project
  add/delete) is protected by `App.Csrf` over the `webframework_forms` bridge:
  each page carries a synchronizer token (an HMAC of the session under a server
  key) in a `<meta>` tag, the page JS echoes it in the POST body, and the handler
  verifies it before acting — a request without a valid token gets `403`. Because
  the token is bound to the session, one issued to another session cannot be
  replayed. `app_http_tests` asserts both the accepted and the `403` paths.
- **Per-action live authorization.** `profile.save` over the WebSocket is gated
  by a dispatcher action guard; a viewer's attempt is rejected before the
  handler runs — presentation and execution are authorized separately.

## Users

| Username | Password | Clearance | May view | May manage |
| --- | --- | --- | --- | --- |
| `admin` | `admin123` | 100 | yes | yes (on an interactive session) |
| `viewer` | `viewer123` | 10 | yes | no |

## Routes

Public: `/login`, `/health`, `/api/login`, `/static/*`. Everything else runs the
global `Resolve_Principal` guard first, then a per-route guard:

| Route | Guard |
| --- | --- |
| `GET /`, `/projects`, `/todo` | `Require_App_Access` (page: anon → `/login`) |
| `POST /api/projects/add`, `/api/projects/delete` | `Require_App_Access_Api` (API: anon → 401, forbidden → 403, low assurance → 403) |
| `WS /ws` upgrade | `Require_App_Access` |
| `profile.save` (live action) | `Require_Admin_Action` (clearance + step-up) |

## Build and run

```sh
alr build
./bin/example_app            # serves on http://localhost:8080
./bin/example_app --port 9000
```

## Tests

```sh
./bin/app_tests        # stack integration: identity auth, sessions, assurance,
                       # role authorization, the tables plan, the live guard
./bin/app_http_tests   # the guard chain over real HTTP requests, incl. the
                       # step-up gate denying a remembered session end to end
```

Both are also driven by the `stack_check` tool (`../stack_check/bin/stack_check`),
the canonical Ada gate that builds and tests the whole stack against the sibling
checkouts.

## Where the pieces live

| Package | Role |
| --- | --- |
| `App.Auth` | credential store + sessions, over the `identity` repository |
| `App.Authz` | the authorization policy (the only decision authority) + the tables plan |
| `App.Guards` | the guard seam: resolve the principal, authorize the route/action |
| `App.Pages` / `App.Projects` | rendering and the scoped data listing |
| `App.State` | per-session UI state (principal, clearance, session token) |

See [`docs/AUTHORIZATION.md`](../docs/AUTHORIZATION.md) for the framework guard
seam these packages build on, and [`docs/ai/APP_STRUCTURE.md`](../docs/ai/APP_STRUCTURE.md)
for the canonical layout.

## License

MIT OR Apache-2.0 WITH LLVM-exception.
