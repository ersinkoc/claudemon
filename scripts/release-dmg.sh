#!/usr/bin/env bash
#
# release-dmg.sh — produce a distributable, Developer ID signed + notarized +
# stapled Claudemon.dmg for sharing outside the App Store.
#
# Pipeline:
#   1. XcodeGen generate + xcodebuild Release (codesigning OFF at build time)
#   2. Sign inside-out with Developer ID, Hardened Runtime + secure timestamp,
#      per-target entitlements: framework -> widget appex -> app
#   3. Verify signatures (codesign --verify --deep --strict)
#   4. Notarize the .app (notarytool submit --wait), staple, validate
#   5. Build a drag-to-install DMG, sign it, notarize + staple the DMG
#   6. Gatekeeper assessment (spctl)
#
# Requirements (already set up on the build machine):
#   - Developer ID Application identity in the keychain (team 3QKMW9HR59)
#   - A notarytool keychain profile (default name: "claudemon")
#
set -euo pipefail

# --- Config -----------------------------------------------------------------
APP_NAME="Claudemon"
WIDGET_NAME="ClaudemonWidget"
SCHEME="Claudemon"
CONFIG="Release"

DEV_ID="Developer ID Application: Arda Balkan (3QKMW9HR59)"
TEAM_ID="3QKMW9HR59"
NOTARY_PROFILE="${NOTARY_PROFILE:-claudemon}"

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

DIST_DIR="${ROOT_DIR}/dist"
DMG_PATH="${DIST_DIR}/${APP_NAME}.dmg"

log() { echo ""; echo "==> $*"; }

# --- 1. Generate + build ----------------------------------------------------
if ! command -v xcodegen >/dev/null 2>&1; then
  command -v brew >/dev/null 2>&1 && brew install xcodegen \
    || { echo "ERROR: xcodegen + brew unavailable" >&2; exit 1; }
fi

log "Generating ${APP_NAME}.xcodeproj"
xcodegen generate

log "Building ${SCHEME} (${CONFIG}, codesigning off)"
rm -rf "${DD}"
xcodebuild \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIG}" \
  -derivedDataPath "${DD}" \
  build | tail -n 3

[[ -d "${APP_BUNDLE}" ]] || { echo "ERROR: app not found at ${APP_BUNDLE}" >&2; exit 1; }
[[ -d "${APPEX}" ]] || { echo "ERROR: widget appex not embedded" >&2; exit 1; }

# --- 2. Sign inside-out (Developer ID, hardened runtime, timestamp) ---------
log "Signing framework"
codesign --force --options runtime --timestamp \
  --sign "${DEV_ID}" "${FRAMEWORK}"

log "Signing widget appex (with entitlements)"
codesign --force --options runtime --timestamp \
  --entitlements "${WIDGET_ENTITLEMENTS}" \
  --sign "${DEV_ID}" "${APPEX}"

log "Signing app (with entitlements)"
codesign --force --options runtime --timestamp \
  --entitlements "${APP_ENTITLEMENTS}" \
  --sign "${DEV_ID}" "${APP_BUNDLE}"

# --- 3. Verify --------------------------------------------------------------
log "Verifying signatures"
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
codesign -dvvv "${APP_BUNDLE}" 2>&1 | grep -E "Authority|TeamIdentifier|Identifier|Timestamp|flags" || true

# --- 4. Notarize the app ----------------------------------------------------
log "Zipping app for notarization"
mkdir -p "${DIST_DIR}"
APP_ZIP="${DIST_DIR}/${APP_NAME}-app.zip"
rm -f "${APP_ZIP}"
ditto -c -k --keepParent "${APP_BUNDLE}" "${APP_ZIP}"

log "Submitting app to notarytool (this can take a minute)"
xcrun notarytool submit "${APP_ZIP}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait

log "Stapling app"
xcrun stapler staple "${APP_BUNDLE}"
xcrun stapler validate "${APP_BUNDLE}"

# --- 5. Build, sign, notarize, staple the DMG -------------------------------
log "Building drag-to-install DMG"
STAGE="${DIST_DIR}/dmg-stage"
rm -rf "${STAGE}" "${DMG_PATH}"
mkdir -p "${STAGE}"
cp -R "${APP_BUNDLE}" "${STAGE}/"
ln -s /Applications "${STAGE}/Applications"

hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGE}" \
  -ov -format UDZO \
  "${DMG_PATH}"

log "Signing DMG"
codesign --force --timestamp --sign "${DEV_ID}" "${DMG_PATH}"

log "Notarizing DMG"
xcrun notarytool submit "${DMG_PATH}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait

log "Stapling DMG"
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"

# --- 6. Gatekeeper assessment ----------------------------------------------
log "Gatekeeper assessment"
echo "--- app ---"
spctl -a -vvv "${APP_BUNDLE}" || true
echo "--- dmg (install) ---"
spctl -a -vvv -t install "${DMG_PATH}" || true

rm -rf "${STAGE}" "${APP_ZIP}"

echo ""
echo "==> Done."
echo "    Distributable: ${DMG_PATH}"
