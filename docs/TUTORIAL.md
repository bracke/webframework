# Tutorial

This tutorial shows the regular shape of a small server-driven app.

## Run and route

1. Register routes and handlers in `main.adb`.
2. Call `App.Runtime.Configure` with a `Web.Config.Config_Type`.
3. Start with `App.Runtime.Run` (HTTP) or `App.Runtime.Run_TLS` (HTTPS/WSS).

A minimal startup sequence is:

```ada
procedure Main is
begin
   App.Runtime.Register ("counter.increment", App.Counter.Increment'Access);
   App.Runtime.Register ("counter.increment", App.Counter.Increment'Access);
   App.Runtime.Get ("/", App.Pages.Home'Access);
   App.Runtime.Get ("/health", App.Pages.Health'Access);
   App.Runtime.WebSocket ("/ws", App.Runtime.WebSocket_Handler'Access);
   App.Runtime.Static ("/static", "static");
   App.Runtime.Configure (Web.Config.Default_Config);
   App.Runtime.Run ("127.0.0.1", 8080);
end Main;
```

Routing is exact-path:

- `App.Runtime.Get` matches the full request path (for example `GET /`).
- `App.Runtime.WebSocket ("/ws", ...)` matches the upgrade request path `"/ws"`.
- `App.Runtime.Static ("/static", ...)` serves `"/static/*"` from the mounted directory.
- unregistered paths return `404 Not Found`.

### Custom error pages

You can return branded end-user error pages by registering error handlers for
status codes before `Run`.

```ada
procedure Not_Found_Error
  (Request : Web.Request.Request_Type;
   Status  : Positive;
   Detail  : String) return Web.Response.Response_Type
is
   pragma Unreferenced (Request);
   pragma Unreferenced (Status);
   pragma Unreferenced (Detail);
begin
   return Web.Response.Html ("<h1>Page not found</h1>");
end Not_Found_Error;

procedure Internal_Error
  (Request : Web.Request.Request_Type;
   Status  : Positive;
   Detail  : String) return Web.Response.Response_Type
is
   pragma Unreferenced (Request);
   pragma Unreferenced (Status);
begin
   pragma Unreferenced (Detail);
   return Web.Response.Html ("<h1>Something went wrong</h1>");
end Internal_Error;

...
App.Runtime.Register_Error_Handler (404, Not_Found_Error'Access);
App.Runtime.Register_Error_Handler (500, Internal_Error'Access);
```

`Request` and `Detail` let handlers vary HTML by path/mode.
Use `Clear_Error_Handler (status)` to return to defaults at runtime.

Run the example app:

```sh
cd example_app
alr build
./bin/example_app --host 127.0.0.1 --port 8080
```

Then browse `http://127.0.0.1:8080/`.

## Counter

1. Create state:

```ada
package App.State is
   type State_Type is record
      Counter : Natural := 0;
   end record;

   --  Create initial session state.
   --  @return Initial application state.
   function Initial return State_Type;
end App.State;
```

2. Instantiate the convenience application façade:

```ada
with Web.Application;
with App.State;

package App.Runtime is new Web.Application
  (App_State     => App.State.State_Type,
   Initial_State => App.State.Initial);
```

3. Register an action handler:

```ada
function Increment
  (State : in out App.State.State_Type;
   Event : Web.Events.Event) return Web.Patch.Patch_List
is
   pragma Unreferenced (Event);
begin
   State.Counter := State.Counter + 1;
   return Web.Patch.Single
     (Web.Patch.Set_Text ("counter-value", Natural'Image (State.Counter)));
end Increment;
```

4. Add browser markup:

```html
<span id="counter-value">0</span>
<button id="counter-inc" data-wf-click="counter.increment">Increment</button>
```

5. Wire routes:

```ada
App.Runtime.Register ("counter.increment", App.Counter.Increment'Access);
App.Runtime.Get ("/", App.Pages.Home'Access);
App.Runtime.WebSocket ("/ws", App.Runtime.WebSocket_Handler'Access);
App.Runtime.Static ("/static", "static");
App.Runtime.Run ("127.0.0.1", 8080);
```

## Form

Use `form[data-wf-submit]`. The runtime serializes `FormData` and sends a
submit event:

```html
<form id="profile-form" data-wf-submit="profile.save">
  <input name="name">
  <button type="submit">Save</button>
</form>
<p id="profile-status"></p>
```

Handler:

```ada
function Save
  (State : in out App.State.State_Type;
   Event : Web.Events.Event) return Web.Patch.Patch_List
is
   pragma Unreferenced (State);
begin
   if not Web.Events.Has_Field (Event, "name") then
      return Web.Patch.Single
        (Web.Patch.Set_Text ("profile-status", "Name is required"));
   end if;

   return Web.Patch.Single
     (Web.Patch.Set_Text
        ("profile-status", "Saved " & Web.Events.Field (Event, "name")));
end Save;
```

## Persisted Todo

Keep UI state in `App.State`; keep persistent data in app-owned store packages.
The framework core does not know about databases.

Recommended shape:

- `App.Database`: setup and database file ownership.
- `App.Store`: persistent operations such as add/list/toggle.
- `App.Todo`: event handlers that call `App.Store` and return patches.
- `App.Pages`: full route rendering.

The reference `example_app` uses this structure with sibling `../database`.
