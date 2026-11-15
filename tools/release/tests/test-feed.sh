#!/bin/bash
# Checks the update feed's notes (#374): run as tools/release/tests/test-feed.sh (CI: release tools job).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
FEED_PY="$HERE/../feed.py"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
ATTR='sparkle:edSignature="x" length="1"'
fail() { echo "FAIL: $1" >&2; exit 1; }
description() { python3 -I -c 'import sys, xml.etree.ElementTree as E; print(E.parse(sys.argv[1]).find("channel/item/description").text)' "$1"; }

# 1. A notes file naming the version is the description, word for word.
python3 -I "$FEED_PY" "$HERE/CHANGELOG-fixture.md" 5.3.1 26.0 "$ATTR" "$OUT/a.xml" "$HERE/whats-new-5.3.1.txt"
[[ "$(description "$OUT/a.xml")" == "$(cat "$HERE/whats-new-5.3.1.txt")" ]] || fail "the description is not the notes file"

# 2. A notes file for another version falls back to the CHANGELOG, cleaned: no hashes, no issue refs, no duplicates.
python3 -I "$FEED_PY" "$HERE/CHANGELOG-fixture.md" 5.3.1 26.0 "$ATTR" "$OUT/b.xml" "$HERE/whats-new-5.3.1.txt" 2>/dev/null
python3 -I "$FEED_PY" "$HERE/CHANGELOG-fixture.md" 5.3.1 26.0 "$ATTR" "$OUT/c.xml"
B="$(description "$OUT/c.xml")"
grep -Eq '\b[0-9a-f]{7}\b' <<<"$B" && fail "a commit hash in: $B"
grep -q '#[0-9]' <<<"$B" && fail "an issue ref in: $B"
grep -q 'closes' <<<"$B" && fail "a closes in: $B"
grep -q 'https://' <<<"$B" && fail "a link in: $B"
[[ "$(grep -c 'Thronsen A parity pin' <<<"$B")" == 1 ]] || fail "the duplicated entry twice in: $B"
grep -q '^• a new dataset starts with an empty phase list$' <<<"$B" || fail "a plain bullet missing in: $B"
sed 's/5\.3\.1/5.4.0/' "$HERE/whats-new-5.3.1.txt" > "$OUT/other.txt"
python3 -I "$FEED_PY" "$HERE/CHANGELOG-fixture.md" 5.3.1 26.0 "$ATTR" "$OUT/d.xml" "$OUT/other.txt" 2>/dev/null
[[ "$(description "$OUT/d.xml")" == "$B" ]] || fail "a notes file for 5.4.0 was used for 5.3.1"

# 3. Neither: it fails.
if python3 -I "$FEED_PY" "$HERE/CHANGELOG-fixture.md" 9.9.9 26.0 "$ATTR" "$OUT/e.xml" "$OUT/other.txt" 2>/dev/null; then
  fail "no notes for 9.9.9 and it wrote a feed"
fi
echo "feed notes: ok"
