#!/usr/bin/env bash
#
# build-xcode.sh — generate the Xcode project (via XcodeGen), build the app +
# embedded WidgetKit extension in Release, and ad-hoc sign both with their
# App-Group entitlements so they run locally.
#
# Usage:  ./scripts/build-xcode.sh
#
# NOTE on signing/distribution:
#   App-Group entitlements + a notarized build require a paid Apple Developer
#   account (a real Team ID; the group must be registered on the portal). For
#   LOCAL use, an ad-hoc signature WITH the entitlements files is sufficient —
#   that is what this script does. For distribution, replace the ad-hoc identity
#   ("-") with a "Developer ID Application: <NAME> (<TEAMID>)" identity, add
#   --options runtime --timestamp, then notarize + staple (see TODO below).
#
set -euo pipefail

APP_NAME="Claudemon"
WIDGET_NAME="ClaudemonWidget"
SCHEME="Claudemon"
CONFIG="Release"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

DD="${ROOT_DIR}/build/dd"
PRODUCTS="${DD}/Build/Products/${CONFIG}"
APP_BUNDLE="${PRODUCTS}/${APP_NAME}.app"
APPEX="${APP_BUNDLE}/Contents/PlugIns/${WIDGET_NAME}.appex"
FRAMEWORK="${APP_BUNDLE}/Contents/Frameworks/${APP_NAME}Core.framework"

APP_ENTITLEMENTS="${ROOT_DIR}/Support/${APP_NAME}.entitlements"
WIDGET_ENTITLEMENTS="${ROOT_DIR}/Support/${WIDGET_NAME}.entitlements"

# --- Ensure the Xcode project exists (XcodeGen) -----------------------------
if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "==> Installing XcodeGen via Homebrew…"
    brew install xcodegen
  else
    echo "ERROR: xcodegen not found and Homebrew unavailable." >&2
    echo "       Install XcodeGen: https://github.com/yonaskolb/XcodeGen" >&2
    exit 1
  fi
fi

echo "==> Generating ${APP_NAME}.xcodeproj…"
xcodegen generate

# --- Build ------------------------------------------------------------------
echo "==> Building ${SCHEME} (${CONFIG})…"
rm -rf "${DD}"
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIG}" \
  -derivedDataPath "${DD}" \
  build | tail -n 3

if [[ ! -d "${APP_BUNDLE}" ]]; then
  echo "ERROR: app bundle not found at ${APP_BUNDLE}" >&2
  exit 1
fi
if [[ ! -d "${APPEX}" ]]; then
  echo "ERROR: widget appex not embedded at ${APPEX}" >&2
  exit 1
fi

# --- Ad-hoc sign (inside-out: framework, appex, then app) -------------------
# Each code-bearing bundle is signed; the appex/app carry their entitlements.
echo "==> Ad-hoc signing (framework → appex → app)…"
if [[ -d "${FRAMEWORK}" ]]; then
  codesign --force --sign - "${FRAMEWORK}"
fi
codesign --force --sign - --entitlements "${WIDGET_ENTITLEMENTS}" "${APPEX}"
codesign --force --sign - --entitlements "${APP_ENTITLEMENTS}" "${APP_BUNDLE}"

echo "==> Verifying signatures…"
codesign --verify --verbose "${APP_BUNDLE}" || true

# TODO (requires paid Apple Developer account + registered App Group):
#   codesign --force --options runtime --timestamp \
#     --entitlements "${WIDGET_ENTITLEMENTS}" \
#     --sign "Developer ID Application: <NAME> (<TEAMID>)" "${APPEX}"
#   codesign --force --options runtime --timestamp \
#     --entitlements "${APP_ENTITLEMENTS}" \
#     --sign "Developer ID Application: <NAME> (<TEAMID>)" "${APP_BUNDLE}"
#   ditto -c -k --keepParent "${APP_BUNDLE}" "${APP_NAME}.zip"
#   xcrun notarytool submit "${APP_NAME}.zip" --keychain-profile "<PROFILE>" --wait
#   xcrun stapler staple "${APP_BUNDLE}"

echo ""
echo "==> Done."
echo "    App bundle: ${APP_BUNDLE}"
echo "    Widget:     ${APPEX}"
echo "    Run with:   open \"${APP_BUNDLE}\""
