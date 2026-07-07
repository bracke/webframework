# Deployment

This framework is intentionally small. A production deployment should make the
runtime policy explicit in Ada code or command-line configuration.

Deployment templates are provided under `deploy/`:

- `deploy/systemd/example_app.service`
- `deploy/supervisord/example_app.conf`
- `deploy/env/example_app.env`
- `deploy/scripts/run_example_app.sh`

Copy these files, replace placeholder paths, and keep flags/versioned arguments in
`example_app.env` so service definitions stay stable over time.

## Required Production Settings

- Set `Mode => Web.Config.Production`.
- Set a non-empty `Allowed_Host` matching the public host authority.
- Enable TLS with `Web.Server.Run_TLS` or run behind a trusted TLS terminator.
- Set `Secure_Cookies => True` for public HTTPS deployments.
- Keep positive limits for `Max_Request_Size`, `Max_WebSocket_Message`, and
  `Max_Connections`.
- Register a health route that returns `Web.Server.Health_Response`.
- Log `Web.Server.Configuration_Report` at startup.
- Start live-session cleanup with an interval suitable for the application.

## Runtime troubleshooting

- `Address already in use` or bind errors `[98]`:
  - port is already bound by another process;
  - use a different port or stop the previous process;
  - confirm with `ss -ltnp` and then restart.
- `request host/origin is not allowed`:
  - request `Host`/`Origin` does not match configured allowed host policy;
  - for non-default ports, include `:<port>` in the configured authority;
  - restart after updating configuration.

Example:

```sh
alr exec -- ss -ltnp '( sport = :8080 )'
pkill -f example_app
```

For local smoke runs, `example_app` defaults to port `8080`.

## Deployment Templates

Use this pattern for Linux services and restarts:

```ini
EXAMPLE_APP_BIN=/path/to/webframework/example_app/bin/example_app
EXAMPLE_APP_ARGS='--production --host 0.0.0.0 --port 8081 --secure-cookies'
```

`deploy/env/example_app.env` is an editable copy for service arguments.

The launcher script resolves `EXAMPLE_APP_BIN` and appends
`APP_ARGS` (or `EXAMPLE_APP_ARGS`) when starting:

```sh
./deploy/scripts/run_example_app.sh
```

## Automatic Restart on Linux

For long-running production use, run under `systemd` so crashes and exits are
restarted automatically.

Example unit file (`deploy/systemd/example_app.service`):

```ini
[Unit]
Description=Webframework example app
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/webframework
EnvironmentFile=/etc/webframework/example_app.env
ExecStart=/bin/sh -c "${PROJECT_ROOT}/deploy/scripts/run_example_app.sh"
Restart=always
RestartSec=3
StartLimitBurst=10
StartLimitIntervalSec=60
User=webframework
Environment=TERM=xterm-256color
Environment=PROJECT_ROOT=/opt/webframework
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Install:

```sh
sudo cp deploy/systemd/example_app.service /etc/systemd/system/example_app.service
sudo systemctl daemon-reload
sudo systemctl enable --now example_app
```

Useful commands:

```sh
sudo systemctl status example_app
sudo systemctl restart example_app
sudo journalctl -u example_app -f
sudo systemctl stop example_app
```

`Restart=always` also restarts clean shutdowns (`SIGTERM`, etc.). If you want a
service that stays down only on manual stop, change it to `Restart=on-failure` and
use `KillSignal=SIGQUIT`/manual stop for operational maintenance.

For quick local development, you can also use a simple shell loop, but this is not
equivalent to `systemd` supervision:

```sh
while true; do
  ./bin/example_app --production --host 0.0.0.0 --port 8081
  sleep 2
