# Request Binding and Input Decoding

`Web.Binding.*` converts an already-parsed HTTP request into strongly typed Ada
values **before** validation and application logic run. It performs *syntactic
decoding only* — never semantic validation, authentication, authorization,
file-storage policy, rendering, or business rules.

```
HTTP bytes -> transport parsing -> source extraction -> BINDING (syntactic decode)
           -> typed value | structured errors -> validation -> auth -> app logic
```

A syntactically invalid date (`2026-02-31`) is a **decoding** failure. A valid
date outside a booking window is a **validation** failure and belongs elsewhere.

The subsystem is part of the `webframework` crate (flat `web-binding-*` units),
not a separate Alire project.

## Package map

| Package | Responsibility |
| --- | --- |
| `Web.Binding` | root: overview, `Source_Kind`, strongly-typed quantities |
| `Web.Binding.Errors` | `Error_Id`, parameters, locations, `Decoding_Error`, bounded `Error_Collection` |
| `Web.Binding.Paths` | typed `Field_Path` segments + deterministic rendering |
| `Web.Binding.Limits` | `Binding_Limits` record + layered tightening |
| `Web.Binding.Policies` | duplicate / unknown / presence / empty / null / aggregation / sensitivity |
| `Web.Binding.Results` | generic typed-value-or-errors result |
| `Web.Binding.Decoders` (+ `Scalar_`, `Collection_`, `Optional_`) | decoder contract + built-ins + combinators |
| `Web.Binding.Sources` / `Source_Values` | source model, cardinality, raw values |
| `Web.Binding.Route` / `Query` / `Headers` / `Cookies` | non-body source adapters |
| `Web.Binding.Record_Binders` / `Union_Binders` | builder-based record + tagged-union binding |
| `Web.Binding.Contexts` | per-request `Binding_Context`, body-ownership state |
| `Web.Binding.Bodies` / `Codecs` / `Codecs.*` / `Registry` | body stream, media-type + immutable codec registry |
| `Web.Binding.Multipart` (+ `.Binding`) / `Uploads` | streaming multipart, typed-field helpers + upload adapter |
| `Web.Binding.Requests` | typed-handler entry points + response classification |
| `Web.Binding.Diagnostics` (+ `.Recording`) | structured, redaction-safe events + sink |
| `Web.Binding.Testing` | test helpers for decoder authors |
| `Web.Binding.Internal.*` | private parser implementations |

The binding core must not depend on templates, HTML, application handlers,
`database`, concrete `Validation` rules, concrete `Identity`/`Authorization`
engines, or application models.

## Integration reality (this repository)

- **Identity, Authorization, i18n** — present. Binding provides *syntactic*
  decoders (credential syntax, resource ids) and returns stable error ids; it
  never authenticates, checks permission, or renders localized prose.
- **Forms, Validation** — provided by the `forms` and `validation` sibling
  libraries, consumed from a handler through the `webframework_forms` bridge. No
  validation/forms logic lives in binding.
- **Files and Uploads** — no HTTP upload-staging sibling exists (`files` is a
  file-manager UI). Binding defines the upload adapter lifecycle
  (`Begin_Upload` / `Write_Chunk` / `Finish_Upload` / `Abort_Upload`) and a test
  double; a real staging backend plugs in later. Binding never embeds one.
- **Body streaming** — `Web.Request` buffers the body as a `String` today. The
  `Web.Binding.Bodies` stream abstraction is streaming-shaped with an in-memory
  backing; a true streaming transport is a framework follow-on that the binding
  layer will consume unchanged.

## Error-ID registry

`Error_Id` is a closed enumeration; its literal spelling is the stable,
compatibility-sensitive localization key (BIND-005). `Errors.Id_Key` renders the
dotted key mechanically (`Decode_Integer_Out_Of_Range` → `decode.integer_out_of_range`).

Namespaces: `binding.*`, `decode.*`, `body.*`, `json.*`, `form.*`,
`multipart.*`, `union.*`, `internal.*` — the full set is the `Error_Id` type in
`web-binding-errors.ads`, kept in exact correspondence with §6 of the spec.

## Invariant registry

| Id | Invariant |
| --- | --- |
| BIND-001 | At most one body decoder owns a request body at a time |
| BIND-002 | A successful bind contains a fully finalized target value |
| BIND-003 | Every loop driven by request input has an effective bound |
| BIND-004 | Equivalent input produces errors in the same order |
| BIND-005 | Public error ids are compatibility-sensitive |
| BIND-006 | Every field-specific error carries an exact structured path |
| BIND-007 | Duplicate handling occurs only through explicit policy |
| BIND-008 | Core decoders do not query external systems or enforce business rules |
| BIND-009 | Multipart file data is never fully buffered by binding |
| BIND-010 | All staged upload resources are aborted when binding fails |
| BIND-011 | Secret fields never expose raw values in errors, logs, or retained data |
| BIND-012 | Registries used during request processing are frozen |
| BIND-013 | Record binding uses no field offsets or unchecked layout |
| BIND-014 | A decoder consumes only its declared input |
| BIND-015 | Union selection is explicit; ambiguity is an error |

