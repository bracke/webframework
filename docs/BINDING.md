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

## Status

Implemented incrementally, phase by phase (§43 of the spec). This document is
the authoritative map; each phase updates it. See the phase table at the end for
what is landed versus pending.

## Package map

| Package | Responsibility | Phase |
| --- | --- | --- |
| `Web.Binding` | root: overview, `Source_Kind`, strongly-typed quantities | 0 |
| `Web.Binding.Errors` | `Error_Id`, parameters, locations, `Decoding_Error`, bounded `Error_Collection` | 0 |
| `Web.Binding.Paths` | typed `Field_Path` segments + deterministic rendering | 0 |
| `Web.Binding.Limits` | `Binding_Limits` record + layered tightening | 0 |
| `Web.Binding.Policies` | duplicate / unknown / presence / empty / null / aggregation / sensitivity | 0 |
| `Web.Binding.Results` | generic typed-value-or-errors result | 0 |
| `Web.Binding.Decoders` (+ `Scalar_`, `Collection_`, `Optional_`) | decoder contract + built-ins + combinators | 1, 4 |
| `Web.Binding.Sources` / `Source_Values` | source model, cardinality, raw values | 2 |
| `Web.Binding.Route` / `Query` / `Headers` / `Cookies` | non-body source adapters | 2 |
| `Web.Binding.Record_Binders` / `Union_Binders` | builder-based record + tagged-union binding | 3, 8 |
| `Web.Binding.Contexts` | per-request `Binding_Context`, body-ownership state | 2, 9 |
| `Web.Binding.Bodies` / `Codecs` / `Codecs.*` / `Registry` | body stream, media-type + immutable codec registry | 5, 6, 9 |
| `Web.Binding.Multipart` / `Uploads` | streaming multipart + upload adapter | 10, 11 |
| `Web.Binding.Forms` / `Validation` | integration adapters (siblings absent → contracts + doubles) | 12, 13 |
| `Web.Binding.Requests` | typed-handler entry points + response classification | 15 |
| `Web.Binding.Testing` | test helpers for decoder authors | all |
| `Web.Binding.Internal.*` | private parser implementations | as needed |

The binding core must not depend on templates, HTML, application handlers,
`database`, concrete `Validation` rules, concrete `Identity`/`Authorization`
engines, or application models.

## Integration reality (this repository)

- **Identity, Authorization, i18n** — present. Binding provides *syntactic*
  decoders (credential syntax, resource ids) and returns stable error ids; it
  never authenticates, checks permission, or renders localized prose.
- **Forms, Validation** — absent as siblings. Binding defines the narrow adapter
  contract each will consume (shared field ids + `Field_Path`) and ships a test
  double. No validation/forms logic lives in binding.
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
relevant, fuzz) coverage. Phase 0 lands BIND-002 (result shape), BIND-004/005/006
(errors + paths), BIND-007 (policy types), BIND-013 (no-reflection foundations).

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

## Phase status

- **Phase 0 — Foundations: landed.** Identifiers, source kinds, typed paths and
  locations, structured error parameters, `Decoding_Error`, bounded
  deterministically-truncated `Error_Collection`, generic results, typed limits
  with layered tightening, policy types, invariant registry. Unit-tested; no body
  decoding yet.
- Phases 1–17: pending, in spec order.
