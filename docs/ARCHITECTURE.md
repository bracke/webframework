# Architecture

This framework is Ada-first and server-driven. Ada owns routes, sessions,
typed application state, event dispatch, and patch generation. The browser uses
HTML, CSS, and `static/webframework.js` for event transport and DOM patch
application only.

`webcore` primitives live under `Web.Request`, `Web.Response`, `Web.Cookie`,
`Web.Html`, `Web.Config`, `Web.Logging`, `Web.Errors`, and `Web.Security`.

`websocket` transport lives in `Web.WebSocket`. It handles RFC6455 upgrade
metadata, accept-key generation, frame encode/decode, masking, ping/pong
opcodes, close frames, close-code validation, minimal length encoding, and
size rejection. Upgrade validation requires a `Sec-WebSocket-Key` value whose
base64 shape decodes to the required 16-byte client nonce, and direct
accept-key generation applies the same key-shape validation. It does not know
JSON, sessions, or handlers.

Cryptographic primitives owned by the framework are centralized through the
sibling `../cryptolib` crate. `Web.WebSocket` uses `CryptoLib.Hashes.SHA1` for
the RFC6455 `Sec-WebSocket-Accept` handshake value, and `Web.Security` uses
`CryptoLib.Random` production entropy for opaque session ids. Access to the
random source is serialized by a protected object, so concurrent session
creation does not share mutable entropy state unsafely. Session entropy is held
through the exported `SSH_Lib.Protocol.Buffers` zeroing buffer before the public
cookie value is derived. The SHA-1 use is the WebSocket protocol handshake
hash, not application encryption.

HTTP response compression is implemented through the sibling `../zlib` crate.
`Web.Response.Compressed` can produce `gzip` or zlib-wrapped `deflate`
responses, and `Web.Server` negotiates those encodings from `Accept-Encoding`
before serialization when `Enable_Compression` is true. Responses smaller than
`Compression_Min_Size` normally stay unencoded when identity is acceptable, but
the server still compresses below that threshold when the client rejects
identity and accepts a supported compressed representation. Explicit `q=0`
entries disable that encoding even when a wildcard is present. When both
supported encodings are acceptable, the higher `q` value wins; equal values
prefer `gzip`. Unsupported response encodings are ignored. Malformed `q`
values, including trailing junk or more than three fractional digits, are
treated as unavailable. If compression is disabled, or the client explicitly
sets `identity;q=0` and no supported encoded response is selected, the server
returns `406 Not Acceptable` instead of silently sending an unencoded body; that
negotiation failure also includes `Vary: Accept-Encoding`. Compression appends
`Accept-Encoding` to an existing `Vary` header without duplicating it.
Identity responses selected by the same negotiation also include
`Vary: Accept-Encoding`, so caches do not reuse them for clients that reject
identity.
Automatic compression is limited to text-like response types: `text/*`,
JavaScript, JSON, XML, and SVG. Already encoded responses are left unchanged
when their existing `Content-Encoding` is acceptable, and otherwise follow the
same negotiation fallback as any other response. Responses marked with
`Cache-Control: no-transform` are left unchanged when identity is acceptable,
and return `406 Not Acceptable` when identity is rejected. The same applies to
binary/static asset types such as PNG, JPEG, ICO, and WOFF2. Request body
compression through `Content-Encoding` is still rejected.

Browser transport encryption is implemented by `Web.TLS`, a narrow Ada binding
to OpenSSL's TLS server API. `Web.Connection` is the shared transport boundary,
so `Web.Server`, `Web.WebSocket`, and `Web.Live` run over either plain TCP or
TLS without duplicating protocol logic. `Web.TLS.Configure_Server` records PEM
certificate/key paths, optional client-certificate CA file, TLS version bounds,
TLS 1.2 cipher list, TLS 1.3 cipher suites, and client verification mode.
TLS path and cipher configuration strings reject control bytes before crossing
the C boundary. Invalid policy fails closed before serving. `ssh_lib` is used
only where its exported Ada security/protocol utilities fit; it is an SSH
library and is not a browser HTTPS/WSS TLS stack.

`webframework` packages live under `Web.Server`, `Web.Static`, `Web.Patch`,
`Web.Protocol`, `Web.Events`, `Web.Dispatcher`, and `Web.Live`. These packages
own route/static dispatch, patch construction, the JSON wire protocol, typed
events, action dispatch, and cookie-backed per-session state.

