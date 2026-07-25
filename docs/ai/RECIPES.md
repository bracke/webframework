# Recipes

Add an action by declaring a handler, registering it in the dispatcher setup,
adding a `data-wf-click` or `data-wf-submit` attribute in rendered HTML, and
returning explicit patches from the handler.

Guard a route by resolving the principal in a global guard (read the session
cookie, put the opaque principal and its derived facts on the context) and
attaching a per-route guard built from the `webframework_authorization` bridge
over the app policy. Register it with `Use_Guard` (global) and the guarded
`Get`/`Post` overloads (per route); the framework runs the guard before the
handler and enforces `Proceed` / `Halt (Response)` without inspecting why.

Gate a live (WebSocket) action by registering it with a `Web.Dispatcher`
action guard: `Register (Action, Handler, Guard)`. The dispatcher runs the guard
before the handler and emits no patch when it denies, so presentation and
execution are authorized separately.
