# webframework_forms

Bridge from the [`forms`](../../forms) library to the webframework HTTP handler
seam. It is the only unit that depends on both: forms stays headless and
byte-oriented (decode → submission → bind → CSRF, no request/response), and
webframework core depends on none of forms' crates.

With this bridge a handler can:

- **Decode a request body into a submission** — `Read_Body (Request, Into,
  Status)` dispatches on `Content-Type`: an `application/x-www-form-urlencoded`
  body is decoded into a `Forms.Submission.Data`; any other type yields
  `Body_Unsupported_Media`, so a JSON or unexpected body is refused rather than
  mis-decoded. (`Read_Urlencoded` remains for the direct case.) String request
  data is converted to `Representation.Byte_Array` at the boundary.
  Note: webframework's server rejects `multipart/form-data` bodies at parse time,
  so multipart never reaches a handler; `forms` has a decoder ready, but wiring
  it needs a webframework-core change, not a bridge one.
- **Enforce CSRF.** Two mechanisms:
  - *Session-bound (preferred)* — `Session_Token (Key, Session_Id)` is an
    HMAC-SHA256 synchronizer token; `Verify_Session_Csrf (Sub, Key, Session_Id)`
    recomputes and constant-time compares it. Because the token is signed and
    bound to the session, a valid token replayed under another session (or a
    planted cookie) is rejected. `Key` is a stable server secret.
  - *Stateless double-submit* — `New_Token` / `Set_Cookie` (HttpOnly,
    SameSite=Strict) / `Verify_Csrf (Request, Sub)`, for session-less endpoints.
  Both are constant-time and fail-closed.

- **Turn diagnostics into a response** — after `Forms.Binding.Bind` (and any
  `Forms.Rules.Merge` of validation results) fills a `Diagnostic_Set`,
  `Diagnostics_Text` / `Error_Response` render it as plain text, and
  `Diagnostics_JSON` / `Error_Response_JSON` as a JSON array for API clients
  (both default to `400`).
- **Re-render sticky values** — `Sticky (Def, Sub, Name)` returns the value to
  re-display for a field after a failed submission, "" for a redacted
  (sensitive) field. (Escape it before embedding in markup.)

Everything is fail-closed and nothing raises. `To_Bytes`/`To_String` convert
between webframework strings and forms byte arrays.

## Build & test

```sh
alr build
cd tests && alr build && ./bin/test_bridge
```

The named invariants (BRIDGE-*), the dependency boundary, and the release gate
for all bridges are documented in [`docs/BRIDGES.md`](../docs/BRIDGES.md) and
enforced by `bridge_tools/check_bridges`.
