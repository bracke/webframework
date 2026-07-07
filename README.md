# webframework

Ada-first server-driven web framework.

The server owns routes, sessions, typed per-session state, browser event
dispatch, and DOM patch generation. The browser uses normal HTML/CSS plus a
small dependency-free `static/webframework.js` runtime for WebSocket event
transport and patch application.

## Scope

- Ada 2022 core.
- Direct `GNAT.Sockets` HTTP/1.1 and WebSocket handling.
- Cookie-backed server-side sessions.
- Explicit DOM patches, no virtual DOM.
- No npm, bundlers, transpilers, or frontend framework.
- Optional HTTPS/WSS through the framework TLS binding.
- Optional response gzip/deflate through the sibling `../zlib` crate.

The framework core is template-engine agnostic and database-free. The example
app demonstrates integration with sibling `../template` and `../database`
crates.

## Crates

- `webframework`: core library.
- `tests`: AUnit suite.
- `example_app`: reference application with routes, live updates, forms,
  templates, and persistence.
- `webframework_cli`: optional scaffolding and app checker.

## Build

Prerequisites:

- Alire.
- Sibling crates: `../cryptolib`, `../sshlib`, `../zlib`, `../template`,
  `../database`, and `../project_tools`.

This repository enforces GNAT 15 through Alire. Every active manifest pins:

```toml
[[depends-on]]
gnat_native = "=15.2.1"
```

Do not run plain system GNAT, GPRBuild, GNATprove, GNATdoc, or related `gnat*`
tools from `PATH`. Build, test, and inspect the compiler through Alire so the
pinned toolchain is selected:

```sh
alr exec -- gnatls --version
```

The compiler version command must report `GNATLS 15.x`.

Build the library:

```sh
alr build
```

Run tests:

```sh
cd tests
alr build
./bin/tests
```

Run the example app:

```sh
cd example_app
alr build
./bin/example_app --host 127.0.0.1 --port 8080
```

### 60-second startup

From a fresh clone:

```sh
cd example_app
alr build
./bin/example_app
```

Then open `http://127.0.0.1:8080/`.

For production-style restarts, use the templates under `deploy/` and set values in
`deploy/env/example_app.env`.

### Start and route

The server wiring pattern is:

- `App.Runtime.Get (path, handler)` for full-page GET routes.
- `App.Runtime.WebSocket (path, handler)` for websocket upgrade handling.
- `App.Runtime.Static ("/static", dir)` for `/static/*` assets.

Example:

```ada
App.Runtime.Get ("/", App.Pages.Home'Access);
App.Runtime.Get ("/health", App.Pages.Health'Access);
App.Runtime.WebSocket ("/ws", App.Runtime.WebSocket_Handler'Access);
App.Runtime.Static ("/static", "example_app/static");
App.Runtime.Configure (Web.Config.Default_Config);
App.Runtime.Run ("127.0.0.1", 8080);
```

In the example app:

- `GET /` renders the page and returns `Set-Cookie: wf_session=...`.
  - `GET /health` returns a simple readiness endpoint.
  - `GET /ws` with websocket headers opens the live channel.
  - `GET /static/style.css` returns files from `example_app/static`.

### Logging

Both framework and example application messages are routed through `Web.Logging`
before being printed. Use minimum level filtering to control what is emitted:

```ada
Web.Logging.Set_Minimum_Level (Web.Logging.Info_Level);
Web.Logging.Set_Structured (True);
```

When a message is below the minimum level, the logging helper suppresses it.
Terminal styling is preserved in the user-facing wrappers in the sample
apps.

`Web.Logging` writes:

- `Debug`, `Info`, `Warn` → `stdout`
- `Error` → `stderr`

Request access logs include:

- `request_id`
- `ip`
- `method`
- `path`
- `status`
- `datetime` (UTC)

The example app's `Log_Message`/`Log_Error` helpers also print via
`Terminal_Styles` and thus still emit to the same streams.

### Troubleshooting

`[98] Address already in use` means the bind port is already taken.

Use a different port:

```sh
./bin/example_app --host 127.0.0.1 --port 8081
```

Or find and stop the process using the port:

```sh
alr exec -- ss -ltnp '( sport = :8080 )'
pkill -f example_app
```

If another service owns the port, move your app to a free port in command line
arguments or deployment settings.

If you see:

```text
request host/origin is not allowed
```

the request `Host` authority does not match the configured allowed host.
For non-default ports, the authority includes `:<port>`.

For automatic process restarts on Linux, see:
`docs/DEPLOYMENT.md` → “Automatic Restart on Linux” and
“Restart Without systemd”.

Process exit codes:

- `0`: startup completed normally.
- `1`: framework/runtime error.
- `2`: command argument or usage error.
- `3`: startup initialization failure (for example database/config errors).

For packaged service examples and sample environment values, also check:
`deploy/README.md`.

By default, the example app sets `Allowed_Host` to:
- `127.0.0.1` when using port `80` or `443`,
- `127.0.0.1:8081` (for example) when using another port.

### Recovery model

The server is request/socket resilient:

- A malformed HTTP request is handled as a per-request error response.
- Handler exceptions in routes, dispatcher actions, and websocket event processing are
  logged and do not terminate the server.
- A broken websocket session is closed without affecting other active sessions.

For long-running app-side side effects (for example database writes), add local
error handling in your handlers and return explicit fallback patches when needed.

The example app follows that guidance in two places:

- `App.Todo.Add` catches persistence/render errors and returns a user-facing
  status patch when the todo write or list render fails.
- `App.Pages.Home` catches template/render failures and returns a 500 response
  instead of crashing the connection.

Run the CLI checks:

```sh
cd webframework_cli
alr build
./bin/webframework check ..
./bin/webframework check ../example_app
```

## Example App Operations

Useful runtime options:

```sh
./bin/example_app --production --secure-cookies \
  --max-request-size 1048576 --max-connections 1024 \
  --compression-min-size 256
```

Logging can be controlled on startup:

```sh
./bin/example_app --log-level warn --log-structured
```

TLS:

```sh
./bin/example_app --tls --cert cert.pem --key key.pem --production
```

The example app exposes `GET /health` and logs
`Web.Server.Configuration_Report` at startup.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Documentation Index](docs/README.md)
- [Public API](docs/API.md)
- [API Stability](docs/API_STABILITY.md)
- [Tutorial](docs/TUTORIAL.md)
- [API Examples](docs/EXAMPLES.md)
- [Recipes](docs/RECIPES.md)
- [Build And Packaging](docs/BUILD.md)
- [Security](docs/SECURITY.md)
- [Deployment](docs/DEPLOYMENT.md)
- [CLI](docs/CLI.md)
- [Release Checklist](docs/RELEASE.md)
- [AI App Structure](docs/ai/APP_STRUCTURE.md)

## Release Tools

The `tools` crate contains Ada-only operational tools:

- `release_smoke`: runs the repeatable build/check/generated-app verification.
- `release_check`: checks release metadata and clean packaging expectations.
- `fuzz_corpus`: runs deterministic hostile parser/protocol corpus checks.
- `stress_harness`: sends concurrent HTTP GET requests to a running app.
