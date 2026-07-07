# API Examples

## Boot the example

```sh
cd example_app
alr build
./bin/example_app --host 127.0.0.1 --port 8080
```

The app serves:

- `GET /` and `GET /health` from `App.Runtime.Get`.
- `GET /ws` websocket upgrade from `App.Runtime.WebSocket`.
- `GET /static/...` from the configured static directory.

## `Web.Application`

```ada
App.Runtime.Configure (Web.Config.Default_Config);
App.Runtime.Get ("/", App.Pages.Home'Access);
App.Runtime.WebSocket ("/ws", App.Runtime.WebSocket_Handler'Access);
App.Runtime.Static ("/static", "static");
App.Runtime.Run ("127.0.0.1", 8080);
```

Health route:

```ada
function Health
  (Request : Web.Request.Request_Type) return Web.Response.Response_Type
is
   pragma Unreferenced (Request);
begin
   return App.Runtime.Health_Response;
end Health;
```

## `Web.Application`

```ada
package App.Runtime is new Web.Application
  (App_State     => App.State.State_Type,
   Initial_State => App.State.Initial);
```

Use `Find_Or_Create_Session` during full-page rendering and
`WebSocket_Handler` for the live route.

`App.Runtime` re-exports the same convenience session and websocket entry points:

```ada
App.Runtime.Register ("counter.increment", App.Counter.Increment'Access);
```

For the common full-page case, `Html_Response` can find or create the session
and attach the cookie in one call:

```ada
return App.Runtime.Html_Response (Request, Rendered_Page);
```

`App.Runtime` uses an internal dispatcher, so direct registration through
`App.Dispatcher` is no longer required in new apps.

Unknown actions are logged and return an empty patch list.

## `Web.Patch`

```ada
return Web.Patch.Single
  (Web.Patch.Set_Text ("status", "Saved"));
```

Use `Replace_HTML` only with trusted rendered HTML. Use `Set_Text` for plain
user-facing text.

## `Web.Protocol`

```ada
Message := Web.Protocol.Decode_Client_Message
  ("{""type"":""click"",""version"":1,"
   & """id"":""counter-inc"",""action"":""counter.increment""}");

Wire := Web.Protocol.Encode_Patches
  (Web.Patch.Single (Web.Patch.Set_Text ("counter-value", "1")));
```

`Web.Protocol` does not dispatch actions or access sockets.

## `Web.Logging`

```ada
Web.Logging.Set_Minimum_Level (Web.Logging.Info_Level);
Web.Logging.Set_Structured (True);
Web.Logging.Info ("service=example started=true");
```

The example app and `webframework_cli` keep console output styled and then forward
it through `Web.Logging`, so level filtering and structured output apply
consistently during development and deployment.

## Reference App Patterns

The `example_app` shows the intended boundaries:

- Full pages render templates in `App.Pages`.
- Event handlers mutate typed session state or persistence and return explicit
  patch lists.
- `Replace_HTML` is used only for rendered template fragments.
- `Set_Text` receives plain text and must not be pre-escaped.
- Forms use stable ids for submitted fields and patch targets.
- Persistent todos live in `App.Store`; per-session UI state stays in
  `App.State`.
