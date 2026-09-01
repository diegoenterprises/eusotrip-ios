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
5. Generate a dedicated owner-private release xcconfig from the protected
   post-rotation secret store, using the names in `EusoTrip.xcconfig.sample`.
   Release automation rejects an ignored workspace `EusoTrip.xcconfig`, every
   symlink, and any config inside the source tree. It snapshots the external
   file privately and rejects changes between settings, tests, Archive,
   export, and upload. Do not reuse the Maps JavaScript key or backend OAuth
   credentials.
6. Keep the synchronized offline source/view roots attached to the iOS app
   target. `README.md` and the SDK audit manifest are explicitly excluded from
   the product; the native-style manifest remains a runtime resource.
7. Export and approve all 18 HERE-native mode/family/theme styles named in
   `HERE_NATIVE_STYLE_SUPPLY_CHAIN.json`, record their SHA-256 values and export
   provenance, and include those exact files in the signed app product.
8. Inventory and hash the vendor-provided privacy manifests. Privacy/legal must
   independently approve the app-level `EusoTrip/Resources/PrivacyInfo.xcprivacy`,
   reconcile required-reason APIs and collected-data declarations, and confirm
   the App Store privacy label. The verifier intentionally does not invent
   those declarations.

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
  navigation boundaries to persistent region IDs. `SignedInstalledCoverageResolver`
  now verifies pinned Ed25519 issuer/audience/key/SDK/rightsholder claims,
  catalog identity, installed native inventory, polygon/multipolygon holes and
  dateline geometry, complete corridors, freshness, replay, and rollback. The
  production composition now supplies the native installed-region inventory to
  that resolver and rejects search, road/truck routing, departure, rerouting,
  or guidance unless the requested point or complete corridor is admitted by
  current signed coverage. The independently licensed and approved signed
  boundary dataset, its pinned public key, and the matching SDK inventory are
  still release inputs; their absence keeps those operations unavailable.
- Installed-coverage time persists the exact signed-envelope digest, the
  authenticated `payload.issuedAt` lower bound, receipt uptime, and kernel boot
  session in device-only Keychain storage. Same-boot relaunch advances only by
  monotonic uptime; reboot, uptime regression, anchor/envelope tamper, or
  missing/corrupt persistence fails closed. `issuedAt` is a conservative signed
  lower bound, not exact server receipt time or trusted current time; a newer
  signed manifest must re-anchor coverage after reboot.
- Rail and Vessel routes are never calculated with HERE road routing. The cache
  accepts only Ed25519-signed `route.plan` bytes whose pinned issuer, audience,
  tenant, user, load, mode, and lifetime claims verify. The authenticated
  production client, decoder, offline reader, logout/principal purge, Rail and
  Vessel callers, and verified route renderer are wired. One app-scoped store
  owns each cache root; a competing store instance is rejected before it can
  create an out-of-order writer.
- Canonical-route observations anchor authenticated signed server time to
  monotonic system uptime per principal and persist the anchor in app-scoped,
  device-only Keychain storage. Wall-clock rollback and forward jumps cannot
  change freshness. A same-boot process relaunch can restore the monotonic
  anchor; a reboot, boot-session mismatch, uptime regression, or tamper event
  deliberately invalidates it. Cached Rail/Vessel freshness then remains
  unavailable until a strictly newer signed response re-anchors it. This is a
  fail-closed safety boundary, not a claim of a secure cross-reboot clock.
- Native-engine readiness proves only inspected engine health and capability
  bits. It is not journey or departure authority; that requires explicit,
  current corridor coverage evidence from the signed coverage resolver.
- Device GPS and local navigation remain distinct from server live-observation
  truth. Traffic, weather, incidents, tender state, and dynamic routing are
  unavailable or timestamped stale while offline.
- The renderer boundary may show an approved EusoTrip family/mode/theme style
  or an opaque unavailable state. Stock HERE or Apple cartography is not a
  visual fallback. Settings mounts a lease-controlled native preview only when
  radio-silent policy, SDK readiness, trusted installed coverage, and a usable
  region are all present. It immediately obscures and removes accessibility
  exposure when eligibility is lost. The production road-journey screen uses
  the same app-owned composition for local search, road/truck alternatives,
  maneuvers, guidance, and coverage state; it requires a fresh precise
  nonsimulated device fix and never fabricates truck constraints.

## Current integration blockers

