#!/usr/bin/env bash
#
# verify_full_stack.sh -- build and test the whole stack locally.
#
# Mirrors the CI "full-stack" job, which is gated on the rest of the stack
# (identity, authorization, tables, tables_authorization, webframework_
# authorization) being published. Until then this reproduces the same checks
# against the sibling working copies, so the integration can be verified
# end to end from a developer machine.
#
# Expects the sibling crates checked out next to this repository.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # the webframework repo

step() { printf '\n== %s ==\n' "$1"; }

step "webframework_authorization bridge"
( cd "$ROOT/../webframework_authorization/tests" \
    && alr --non-interactive build && ./bin/test_bridge )

step "framework AUnit suite"
( cd "$ROOT/tests" && alr --non-interactive build && ./bin/tests )

step "example app + integration tests"
( cd "$ROOT/example_app" && alr --non-interactive build \
    && ./bin/app_tests && ./bin/app_http_tests )

step "framework CLI checker on the example app"
( cd "$ROOT/webframework_cli" && alr --non-interactive build \
    && ./bin/webframework check ../example_app )

printf '\nALL GREEN\n'
