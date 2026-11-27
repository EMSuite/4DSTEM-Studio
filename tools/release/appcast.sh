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
# sign_update from the pinned tag's official Swift Package Manager zip, held to the checksum Sparkle's Package.swift states for it
# (tools/lib/sparkle-pin.sh): the binary SwiftPM fetched while the app linked that package. The app's own Sparkle is built from
# source (Vendor/Sparkle, #497), and signing a DMG does not depend on how the framework was built.
. "$ROOT/tools/lib/sparkle-pin.sh"
TOOLS="$ROOT/build/sparkle-tools/$SPARKLE_TAG"
SIGN_UPDATE="$TOOLS/bin/sign_update"
if [[ ! -x "$SIGN_UPDATE" ]]; then
  mkdir -p "$TOOLS"
  curl -fsSL -o "$TOOLS/spm.zip" "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_TAG/Sparkle-for-Swift-Package-Manager.zip" \
    || { echo "Could not download Sparkle $SPARKLE_TAG's Swift Package Manager zip." >&2; exit 1; }
  [[ "$(shasum -a 256 "$TOOLS/spm.zip" | cut -d' ' -f1)" == "$SPARKLE_SPM_ZIP_SHA256" ]] \
    || { echo "Sparkle $SPARKLE_TAG's zip does not match the checksum in tools/lib/sparkle-pin.sh." >&2; rm -f "$TOOLS/spm.zip"; exit 1; }
  ditto -x -k "$TOOLS/spm.zip" "$TOOLS"
  rm -f "$TOOLS/spm.zip"
fi
[[ -x "$SIGN_UPDATE" ]] || { echo "No $SIGN_UPDATE in Sparkle $SPARKLE_TAG's zip." >&2; exit 1; }

# sign_update prints the enclosure's two attributes: sparkle:edSignature="…" length="…".
ATTRIBUTES="$("$SIGN_UPDATE" "$DMG")"
[[ "$ATTRIBUTES" == *'sparkle:edSignature="'*'length="'* ]] || { echo "sign_update printed no signature: $ATTRIBUTES" >&2; exit 1; }
FLOOR="$(grep -m1 'MACOSX_DEPLOYMENT_TARGET = ' "$ROOT/FourDSTEMStudio.xcodeproj/project.pbxproj" | sed 's/.*= \(.*\);/\1/')"

# The release notes (#374): the store's What's New text when it names this version, else the CHANGELOG section cleaned.
/usr/bin/python3 -I "$ROOT/tools/release/feed.py" "$ROOT/CHANGELOG.md" "$VERSION" "$FLOOR" "$ATTRIBUTES" "$FEED" "${NOTES:-}"
echo "$FEED"