`Web.Server.Run` binds with `GNAT.Sockets`, accepts up to the configured
`Max_Connections`, and serves registered routes, static files, and WebSocket
upgrades over plain HTTP/WS. Sockets accepted beyond that bound are closed
before a worker task is allocated. `Web.Server.Run_TLS` loads PEM
certificate/key files or a
`Web.TLS.Server_Config`, performs the TLS handshake after TCP accept, and serves
the same routes and WebSocket handlers as HTTPS/WSS. `Reload_TLS` swaps the TLS
context behind a protected object, so reloads are serialized with future
handshakes while active connections continue on their existing TLS sessions.
OpenSSL reason strings are included in framework security errors when
available. `Stop` requests cooperative shutdown and wakes the accept loop with a
local connection; it is intended for tests and embedding tools that need a
bounded server lifecycle. `Running` reports whether the listener is active and
shutdown has not been requested. `Health_Response` and `Configuration_Report`
are explicit helpers for applications that want health/readiness routes and
startup policy logging without hidden framework routes.

`Web.Server.Configure` applies the process-wide server policy before `Run` or
`Run_TLS`: production mode hides handler exception details from HTTP responses,
`Allowed_Host` is enforced against Host and WebSocket Origin/Host values, and
`Max_Request_Size` bounds request reads and parsed requests. `Max_Connections`
bounds accepted worker concurrency. Invalid zero limits fail closed during
configuration. Bind ports must be in `1 .. 65535` before socket or TLS setup
starts.

`Web.Live` stores typed `App_State` values server-side behind opaque
`wf_session` cookies. Session access is serialized by the live store. Each
accepted WebSocket touches the session, and browser events touch the session
before dispatch. `Cleanup_Sessions` removes sessions whose inactivity exceeds
the configured timeout and closes any active sockets after releasing the store
lock. `Start_Cleanup_Task` can run that cleanup periodically when an embedding
application wants automatic expiration. `Cleanup_Task_Running` reports whether
that periodic worker is currently started.

## Recovery and fault boundaries

The framework keeps failures scoped to one request, one websocket session, or
one shard:

- `Web.Server.Handle_Connection` catches request parsing and dispatch failures
  and returns an HTTP error for that connection only.
- Worker tasks are isolated; task exceptions are logged, and the accept loop keeps
  running.
- `Web.Server.Dispatch` catches route handler failures and converts them to
  internal-server-error responses.
- `Web.Live.Run_Connection` catches malformed websocket messages and unexpected
  runtime exceptions, then closes only that socket.
- `Web.Live.Dispatch_Event` catches action-handler exceptions and returns an empty
  patch list.
- `Web.Dispatcher.Dispatch` logs unknown actions and handler exceptions without
  propagating from the handler path to protocol code.

Application handlers should still validate and guard side effects such as database
operations; the framework isolates failures but does not retry mutations.

For process restart policy and log-driven runbook behavior in production, see
`docs/DEPLOYMENT.md`.

`Web.Security.Require_Allowed_Origin` validates cross-origin policy with exact
origin/authority matching. `Origin` values must be `http://` or `https://`
origins with no path, query, fragment, userinfo, spaces, or control bytes. A
configured full origin must match scheme, host, and port exactly after
case-normalizing the host. A configured host-only authority matches only the
request authority exactly. Host header fallback uses the same authority parser.

HTTP request and response header values reject C0 controls and DEL before
storage or serialization. `Set-Cookie` values are validated before
serialization so unsafe bytes cannot be emitted into response header lines.
Response header replacement is case-insensitive, and `Content-Length` is owned
by response serialization so applications cannot emit conflicting lengths.
Cookie parsing ignores unsafe cookie pairs and keeps the first valid value for
duplicate names. Cookie lookups reject malformed cookie names instead of
silently returning an empty result. `Set-Cookie` generation rejects
`SameSite=None` unless the cookie is also marked `Secure`, and supports explicit
validated path values.
Static file serving enforces URL-prefix boundaries before mapping a request
path to the configured static directory, so similarly named prefixes do not
fall through into the static mount. Only ordinary files are served; directories
and special filesystem entries are treated as not found. Path safety rejects
traversal markers, C0 controls, DEL, C1 controls, and backslash separators. Static file
serving validates URL prefix and directory inputs itself, even when called
directly rather than through `Web.Server.Static`. Static file reads are capped
by `Web.Security.Max_Request_Size` before allocation. Content type detection is
case-insensitive over the final file extension.

The browser runtime is `static/webframework.js`. It sends browser events and
applies server patches only. It ignores malformed server messages, requires
patch lists to be arrays, avoids duplicate active WebSocket connections, and
starts whether the script runs before or after `DOMContentLoaded`. It has no
application state, routing, validation, frontend templates, npm dependency,
bundler, or transpiler.

The example application is intentionally outside the framework boundary and may
depend on the sibling `../template` crate for rendering. It loads
`example_app/templates/*.html` files, renders layout/page/fragment templates in
app code, and explicitly splices already-rendered fragments at app-owned marker
comments. Todo list items use `todo-item.html` for both initial page rendering
and WebSocket patch rendering. Framework core still transports only rendered
HTML strings.

