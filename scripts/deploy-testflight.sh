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
RELEASE_LADDER_PATH="${RELEASE_LADDER_PATH:-/tmp/eusotrip-release-ladder.json}"

LADDER_COMPILED="not_run"
LADDER_ARCHIVED="not_run"
LADDER_EXPORTED="not_run"
LADDER_UPLOADED="not_run"
LADDER_PROCESSING="manual_confirm_required"
LADDER_AVAILABLE="manual_confirm_required"

write_ladder () {
  mkdir -p "$(dirname "$RELEASE_LADDER_PATH")"
  printf '{\n' > "$RELEASE_LADDER_PATH"
  printf '  "compiled": "%s",\n' "$LADDER_COMPILED" >> "$RELEASE_LADDER_PATH"
  printf '  "archived": "%s",\n' "$LADDER_ARCHIVED" >> "$RELEASE_LADDER_PATH"
  printf '  "exported": "%s",\n' "$LADDER_EXPORTED" >> "$RELEASE_LADDER_PATH"
  printf '  "uploaded": "%s",\n' "$LADDER_UPLOADED" >> "$RELEASE_LADDER_PATH"
  printf '  "processing": "%s",\n' "$LADDER_PROCESSING" >> "$RELEASE_LADDER_PATH"
  printf '  "availableInTestFlight": "%s"\n' "$LADDER_AVAILABLE" >> "$RELEASE_LADDER_PATH"
  printf '}\n' >> "$RELEASE_LADDER_PATH"
}

mark_failed_step () {
  case "$1" in
    archive)
      LADDER_COMPILED="fail"
      LADDER_ARCHIVED="fail"
      ;;
    export)
      LADDER_EXPORTED="fail"
      ;;
    upload)
      LADDER_UPLOADED="fail"
      ;;
  esac
  write_ladder
}

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
  trap 'mark_failed_step archive' ERR
  xcodebuild \
    -project EusoTrip.xcodeproj \
    -scheme EusoTrip \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    archive
  trap - ERR
  LADDER_COMPILED="pass"
  LADDER_ARCHIVED="pass"
else
  echo "→ Archive already exists at $ARCHIVE_PATH (skipping)"
  LADDER_COMPILED="pass"
  LADDER_ARCHIVED="pass"
fi
write_ladder

# ── 2. Export .ipa ──────────────────────────────────────────────────
echo "→ Exporting .ipa for App Store Connect …"
rm -rf "$EXPORT_PATH"
trap 'mark_failed_step export' ERR
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath  "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates
trap - ERR
LADDER_EXPORTED="pass"
write_ladder

IPA_PATH="$(find "$EXPORT_PATH" -maxdepth 2 -name '*.ipa' | head -1)"
if [[ -z "$IPA_PATH" ]]; then
  mark_failed_step export
  echo "ERROR: No .ipa found under $EXPORT_PATH" >&2
  exit 1
fi
echo "→ Built .ipa: $IPA_PATH"

# ── 3. Upload to TestFlight ─────────────────────────────────────────
echo "→ Uploading to TestFlight via altool …"
trap 'mark_failed_step upload' ERR
xcrun altool \
  --upload-app \
  --type ios \
  --file "$IPA_PATH" \
  --apiKey "$ASC_API_KEY_ID" \
  --apiIssuer "$ASC_API_KEY_ISSUER" \
  --output-format xml
trap - ERR
LADDER_UPLOADED="pass"
write_ladder

echo "Upload complete. Release ladder written to $RELEASE_LADDER_PATH"
echo "Processing and TestFlight availability still require App Store Connect confirmation:"
echo "https://appstoreconnect.apple.com/apps"
