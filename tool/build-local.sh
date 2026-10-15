#!/usr/bin/env bash
#
# Builds a signed release APK and leaves it in dist/ for manual installation —
# over a cable, or by copying the file to the phone. No Firebase involved.
#
# This exists for the moments App Distribution can't cover: a first install
# after a signing-key change (which needs an uninstall first), a phone that
# isn't an invited tester, or no network.
#
# Usage:  tool/build-local.sh              # build, copy to dist/
#         tool/build-local.sh --install    # also adb install to the phone
#         tool/build-local.sh --no-build   # just copy the APK already built
#         tool/build-local.sh --bridge     # DEBUG-signed build (see below)
#
# --bridge deliberately builds with the debug signature, which is the only
# thing that can update an app installed before the real keystore existed.
# Use it once, to get the export feature onto a phone holding data you want
# out. It is a stepping stone, not something to distribute: it cannot be
# updated by a properly signed build afterwards.
set -euo pipefail

cd "$(dirname "$0")/.."

BUILD=1
INSTALL=0
BRIDGE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --install)  INSTALL=1 ;;
    --no-build) BUILD=0 ;;
    --bridge)   BRIDGE=1 ;;
    -h|--help)  sed -n '2,/^set /p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ "$BRIDGE" = 1 ]; then
  # Hide the keystore so gradle takes its debug-signing fallback. Restored on
  # any exit, including a failed build or Ctrl-C — losing it would be worse
  # than a failed build.
  if [ -f android/key.properties ]; then
    trap 'mv -f android/key.properties.bridge-hidden android/key.properties 2>/dev/null || true' EXIT INT TERM
    mv android/key.properties android/key.properties.bridge-hidden
  fi
  echo "→ BRIDGE build: debug-signed on purpose, so it can update the old install"
else
  # Same guard as ship.sh: without the keystore this silently produces a
  # debug-signed APK that can never update a real install.
  if [ ! -f android/key.properties ]; then
    echo "android/key.properties is missing — this build would be debug-signed" >&2
    echo "and could not update any install made with the real key." >&2
    exit 1
  fi
fi

APK="build/app/outputs/flutter-apk/app-release.apk"

if [ "$BUILD" = 1 ]; then
  echo "→ flutter build apk --release"
  flutter build apk --release
fi

[ -f "$APK" ] || { echo "no APK at $APK" >&2; exit 1; }

NAME=$(sed -n 's/^name: *//p' pubspec.yaml | tr -d '[:space:]')
VERSION=$(sed -n 's/^version: *//p' pubspec.yaml | tr -d '[:space:]')
SHA=$(git rev-parse --short HEAD 2>/dev/null || echo nogit)

mkdir -p dist
if [ "$BRIDGE" = 1 ]; then
  OUT="dist/${NAME}-${VERSION}-${SHA}-BRIDGE-debugsigned.apk"
else
  OUT="dist/${NAME}-${VERSION}-${SHA}.apk"
fi
cp "$APK" "$OUT"

# Prove which key signed it rather than trusting the build. CN=Android Debug
# means the fallback fired and the guard above was somehow bypassed.
APKSIGNER=$(ls ~/Library/Android/sdk/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)
if [ -n "$APKSIGNER" ]; then
  CERT=$("$APKSIGNER" verify --print-certs "$OUT" 2>/dev/null \
         | sed -n 's/^Signer #1 certificate DN: //p')
  echo "→ signed by: ${CERT:-unknown}"
  case "$CERT" in
    *"Android Debug"*)
      if [ "$BRIDGE" = 0 ]; then
        echo "refusing: this APK is debug-signed." >&2; rm -f "$OUT"; exit 1
      fi ;;
    *)
      if [ "$BRIDGE" = 1 ]; then
        echo "refusing: --bridge produced a real-key APK, which cannot update" >&2
        echo "the old install. The keystore was not hidden as intended." >&2
        rm -f "$OUT"; exit 1
      fi ;;
  esac
else
  echo "→ apksigner not found; signature unverified" >&2
fi

echo "→ ${OUT}  ($(du -h "$OUT" | cut -f1))"

if [ "$INSTALL" = 1 ]; then
  command -v adb >/dev/null || { echo "adb not found" >&2; exit 1; }
  echo "→ adb install -r ${OUT}"
  # -r keeps the app's data. It fails on a signature mismatch rather than
  # wiping anything, which is the outcome you want: uninstall is your call.
  if ! adb install -r "$OUT"; then
    echo >&2
    echo "Install failed. If this says INSTALL_FAILED_UPDATE_INCOMPATIBLE the" >&2
    echo "phone holds a build signed with a different key (the old debug one)." >&2
    echo "Export your data from Settings → Data first, then:" >&2
    echo "  adb uninstall com.tedif.weight_buddy && tool/build-local.sh --no-build --install" >&2
    exit 1
  fi
fi
