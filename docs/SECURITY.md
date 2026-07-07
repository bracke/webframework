# Security Posture

This framework is intentionally small. Production deployments should use the
strict interfaces below instead of adding hidden middleware or frontend build
steps.

## Transport

- Plain `Run` serves HTTP and WS for local or trusted deployments.
- `Run_TLS` serves HTTPS and WSS with OpenSSL through the Ada `Web.TLS`
  binding.
- `Web.Connection` rejects `No_Socket` wrappers and null TLS handles at
  construction time.
- TLS certificate, key, CA, and cipher configuration strings reject control
  bytes before they cross the C boundary.
- TLS policy is configured before serving and can be reloaded for future
  handshakes.

## Cryptography

- WebSocket handshakes use `CryptoLib.Hashes.SHA1` only for the RFC6455
  `Sec-WebSocket-Accept` value.
- Session ids use `CryptoLib.Random` production entropy.
- Session id alphabet selection uses rejection sampling to avoid modulo bias.
- Random-source access is serialized by a protected object.
- Session entropy passes through `SSH_Lib.Protocol.Buffers` so ephemeral secret
  bytes are explicitly cleared.
- Framework core does not implement password storage, application encryption,
  or database encryption.

## HTTP Boundary

- Only one HTTP/1.1 request per connection is supported.
- The HTTP parser accepts `GET` only; other methods are rejected before
  routing.
- HTTP/2, chunked encoding, request body compression, multipart uploads,
  Expect/Continue, and pipelining are rejected.
- Any request `Transfer-Encoding` header is rejected, including empty,
  whitespace-only, identity-valued, chunked, or unknown transfer codings.
- Rejected multipart media types are recognized even when parameters are
  present.
- Any request `Content-Encoding` header is rejected, including empty,
  whitespace-only, or identity-valued headers.
- Response `gzip` and zlib-wrapped `deflate` compression are negotiated from
  `Accept-Encoding` and implemented through `../zlib`.
- Response compression can be disabled and has a configurable minimum body size.
- When compression is disabled, requests that reject identity receive
  `406 Not Acceptable`.
- The minimum body size is an optimization only; when identity is rejected and a
  supported compressed representation is accepted, the server compresses below
  the threshold instead of returning `406`.
- Explicit `q=0` entries disable the matching response encoding even when a
  wildcard is present.
- Higher `Accept-Encoding` `q` values win; equal supported values prefer
  `gzip`.
- Malformed `q` values, including trailing junk or more than three fractional
  digits, are treated as unavailable.
- Empty or malformed `Accept-Encoding` coding items are treated as unavailable.
- Duplicate `Accept-Encoding` coding entries in one header value are treated as
  unavailable instead of using overwrite order.
- Requests that reject the identity representation with `identity;q=0` receive
  `406 Not Acceptable` when no supported compressed representation is selected.
- Negotiation-driven `406 Not Acceptable` responses include
  `Vary: Accept-Encoding`.
- Compression and identity negotiation preserve existing `Vary` values and add
  `Accept-Encoding` without duplication.
- Automatic compression is limited to text-like response types; already encoded
  responses are not transformed and are served only when their existing
  `Content-Encoding` is acceptable. `Cache-Control: no-transform` responses and
  common binary/static asset types are not transformed; if identity is rejected
  for those responses, the server returns `406 Not Acceptable`.
- Direct `Web.Response.Compressed` calls enforce the same compressible-response
  policy and reject already encoded, `no-transform`, and binary responses.
- Unsupported response encodings are ignored.
- Header names must be token characters with no whitespace before `:`.
- Header values reject C0 controls, horizontal tab, DEL, and C1 controls.
- Direct `Web.Request.Set_Header` calls apply the same name/value validation as
  the HTTP parser.
- Direct `Web.Request.Create` calls validate method token shape, absolute
  raw/decoded path safety, and query delimiters/control bytes.
- Direct request and response header lookups validate header names before
  probing the case-insensitive header maps.
- Duplicate request headers are rejected so singleton header decisions cannot be
  changed by overwrite order.
- HTTP/1.1 `Host` is required and must parse as a strict authority with no
  userinfo, path, query, fragment, malformed port, or malformed host label.
  DNS labels cannot be empty, over 63 bytes, or start/end with `-`; IPv4-like
  hosts must be valid dotted-quad literals; bracketed IPv6 literals must have
  valid hextet structure.
- Non-empty `Allowed_Host` server configuration is validated when it is applied;
  invalid authorities or origins fail before serving.
- `Max_Request_Size`, `Max_WebSocket_Message`, and `Max_Connections` must be
  positive. Accepted sockets beyond `Max_Connections` are closed before worker
  task allocation.
- Server bind ports outside `1 .. 65535` are rejected before socket or TLS setup.
- Server bind hosts must be non-empty numeric socket addresses without control
  bytes and are rejected before socket or TLS setup.
