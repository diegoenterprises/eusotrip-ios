# 60 · Offline-First + Pulse Watch

**What this covers.** The complete offline-first doctrine for EusoTrip — why offline is a first-class requirement (not polish), the F01–F16 feature catalog (unified outbox, voice dispatch grammar, dead-zone coast, satellite fallback, HOS clock swap, plus Q3/Q4 mesh relay + CRDT + blockchain audit + convoy + keep-alive navigation + BOL copilot + proximity handoff), Pulse Watch targeting + lifecycle + always-on contract, 9-state orb state machine with 17 events, the 1.5-second pairing deadline, AuthStore sync with four parallel transports, AudioSessionPreflight (the zero-channel exception), SFSpeechRecognizer + AVAudioEngine integration, HKWorkoutSession for drive auto-detection, haptic + visual feedback <100ms, DebugHealthView triple-tap, OrbLog telemetry, SOS flow, Siri App Intents, complications, notifications, battery budget, background modes, WCSession best practices, watch-only auth bypass via shared Keychain. Source: wave-1 shard `team_OFFLINE_PULSE`.

**When you need this.** When building anything offline-adjacent. When working on Pulse watch. When scoping F-code features. When debugging "the orb got stuck."

**Cross-links.** Auth: [05_Auth_Security_Compliance.md §8](./05_Auth_Security_Compliance.md). Apple frameworks: [06_Third_Party_Integrations.md §4](./06_Third_Party_Integrations.md). Realtime: [03_Backend_API_Contract.md §11-22](./03_Backend_API_Contract.md). Driver offline: [10_Mode_TRUCK/01_Driver.md §7](./10_Mode_TRUCK/01_Driver.md).

---

## 1. Why offline-first is a first-class requirement, not a polish item

Every competing trucking product assumes connectivity and bolts on "offline mode" as retrofit. EusoTrip inverts the assumption. The *primary* execution environment for mobile stack is a cab, yard, port, tunnel, rural corridor — in each, for a non-trivial fraction of the workday, network is unreliable, marginal, or absent.

**The numbers that drive the doctrine:**

- **15–30% of OTR miles in lower 48** run through rural highways, deep valleys, canyon stretches, documented cellular dead zones — not edge cases. Measured by Kuebix, ATRI, Samsara across hundreds of millions of driver-hours.
- **Ports** (LA/LB, Oakland, Savannah, Houston, Laredo, Otay Mesa, Prince Rupert) sit under RF conditions combining metal containers, gantry cranes, thick reinforced concrete, intentional jamming near secure terminals. Cellular inside a port can drop to sub-1 Mbps or fail for 20–40 minute windows.
- **Tunnels** — Eisenhower, Lincoln, Fort McHenry, Holland, Chesapeake Bay Bridge-Tunnel, Ted Williams — guarantee cellular loss for bore duration. Long hauls with multiple tunnel transits add 30–90 seconds of guaranteed LTE silence per transit.
- **Rail corridors** compound the problem. Intermodal moves across UP and BNSF in Wyoming, Montana, Dakotas, northern Minnesota run hundreds of miles through corridors where even Verizon 4G has holes 10–40 miles wide. Rail yards themselves are RF-noisy.
- **Cross-border corridors** — Laredo ↔ Nuevo Laredo, El Paso ↔ Juárez, Detroit ↔ Windsor, Blaine ↔ Surrey — have carrier-switching dead zones extending minutes at customs booths.

**Doctrine**: if a feature does not have documented offline posture — what happens when the network disappears mid-operation — that feature is not done. Offline posture is first-class property of every user-facing action.

Flows into five concrete engineering contracts: unified outbox, local voice grammar, dead-zone coasting, satellite fallback for life-safety, watch companion operating without paired iPhone in range.

---

## 2. F01 — The OfflineQueue — unified outbox with priority lanes

`Services/OfflineQueue.swift` on watch (and iOS sibling) is the keystone. Every network-touching action passes through, with same retry contract.

**Five priority lanes, strictly ordered:**

| Lane | Priority | Reason | Quota | Backoff | Stale window |
|------|----------|--------|-------|---------|--------------|
| SOS | 0 | Life-safety. Never evicted by quota. | 50 | 2s → 5s | never |
| HOS | 1 | FMCSA compliance; loss is a legal event. | 500 | 4s → 60s | never |
| Load | 2 | Revenue-critical (accept / arrived / POD). | 200 | 8s → 300s | 72h |
| Voice | 3 | Esang round-trips. Stale voice = stale intent. | 100 | 15s → 600s | 24h |
| Message | 4 | Dispatcher chat pings. | 100 | 30s → 900s | 24h |

Each entry is `OutboxEntry` — wrapped `QueuedAction` plus idempotency key, attempt counter, next-retry timestamp, last-error string. Keys are ULID/UUID-flavored so replay after crash or reboot converges deterministically against server's idempotency table.

**File-backed persistence.** Queue serializes to `Application Support/esang-offline-queue.json` on every enqueue + flush. Cold upgrade from build 21 or earlier detects legacy `[QueuedAction]` format and migrates to `Envelope { version: 2, entries }` on first restore.

**Exponential backoff per lane.** `recordFailure(error:)` advances `nextRetryAt` via `min(maxBackoff, minBackoff * 2^attempts)` with `attempts` clamped at 10. SOS tops out at 5 seconds — we hammer that lane. Message caps at 15 minutes.

