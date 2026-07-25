# AI Notes: Web.Binding

Request binding and input decoding. Turns a parsed HTTP request into strongly
typed Ada values before validation/auth/app logic. Syntactic decoding only — no
validation, auth, storage, or rendering. Full guide: `../BINDING.md`.

## Package ownership (what to reach for)

- Foundations: `Web.Binding` (source kinds, quantity types), `Web.Binding.Errors`
  (Error_Id + Id_Key + bounded Error_Collection), `Web.Binding.Paths` (typed
  Field_Path + Render), `Web.Binding.Limits`, `Web.Binding.Policies`,
  `Web.Binding.Results` (generic value-or-errors).
- Decoders: `Web.Binding.Decoders` + `.Integer_/Modular_/Float_/Boolean_/Text_/
  Enum_/UUID_/Date_/Time_/DateTime_/Base64_Decoders`, combinators
  `Optional_/Defaulted_Decoders`, `.Guard` (exception → internal.decoder_failure).
- Sources: `Web.Binding.Sources` (Occurrences + Resolve_Scalar), `Web.Binding.
  Percent`, adapters `Query` / `Route` / `Headers` / `Cookies`; `Web.Binding.Names`
  (flat-name adapters).
- Binders: `Web.Binding.Record_Binders` (Builder + Bind_Scalar / Bind_Collection /
  Bind_Nested / Assign), `Web.Binding.Union_Binders`.
- Body: `Web.Binding.Streams` (+ `.Memory`), `Web.Binding.Bodies` (ownership),
  `Web.Binding.Codecs.URL_Encoded` / `.JSON` (+ `.JSON.Binding`) / `Multipart`,
  `Web.Binding.Media_Types`, `Web.Binding.Codecs.Registry`, `Web.Binding.Uploads`
  (+ `.Memory`).
- Integration: `Web.Binding.Forms`, `Web.Binding.Validation`, `Web.Binding.Auth`,
  `Web.Binding.Contexts`, `Web.Binding.Requests` (Classify + Dispatch).

## Instantiation patterns

- Scalar decoder for a target type: `package Int is new Integer_Decoders (T);`
  then wrap for a binder: `function Dec (Text; P; S) return Int.Results.Result is
  (Int.Decode (Text, P, S));` (the 3-arg profile the binders expect).
- Record binder: `package RB is new Record_Binders (Rec);` then per field
  `procedure Bind_X is new RB.Bind_Scalar (Field_T, Dec.Results, Dec_Wrapper,
  Set_X);` and drive with `RB.Start` → `Bind_X (B, Occ, Path, Source, Presence)`
  → `RB.Finish`. Collections: `RB.Bind_Collection` with an Append setter.
- JSON typed bind: drive `Codecs.JSON.Reader` with `JSON.Binding` primitives
  (Next_Member / Next_Element / Read_Scalar / Skip_Value) + `RB.Assign`; dispatch
  members with a case on the key (deterministic).
- Example end to end: `example_app/src/app-query_binding.adb`.

## Dependency rules

- The binding core depends on NONE of: templates, HTML, app handlers, database,
  concrete Validation/Identity/Authorization engines, app models.
- Every public `Web.Binding.*` unit must be listed in `Library_Interface` in
  `webframework.gpr` (standalone library) or it won't compile / isn't visible.
- Array aggregates use `[...]` (Ada 2022, `-gnatwj`); comments follow `-gnatyc`;
  warnings are errors (`-gnatwe`).

## Extension points

- New scalar type: instantiate an existing generic decoder, or write a decoder
  returning `Results.Result` and never raising (wrap risky code in `.Guard`).
- New body codec: consume `Streams.Input_Stream'Class`, produce a source or typed
  bind; register it in the immutable `Codecs.Registry`.
- New source: expose `Sources.Occurrences` via a `Lookup`.

## Prohibited shortcuts

- No runtime reflection, no unchecked record layout/offsets — record binding is
  builder + explicit setters only (BIND-013).
- Decoders never query external systems or enforce business rules (BIND-008); no
  semantic rules in binding descriptors.
- No exceptions for ordinary malformed input — return structured results.
- Never retain or log secret values; credential fields are Secret_Value.
- Duplicates rejected by default; JSON duplicate members rejected; no media-type
  sniffing.

## Workflows

- Build: `cd webframework && alr build`. Tests: `cd tests && alr build && ./bin/tests`.
- Whole stack incl. example: `./scripts/verify_full_stack.sh`.
- Error-ID registry: the `Error_Id` type in `web-binding-errors.ads`. Invariant
  registry + coverage map: `../BINDING.md`.
