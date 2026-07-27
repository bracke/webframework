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

Everything is fail-closed and nothing raises. `To_Bytes`/`To_String` convert
between webframework strings and forms byte arrays.

A later phase adds a bind helper and a diagnostics → response mapping (sticky
re-render).

## Build & test

```sh
alr build
cd tests && alr build && ./bin/test_bridge
```
