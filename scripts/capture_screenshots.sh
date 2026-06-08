#!/bin/zsh
# Capture App Store screenshots for The Clapper.
#
# Strategy: build a fresh sim .app, boot the target sim, install, launch,
# then prompt the operator to navigate to each scene and hit return.
# Saves to fastlane/screenshots/<lang>/<device-id>_<NN>_<name>.png at native
# device resolution (App Store-ready, no resize).
#
# Required ASC device classes (2026):
#   - iPhone 6.9" (iPhone 16 Pro Max)  1320x2868
#   - iPad 13"   (iPad Pro 13" M4)     2064x2752
#
# Usage:
#   ./scripts/capture_screenshots.sh                # both devices
#   ./scripts/capture_screenshots.sh iphone         # iPhone only
#   ./scripts/capture_screenshots.sh ipad           # iPad only

set -e
cd "$(dirname "$0")/.."

BUNDLE_ID="com.edgeless.theclapper"
SCHEME="TheClapper"
LANG="en-US"
OUT_BASE="fastlane/screenshots/${LANG}"

mkdir -p "${OUT_BASE}"

# Pick first booted-able device for each class. simctl names can have multiple
# OS-runtime instances; we just take the first match.
IPHONE_SIM=$(xcrun simctl list devices available | grep "iPhone 16 Pro Max" | head -1 | grep -oE "\([A-F0-9-]{36}\)" | tr -d '()')
IPAD_SIM=$(xcrun simctl list devices available | grep "iPad Pro 13-inch (M4)" | head -1 | grep -oE "\([A-F0-9-]{36}\)" | tr -d '()')

[ -z "$IPHONE_SIM" ] && { echo "No iPhone 16 Pro Max simulator found"; exit 1; }
[ -z "$IPAD_SIM" ]   && { echo "No iPad Pro 13-inch M4 simulator found"; exit 1; }

# The shots we want, in order. Operator navigates to each, then hits Return.
SHOTS=(
  "01_home_listening:Home tab, microphone permission granted, tap 'Start Listening', waveform animating"
  "02_gesture_detected:Home tab, just after a clap is detected (gesture badge visible)"
  "03_camera_preview:Camera tab, live preview, no recording"
  "04_camera_recording:Camera tab, recording active (red indicator + timer)"
  "05_settings_mapping:Settings tab, gesture-to-action mapping list visible"
  "06_settings_advanced:Settings tab, scrolled to advanced/threshold sliders"
)

capture_device() {
  local SIM_UDID=$1
  local LABEL=$2
  echo ""
  echo "=========================================="
  echo "Device: ${LABEL}  (${SIM_UDID})"
  echo "=========================================="

  echo "Booting simulator..."
  xcrun simctl boot "${SIM_UDID}" 2>/dev/null || true
  open -a Simulator

  echo "Building app for simulator..."
  xcodebuild -hide_banner -quiet \
    -project TheClapper.xcodeproj \
    -scheme "${SCHEME}" \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination "id=${SIM_UDID}" \
    -derivedDataPath build/sim-${SIM_UDID:0:8} \
    build

  APP_PATH=$(find "build/sim-${SIM_UDID:0:8}/Build/Products/Debug-iphonesimulator" -name "TheClapper.app" -type d | head -1)
  [ -z "$APP_PATH" ] && { echo "Built .app not found"; exit 1; }

  echo "Installing ${APP_PATH}..."
  xcrun simctl install "${SIM_UDID}" "${APP_PATH}"

  echo "Granting privacy permissions (mic + camera + photo-add)..."
  xcrun simctl privacy "${SIM_UDID}" grant microphone "${BUNDLE_ID}" 2>/dev/null || true
  xcrun simctl privacy "${SIM_UDID}" grant camera     "${BUNDLE_ID}" 2>/dev/null || true
  xcrun simctl privacy "${SIM_UDID}" grant photos     "${BUNDLE_ID}" 2>/dev/null || true

  echo "Launching app..."
  xcrun simctl launch "${SIM_UDID}" "${BUNDLE_ID}"

  for entry in "${SHOTS[@]}"; do
    local name="${entry%%:*}"
    local hint="${entry##*:}"
    local out="${OUT_BASE}/${SIM_UDID:0:8}_${name}.png"
    echo ""
    echo "  --> ${name}"
    echo "      Hint: ${hint}"
    echo "      Navigate the simulator now, then press Return to capture."
    read -r _
    xcrun simctl io "${SIM_UDID}" screenshot "${out}"
    echo "      Saved: ${out}"
  done

  echo ""
  echo "Done with ${LABEL}."
}

case "${1:-both}" in
  iphone) capture_device "${IPHONE_SIM}" "iPhone 16 Pro Max" ;;
  ipad)   capture_device "${IPAD_SIM}"   "iPad Pro 13-inch" ;;
  both)
    capture_device "${IPHONE_SIM}" "iPhone 16 Pro Max"
    capture_device "${IPAD_SIM}"   "iPad Pro 13-inch"
    ;;
  *)
    echo "Usage: $0 [iphone|ipad|both]"
    exit 1
    ;;
esac

echo ""
echo "All captures in ${OUT_BASE}/"
ls -la "${OUT_BASE}/" | grep -v '^total'
