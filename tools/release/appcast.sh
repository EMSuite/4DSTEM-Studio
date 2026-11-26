#!/bin/zsh
# Writes the update feed for one download (#122): tools/release/appcast.sh <notarized DMG> <version> <out.xml> [notes file]
#
# The website serves the feed at https://mac4dstem.com/appcast/mac4dstem.xml (the app's SUFeedURL, Info-Direct.plist), so
# the file this writes is committed to the website repo as appcast/mac4dstem.xml in the same PR that sets the download's
# version and size. One item, the newest release: Sparkle needs only that. The DMG is signed with Sparkle's sign_update,
# which reads the private EdDSA key from the login keychain (macOS asks once to allow it); the key never leaves the Mac.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DMG="$1" VERSION="$2" FEED="$3" NOTES="${4:-}"
SIGN_UPDATE="$ROOT/build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
[[ -x "$SIGN_UPDATE" ]] || { echo "No $SIGN_UPDATE (build-developer-id.sh clones the packages there)." >&2; exit 1; }

# sign_update prints the enclosure's two attributes: sparkle:edSignature="…" length="…".
ATTRIBUTES="$("$SIGN_UPDATE" "$DMG")"
[[ "$ATTRIBUTES" == *'sparkle:edSignature="'*'length="'* ]] || { echo "sign_update printed no signature: $ATTRIBUTES" >&2; exit 1; }
FLOOR="$(grep -m1 'MACOSX_DEPLOYMENT_TARGET = ' "$ROOT/FourDSTEMStudio.xcodeproj/project.pbxproj" | sed 's/.*= \(.*\);/\1/')"

# The release notes (#374): the store's What's New text when it names this version, else the CHANGELOG section cleaned.
/usr/bin/python3 -I "$ROOT/tools/release/feed.py" "$ROOT/CHANGELOG.md" "$VERSION" "$FLOOR" "$ATTRIBUTES" "$FEED" "${NOTES:-}"
echo "$FEED"
