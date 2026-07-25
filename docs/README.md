# Documentation Index

## Getting Started

- [README](../README.md) — repository overview and quick start.
- [Build and Packaging](BUILD.md) — how to compile and prepare artifacts.
- [Tutorial](TUTORIAL.md) — first page route, websocket action wiring, and
  template integration.

## Runtime

- [Architecture](ARCHITECTURE.md) — architecture and request/event flow.
- [Authorization & the guard seam](AUTHORIZATION.md) — how identity and
  authorization gate routes and the WebSocket upgrade without the framework
  core depending on either.
- [API](API.md) — package-level API and boundaries.
- [Request Binding & Input Decoding](BINDING.md) — the `Web.Binding.*` subsystem:
  typed decoding of route/query/header/cookie and JSON/URL-encoded/multipart
  bodies into Ada values, with exact paths, streaming codecs, and the Forms /
  Validation / Uploads / Identity / Authorization seams.
- [Deployment](DEPLOYMENT.md) — systemd/supervisord examples, restart behavior,
  and startup checks.
- [Security](SECURITY.md) — host/origin policy, websocket, and session
  hardening.

## Example & CLI

- [Examples](EXAMPLES.md) — end-to-end route and handler sample snippets.
- [CLI](CLI.md) — scaffold/check commands and exit status conventions.
- [Recipes](RECIPES.md) — practical implementation patterns.

## Stability

- [API Stability](API_STABILITY.md)
- AI/CLI compatibility guidance is in `docs/ai/APP_STRUCTURE.md` and
  `docs/ai/CHECKLIST.md`.

## Release

- [Release Notes Checklist](RELEASE.md)

If you need fast triage, check `DEPLOYMENT.md` for runtime and restart
troubleshooting and `BUILD.md` for compile requirements.
