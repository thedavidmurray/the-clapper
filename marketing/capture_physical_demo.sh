#!/bin/bash
set -euo pipefail

# Clapper physical device demo recorder
# Usage: ./capture_physical_demo.sh [output_filename]
# Default: Clapper_PhysicalDevice_Demo_$(date +%Y%m%d-%H%M).mov

OUTPUT="${1:-Clapper_PhysicalDevice_Demo_$(date +%Y%m%d-%H%M).mov}"
DURATION=${2:-90}  # seconds, max 120 per requirements
DEVICE="72E8237A-7DC8-5B68-91BF-AB49E0A5F930"  # Wavy Javy iPhone 14 Pro

# Verify device connection
echo "Checking device connection..."
xcrun devicectl list devices 2>/dev/null | grep -q "Wavy Javy.*available" || {
  echo "ERROR: Device 'Wavy Javy' not available or not connected."
  echo "1. Connect iPhone via USB"
  echo "2. Unlock device and tap 'Trust'"
  echo "3. Wait for 'available' status"
  exit 1
}

# Check screen recording capability
echo "Checking screen recording entitlement..."
xcrun devicectl device info devices "$DEVICE" 2>/dev/null | grep -q "ScreenRecording" || {
  echo "WARNING: Screen recording may require explicit entitlement check"
}

echo "Starting recording on device: $DEVICE"
echo "Duration: $DURATION seconds"
echo "Output: $OUTPUT"
echo ""
echo "MANUAL STEPS REQUIRED:"
echo "1. On device: Open Control Center -> Screen Recording -> Start"
echo "2. Launch The Clapper app"
echo "3. Follow shot list in clapper-physical-demo-episode.md"
echo "4. After recording, save to Photos"
echo "5. Press ENTER here when done..."
read -r

echo "Transferring recording from device..."
# xcrun devicectl device file system list would show paths, but Photos requires MediaStore
# Direct approach: user exports via AirDrop/Share to Mac
# Alternative: xcrun simctl on simulator (not valid for Apple review)

echo ""
echo "AFTER RECORDING:"
echo "1. Export to Mac via AirDrop/Image Capture/Photos app"
echo "2. Compress if > 500MB:"
echo "   ffmpeg -i input.mov -c copy -movflags faststart $OUTPUT"
echo "3. Upload to Google Drive (unlisted) or YouTube (unlisted)"
echo "4. Update EDGA-8501 comment with link"

# Verify output
if [[ -f "$OUTPUT" ]]; then
  SIZE=$(du -h "$OUTPUT" | cut -f1)
  echo "Output: $OUTPUT ($SIZE)"
else
  echo "Output file not found. Complete recording transfer manually."
fi
