#!/bin/bash
# A fresh checkout with no build/ gets its dmgbuild venv on the first release run (#373).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
DMGBUILD="$("$HERE/../ensure-dmgbuild.sh" "$ROOT")"
[[ "$DMGBUILD" == "$ROOT/build/dmg-venv/bin/dmgbuild" && -x "$DMGBUILD" ]] || { echo "FAIL: no dmgbuild at $DMGBUILD" >&2; exit 1; }
[[ "$("$ROOT/build/dmg-venv/bin/pip" show dmgbuild)" == *"Version: 1.6.1"* ]] || { echo "FAIL: not dmgbuild 1.6.1" >&2; exit 1; }
# A second run finds it and creates nothing.
[[ "$("$HERE/../ensure-dmgbuild.sh" "$ROOT" 2>&1)" == "$DMGBUILD" ]] || { echo "FAIL: the second run did not just print the path" >&2; exit 1; }
echo "ensure dmgbuild: ok"
