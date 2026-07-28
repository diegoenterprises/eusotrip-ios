#!/usr/bin/env bash
# Archive, export, and upload EusoTrip to TestFlight with an App Store
# Connect API key. Build products stay outside the synced workspace.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPORT_OPTIONS="${PROJECT_ROOT}/scripts/exportOptions.testflight.plist"
RELEASE_LADDER_PATH="${RELEASE_LADDER_PATH:-/tmp/eusotrip-release-ladder.json}"

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "ERROR: env var ${name} is required." >&2
    exit 1
  fi
}

require_env ASC_API_KEY_ID
require_env ASC_API_KEY_ISSUER
require_env ASC_API_KEY_PATH

EXPECTED_KEY_NAME="AuthKey_${ASC_API_KEY_ID}.p8"
if [[ "$(basename "$ASC_API_KEY_PATH")" != "$EXPECTED_KEY_NAME" ]]; then
  echo "ERROR: ASC_API_KEY_PATH must end in ${EXPECTED_KEY_NAME}." >&2
  exit 1
fi
if [[ ! -r "$ASC_API_KEY_PATH" ]]; then
  echo "ERROR: ASC_API_KEY_PATH is not readable." >&2
  exit 1
fi

cd "$PROJECT_ROOT"

BUILD_SETTINGS="$(xcodebuild -project EusoTrip.xcodeproj -scheme EusoTrip -configuration Release -showBuildSettings)"
VERSION="${RELEASE_VERSION:-$(awk '/MARKETING_VERSION =/ { print $3; exit }' <<<"$BUILD_SETTINGS")}"
BUILD_NUMBER="${RELEASE_BUILD_NUMBER:-$(awk '/CURRENT_PROJECT_VERSION =/ { print $3; exit }' <<<"$BUILD_SETTINGS")}"
if [[ -z "$VERSION" || -z "$BUILD_NUMBER" ]]; then
  echo "ERROR: Unable to resolve MARKETING_VERSION/CURRENT_PROJECT_VERSION." >&2
  exit 1
fi

RELEASE_ROOT="${RELEASE_ROOT:-$(mktemp -d "/tmp/eusotrip-testflight-${VERSION}-${BUILD_NUMBER}-XXXXXX")}"
DERIVED_DATA_PATH="${RELEASE_ROOT}/DerivedData"
ARCHIVE_PATH="${RELEASE_ROOT}/EusoTrip-${VERSION}-${BUILD_NUMBER}.xcarchive"
EXPORT_PATH="${RELEASE_ROOT}/export"

LADDER_COMPILED="not_run"
LADDER_ARCHIVED="not_run"
LADDER_EXPORTED="not_run"
LADDER_UPLOADED="not_run"
LADDER_PROCESSING="pending"
LADDER_AVAILABLE="pending"

write_ladder() {
  mkdir -p "$(dirname "$RELEASE_LADDER_PATH")"
  cat > "$RELEASE_LADDER_PATH" <<JSON
{
  "version": "${VERSION}",
  "build": "${BUILD_NUMBER}",
  "releaseRoot": "${RELEASE_ROOT}",
  "archivePath": "${ARCHIVE_PATH}",
  "compiled": "${LADDER_COMPILED}",
  "archived": "${LADDER_ARCHIVED}",
  "exported": "${LADDER_EXPORTED}",
  "uploaded": "${LADDER_UPLOADED}",
  "processing": "${LADDER_PROCESSING}",
  "availableInTestFlight": "${LADDER_AVAILABLE}"
}
JSON
}

mark_failed_step() {
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

write_ladder
echo "Release ${VERSION} (${BUILD_NUMBER})"
echo "Release workspace: ${RELEASE_ROOT}"

trap 'mark_failed_step archive' ERR
xcodebuild \
  -project EusoTrip.xcodeproj \
  -scheme EusoTrip \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -archivePath "$ARCHIVE_PATH" \
  -authenticationKeyPath "$ASC_API_KEY_PATH" \
  -authenticationKeyID "$ASC_API_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_API_KEY_ISSUER" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  MARKETING_VERSION="$VERSION" \
  archive
trap - ERR
LADDER_COMPILED="pass"
LADDER_ARCHIVED="pass"

ARCHIVED_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$ARCHIVE_PATH/Info.plist")"
ARCHIVED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$ARCHIVE_PATH/Info.plist")"
if [[ "$ARCHIVED_BUILD" != "$BUILD_NUMBER" || "$ARCHIVED_VERSION" != "$VERSION" ]]; then
  mark_failed_step archive
  echo "ERROR: Archive contains ${ARCHIVED_VERSION} (${ARCHIVED_BUILD}), expected ${VERSION} (${BUILD_NUMBER})." >&2
  exit 1
fi
write_ladder

trap 'mark_failed_step export' ERR
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -authenticationKeyPath "$ASC_API_KEY_PATH" \
  -authenticationKeyID "$ASC_API_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_API_KEY_ISSUER" \
  -allowProvisioningUpdates
trap - ERR
LADDER_EXPORTED="pass"
write_ladder

IPA_PATH="$(find "$EXPORT_PATH" -maxdepth 2 -name '*.ipa' -print -quit)"
if [[ -z "$IPA_PATH" ]]; then
  mark_failed_step export
  echo "ERROR: No IPA was exported." >&2
  exit 1
fi

trap 'mark_failed_step upload' ERR
API_PRIVATE_KEYS_DIR="$(dirname "$ASC_API_KEY_PATH")" xcrun altool \
  --upload-app \
  --type ios \
  --file "$IPA_PATH" \
  --apiKey "$ASC_API_KEY_ID" \
  --apiIssuer "$ASC_API_KEY_ISSUER" \
  --output-format json
trap - ERR
LADDER_UPLOADED="pass"
write_ladder

echo "Upload accepted. Poll App Store Connect before calling the build available."
echo "Release ladder: ${RELEASE_LADDER_PATH}"
