# webframework_navigation

Bridge from the [`navigation`](../../navigation) library to the webframework HTTP
handler seam. It is the only unit that depends on both: navigation stays headless
(it builds URLs and resolves menus but knows nothing of requests/responses), and
webframework core depends on none of navigation's crates.

With this bridge an application can:

- **Redirect to a named route** — `Redirect_To (Routes, "user.show", Params)`
  builds the reverse URL and returns a `303` response with the `Location` header
  set. Type-safe: links never drift, and a build failure returns your error
  response (default `500`) rather than redirecting to a wrong or empty URL.
- **Resolve the active menu item from the request** —
  `Active_For (Menu, Routes, Request)` matches `Web.Request.Path` against the
  menu.
- Build a reverse URL as a plain string with `Location_Of` for embedding in a
  response body.

Everything is fail-closed and nothing raises, consistent with both libraries.

Later phases add menu/breadcrumb HTML render helpers and visibility filtering
wired to the request context.

## Build & test

```sh
alr build
cd tests && alr build && ./bin/test_bridge
```