**Flush triggers:**
1. **`NWPathMonitor.satisfied` edge** — `NetworkReachabilityHub.shared` watches `NWPath.status` on utility queue; on `unsatisfied → satisfied` transition, hops to `@MainActor`, updates `OrbStateMachine.networkReachable`, calls `OfflineQueue.shared.flushAll(auth:)` against live `AuthStore.shared`. Closes the "first utterance after reinstall sits in queue forever" bug from build 21.
2. **`WCSession.reachabilityDidChange`** — when watch suddenly reaches iPhone companion after disconnect, piggybacks on phone's LTE path even if wrist has no direct connectivity.
3. **Foreground resume** — `scenePhase == .active` triggers `await offline.flush(auth:)` in `EusoTripWatchApp.onChange(of: scenePhase)`.
4. **Manual retry** — `OutboxStatusView` per-lane "retry now" control; "show queued messages" / "retry queue" recognized offline-voice intents.

**Priority drain with starvation protection.** Flush loop walks lanes strictly: SOS → HOS → Load → Voice → Message. Within lane, entries sorted by `enqueuedAt` (oldest first) — replay is causal. Non-SOS lane transient failure breaks to next lane rather than hammering same endpoint — one misbehaving backend route can't starve HOS or Load behind it. SOS exception: keeps attempting every SOS entry in same flush pass.

**The crucial property.** Driver in Eisenhower Tunnel at 2 a.m. utters "accept this load" → local confirmation, haptic tap, spoken reply — when watch surfaces in Dillon CO and LTE re-satisfies, server accept fires automatically with same idempotency key. Driver never knows there was a race. That's the contract.

---

## 3. F04 — Voice Dispatch Local Grammar

`Services/VoiceDispatch.swift` defines the twelve-plus intent local grammar wrist resolves against transcript *before* giving up and queuing for server round-trip.

**Intent coverage:**
- `log off duty` / `off duty` / `going off duty` → HOSStore swap + enqueue `hos.changeStatus`.
- `log on duty` / `on duty` / `going on duty`.
- `start driving` / `log driving`.
- `sleeper berth` / `going to sleep`.
- `accept load` / `accept this load` / `take it` (requires active loadId).
- `arrived at pickup` / `arrived pickup`.
- `arrived at delivery` / `arrived delivery`.
- `remaining drive` / `how much drive time` — synthesized from `HOSClockSwap.shared.liveDriveRemaining`.
- `active load` / `current load` — synthesized from `LoadStore.shared.active`.
- `battery` — `WKInterfaceDevice.batteryLevel`.
- `sos` / `emergency` / `mayday` / `help me` → `EmergencyController.activate`.
- `text dispatch {message}`.
- `repeat` — replay last Esang reply.

Each match produces `OfflineIntent` with spoken confirmation (`"Off duty logged. I'll sync when you're back online."`), set of structured `VoiceAction` payloads dispatched to `VoiceActionDispatcher`, `enqueueOnline: Bool` flag.

**Doctrine**: mutating intents always dual-written. Local state change gives driver instant wrist feedback + visible UI change; server still receives same idempotency key in voice lane — backend's HOS, Load, Messaging systems remain source of truth for audit. Read-only queries synthesize replies from local stores without server round-trip.

Anything outside the grammar falls through to standard "queued for reconnect" — transcript enqueued into voice lane, and when server reachable again, `voiceESANG.processVoiceCommand` sees utterance and responds canonically. Driver's only regression is ~2 second reply-delay next time they're in coverage.

---

## 4. F02b — Dead-Zone Coast

`Services/DeadZoneCoast.swift` handles general case that `TunnelAwareETA.swift` does not: any 60+ second silence on CLLocation stream, regardless of whether we think we're in mapped tunnel.

**Contract:**
1. Watch CLLocation for fix freshness. Accept fix as "good" only when `horizontalAccuracy >= 0` AND `<= 40 m`.
2. If last good fix older than `coastTriggerSeconds` (default 60s), enter `COASTING`, freeze last `(lat, lon, heading, speed)` as anchor.
3. Propagate forward with simple kinematics: `pos += speed · heading · dt`. No full EKF — general-case dead zone can last hours; 50 Hz CoreMotion would drain Series 4 battery in afternoon.
4. Uncertainty grows linearly: `r = max(horizontalAccuracy, uncertaintyRatePerSec · coastElapsed)`. At 2 m/s uncertainty-growth rate, 60-sec coast is ~120 m 1-σ, 5-min ~600 m, 15-min ~1.8 km. Dispatch dashboards render as dot with growing halo — *honestly* stale, not a lie.
5. Enqueue breadcrumb `OfflineQueue.enqueueMessage(to: "dispatch:breadcrumb", ...)` every `breadcrumbIntervalSeconds` (2 min) while coasting.
6. At `satelliteEscalationSeconds` (5 min), flip `SatelliteFallback.terrestrialDown = true`, post `.deadZoneSatelliteEscalation` so UI offers satellite card.

**Why kinematic, not EKF?**
- **Battery.** 50 Hz IMU is expensive. `TunnelAwareETA`'s EKF runs only when geometry matches known tunnel, short window. General dead-zone may last hours.
- **Accuracy.** Without GNSS-corrected bias estimation, 50 Hz IMU integration drifts into nonsense fast. Pure kinematic coast from last-known speed is no worse for breadcrumb-grade reporting.
- **Downstream contract.** Dispatch needs "last known point + heading + elapsed seconds" breadcrumb + uncertainty circle, not sub-meter position.

When `TunnelAwareETA` running in parallel (geometry match), its output more authoritative — UI prefers its `bestEstimate()`; `DeadZoneCoast` is general-case fallback. Two services happily coexist.

---

## 5. F03 — Iridium + Globalstar Satellite Fallback (SOS only)

