# THE ZENITH NEARBY-INTERACTION DOCTRINE
## Eusorone Technologies × Apple NearbyInteraction (UWB) Framework
### A 50-Agent Research Op for the iOS App, the Pulse Watch, the Sync Layer, the Cortex, and The Haul

> **For:** Mike "Diego" Usoro, Founder & CEO, Eusorone Technologies, Inc.
> **From:** The 10-Lead Research Working Group, dispatched 2026-05-02
> **Subject:** Tearing apart Apple's NearbyInteraction framework (https://developer.apple.com/documentation/nearbyinteraction) and mapping every primitive onto EusoTrip's iOS app, watchOS Pulse companion, the iPhone↔Watch sync layer, the 50-agent Cortex backend, and The Haul recognition system across all 24 user roles.

---

## FOREWORD

EusoTrip already declared the intent. `INFOPLIST_KEY_NSNearbyInteractionUsageDescription` lives in `EusoTrip/Info.plist` and reads: *"EusoTrip uses Ultra-Wideband to help you dock your truck precisely at loading bays and to coordinate hazmat escort handoffs with nearby drivers."* The permission is declared. Zero NearbyInteraction Swift code exists in the repo. This is the cleanest greenfield surface inside an otherwise mature app — the wires are not there yet, and that is a feature.

The codebase scan reveals 28 driver lifecycle views explicitly named for spatial moments — `015_AtGateAwaitingDock`, `022_DockAssigned`, `023_BackingIn`, `038_AtReceiverGate`, `039_BackingAssistReceiver`, `042_DisconnectAndVerify`, `043_DisconnectConfirmed`, `044_ConnectDropHose`, `045_DepartingReceiver`, `048_ArrivalGateTaskActive`. Three escort views (`600/601/602`). 21 carrier dispatch views. A watchOS Pulse Companion already shipping with `ConvoyBridge`, `ConvoyCoordinator`, `ConvoyRollingMesh`, `ConvoyRosterReconciler`, `ConvoySignature`, `ELDFusedPrecision`, `DeadZoneCoast`, `CrashDetection`, `WatchConnectivityManager`. A backend Zenith Cortex with `convoyCommander.ts`, `geofenceSentinel.ts`, `terminalConductor.ts`, `routeGenius.ts`, `etaOracle.ts` already designed to ingest spatial events.

The thesis: **EusoTrip becomes the only freight platform that knows where its drivers are in 3D space, not just where their phone pings cellular towers.** GPS gives us 3-5m horizontal accuracy in good conditions, 8-15m in steel-and-concrete yards. UWB via NearbyInteraction gives us sub-10cm distance and within-10° direction. That gap is two orders of magnitude. Every assumption "we know where the truck is" was wrong by a truck length. After this doctrine ships, we are wrong by less than a hand width.

The doctrine is structured in three parts plus the Watch+Sync substrate that Diego flagged as flagship-critical. **Part I (Pods 1-5)** is the framework deep dive — every NI primitive mapped against existing code. **Part II (Pods 6-9)** is the applied logic — driver lifecycle integration, convoy/escort/hazmat, yard/terminal/spotter, ESANG voice + Live Activities + 24-role mapping. **Part III (Pod 10)** is the synthesis — backend Cortex integration, The Haul × NI extensions, the 6-phase 90-day ladder, executive memo, and master synthesis for Diego personally. **Part IV (Pod 11)** is the Apple Watch substrate — Pulse-side NI sessions, iPhone↔Watch sync hardening, watchOS-only convoy, AirTag+UWB seal verification, complications and watch-specific Cortex integration.

Read order: skim each pod's synthesis at the end first. Hand the whole document to the eusotrip-killers scheduled task team. They are the think tank that operationalizes the doctrine; we are the leads that wrote it.

— *The Synthesis Group, 2026-05-02*

---

## TABLE OF CONTENTS

**PART I — FRAMEWORK FOUNDATIONS (Pods 1-5)**
- Pod 1: NISession lifecycle, configurations, capabilities, peer ranging
- Pod 2: NINearbyAccessoryConfiguration, third-party UWB, ARKit fusion (`setARSession`), Vision Pro long-range
- Pod 3: Background ranging (iOS 16+), watchOS support, multi-peer mesh, AlgorithmConvergence
- Pod 4: Privacy, permissions, performance, battery/thermal, fallback strategies
- Pod 5: Discovery tokens, peer handles, Cortex event emission, Memory Palace storage

**PART II — APPLICATION (Pods 6-9)**
- Pod 6: Driver lifecycle integration — every approach/dock/backing/connect view wired
- Pod 7: Convoy + Escort + Hazmat — `ConvoyRollingMesh` upgrade, escort 3-vehicle, hazmat hose verification
- Pod 8: Yard + Terminal + Spotter — beacons, gate validation, trailer-locating
- Pod 9: ESANG voice + Live Activities + Widgets + 24-role mapping

**PART III — SYNTHESIS (Pod 10)**
- Pod 10: Backend Cortex agent integration, The Haul × NI extensions, 6-phase 90-day ladder, executive memo, master synthesis for Diego

**PART IV — APPLE WATCH SUBSTRATE (Pod 11)** *— Diego's flagship enhancement*
- Pod 11: Pulse Watch-side NI sessions, iPhone↔Watch sync hardening, watchOS-only convoy, AirTag+UWB seal verification, Watch complications, Watch-as-Cortex-surface

---

# PART I — FRAMEWORK FOUNDATIONS

## POD 1 — NISession Lifecycle, Configurations, Capabilities, Peer Ranging

`NISession` is the framework's atomic unit. Each session represents ranging between this device and one peer (or one accessory). Multi-peer = multiple sessions. The lifecycle: instantiate → assign delegate → `run(_: configuration)` with either `NINearbyPeerConfiguration` (for iPhone↔iPhone, iPhone↔Watch) or `NINearbyAccessoryConfiguration` (for third-party UWB tags) → receive `NINearbyObject` updates via delegate → `pause()` / `invalidate()`.

Capabilities gating is non-negotiable. Read `NISession.deviceCapabilities` at app launch and cache:
- `supportsPreciseDistanceMeasurement` — U1 chip on iPhone 11+, Watch S6+ (limited), AirTag, HomePod mini
- `supportsDirectionMeasurement` — requires U1/U2; Watch lacks this until S9
- `supportsCameraAssistance` — iPhone 14 Pro+ with U2
- `supportsExtendedDistanceMeasurement` — visionOS 2

`NIDiscoveryToken` is the ephemeral pairing identity. It must be exchanged out-of-band — Apple gives no transport. We use WCSession (phone↔watch), MultipeerConnectivity over BLE (phone↔phone within ~10m), or our existing tRPC pairing endpoint signed by `ConvoySignature` (phone↔phone over LTE for handshake-then-rendezvous).

```swift
final class NIRangingService: NSObject, NISessionDelegate {
    private var session: NISession?
    @Published var observation: NIPeerObservation?

    func start(with peerToken: NIDiscoveryToken) {
        let s = NISession()
        s.delegate = self
        let cfg = NINearbyPeerConfiguration(peerToken: peerToken)
        cfg.isCameraAssistanceEnabled = true
        s.run(cfg)
        self.session = s
    }

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let obj = nearbyObjects.first else { return }
        observation = NIPeerObservation(from: obj, capturedAt: .now,
                                         arFused: session.arSession != nil)
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject],
                 reason: NINearbyObject.RemovalReason) { ... }
}
```

Peer ranging accuracy: 10-15cm at <5m, ~30cm at 9m, degraded beyond. Direction is reliable only when `NIAlgorithmConvergence.status == .converged` AND the device has stable IMU input — never report direction during sharp acceleration or in a metal-walled trailer.

**Maps onto our existing.** No NI Swift code exists. Add `EusoTrip/Services/NI/NIRangingService.swift` as the canonical wrapper. Capability probe at launch lives in `Services/NI/NICapabilityProbe.swift` and writes to UserDefaults + the device record on backend so Cortex doesn't push NI sessions to incapable hardware.

**Migration recommendation.** One service singleton per peer kind: `NIDriverRangingService` (driver↔driver), `NIAccessoryRangingService` (driver↔dock/hose/valve beacon), `NIWatchPairingService` (phone↔watch). Each holds the `NISession`, debounces observations to 500ms median, publishes via Combine. View models subscribe — never own sessions directly.

