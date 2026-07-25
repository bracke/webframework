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
| `Web.Binding.Diagnostics` (+ `.Recording`) | structured, redaction-safe events + sink | 16+ |
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
relevant, fuzz) coverage. Coverage map (as of phase 16): BIND-001
(Bodies.Claim), BIND-002 (Results shape + record binder), BIND-003 (bounded
parsers + fuzz for url/JSON/multipart), BIND-004 (deterministic error order),
BIND-005 (Id_Key), BIND-006 (exact paths, collection/nested/JSON tests),
BIND-007 (duplicate policy resolution), BIND-008 (decoders are pure syntax),
BIND-009 (upload streaming, never fully buffered), BIND-010 (upload abort on
scope exit), BIND-011 (secret redaction, Forms + hardening), BIND-012 (frozen
registry + concurrent-use test), BIND-013 (builder, no reflection/layout),
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

## Phase status

- **Phase 0 — Foundations: landed.** Identifiers, source kinds, typed paths and
  locations, structured error parameters, `Decoding_Error`, bounded
  deterministically-truncated `Error_Collection`, generic results, typed limits
  with layered tightening, policy types, invariant registry. Unit-tested; no body
  decoding yet.
- **Phase 1 — Scalar decoder framework: landed.** Decoder contract
  (`Web.Binding.Decoders`: input kinds, metadata, `Single_Error`, a total UTF-8
  validator) and built-in decoders, all returning structured results and never
  raising on malformed input:
  - signed integer (radix/sign/whitespace/separator/leading-zero config; exact
    `decode.invalid_integer` vs `decode.integer_out_of_range`, overflow-guarded);
  - modular integer (unsigned, at-modulus is out of range);
  - float (strict decimal; NaN/Inf → `decode.non_finite_float`; overflow caught
    at a defensive boundary);
  - Boolean (narrow `true`/`false` default + optional 1/0, yes/no, on/off + case
    folding; checkbox semantics excluded);
  - bounded text (UTF-8 validation + length bound);
  - enumeration (explicit wire mappings, case modes, aliases/deprecated aliases);
  - UUID (canonical hyphenated, normalized to lowercase);
  - ISO date, time-of-day, and RFC 3339 date-time (real-calendar validation, so
    `2026-02-31` is `decode.invalid_date`; leap years and leap seconds handled;
    `Web.Binding.Decoders.Calendar` holds the shared model);
  - Base64 (standard + URL-safe, padding policy, bounded byte output);
  - optional and default combinators (a malformed present value is an error,
    never silently defaulted).

  AUnit suite 48 → 65. All acceptance rules met (exact classification, no
  malformed-input exception flow). **Deferred by design:** fixed-point,
  duration, hex-bytes (niche scalar decoders, add on demand); normalized
  media-type and URI-component decoders belong with the structural media-type
  work in Phase 9.
- **Phase 2 — Non-body request sources: landed.** `Web.Binding.Sources` (ordered
  bounded `Occurrences` with locations + malformed flag; `Resolve_Scalar` applies
  the duplicate and empty policies deterministically — missing / present-empty /
  present-value are distinct). `Web.Binding.Percent` (shared, total percent-
  decode). Source adapters: `Query` (parse → ordered pairs, percent + plus,
  duplicates/empty preserved, malformed flagged, ordinal locations), `Route`
  (app-supplied captures — this router is exact-match, no path captures),
  `Headers` (single-valued per the transport; no blind comma join/split),
  `Cookies` (jar lookup; duplicate `Count` surfaced as repeated occurrences so
  Reject fires). AUnit suite 65 → 71 (mixed-source extraction without body
  access; deterministic duplicate handling). Body sources come with the codecs
  (phases 5–10).