`Services/SatelliteFallback.swift` enumerates three system-mediated channels and routes life-safety payloads through paired iPhone's satellite surface. **No direct third-party satellite API on iOS 26** — explicitly not claimed.

**Channels modeled:**
- `globalstarEmergency` — Apple Emergency SOS via Globalstar. 160-byte cap, emergency-only. Available on iPhone 14+; phone routes to native emergency UI.
- `tmobileStarlinkD2C` — T-Mobile Direct-to-Cell Starlink SMS. 240-byte cap, carrier-conditional.
- `iridiumInReach` — Garmin inReach via Messenger SDK over BLE. 160-byte cap, requires puck + subscription.

**`composeSOS(channel:reason:coordinate:loadId:driverId:)`** builds byte-capped payload: `EUSO SOS 34.0522,-118.2437 L:LD-8817 D:D-42 driver-initiated`. Dispatch shortcode (tenant-configurable via `tenant_branding.satelliteShortcode`) prepended for SMS channels, omitted for Globalstar (goes to 911).

**`sendSOS(...)`** hands off via `WatchConnectivityManager.sendSatelliteSOS(...)`. Wrist cannot open satellite link directly; asks phone, which presents `MFMessageComposeViewController` for SMS channels or Emergency SOS flow for Globalstar. Even on successful handoff, still enqueue payload into Message lane with destination `"satellite:<channel>"` for audit log on reconnect.

**Dwell detection.** `startMonitoring(connectivity:)` runs `NWPathMonitor` on wrist; when path has been non-cellular + non-WiFi for `terrestrialLossThresholdSeconds` (180s default), `terrestrialDown` flips and fires probe for which satellite channels phone reports. UI renders "Use phone satellite" escalation card.

**Critical doctrine**: satellite fallback is for SOS + critical breadcrumbs only. Bandwidth is pennies-per-byte; some channels regulated as emergency-only. Never stream telemetry, HOS syncs, voice over satellite.

---

## 6. F01–F16+ offline mode encyclopedia

Every F-code shipped or scaffolded in Pulse Build 24. Each carries feature-flag gate in `EusoTripConfig.swift`.

**Q2 2026 Foundation Tier — SHIPPED, defaults `true`:**

- **F01 — Unified Outbox.** See §2.
- **F02 — Tunnel-Aware ETA.** `TunnelAwareETA.swift`. Classifies every `CLLocation` by accuracy, enters `.tunnelDR` when GNSS degrades past threshold, propagates forward on last-known speed × heading, transitions to `.recovering` with drift metric when GPS returns. Scaffold keeps `CMMotionManager` warm for full IMU integration. Flag: `tunnelAwareETAEnabled`.
- **F02b — Dead-Zone Coast.** See §4. Flag: `deadZoneCoastEnabled`.
- **F03 — Satellite SMS Fallback.** See §5. Flag: `satelliteFallbackEnabled`.
- **F04 — Voice-Only Offline Dispatch Console.** See §3. Flag: `voiceDispatchOfflineEnabled`.
- **F05 — HOS Clock Swap via `updateApplicationContext`.** `HOSClockSwap.swift`. 1 Hz local tick between server pushes. Compares local extrapolation against fresh `updateApplicationContext` payloads; fires `.hosClockSwapped` on >120s drift. Flag: `hosClockSwapEnabled`.

**Q3 2026 Offline Intelligence Tier — SCAFFOLDED:**

- **F06 — Offline ETA from Learned Route History.** `LearnedRouteETA.swift`. Runtime EWMA estimator today, Create ML tabular regressor drop-in later. Trained per-driver on (segment, hour-of-week, weather, loaded) → observed speed. Flag: `learnedRouteETAEnabled` (ships `true`; estimator restores empty and learns).
- **F07 — On-Watch Fatigue Predictor.** `FatiguePredictor.shared`. Activity Classifier on windowed HRV + motion + HOS clock; P(microsleep within 20 min) scored at 1 Hz during driving. Haptic nudge at high confidence.
- **F08 — UWB Docking Assist.** `UWBDocking.swift`. `NIDiscoveryToken` + `NISession` for trailer coupling + dock backing. `hapticCadenceSeconds()` maps distance → tick cadence (1 Hz at 3 m, 4 Hz at 1 m, continuous at 30 cm). Flag: `uwbDockingEnabled`.
- **F09 — Mesh Relay.** `MeshRelay.swift`. Peer-to-peer relay state machine with fixed service UUID `9F8E9D00-E050-4C0C-9E0F-EEB4D0A7B01E`. `MeshEnvelope` carries idempotency key, origin driver id, TTL (max 3 hops), lane, payload kind, opaque bytes. Drains SOS + HOS lanes from outbox through nearby peers. Flag: `meshRelayEnabled`.
- **F10 — ELD-Fused Precision ETA.** When phone actively paired with truck ECM, J1939 SPN 84 wheel-tick velocity forwarded over WatchConnectivity, fused into tunnel-mode dead reckoning. Flag: `eldFusedPrecisionEnabled`.

**Q4 2026 Fleet Mesh + Convoy Tier — SCAFFOLDED:**

