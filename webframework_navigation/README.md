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
- **Render a menu or breadcrumb trail to HTML** — `Render_Menu` emits a nested
  `<ul>` with the active item (and its trail) marked for styling; the active
  item comes from `Active_For`. `Render_Breadcrumbs` emits `<nav><ol>…`. Every
  label and URL is HTML-escaped (`Web.Html`), so navigation data can never
  inject markup.
- **Render only what a viewer may see** — instantiate the generic
  `Webframework_Navigation.Filtered_Menu` with your viewer type and a `Can_See`
  predicate (the seam an app wires `Authorization.Capabilities` into); hidden
  items and their whole subtrees are omitted, fail-closed.

Everything is fail-closed and nothing raises, consistent with both libraries.

## Build & test

```sh
alr build
cd tests && alr build && ./bin/test_bridge
```

The named invariants (BRIDGE-*), the dependency boundary, and the release gate
for all bridges are documented in [`docs/BRIDGES.md`](../docs/BRIDGES.md) and
enforced by `bridge_tools/check_bridges`.