The example todo store persists through the sibling `../database` crate using
typed table operations and transactions. It does not use SQL, and the framework
core remains database-free.

## HTTP Flow

1. `Web.Server.Run` accepts a TCP connection with `GNAT.Sockets`; `Run_TLS`
   accepts TCP and then performs a TLS server handshake.
2. The server reads one HTTP/1.1 request within the configured size limit and
   rejects unsupported features such as HTTP/2, chunked encoding, request body
   compression, multipart uploads, and pipelining. Header names must be RFC
   token characters with no whitespace before the colon. `Content-Length`
   values must be unsigned decimal digits only. Request targets must be visible
   ASCII, begin with `/`, contain no fragment, and have a safe path component.
3. `Web.Server.Parse_Request` creates `Web.Request.Request_Type`.
4. The connection boundary enforces the configured Host/Origin policy.
5. `Web.Server.Dispatch` routes `GET` requests to registered handlers or
   `Web.Static.Serve`.
6. `Web.Server` applies negotiated `gzip` or `deflate` response compression
   when requested by `Accept-Encoding` and allowed by the configured compression
   policy.
7. `Web.Response.Serialize` writes an HTTP/1.1 response with `Content-Length`.

## WebSocket Flow

1. `Web.WebSocket.Is_Upgrade` identifies a strict RFC6455 upgrade request with
   `GET`, Upgrade/Connection tokens, version 13, and a valid client key shape.
2. `Web.Server` sends the RFC6455 `101 Switching Protocols` response.
3. The registered WebSocket handler passes the transport connection to
   `Web.Live`.
4. `Web.Live.Run_Connection` receives text frames within the configured message
   size limit, decodes protocol messages, converts them to typed events,
   dispatches them, encodes patches, and sends text frames back to the browser.
5. Ping frames receive pong responses. Close frames receive close responses.
   Fragmentation, RSV extension bits, WebSocket compression/extensions, binary
   frames, invalid text UTF-8, invalid control frames, invalid close codes,
   non-minimal lengths, invalid close reason UTF-8, and oversized messages
   close the connection.
   Outbound pong frames also enforce the control-frame payload limit before
   socket writes, and outbound server text frames are UTF-8 checked before
   encoding.

Decoded events are bounded before dispatch. Element ids and action names must
use the same stable-name character set as DOM ids and are limited to 128 bytes.
Submit fields reject duplicate names, more than 64 entries, names over 128
bytes, and values over 8192 bytes. Field accessors validate lookup names with
the same rules before probing the event field map. The JSON decoder rejects
malformed escapes, unsupported surrogate code points, duplicate protocol keys,
trailing data, leading-zero numbers, and strings over 8192 bytes, including
ignored JSON values.

Dispatcher registration validates action names with the same stable-name
grammar and length limit used by decoded events. Duplicate actions and null
handlers fail during registration.

## Session Lifecycle

Sessions are cookie-backed with `wf_session`. The cookie contains only an
opaque random id. State lives server-side in the instantiated `Web.Live`
package. `Find_Or_Create_Session` creates state from the generic
`Initial_State` function and returns a generated id only after atomically
inserting it into the protected store. `With_State` and live dispatch serialize
access to the typed session state. Direct `With_State` and `Run_Connection`
calls reject malformed session ids before entering the store; `With_State` also
rejects null callbacks. Cookie values must match the framework session id format
exactly; malformed or attacker-supplied values are ignored rather than used to
create sessions.

Only one active WebSocket is kept per session. A new WebSocket for the same
session replaces and closes the previous socket. `Cleanup_Sessions` removes
inactive sessions and closes active sockets after leaving the session-store
lock. `Configure` applies `Web.Config` session settings, including
`Secure_Cookies`, `Session_Timeout`, and `Max_WebSocket_Message`;
`Set_Secure_Cookies` is available for applications that configure this policy
directly.

`Session_Count` and `Active_WebSocket_Count` expose protected-store snapshots
for diagnostics and tests. They are observational only and do not participate in
routing, dispatch, cleanup policy, or protocol decisions.

## Patch Protocol

Patch construction is explicit. There is no virtual DOM. Patch target ids,
class names, and attribute names are validated by `Web.Patch`. `Replace_HTML`
accepts trusted rendered HTML; `Set_Text` accepts plain text. JSON encoding
belongs only to `Web.Protocol`, which revalidates public patch records and
escapes JSON control bytes before sending patch messages to the browser.

## Concurrency

The server uses one Ada task per connection. Handlers run synchronously and
should be short. Socket writes are not performed while holding the live session
store lock.
