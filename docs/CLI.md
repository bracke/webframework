# CLI

`webframework_cli` builds the `webframework` executable. It is an optional
tooling crate and is not a runtime dependency of `webframework`.
It requires the Alire-selected `gnat_native = "=15.2.1"` toolchain and the
sibling `../project_tools` crate.

Commands:

- `webframework new NAME`
- `webframework add page ROOT NAME ROUTE`
- `webframework add feature ROOT NAME`
- `webframework add handler ROOT ACTION`
- `webframework add form ROOT NAME`
- `webframework check [ROOT]`

## Exit Status

Command return codes are stable:

- `0` success.
- `1` execution failure (I/O, generation, or validation errors).
- `2` usage / CLI argument problems.

The executable returns the same values from `webframework` and `webframework
<command>`, so scripts can handle failures without parsing log output.

For restart and service wiring, see `docs/DEPLOYMENT.md`.

Generated apps use explicit Ada files, `webframework.toml`, templates, and
static assets. `webframework new` accepts a plain app name, a nested path, or an
absolute destination path; the Ada project name is derived from the final path
component. The generator writes plain files only; there is no hidden code
generation after creation. The scaffolded application source files are intentionally
heavily commented and explicit so team members can read and modify behavior
without hidden conventions. Generated pages and handlers include local exception
boundaries and fallback responses/patches so application side effects are
contained without taking down the process. The generated `/health` route also
follows the same safe-failure pattern and returns HTTP 500 on unexpected render
failures.

`webframework new` also writes an `alire.toml` pinned to the local framework
checkout so generated apps can be built with `alr build`.
Generated `main.adb` includes explicit runtime configuration for host, port,
production mode, secure cookies, request/WebSocket limits, compression, and
session cleanup:

```sh
./bin/my_app --production --secure-cookies --host example.com --port 8080
```

`webframework check` validates the app manifest, expected directories, the
browser runtime, dispatcher/live wiring, route registration, action handler
registration, duplicate manifest entries, template/static file presence, and
patch targets where they are visible in source or templates. Apps with no
declared actions yet are valid; action registration is required once actions
appear in the manifest.

The checker also emits warnings for production-friendly conventions such as a
`/health` route using `Web.Server.Health_Response`. Warnings do not fail the
check; missing required wiring still returns a nonzero exit status.

`Print_Info` writes to `stdout` and `Print_Error` writes to `stderr`.
`Web.Logging` is invoked first, so you can still filter/route with logging
settings and environment-level stream redirection:

```sh
./bin/my_app > app.log 2> app.err
./bin/my_app > app.log 2>&1
```

Generated sample `main.adb` code now uses logging helpers for user output:

- `Print_Info` calls `Web.Logging.Info` then writes to stdout.
- `Print_Error` calls `Web.Logging.Error` then writes to stderr.

If you want production logging behavior in generated apps, call
`Web.Logging.Set_Minimum_Level` in `main.adb` before command processing.

Generated `main.adb` also accepts:

- `--log-level [debug|info|warn|error]`
- `--log-structured`
- `--use-forwarded-for`

Example:

```sh
./bin/my_app --log-level warn --log-structured --compression-min-size 1024 \
  --use-forwarded-for
```

A repository root may contain a redirect manifest:

```toml
app_root = "example_app"
```

In that case `webframework check .` validates the app under `example_app/`.

Before release, also run the generated-app probe documented in
`docs/RELEASE.md`.