- **Phase 3 — Record binding: landed.** `Web.Binding.Record_Binders` (generic
  over the target record): a limited `Builder` holds a defaults-seeded working
  copy + error collection + aggregation mode; the nested generic `Bind_Scalar`
  resolves a field's occurrences (phase 2), decodes the value (phase 1) and
  assigns it through a caller-supplied setter. No reflection, no unchecked layout
  (BIND-013); `Finish` returns the record only on success, never a partial value
  (BIND-002). Required-missing / duplicate / empty / malformed / undecodable are
  structured errors at exact paths; a malformed present value is never replaced
  by a default; fields bind in call order so error order is deterministic
  (BIND-004); `Fail_Fast` vs `Aggregate_Fields`; `Note_Unknown` applies the
  unknown-field policy. Mixed-source records need no implicit merge (each field
  takes its own occurrences). AUnit suite 71 → 74.
- **Phase 4 — Collections and nesting: landed.** Both integrate with the phase-3
  builder through caller-supplied setters (no container types inside `Result`).
  `Record_Binders.Bind_Collection` (nested generic): each repeated occurrence is
  decoded and appended in source order at an exact indexed path (`base[0]`,
  `base[1]`, …); more than `Max_Items` is `decode.too_many_items` (excess never
  appended), fewer than `Min_Items` is `decode.invalid_list`; per-element errors
  aggregate. `Sources.Split` turns a delimited scalar into occurrences so the
  same binder handles delimited collections. `Bind_Nested` (nested generic)
  composes a sub-record bind into the parent, merging the sub-errors (already
  carrying nested paths); absent + optional is None, absent + required is
  `binding.missing`, present-but-malformed aggregates. `Web.Binding.Names` gives
  pluggable flat-name adapters (dotted / bracketed / underscored) for nested
  fields on flat sources; `Guard_Depth` enforces a maximum path depth
  (`decode.nesting_too_deep`). AUnit suite 74 → 78.
- **Phase 5 — URL-encoded codec + stream abstraction: landed.**
  `Web.Binding.Streams` (abstract bounded input stream: `Read` enforces the
  aggregate byte limit and tracks the offset; outcomes cover chunk / EOF /
  over-limit / cancelled / failed, none raising) with `Streams.Memory` — the
  in-memory backing and test double (configurable chunking + injected premature
  EOF / read failure). `Web.Binding.Bodies` tracks body ownership (Available /
  Decoding / Consumed / Failed; a second claim is refused → the caller reports
  binding.source_already_consumed). `Web.Binding.Codecs.URL_Encoded` is a
  streaming byte-level state machine, so `%XX` escapes and `&`/`=` delimiters may
  split across chunks and the result is fragmentation-invariant; percent + plus
  decoded, malformed escape flagged, bounded pair count / name+value length /
  body size (too_many_fields / field_too_large / body_too_large). UTF-8
  validation stays a decoder concern (layering). AUnit suite 78 → 85, including a
  fuzz harness (adversarial corpus + pseudo-random bytes at every chunk size:
  always terminates, no exceptions, bounded output).
- **Phase 6 — JSON streaming core: landed.** `Web.Binding.Codecs.JSON` is a
  strict streaming pull-tokenizer over the body stream, no DOM: one token at a
  time (Start_Object, Key, String_Value, Number_Value, …, End_Document). A
  one-character lookahead makes it fragmentation-invariant; an explicit state
  stack (never recursion) enforces structure and a bounded nesting depth. Full
  escape handling incl. surrogate pairs and UTF-8 validation; strict number
  grammar (no leading zeros / bare dots / NaN / Infinity); rejects comments,
  trailing commas, trailing content, control chars in strings, invalid escapes.
  Source locations (line / column / byte offset); bounds on depth, token count,
  string length and numeric-literal length. Malformed input yields an
  Error_Token, never an exception. AUnit suite 85 → 93, including the escape and
  number matrices and a fuzz harness (adversarial + pseudo-random bytes at every
  chunk size: always terminates at End_Document or Error_Token).
