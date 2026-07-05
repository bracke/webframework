# Security Posture

This framework is intentionally small. Production deployments should use the
strict interfaces below instead of adding hidden middleware or frontend build
steps.

## Transport

- Plain `Run` serves HTTP and WS for local or trusted deployments.
- `Run_TLS` serves HTTPS and WSS with OpenSSL through the Ada `Web.TLS`
  binding.
- TLS certificate, key, CA, and cipher configuration strings reject control
  bytes before they cross the C boundary.
- TLS policy is configured before serving and can be reloaded for future
  handshakes.

## Cryptography

- WebSocket handshakes use `CryptoLib.Hashes.SHA1` only for the RFC6455
  `Sec-WebSocket-Accept` value.
- Session ids use `CryptoLib.Random` production entropy.
- Random-source access is serialized by a protected object.
- Session entropy passes through `SSH_Lib.Protocol.Buffers` so ephemeral secret
  bytes are explicitly cleared.
- Framework core does not implement password storage, application encryption,
  or database encryption.

## HTTP Boundary

- Only one HTTP/1.1 request per connection is supported.
- HTTP/2, chunked encoding, request body compression, multipart uploads,
  Expect/Continue, and pipelining are rejected.
- Response `gzip` and zlib-wrapped `deflate` compression are negotiated from
  `Accept-Encoding` and implemented through `../zlib`.
- Response compression can be disabled and has a configurable minimum body size.
- Explicit `q=0` entries disable the matching response encoding even when a
  wildcard is present.
- Higher `Accept-Encoding` `q` values win; equal supported values prefer
  `gzip`.
- Malformed `q` values, including trailing junk or more than three fractional
  digits, are treated as unavailable.
- Requests that reject the identity representation with `identity;q=0` receive
  `406 Not Acceptable` when no supported compressed representation is selected.
- Compression preserves existing `Vary` values and adds `Accept-Encoding`
  without duplication.
- Automatic compression is limited to text-like response types; already encoded
  responses, `Cache-Control: no-transform` responses, and common binary/static
  asset types are not transformed.
- Unsupported response encodings are ignored.
- Header names must be token characters with no whitespace before `:`.
- Header values reject C0 controls and DEL.
- `Content-Length` must be unsigned decimal digits only and must match the body
  length exactly.
- Response `Content-Length` is generated during serialization and cannot be set
  by applications.

## WebSocket Boundary

- Upgrade validation requires method `GET`, version 13, strict Upgrade and
  Connection tokens, and a valid 16-byte client nonce shape.
- Only unfragmented masked client text, ping, pong, and close frames are
  accepted.
- RSV bits, WebSocket compression/extensions, binary frames, continuation
  frames, invalid control frames, invalid close codes, non-minimal length
  encodings, unmasked client frames, and oversized frames/messages are rejected.

## Sessions

- `wf_session` cookies contain only opaque random ids.
- Session state is server-side and typed by the application.
- Malformed or unknown session cookies are ignored rather than trusted.
- Session id creation inserts into the protected store atomically with collision
  retry.
- One active WebSocket is kept per session; a new one replaces the old one.

## Boundaries

- `webcore`, `websocket`, and `webframework` do not depend on templates or
  databases.
- Template rendering and persistence live in `example_app`.
- `../template` and `../database` are example-app dependencies only.
- Browser JavaScript transports events and applies patches only; it has no app
  state, routing, validation, or templates.