The source boundary is intentionally not labeled full parity or release ready.
The app-owned composition, native inventory adapter, Settings preview,
radio-silent road/truck journey caller, signed Rail/Vessel package client and
callers, principal-transition purge, and verified route surfaces are now in
source. The matching authenticated server procedure lives on its separately
verified web branch and must be integrated with this exact iOS branch before a
release claim.

The remaining release inputs are not safe to fabricate: the licensed HERE SDK
4.27.2.0 framework/archive, archive and extracted-tree hashes, `HERE_NOTICE`,
vendor privacy material, dedicated rotated Navigate credentials, all 18
approved native style exports and hashes, and a rightsholder-approved signed
coverage catalog/public key/manifest matching real installed SDK inventory.
The current active Rail/Vessel movement map still uses the online JavaScript
surface; replacing it without losing route geometry, endpoints, live position,
camera/follow state, or failure truth requires a typed native scene-projection
API and signed-geometry adapter. Until that is implemented and device-proven,
the Settings preview and road-journey screen are the native offline surfaces,
not a universal replacement for every map in the app.

`verify-here-offline-contract.mjs` is a source/artifact gate only; it cannot
prove physical-device behavior or radio silence.
The authoritative TestFlight deployment script now runs the production gate,
regression harness, and source gate before Archive; validates the exact archived
`.app`; performs a local-only export; and validates the exact `.app` extracted
from the single exported IPA before its one explicit upload. Its schema-3
release ledger cannot reach the final state until an independently approved
physical-iPhone evidence bundle is bound to the same commit, tree, build, IPA,
app, SDK, styles, private packet capture, and sanitized zero-HERE summary.
Historical build logs, documentation, and a legacy test contained exposed HERE
credential material. The current tree is sanitized, but every affected HERE
credential—including the Maps JS key—must be revoked/rotated and the old bytes
remediated from all Git refs through the approved secret-response process before
any release claim. The
nonsecret `security/HERE_CREDENTIAL_REMEDIATION.json` attestation intentionally
remains unapproved until rotation, history cleanup, and a clean history-wide
secret scan are independently approved. Finite HERE callbacks now share an
exactly-once watchdog for native success, failure, inactivity timeout, task
cancellation, and late-callback rejection. Transfer timeouts suspend while
intentionally paused, background maintenance is paused and owner-matched on
foreground recovery, and interrupted voice guidance requires both
system-approved audio restoration and a fresh verified GNSS fix.
Licensed-binary device tests still must prove those callback and interruption
paths; release verification remains blocked until that evidence exists.
The device-acceptance ledger keeps this pending rather than allowing App Store
Connect processing alone to mean release-ready. The public GitHub repository
currently has no protected `main` or protected release environment.
`verify-github-release-governance.mjs` now rejects release unless the exact
commit is the protected `main` head, the app-bound HERE source check is green,
stale/last-push review rules and admin enforcement are enabled,
force-push/deletion are disabled, and `here-offline-release` has independent
reviewers with protected-branch-only deployment. Repository administration must
enable those controls; a local environment variable cannot self-approve them.

## Release acceptance

Simulator and cache-only checks are insufficient. On a real iPhone:

1. Install one small region online and verify its bytes, layers, and catalog
   version.
2. Force-quit and cold-launch in airplane mode to prove same-boot restoration.
   Then reboot and confirm the trusted-time boundary fails closed until a newer
   signed response re-anchors it; do not treat that deliberate denial as
   cross-reboot offline parity.
3. Verify native vector pan/zoom, local place/address/category search,
   dimensioned truck routing, visual guidance, installed TTS voice, GPS
   progression, deviation, local rerouting, and approaching/outside-coverage
   transitions.
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

Keep the raw packet capture and device evidence in one owner-private directory;
never commit or upload them from the public repository. After independent
approval, bind them to the exact schema-3 release ledger:

```sh
node scripts/verify-here-offline-device-acceptance.mjs \
  --evidence=/private/device-acceptance.json \
  --ladder=/private/release-ladder.json \
  --capture=/private/radio-silent.pcap \
  --network-summary=/private/network-summary.json

node scripts/release-ladder-status.mjs \
  --file=/private/release-ladder.json
```

Offline Wikipedia-style editorial guides are not a HERE SDK capability. They
require a separately licensed, versioned, downloadable EusoTrip content lane.
This contract targets EusoTrip's road/truck freight operations plus signed
server-canonical Rail and Vessel itineraries. It must not be described as
consumer hiking/cycling, contour/elevation, or editorial-guide parity with
Organic Maps unless those separately modeled, licensed, and device-proven
capabilities are added.