- **Phase 7 — Typed JSON binding: landed.** `Web.Binding.Codecs.JSON.Binding`
  drives the phase-6 tokenizer into typed values with no DOM: streaming
  primitives walk objects (`Next_Member` positions at each value), arrays
  (`Next_Element`), skip unknown values (`Skip_Value`), and extract scalars
  (generic `Read_Scalar` → a decoder result; objects/arrays are
  json.unexpected_kind). A `Member_Tracker` gives duplicate detection and
  required-field checking. `Record_Binders.Assign` folds each field result into
  the builder (a "setter" may set or append, so the same call binds scalars and
  collection elements). The application supplies deterministic member dispatch (a
  case on the key — compiler-generated, not hash-iteration order); errors carry
  exact JSON paths (`body.tags[1]`, `body.user.age`) and aggregate within a
  structurally valid object. AUnit suite 93 → 96 (full object with array +
  nested; duplicate / unknown / null / type-mismatch / missing; path + order
  aggregation).
- **Phase 8 — Discriminated unions: landed.** `Web.Binding.Union_Binders`
  (generic over the alternative enum): a `Selector` maps discriminator wire
  values to alternatives (`Resolve` → found/not-found → union.missing /
  union.invalid), and `Resolve_Structural` turns per-alternative match flags into
  Exactly_One / Ambiguous (union.ambiguous_alternative) / No_Match
  (union.no_matching_alternative). The safe-construction pattern: decode the
  discriminator, collect the selected alternative's fields into locals, and build
  the discriminated Ada value once with the resolved discriminant — never
  mutating a mis-discriminated record; a field from another alternative is
  rejected. AUnit suite 96 → 99 (both alternatives construct; missing / invalid /
  wrong-alternative; structural exactly-one / ambiguous / no-match).
- **Phase 9 — Media types + codec registry: landed.** `Web.Binding.Media_Types`
  parses a Content-Type into type / subtype / structured suffix / charset /
  boundary (case-insensitive, quoted params, verbatim boundary); malformed
  syntax is Valid => False (→ body.invalid_content_type), never an exception.
  Also covers the deferred phase-1 "normalized media type" via `Normalized`.
  `Web.Binding.Codecs.Registry` registers codecs against exact / suffix / wildcard
  patterns in a mutable Builder, then `Freeze` validates (ambiguous same-
  specificity patterns, invalid wildcards) and yields an immutable Registry
  (BIND-012). `Select_Codec` is deterministic: exact → suffix (+json) → wildcard
  (type/* then */*) → none; no sniffing. Missing-Content-Type policy (reject /
  allow-empty / use-default). AUnit suite 99 → 102.
- **Phase 10 — Multipart streaming core: landed.** `Web.Binding.Multipart` is a
  defensive streaming pull parser: skip the preamble, then per part read bounded
  headers (Content-Disposition → name + optional filename; optional part
  Content-Type) and stream the body up to the next boundary. Boundary detection
  uses a compacting buffer with block search that holds back a delimiter-length
  tail, so a boundary split across read chunks is found and the result is
  fragmentation-invariant; scanning is linear and bounded, and file bodies are
  never fully buffered (a caller streams them via Read_Body — phase 11 wires the
  sink). Limits bound part count, header size and text-field size; malformed
  framing is a structured Outcome, never an exception; client filenames are
  metadata only. AUnit suite 102 → 106, including fragmentation across chunk
  sizes 1…5000 and a fuzz harness (adversarial + pseudo-random, always terminates).
- **Phase 11 — Files and Uploads adapter: landed.** `Web.Binding.Uploads` defines
  the narrow backend contract (`Upload_Sink`: Begin_Upload / Write_Chunk /
  Finish_Upload / Abort_Upload) and a controlled, request-scoped `Upload_Session`
  that streams a multipart part's body into a sink chunk by chunk (never buffering
  the whole file, BIND-009), enforces per-upload and aggregate byte limits, and
  yields an opaque `Upload_Handle` with metadata (filename, content-type, byte
  count, checksum) — never a path. On `Finalize` (scope exit) or `Discard` it
  aborts every staged-but-uncommitted upload, so a failed bind cleans up
  deterministically and handles never escape (BIND-010). `Web.Binding.Uploads.
  Memory` is the in-memory backend and test double (rolling checksum + injectable
  begin/write/finish faults). AUnit suite 106 → 110 (stream + checksum,
  per-upload / aggregate limits, injected sink failure, abort-on-scope-exit).