Each invariant carries a guard/assertion where practical plus AUnit (and, where
relevant, fuzz) coverage. Coverage map: BIND-001
(Bodies.Claim), BIND-002 (Results shape + record binder), BIND-003 (bounded
parsers + fuzz for url/JSON/multipart), BIND-004 (deterministic error order),
BIND-005 (Id_Key), BIND-006 (exact paths, collection/nested/JSON tests),
BIND-007 (duplicate policy resolution), BIND-008 (decoders are pure syntax),
BIND-009 (upload streaming, never fully buffered), BIND-010 (upload abort on
scope exit), BIND-011 (secret redaction in errors/logs — hardening), BIND-012
(frozen registry + concurrent-use test), BIND-013 (builder, no reflection/layout),
BIND-014 (decoder consumption discipline), BIND-015 (union ambiguity). The
defensive boundary (`Web.Binding.Decoders.Guard`) converts any unexpected
exception to internal.decoder_failure.

## Resource-limit layering

`Binding_Limits` fields are strongly typed (byte counts, item counts, depths,
ordinals, part numbers, error/token counts are distinct types). Limits compose
in layers — server hard maximum, route/handler, binding definition, field — and
an inner layer may only *reduce* an outer one. `Limits.Tighten` takes the
per-field minimum; `Limits.Is_Within` asserts the monotonicity. All size/offset
arithmetic checks overflow before use.

## Upload adapter lifecycle

```
parse+stage -> complete binding -> validation -> auth/app decision -> commit | discard
```

A successful multipart bind exposes an opaque staged-upload handle, never a path
string. If binding fails after staging, every uncommitted upload is aborted and
cleaned up deterministically; the primary decoding error is preserved; cleanup
failures are logged in redacted structured form (BIND-010).

## Binding lifecycle

```
context  ->  source lookup  ->  resolve (duplicate/empty/missing)  ->  decode
         ->  assign into builder  ->  finish  ->  typed value | errors
         ->  dispatch: on success run the handler; on failure classify + map
```

For a body, insert `select codec (media type) -> claim body -> stream-parse` after
the context step; the codec produces sources (URL-encoded) or drives a typed bind
(JSON, multipart). Uploads stream through the session and are aborted if the bind
fails.

## Missing, empty, and JSON null

Three distinct states, never conflated:

- **Missing** — the field is absent. Required → `binding.missing`; Optional /
  Optional_With_Default → the seeded default is kept.
- **Present-empty** — the field is supplied with an empty value. `Empty_Policy`
  decides: decode it, reject it (`binding.empty_not_allowed`), treat as missing,
  or map to None / an empty collection.
- **JSON null** — an explicit `null`. `Null_Policy` decides: reject, map to None,
  map to default, or custom. A default never replaces a *malformed supplied*
  value — `page=abc` is an error, not the default.

## Security and redaction

- Every attacker-controlled dimension is bounded (body size, value/field length,
  counts, JSON depth/tokens, collection items, path depth, errors); size and
  offset arithmetic is overflow-checked; all three body parsers are fuzzed.
- Malformed input is a structured result, never an exception; `Decoders.Guard`
  backstops the unexpected as `internal.decoder_failure`.
- Secret fields (`Secret_Value`) are never retained for re-render or logging
  (Forms); errors carry only a path, id and bounded typed parameters — never the
  raw value (BIND-011).
- Deny-by-default: duplicates rejected, JSON duplicate members rejected, no
  media-type sniffing, unsupported/ambiguous codec configs rejected at freeze.

`Web.Binding.Diagnostics` emits structured events at the seams (codec selected,
bind succeeded/failed, limit exceeded, upload aborted, internal exception,
registry failure) through a `Sink` an application implements; the default sink is
a no-op. Events carry only safe fields — correlation id, route id, codec id,
error id, error count, source kind, redacted rendered path, limit category —
**never** a raw body, password, token, cookie, uploaded content or secret value.
`Web.Binding.Requests.Dispatch` emits bind succeeded/failed and the upload
session emits upload-aborted on cleanup; `Web.Binding.Diagnostics.Recording` is an
in-memory sink for tests.

## Usage

The minimal flat-record pattern (see `example_app/src/app-query_binding.adb` for
a complete, tested example binding a listing query):

```ada
package RB   is new Web.Binding.Record_Binders (My_Record);
package Ints is new Web.Binding.Decoders.Integer_Decoders (Field_T);
function Dec (T : String; P : Field_Path; S : Source_Kind) return Ints.Results.Result
  is (Ints.Decode (T, P, S));
procedure Bind_F is new RB.Bind_Scalar (Field_T, Ints.Results, Dec, Set_F);

B : RB.Builder := RB.Start (Defaults);
Bind_F (B, Query.Lookup (Q, "f"), Path, Query_Parameter, Presence => Required);
Result := RB.Finish (B);   --  Succeeded -> Value_Of; else Errors_Of (exact paths)
```

Collections use `RB.Bind_Collection` with an append setter; nested records use
`RB.Bind_Nested`; JSON drives `Codecs.JSON.Reader` through `JSON.Binding`. See the
AUnit suites (`tests/src/web_binding_*`) for a worked example of every feature,
and `docs/ai/BINDING.md` for the AI-oriented map.

## Migration notes

- The subsystem is additive: it introduces the `Web.Binding.*` hierarchy and
  adds those units to the standalone-library `Library_Interface`; nothing in the
  existing framework changed. Handlers can adopt it incrementally, one route at a
  time, alongside ad-hoc parsing.
- Error ids (`Error_Id` literal spellings) are compatibility-sensitive
  localization keys; treat additions as append-only.
- Streaming is API-shaped over the currently-buffered body; a true streaming
  transport is a framework follow-on that binding consumes unchanged.
