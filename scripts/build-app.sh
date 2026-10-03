#!/usr/bin/env bash
# Builds "Focus Timer.app" from the tree this script lives in. It only builds:
# nothing is installed or launched (that's scripts/release-local.sh).
#
#   scripts/build-app.sh            # -> build/Focus Timer.app
#   scripts/build-app.sh /some/dir  # -> /some/dir/Focus Timer.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build}"
APP="$OUT/Focus Timer.app"

echo "==> Compiling"
swift build -c release --package-path "$ROOT" --product FocusTimer
BIN="$(swift build -c release --package-path "$ROOT" --show-bin-path)/FocusTimer"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FocusTimer"

# The icon is drawn by the app itself, so there's no binary asset to keep in git.
ICON_DIR="$(mktemp -d -t focus-timer-icon)"
trap 'rm -rf "$ICON_DIR"' EXIT
"$BIN" --render-icon "$ICON_DIR/AppIcon.iconset"
iconutil -c icns "$ICON_DIR/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

# The in-app Update button compares this commit with origin/main and reruns
# release-local.sh from this checkout. Both are empty for a plain local build,
# which switches the button off.
PLIST="$APP/Contents/Info.plist"
cp "$ROOT/Support/Info.plist" "$PLIST"
plutil -insert FTBuildSHA -string "${FOCUS_TIMER_BUILD_SHA:-}" "$PLIST"
plutil -insert FTRepoPath -string "${FOCUS_TIMER_REPO_PATH:-}" "$PLIST"

# Apple Silicon refuses to run unsigned code; an ad-hoc signature is enough
# for an app that never leaves the machine it was built on.
codesign --force --sign - "$APP"

echo "==> Built $APP"
