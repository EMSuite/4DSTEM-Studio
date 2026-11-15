#!/bin/bash
# Makes sure dmgbuild is in <root>/build/dmg-venv (#373): a fresh tag worktree has no build/ (gitignored), so the first
# release run creates the venv itself instead of stopping. Build-time only, kept out of the scientific Python environment.
#   tools/release/ensure-dmgbuild.sh <root>    prints the dmgbuild path; fails only if creating the venv fails.
set -euo pipefail
ROOT="${1:?usage: ensure-dmgbuild.sh <root>}"
VENV="$ROOT/build/dmg-venv"
DMGBUILD="$VENV/bin/dmgbuild"
if [[ ! -x "$DMGBUILD" ]]; then
  echo "Creating $VENV (dmgbuild 1.6.1)" >&2
  mkdir -p "$ROOT/build"
  python3 -m venv "$VENV" >&2 || { echo "python3 -m venv $VENV failed" >&2; exit 1; }
  "$VENV/bin/pip" install --quiet --disable-pip-version-check dmgbuild==1.6.1 >&2 || { echo "pip install dmgbuild==1.6.1 failed" >&2; exit 1; }
  [[ -x "$DMGBUILD" ]] || { echo "dmgbuild is still missing at $DMGBUILD" >&2; exit 1; }
fi
echo "$DMGBUILD"
