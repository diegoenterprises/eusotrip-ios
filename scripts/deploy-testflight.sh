#!/usr/bin/env bash
# deploy-testflight.sh — one-shot Archive → Export → TestFlight upload
# for the EusoTrip iOS app.
#
# Usage:
#   ./scripts/deploy-testflight.sh
#
# Required env vars (set in your shell or a .env you `source` first):
#   ASC_API_KEY_ID       — App Store Connect API key id (e.g. ABC123XYZ)
#   ASC_API_KEY_ISSUER   — issuer UUID
#   ASC_API_KEY_PATH     — absolute path to AuthKey_<id>.p8
#
# The script keeps the marketing version + build number untouched —
# bump those in EusoTrip.xcodeproj/project.pbxproj manually before
# running (current: 1.0 / 204).

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE_PATH="${HOME}/Desktop/EusoTrip-1.0-204.xcarchive"
EXPORT_PATH="${HOME}/Desktop/EusoTrip-1.0-204-export"
EXPORT_OPTIONS="${PROJECT_ROOT}/scripts/exportOptions.testflight.plist"

require_env () {
  local v="$1"
  if [[ -z "${!v:-}" ]]; then
    echo "ERROR: env var $v is required (App Store Connect API credential)." >&2
    exit 1
  fi
}
require_env ASC_API_KEY_ID
require_env ASC_API_KEY_ISSUER
require_env ASC_API_KEY_PATH

cd "$PROJECT_ROOT"

# ── 1. Archive ───────────────────────────────────────────────────────
if [[ ! -d "$ARCHIVE_PATH" ]]; then
  echo "→ Archiving (Release · generic/iOS) …"
  xcodebuild \
    -project EusoTrip.xcodeproj \
    -scheme EusoTrip \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    archive
else
  echo "→ Archive already exists at $ARCHIVE_PATH (skipping)"
fi

# ── 2. Export .ipa ──────────────────────────────────────────────────
echo "→ Exporting .ipa for App Store Connect …"
rm -rf "$EXPORT_PATH"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath  "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

IPA_PATH="$(find "$EXPORT_PATH" -maxdepth 2 -name '*.ipa' | head -1)"
if [[ -z "$IPA_PATH" ]]; then
  echo "ERROR: No .ipa found under $EXPORT_PATH" >&2
  exit 1
fi
echo "→ Built .ipa: $IPA_PATH"

# ── 3. Upload to TestFlight ─────────────────────────────────────────
echo "→ Uploading to TestFlight via altool …"
xcrun altool \
  --upload-app \
  --type ios \
  --file "$IPA_PATH" \
  --apiKey "$ASC_API_KEY_ID" \
  --apiIssuer "$ASC_API_KEY_ISSUER" \
  --apple-id "" \
  --output-format xml || {
    echo "altool failed — falling back to xcrun notarytool style upload" >&2
    xcrun notarytool submit "$IPA_PATH" \
      --key "$ASC_API_KEY_PATH" \
      --key-id "$ASC_API_KEY_ID" \
      --issuer "$ASC_API_KEY_ISSUER" \
      --wait
  }

echo "✓ Upload complete. Build will appear in App Store Connect after Apple's
   processing pipeline finishes (usually 5-30 min). Watch:
   https://appstoreconnect.apple.com/apps"
