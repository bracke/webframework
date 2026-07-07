# API Stability

This document records the current release-candidate API posture.

## Stable For Application Use

- `Web.Request`
- `Web.Response`
- `Web.Cookie`
- `Web.Html`
- `Web.Config`
- `Web.Logging`
- `Web.Errors`
- `Web.Security`
- `Web.Patch`
- `Web.Events`
- `Web.Dispatcher`
- `Web.Live`
- `Web.Server` route/static/WebSocket registration and run helpers

These packages are the intended public surface for applications.

## Advanced Or Transport-Level

- `Web.Connection`
- `Web.TLS`
- `Web.WebSocket`
- `Web.Protocol`
- `Web.Static`

Applications may use these directly, but they are closer to protocol and
transport internals. Keep direct use focused and covered by tests.

## Compatibility Rules

- Keep application-facing names Ada-idiomatic.
- Do not add hidden route discovery, handler reflection, or frontend build
  steps.
- Preserve the template/database boundary: framework core stays independent.
- Prefer additive changes for stable packages.
- Document any incompatible change in this file and `docs/RELEASE.md`.

## Experimental Areas

- CLI scaffolding commands may evolve before the first stable release.
- Stress and fuzz tools are release aids, not runtime dependencies.
- TLS cipher defaults follow the underlying TLS binding and deployment policy.