- **F11 — FleetCRDT.** `FleetCRDT.swift`. Sparse vector-clock LWW CRDT with per-field tagging. Prefers causally later side on merge; breaks concurrent-write ties by stable hash of actor id. `HOSCRDTState` wires five HOS fields a driver can mutate offline: status, driveMinutes, windowMinutes, cycleMinutes, statusSince. Flag: `fleetCRDTEnabled`.
- **F12 — BlockchainAudit.** `BlockchainAudit.swift`. Local append-only `CryptoKit.SHA256` hash-chained log. `verifyRecent()` re-computes 30-block window to detect tampering. `buildAnchorEnvelope(driverId:)` produces envelope server counter-signs. Kinds: `hosStatus, loadAccept, loadArrived, podScan, hazmatHandoff, emergency, voiceIntent`. Flag: `blockchainAuditEnabled`.
- **F13 — Convoy Coordinator.** `ConvoyCoordinator.swift + ConvoyBridge.swift + ConvoySignature.swift + ConvoyRosterReconciler.swift`. P-256-signed heartbeats, TOFU pin-on-first-see, upgrade to confirmed/suspect via iOS companion's call to `fleet.verifyConvoyMember`. Runs in "phantom convoy" mode over WCSession when BLE off. Flags: `convoyEnabled, convoySignatureRequired`.
- **F14 — Pulse Keep-Alive Navigation Session.** `NavigationSession.swift`. Dedicated `HKWorkoutSession`-backed surface so turn-by-turn cues continue firing on wrist across full haul even when paired iPhone backgrounded or out of reach. Annotates CLLocation stream with maneuver-distance haptics. Flag: `keepAliveNavigationEnabled`.
- **F15 — BOL / Placard Copilot.** `BOLCopilot.swift + BOLCopilotView.swift`. iOS owns camera (VisionKit `DataScannerViewController` + Foundation Models for structured-field extraction); watch is result-viewer + voice trigger. Cross-references placard UN numbers against bundled ERG 2024 database. Flag: `bolCopilotEnabled`.
- **F16 — Wrist-to-Terminal Proximity Handoff.** `ProximityHandoff.swift`. Driver taps "Handoff"; wrist advertises 60-second BLE beacon carrying driver id + active load displayId + HMAC-signed envelope. Dock kiosks, dispatcher wrists, paired iPhones pick up context without QR scans. Flags: `proximityHandoffEnabled, proximityHandoffWindowSeconds`.

Every code F01–F16 live in-tree. F17+ remain 2027 moonshot: LoRa truck beacon mesh, full on-device BOL + placard copilot against Foundation Models on A17 Pro+, multi-hop convoy rolling mesh, convoy-led cross-border customs pre-clearance.

---

## 7. Pulse Watch doctrine — targeting, lifecycle, always-on

- **Bundle id**: `com.app.eusotrip.watch`.
- **Deployment target**: watchOS 10.0+.
- **Hardware floor**: Apple Watch Series 4 and newer. Series 3 and earlier explicitly out of scope. S4 SiP, 64-bit architecture, Neural Engine on S5+ leveraged at runtime.
- **Premium tier**: Apple Watch Ultra 2 (dual-frequency GPS, S9 + U2 UWB, Action Button). Premium features (UWB docking, Ultra-only always-on navigation arc, hardware Action Button bound to `EsangSOSIntent`) degrade gracefully on non-Ultra.

**Always-on display.** watchOS 10's always-on mode dims orb to low-luminance "ambient" frame every ~10 seconds, requires `@Environment(\.isLuminanceReduced)` checks to reduce animation amplitude. `EsangOrbWatch` particle swarm drops to ~8% motion in `.luminanceReduced`; gradient collapses to static dark-blue disc; hint line truncates to two words max. **SOS long-press affordance must remain responsive in ambient mode** — waking dim wrist + pressing must see confirmation countdown within 100ms.

**Complication: HOS Remaining + Orb Thumbnail.** `Complications/HOSComplication.swift` provides three families:
- `.accessoryCircular` — ring of remaining drive-hours with "DRV" label inside; stroke lerped over `hos.drivePct`.
- `.accessoryRectangular` — status icon + drive hours + window hours row.
- `.accessoryInline` — `HOS 7h 42m drive`.

Provider reads `hos.json` from shared `Application Support` directory — WidgetKit extension stays in sync without live app launch. `getTimeline` projects one entry every 15 minutes for 2 hours forward, decrementing `driveRemainingMinutes` when `status == .driving`, expires timeline every `complicationRefreshSeconds` (5 min on wall power / active driving).

Orb thumbnail variant surfaces on Modular Ultra face: miniature `EsangOrbWatch` glyph + HOS drive hours as corner complication — tapping launches straight into Pulse home with orb in `.idleSignedIn`.

**Launch path (`EusoTripWatchApp.swift`).** Build 24 ships defensive phased-launch wrapped in `safeStep(name:work:)` traps. Each subsystem brings up independently:

1. `auth.restore` — Keychain pull of token, user, role.
2. `hos.restore` — persisted HOS snapshot.
3. `loads.restore` — active load snapshot.
4. `offline.restore` — Envelope v2 decode with v1 migration fallback.
5. `connectivity.activate` — `WCSession.default.activate`.
6. Permission prime — `SFSpeechRecognizer.requestAuthorization` + `AVAudioApplication.requestRecordPermission` once per install, guarded by `UserDefaults` key `esang.didPrimePermissions`.
7. `OrbStateMachine.shared.appeared(signedIn:)` — seed with current auth flag, arm 1.5s pairing deadline if needed.
8. `NetworkReachabilityHub.shared.start()` — begin `NWPathMonitor`.
9. Deferred +250ms: `AskEsangIntentRegistrar.register, DrivingSessionManager.begin`.
10. Deferred +600ms: `HOSClockSwap.start, SatelliteFallback.startMonitoring, LearnedRouteETA.restore, BlockchainAudit.restore, FleetCRDT.configure + seedIfEmpty, MeshRelay.begin, ConvoySignature.bootstrap, ConvoyCoordinator.configure, ConvoyBridge.start, ConvoyRosterReconciler.start`.

