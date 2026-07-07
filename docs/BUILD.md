# Build And Packaging

The project is source-only. Generated Alire/GPR outputs, local databases, and
Ada compiler byproducts are ignored by `.gitignore`.

## Prerequisites

- Alire for dependency resolution.
- OpenSSL development/runtime libraries for native HTTPS/WSS TLS termination.
- Sibling crates:
  - `../cryptolib` for framework hashing and secure random bytes.
  - `../sshlib` for reusable Ada security/protocol utilities where applicable.
  - `../zlib` for HTTP response gzip/deflate compression.
  - `../template` for the example app template integration.
  - `../database` for the example app persistent todo store.
  - `../project_tools` for `webframework_cli`.

No npm, bundler, transpiler, or frontend framework is used.

Every active Alire manifest pins `gnat_native = "=15.2.1"`. Do not run plain
system GNAT, GPRBuild, GNATprove, GNATdoc, or related `gnat*` tools from
`PATH`; use `alr exec -- ...` or `alr build`. Before building, verify:

```sh
alr exec -- gnatls --version
```

The command must report `GNATLS 15.x`.

The supported security posture and rejected protocol surface are documented in
`docs/SECURITY.md`.

## Build

From the repository root:

```sh
alr build
```

Build tests:

```sh
cd tests
alr build
./bin/tests
```

Build the example app:

```sh
cd example_app
alr build
./bin/example_app
```

The example app accepts runtime options:

```sh
./bin/example_app --host 127.0.0.1 --port 8443 \
  --production --tls --cert cert.pem --key key.pem
```

To log client IPs from a reverse proxy, enable:

```sh
./bin/example_app --use-forwarded-for
```

This option reads the first value of the `x-forwarded-for` header only.
If omitted, the framework uses the socket peer address.

When `--tls`, `--production`, or `--secure-cookies` is set, the app configures
live sessions with secure cookies before serving. The app also calls
`Web.Server.Configure` so production mode hides exception details, Host/Origin
policy is enforced, and request/connection size limits come from `Web.Config`.
It registers `GET /health` with `Web.Server.Health_Response` and logs
`Web.Server.Configuration_Report` at startup.
TLS-enabled apps can call `Web.Server.Run_TLS` with PEM certificate/key files or
with `Web.Config.TLS_Config (Config)` for configured TLS version, cipher, CA,
and client-certificate policy.

If a sibling crate was previously built with a different GNAT version, clean
that crate's generated `obj/` and `lib/` directories before rebuilding the
example app. Mixed `.ali` files from different GNAT versions fail at bind time.

Build the CLI:

```sh
cd webframework_cli
alr build
./bin/webframework check ..
```

Build release/stress tools:

```sh
cd tools
alr build
./bin/release_smoke
./bin/soak_harness 16 250
./bin/fuzz_corpus
./bin/release_check
```

Run `./bin/release_smoke --include-soak` to include a shorter self-contained
server soak in the release smoke pass. Run `./bin/release_smoke
--include-long-soak` for a heavier release-candidate soak.

Run a stress probe against a separately running server:

```sh
./bin/stress_harness 127.0.0.1 8080 /health 16 100
```

## Validation

Recommended release checks:

```sh
alr build
cd tests
alr build
./bin/tests
cd ..
cd example_app
alr build
cd ..
cd webframework_cli
alr build
./bin/webframework check ..
./bin/webframework check ../example_app
./bin/webframework new /tmp/webframework_release_probe
./bin/webframework check /tmp/webframework_release_probe
cd ../tools
alr build
./bin/release_smoke
./bin/release_smoke --include-soak
./bin/release_smoke --include-long-soak
./bin/fuzz_corpus
./bin/release_check
```

## Cleanup

Use `alr exec -- gprclean` or remove ignored build directories. The repository should not
carry generated `obj/`, `bin/`, `lib/`, Alire `config/`, or local `.db` files.

## Logging

`Web.Logging` is the primary control for runtime diagnostics. The example app and
CLI keep console messages styled and forward them through `Web.Logging`:

```ada
Web.Logging.Set_Minimum_Level (Web.Logging.Info_Level);
Web.Logging.Set_Structured (True);
```
