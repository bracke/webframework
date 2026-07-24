# Authorization & the guard seam

The framework core authenticates nothing and authorizes nothing. It provides a
**guard seam** so an application can plug identity and authorization in
uniformly and fail-closed, without the core depending on either library. This is
the deliberate boundary: `webframework` owns transport, sessions, and rendering;
*who you are* and *what you may do* live upstream.

## The pieces

### `Web.Context` — the request context

A request-scoped value threaded through the guards to the handler.

```ada
function New_Context return Request_Context;
function  Principal (Ctx : Request_Context) return String;   -- opaque; "" = anonymous
procedure Set_Principal (Ctx : in out Request_Context; Value : String);
function  Session (Ctx : Request_Context) return String;
procedure Set_Attribute (Ctx : in out Request_Context; Key, Value : String);
function  Attribute (Ctx : Request_Context; Key : String) return String;
```

The principal is an **opaque reference the framework never interprets** —
identity and authorization assign it meaning. Guards enrich the context; the
handler reads it.

### `Web.Guard` — pre-handler guards

```ada
type Guard_Outcome (Decision : Guard_Decision := Proceed) is ...;  -- Proceed | Halt (Response)
function Proceed return Guard_Outcome;
function Halt (Response : Web.Response.Response_Type) return Guard_Outcome;

type Guard_Access is access function
  (Request : Web.Request.Request_Type;
   Context : in out Web.Context.Request_Context) return Guard_Outcome;

type Contextual_Handler is access function
  (Request : Web.Request.Request_Type;
   Context : Web.Context.Request_Context) return Web.Response.Response_Type;
```

A guard may enrich the context (resolve a principal) and may **short-circuit**
the request by returning a response. The framework runs the guards and never
inspects what they decide. A guard that raises fails the request **closed**.

### Registration

```ada
--  A global guard runs before every request (HTTP and WebSocket upgrades).
procedure Use_Guard (Guard : Web.Guard.Guard_Access);

--  A context-aware route, optionally protected by a per-route guard.
procedure Get  (Path : String; Handler : Contextual_Handler; Guard : Guard_Access := null);
procedure Post (Path : String; Handler : Contextual_Handler; Guard : Guard_Access := null);

--  Guard a WebSocket route: the guards run before the handshake, and a halting
--  guard rejects the upgrade with its response instead of opening the channel.
procedure Guard_WebSocket (Path : String; Guard : Guard_Access);
```

Order: global guards first, then the route's guards; the first to halt wins.
Guarding covers **both** HTTP dispatch and the WebSocket upgrade — a refused
caller never opens the live channel.

### Session identity lifecycle

```ada
--  Rotate a session id (preserving state) on privilege change: fixation defense.
function  Regenerate_Session (Old_Id : String) return String;
--  Drop a session immediately (logout): its id can never be replayed.
procedure Invalidate_Session (Id : String);
```

`Web.Response.Forbidden` (403) completes the `401`/`403` vocabulary alongside
`Unauthorized`.

## The intended flow

```
Identity  ─►  Authorization  ─►  webframework_authorization  ─►  webframework
  (who)          (what)               (the bridge)               (this seam)
```

1. A **global guard** resolves the session cookie to the principal it stored,
   and puts that opaque principal on the context.
2. A **per-route guard** — built from the `webframework_authorization` bridge —
   reads the principal, asks the authorization engine for a decision, and maps
   it to `Proceed`/`Halt` fail-closed (anonymous → login/401, denied → 403).
3. The **handler** runs only for allowed callers and reads the principal (and
   any derived attributes) from the context.

Login verifies credentials through identity, then `Regenerate_Session`; logout
`Invalidate_Session`. None of this is in the framework core — it is all wired at
the application layer through the seam above.

The `example_app` demonstrates the whole chain: guarded pages and API routes, a
guarded WebSocket channel, identity-backed password authentication, and a
projects listing whose columns and row scope are planned by the `tables` crate
from the same authorization decision.