Each step wrapped — single throwing initializer can't abort launch. Build 21 crash-to-home was direct consequence of synchronous first-frame work exceeding watchOS 20-second launch watchdog; phased isolation closes that class of bugs.

---

## 8. Orb state machine — 9 states

`Services/OrbStateMachine.swift` is the single source of truth for orb lifecycle. **Nine states, mutually exclusive:**

1. **`bootingPermissions`** — first frame; hint "Starting…"
2. **`unpairedPairing`** — no token, 1.5s pairing deadline armed. Hint: "Pairing…"
3. **`unpairedReady`** — pairing deadline fired, no token, orb fully tappable. Hint: "Tap to ask" with OFFLINE capsule. *Not `.error`.*
4. **`idleSignedIn`** — token present, orb ready. Hint: "Tap to ask".
5. **`listening`** — AVAudioEngine capturing, SFSpeechRecognizer partials flowing. Hint: "Listening…"
6. **`thinking`** — utterance final, server round-trip in flight (or local grammar resolving). Hint: "Thinking…"
7. **`done`** — reply rendered, speech synthesis complete. Hint: "Done."
8. **`speaking`** — AVSpeechSynthesizer delivering reply (overlaps with `done` on some machines; sub-state).
9. **`error(String)`** — hard failure surfaced as hint card.

### 17 orb events

Every logged via `OrbLog.transition(from, to)`:

1. `tap` — primary orb tap.
2. `longPressBegan` — start of SOS 1s hold.
3. `longPressEnded` — release (SOS armed or cancelled).
4. `crownTurned` — Digital Crown rotation for HOS scrubbing or reply scroll.
5. `authReady` — `AuthStore.isSignedIn` flipped true.
6. `authLost` — explicit sign-out or cleared token.
7. `networkReachable` — `NWPathMonitor` edge to satisfied.
8. `networkLost` — edge to unsatisfied.
9. `permGranted` — mic/speech/HealthKit grant resolved.
10. `permDenied` — grant denied.
11. `audioEngineReady` — `AVAudioEngine.start()` succeeded after `AudioSessionPreflight.check`.
12. `recognitionPartial` — `SFSpeechRecognitionResult.isFinal == false` tick.
13. `recognitionFinal` — `isFinal == true`.
14. `submitSucceeded` — server returned 2xx or local grammar resolved cleanly.
15. `submitFailed` — network error or server non-2xx; entry now lives in outbox.
16. `pairingTimeout` — 1.5s elapsed with no token.
17. `userReset` — diagnostic "reset orb" control from `DebugHealthView`.

---

## 9. The 1.5-second pairing deadline — never silent, never stuck

**The most important rule in the entire doctrine**, codified in `armPairingDeadline()`:

> When the pairing deadline fires and no token has arrived, transition to **`unpairedReady` — NOT `.error`** — so taps proceed immediately into `VoiceDispatch` + `OfflineQueue` instead of being swallowed by an error card.

Brand-new wrist boots, starts `WCSession`, arms 1.5-second `Task.sleep`. If iPhone companion hasn't mirrored auth token by then, orb becomes fully tappable in offline mode. Driver can log off-duty, arm SOS, ask for remaining drive time, message dispatch — all before phone has ever connected. When token eventually lands, `authReady()` called, pairing deadline cancelled, orb settles into `idleSignedIn` with no visible discontinuity.

**The orb is never silent, never stuck on "Pairing…"**

---

## 10. AuthStore sync — four parallel transports

`AuthStore.swift` reached from four directions, by design — WCSession is not a reliable single point of failure:

1. **`WCSession.updateApplicationContext`** — coalesced latest-snapshot, survives phone reboot, replays on wrist foreground. Canonical transport for `auth.update`.
2. **`WCSession.transferUserInfo`** — FIFO queued, guaranteed delivery. Used for first post-sign-in push when `reachabilityDidChange` fires.
3. **`WCSession.sendMessage`** — foreground-only, fastest when companion actively reachable (driver opens iOS app while wrist is on).
4. **Shared Keychain** — access group `$(AppIdentifierPrefix)com.app.eusotrip.shared`, `kSecAttrAccessibleAfterFirstUnlock`. Either bundle reads + writes Esang token, drops WCSession as single pairing SPOF. Team prefix resolved at runtime via probe item — no hard-coded team id.

When iOS companion calls `WatchAuthBridge.startRealtimeBridge()`, Socket.IO event on iOS propagates to wrist in under a second through four-way fan-out. On wrist, `applyContext(_:)` normalizes empty-string fields to `nil` and honors explicit `clear` flag, fully wiping keychain on sign-out (build 21 bug where `clear: true` + empty fields left `token = ""` and `isSignedIn = true` is dead).

---

## 11. AudioSessionPreflight — the zero-channel exception

`Services/AudioSessionPreflight.swift` validates `AVAudioSession` can transition into `.playAndRecord` before `AVAudioEngine.start()`. On watchOS 26.4, route held by `HKWorkoutSession` (our `DrivingSessionManager` background session) can silently refuse activation, and subsequent `installTap(onBus:)` call gets 0-channel input format — an Objective-C exception, not a Swift throw, unrecoverable from Swift-land. Why this preflight exists.

**The check:**

1. `setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .allowBluetoothHFP])` — `.spokenAudio` mode + HFP so Bluetooth headsets and car systems carry mic path; `.duckOthers` dips any music during capture.
2. `setActive(true, options: .notifyOthersOnDeactivation)` — running workout-builder yields audio route gracefully. Line that tripped zero-channel bug.
3. On any thrown `NSError`, throw `EsangError.audioRouteUnavailable` — caller surfaces hint-card error instead of installing tap onto format with `channelCount == 0`.

