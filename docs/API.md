# Public API

## Webcore

- `Web.Request`: parsed HTTP request values and case-insensitive headers.
- `Web.Response`: HTTP responses, helpers, validated case-insensitive headers,
  zlib-backed gzip/deflate response compression, server-owned
  `Content-Length`, and serialization.
- `Web.Cookie`: request cookie parsing and validated `Set-Cookie` generation,
  including explicit multi-character `Path` values.
- `Web.Html`: escaping, trusted rendered HTML wrapper, id/class validation.
- `Web.Config`: default framework configuration values, including response
  compression enablement and minimum body size.
- `Web.Logging`: stdout/stderr logging helpers.
- `Web.Errors`: framework exceptions and exception-to-response conversion.
- `Web.Security`: path checks, cryptolib-backed session ids, session id format
  validation, ssh_lib-backed zeroing entropy buffers, and strict Origin/Host
  validation.

## WebSocket

- `Web.Connection`: shared read/write/close transport wrapper for plain TCP and
  TLS connections.
- `Web.TLS`: Ada OpenSSL binding for server TLS contexts, TLS handshakes,
  decrypted reads, encrypted writes, TLS version/cipher/client-certificate
  policy, control-byte-rejected configuration strings, certificate reload,
  OpenSSL error reporting, and explicit no-verify local test clients.
- `Web.WebSocket`: RFC6455 upgrade helpers, frame encode/decode, ping/pong,
  close frames, client masking, valid close-code checks, minimal length
  encoding checks, strict 16-byte client nonce validation, cryptolib-backed
  SHA-1 accept-key hashing, and size rejection.

`Web.WebSocket` does not know JSON, sessions, routes, handlers, templates, or
application state.

## Webframework

- `Web.Server`: `GNAT.Sockets` HTTP/HTTPS server, route/static/WebSocket
  registry, request parsing, response sending, `Run`, `Run_TLS`, and
  cooperative `Stop`. Normal HTTP responses negotiate `gzip` or `deflate` from
  `Accept-Encoding`, preferring `gzip`, when enabled by config and the response
  body meets the configured minimum size. If the client explicitly rejects the
  identity representation and no supported encoded representation is selected,
  the server returns `406 Not Acceptable`. `Configure` applies
  production/development error mode, allowed Host/Origin policy, request size
  limits, and response compression policy. `Reload_TLS` replaces
  certificate/key/CA/policy for future TLS handshakes.
- `Web.Static`: safe static-file mapping, URL-prefix boundary checks, and
  content types.
- `Web.Patch`: typed patch operations with no JSON or socket dependency.
- `Web.Protocol`: JSON wire protocol encode/decode with protocol version
  enforcement, duplicate-field rejection, bounded event payloads, and
  control-byte-safe JSON output.
- `Web.Events`: typed browser event values, validated element/action names,
  and bounded form fields.
- `Web.Dispatcher`: generic action-to-handler registry over app state.
- `Web.Live`: generic cookie-backed sessions, secure-cookie configuration,
  serialized state access, active WebSocket replacement, event loop, manual
  session cleanup, configured WebSocket message limits, and opt-in background
  cleanup.

## Example App

The example app owns rendering, templates, form behavior, and persistence. It
may depend on the sibling `../template` crate. Framework core packages do not
depend on templates or databases.

## Browser Runtime

`static/webframework.js` sends events and applies patches. It ignores malformed
server messages, avoids duplicate active WebSocket connections, preserves
focused subtrees for non-forced HTML replacement, and starts whether loaded
before or after `DOMContentLoaded`. It has no app state, client routing,
validation, templating, npm dependency, bundler, or transpiler.
