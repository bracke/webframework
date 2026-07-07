#!/usr/bin/env sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
DEFAULT_ROOT=$(cd -- "$SCRIPT_DIR/../.." && pwd)

if [ -f "$SCRIPT_DIR/../env/example_app.env" ]; then
  . "$SCRIPT_DIR/../env/example_app.env"
fi

if [ -z "${PROJECT_ROOT:-}" ]; then
  PROJECT_ROOT=$DEFAULT_ROOT
fi

EXAMPLE_APP_BIN=${EXAMPLE_APP_BIN:-$PROJECT_ROOT/example_app/bin/example_app}
if [ -z "${EXAMPLE_APP_ARGS:-}" ]; then
  EXAMPLE_APP_ARGS=${APP_ARGS:---host 127.0.0.1 --port 8080}
fi

if [ ! -x "$EXAMPLE_APP_BIN" ]; then
  echo "EXAMPLE_APP_BIN is not executable: $EXAMPLE_APP_BIN" >&2
  exit 1
fi

exec "$EXAMPLE_APP_BIN" $EXAMPLE_APP_ARGS
