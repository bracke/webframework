# Public API

## Webcore

- `Web.Request`: parsed HTTP request values and validated case-insensitive
  header storage/lookups, with validated direct construction.
- `Web.Response`: HTTP responses, helpers, validated status codes,
  validated case-insensitive header storage/lookups, zlib-backed gzip/deflate response
  compression, server-owned
  `Content-Length`, validated `Content-Type`, `Content-Encoding`,
  `Cache-Control`, `Connection`, and `Vary` management, and serialization.
- `Web.Cookie`: request cookie parsing and validated `Set-Cookie` generation,
  including explicit multi-character `Path` values and checked `Max-Age`
  semantics.
- `Web.Html`: escaping with raw control-byte encoding, trusted rendered HTML
  wrapper, id/class validation.
- `Web.Config`: default framework configuration values, including response
  compression enablement, minimum body size, and accepted connection limits.
- `Web.Logging`: stdout/stderr logging helpers with configurable minimum level
  and optional key/value structured output (`Debug`/`Info`/`Warn` to `stdout`,
  `Error` to `stderr`).
- `Web.Errors`: framework exceptions and exception-to-response conversion.
- `Web.Security`: path checks, cryptolib-backed session ids, session id format
  validation, ssh_lib-backed zeroing entropy buffers, and strict Origin/Host
  validation.

## WebSocket

- `Web.Connection`: shared read/write/close transport wrapper for plain TCP and
  TLS connections with validated socket and TLS handles.
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
  cooperative observable `Stop`. `Health_Response` returns a stable text
  health-check response, and `Configuration_Report` returns a short validated
  runtime policy summary. Normal HTTP responses negotiate `gzip` or `deflate`
  from `Accept-Encoding`, preferring `gzip`, when enabled by config and the
  response body meets the configured minimum size, or when the client rejects
  identity and accepts a supported compressed representation. If compression is
  disabled, or the client explicitly rejects the identity representation and no
  supported encoded representation is selected, the server returns
  `406 Not Acceptable` with `Vary: Accept-Encoding`.
  `Run`/`Run_TLS` validate bind ports and numeric bind addresses. `Configure`
  validates non-empty allowed-host policy and applies
  production/development error mode, allowed Host/Origin policy, request size
  limits, accepted connection limits, and response compression policy. A failed
  route/parser dispatch path returns a request-local `4xx`/`5xx` response.
  `Register_Error_Handler` and `Clear_Error_Handler` register status-specific
  handlers for custom end-user error pages.
  `Reload_TLS` replaces certificate/key/CA/policy for future TLS handshakes.

## Fault isolation

- Exceptions from parsing, static serving, route handlers, dispatchers, and websocket
  event loops are contained within the current connection or session.
- Unknown websocket actions and handler exceptions produce empty patch lists and do
  not propagate into protocol transport.
- Unknown session ids or malformed action names are rejected at the boundary and do
  not mutate shared process state.
- `Web.Static`: safe static-file mapping, URL-prefix boundary checks, and
  case-insensitive extension content types.
- `Web.Patch`: typed patch operations and validated patch-list assembly with
  no JSON or socket dependency.
- `Web.Protocol`: JSON wire protocol encode/decode with protocol version
  enforcement, duplicate-field rejection, parser-bounded strings, bounded event
  payloads, and control-byte-safe JSON output.
- `Web.Events`: typed browser event values, validated element/action names,
  bounded form fields, and validated field lookups.
- `Web.Dispatcher`: generic validated action-to-handler registry over app
  state.
- `Web.Live`: generic cookie-backed sessions, secure-cookie configuration,
  serialized state access, active WebSocket replacement, event loop, manual
  session cleanup, current session/WebSocket counters, configured WebSocket
  message limits, strict `With_State` validation, and opt-in observable
  background cleanup.
- `Web.Application`: convenience façade that instantiates and wires both
  `Web.Dispatcher` and `Web.Live` for one generic package, exposing the
  most common session/liveloop methods so application startup is less
  boilerplate.
  `Register_Error_Handler` and `Clear_Error_Handler` are re-exported so
  application startup can install custom response pages through the façade.

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
