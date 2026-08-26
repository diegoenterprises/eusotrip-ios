#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
scratch_dir=$(mktemp -d "${TMPDIR:-/tmp}/eusotrip-auth-contracts.XXXXXX")
trap 'rm -rf "$scratch_dir"' EXIT INT TERM

xcrun swiftc \
  "$repo_root/EusoTrip/Services/EusoSessionTokenPolicy.swift" \
  "$repo_root/scripts/EusoSessionTokenPolicyContractTests.swift" \
  -o "$scratch_dir/auth-contracts"
"$scratch_dir/auth-contracts"

api="$repo_root/EusoTrip/Services/EusoTripAPI.swift"
session="$repo_root/EusoTrip/Services/EusoTripSession.swift"
app="$repo_root/EusoTrip/EusoTripApp.swift"
watch_handler="$repo_root/EusoTrip/Services/WatchCommandHandler.swift"
convoy_bridge="$repo_root/EusoTrip/Services/ConvoyPhoneBridge.swift"
sign_in="$repo_root/EusoTrip/Views/Auth/001_SignIn.swift"

grep -q 'renewSession' "$api"
grep -q '"auth.refreshSession"' "$api"
grep -q '"app_refresh_token"' "$api"
grep -q 'mutationNoAutoRefresh' "$api"
grep -q 'dataWithSessionRecovery' "$api"
grep -q 'authenticatedRawRequest' "$api"
grep -q 'sessionRefreshHandler: (@MainActor () async throws -> Bool)' "$api"
grep -q 'self.authToken = token' "$api"
existing_line=$(grep -n 'if let existing = inFlightRefresh' "$api" | head -1 | cut -d: -f1)
guard_line=$(grep -n 'guard let handler = sessionRefreshHandler, !isRefreshing' "$api" | head -1 | cut -d: -f1)
if [ "$existing_line" -ge "$guard_line" ]; then
  echo "FAIL: sibling 401s are rejected before they can await the shared refresh" >&2
  exit 1
fi

grep -q 'EusoSessionTokenPolicy.shouldRenew' "$session"
grep -q 'inFlightRenewal' "$session"
grep -q 'clearLocalSession' "$session"
grep -q 'pushWatchCredential(for: me)' "$session"
grep -q 'recoveryUnavailable = true' "$session"
grep -q 'renew: true' "$session"
grep -q 'waitForLogoutCompletion' "$session"
grep -q 'SecItemUpdate' "$session"
grep -q 'credential.v2' "$session"
grep -q 'let cachedUser: AuthUser?' "$session"
grep -q 'cachedUser: cached' "$session"
bundle_line=$(grep -n 'keychain.save(key: kCredentialBundle' "$session" | head -1 | cut -d: -f1)
legacy_line=$(grep -n 'keychain.save(key: kAuthToken' "$session" | head -1 | cut -d: -f1)
if [ "$bundle_line" -ge "$legacy_line" ]; then
  echo "FAIL: rotated credential bundle must commit before compatibility mirrors" >&2
  exit 1
fi
cached_legacy_line=$(grep -n 'saveCachedUser(cached)' "$session" | head -1 | cut -d: -f1)
if [ "$bundle_line" -ge "$cached_legacy_line" ]; then
  echo "FAIL: atomic credential/profile bundle must commit before cached-user mirror" >&2
  exit 1
fi

reissue_block=$(sed -n '/private func reissue(/,/^    }/p' "$api")
printf '%s\n' "$reissue_block" | grep -q 'if let authToken'
printf '%s\n' "$reissue_block" | grep -q 'Bearer.*authToken'
printf '%s\n' "$reissue_block" | grep -q 'setValue(nil.*Authorization'
capture_block=$(sed -n '/private func captureSessionToken/,/^    }/p' "$api")
if printf '%s\n' "$capture_block" | grep -q 'app_refresh_token'; then
  echo "FAIL: refresh credential is eligible for Authorization/Watch promotion" >&2
  exit 1
fi
grep -q 'guard let token = api.authToken' "$session"
if grep -E 'print\(.*(app_refresh_token|cookieJSON)' "$api" "$session" >/dev/null; then
  echo "FAIL: refresh credential material can enter diagnostic logs" >&2
  exit 1
fi
grep -q 'EusoSessionReturnGate' "$app"
grep -q 'authenticatedRawRequest' "$watch_handler"
grep -q 'authenticatedRawRequest' "$convoy_bridge"
if grep -q 'URLSession.shared.data(for: req)' "$watch_handler" "$convoy_bridge"; then
  echo "FAIL: a watch security request still bypasses session recovery" >&2
  exit 1
fi

if grep -q 'oldPhase == .background' "$app"; then
  echo "FAIL: brittle background -> active comparison remains" >&2
  exit 1
fi

if ! sed -n '/Developer-only walkthrough/,+7p' "$sign_in" | grep -q '#if DEBUG'; then
  echo "FAIL: fabricated preview identity is available in release sign-in" >&2
  exit 1
fi
if ! awk '
  previous ~ /#if DEBUG/ && /Offline demo sign-in/ { found = 1 }
  { previous = $0 }
  END { exit(found ? 0 : 1) }
' "$session"; then
  echo "FAIL: fabricated demo session is compiled into release builds" >&2
  exit 1
fi

echo "PASS: iOS auth persistence source contracts"