done
```

## Restart Without systemd

If `systemd` is not available, use a dedicated supervisor process:

### supervisord

Add a program entry:

```ini
[program:example_app]
command=/path/to/webframework/deploy/scripts/run_example_app.sh
directory=/path/to/webframework
autostart=true
autorestart=true
startsecs=3
startretries=10
stderr_logfile=/var/log/example_app.err.log
stdout_logfile=/var/log/example_app.out.log
environment=PROJECT_ROOT="/path/to/webframework",APP_ARGS="--production --host 0.0.0.0 --port 8081"
```

`APP_ARGS` lets you pass runtime flags without editing the launcher script.

Useful control commands:

```sh
supervisorctl reread
supervisorctl update
supervisorctl status example_app
supervisorctl restart example_app
```

### runc / runit / daemontools

Use a `run` script that exits on failure and is watched by the service runner:

```sh
#!/bin/sh
exec /path/to/webframework/deploy/scripts/run_example_app.sh
```

Mark as executable and let your init-style supervisor supervise the service.

```sh
chmod +x deploy/scripts/run_example_app.sh
```

### cron-style wrapper

As a fallback on constrained hosts, run with `cron` or `nohup` plus `wait loop`:

```sh
nohup sh -c 'while true; do ./bin/example_app --production --host 0.0.0.0 --port 8081; sleep 2; done' \
  > app.log 2>&1 &
```

For production environments, prefer a real supervisor over cron wrappers so restart
state, logs, and health are observable.

## TLS

Native HTTPS/WSS is configured through `Web.Config.TLS_Config` or direct
`Web.TLS.Configure_Server` use:

```ada
Config.Mode := Web.Config.Production;
Config.Secure_Cookies := True;
Web.Config.Set_Allowed_Host (Config, "example.com");
Web.Server.Configure (Config);
App.Live.Configure (Config);
Web.Server.Run_TLS ("0.0.0.0", 443, Config);
```

If TLS is terminated by a reverse proxy, the proxy must preserve `Host`, reject
oversized request bodies before forwarding, and forward WebSocket upgrades for
the configured live path.

## Compression

Response compression is opt-in through configuration and negotiates `gzip` or
zlib-wrapped `deflate` from `Accept-Encoding`. Disable compression for
deployments that prefer proxy-managed compression:

```ada
Config.Enable_Compression := False;
```

`Cache-Control: no-transform`, already encoded responses, and common binary
static assets are not transformed.

## Sessions

Sessions are cookie-backed and server-side. The cookie contains only an opaque
`wf_session` id. Duplicate session cookies are rejected as ambiguous.

Run cleanup periodically:

```ada
App.Live.Configure (Config);
App.Live.Start_Cleanup_Task (60);
```

## Logging

Use structured logs for service environments:

```ada
Web.Logging.Set_Minimum_Level (Web.Logging.Info_Level);
Web.Logging.Set_Structured (True);
Web.Logging.Info ("event=startup " & Web.Server.Configuration_Report);
```

By design, the sample app and CLI emit their operational messages through
`Web.Logging` first, then print them to the terminal.

`Web.Logging` writes to standard streams:

- `Debug`/`Info`/`Warn` to `stdout`
- `Error` to `stderr`

Structured mode (`Set_Structured`) changes payload formatting but keeps the same
destinations.

At request level, the framework emits one `Info`-level access entry per handled
HTTP request containing `request_id`, `ip`, `method`, `path`, `status`, and
`datetime`.

By default `ip` is the accepted socket peer endpoint. For deployments behind
trusted reverse proxies, enable `x-forwarded-for` through configuration or
`example_app` command line (`--use-forwarded-for`) so logs use the first value
from `X-Forwarded-For`.

If you run the example app from a shell, this means:

```sh
./bin/example_app ... > app.log 2> app.err
./bin/example_app ... > app.log 2>&1   # capture everything in one file
```

`Web.Logging.Set_Minimum_Level` above `Info_Level` filters info-class startup and
help messages automatically.

## Health Checks

Register a lightweight health route:

```ada
function Health
  (Request : Web.Request.Request_Type) return Web.Response.Response_Type
is
   pragma Unreferenced (Request);
begin
   return Web.Server.Health_Response;
end Health;
```

## Release Validation

Before deployment, run:

```sh
cd tools
alr build
./bin/release_smoke --include-example-build --include-soak
./bin/fuzz_corpus
./bin/soak_harness 16 250
```

For a clean packaging tree after build artifacts are removed:

```sh
./bin/release_check --strict-artifacts
```