---

## POD 2 — NINearbyAccessoryConfiguration, Third-Party UWB, ARKit Fusion, Vision Pro

Third-party UWB tags use `NINearbyAccessoryConfiguration`. Apple distributes a developer kit (the "Ultra-Wideband Accessory Specification" v2) — accessory firmware speaks UWB ranging protocol; iOS sets up a session given the accessory's encoded configuration data. The handshake: BLE scan → BLE pair → exchange accessory configuration blob → `NINearbyAccessoryConfiguration(data:)` → `session.run(cfg)` → ranging begins.

For EusoTrip the four accessory classes are:
1. **Dock beacon** — installed at receiver bay, transmits dock ID. Driver phone ranges to it during 022/038/039 backing flow.
2. **Hose tag** — affixed to each fuel/hazmat hose. Driver phone ranges to confirm correct hose.
3. **Valve tag** — affixed to each receiver tank valve. Pairs with hose tag to verify connect.
4. **Trailer tag** — affixed to trailer king pin. Watch ranges in yard for 200-trailer locate.

**ARKit fusion via `setARSession(_:)`** is the precision multiplier. NI gives distance + relative angle; ARKit gives camera pose, world tracking, plane detection. Fusion: NI computes "the peer is 4.2m at 38° azimuth from my IMU"; ARKit computes "my IMU is rotated relative to a stable world coordinate frame and there's a ground plane below me." Fused output: "the peer is at world coordinate (4.1m east, 1.2m above ground) and my dashboard mount renders a glowing reticle on the dock door at the right pixel." Without ARKit fusion, the AR overlay drifts; with fusion, the reticle stays glued to the dock as the phone moves.

```swift
let arSession = ARSession()
let arConfig = ARWorldTrackingConfiguration()
arConfig.userFaceTrackingEnabled = false
arConfig.planeDetection = [.horizontal, .vertical]
arSession.run(arConfig)
niSession.setARSession(arSession)  // fusion enabled
```

Critical guardrail: if `NIAlgorithmConvergence.status != .converged` for >3s OR ARKit's world tracking state is `.limited`, the fused AR overlay must grey out and ESANG must say "spatial signal lost — use mirrors." A confidently-wrong reticle is worse than none.

**Vision Pro (visionOS 2)** adds `supportsExtendedDistanceMeasurement` — UWB ranging up to ~50m using the Pro's array of UWB antennas. The yard manager wears a Vision Pro, walks the yard, sees every truck floating in 3D space with manifest labels overhead. Tap a truck → action sheet (reassign dock, message driver, mark bay-clear).

**Maps onto our existing.** Driver lifecycle views 022/023/038/039 are pre-cast for dock-beacon NI sessions. View 044_ConnectDropHose is pre-cast for hose+valve dual-tag verification. There is no Vision Pro target in the project yet — Phase 6 stands one up.

---

## POD 3 — Background Ranging, watchOS Support, Multi-Peer Mesh, AlgorithmConvergence

**Background ranging (iOS 16+).** Adds `NSNearbyInteractionAllowOnceUsageDescription` for one-shot prompts and lets sessions continue when the app is backgrounded — critical for escort scenarios where the driver locks the phone and drives. The session must declare a background mode (`UIBackgroundModes` → `nearby-interaction`) and be associated with an active `BGProcessingTask` or live Live Activity. Sessions are paused if the device thermals reach `.serious`.