- Request path and route/static registration safety are checked both before and
  after percent decoding, so encoded traversal, C1 controls, slash, and
  backslash bypasses are rejected.
- Static files larger than `Web.Security.Max_Request_Size` are rejected before
  reading them into memory.
- Static serving validates its URL prefix and filesystem directory inputs even
  when called directly.
- Response `Vary` values are validated as comma-separated tokens; `*` is valid
  only as a standalone value.
- Response `Content-Type` values must be valid media types with tokenized
  type/subtype and well-formed parameters.
- Response `Content-Encoding` values must be a single valid coding token. The
  server does not accept response coding lists because negotiation is performed
  against one representation coding.
- Response `Cache-Control` values are validated as comma-separated directives
  with token directive names and token or quoted-string directive values.
- Response `Connection` values are validated as non-empty comma-separated
  token lists.
- `Content-Length` must be non-empty unsigned decimal digits only, fit in Ada
  `Natural`, and match the body length exactly.
- Duplicate `Content-Length` is rejected before the connection reader trusts a
  request body size.
- Request body bytes without `Content-Length` are rejected by the parser.
- Response `Content-Length` is generated during serialization and cannot be set
  by applications.
- Response status codes are validated as HTTP status values in the range
  `100 .. 599` at construction time.
- Cookie names are HTTP tokens. Cookie values reject control bytes, DEL, C1
  controls, and cookie-delimiter characters. Cookie paths must be absolute,
  header-safe, and raw/decoded path-safe.
- Cookie `Max-Age` accepts non-negative values; `-1` is the only sentinel for
  omitting the attribute.
- Parsed cookie lookups validate cookie names before accessing the jar.
- HTML escaping emits markup delimiters as entities and encodes C0, DEL, and
  C1 controls as numeric character references instead of raw bytes.

## WebSocket Boundary

- Upgrade validation requires method `GET`, version 13, strict Upgrade and
  Connection tokens, and a valid 16-byte client nonce shape.
- Direct `Sec-WebSocket-Accept` generation rejects malformed client keys.
- Only unfragmented masked client text, ping, pong, and close frames are
  accepted.
- RSV bits, WebSocket compression/extensions, binary frames, continuation
  frames, invalid text UTF-8, invalid control frames, invalid close codes,
  non-minimal length encodings, invalid close reason UTF-8, unmasked client
  frames, and oversized frames/messages are rejected.
- Outbound pong frames enforce the RFC6455 control-frame payload limit before
  writing to the socket.
- Outbound server text frames are UTF-8 checked before encoding.

## Patch Boundary

- Patch target ids, CSS class names, and attribute names are validated before
  patches can be encoded for the browser.
- Attribute patch names reject empty names, whitespace/control bytes, and HTML
  delimiter characters.
- Patch list assembly validates public raw patch records passed to `Single`
  and `Append`.
- Patch JSON encoding revalidates public patch records so bypassing the
  constructors does not bypass protocol checks.
- Patch JSON encoding escapes C0, DEL, and C1 controls so server messages do
  not carry raw control bytes.
- Client protocol JSON strings are bounded before dispatch, including ignored
  extension fields.

## Sessions

- `wf_session` cookies contain only opaque random ids.
- Session state is server-side and typed by the application.
- Malformed or unknown session cookies are ignored rather than trusted.
- Duplicate `wf_session` cookies are rejected as ambiguous rather than using
  first or last overwrite order.
- Session id creation inserts into the protected store atomically with collision
  retry.
- Direct `With_State` and `Run_Connection` calls reject malformed session ids;
  `With_State` also rejects null callbacks.
- One active WebSocket is kept per session; a new one replaces the old one.

## Boundaries

- `webcore`, `websocket`, and `webframework` do not depend on templates or
  databases.
- Template rendering and persistence live in `example_app`.
- `../template` and `../database` are example-app dependencies only.
- Browser JavaScript transports events and applies patches only; it has no app
  state, routing, validation, or templates.

## Production Readiness Gates

- Run the AUnit suite and CLI checks before release: protocol encode/decode,
  hostile HTTP parsing, WebSocket framing, sessions, patches, static traversal,
  TLS policy, browser runtime behavior, and end-to-end live flows are covered
  by the repository tests.
- Add deployment-specific stress tests around the configured
  `Max_Connections`, WebSocket replacement, disconnect during send, and cleanup
  under active traffic before exposing the service to untrusted load.
- Add fuzz-style corpus tests for the HTTP parser, WebSocket frames, protocol
  JSON, and percent-decoded static paths when changing those parsers.
- Production deployments should set `Mode => Production`, a non-empty
  `Allowed_Host`, TLS certificate/key policy, `Secure_Cookies => True` for live
  sessions, positive resource limits, and a route that returns
  `Web.Server.Health_Response`.
- Log `Web.Server.Configuration_Report` at startup so the effective runtime
  policy is visible in operations.
- Release packaging should verify root build, test build, CLI build,
  `webframework check .`, `webframework check example_app`, and a generated
  app probe.