- **Phase 12 — Forms integration: landed.** No Forms sibling exists, so
  `Web.Binding.Forms` defines the adapter contract and a usable in-place form.
  It tracks the submission lifecycle (Not_Submitted → Decoded / Decode_Failed →
  Validated / Validation_Failed), retains submitted raw values for safe
  re-rendering **subject to sensitivity** (Public retained; Private and Secret
  never retained, so passwords / tokens / CSRF secrets stay blank — BIND-011),
  and converts a bind result's structured errors into per-field errors (matched
  by the path's leaf name) and non-field (form-level) errors. Forms consume the
  binding output and never reparse. AUnit suite 110 → 112 (a full re-render:
  valid and invalid field values retained, secret redacted, per-field vs
  non-field errors; and the state transitions).
- **Phase 13 — Validation integration: landed.** No Validation sibling exists,
  so `Web.Binding.Validation` defines the seam: a merged `Presentation` that
  combines a bind result's decoding errors with the validation layer's semantic
  issues, preserving each entry's origin (From_Decoding / From_Validation) and
  ordering decoding before validation. Decoding entries carry the stable
  error-id key, leaf field name and rendered path; validation issues use the
  same path form, so the two align. Binding hands validation a decoded typed
  value and compatible paths; validation never touches the raw request and its
  rules never live in binding descriptors. AUnit suite 112 → 114 (the marquee
  case: decoding succeeds but a semantic rule fails; and a merged decode +
  validation presentation preserving origin).
- **Phase 14 — Identity and Authorization adapters: landed.** `Web.Binding.Auth`
  decodes the Authorization header *syntax* only — scheme (Basic / Bearer /
  Digest / Other) + raw credentials, and for Basic the base64 userid:password
  split — and verifies nothing (no password check, token signature, session
  lookup or identity assignment). Credential fields are secrets. The tests are
  the required examples: a login input where the password is a Secret_Value field
  and is redacted on re-render (never retained), and a resource-identifier
  binding (route UUID) that yields a typed value for authorization to consume
  elsewhere — binding makes no permission decision. No authentication or
  authorization logic lives in binding core (the acceptance rule). AUnit suite
  114 → 117.
- **Phase 15 — Typed handlers: landed.** `Web.Binding.Requests` provides the
  failure classification (`Classify`: malformed/missing → Bad_Request 400,
  unsupported/missing media type → 415, over-size body/field → 413, binding-
  config fault → 500, and route-parameter → 404 by policy; worst class wins) and
  a generic `Dispatch` that runs the application handler **only on success** with
  the fully typed value, sending failures to a response mapper with the class and
  errors — binding never builds a response itself. `Web.Binding.Contexts` is the
  minimal per-request `Binding_Context` (effective limits, aggregation mode,
  diagnostics flag, correlation id), the §9 skeleton deferred from phase 0. AUnit
  suite 117 → 120 (classification incl. worst-wins and route-404, the context,
  and dispatch proving the handler runs only on success).
- **Phase 16 — Hardening: landed.** `Web.Binding.Decoders.Guard` is the defensive
  boundary — it wraps a decoder so any exception (violated invariant, programmer
  error, unexpected runtime fault) is caught and converted to
  internal.decoder_failure carrying only the path and id, never request data. A
  `Cancel` stream fault was added. New hardening suite: concurrent shared use
  (four tasks × 3000 iterations over immutable decoders and a frozen registry,
  no corruption — BIND-012), stream cancellation yielding a defined error and
  terminating, the guard, and secret redaction (BIND-011). AUnit suite 120 → 124;
  every invariant now has coverage (see the map above) and no attacker-controlled
  path is unbounded (all parsers fuzzed and bounded).
- **Phase 17 — Documentation and integration example: landed.** This guide plus
  the AI-oriented `docs/ai/BINDING.md` (package ownership, instantiation patterns,
  dependency rules, extension points, prohibited shortcuts); pointers from
  `docs/README.md` and `docs/ai/CHECKLIST.md`; and a complete, tested example in
  the example app (`app-query_binding` binds the projects-listing query into a
  typed record, exercised by `app_tests`).

All 17 phases complete; 124 framework AUnit tests plus the example app's binding
tests, green end to end.