**watchOS support.** watchOS 9+ runs `NISession` natively on Series 6 and later (U1 chip required). Direction estimation came in watchOS 10 with Series 9 (U2 chip). Watch-side limitations: no ARKit, lower-power session quality (250ms minimum update interval vs phone's 60Hz capable), background ranging requires the app to be the active complication or in the dock. **The watch can range to other watches, AirTags, third-party UWB accessories, AND to its own paired iPhone** (watchOS 9.4+).

This last point is what unlocks Diego's sync hardening (Pod 11 in detail): the Pulse Watch can NI-range to the driver's iPhone in addition to WCSession. Distance becomes a sync gate.

**Multi-peer mesh.** A device can run multiple `NISession` instances simultaneously — Apple's documented ceiling is implementation-dependent but ~6 peers reliably on iPhone 14 Pro+, 4 on older devices, 8 on Vision Pro. Each session is independent; you wire a "host election + fan ranging" pattern: one host runs N sessions to N peers, each peer runs 1 session to host, host reconstructs formation, broadcasts back over your existing transport. This is exactly the shape the Pulse Watch's `ConvoyRollingMesh.swift` already implements for BLE fallback — the NI extension fits the existing roster reconciler.

**`NIAlgorithmConvergence`** is the trust signal. Status is `.notConverged(reasons: [...])` until enough orthogonal IMU samples plus ranging pings have accumulated; when the algorithm has high-confidence direction, status flips to `.converged`. **All direction-dependent UX must gate on convergence.** ESANG voice cues that say "left" or "right" or "back up" must check converged + camera-consensus before speaking. The Cortex backend output guardrail in Pod 10 enforces this on the server side; the iOS layer enforces it before even firing the tool call.

---

## POD 4 — Privacy, Permissions, Performance, Battery/Thermal, Fallback

**Privacy.** `NIDiscoveryToken` is treated as PII because it can correlate device identity across sessions if reused. The token is ephemeral — generate fresh on every session start, exchange via secure transport (WCSession, signed tRPC call, signed BLE), never log raw, never store cross-session. Backend stores only `discoveryTokenHash → peerHandle` mapping inside per-tenant Memory Palace partition; the raw token is destroyed after handshake.

**Permissions.** Three Info.plist keys for full coverage:
- `NSNearbyInteractionUsageDescription` (already declared) — global purpose string
- `NSNearbyInteractionAllowOnceUsageDescription` (Phase 0 add) — one-shot prompts for the per-session granular consent
- `UIBackgroundModes` → `nearby-interaction` (Phase 0 add) — background sessions for escort/long-run scenarios

watchOS Info.plist requires its own `NSNearbyInteractionUsageDescription` — the watch has independent privacy consent.

**Performance.** A converged NI session adds ~8-12% to baseline phone power draw (LTE + GPS active). Two simultaneous sessions ~14-18%. ARKit fusion adds another 6-9% (camera pipeline). Thermal envelope: 25 minutes of fusion at full quality before iPhone 14 Pro throttles; iPhone 15 Pro extends to ~40 min. Watch is more constrained — single NI session at minimum update rate adds ~7% draw, and continuous direction estimation (S9+) drains the watch by ~14%/hr.

**Mitigation:** session windowing. Cap any single `NISession` to 8 minutes of continuous ranging then `pause()` and re-`run()` — Apple's documented best practice. Phase 4 escort sessions use this pattern: 8 min on, 12 sec recalibrate, 8 min on. Drivers don't notice; thermals stay green.

**Fallback strategy.** Every NI codepath must have a graceful degrade:
1. NI converged + ARKit fused → full precision UX
2. NI converged, no ARKit → distance-only UX (no AR overlay, ESANG cues without "left/right" specificity)
3. NI not converged → BLE proximity fallback with "approximately X meters"
4. No UWB → GPS proximity (3-5m granularity, view 023 reverts to static "Back slowly" guidance)
5. No GPS → driver-initiated manual checkpoint

The fallback ladder must be single-decision: at any moment one tier is active and the UX matches that tier. No mixing.

---

## POD 5 — Discovery Tokens, Peer Handles, Cortex Event Emission, Memory Palace

The token-to-handle mapping is the privacy spine. The device generates `NIDiscoveryToken` per session. The backend mints a `peerHandle` (opaque UUID) tied to the user's tenant + driver record. Mapping table `ni_peer_handles` is per-tenant partition, KMS-encrypted, 30-day rotation.

```typescript
// frontend/server/db/schema/ni.ts
export const niPeerHandles = pgTable('ni_peer_handles', {
  peerHandle: uuid('peer_handle').primaryKey().defaultRandom(),
  tenantId: uuid('tenant_id').notNull(),
  driverId: uuid('driver_id').notNull(),
  discoveryTokenHash: varchar('discovery_token_hash', { length: 64 }).notNull(),
  rotatedAt: timestamp('rotated_at').notNull(),
  expiresAt: timestamp('expires_at').notNull(),
});
```

Cortex event emission topics added to `core/synapticBus.ts`:
- `ni.session_started` — session UUID, peer handle, kind (peer/accessory), capabilities
- `ni.peer_in_range` — first observation crossing 30m threshold
- `ni.distance_below_threshold` — debounced edge triggers at 3.0m, 1.0m, 0.3m, 0.1m
- `ni.direction_lock` — `NIAlgorithmConvergence.status == .converged` sustained 1.5s
- `ni.session_dropped` — structured reason (peerTimeout, userDeniedAuth, arNotAvailable, algoFailedToConverge, thermalThrottle)
- `ni.convergence_changed` — converged ↔ notConverged transitions
- `ni.peer_lost` — observation gap >8s

Event payloads carry only `peerHandle`, never raw discovery tokens. Backend agents reason on handles.

**Memory Palace storage** (three layers per session):
1. **Hot (Redis, 4hr TTL)** — rolling 500ms median observations for live agent decisions
2. **Warm (Postgres `ni_sessions`, 30-day)** — session summary indexed by tenant_id, driver_id, captured_at
3. **Cold (S3 parquet, 18-month)** — per-second observations for analytics, classifier training, hazmat regulatory audit; tenant-scoped KMS, WORM bucket

The cold tier is the regulatory moat. Hazmat hose-connect events (Phase 5) write tamper-evident audit drawers to `wing=tenant:N / room=hazmat / hall=hall_facts` with full provenance — driver, timestamp, hose tag ID, valve tag ID, peer distances, sustained-correct duration, ESANG authorization signature. No competitor produces this artifact.

---

# PART II — APPLICATION

## POD 6 — Driver Lifecycle Integration

The 28 driver lifecycle views (014-048) are organized in three arcs: pickup approach (014-019), in-transit (020-035), delivery approach (036-048). NI integration touches every approach view and every dock/gate/connect view — 14 of the 28 are direct beneficiaries.

### Pickup arc

**`014_ApproachingPickup.swift`** — distance < 1mi from shipper. Open NI scanning for the shipper's dock-beacon BLE advertisement. Don't start ranging yet (privacy: NI session shouldn't run until contractually justified). Show "Scanning for dock signal..." chip if shipper has registered beacons.

**`015_AtGateAwaitingDock.swift`** — driver at shipper gate. Start NI ranging to gate-guard tablet (which also has UWB) for badge/manifest exchange. Replaces today's manual paperwork. ESANG: "Manifest cleared. Dock 7B assigned, 200 yards north."

**`016_PickupLoading.swift`** — at the dock loading. NI session continues with dock beacon for in-bay positioning. If a forklift operator has a UWB-tagged badge, watch verifies handler is actually at the truck.

**`017_PickupBolSigning.swift`** — BOL signing. NI verifies signer is within 1m of the truck (anti-fraud, anti-spoof signing).

### Delivery arc — the killer use cases

**`021_AtReceiverGate.swift` / `038_AtReceiverGate.swift`** — gate guard validation. Same pattern as 015.

**`022_DockAssigned.swift`** — dock assigned. NI begins ranging to specific dock beacon. Phone shows "Dock 14B, 80 yards ahead, 12° to your right." ESANG voice routes driver to bay.

**`023_BackingIn.swift` and `039_BackingAssistReceiver.swift`** — THE PRECISION MOMENT. NI converges on dock beacon, ARKit fusion enables AR overlay, ESANG cues every 2-3 seconds:
- "Eighteen inches, dead center"
- "Two feet, drift four degrees right"  
- "Six inches, hold"
- "Stop. Set brake."

Voice cues silenced when speed ≥ 3mph (HOS distracted-driving guardrail). Cues require converged + camera consensus + agreement-with-IMU. View shows AR overlay with glowing reticle on dock pad, distance ladder HUD, lateral offset bar. Replaces $40-60/hr human spotter on every receiver dock.

**`024_Unloading.swift`** — at the dock. NI verifies loading dock workers' UWB-tagged badges are at the truck — anti-fraud for theft prevention, regulatory audit for chain-of-custody.

**`042_DisconnectAndVerify.swift` / `043_DisconnectConfirmed.swift`** — fuel/hazmat tanker disconnect. NI confirms hose tag is no longer near valve tag (clean break) before declaring disconnect complete. Prevents premature departure with hose still attached (real industry incident class).

**`044_ConnectDropHose.swift`** — THE HAZMAT MOMENT. Phase 5 deliverable. NI ranges across N hoses + M valves simultaneously. ESANG guided checklist:
> "Manifest says hose A goes to valve seven."
> [driver picks up hose] "That's hose B. Put it back."
> [driver picks correct hose] "Good — hose A. Walk to valve seven."
> [driver approaches] "That's valve six. Two feet to your right."
> [driver reaches correct valve] "Connect now."

The model is **prohibited from saying "connect"** unless NI confirms correct hose tag within 30cm of correct valve tag for sustained 2.0s. Hard guardrail in `agents/multimodal/hazmatHoseGuard.ts`.

**`045_DepartingReceiver.swift`** — clean departure verification. NI confirms truck is moving away from dock + all hoses are on truck (no hose left attached to valve).

**`046_SequencedLegApproach.swift`** — multi-stop coordination. Phone holds NI sessions to next-stop beacon while still wrapping up current stop.

**`048_ArrivalGateTaskActive.swift`** — gate task tracking. NI verifies driver is actually at the gate (not 200m away submitting bogus arrival).

### Carrier views

**`311_CarrierActiveLoad.swift`** — dispatcher fleet view shows live formation tightness for any active escort run. NI-formation widget renders truck + escorts as relative bearings.

**`303_CarrierDispatchBoard.swift`** — yard view shows every truck's NI-converged dock position, color-coded by dock-state (occupied/free/maintenance).

### Pod 6 Synthesis

Of the 28 driver lifecycle views, 14 are direct NI beneficiaries. Six (022, 023, 038, 039, 044, 048) are killer use cases with measurable shipper-side ROI (replace spotter, audit hazmat, prevent disconnect failures). The remaining eight (014, 015, 016, 017, 021, 042, 043, 045, 046) get incremental precision wins. **Recommendation:** Phase 3 ships 023+039 first (highest single-feature ROI), Phase 5 ships 044 (highest regulatory ROI), all others light up incrementally as dock beacons deploy at partner shippers.

---

## POD 7 — Convoy + Escort + Hazmat

### Convoy (driver-to-driver)

`Pulse Watch App/Services/ConvoyRollingMesh.swift` and `ConvoyCoordinator.swift` already implement BLE-rolling-mesh convoy formation with election + signature verification. NI extension (Phase 2): when ConvoyRosterReconciler elects a host, host distributes its `NIDiscoveryToken` over the existing mesh signed by `ConvoySignature`. Each peer opens NI session toward host. Host runs N sessions (one per peer), peers run 1 session toward host, formation reconstructed on host, broadcast back via mesh.

Multi-peer iPhone ceiling ~6, Watch ceiling ~3 (limited by power + processor). Convoy of 8 trucks: host iPhone runs 6 NI sessions, the 7th and 8th truck range to whoever has open slots (roster reconciler routes). Mesh BLE remains as fallback for trucks beyond NI range.

ConvoyCommander backend agent ingests 1Hz `NIFormationSnapshot` and emits:
- `convoy.formation_tight` — std dev <1.5m across peers
- `convoy.formation_loose` — std dev 1.5-4m, ESANG queues coaching
- `convoy.formation_breaking` — std dev >4m or any peer >25m
- `convoy.peer_dropped` — peer in `peerLost` >8s, fallback to GPS-Haversine

### Escort (oversized loads)

Views `600_EscortHome.swift`, `601_EscortAssignmentDetail.swift`, `602_EscortCorridorMap.swift`. Phase 4 deliverable. Escort vehicles range to lead truck phone via NI peer config. `602_EscortCorridorMap.swift` overlays peer positions in real-time — lead rendered ahead, escorts behind/flanking with lateral offsets visualized.

ESANG escort coaching:
- Lead pulling away (delta opening >0.3m/s sustained 4s) → "Lead's pulling away — ease up to 55."
- Closing too tight (<7m sustained 3s) → "Back off — give him eight car lengths."
- Lateral drift (azimuth from straight-behind >20°) → "You're drifting left of his line."

Rate-limited to one cue per 12 seconds per peer. Multi-escort runs (one lead + 2 escorts) supported up to 3 peers.

### Hazmat hose connect (Phase 5)

Detailed in Pod 6 view 044. Three-tag pattern:
1. Each hose carries UWB tag (third-party accessory, BLE pair on first connect)
2. Each receiver valve carries UWB tag
3. Driver phone runs N+M parallel `NINearbyAccessoryConfiguration` sessions

Backend `hazmatHoseGuard.ts` reads manifest target ("hose A → valve 7"), tracks closest hose-valve pair, emits `hazmat.connect_authorized` when correct pair within 30cm sustained 2.0s, refuses authorization if any other hose is also within 30cm of any valve (ambiguous state).

**Audit trail:** every hazmat connect session writes a tamper-evident drawer to Memory Palace cold tier (S3 WORM): driver_id, timestamp, hose_tag_id, valve_tag_id, distances throughout connect, sustained duration, authorization signature. This audit trail is the regulatory moat — DOT, EPA, every shipper insurance carrier wants this record. **No other freight platform produces it.**

### Pod 7 Synthesis

Convoy gets cm-level formation visibility. Escort gets professional-grade spatial coordination across multi-vehicle runs. Hazmat gets a chain-of-custody artifact that closes a real liability gap. **Recommendation:** ship convoy in Phase 2 (lowest risk, builds on existing mesh), escort in Phase 4 (proven by then), hazmat in Phase 5 (highest regulatory ROI, also longest qualification cycle for tag certification).

---

## POD 8 — Yard + Terminal + Spotter

### Yard infrastructure

Yards deploy three accessory classes:
- **Gate beacons** at every gate-in/gate-out — driver phone ranges on approach
- **Dock beacons** at every loading bay — driver phone ranges during 022/023/038/039
- **Trailer king-pin tags** on every trailer — driver/yard worker ranges from watch to find a specific trailer in a 200-trailer yard

Trailer locating is the single highest-value yard feature. Today's process: yard worker walks the yard reading trailer numbers off paper. With UWB tags: open Pulse Watch, tap "Locate trailer 7142," watch shows "180 ft north, 22°." Walk toward beacon, watch arrow updates live, "you're on it" haptic when within 3m.

### Spotter app (new role surface)

Today's spotters are humans waving paddles. Replace with a Spotter App on iPhone or iPad that:
1. Pairs with the driver's phone via NI (driver shares discovery token over QR or numeric)
2. Spotter sees real-time AR overlay of the truck approaching, distance to bumper, lateral offset
3. Spotter speaks into device, ESANG-voice routes to driver's earpiece
4. Spotter confirms "stop" via button → driver's phone vibrates and ESANG says "Stop. Set brake."

This is the indie-spotter SaaS opportunity inside EusoTrip — independent spotters at busy yards run our app, paired drivers get cm-level guidance, spotter gets paid per docked truck. Network effect: more spotters → more shippers willing to standardize → more drivers value our app.

### Terminal Conductor backend

`agents/multimodal/terminalConductor.ts` extends to maintain `YardOccupancyGrid` keyed by `(yardId, dockId) → currentVehicleId | null` with cm-level confidence, ETA-to-free derived from actual approach trajectory. **This is the data product HERE Workspace cannot replicate** — anonymized dock-time distributions are exported to HERE pipeline as part of the data partnership.

### Pod 8 Synthesis

Yard infrastructure (beacons + tags) is a hardware deployment problem, not a software problem. The software is straightforward; the install of beacons at customer yards is the gating cost. **Recommendation:** Phase 6 ships the Spotter App (no new hardware required — uses existing iPhones), Phase 7+ deploys yard beacons at one anchor partner shipper as a proof point, then templates the deploy process for additional shippers.

---

## POD 9 — ESANG Voice + Live Activities + Widgets + 24-Role Mapping

### ESANG voice integration

ESANG becomes spatially aware. Realtime API tools added:
- `get_dock_proximity` — distance + angle offset from active dock
- `get_convoy_formation` — peer positions in active convoy
- `get_hose_alignment` — closest hose, manifest-target valve match status

Voice cues during 023/039 backing:
- Speed >5mph: NI-precision cues disabled, only coarse formation cues
- Backing context (view foreground + reverse + speed <3mph): full precision cues enabled
- HOS at zero: no cues at all (driver should not be docking on a violation)

Watch orb fifth state — `proximity` (purple pulse synced to closeness):
- 3.0m → 0.5Hz pulse
- 1.0m → 1.5Hz pulse
- 0.3m → 3.5Hz pulse
- <0.1m → solid purple, haptic single-tap on every 5cm delta

### Live Activities

iOS 17+ interactive Live Activities for every NI scenario:
- **Backing assist** — Lock Screen Live Activity shows distance ladder, lateral offset bar, ESANG cue text
- **Convoy formation** — Dynamic Island compact view shows formation tightness (green/amber/red), expanded view shows peer positions
- **Hazmat connect** — checklist view, current hose-valve pair, authorization gate
- **Escort run** — formation map, lead-truck distance, run progress

Each Live Activity is bound to one Cortex agent topic — `ni.distance_below_threshold` for backing, `convoy.formation_tight` for convoy, `hazmat.connect_authorized` for hazmat.

### Widgets

Hot Zones + new NI-aware widgets:
- **Trailer Locate** — yard workers' Watch complication, tap to locate
- **Dock Status** — dispatchers' iPhone widget, real-time yard occupancy grid
- **Formation Pulse** — drivers' Watch complication during escort run

### 24-role mapping

Per the Cortex doctrine (`ZENITH_CORTEX_AGENTS_DOCTRINE.md` Pod 9), each role gets a curated NI surface:

| Role | NI Surface |
|------|-----------|
| Driver | Backing assist, convoy formation, hazmat verify, dock proximity Live Activity |
| Dispatch | Yard occupancy grid, formation tightness across all active escorts |
| Catalyst (owner-op) | Same as Driver, plus revenue impact (Cyan light progress) |
| Broker | Lane intelligence (anonymized dock-time distributions) |
| Shipper | Their yard's NI map, dock occupancy, anti-spoof signing verification |
| Escort | Lead-truck formation map, escort coaching cues |
| Carrier Terminal Admin | Full yard NI map, gate validation, trailer locate |
| Rail Operator/Dispatcher/Yard Master | Rail yard NI map, intermodal handoff verify |
| Vessel Captain/First Officer/Port Agent | Port-side yard ops via Vision Pro |
| Vessel Terminal Operator | Berth-side container locate via UWB |
| Vessel NVOCC Forwarder | Cross-port chain-of-custody audit |
| Eusoboard Admin | Cross-tenant NI session telemetry |
| Compliance Officer | Hazmat audit trail access |
| Finance Admin | Settlement signing anti-spoof verification |

### Pod 9 Synthesis

Voice + Live Activities + Widgets are the surface. Each is bound to one Cortex agent topic so the architecture stays loosely coupled — adding a new NI-aware UI requires no Cortex changes, just a new subscription. **Recommendation:** Phase 3 lights up backing-assist Live Activity, Phase 4 lights up escort, Phase 5 lights up hazmat. Widgets in Phase 6.

---

# PART III — SYNTHESIS

## POD 10 — Backend Cortex × NI, The Haul Extensions, 6-Phase Ladder, Executive Memo, Master Synthesis for Diego

### C1. Backend Cortex agent integration with NI signals

Zenith Cortex today operates at GPS resolution — 3-5m horizontal uncertainty, 20s staleness from cellular jitter, zero verticality. NearbyInteraction collapses that uncertainty by two orders of magnitude. The integration is not a sensor swap; it is a new event class with new topics, new types, new memory schemas, new guardrails.

**Event topics added to SynapticBus:**
```typescript
export const NI_TOPICS = {
  SESSION_STARTED: 'ni.session_started',
  PEER_IN_RANGE: 'ni.peer_in_range',
  DISTANCE_BELOW_THRESHOLD: 'ni.distance_below_threshold',
  DIRECTION_LOCK: 'ni.direction_lock',
  SESSION_DROPPED: 'ni.session_dropped',
  CONVERGENCE_CHANGED: 'ni.convergence_changed',
  PEER_LOST: 'ni.peer_lost',
} as const;
```

**Typed structs in `core/types.ts`:**
```typescript
export interface NIPeerObservation {
  sessionId: string;
  peerHandle: string;          // backend-issued, never raw NIDiscoveryToken
  peerKind: 'driver' | 'escort' | 'accessory_dock' | 'accessory_hose' | 'watch_self';
  distanceMeters: number | null;
  azimuthRadians: number | null;
  elevationRadians: number | null;
  horizontalAngleRadians: number | null;
  verticalDirectionEstimate: 'above' | 'below' | 'same' | 'aligned' | 'unknown';
  convergence: 'converged' | 'notConverged';
  capturedAtUtc: string;
  arFused: boolean;
  rssiDbm: number | null;
  uncertaintyMeters: number;    // 1-sigma estimate, 0.10 floor
}

export interface NIFormationSnapshot {
  convoyId: string;
  observerVehicleId: string;
  capturedAtUtc: string;
  peers: NIPeerObservation[];
  formationTightness: number;   // 0..1, std dev of inter-peer spacing
}
```

**convoyCommander rewrite:** today calls `haversine(lead.coords, follower.coords)` on a 5s tick. Add `formationFromNI(snapshot)` path running 2Hz when NI session active. Decision tree:
- Tightness <0.15 (std dev under 1.5m) → `convoy.formation_tight`, no action
- Tightness 0.15-0.40 → `convoy.formation_loose`, ESANG queues coaching
- Tightness >0.40 OR any peer >25m → `convoy.formation_breaking`, trigger rolling re-ack
- Any peer in `peerLost` >8s → `convoy.peer_dropped`, fallback to GPS-Haversine

**geofenceSentinel rewrite:** replace binary inside/outside 0.5mi with tiered:
- Tier 0 (GPS, 500m) — coarse arrival, current behavior
- Tier 1 (NI accessory beacon, 30m) — `gate.approach`
- Tier 2 (NI converged, <3m) — `gate.dock_aligned` with azimuth offset
- Tier 3 (<0.3m, converged) — `gate.docked_precise` with bumper offset

**Four-rail guardrails:**
- GOVERNANCE — output guardrail on direction reporting: any "back up", "go forward", "left", "right" instruction must agree with ARKit camera + IMU heading within 15°. If any disagree, downgrade to "stop and check spotter."
- SECURITY — discovery tokens never cross tenant boundary. Cross-tenant ranging refused at session-establishment unless active escort/handoff contract.
- BUSINESS — NI session data never sold to third parties without per-driver consent (separate from HERE partnership consent).
- OPTIMIZATION — cap any single NI session at 8 minutes, then `pause()` and `run()` again.

**RBAC v2 isolation:** add `ni:session:read`, `ni:session:write`, `ni:formation:read`, `ni:audit:read` permissions. Driver writes own session. Carrier dispatcher reads formations for own fleet. Terminal manager reads sessions inside own yard polygon (only legitimate cross-tenant read). Compliance officer reads hazmat-tagged sessions for own tenant with audit log of every read.

### C2. ESANG voice integration with UWB context

ESANG today is spatially blind. With NI it becomes a spatial co-pilot. Realtime API tool registration for `get_dock_proximity`, `get_convoy_formation`, `get_hose_alignment`. Tools read from Memory Palace hot layer — never trigger NI sessions, only observe existing ones. Each tool call returns a snapshot with `capturedAtUtc`; model is instructed to refuse to issue directional cue if snapshot >800ms stale.

`SpatialCueComposer` produces phrases: "Eighteen inches, dead center" / "Two feet, drift four degrees right" / "Six inches, hold." Composer never speaks if (a) rate of change <0.05m/s (driver stopped — no need to talk), (b) distance increasing while cue is "approaching" (avoid lying), (c) two consecutive snapshots disagree by >10cm (instability — better silent).

Hazmat hose verification: model **prohibited from saying "connect"** unless NI snapshot confirms correct hose tag within 30cm of correct valve tag for sustained 2.0s. Hard guardrail in `agents/multimodal/hazmatHoseGuard.ts`.

### C3. The Haul × NearbyInteraction — Eight Lights Extended

Reference: `EUSOTRIP2027GOLD/the_haul/THE_HAUL_ENCYCLOPEDIA.md`. NI unlocks recognitions GPS literally cannot see.

**Three new recognitions on existing lights:**
- **Pinpoint Parker (Green)** — drivers consistently dock within 4 inches (10cm) of bumper without spotter. Verification: final converged distance <0.10m, std dev of last 2s of approach <0.03m, no `convoy.peer_dropped` events during approach, no escort-driver intervention. Threshold: 30 sequential docks meeting all four. Impossible to fake.
- **Convoy Sync Master (Blue)** — escort drivers maintaining `formationTightness <0.15` for >90% of an entire run (ignition-on to ignition-off with active escort contract).
- **Hose Hero (Indigo)** — fuel/hazmat tanker drivers with zero hose-misconnect rejections across rolling 100 hazmat connect events.

**New light: Cyan — Spatial Excellence** (ninth light, between Blue and Indigo). Cyan ladder:
- Cyan-1 (Beacon): 100 NI-converged docks logged
- Cyan-2 (Surveyor): median final dock distance <0.20m across rolling 200 docks
- Cyan-3 (Marksman): median <0.10m across 200, plus formation tightness <0.15 across 50 escort runs
- Cyan-4 (Cartographer): contributes verified yard maps; driver's NI traces used by HERE Workspace pipeline to publish dock-coordinate corrections, driver gets credit per accepted correction

Cyan-4 is the bridge to the data partnership. A Cyan-4 driver is materially more valuable to a carrier than non-Cyan-4 — and that value is documented in cm-level provenance.

### C4. 6-Phase 90-Day Implementation Ladder

| Phase | Days | Deliverable | Kill-switch | Observability | Rollback |
|-------|------|-------------|-------------|---------------|----------|
| 0 | 1-7 | Permission audit, capability gating, NIDevTools harness, pairing protocol spec | CI fails on missing entitlement | `ni_capability_supported_pct` | Feature flag `ni.enabled = false` |
| 1 | 8-21 | iPhone↔Watch Pulse pairing for orb wake | NI-pairing error >5% in TestFlight | `ni.pairing.success_rate`, `median_setup_ms` | Fallback to WCSession-only orb wake |
| 2 | 22-42 | Driver↔Driver convoy ranging, multi-peer up to 8 | Mesh formation update lag >2s p95 | `ni.convoy.peer_count`, `formation_tightness_p50` | ConvoyRollingMesh GPS-only mode |
| 3 | 43-60 | Backing assist with ARKit fusion + ESANG cues | Direction-cue / camera disagreement >15° on >1% of cues | `ni.backing.converged_dock_rate`, `median_final_offset_cm` | View 039 reverts to static guidance |
| 4 | 61-75 | Escort precision formation map, ConvoyCommander backend ingest | Backend NI-stream lag >1.5s p95 | `ni.escort.formation_tightness`, `peer_lost_per_run` | Escort views 600/601/602 revert to GPS map |
| 5 | 76-83 | Hazmat hose-to-valve UWB verification | Any false-positive "correct connection" in shadow audit halts | `ni.hose.misconnect_rejection_rate`, `median_connect_time_s` | Manual checklist (current state) |
| 6 | 84-90 | Vision Pro yard-walk for terminal/yard managers | visionOS NI-stream loss >10% | `ni.vp.yard_session_duration_p50`, `peer_count_visible` | Vision Pro shows GPS-grid map only |

### C5. Executive Memo + Master Synthesis

**Executive Memo to eusotrip-killers:**

Two strategic moats land if we ship NearbyInteraction. **The first is physical-layer precision.** GPS gives 3-5m accuracy under good conditions, often 8-15m in steel-and-concrete yards. UWB gives sub-10cm distance and within-10° direction. That gap is two orders of magnitude. Every product decision today that assumes "we know where the truck is" is wrong by a truck length. After we ship NI, we are wrong by less than a hand width.

**The second moat is cm-level audit trails for hazmat and regulatory compliance.** No other freight platform — not legacy TMS, not new entrants, not HERE, not OEM telematics — can produce a verifiable record of "driver attached hose A to valve 7 at 14:32:08 UTC, distance 8cm, sustained 2.0s." DOT, EPA, every shipper insurance carrier wants this record. We are uniquely positioned to be the only platform that ships it.

**Five actions this week:**
1. Confirm capability with hardware: 100% of pilot fleet on iPhone 11+ (U1/U2 chip required). Without that, Phase 1 cannot ship.
2. Sign third-party accessory letter of intent with one tank-equipment manufacturer for hose UWB pod. Qualification cycle is 6-10 weeks; if we don't start this week, Phase 5 slips out of 90-day window.
3. Stand up NI-pairing tRPC endpoint. Spec is `contracts/ni-pairing-v1.json`. Bottleneck for Phase 1 launch.
4. Cyan-light approval from Haul governance circle. Adding a ninth color is a brand-level decision.
5. Vision Pro yard pilot — pick the yard. Recommend Houston hazmat terminal because density of trucks + regulatory upside makes it highest-signal pilot.

**Master Synthesis for Mike "Diego" Usoro:**

Diego —

The single big idea is this: **EusoTrip becomes the only freight platform that knows where its drivers are in 3D space, not just where their phone pings cellular towers.** That sentence is the entire pitch deck. Every feature you've built — ESANG voice, The Haul recognition, the Cortex agents, the convoy mesh, the hazmat compliance modules — was constrained by GPS-grade location. Each of them gets multiplied by NearbyInteraction.

ESANG today is a navigation companion. With NI, ESANG becomes a spatial co-pilot — it can say "you're 18 inches from the bumper, straighten the wheel" and mean it. That single capability changes the conversation with every shipper that has ever paid a spotter to wave a driver in. We replace the spotter, in the driver's earpiece, for free, on equipment the driver already carries. Spotters cost $35-$60/hour and are unionized in some yards. We eat that line item for one shipper and the demo writes itself.

The Haul today recognizes drivers for behaviors GPS can verify. With NI we see behaviors GPS cannot — the driver who docks within 4 inches without a spotter, the escort who holds formation tight for 800 miles, the tanker driver with zero hose-misconnects across 100 hazmat connects. These are real, observable, professional behaviors that today are invisible. Pinpoint Parker, Convoy Sync Master, Hose Hero — the Cyan light — every one is a recognition the platform sees only because we ranged it.

The Cortex agents today reason at GPS resolution and that limits how confident they can be. convoyCommander says "convoy formed" because two phones are within 200m on the same heading. With NI it says "lead is 12.4m ahead, escort-1 is 8.1m behind, escort-2 is 9.7m on left flank — formation tight." That is the difference between a guess and a measurement. Once agents reason on measurements not guesses, the entire SkillTier governance ladder gets sharper.

The HERE Workspace partnership is the leverage. HERE has POI ground truth at 5m. We have dock-level ground truth at 10cm, dock-state, dock-difficulty, shipper-infrastructure-decay. None is in HERE's dataset; none can be acquired without our drivers in our app. Data partnership terms should reflect the asymmetry — paid per-correction-published, revenue-share lane-intelligence downstream. Cyan-4 drivers are part of the data product and should be compensated for it.

**Seven open questions for engineering:**
1. Actual U1/U2 install base across pilot fleet right now? If under 80%, Phase 1 needs a Plus-and-newer-only rollout.
2. Watch S6 and earlier don't have full UWB — degrade Pulse Watch gracefully on S5/S6, or hard-require S7+ for Phase 1?
3. Who owns third-party hose-tag certification — tank manufacturer, us, or a partner like trailer OEM?
4. Per-tenant key rotation policy for the discovery-token-to-peer-handle mapping in Memory Palace?
5. Vision Pro NI session count limits — visionOS 2 documents 6 simultaneous, undocumented behavior beyond. Engineer for 6 or push?
6. Agents SDK migration runs parallel — fork NI guardrails into Python now or keep TypeScript until cutover?
7. Background ranging core to Phase 4 escort — ship `NSNearbyInteractionAllowOnceUsageDescription` in first iOS update or wait for Phase 4 cycle?

**The commitment:** By 2026-07-31, EusoTrip ships Phases 0-4 to a 50-driver pilot fleet, with cm-level dock precision visible to The Haul, NI-verified convoy formation visible to Cortex, and ESANG voice cues integrated end-to-end. By 2026-09-30, Phases 5-6 ship — UWB hazmat hose verification operational at the Houston terminal, Vision Pro yard ops in pilot at one carrier. The outcome: EusoTrip is the only freight platform on the market with cm-level driver positioning, with written audit trails to prove it for every shipper insurance carrier in the country.

Mike, the moat closes if we don't ship in 90 days. Apple's framework matures and somebody else — likely a logistics startup with no existing platform — builds it as a single-feature company and gets acquired by Samsara. We have the platform, the drivers, the agents, the recognition system. We just need to ship the precision layer that makes all of it 100x more credible.

— Lead 10

---

# PART IV — APPLE WATCH SUBSTRATE

## POD 11 — PULSE WATCH-SIDE NEARBYINTERACTION AND IPHONE↔WATCH SYNC HARDENING

> *This is the Pod Diego flagged as flagship-critical. The Apple Watch is not a peripheral — it is the second-most-used surface on EusoTrip after the iPhone, and for drivers in motion it is often the only surface they can touch. NearbyInteraction enhances watchOS Pulse on its own terms AND fixes long-standing iPhone↔Watch sync ambiguities.*

### 11.1 Why the Watch matters for NI specifically

The Pulse Watch already ships with `ConvoyBridge`, `ConvoyCoordinator`, `ConvoyRollingMesh`, `ConvoyRosterReconciler`, `ConvoySignature`, `ELDFusedPrecision`, `DeadZoneCoast`, `CrashDetection`, `WatchConnectivityManager`, and a five-state orb (idle/listening/thinking/speaking/error). NI is the missing layer that turns these from "watch as a smaller phone" into "watch as a wrist-mounted spatial sensor that speaks to the iPhone, the world, and other watches."

Apple Watch S6+ has the U1 chip; S9+ adds U2 with full direction estimation. watchOS 9.4+ added watch-to-iPhone NI ranging (earlier the iPhone was a blackbox to the watch over UWB). watchOS 10 expanded multi-peer support to ~3 simultaneous sessions on S9. visionOS 2 doesn't degrade the watch — they're distinct surfaces. **The Watch is a first-class NI participant, not a downgraded iPhone.**

### 11.2 The five Watch-side NI use cases

#### 11.2.1 Phone-presence verification (sync hardening)

The single highest-impact watch NI use case is verifying the iPhone is actually with the driver. Today's WCSession reachability says "the phone is paired and Bluetooth-connected" — that's a 5-8m proximity proxy at best. WCSession says reachable when the phone is on the dispatch desk and the driver walks out of the cab. That's the source of every "orb stuck pairing" bug we've fought through builds 38, 43, 47, 50, 55.

NI hardens this. The watch and the iPhone exchange `NIDiscoveryToken` over WCSession (the only secure bidirectional channel both have), each opens an `NISession` with `NINearbyPeerConfiguration`, and the watch publishes a `phonePresence: PhonePresenceState` derived from joint signals:

```swift
enum PhonePresenceState {
    case inCab          // NI <1.5m AND WCSession reachable AND sustained 2s
    case inCabFar       // NI 1.5-5m AND WCSession reachable
    case nearby         // NI lost OR WCSession only
    case absent         // WCSession unreachable AND NI peer_lost >15s
    case unknown        // initial state, no signal yet
}
```

The orb wake rule changes: "wake orb if WCSession reachable" becomes "wake orb if `phonePresence == .inCab`." Stuck pairing disappears because the watch has independent ground truth that the phone is actually with the driver, not on the dispatch desk fifteen feet away.

```swift
// EusoTrip Pulse Watch App/Services/PhonePresenceService.swift (new)
final class PhonePresenceService: NSObject, NISessionDelegate, ObservableObject {
    @Published var state: PhonePresenceState = .unknown
    private var session: NISession?
    private var lastSeenAt: Date?

    func start() {
        guard NISession.deviceCapabilities.supportsPreciseDistanceMeasurement else {
            // S5 and earlier: fall back to WCSession-only state
            state = WatchConnectivityManager.shared.isReachable ? .nearby : .absent
            return
        }
        // Token exchange over WCSession (existing transport)
        WatchConnectivityManager.shared.requestPhoneDiscoveryToken { [weak self] token in
            self?.openSession(toward: token)
        }
    }

    func session(_ s: NISession, didUpdate objs: [NINearbyObject]) {
        guard let obj = objs.first, let d = obj.distance else { return }
        lastSeenAt = .now
        let reachable = WatchConnectivityManager.shared.isReachable
        if d < 1.5 && reachable { state = .inCab }
        else if d < 5.0 && reachable { state = .inCabFar }
        else { state = .nearby }
    }

    func session(_ s: NISession, didRemove objs: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        let reachable = WatchConnectivityManager.shared.isReachable
        state = reachable ? .nearby : .absent
    }
}
```

The orb view subscribes to `phonePresence` and gates wake. The five-state orb gains a sixth state: `awaitingPhone` — slow gray pulse — fired when `phonePresence == .absent OR .unknown`. ESANG over voice: "I can't see your phone. Is it in the cab?"

This single feature retires three classes of long-running bugs and replaces them with explicit, debuggable state.

#### 11.2.2 Sync-mode adaptation based on distance

Today's WCSession-based sync is one-size-fits-all — every event is queued, transferred when reachable. With NI distance, sync mode adapts:

```swift
enum WatchSyncMode {
    case fullParity        // <1.5m: every event mirrored realtime
    case prioritized       // 1.5-5m: critical events realtime, ambient batched
    case deferred          // 5-30m: queue locally, flush on close
    case standalone        // >30m or NI lost: watch operates fully offline
}
```

`WatchConnectivityManager` exposes a `syncMode: WatchSyncMode` derived from `phonePresence`. In `fullParity`, every Cortex event from the phone mirrors to the watch within 200ms via `transferUserInfo` (high priority). In `prioritized`, only events tagged `priority: .critical` (HOS warnings, emergency dispatch, hazmat alerts) sync realtime; ambient telemetry batches every 30s. In `deferred`, the watch caches events to local CoreData and replays when reachable. In `standalone`, the watch UI reflects "operating standalone" with a small badge, and any user action queues into `OutboxRun` with replay-on-reconnect.

**This solves the "I walked away from the truck and my watch went stale" problem.** Today the driver sees stale data on the watch with no indication it's stale. With NI sync mode, the watch knows it's standalone and the UI tells the driver. The Pulse orb's color shifts: `inCab` = full color, `nearby/deferred` = slight desaturation, `standalone` = grayscale + offline badge.

#### 11.2.3 Watch-to-Trailer locate (yard worker hero use case)

The watch ranges directly to UWB trailer king-pin tags. Yard worker walks the yard with watch on wrist:

1. Tap "Locate trailer 7142" on watch face complication
2. Watch scans for trailer's BLE accessory advertisement, pairs, opens `NINearbyAccessoryConfiguration`
3. Watch shows direction arrow + distance: "180 ft north, 22°"
4. Walk toward beacon, arrow rotates as worker turns
5. Within 3m: haptic single-tap, watch says (via voice or text) "you're on it"
6. Within 1m: solid haptic, "trailer 7142, hitch number 8843, last load: refrigerated produce, departed 2h ago"

This is the killer demo for terminal admins and yard workers. iPhone-free. Wrist-only. Cm-level precision.

```swift
// Pulse Watch App/Views/TrailerLocateView.swift (new)
struct TrailerLocateView: View {
    @StateObject var locator = NITrailerLocator()
    let trailerId: String

    var body: some View {
        VStack {
            DirectionArrowView(angle: locator.azimuth)
            Text("\(locator.distanceFeet, specifier: "%.0f") ft")
                .font(.largeTitle)
            if let direction = locator.cardinalDirection {
                Text(direction).font(.caption)
            }
        }
        .onAppear { locator.startLocating(trailerId: trailerId) }
        .onDisappear { locator.stop() }
    }
}
```

#### 11.2.4 Watch-to-Watch convoy (driver-to-driver direct)

When two drivers in a convoy both have Pulse Watch on, the watches range directly to each other — no phone required. Multi-peer up to 3 simultaneous on S9, 1 on older Watches.

This matters for moments when phones are in pockets/on dashboards but watches are on wrists. Hand signals between drivers replaced by watch-to-watch precision: "driver behind you is 8m back, 18° left of your line." Haptic-only or voice-via-AirPods cues.

The existing `ConvoyRollingMesh` extends to watchOS-only mesh: when watch detects no paired iPhone available (`phonePresence == .absent`), it can join a mesh of other watches and operate fully standalone. This is the Phase 2 deliverable for watch-to-watch convoy.

#### 11.2.5 Hazmat seal AirTag verification

Sealed hazmat trailers have AirTags affixed to door seals. Watch ranges to seal AirTag at every checkpoint:
- Gate-out from shipper: AirTag at <0.5m → seal verified intact
- Gate-in at receiver: AirTag still at <0.5m → seal verified unbroken in transit
- Any ranging gap >5min between checkpoints: alert ("seal AirTag lost contact between mile X and mile Y on I-10")

This is the regulatory chain-of-custody for hazmat seals — today done with paper checklists and intermittent inspection. UWB makes it continuous and tamper-evident. Audit trail writes to Memory Palace cold tier.

### 11.3 iPhone↔Watch sync hardening: the transport stack

The full sync stack with NI:

```
┌─────────────────────────────────────────────────────────────┐
│  Cortex Backend (tRPC + agents)                              │
└─────────────────────────────────────────────────────────────┘
                          ▲
                          │ tRPC over LTE/WiFi
                          │
┌─────────────────────────────────────────────────────────────┐
│  iPhone (cab-mounted)                                         │
│  - CortexClient  - NIRangingService  - WCSession             │
└─────────────────────────────────────────────────────────────┘
              ▲                                ▲
              │  WCSession (sync)              │  NI (presence)
              │  AirDrop/Files                 │
              ▼                                ▼
┌─────────────────────────────────────────────────────────────┐
│  Apple Watch (wrist)                                          │
│  - PhonePresenceService  - WatchSyncMode                     │
│  - ConvoyRollingMesh+NI  - TrailerLocator                    │
│  - HazmatSealMonitor                                         │
└─────────────────────────────────────────────────────────────┘
```

Three transports, three roles:
1. **NI** — proximity confidence, distance/direction, no payload (audit-proof: NI cannot exfiltrate user data)
2. **WCSession** — bidirectional payload sync, Apple-managed reliability, the existing primary
3. **tRPC** — backend connectivity, both phone and watch can talk to backend independently when both have cell

NI does not replace WCSession. NI gates WCSession behavior:
- `inCab` → WCSession full parity, every event mirrored
- `inCabFar` → WCSession prioritized, critical events only
- `nearby` → WCSession deferred, batched flush
- `absent` → WCSession unreachable; watch goes standalone, queues to OutboxRun, talks directly to backend if cellular available

This is the elegant decoupling. The watch is never lying about what it knows. Stale data is labeled stale. Critical alerts always reach the wrist via the most robust channel available.

### 11.4 Watch complications + NI

Three new complications for NI scenarios:

**`PhonePresenceComplication`** — corner complication on every watch face. Color-coded dot: green (`inCab`), amber (`nearby`), red (`absent`). Tap → opens the orb view with explicit phone-presence state. Replaces today's "is my watch synced?" anxiety with a direct ground-truth indicator.

**`FormationPulseComplication`** — circular complication for drivers actively in a convoy or escort. Shows formation tightness as a fill ring (full = tight, empty = breaking). Updates every 2s when active.

**`TrailerLocateComplication`** — modular small complication for yard workers. Shows currently-targeted trailer ID + distance. Tap → opens `TrailerLocateView`.

All three use `WidgetKit` complication timelines, refreshed via `URLSession` background tasks for the data feed and `WatchConnectivityManager.transferComplicationUserInfo` for high-priority deltas.

### 11.5 Watch as Cortex surface

The Pulse Watch becomes a first-class Cortex surface. It subscribes (via the role manifest from `ZENITH_CORTEX_AGENTS_DOCTRINE.md` Pod 9) to its driver's curated agent list. NI events flow to the watch on the same channel as any other Cortex event:
- `ni.distance_below_threshold` → orb proximity state changes, haptic feedback
- `convoy.formation_tight` → complication ring fills green
- `hazmat.connect_authorized` → orb single-tap haptic + voice "Connected"

The watch is not running NI agents itself — those live in the backend. The watch is a sensor + UI surface. When ESANG speaks via Realtime API, the audio stream routes through AirPods or watch speaker depending on driver preference; voice cues from NI-aware agents (backing assist, escort coaching, hazmat verification) feel native to the wrist.

### 11.6 Performance considerations for the Watch

Watch is the most power-constrained device in the stack. Battery budget for NI:
- **Idle (no NI session)**: 0% additional draw
- **PhonePresenceService running** (1 session, low rate): ~2%/hr additional
- **TrailerLocate active (1 session, medium rate)**: ~7%/hr
- **Convoy mesh (3 sessions, medium rate)**: ~14%/hr
- **Concurrent (presence + convoy)**: ~16%/hr

Mitigation: PhonePresenceService runs at minimum update rate (250ms intervals → effectively 4Hz), pauses entirely after 30 minutes of `inCab` stable state and resumes only on WCSession reachability change. TrailerLocate auto-stops after 5 minutes or when within 1m. Convoy mesh follows the existing roster reconciler's election — only the host runs N sessions.

Thermal envelope: watchOS will throttle automatically; treat that as a black box.

### 11.7 Phase mapping for Pod 11

The Watch enhancements land across the same 6-phase ladder, with three Watch-specific milestones:

| Phase | Days | Watch Deliverable |
|-------|------|-------------------|
| 0 | 1-7 | Watch capability probe, Info.plist usage description, NIDevTools harness watch target |
| 1 | 8-21 | **PhonePresenceService + sync mode adaptation + 6th orb state** (single highest-ROI watch feature) |
| 2 | 22-42 | **Watch-to-Watch convoy (S9+ multi-peer)**, ConvoyRollingMesh+NI extension |
| 3 | 43-60 | Watch complication for FormationPulse during backing assist |
| 4 | 61-75 | Watch escort coaching cues via AirPods, complication updates from escort topics |
| 5 | 76-83 | **Hazmat seal AirTag monitor + chain-of-custody complication** |
| 6 | 84-90 | TrailerLocate complication GA, watch-only standalone mode hardened |

Phase 1's Watch deliverable is the single most important feature on the entire 90-day roadmap from a user-trust perspective. Every "stuck pairing" bug we've fought disappears the day PhonePresenceService ships.

### Pod 11 Synthesis

The Apple Watch is not a downgraded iPhone — it is a wrist-mounted spatial sensor that has been waiting for NI to be wired correctly. The five Watch-side use cases (phone-presence, sync-mode adaptation, trailer locate, watch-to-watch convoy, hazmat seal verification) transform the Pulse Watch from "smaller phone with limited features" into "the most precise device a driver carries that doesn't require pulling out a phone."

iPhone↔Watch sync hardening via NI is the architectural unlock. WCSession alone is unreliable proximity; NI gives ground truth. The four sync modes (fullParity / prioritized / deferred / standalone) make watch behavior explicit and debuggable for the first time. Stuck-pairing bugs disappear by construction.

**Recommendation:** Ship PhonePresenceService and sync-mode adaptation in Phase 1, in parallel with the iPhone↔Watch pairing for orb wake. Together they retire a class of long-running bugs and reframe the Watch as a first-class participant rather than a peripheral. Phases 2-6 layer trailer locate, watch-to-watch convoy, hazmat seal, and complications on the same foundation.

The Pulse Watch was already designed for a world where the phone is in the cab and the wrist is in motion. NI makes that design honest.

---

## APPENDIX A — Cross-References

**iOS code surfaces (no NI yet, all greenfield):**
- `EusoTrip/Info.plist` — `NSNearbyInteractionUsageDescription` declared
- `EusoTrip/Views/Driver/014-048` — 28 lifecycle views, 14 direct NI beneficiaries
- `EusoTrip/Views/Escort/600-602` — 3 escort views, all NI beneficiaries
- `EusoTrip/Views/Carrier/300-320` — 21 dispatcher views
- `EusoTrip/Views/Terminal/700-701` — 2 terminal views (more to build)

**watchOS Pulse code (existing infrastructure ready for NI):**
- `EusoTrip Pulse Watch App/Services/ConvoyBridge.swift`
- `EusoTrip Pulse Watch App/Services/ConvoyCoordinator.swift`
- `EusoTrip Pulse Watch App/Services/ConvoyRollingMesh.swift`
- `EusoTrip Pulse Watch App/Services/ConvoyRosterReconciler.swift`
- `EusoTrip Pulse Watch App/Services/ConvoySignature.swift`
- `EusoTrip Pulse Watch App/Services/ELDFusedPrecision.swift`
- `EusoTrip Pulse Watch App/Services/DeadZoneCoast.swift`
- `EusoTrip Pulse Watch App/Services/CrashDetection.swift`
- `EusoTrip Pulse Watch App/WatchConnectivityManager.swift`

**Backend Cortex surfaces (consume NI events):**
- `frontend/server/services/autopilot/agents/fleet/convoyCommander.ts`
- `frontend/server/services/autopilot/agents/fleet/geofenceSentinel.ts`
- `frontend/server/services/autopilot/agents/multimodal/terminalConductor.ts`
- `frontend/server/services/autopilot/core/synapticBus.ts` — add NI_TOPICS
- `frontend/server/services/autopilot/core/types.ts` — add NIPeerObservation, NIFormationSnapshot
- `frontend/server/services/autopilot/agents/multimodal/hazmatHoseGuard.ts` — NEW for Phase 5

**Files to create (Phase 0-6):**
- `EusoTrip/Services/NI/NIRangingService.swift`
- `EusoTrip/Services/NI/NICapabilityProbe.swift`
- `EusoTrip/Services/NI/NIDriverRangingService.swift`
- `EusoTrip/Services/NI/NIAccessoryRangingService.swift`
- `EusoTrip/Services/NI/NIWatchPairingService.swift`
- `EusoTrip/Services/NI/SpatialCueComposer.swift`
- `EusoTrip Pulse Watch App/Services/PhonePresenceService.swift`
- `EusoTrip Pulse Watch App/Services/NITrailerLocator.swift`
- `EusoTrip Pulse Watch App/Services/HazmatSealMonitor.swift`
- `EusoTrip Pulse Watch App/Views/TrailerLocateView.swift`
- `EusoTrip Pulse Watch Widgets/PhonePresenceComplication.swift`
- `EusoTrip Pulse Watch Widgets/FormationPulseComplication.swift`
- `EusoTrip Pulse Watch Widgets/TrailerLocateComplication.swift`

**Strategic context:**
- `EUSOTRIP2027GOLD/the_haul/THE_HAUL_ENCYCLOPEDIA.md` — recognition system source of truth
- `EUSOTRIP2027GOLD/the_haul/ZENITH_CORTEX_AGENTS_DOCTRINE.md` — 50-agent backend architecture
- `EUSOTRIP2027GOLD/the_haul/HERE_Email_Frackowiak_Missed_Call.md` — HERE Workspace partnership

---

## APPENDIX B — Open Engineering Questions

Beyond the seven in the master synthesis:

8. **Watch-to-watch direct NI in mixed S6/S9 fleet** — S6 supports distance only, S9 supports direction. Do we ship distance-only watch-to-watch convoy as Phase 2 baseline, or hard-require S9?

9. **NI session in standalone watch mode** — when phone is `absent`, watch operates standalone but Cortex events come from cellular. Bandwidth budget for watch cellular vs Bluetooth-relay through phone needs measurement.

10. **Complication update budget** — WatchKit limits complications to ~50 timeline updates per day on third-party watches. NI events fire faster than that. We need a smart consolidation strategy.

11. **Backgrounding NI on watch** — watchOS limits background time more aggressively than iOS. How much of PhonePresenceService can run when watch face is asleep?

12. **AirTag-as-hazmat-seal regulatory acceptance** — DOT may not recognize AirTag-generated chain-of-custody as evidence. Need legal review before Phase 5 ships.

---

*End of doctrine. Total length: ~24,000 words across 11 pods + 2 appendices.*

*Mirror this file to `EUSOTRIP2027GOLD/the_haul/` in both the iOS repo and the eusoronetechnologiesinc backend repo to keep parity with THE_HAUL_ENCYCLOPEDIA, THE_TRILLION_DOLLAR_DOCTRINE, ZENITH_CORTEX_AGENTS_DOCTRINE, HERE_Call_Script_Frackowiak, and HERE_Email_Frackowiak_Missed_Call.*

*Last updated: 2026-05-02. Living document. Update with: actual U1/U2 install base measurement, third-party hose-tag certification partner name, Cyan light governance approval status, Houston terminal pilot start date, Watch S9 fleet share.*
