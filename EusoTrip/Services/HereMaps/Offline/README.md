# EusoTrip offline maps

This directory is the native HERE SDK Navigate boundary. The existing HERE
Maps JavaScript `WKWebView` and backend routing/search procedures remain online
services and must never be reported as a persistent offline map system.

## Supply-chain prerequisites

The app deliberately builds without the proprietary SDK and reports
`missingFramework`. To enable the native adapter:

1. Confirm that the registered EusoTrip application is contractually entitled
   to **HERE SDK Navigate for iOS**.
2. Pin and record the approved SDK version and vendor archive SHA-256. The
   implementation target is 4.27.2.0; do not adopt an unreleased or newer
   version without rerunning the full regression matrix.
   Record the canonical extracted xcframework tree hash and HERE_NOTICE hash as
   well, so the loose framework, approved archive, and built product form one
   verifiable chain rather than trusting matching Info.plist text.
3. Add the vendor-provided `heresdk.xcframework` to the EusoTrip app target,
   link and embed it according to HERE's iOS integration guide, and preserve
   the required device and simulator slices.
4. Add the SDK-provided `HERE_NOTICE` to Copy Bundle Resources. Startup fails
   closed when the notice is missing.
5. Put the dedicated Navigate access-key ID and secret in a gitignored
   `EusoTrip.xcconfig` using the names in `EusoTrip.xcconfig.sample`. Do not
   reuse the Maps JavaScript key or backend OAuth credentials.
6. Keep the synchronized offline source/view roots attached to the iOS app
   target. `README.md` and the SDK audit manifest are explicitly excluded from
   the product; the native-style manifest remains a runtime resource.
7. Export and approve all 18 HERE-native mode/family/theme styles named in
   `HERE_NATIVE_STYLE_SUPPLY_CHAIN.json`, record their SHA-256 values and export
   provenance, and include those exact files in the signed app product.

No credential value may appear in source, tests, logs, screenshots, or build
artifacts beyond the signed application's required mobile configuration.

## Runtime contract

- One app-scoped supervisor owns the shared native engine and rejects a policy
  restart while navigation or rendering leases are active.
- Radio-silent launch is selected before engine initialization. Changing the
  startup policy recreates the shared engine.
- Downloads explicitly include rendering, detailed rendering, navigation,
  offline search, offline routing, truck restrictions and attributes, fuel
  attributes, and terrain. SDK defaults are not accepted as proof.
- Catalog, download, update, delete, repair, pause, resume, and cancel controls
  are serialized by `OfflineMapCoordinator`. Completed durable mutations are
  independently read back; cancellation is requested, then final state is read
  independently. Native cancellation acknowledgement remains licensed-device
  acceptance evidence and is never mislabeled as a completed map mutation.
- A failed or cancelled durable mutation triggers a fresh native health/radio
  inspection and inventory readback before the operation is cleared. Local
  results require non-empty attribution to current, usable installed regions.
- HERE 4.27 search/routing can use cache and does not attribute results or
  navigation boundaries to persistent region IDs. Search, road/truck routing,
  guidance, and voice capability are therefore withheld and their direct
  native boundaries fail closed until EusoTrip has independently verified,
  signed installed-region geometry and boundary evidence.
- Rail and Vessel routes are never calculated with HERE road routing. The cache
  accepts only Ed25519-signed `route.plan` bytes whose pinned issuer, audience,
  tenant, user, load, mode, and lifetime claims verify. Production decoder,
  logout purge, and route-surface callers are still required before this cache
  becomes app behavior. One app-scoped store owns each cache root; a competing
  store instance is rejected before it can create an out-of-order writer.
- Canonical-route observations obtain time from the store's injected clock;
  callers cannot select an earlier evaluation time per read. Persisted receipt
  evidence rejects pre-receipt rollback, but trustworthy elapsed time across a
  device clock rollback or reboot is not yet available offline. Cached Rail or
  Vessel freshness must remain release-blocked until that evidence is added.
- Native-engine readiness proves only inspected engine health and capability
  bits. It is not journey or departure authority; that requires explicit,
  current corridor coverage evidence from the signed coverage resolver.
- Device GPS and local navigation remain distinct from server live-observation
  truth. Traffic, weather, incidents, tender state, and dynamic routing are
  unavailable or timestamped stale while offline.
- The renderer boundary may show an approved EusoTrip family/mode/theme style
  or an opaque unavailable state. Stock HERE or Apple cartography is not a
  visual fallback. This branch does not yet mount that native surface in a
  production screen.

## Current integration blockers

The source boundary is intentionally not labeled full parity or release ready.
The licensed framework/archive/notices, Navigate credentials, 18 approved
native styles, production settings/map/search/route/navigation callers,
principal-transition purge wiring, signed route.plan response support, and a
trusted installed-coverage resolver are absent. `verify-here-offline-contract.mjs`
is a source/artifact gate only; it cannot prove device behavior or radio silence.
No authoritative Archive/CI automation invokes its `--release` built-product
mode or regression harness yet, so release enforcement itself remains a named
blocker rather than an assumed manual step.
Historical build logs, documentation, and a legacy test contained exposed HERE
credential material. The current tree is sanitized, but every affected HERE
credential—including the Maps JS key—must be revoked/rotated and the old bytes
remediated from all Git refs through the approved secret-response process before
any release claim. The
nonsecret `security/HERE_CREDENTIAL_REMEDIATION.json` attestation intentionally
remains unapproved until rotation, history cleanup, and a clean history-wide
secret scan are independently approved. Finite HERE callbacks also still need
bounded watchdog/cancellation bridges and interruption tests with the licensed
binary; release verification remains blocked until that evidence exists.

## Release acceptance

Simulator and cache-only checks are insufficient. On a real iPhone:

1. Install one small region online and verify its bytes, layers, and catalog
   version.
2. Force-quit, enable airplane mode, reboot, and cold-launch.
3. Verify native vector pan/zoom. Only after the signed coverage resolver is
   integrated, verify local place/address/category search, dimensioned truck
   routing, visual guidance, installed TTS voice, GPS progression, deviation,
   local rerouting, and approaching/outside-coverage transitions.
4. Cross an uncovered boundary and verify the named missing-coverage state from
   independent installed-region evidence rather than an empty attribution.
5. Exercise pause/resume/cancel, low storage, interrupted install, update,
   corruption repair, delete, redownload, account switch, and stale canonical
   route handling.
6. Capture network traffic and prove zero HERE SDK requests during the
   radio-silent run. Audit unrelated EusoTrip API activity separately instead
   of treating the offline-map subsystem as a global app network switch.
7. Archive from clean DerivedData and inspect the signed app for the approved
   SDK, `HERE_NOTICE`, required privacy disclosure, and unintended credentials.

Offline Wikipedia-style editorial guides are not a HERE SDK capability. They
require a separately licensed, versioned, downloadable EusoTrip content lane.
This contract targets EusoTrip's road/truck freight operations plus signed
server-canonical Rail and Vessel itineraries. It must not be described as
consumer hiking/cycling, contour/elevation, or editorial-guide parity with
Organic Maps unless those separately modeled, licensed, and device-proven
capabilities are added.
