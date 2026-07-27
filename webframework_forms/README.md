# webframework_forms

Bridge from the [`forms`](../../forms) library to the webframework HTTP handler
seam. It is the only unit that depends on both: forms stays headless and
byte-oriented (decode → submission → bind → CSRF, no request/response), and
webframework core depends on none of forms' crates.

With this bridge a handler can:

- **Decode a request body into a submission** — `Read_Urlencoded (Request, Into,
  Status)` turns an `application/x-www-form-urlencoded` body into a
  `Forms.Submission.Data` ready for `Forms.Binding.Bind`. String request data is
  converted to `Representation.Byte_Array` (forms' currency) at the boundary.
- **Enforce CSRF with a double-submit cookie** — `New_Token` mints a token from
  the stack CSPRNG; `Set_Cookie` returns a `Set-Cookie` value (HttpOnly,
  SameSite=Strict) and `Token_Hex` the hidden-field value; `Verify_Csrf
  (Request, Sub)` checks the submitted field against the request's cookie,
  constant-time and fail-closed.

- **Turn diagnostics into a response** — after `Forms.Binding.Bind` (and any
  `Forms.Rules.Merge` of validation results) fills a `Diagnostic_Set`,
  `Diagnostics_Text` renders it and `Error_Response` wraps it in a `400`.
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
