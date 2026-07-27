# integration_demo

End-to-end demonstration that the headless `navigation` and `forms` libraries are
usable inside webframework HTTP handlers, through the
[`webframework_navigation`](../webframework_navigation) and
[`webframework_forms`](../webframework_forms) bridges.

`src/site.adb` builds a route table, a menu, and a contact-form definition once,
then defines two handlers:

- **GET /contact** — renders the page chrome with `Render_Menu` (the active item
  highlighted, resolved from the request path) and `Render_Breadcrumbs`, plus a
  contact form carrying a CSRF token issued into both a `Set-Cookie` header and a
  hidden field.
- **POST /contact** — verifies CSRF against the cookie, decodes the urlencoded
  body into a submission, binds it against the form definition, and either
  re-renders the form **sticky** with the diagnostics (`400`) on failure or
  **redirects by route name** to `thanks` (`303`) on success.

`src/demo.adb` drives these handlers with synthetic requests (via the
`Web.Server.Parse_Request` test seam — no socket) and self-checks the whole loop:
the CSRF cookie issued on GET is carried into a valid POST (→ `303 /thanks`), a
missing field re-renders sticky with an error (`400`), and a POST with no CSRF
cookie is refused (`403`).

```sh
alr build && ./bin/demo
```

This is the integration proof for the two bridge crates; it depends on both plus
webframework, navigation, and forms.
