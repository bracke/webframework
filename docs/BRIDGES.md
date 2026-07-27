# Bridge crates — contract, invariants, and acceptance

The bridge crates wire the headless sibling libraries into the webframework HTTP
handler seam. Each is the **only** unit that depends on both sides; webframework
core depends on none of the sibling crates.

| Bridge | Wires in | May depend on |
|--------|----------|---------------|
| `webframework_navigation` | `navigation` | webframework + navigation only |
| `webframework_forms` | `forms` | webframework + forms (+ representation) only |
| `integration_demo` | both bridges | webframework + both bridges + navigation + forms |

The **dependency boundary** is machine-checked by `bridge_tools/check_bridges`:
neither forms bridge nor navigation bridge may reach the *other* sibling, and no
bridge may reach authorization, identity, persistence, i18n, an HTTP client, or
sockets.

## Test harness

Each bridge is tested with **AUnit** (matching the sibling libraries, not the
older host framework's plain drivers): `tests/` builds `./bin/tests`, with a
functional+hardening fixture (`bridge_tests`) and a **deterministic fuzz** fixture
(`fuzz_tests`, a reproducible LCG, 2000 iterations each). The navigation fuzz
proves rendered HTML stays injection-safe and a redirect never lets a param value
inject a header (response splitting); the forms fuzz proves body decoding and
CSRF verification never raise and stay deterministic on arbitrary input.

## Invariants (BRIDGE-*)

Each is covered by a case in the bridge test suites (see mapping below).

| ID | Invariant | Owner |
|----|-----------|-------|
| BRIDGE-01 | A reverse-URL redirect never targets a wrong/empty URL: a failed build yields the caller's error response (default 500), never a redirect | webframework_navigation |
| BRIDGE-02 | Rendered menu/breadcrumb HTML escapes every label and URL, so navigation data can never inject markup or break an attribute | webframework_navigation |
| BRIDGE-03 | Menu rendering under a viewer omits items (and their subtrees) that are not `Visible`; `Hidden` and `Indeterminate` both hide (fail-closed) | webframework_navigation |
| BRIDGE-04 | Active-state is resolved only from the request path; rendering never raises, even on an empty menu or hostile input | webframework_navigation |
| BRIDGE-05 | A malformed/oversized request body decodes to a value status, never a crash | webframework_forms |
| BRIDGE-06 | CSRF verification is constant-time and fail-closed: an absent, empty, malformed, oversized, or mismatched cookie/field returns False | webframework_forms |
| BRIDGE-07 | Sensitive field values are never re-rendered (sticky returns "" for a redacted field) | webframework_forms |
| BRIDGE-08 | No bridge reaches the other sibling or any auth/identity/persistence/transport crate | all (boundary audit) |
| BRIDGE-09 | Rendering/decoding/CSRF are deterministic and total (never raise) on arbitrary input | fuzz suites |

## Acceptance evidence

| Invariant | Evidence |
|-----------|----------|
| BRIDGE-01 | `webframework_navigation` driver: "missing param yields the error response", "redirect fail-closed on an over-budget URL" |
| BRIDGE-02 | driver: script-tag label escaped, quote-breaking URL escaped, breadcrumb labels escaped |
| BRIDGE-03 | driver: Filtered_Menu hides the gated section/subtree from a guest, shows it to an admin |
| BRIDGE-04 | driver: Active_For resolves the section match; empty menu renders to nothing |
| BRIDGE-05 | `webframework_forms` driver: malformed percent-escape is a value error, not a crash |
| BRIDGE-06 | driver: matching/mismatched/absent/malformed-hex/empty/oversized/wrong-length cookie cases |
| BRIDGE-07 | driver: `Sticky` returns the submitted value; sensitivity redaction covered in the forms library |
| BRIDGE-08 | `check_bridges` dependency-boundary audit |
| BRIDGE-09 | `fuzz_tests` — 2000× render/redirect (navigation) and decode/verify (forms), asserting injection-safety + no header split + determinism |

## Release gate

```sh
cd bridge_tools && alr build
./bin/check_bridges            # surface + dependency-boundary audit
./bin/check_bridges --release  # + build each bridge, run every test driver + demo
```

A release is accepted only when the surface, the boundary audit, and every
build/test/demo gate pass.
