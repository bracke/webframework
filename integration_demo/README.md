# integration_demo

End-to-end demonstration that the headless `navigation` and `forms` libraries are
usable inside webframework HTTP handlers, through the
[`webframework_navigation`](../webframework_navigation) and
[`webframework_forms`](../webframework_forms) bridges.

`src/site.adb` builds a route table, a menu, and a contact-form definition once,
then defines two handlers:

- **GET /contact** — renders the page chrome with `Render_Menu` (the active item
  highlighted, resolved from the request path) and `Render_Breadcrumbs`, plus a
  contact form. It establishes a session (a `sid` cookie) and embeds a
  **session-bound CSRF token** (`Session_Token` — an HMAC of the session under a
  server key) in a hidden field.
- **POST /contact** — verifies the CSRF token against the request's session
  (`Verify_Session_Csrf`), decodes the body by `Content-Type` (`Read_Body`;
  a non-form body is refused), binds it against the form definition, and either
  re-renders the form **sticky** with the diagnostics (`400`) on failure or
  **redirects by route name** to `thanks` (`303`) on success.

`src/demo.adb` registers the handlers and drives them through the real router
(`Web.Server.Dispatch`) with synthetic requests (via the `Parse_Request` test
seam — no socket), and self-checks the whole loop: the session + CSRF token from
GET carry into a valid POST (→ `303 /thanks`); a missing field re-renders sticky
with an error (`400`); a valid CSRF token replayed under a **different session**
is refused (`403` — what session binding buys over double-submit); and a POST with
no session is refused (`403`).

```sh
alr build && ./bin/demo
```

This is the integration proof for the two bridge crates; it depends on both plus
webframework, navigation, and forms.
