# Sparkle with the app-name rename

The website download of 4DSTEM Studio updates itself with [Sparkle](https://github.com/sparkle-project/Sparkle) (#122). Until
5.4.3 the app was mac4DSTEM.app. A fresh download is now `4DSTEM Studio.app` (#496), but stock Sparkle installs an update in
place, so a copy updated from an old release keeps the old file name (#497).

Sparkle has a build setting for this: `SPARKLE_NORMALIZE_INSTALLED_APPLICATION_NAME` in `Configurations/ConfigCommon.xcconfig`,
which is 0 upstream. Built with 1, its installer moves the updated app to `<SUBundleName>.app`. The app's `SUBundleName` is
"4DSTEM Studio" (`FourDSTEMStudio/Info-Direct.plist`).

An update is run by the installed app's own Sparkle installer. So the first release that carries this build renames nothing,
and every update after it renames the file. The bundle identifier, the feed and the user's settings stay as they are.

Electron Microscopy Studio does the same (its `Vendor/Sparkle`, #761) at the same Sparkle tag.

## What is here

- **`Sparkle.xcframework`:** Sparkle at the tag and commit in `tools/lib/sparkle-pin.sh`, built by
  `tools/release/build-sparkle.sh` with that one setting changed. It has no dSYMs and is signed ad hoc. Xcode signs the
  framework when it embeds it. `tools/release/build-developer-id.sh` checks that the download carries this build (by the
  helpers' Mach-O UUIDs), then signs each helper with the Developer ID.
  - The framework in this folder was built by Electron Microscopy Studio's public run of the same script, pin and Xcode.
    `build-info.txt` names that run. `.github/workflows/sparkle.yml` here rebuilds it on any branch that changes the pin.
- **`build-info.txt`:** the tag, the commit, the setting, the Xcode, the workflow run that built it, and the SHA-256 of every
  file in the framework. `tools/run-tests.sh inventory` checks it against the tree, the pin and NOTICE.
- **`Package.swift`:** a local package. The Xcode project links its one product, `Sparkle`, in place of the remote package.

`tools/release/appcast.sh` signs the DMG with `sign_update`, taken from the same tag's official Swift Package Manager zip
(its checksum is in the pin).

## Rebuild (a new Sparkle tag)

1. In `tools/lib/sparkle-pin.sh`, change the tag, the commit, and the zip checksum from Sparkle's `Package.swift` at that tag.
2. Change the tag and commit in NOTICE.
3. Push the branch. `.github/workflows/sparkle.yml` builds the framework on GitHub's macOS runner. Because the pin is new, it
   commits `Sparkle.xcframework` and `build-info.txt` here on that branch, with the run's URL in the message.
4. Pull that commit and open the pull request as usual.

`tools/release/build-sparkle.sh` also runs on a Mac with Xcode. Its `build-info.txt` then says "built locally".

## Going back to stock Sparkle

Sparkle's note on the setting is to turn it off once the rename is done. Do that when the releases that rename have been out
long enough (an issue tracks it):

1. Point the project back at `https://github.com/sparkle-project/Sparkle`, up to the next major from the tag.
2. Delete this folder, `tools/release/build-sparkle.sh`, `tools/lib/sparkle-pin.sh` and `.github/workflows/sparkle.yml`.
3. In `tools/release/appcast.sh`, take `sign_update` from `build/SourcePackages/artifacts/sparkle/Sparkle/bin` again.
4. Drop the Sparkle section of `tools/run-tests.sh inventory`, and the UUID check in `tools/release/build-developer-id.sh`.
