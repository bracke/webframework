# Build And Packaging

The project is source-only. Generated Alire/GPR outputs, local databases, and
Ada compiler byproducts are ignored by `.gitignore`.

## Prerequisites

- GNAT with Ada 2022 support.
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

When `--tls`, `--production`, or `--secure-cookies` is set, the app configures
live sessions with secure cookies before serving. The app also calls
`Web.Server.Configure` so production mode hides exception details, Host/Origin
policy is enforced, and request size limits come from `Web.Config`.
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
```

## Cleanup

Use `gprclean` or remove ignored build directories. The repository should not
carry generated `obj/`, `bin/`, `lib/`, Alire `config/`, or local `.db` files.