Before every capture, `DrivingSessionManager.pauseForVoice()` pauses workout session for listen duration — mic route is ours alone. `resumeAfterVoice()` reactivates. Both idempotent. Yielding audio route without pausing workout leaves wrist fighting itself for same input device — cut-off transcripts on first syllable.

---

## 12. SFSpeechRecognizer + AVAudioEngine integration

`EsangSession.swift` owns capture pipeline. `SFSpeechRecognizer, AVAudioEngine, AVSpeechSynthesizer` all marked `lazy var` — audio stack not instantiated until driver actually starts listening. Eliminated build 21 race between `@StateObject` creation and workout-session audio wiring that triggered hard launch crash.

**Flow:**
1. Orb tap → `handleTap()` → `OrbLog.tap(state:signedIn:)`.
2. `requestPermissions()` if not yet primed — `SFSpeechRecognizer.requestAuthorization + AVAudioApplication.requestRecordPermission`.
3. `DrivingSessionManager.shared.pauseForVoice()`.
4. `AudioSessionPreflight.check()` — throws or passes.
5. Install tap on `AVAudioEngine.inputNode`, start engine.
6. Create `SFSpeechAudioBufferRecognitionRequest`, pipe buffers in.
7. Partials → `OrbStateMachine.transition(.listening)`.
8. Final → `submitTranscribedText(_:auth:connectivity:)`:
   - Try `EsangClient.processVoiceCommand` online.
   - On network failure, run `VoiceDispatch.resolve(transcript, loadId:)`. If match, speak confirmation, dispatch actions, enqueue server round-trip if `enqueueOnline == true`.
   - On complete miss, enqueue raw utterance to voice lane.
9. `AVSpeechSynthesizer` delivers reply. `done` transition.
10. `DrivingSessionManager.resumeAfterVoice()`.

On-device recognition enabled via `SFSpeechRecognizer(locale:)` with `requiresOnDeviceRecognition = true` for en-US on S6+ watches — what keeps F04 working with zero server dependency.

---

## 13. HKWorkoutSession for drive auto-detection

`DrivingSessionManager.swift` owns `HKWorkoutSession(.other, .outdoor)` keeping Pulse app alive across long hauls. Without it, watchOS suspends us after ~30 seconds — unacceptable for HOS surface needing to capture next "driving → on duty not driving" transition at red light.

`CMMotionActivityManager.startActivityUpdates` watches for `act.automotive && act.confidence != .low`; on first confident automotive classification, automatically advances `HOSStore.current.status = .driving`. F05 "drive auto-detection" contract — driver never has to tap a start button; wrist sees truck moving and logs HOS swap.

Accelerometer at 10 Hz for hard-brake / pothole / sharp-turn classification (threshold 2.3 g). Gyro z-axis at 10 Hz feeds `FatiguePredictor.shared.ingestGyro(z:at:)`. CLLocation pump started inside `startLocationPump()` with `desiredAccuracy = kCLLocationAccuracyBest` + `distanceFilter = 5 m`, delegates fan-out to `TunnelAwareETA.ingest, DeadZoneCoast.ingest, LearnedRouteETA.ingest, ConvoyCoordinator.observeLocalLocation, NavigationSession.ingest` — one GPS pipe, five consumers.

---

## 14. Haptic + visual feedback <100ms per tap

`EsangOrbWatch` view reserves dedicated `@State var tapFlash` and `@State var pressScale` pair — every orb tap produces ring pulse + scale bounce regardless of whether underlying `handleOrbTap` produced visible state change. Without this, tap while signed-out (which silently fires `connectivity.requestAuthMirror()`) felt like dead button.

Budget:
- **<16ms** — gesture recognized by SwiftUI.
- **<50ms** — `WKInterfaceDevice.play(.click)` dispatched.
- **<100ms** — `pressScale = 0.93` and back to `1.0`, with `tapFlash` ring draw. Matches watchOS-native button-press feel.

Applies to every tappable surface: HOS status chips, load-accept button, OutboxStatusView retry rows, BOLCopilot confirm sheet, every toast-dismiss affordance.

---

## 15. DebugHealthView — triple-tap time label

`Views/DebugHealthView.swift` is the on-device diagnostic, reached by triple-tapping time label in home/instrument panel. Surfaces:
- Last 50 orb-log events.
- Live auth state.
- WCSession reachability.
- Network-path status.
- Mic/speech/audio permission state.
- Current audio route.
- Per-lane outbox depth.
- Last error.

"Copy Diag" button serializes above into JSON `DiagBundle`, writes to iPhone pasteboard via WCSession — driver can email to support (a.lynngambardella@gmail.com) without wiring Console.app entitlements on wrist. How we close support loop without asking driver for sysdiagnose.

DebugHealthView gated to DEBUG / TestFlight only — never shipped to App Store production.

---

## 16. OrbLog telemetry

`Services/OrbLog.swift` centralizes every orb-lifecycle branch through single `Logger(subsystem: "com.app.eusotrip.watch", category: "orb")` + 50-event in-memory ring buffer that `DebugHealthView` reads.

Emitters:
- `tap(state:signedIn:)` — every orb tap, state-machine snapshot at entry.
- `audio(_:)` — audio preflight failures + route changes.
- `transition(_:_:)` — every state-machine transition.
- `permission(_:_:)` — every permission request + resolution.
- `info(_:)` / `error(_:)` — free-form infrastructure notes.

