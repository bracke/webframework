# Release Checklist

Use this checklist before tagging or packaging a release.

## Build Matrix

Run from a clean worktree. All compiler and builder commands must go through
Alire, and `alr exec -- gnatls --version` must report `GNATLS 15.x`:

```sh
alr exec -- gnatls --version
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
cd /tmp/webframework_release_probe
alr build
cd -
cd tools
alr build
./bin/release_smoke
./bin/release_smoke --include-soak
./bin/release_smoke --include-long-soak
./bin/fuzz_corpus
./bin/release_check
```

## API Review

- Public `.ads` subprograms have gnatdoc comments.
- `docs/API_STABILITY.md` reflects the intended stable and advanced surfaces.
- New names follow Ada naming conventions and avoid Ada keywords.
- Core packages do not depend on templates or databases.
- WebSocket transport does not know JSON, sessions, routes, or handlers.
- Browser runtime remains event transport and DOM patch application only.

## Security Review

- `docs/SECURITY.md` reflects current accepted and rejected protocol behavior.
- Default limits are positive and production deployments override them as
  needed.
- `Mode => Production`, non-empty `Allowed_Host`, TLS policy, and
  `Secure_Cookies => True` are used for public deployments.
- `Web.Server.Configuration_Report` is logged at startup.
- A health route using `Web.Server.Health_Response` is registered by the app.
- `Web.Logging.Set_Minimum_Level` and `Web.Logging.Set_Structured` are set by
  deployments that need filtered or key/value logs.
- `tools/bin/fuzz_corpus` passes after parser, WebSocket, protocol, or static
  path changes.
- `tools/bin/release_check` passes before tagging.
- After build artifacts are removed, `tools/bin/release_check --strict-artifacts`
  passes from a clean packaging tree.

## Packaging Review

- Generated directories are absent: `alire/`, `config/`, `obj/`, `bin/`, and
  `lib/`.
- Local database files are absent.
- Sibling dependency build artifacts are not removed or modified by this
  repository's cleanup.
- `README.md`, `docs/BUILD.md`, `docs/API.md`, `docs/ARCHITECTURE.md`,
  `docs/API_STABILITY.md`, `docs/SECURITY.md`, and `docs/CLI.md` are current.

## Example App Review

- `/` renders the reference UI.
- `/health` returns `ok`.
- Counter click produces a patch.
- Profile form validates and patches status.
- Todo add/toggle persists through `../database`.
- Static runtime and CSS are served from `/static`.

## Stress Probe

Run the self-contained soak harness before release candidates:

```sh
cd tools
./bin/soak_harness 16 250
```

Or include a shorter soak in the release smoke program:

```sh
./bin/release_smoke --include-soak
```

Use the longer release-candidate variant before tagging:

```sh
./bin/release_smoke --include-long-soak
```

With an app running locally, use the external stress client:

```sh
cd tools
./bin/stress_harness 127.0.0.1 8080 /health 16 100
```

Use higher client/request counts for deployment-specific capacity checks.
