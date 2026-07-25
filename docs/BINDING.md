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
- Phases 12–17: pending, in spec order.
