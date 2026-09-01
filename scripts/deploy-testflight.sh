#!/usr/bin/env bash
# Archive, export, and upload EusoTrip to TestFlight with an App Store
# Connect API key. Build products stay outside the synced workspace.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPORT_OPTIONS="${PROJECT_ROOT}/scripts/exportOptions.testflight.plist"

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
require_env HERE_OFFLINE_EXPECTED_TEAM_ID
require_env HERE_OFFLINE_EXPECTED_SIGNING_AUTHORITY
require_env EUSOTRIP_APPROVED_RELEASE_COMMIT
require_env EUSOTRIP_RELEASE_XCCONFIG_PATH
require_env EUSOTRIP_RELEASE_CONFIG_ATTESTATION_PATH
require_env GITHUB_TOKEN

cd "$PROJECT_ROOT"

if [[ -e "${PROJECT_ROOT}/EusoTrip.xcconfig" || -L "${PROJECT_ROOT}/EusoTrip.xcconfig" ]]; then
  echo "ERROR: Release refuses the ignored workspace EusoTrip.xcconfig; use the protected external release config." >&2
  exit 1
fi

canonical_private_file() {
  local candidate="$1"
  local label="$2"
  if [[ "$candidate" != /* || ! -f "$candidate" || -L "$candidate" ]]; then
    echo "ERROR: ${label} must be one absolute regular non-symlink file." >&2
    exit 1
  fi
  local directory
  directory="$(cd "$(dirname "$candidate")" && pwd -P)"
  local resolved="${directory}/$(basename "$candidate")"
  local owner mode directory_owner directory_mode
  owner="$(stat -f '%u' "$resolved")"
  mode="$(stat -f '%Lp' "$resolved")"
  directory_owner="$(stat -f '%u' "$directory")"
  directory_mode="$(stat -f '%Lp' "$directory")"
  if [[ "$owner" != "$(id -u)" || "$directory_owner" != "$(id -u)" ]] ||
     (( (8#$mode & 8#077) != 0 || (8#$directory_mode & 8#077) != 0 )); then
    echo "ERROR: ${label} and its directory must be release-user-owned with no group/other access." >&2
    exit 1
  fi
  if [[ "$resolved" == "$PROJECT_ROOT"/* ]]; then
    echo "ERROR: ${label} must be supplied outside the source worktree." >&2
    exit 1
  fi
  printf '%s\n' "$resolved"
}

ASC_API_KEY_PATH="$(canonical_private_file "$ASC_API_KEY_PATH" "App Store Connect private key")"
ASC_KEY_ID_VALUE="$ASC_API_KEY_ID" \
ASC_ISSUER_VALUE="$ASC_API_KEY_ISSUER" \
ASC_KEY_PATH_VALUE="$ASC_API_KEY_PATH" \
ASC_VALIDATOR_MODULE="${PROJECT_ROOT}/scripts/asc-latest-build.mjs" \
  node --input-type=module <<'NODE'
import { pathToFileURL } from "node:url";
const { validateKeyConfiguration } = await import(pathToFileURL(process.env.ASC_VALIDATOR_MODULE));
validateKeyConfiguration({
  keyId: process.env.ASC_KEY_ID_VALUE,
  issuerId: process.env.ASC_ISSUER_VALUE,
  privateKeyPath: process.env.ASC_KEY_PATH_VALUE,
});
NODE

RELEASE_XCCONFIG_PATH="$(canonical_private_file "$EUSOTRIP_RELEASE_XCCONFIG_PATH" "release xcconfig")"
RELEASE_CONFIG_ATTESTATION_PATH="$(canonical_private_file "$EUSOTRIP_RELEASE_CONFIG_ATTESTATION_PATH" "release config attestation")"
RELEASE_CONFIG_ATTESTATION_SHA256="$(
  node "${PROJECT_ROOT}/scripts/verify-release-config-attestation.mjs" \
    --file="$RELEASE_CONFIG_ATTESTATION_PATH" \
    --xcconfig="$RELEASE_XCCONFIG_PATH" \
    --expected-team="$HERE_OFFLINE_EXPECTED_TEAM_ID"
)"
RELEASE_XCCONFIG_SHA256="$(node "${PROJECT_ROOT}/scripts/hash-release-artifact.mjs" --path="$RELEASE_XCCONFIG_PATH")"

private_file_snapshot() {
  local candidate="$1"
  {
    stat -f '%d:%i:%z:%m:%u:%Lp' "$candidate"
    /usr/bin/shasum -a 256 "$candidate" | awk '{print $1}'
  } | /usr/bin/shasum -a 256 | awk '{print $1}'
}
RELEASE_XCCONFIG_PRIVATE_SNAPSHOT="$(private_file_snapshot "$RELEASE_XCCONFIG_PATH")"
RELEASE_ATTESTATION_PRIVATE_SNAPSHOT="$(private_file_snapshot "$RELEASE_CONFIG_ATTESTATION_PATH")"
ASC_KEY_PRIVATE_SNAPSHOT="$(private_file_snapshot "$ASC_API_KEY_PATH")"
assert_release_config_unchanged() {
  if [[ ! -f "$RELEASE_XCCONFIG_PATH" || -L "$RELEASE_XCCONFIG_PATH" ||
        ! -f "$RELEASE_CONFIG_ATTESTATION_PATH" || -L "$RELEASE_CONFIG_ATTESTATION_PATH" ||
        ! -f "$ASC_API_KEY_PATH" || -L "$ASC_API_KEY_PATH" ||
        "$(private_file_snapshot "$RELEASE_XCCONFIG_PATH")" != "$RELEASE_XCCONFIG_PRIVATE_SNAPSHOT" ||
        "$(private_file_snapshot "$RELEASE_CONFIG_ATTESTATION_PATH")" != "$RELEASE_ATTESTATION_PRIVATE_SNAPSHOT" ||
        "$(private_file_snapshot "$ASC_API_KEY_PATH")" != "$ASC_KEY_PRIVATE_SNAPSHOT" ]]; then
    echo "ERROR: Protected release configuration changed during the release." >&2
    exit 1
  fi
}

if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  echo "ERROR: TestFlight release requires a clean, committed source worktree." >&2
  exit 1
fi
SOURCE_COMMIT="$(git rev-parse HEAD)"
SOURCE_TREE="$(git rev-parse 'HEAD^{tree}')"
if [[ ! "$EUSOTRIP_APPROVED_RELEASE_COMMIT" =~ ^[a-f0-9]{40}$ || "$SOURCE_COMMIT" != "$EUSOTRIP_APPROVED_RELEASE_COMMIT" ]]; then
  echo "ERROR: HEAD does not match the immutable commit approved by the release authority." >&2
  exit 1
fi
node --test "${PROJECT_ROOT}/scripts/verify-reachable-here-credential-history.test.mjs"
node "${PROJECT_ROOT}/scripts/verify-reachable-here-credential-history.mjs" \
  --repository="$PROJECT_ROOT"
assert_source_unchanged() {
  if [[ "$(git rev-parse HEAD)" != "$SOURCE_COMMIT" ||
        "$(git rev-parse 'HEAD^{tree}')" != "$SOURCE_TREE" ||
        -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    echo "ERROR: Release source changed after its immutable identity was recorded." >&2
    exit 1
  fi
}
RELEASE_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
GITHUB_RELEASE_REPOSITORY="diegoenterprises/eusotrip-ios"
GITHUB_RELEASE_BRANCH="main"
GITHUB_RELEASE_REQUIRED_CHECK="HERE Offline Source Contract"
GITHUB_RELEASE_ENVIRONMENT="here-offline-release"
verify_github_governance() {
  local receipt parsed
  receipt="$(node "${PROJECT_ROOT}/scripts/verify-github-release-governance.mjs" \
    --repository="$GITHUB_RELEASE_REPOSITORY" \
    --branch="$GITHUB_RELEASE_BRANCH" \
    --commit="$SOURCE_COMMIT" \
    --required-check="$GITHUB_RELEASE_REQUIRED_CHECK" \
    --environment="$GITHUB_RELEASE_ENVIRONMENT" \
    --json)"
  parsed="$(GITHUB_GOVERNANCE_RECEIPT_VALUE="$receipt" node --input-type=module <<'NODE'
const receipt = JSON.parse(process.env.GITHUB_GOVERNANCE_RECEIPT_VALUE);
if (!Number.isSafeInteger(receipt.deploymentId) || receipt.deploymentId <= 0 ||
    !Number.isSafeInteger(receipt.deploymentStatusId) || receipt.deploymentStatusId <= 0) {
  throw new Error("GitHub governance receipt lacks exact deployment identities");
}
process.stdout.write(`${receipt.deploymentId}\t${receipt.deploymentStatusId}`);
NODE
)"
  IFS=$'\t' read -r GITHUB_ENVIRONMENT_DEPLOYMENT_ID GITHUB_ENVIRONMENT_DEPLOYMENT_STATUS_ID <<<"$parsed"
  GITHUB_GOVERNANCE_VERIFIED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
verify_github_governance

assert_source_unchanged
assert_release_config_unchanged
BUILD_SETTINGS="$(xcodebuild -project EusoTrip.xcodeproj -scheme EusoTrip -configuration Release -xcconfig "$RELEASE_XCCONFIG_PATH" -showBuildSettings)"
assert_release_config_unchanged
VERSION="${RELEASE_VERSION:-$(awk '/MARKETING_VERSION =/ { print $3; exit }' <<<"$BUILD_SETTINGS")}"
PROJECT_BUILD_NUMBER="$(awk '/CURRENT_PROJECT_VERSION =/ { print $3; exit }' <<<"$BUILD_SETTINGS")"
RESOLVED_DEVELOPMENT_TEAM="$(awk '/DEVELOPMENT_TEAM =/ { print $3; exit }' <<<"$BUILD_SETTINGS")"
ASC_BUNDLE_ID="${ASC_BUNDLE_ID:-com.app.eusotrip}"
if [[ -z "$VERSION" || -z "$PROJECT_BUILD_NUMBER" || -z "$ASC_BUNDLE_ID" ]]; then
  echo "ERROR: Unable to resolve MARKETING_VERSION/CURRENT_PROJECT_VERSION." >&2
  exit 1
fi
if [[ "$RESOLVED_DEVELOPMENT_TEAM" != "$HERE_OFFLINE_EXPECTED_TEAM_ID" ]]; then
  echo "ERROR: Release signing team does not match the committed Release build configuration." >&2
  exit 1
fi

# Apple rejects reused CFBundleVersion values after an upload has entered ASC,
# even when the project file still carries that historical floor. Resolve the
# live maximum before spending time on an archive. With build 850 already in
# TestFlight, the default candidate becomes 851; an explicit override must be
# higher than whatever ASC reports at release time.
assert_release_config_unchanged
ASC_LATEST_BUILD="$({
  ASC_BUNDLE_ID="$ASC_BUNDLE_ID" \
  ASC_API_KEY_ID="$ASC_API_KEY_ID" \
  ASC_API_KEY_ISSUER="$ASC_API_KEY_ISSUER" \
  ASC_API_KEY_PATH="$ASC_API_KEY_PATH" \
    node "${PROJECT_ROOT}/scripts/asc-latest-build.mjs"
})"
assert_release_config_unchanged
BUILD_NUMBER="$(
  node --input-type=module - \
    "$PROJECT_BUILD_NUMBER" \
    "$ASC_LATEST_BUILD" \
    "${RELEASE_BUILD_NUMBER:-}" \
    "${PROJECT_ROOT}/scripts/asc-latest-build.mjs" <<'NODE'
import { pathToFileURL } from 'node:url';
const [projectBuild, latestAscBuild, overrideBuild, modulePath] = process.argv.slice(2);
const { selectReleaseBuild } = await import(pathToFileURL(modulePath));
process.stdout.write(String(selectReleaseBuild({ projectBuild, latestAscBuild, overrideBuild })));
NODE
)"

RELEASE_ROOT="${RELEASE_ROOT:-$(mktemp -d "/tmp/eusotrip-testflight-${VERSION}-${BUILD_NUMBER}-XXXXXX")}"
if [[ ! -d "$RELEASE_ROOT" || -L "$RELEASE_ROOT" ]]; then
  echo "ERROR: RELEASE_ROOT must be one existing private directory." >&2
  exit 1
fi
RELEASE_ROOT="$(cd "$RELEASE_ROOT" && pwd -P)"
RELEASE_ROOT_OWNER="$(stat -f '%u' "$RELEASE_ROOT")"
RELEASE_ROOT_MODE="$(stat -f '%Lp' "$RELEASE_ROOT")"
if [[ "$RELEASE_ROOT_OWNER" != "$(id -u)" ]] || (( (8#$RELEASE_ROOT_MODE & 8#077) != 0 )); then
  echo "ERROR: RELEASE_ROOT must be owned by the release user with no group/other access." >&2
  exit 1
fi
DERIVED_DATA_PATH="${RELEASE_ROOT}/DerivedData"
TEST_DERIVED_DATA_PATH="${RELEASE_ROOT}/OfflineTestDerivedData"
ARCHIVE_PATH="${RELEASE_ROOT}/EusoTrip-${VERSION}-${BUILD_NUMBER}.xcarchive"
EXPORT_PATH="${RELEASE_ROOT}/export"
RELEASE_LADDER_PATH="${RELEASE_LADDER_PATH:-${RELEASE_ROOT}/release-ladder.json}"
RELEASE_LADDER_DIRECTORY="$(dirname "$RELEASE_LADDER_PATH")"
if [[ ! -d "$RELEASE_LADDER_DIRECTORY" || -L "$RELEASE_LADDER_DIRECTORY" || "$(cd "$RELEASE_LADDER_DIRECTORY" && pwd -P)" != "$RELEASE_ROOT" ]]; then
  echo "ERROR: RELEASE_LADDER_PATH must stay inside the private release root." >&2
  exit 1
fi

LADDER_COMPILED="not_run"
LADDER_ARCHIVED="not_run"
LADDER_TESTED="not_run"
LADDER_EXPORTED="not_run"
LADDER_UPLOADED="not_run"
LADDER_HERE_OFFLINE_CONTRACT="not_run"
LADDER_DEVICE_ACCEPTANCE="pending"
LADDER_PROCESSING="pending"
LADDER_AVAILABLE="pending"
ARCHIVE_APP_TREE_SHA256=""
EXPORTED_IPA_PATH=""
EXPORTED_IPA_SHA256=""
EXPORTED_APP_PATH=""
EXPORTED_APP_TREE_SHA256=""

write_ladder() {
  mkdir -p "$(dirname "$RELEASE_LADDER_PATH")"
  local ladder_temporary
  ladder_temporary="$(mktemp "${RELEASE_ROOT}/.release-ladder-XXXXXX")"
  umask 077
  LADDER_OUTPUT_PATH="$ladder_temporary" \
  LADDER_VERSION_VALUE="$VERSION" \
  LADDER_BUILD_VALUE="$BUILD_NUMBER" \
  LADDER_PROJECT_BUILD_VALUE="$PROJECT_BUILD_NUMBER" \
  LADDER_ASC_LATEST_VALUE="$ASC_LATEST_BUILD" \
  LADDER_BUNDLE_ID_VALUE="$ASC_BUNDLE_ID" \
  LADDER_SOURCE_COMMIT_VALUE="$SOURCE_COMMIT" \
  LADDER_SOURCE_TREE_VALUE="$SOURCE_TREE" \
  LADDER_CONFIG_ATTESTATION_PATH_VALUE="$RELEASE_CONFIG_ATTESTATION_PATH" \
  LADDER_CONFIG_ATTESTATION_HASH_VALUE="$RELEASE_CONFIG_ATTESTATION_SHA256" \
  LADDER_XCCONFIG_HASH_VALUE="$RELEASE_XCCONFIG_SHA256" \
  LADDER_STARTED_AT_VALUE="$RELEASE_STARTED_AT" \
  LADDER_GITHUB_REPOSITORY_VALUE="$GITHUB_RELEASE_REPOSITORY" \
  LADDER_GITHUB_BRANCH_VALUE="$GITHUB_RELEASE_BRANCH" \
  LADDER_GITHUB_CHECK_VALUE="$GITHUB_RELEASE_REQUIRED_CHECK" \
  LADDER_GITHUB_ENVIRONMENT_VALUE="$GITHUB_RELEASE_ENVIRONMENT" \
  LADDER_GITHUB_VERIFIED_AT_VALUE="$GITHUB_GOVERNANCE_VERIFIED_AT" \
  LADDER_GITHUB_DEPLOYMENT_ID_VALUE="$GITHUB_ENVIRONMENT_DEPLOYMENT_ID" \
  LADDER_GITHUB_DEPLOYMENT_STATUS_ID_VALUE="$GITHUB_ENVIRONMENT_DEPLOYMENT_STATUS_ID" \
  LADDER_RELEASE_ROOT_VALUE="$RELEASE_ROOT" \
  LADDER_ARCHIVE_PATH_VALUE="$ARCHIVE_PATH" \
  LADDER_ARCHIVE_APP_PATH_VALUE="${ARCHIVED_APP_PATH:-}" \
  LADDER_ARCHIVE_HASH_VALUE="$ARCHIVE_APP_TREE_SHA256" \
  LADDER_IPA_PATH_VALUE="$EXPORTED_IPA_PATH" \
  LADDER_IPA_HASH_VALUE="$EXPORTED_IPA_SHA256" \
  LADDER_EXPORTED_APP_PATH_VALUE="$EXPORTED_APP_PATH" \
  LADDER_EXPORTED_APP_HASH_VALUE="$EXPORTED_APP_TREE_SHA256" \
  LADDER_COMPILED_VALUE="$LADDER_COMPILED" \
  LADDER_ARCHIVED_VALUE="$LADDER_ARCHIVED" \
  LADDER_TESTED_VALUE="$LADDER_TESTED" \
  LADDER_OFFLINE_VALUE="$LADDER_HERE_OFFLINE_CONTRACT" \
  LADDER_DEVICE_ACCEPTANCE_VALUE="$LADDER_DEVICE_ACCEPTANCE" \
  LADDER_EXPORTED_VALUE="$LADDER_EXPORTED" \
  LADDER_UPLOADED_VALUE="$LADDER_UPLOADED" \
  LADDER_PROCESSING_VALUE="$LADDER_PROCESSING" \
  LADDER_AVAILABLE_VALUE="$LADDER_AVAILABLE" \
    node --input-type=module <<'NODE'
import fs from "node:fs";
const optional = name => process.env[name] || null;
const ladder = {
  schemaVersion: 3,
  version: process.env.LADDER_VERSION_VALUE,
  build: process.env.LADDER_BUILD_VALUE,
  projectBuild: process.env.LADDER_PROJECT_BUILD_VALUE,
  ascLatestBuildBeforeRelease: process.env.LADDER_ASC_LATEST_VALUE,
  bundleId: process.env.LADDER_BUNDLE_ID_VALUE,
  sourceCommit: process.env.LADDER_SOURCE_COMMIT_VALUE,
  sourceTree: process.env.LADDER_SOURCE_TREE_VALUE,
  releaseConfigAttestationPath: process.env.LADDER_CONFIG_ATTESTATION_PATH_VALUE,
  releaseConfigAttestationSha256: process.env.LADDER_CONFIG_ATTESTATION_HASH_VALUE,
  releaseXcconfigSha256: process.env.LADDER_XCCONFIG_HASH_VALUE,
  releaseStartedAt: process.env.LADDER_STARTED_AT_VALUE,
  githubRepository: process.env.LADDER_GITHUB_REPOSITORY_VALUE,
  githubBranch: process.env.LADDER_GITHUB_BRANCH_VALUE,
  githubRequiredCheck: process.env.LADDER_GITHUB_CHECK_VALUE,
  githubReleaseEnvironment: process.env.LADDER_GITHUB_ENVIRONMENT_VALUE,
  githubGovernanceVerifiedAt: process.env.LADDER_GITHUB_VERIFIED_AT_VALUE,
  githubEnvironmentDeploymentId: Number(process.env.LADDER_GITHUB_DEPLOYMENT_ID_VALUE),
  githubEnvironmentDeploymentStatusId: Number(process.env.LADDER_GITHUB_DEPLOYMENT_STATUS_ID_VALUE),
  releaseRoot: process.env.LADDER_RELEASE_ROOT_VALUE,
  archivePath: process.env.LADDER_ARCHIVE_PATH_VALUE,
  archiveAppPath: optional("LADDER_ARCHIVE_APP_PATH_VALUE"),
  archiveAppTreeSha256: optional("LADDER_ARCHIVE_HASH_VALUE"),
  exportedIPAPath: optional("LADDER_IPA_PATH_VALUE"),
  exportedIPASha256: optional("LADDER_IPA_HASH_VALUE"),
  exportedAppPath: optional("LADDER_EXPORTED_APP_PATH_VALUE"),
  exportedAppTreeSha256: optional("LADDER_EXPORTED_APP_HASH_VALUE"),
  compiled: process.env.LADDER_COMPILED_VALUE,
  archived: process.env.LADDER_ARCHIVED_VALUE,
  tested: process.env.LADDER_TESTED_VALUE,
  hereOfflineContract: process.env.LADDER_OFFLINE_VALUE,
  deviceAcceptance: process.env.LADDER_DEVICE_ACCEPTANCE_VALUE,
  exported: process.env.LADDER_EXPORTED_VALUE,
  uploaded: process.env.LADDER_UPLOADED_VALUE,
  processing: process.env.LADDER_PROCESSING_VALUE,
  availableInTestFlight: process.env.LADDER_AVAILABLE_VALUE,
};
fs.writeFileSync(process.env.LADDER_OUTPUT_PATH, `${JSON.stringify(ladder, null, 2)}\n`, {
  mode: 0o600,
});
NODE
  chmod 600 "$ladder_temporary"
  mv -f "$ladder_temporary" "$RELEASE_LADDER_PATH"
}

mark_failed_step() {
  case "$1" in
    archive)
      LADDER_COMPILED="fail"
      LADDER_ARCHIVED="fail"
      ;;
    offline_tests)
      LADDER_TESTED="fail"
      ;;
    export)
      LADDER_EXPORTED="fail"
      ;;
    offline_contract)
      LADDER_HERE_OFFLINE_CONTRACT="fail"
      ;;
    upload)
      LADDER_UPLOADED="fail"
      ;;
  esac
  write_ladder
}

write_ladder
echo "Release ${VERSION} (${BUILD_NUMBER}); project=${PROJECT_BUILD_NUMBER}, ASC latest=${ASC_LATEST_BUILD}"
echo "Release workspace: ${RELEASE_ROOT}"

# This harness proves the release verifier itself still rejects malformed or
# substituted HERE artifacts before we spend an archive or App Store upload.
trap 'mark_failed_step offline_contract' ERR
node "${PROJECT_ROOT}/scripts/here-production-gate.mjs"
node --test "${PROJECT_ROOT}/scripts/asc-latest-build.test.mjs"
node "${PROJECT_ROOT}/scripts/preflight-exported-ipa.test.mjs"
node "${PROJECT_ROOT}/scripts/hash-release-artifact.test.mjs"
node "${PROJECT_ROOT}/scripts/verify-exported-ipa-app-binding.test.mjs"
node "${PROJECT_ROOT}/scripts/select-available-ios-simulator.test.mjs"
node "${PROJECT_ROOT}/scripts/release-ladder-status.test.mjs"
node "${PROJECT_ROOT}/scripts/asc-build-status.test.mjs"
node "${PROJECT_ROOT}/scripts/verify-release-config-attestation.test.mjs"
node "${PROJECT_ROOT}/scripts/verify-here-offline-device-acceptance.test.mjs"
node "${PROJECT_ROOT}/scripts/verify-github-release-governance.test.mjs"
node "${PROJECT_ROOT}/scripts/verify-here-offline-contract.test.mjs"
node "${PROJECT_ROOT}/scripts/verify-here-offline-contract.mjs"
trap - ERR

if [[ -n "${OFFLINE_TEST_DESTINATION:-}" ]]; then
  OFFLINE_TEST_DESTINATION_RESOLVED="$OFFLINE_TEST_DESTINATION"
else
  OFFLINE_TEST_DESTINATION_RESOLVED="$({
    xcrun simctl list devices available -j | node "${PROJECT_ROOT}/scripts/select-available-ios-simulator.mjs"
  })"
fi
trap 'mark_failed_step offline_tests' ERR
assert_source_unchanged
assert_release_config_unchanged
xcodebuild test \
  -project EusoTrip.xcodeproj \
  -scheme EusoTrip \
  -configuration Debug \
  -destination "$OFFLINE_TEST_DESTINATION_RESOLVED" \
  -derivedDataPath "$TEST_DERIVED_DATA_PATH" \
  -xcconfig "$RELEASE_XCCONFIG_PATH" \
  -only-testing:EusoTripOfflineTests \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO
trap - ERR
assert_source_unchanged
assert_release_config_unchanged
LADDER_TESTED="pass"
write_ladder

trap 'mark_failed_step archive' ERR
assert_source_unchanged
assert_release_config_unchanged
xcodebuild \
  -project EusoTrip.xcodeproj \
  -scheme EusoTrip \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -archivePath "$ARCHIVE_PATH" \
  -xcconfig "$RELEASE_XCCONFIG_PATH" \
  -authenticationKeyPath "$ASC_API_KEY_PATH" \
  -authenticationKeyID "$ASC_API_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_API_KEY_ISSUER" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  MARKETING_VERSION="$VERSION" \
  archive
trap - ERR
assert_source_unchanged
assert_release_config_unchanged
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

ARCHIVED_APP_PATH="${ARCHIVE_PATH}/Products/Applications/EusoTrip.app"
if [[ ! -d "$ARCHIVED_APP_PATH" ]]; then
  mark_failed_step offline_contract
  echo "ERROR: Archived EusoTrip.app is missing." >&2
  exit 1
fi

# The release verifier inspects the signed archive product itself. It binds
# HERE Navigate, HERE_NOTICE, all 18 approved native styles, credentials, and
# signing identity to the committed supply-chain attestations before export.
trap 'mark_failed_step offline_contract' ERR
node "${PROJECT_ROOT}/scripts/verify-here-offline-contract.mjs" \
  --release \
  --built-app="${ARCHIVED_APP_PATH}"
trap - ERR
ARCHIVE_APP_TREE_SHA256="$(
  node "${PROJECT_ROOT}/scripts/hash-release-artifact.mjs" --path="$ARCHIVED_APP_PATH"
)"
LADDER_HERE_OFFLINE_CONTRACT="pending"
write_ladder

trap 'mark_failed_step export' ERR
assert_source_unchanged
assert_release_config_unchanged
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
assert_source_unchanged
assert_release_config_unchanged
LADDER_EXPORTED="pass"
write_ladder

IPA_PATHS=()
while IFS= read -r -d '' candidate; do
  IPA_PATHS+=("$candidate")
done < <(find "$EXPORT_PATH" -maxdepth 2 -type f -name '*.ipa' -print0)
if [[ "${#IPA_PATHS[@]}" -ne 1 ]]; then
  mark_failed_step export
  echo "ERROR: Expected exactly one exported IPA; found ${#IPA_PATHS[@]}." >&2
  exit 1
fi
IPA_PATH="${IPA_PATHS[0]}"
EXPORTED_IPA_PATH="$IPA_PATH"

# Export must remain local. Validate the exact distributable product, not only
# its pre-export Archive ancestor, before the single explicit upload below.
trap 'mark_failed_step offline_contract' ERR
node "${PROJECT_ROOT}/scripts/preflight-exported-ipa.mjs" --ipa="$IPA_PATH"
trap - ERR
EXPORTED_APP_ROOT="$(mktemp -d "${RELEASE_ROOT}/exported-app-inspection-XXXXXX")"
chmod 700 "$EXPORTED_APP_ROOT"
/usr/bin/ditto -x -k "$IPA_PATH" "$EXPORTED_APP_ROOT"
EXPORTED_APP_PATHS=()
while IFS= read -r -d '' candidate; do
  EXPORTED_APP_PATHS+=("$candidate")
done < <(find "$EXPORTED_APP_ROOT/Payload" -maxdepth 1 -type d -name 'EusoTrip.app' -print0)
if [[ "${#EXPORTED_APP_PATHS[@]}" -ne 1 ]]; then
  mark_failed_step offline_contract
  echo "ERROR: Expected exactly one EusoTrip app in the exported IPA; found ${#EXPORTED_APP_PATHS[@]}." >&2
  exit 1
fi
EXPORTED_APP_PATH="${EXPORTED_APP_PATHS[0]}"
PAYLOAD_REAL_PATH="$(cd "$EXPORTED_APP_ROOT/Payload" && pwd -P)"
EXPORTED_APP_REAL_PATH="$(cd "$EXPORTED_APP_PATH" && pwd -P)"
if [[ "$EXPORTED_APP_REAL_PATH" != "$PAYLOAD_REAL_PATH/EusoTrip.app" ]]; then
  mark_failed_step offline_contract
  echo "ERROR: Exported app escaped the inspected Payload directory." >&2
  exit 1
fi
EXPORTED_APP_PATH="$EXPORTED_APP_REAL_PATH"

trap 'mark_failed_step offline_contract' ERR
node "${PROJECT_ROOT}/scripts/verify-here-offline-contract.mjs" \
  --release \
  --built-app="${EXPORTED_APP_PATH}"
trap - ERR
EXPORTED_IPA_SHA256="$(
  node "${PROJECT_ROOT}/scripts/hash-release-artifact.mjs" --path="$EXPORTED_IPA_PATH"
)"
EXPORTED_APP_TREE_SHA256="$(
  node "${PROJECT_ROOT}/scripts/hash-release-artifact.mjs" --path="$EXPORTED_APP_PATH"
)"
node "${PROJECT_ROOT}/scripts/verify-exported-ipa-app-binding.mjs" \
  --ipa="$EXPORTED_IPA_PATH" \
  --ipa-sha256="$EXPORTED_IPA_SHA256" \
  --app-tree-sha256="$EXPORTED_APP_TREE_SHA256"
LADDER_HERE_OFFLINE_CONTRACT="pass"
write_ladder

trap 'mark_failed_step upload' ERR
assert_source_unchanged
assert_release_config_unchanged
verify_github_governance
assert_source_unchanged
assert_release_config_unchanged
if [[ "$(node "${PROJECT_ROOT}/scripts/hash-release-artifact.mjs" --path="$EXPORTED_IPA_PATH")" != "$EXPORTED_IPA_SHA256" ||
      "$(node "${PROJECT_ROOT}/scripts/hash-release-artifact.mjs" --path="$EXPORTED_APP_PATH")" != "$EXPORTED_APP_TREE_SHA256" ]]; then
  echo "ERROR: Exported release artifacts changed before upload." >&2
  exit 1
fi
write_ladder
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
