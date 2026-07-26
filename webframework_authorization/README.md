# webframework_authorization

A small bridge from the [`authorization`](../authorization) engine to the
[`webframework`](../webframework) guard seam. It is the **only** unit that
depends on both libraries; the web framework core depends on neither
`authorization` nor `identity`, and the authorization engine knows nothing about
HTTP.

It is one element of a larger stack and is not released standalone.

## What it does

`webframework` runs guards before a route handler (and before a WebSocket
upgrade). A guard returns `Proceed` or `Halt (Response)`, and the framework
never inspects *why*. This crate turns an authorization decision into that
outcome, **fail-closed**:

```
Authorization.Evaluator.Decision  ──►  Web.Guard.Guard_Outcome
      Authorized / Authorized_With_Requirements  ──►  Proceed
      Rejected  (deny, or indeterminate)          ──►  Halt (denial response)
```

Only an explicit authorization proceeds. A definite deny and an *indeterminate*
"could not decide" both halt — the deny-by-default posture of the engine carried
unchanged into the request path.

## API

```ada
--  Map a decision to a guard outcome, fail-closed. On_Deny defaults to 403.
function Outcome_Of
  (Decision : Ev.Decision;
   On_Deny  : Web.Response.Response_Type := Web.Response.Forbidden)
   return Web.Guard.Guard_Outcome;

--  Build a route guard from an application decision function. Denies anonymous
--  requests (with Anonymous) before consulting the policy; otherwise asks
--  Decide and maps the result fail-closed (with Denied).
generic
   Denied    : Web.Response.Response_Type;
   Anonymous : Web.Response.Response_Type;
   with function Decide
     (Principal : String;
      Request   : Web.Request.Request_Type;
      Context   : Web.Context.Request_Context) return Ev.Decision;
function Guarded
  (Request : Web.Request.Request_Type;
   Context : in out Web.Context.Request_Context) return Web.Guard.Guard_Outcome;
```

An application instantiates `Guarded` with its own decision function (which
builds an authorization request from the resolved principal and evaluates it
against the app's policy), then registers the instance's `'Access` as a
`Web.Guard.Guard_Access`. The principal is read from the request context — an
opaque string the framework never interprets, that an upstream guard resolved
from the session and that identity gave meaning. The whole context is passed to
`Decide` too, so the policy can read facts an upstream guard attached (the
principal's clearance, the session's assurance level) without the framework
knowing what any of them mean.

## Where it sits

```
identity  ─►  authorization  ─►  webframework_authorization  ─►  webframework
   (who)         (what)                 (this crate)              (transport)
```

Identity authenticates and yields a principal; authorization decides; this
bridge maps the decision to an allow/deny at the route; the framework enforces
it. See the `example_app` in the `webframework` repository for the full chain,
and [`tables_authorization`](../tables_authorization) for the parallel bridge
that plans a data listing from the same decision.

## Build

```sh
alr build                              # the library
cd tests && alr build && ./bin/test_bridge   # the fail-closed mapping test
```

Requires Alire and GNAT (gnat_native 15.2.1). Depends on `authorization` and
`webframework` (and, transitively, the OpenSSL libraries `webframework` links).

## License

MIT OR Apache-2.0 WITH LLVM-exception.
