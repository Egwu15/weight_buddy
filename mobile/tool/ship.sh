#!/usr/bin/env bash
#
# Builds an APK and pushes it to Firebase App Distribution, so the phone can
# install it from the App Tester app instead of over a cable.
#
# Usage:  tool/ship.sh                    # release build, upload
#         tool/ship.sh --debug            # debug build instead
#         tool/ship.sh --no-build         # ship the APK that's already there
#         tool/ship.sh --archive          # also attach to a GitHub Release
#         tool/ship.sh -m "what changed"  # release note (default: last commit)
#
# App ID from tool/.firebase-app-id or FIREBASE_APP_ID. Group from SHIP_GROUPS.
set -euo pipefail

cd "$(dirname "$0")/.."

FLAVOUR=release
BUILD=1
ARCHIVE=0
MESSAGE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --debug)    FLAVOUR=debug ;;
    --release)  FLAVOUR=release ;;
    --no-build) BUILD=0 ;;
    --archive)  ARCHIVE=1 ;;
    -m|--notes) shift; MESSAGE="${1:-}"
                [ -n "$MESSAGE" ] || { echo "-m needs a message" >&2; exit 2; } ;;
    -h|--help)  sed -n '2,/^set /p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

APP_ID="${FIREBASE_APP_ID:-$(cat tool/.firebase-app-id 2>/dev/null || true)}"
[ -n "$APP_ID" ] || {
  echo "no Firebase App ID. Put it in tool/.firebase-app-id or set FIREBASE_APP_ID." >&2
  exit 1; }

command -v firebase >/dev/null || {
  echo "firebase CLI not found. Run: npm i -g firebase-tools && firebase login" >&2; exit 1; }

# The keystore is gitignored, so its absence is silent and the fallback is a
# debug signature that can never update a real install.
if [ "$FLAVOUR" = release ] && [ ! -f android/key.properties ]; then
  echo "android/key.properties is missing — a release build here would be" >&2
  echo "debug-signed and could not update any install made with the real key." >&2
  exit 1
fi

APK="build/app/outputs/flutter-apk/app-${FLAVOUR}.apk"

if [ "$BUILD" = 1 ]; then
  echo "→ flutter build apk --${FLAVOUR}"
  flutter build apk "--${FLAVOUR}"
fi

[ -f "$APK" ] || { echo "no APK at $APK" >&2; exit 1; }

NAME=$(sed -n 's/^name: *//p' pubspec.yaml | tr -d '[:space:]')
VERSION=$(sed -n 's/^version: *//p' pubspec.yaml | tr -d '[:space:]')
SHA=$(git rev-parse --short HEAD 2>/dev/null || echo nogit)
DIRTY=$(git diff --quiet 2>/dev/null || echo " (dirty)")
NOTES="${VERSION} · ${SHA}${DIRTY} · ${MESSAGE:-$(git log -1 --pretty=%s 2>/dev/null)}"

echo "→ ${APK}  ($(du -h "$APK" | cut -f1))"
echo "→ ${NOTES}"
# Without a group the upload succeeds but reaches nobody, which looks like
# success and isn't. Override with SHIP_GROUPS to send it somewhere else.
firebase appdistribution:distribute "$APK" \
  --app "$APP_ID" \
  --release-notes "$NOTES" \
  --groups "${SHIP_GROUPS:-me}"

# Firebase drops releases after 150 days; a GitHub Release does not expire.
if [ "$ARCHIVE" = 1 ]; then
  TAG="build-${VERSION}-${SHA}"
  ASSET="${NAME}-${VERSION}-${SHA}-${FLAVOUR}.apk"
  cp "$APK" "/tmp/${ASSET}"
  echo "→ archiving as GitHub Release ${TAG}"
  gh release create "$TAG" "/tmp/${ASSET}" --title "$TAG" --notes "$NOTES" 2>/dev/null \
    || gh release upload "$TAG" "/tmp/${ASSET}" --clobber
  rm -f "/tmp/${ASSET}"
fi