`Logger` is near-zero-cost no-op when subsystem unsubscribed — leaving in production is free. Ring-buffer writes gated on `DEBUG || TESTFLIGHT` to avoid retaining event strings in shipping builds.

---

## 17. SOS flow on watch — hold 1s → confirm → fire + broadcast

Life-safety path:

1. **Long-press begins** on orb (or dedicated SOS tile). `WKInterfaceDevice.play(.warning)` fires immediately.
2. **1-second hold** triggers `EmergencyController.activate(reason:auth:connectivity:silent:)`.
3. **Confirm sheet** with 30-second countdown + Cancel button (silent-mode SOS via duress phrase skips sheet, sets `silent = true`).
4. **Fan-out on confirm:**
   - `emergencyProtocols.activate` fired through SOS lane (2s/5s backoff, never stale, never evicted).
   - `connectivity.triggerEmergencySOS(reason:coordinate:)` to phone — E911 call on larger radio.
   - Broadcast location continuously for 10 minutes into SOS lane.
   - `BlockchainAudit.append(kind: .emergency, payload:)` if `blockchainAuditEnabled` — tamper-evident anchor.
   - `ConvoyCoordinator` fan-out to trailing trucks so they learn something's wrong even if cellular dead.
   - `SatelliteFallback.composeSOS + sendSOS(channel: .globalstarEmergency, ...)` if `terrestrialDown` or user explicitly selects satellite escalation.

SOS is the one place wrist does not wait for acknowledgment — outbox retry contract alone guarantees delivery the moment any channel opens.

---

## 18. Siri integration — "Ask Esang" shortcut

`Intents/AskEsangIntent.swift` defines three `AppIntent`s:
- **`AskEsangIntent`** — "Hey Siri, ask Esang [query]" — parameterized with `@Parameter(title: "Question")`. Performs `EsangSession.submitTranscribedText`, returns `.result(dialog:)` so Siri speaks reply.
- **`EsangSOSIntent`** — "Hey Siri, Esang SOS" — fires `EmergencyController.activate(reason: "siri-sos", ...)`, returns "Emergency services are being contacted."
- **`HOSStatusIntent`** — "Hey Siri, check my HOS on EusoTrip" — synthesizes drive/window reply from `HOSStore.shared.current`.

`EusoTripAppShortcuts: AppShortcutsProvider` exposes with multiple phrase variants — users see in Shortcuts app + Action Button settings. `AskEsangIntentRegistrar.register()` calls `EusoTripAppShortcuts.updateAppShortcutParameters()` on every cold launch.

**NSUserActivity handoff.** `EusoTripConfig.handoffActivityType = "com.eusotrip.esang.activate"` declared in both iOS + watchOS `Info.plist` under `NSUserActivityTypes` — "Esang activated from iPhone" handoff surface appears in watch dock when iOS app active.

**Current state:**
- `AskEsangIntent` — SHIPPING, behind `openAppWhenRun: true`.
- `EsangSOSIntent` — SHIPPING, duress-mode phrase "Esang SOS".
- `HOSStatusIntent` — SHIPPING.
- `LogHOSIntent` — SCAFFOLDED, not yet exposed; will route status swaps through `VoiceActionDispatcher` with Siri confirmation.
- `NavigateToLoadIntent` — SCAFFOLDED, will surface active load's pickup or delivery in Maps watch app.

---

## 19. Complication templates per watch face

`HOSComplication` supports `.accessoryCircular, .accessoryRectangular, .accessoryInline`. `ActiveLoadComplication` supports `.accessoryCircular` (load-type glyph), `.accessoryRectangular` (origin → destination with miles-to-go), `.accessoryInline` (`L-8817 Memphis → Dallas`).

Per-face guidance:
- **Modular Ultra / Modular** — HOS rectangular in top-row large, ActiveLoad inline in bottom.
- **Infograph** — HOS circular in one corner, ActiveLoad circular opposite; inline load at bottom.
- **California / Chronograph Pro** — HOS inline only; face is already dense.
- **Nightstand** — neither; driver is off-duty by definition.

`ComplicationRefresher.swift` reloads timelines via `WidgetCenter.shared.reloadAllTimelines()` on HOSStore updates, load state changes, reachability edges.

---

## 20. Notifications — load assigned, HOS warning, SOS ack, message

Four categories on wrist:
1. **Load assigned** — `UNUserNotificationCenter` local on new `load.assigned` from iOS; deep-links to `WatchLoadDetailView`.
2. **HOS warning** — fires when drive clock <30 minutes; haptic `.notification`, title "30 min drive left."
3. **SOS ack** — server acks SOS; haptic `.success`, category `EMERGENCY_ACK`.
4. **Message** — dispatcher or broker reply; haptic `.click`, deep-links to `InboxView`.

All four mirrored into iOS companion — driver sees notification on whichever surface they're actively looking at.

---

## 21. Battery budget — <3% drain/hr on-screen UI

Baseline: Apple Watch Series 7, always-on display enabled, Pulse orb visible for one hour on-wrist-but-idle (no voice captures, no SOS). Budget:

- Always-on ambient rendering — ~1.2%/hr (measured S7).
- HOSClockSwap 1 Hz tick — ~0.2%/hr.
- NWPathMonitor — ~0.1%/hr.
- OrbStateMachine + OrbLog — ~0.1%/hr.
- WCSession idle — ~0.3%/hr.
- CLLocation at `kCLLocationAccuracyBest` with 5m distanceFilter — ~1.0%/hr.

Voice capture + HKWorkoutSession pushes to ~15–20%/hr during active driving — price of staying alive for HOS window. Budgeted against 11-hour drive cycle. Series SE2 and earlier fall back to iPhone-resident fatigue scoring to stay under battery cliff.

---

## 22. Background modes — workout-processing (and the audio strip)

**Enabled on watch target:**
- `workout-processing` — required for `HKWorkoutSession` during hauls.
- `location` — for CLLocation pump feeding F02, F02b, F06, F13, F14.
- `remote-notification` — silent pushes that kick HOS / load refreshes.

**NOT enabled**: `audio`. iOS permits `audio` as background mode but watchOS does not — always rejected, stripped from plist. Voice capture only runs while app foregrounded or Digital Crown / AssistiveTouch invocation brings us back on-screen. Non-negotiable on watchOS.

---

## 23. WCSession best practices — coalescing + delivery

Every watch-to-phone + phone-to-watch call in `WatchConnectivityManager.swift` follows dual-path contract:

- **Reachable** (foreground-to-foreground): `session.sendMessage(payload, replyHandler:, errorHandler:)` — fast, expects ack, falls through to `transferUserInfo` on `errorHandler`.
- **Unreachable** (background, locked, wake-up-needed): `session.transferUserInfo(payload)` — FIFO queued, guaranteed on wake.

For latest-snapshot surfaces — HOS clock, active load, auth state — use `session.updateApplicationContext(_:)` which coalesces so burst of updates only delivers last. HOS clock specifically swapped from `sendMessage` to `updateApplicationContext` in build 24 — old path had class of "disappearing-timer" bugs where fast succession lost latest snapshot when reachability flickered.

**Op-code aliases.** iOS `WatchCommandHandler` now accepts Pulse op codes: `esang.activate` aliases activation handler, `esang.hos` aliases HOS handler, `handleExchange(_:)` processes `esang.exchange` payloads by surfacing transcript + posting `.esangRefreshSurface` so any open iOS view refreshes. Closes op-code-mismatch bug where Pulse emitted codes iOS didn't recognize and round-trips went partially silent.

---

## 24. Watch-only auth bypass via shared Keychain

Why shared Keychain access group matters: when paired iPhone unreachable — dead battery, left in truck, out-of-bluetooth-range — watch can restore Esang token from Keychain on cold launch and operate signed-in without ever talking to phone. Every outbox entry carries token through watch's own cellular radio (on cellular-equipped Ultra / Series 5+ cellular) or caches + retries through next reachability edge.

For non-cellular watches, this is the lifeline: wrist stays signed-in and queues HOS + SOS events into outbox even if phone absent. When phone returns, everything flushes with original idempotency keys — server sees clean, ordered replay.

Specifically why we invested in team-prefix-resolving Keychain code path rather than hard-coding: access group must resolve at runtime for any developer's local build, and both Pulse bundle + iOS companion have to see same token behind it.

---

## 25. Build 24 release notes integration

Pulse Build 24 is canonical reference build this doctrine codifies:
- **Launch stability** — phased `safeStep(name:work:)`, `lazy var` audio stack, no build-21 crash-to-home.
- **iPhone ↔ Pulse sync** — op-code aliases (`esang.activate, esang.hos, esang.exchange`), `esangRefreshSurface` notification, `auth.update` empty-string normalization.
- **F01 unified outbox** — five lanes, `esang-offline-queue.json`, envelope v2 with v1 migration.
- **F02 tunnel-aware ETA** — `TunnelAwareETA` with recovering state + drift metrics.
- **F03 satellite SMS fallback** — three channels, 160/240/160 byte caps, `composeSOS/sendSOS`.
- **F04 voice dispatch grammar** — ten-plus intents, live dual-write.
- **F05 HOS clock swap** — 1 Hz tick, 120s drift threshold, `.hosClockSwapped` re-sync animation.
- **Q3/Q4 scaffolds** — `MeshRelay, UWBDocking, FleetCRDT, BlockchainAudit` — all compile, all behind flags.
- **24-persona tab composition** — `RoleComposition.tabs(for:)` + `RoleTabHost` with placeholders for personas without dedicated views yet.
- **OutboxStatusView** — per-lane counts, oldest-entry age, retry attempts, last error — reachable via "show queued messages" voice command.
- **Feature flags** — every Q2 defaults `true`, every Q3/Q4 defaults `false`, flippable without rebuild.
- **`CURRENT_PROJECT_VERSION = 24`** across all eight target configurations.

Archive + upload: `EusoTrip.xcodeproj` → EusoTrip scheme → Any iOS Device (arm64) → Product → Archive → Organizer → Distribute App → App Store Connect → Upload. Pulse Watch App embeds automatically. TestFlight surfaces build under EusoTrip Pulse Watch App track within ~15 minutes.

---

## 26. The one-line doctrine

**Every action the driver takes on the wrist completes locally first, gets a spoken confirmation, earns a haptic within 100ms, and replays to the server with a stable idempotency key the moment any channel — cellular, WiFi, WCSession, satellite, or mesh — opens.**

That is the contract. Every design decision in F01–F16, every state in the nine-state orb machine, every line of `OfflineQueue, VoiceDispatch, DeadZoneCoast, SatelliteFallback, AudioSessionPreflight, DrivingSessionManager` exists to uphold it.

A driver in Eisenhower Tunnel, dead zone on Sonoran US-2, metal-wrapped berth at Long Beach, or north of Thunder Bay still has: working HOS, working dispatch, working SOS, a live orb that accepts input, a queue that flushes on next reachable path, and a wrist that never lies about what's estimated versus measured.

That's what second-to-none looks like in code.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
