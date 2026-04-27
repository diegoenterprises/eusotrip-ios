# Wave-3 Audit · Agent 02 · Driver Bucket 02 (screens 036-048)

Scope: 13 Driver screens covering the delivery-side lifecycle — ESANG smart stop on the en-route leg, receiver-gate ops, cryogenic/liquid discharge, dry-break disconnect/re-connect, departing the receiver, and multi-leg sequencing + arrival checkpoint + post-trip DVIR at home yard.

Backend routers referenced (all under `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/`):
- `driverMobile.ts` (1760 lines) — driver home, truck-stop finder, fuel stops, checklist, notifications
- `loadLifecycle.ts` (3528 lines) — state machine, transitions, checkIn, custodyChain, timers, approvals, compliance
- `loadStops.ts` — stop list, reorder
- `location.ts`, `tracking.ts`, `navigation.ts`, `geofencing.ts` — GPS, ETA, waypoint status, geofence events
- `weather.ts`, `restStops.ts`, `fuelManagement.ts` — fuel / rest / weather context
- `facilityIntelligence.ts` — approaching-trucks, facility search, hazmat rack pricing
- `hazmat.ts`, `erg.ts` — placards, ERG, segregation, trainingCompliance
- `inspections.ts` — DVIR templates, submit, history
- `bol.ts` — BOL + run-ticket generation; `pod.ts` — POD submit
- `relay.ts` — multi-leg relay (legs, handoff)
- `convoy.ts` — convoy positions
- `appointments.ts` — hazmat bays, decon schedule
- `yardManagement.ts` — gate log, dock schedule
- `spectraMatch.ts` — crude/product match, terminal catalog, destination intelligence
- `esangAI.ts`, `esangVoice.ts` — AI identify, voice (speak/preview)
- `safetyAlerts.ts` — SOS, speed events
- `zeunMechanics.ts` — breakdowns, self-repair, DTC lookup

Swift port directory contains screens 010-022 only; none of the 13 screens in this bucket are ported.

---

## 036 ESANG Smart Stop.png
**Swift port:** NOT PORTED
**Purpose (1-line):** ESANG recommends the next fuel/rest stop mid-route with ranked rationale (storm, HOS reset, fuel price, hazmat spaces) and offers Accept&Route / Skip.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Topbar kicker "ESANG SUGGESTS · 19:48" | Current suggestion timestamp | `esangAI.getRecent` (esangAI.ts:288) | Identify-event feed, not stop-specific |
| Title "Pull off in 6 mi for a stacked win" | ESANG rationale string | GAP — `esangAI.smartStopSuggestion` missing | Copy template not backed |
| Stop card (Pilot #341, 96 ESANG score) | Ranked truck stop | `driverMobile.getTruckStopFinder` (driverMobile.ts:859) | Returns stops; no ESANG-score field |
| Distance 6.0 mi · ETA delta +12m · Park 8/142 | Distance, ETA impact, live parking count | `restStops.getNearby` (restStops.ts:71), `driverMobile.getTruckParking` (driverMobile.ts:915) | Live parking counts heuristic |
| Reason row: Diesel $0.82/gal cheaper | Price delta vs current route | `fuelManagement.getFuelPrices` (fuelManagement.ts:179), `getOptimalFuelStops` (fuelManagement.ts:275) | OK |
| Reason row: Mandatory 30-min reset in 1h 18m | HOS clock | `hos.getCurrentStatus` (hos.ts:50), `driverMobile.getDriverHosStatus` (driverMobile.ts:1496) | OK |
| Reason row: 8 hazmat spaces confirmed | Hazmat parking availability | GAP — no hazmat-parking feed on `driverMobile.getTruckParking` | Column `hazmatSpaces` not exposed |
| Weather banner "storm cell 22 min, route around" | Weather hazard overlay | `weather.getRouteConditions` (weather.ts:149), `weather.getDriverRouteWeather` (weather.ts:363) | OK |
| "ESANG ranked 7 candidates" footer | Candidate count / provenance | GAP — no ranked-candidates log endpoint | Audit trail missing |
| Skip (secondary) | Dismiss suggestion | GAP — `esangAI.dismissSuggestion` missing | Need feedback channel |
| Accept & route (primary) | Lock stop into route | `navigation.calculateRoute` (navigation.ts:24) + `routeOptimization` reroute | Re-route path OK; commit + audit GAP |
| Bottom nav (Home/Trips/ESANG orb/Wallet/Me) | App nav | n/a | Shell nav |

### Backend GAPS
1. `esangAI.smartStopSuggestion` — ranked stop suggestion with composite score/rationale, currently only `getRecent` exists.
2. `driverMobile.getTruckParking` returns no `hazmatSpaces`/ERG-class field.
3. `esangAI.dismissSuggestion` (user feedback → improves ranker) missing.
4. No audit procedure that logs "accepted/skipped" decisions (`esangAI.logAccuracy` exists at esangAI.ts:316 but is oil-product identify, not stop-suggest).

### User-journey entry points
- Upstream screen 035 En Route Drive (active in_transit).
- Event: mid-route geofence approach + HOS/weather/fuel thresholds trigger ESANG suggestion (see `EusoMap/EusoTrip_GPS_Navigation_Geofencing_System.md`).
- Push notification: "ESANG: stacked win 6 mi ahead".
- Backend state required: load `status ∈ {in_transit}`, active HOS clock, weather/fuel/parking feeds live, hazmat flag on load (for placard-aware parking).

---

## 037 Approaching Receiver.png
**Swift port:** NOT PORTED (Swift port `020_ApproachingDelivery.swift` covers Wave-2 equivalent, not this petroleum-receiver variant)
**Purpose (1-line):** Within 7 min of Wawa Lancaster drop; hazmat PPE checklist + ESANG ping + spotter contact for vapor-recovery discharge.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Turn-by-turn kicker "APPROACHING DESTINATION · NH₃ 6,800 gal" | Product + destination | `loads.getById` (loads.ts:1012), `tracking.getVehicleLocation` (tracking.ts:169) | OK |
| Distance 3.6 mi · 7 min · ETA 11:25 | Live ETA | `navigation.getETA` (navigation.ts:123), `navigation.updateETA` (navigation.ts:144) | OK |
| Facility card (Wawa Distribution Lancaster) | Stop/facility meta | `loadStops.getByLoadId` (loadStops.ts:45), `facilityIntelligence.getById` (facilityIntelligence.ts:50) | OK |
| Gate 1 / Bay 6 / Contact Sara Quintanilla + phone | Dock + contact | `yardManagement.getDockSchedule` (yardManagement.ts:456), `facilityIntelligence.search` | Contact phone GAP |
| Hazmat receiving warning strip | Product hazard memo | `hazmat.getRouteRestrictions` (hazmat.ts:401), `productProfiles` | Partial |
| Pre-arrival checklist row 1 "Hazmat PPE on" CONFIRMED | Driver acknowledgment | `driverMobile.submitChecklist` (driverMobile.ts:1127), `drivers.getPreTripChecklist` | OK |
| Checklist row 2 "BOL + Class 3 ERC card" READY | Document readiness | `driverMobile.getDriverDocuments` (driverMobile.ts:1280), `erg.getMetadata` (erg.ts:149) | OK |
| Checklist row 3 "ESANG arrival ping" SAVED | Geofence ping status | `geofencing.recordEvent` (geofencing.ts:194) | OK |
| Checklist row 4 "Spotter contact saved" PENDING | Spotter assignment | GAP — no `spotter.assign` or contact-save proc | Spotter role undefined |
| ESANG banner "Rack 3 arm 3 staged" | Facility arm assignment | `facilityIntelligence.getApproachingTrucks` (facilityIntelligence.ts:411), `terminals` | Data present; field naming GAP |
| Trip log (secondary) | Open load timeline | `loads.getTimeline` (loads.ts:1507) | OK |
| Notify receiver (primary) | Send ETA ping | GAP — `notifications.notifyFacility` missing (closest: `appointments.sendReminder` appointments.ts:321) | No driver→receiver notify |

### Backend GAPS
1. Spotter assignment/contact persistence missing (no router).
2. `notifications.notifyFacility` / `receiver.notifyArrival` missing; only `appointments.sendReminder` exists.
3. Facility contact phone not exposed in current facility queries.
4. ESANG "rack/arm" fields not a first-class column.

### User-journey entry points
- Upstream: 035 En Route Drive / 036 Smart Stop (skip or resume).
- Event: DELIVERY_APPROACH geofence ENTER (<5 mi) (see geofencing system md).
- Push: "Wawa Lancaster 5 mi ahead — review checklist".
- Backend state: load `status ∈ {in_transit}` transitions to `at_delivery` on arrival geofence.

---

## 038 At Receiver Gate.png
**Swift port:** NOT PORTED (`021_AtReceiverGate.swift` covers dry-van variant; this is hazmat-petroleum variant)
**Purpose (1-line):** Arrived at receiver perimeter; stepped flow Show Credentials → Security Verify → Bay Assigned, with QR kiosk / PIN+DOT plates.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Arrived card (geofence entered 11:24) | Arrival timestamp + elapsed | `geofencing.recordEvent` (geofencing.ts:194), `location.geofenceEvent` (location.ts:182) | OK |
| Step indicator (Show → Security → Bay) | Current step | GAP — facility check-in stepper state not modeled | Only load status |
| Driver credential QR block | CDL/driver QR token | `driverMobile.getDriverDocuments` (driverMobile.ts:1280) | No QR-token mint |
| "Kiosk reads QR, assigns Bay 6" (LIVE) | Facility kiosk reader | GAP — `kiosk.readCredential` + `facility.assignBay` | Yard mgmt has dock schedule but not auto-kiosk |
| PIN + DOT plates info | Security hut info | `hazmat.getSecurityPlanStatus` (hazmat.ts:1052) | Partial |
| Wallet chips (BOL packet, Hazmat manifest, Sched window, ERG card) | Document shortcuts | `driverMobile.getDriverDocuments`, `bol.getSummary` (bol.ts:346), `erg.search` | OK |
| Queue chip "2 of 4 · ~6 min" | Queue position | `yardManagement.getGateLog` (yardManagement.ts:1508), `facilityIntelligence.getApproachingTrucks` | Partial — explicit queue-position GAP |
| "Handoff arming 11:25" (custody) | Chain-of-custody arming | `loadLifecycle.getCustodyChain` (loadLifecycle.ts:3516) | Read-only; arming mutation GAP |
| Call (secondary) | Call facility | `communicationHub.*` (messaging) | OK |
| Show QR / Show pass at gate (primary) | Transition to check-in | `loadLifecycle.checkIn` (loadLifecycle.ts:3466) type="delivery" | OK — transitions to `delivery_checkin` |
| Bottom nav | Shell nav | n/a | — |

### Backend GAPS
1. No kiosk/facility credential reader endpoint (`facility.readKiosk`).
2. Driver QR token minting not in routers.
3. Explicit queue position "N of M" not exposed.
4. Custody-chain "arming" mutation (vs read) missing.
5. Facility check-in stepper state (step 1→2→3) not modeled.

### User-journey entry points
- Upstream: 037 Approaching Receiver.
- Event: delivery geofence enter → status `at_delivery`.
- Push: "At Wawa Lancaster — show QR".
- Backend state: load `status = at_delivery`, pending `delivery_checkin`.

---

## 039 Backing Assist Receiver.png
**Swift port:** NOT PORTED
**Purpose (1-line):** Live multi-cam assist (rear, L/R mirrors) + spotter voice overlay + auto parking-brake advisor while backing into Bay 6.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Kicker "Backing into Bay 6 · Wawa Lancaster" | Facility + bay assigned | `yardManagement.getDockSchedule` (yardManagement.ts:456), `yardManagement.assignYardMove` (yardManagement.ts:1722) | OK |
| Rear cam feed (target line, 14 in) | Live telemetry camera | GAP — no `telemetry.cameraStream` or `backing.feed` | Camera stack undefined |
| Left/right mirror feeds (18/14 in) | Clearance deltas | GAP — same backing-assist router missing | — |
| Distance-to-pad ring "14 / Set parking brake at 4 in" | Live proximity alert | GAP — `backingAssist.calculateEngage` missing | Real-time LiDAR/prox math |
| L/R clearance chips (18 in / 14 in) | Running clearance | GAP | — |
| Spotter live voice (Sara Q · signal bars) | Voice comm channel | `esangVoice.speak` (esangVoice.ts:59), `communicationHub.*` | Voice TTS OK; spotter-live channel GAP |
| Hold (secondary) | Pause backing session | GAP | — |
| Set parking brake (primary) | Driver confirms brake set | GAP — `backingAssist.confirmBrake` + status transition | No status for "backing complete" |

### Backend GAPS
1. `backingAssist.*` router entirely missing: camera stream, clearance feed, brake-engagement, spotter voice session, session start/stop.
2. No "backing" load-status; would need new state between `delivery_checkin` and `unloading`.
3. No telemetry ingestion for clearance/LiDAR from truck sensors.

### User-journey entry points
- Upstream: 038 At Receiver Gate → bay assigned.
- Event: dock approach geofence + bay assignment from facility.
- Backend state: load `status = delivery_checkin`, bay/dock assigned via `yardManagement.assignYardMove`.

---

## 040 Discharge in Progress.png
**Swift port:** NOT PORTED
**Purpose (1-line):** Live gasoline/NH₃ discharge telemetry — flow, pressure, temp, vapor + ESANG hazwatch status and Emergency Stop.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Header "Discharging gasoline/NH₃ · Bay 6 · 00:14:08 elapsed" | Active discharge session timer | GAP — `discharge.startSession` / `getSession` missing | No discharge router |
| Transferred 5,200 gal / Remaining 3,400 gal · 60% bar | Volume telemetry | GAP — `runTickets.calculateRunTicketVolumes` exists (bol.ts:796) but not live stream | Session telemetry not wired |
| Flow rate 220 gpm (chart) | Live gpm chart | GAP | — |
| Truck dropping 40% / Receiver rising 64% bars | Dual-tank live levels | GAP | — |
| Pressure 38 psi / Temp 71 °F / Vapor 14 ppm | Sensor readings | GAP — `trailerRegulatory` has spec, not live | — |
| ESANG hazwatch: VRC, ESD bond, scrubber, sensors, spill-kit rows | Continuous compliance monitor | `hazmat.validateLoad` (hazmat.ts:171) (single-shot only) | Live monitor GAP |
| PAUSE (secondary) | Pause session | GAP | — |
| EMERGENCY STOP (danger) | SOS + halt discharge | `safetyAlerts.triggerSOS` (safetyAlerts.ts:15) | SOS path OK; discharge-stop ack GAP |

### Backend GAPS
1. Entire `discharge.*` / `transferSession.*` router missing (start, live-tick, pause, resume, complete).
2. No live sensor telemetry ingestion for pressure/temp/vapor/flow.
3. Hazwatch continuous monitor procedure missing.
4. Discharge-specific "emergency stop" coupling to hardware not present.

### User-journey entry points
- Upstream: 039 Backing Assist → brake confirmed → hose connected.
- Event: operator presses Start Discharge; BOL opens transfer session.
- Backend state: load `status ∈ {unloading}`; run-ticket initiated via `bol.generateRunTicket` (bol.ts:612).

---

## 041 Discharge Complete.png
**Swift port:** NOT PORTED
**Purpose (1-line):** Discharge closed — totals, start/end, post-flow checklist (pump off, VRC purged), ESANG custody BOL SEALED + signature.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Header "Discharge complete · 28:42 total · 100% bar" | Completed session summary | GAP — `discharge.completeSession` missing | — |
| Transferred 8,600 gal · BOL reconciled +22 gal | Final volumes + reconciliation delta | `bol.calculateRunTicketVolumes` (bol.ts:796), `bol.generateCompletionTicket` (bol.ts:821) | OK for totals; delta/reconciliation GAP |
| Peak rate 224 gpm / Avg 200 gpm | Session stats | GAP | — |
| Tanks "settled" (truck 0% / receiver 83%) | Final gauge snapshot | GAP | — |
| Post-flow checklist 3/3 confirmed | Checklist completions | `driverMobile.submitChecklist` (driverMobile.ts:1127) | Reusable |
| ESANG custody card BOL SEALED + hash | Chain-of-custody event | `loadLifecycle.getCustodyChain` (loadLifecycle.ts:3516) | Read; seal-mutation GAP |
| Share (secondary) | Share BOL | `loads.share` (loads.ts:1958) | OK |
| Disconnect & verify (primary) | Transition to disconnect | GAP — `discharge.markComplete` → status `unloaded` missing direct path | `loadLifecycle.executeTransition` exists (line 2247) |

### Backend GAPS
1. `discharge.completeSession` summary-persistence missing.
2. BOL reconciliation delta (+22 gal) — no endpoint; `runTickets` computes volumes only.
3. Custody seal mutation ("sealed") not exposed; only read via `getCustodyChain`.
4. Peak/Avg flow-rate session stats not persisted.

### User-journey entry points
- Upstream: 040 Discharge in Progress (flow complete).
- Event: flow rate=0 sustained → auto-trigger "complete" modal.
- Backend: load `status: unloading → unloaded` via `loadLifecycle.executeTransition`.

---

## 042 Disconnect and Verify.png
**Swift port:** NOT PORTED
**Purpose (1-line):** Step-by-step dry-break disconnect wizard — vent residual, retract collar, cap/stow hose, walk-around.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Kicker "Disconnecting drop hose · Bay 6 · Step 2 of 4" | Wizard progress | GAP — no `disconnectWizard.*` router | — |
| SVG dry-break animation · LIVE pill | Visual cue only | n/a | Client-only |
| Current step "Retract dry-break collar" | Step title + instructions | GAP — step content not in DB | Could live in `dvirTemplates` style |
| Pressure 0 psi / Vapor 8 ppm / ESD bond LIVE | Residual sensor readings | GAP — sensor telemetry router missing | — |
| Ladder (4 steps, status per step) | Checklist progress | `driverMobile.submitChecklist` (driverMobile.ts:1127) | Reusable |
| Spotter note (Sara Q live rec) | Spotter annotation | GAP — no spotter-note persistence | — |
| Help (secondary) | Inline help | `support.*` | OK |
| Confirm uncoupled (primary) | Mark step complete, advance | `driverMobile.submitChecklist` (driverMobile.ts:1127) | Reusable container; no wizard fsm |

### Backend GAPS
1. Dedicated `disconnectWizard.*` FSM (steps, validation, per-step sensor gating) missing.
2. Spotter live-recording / annotation persistence missing.
3. Residual sensor stream ingestion missing.

### User-journey entry points
- Upstream: 041 Discharge Complete → "Disconnect & verify".
- Event: discharge complete + spotter on-watch.
- Backend state: load `status = unloaded`; dry-break coupler live.

---

## 043 Disconnect Confirmed.png
**Swift port:** NOT PORTED
**Purpose (1-line):** All 4 disconnect steps verified, hose stowed, binder closed; dock receipt acknowledged + ESANG AI co-signature; Depart CTA.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Header "Disconnect confirmed · 07:00 elapsed · all steps verified" | Wizard totals | GAP (see 042) | — |
| SVG "hose stowed · collar seated" | Visual cue | n/a | — |
| Pressure/Vapor/ESD "Released" chips | Final sensor state | GAP | — |
| Ladder 4/4 confirmed | Completed checklist | `driverMobile.submitChecklist` | Reusable |
| Dock receipt card (operator acks) — ACKNOWLEDGED | Facility operator confirmation | GAP — no `facility.dockReceiptAck` proc | — |
| ESANG · AI co-signature, hash WAR-23117-C44F-7B91 | Blockchain/audit hash | `blockchainAudit.*` (blockchainAudit.ts) | Check exists |
| Receipt (secondary) | View/download dock receipt | `documentCenter.*` / `documents.*` | OK |
| Depart receiver (primary) | Transition to departing / next leg | `loadLifecycle.executeTransition` (loadLifecycle.ts:2247) | To `delivered` status |

### Backend GAPS
1. Facility-side dock-receipt acknowledgment endpoint missing.
2. ESANG AI co-signature proc absent; closest is `esangAI.identify` (identify-only, not signature).
3. Final `released` sensor state persistence missing.

### User-journey entry points
- Upstream: 042 Disconnect & Verify → all 4 confirmed.
- Event: operator acks dock receipt → Depart enabled.
- Backend state: `unloaded → pod_pending` or `delivered` (per loads enum line 282).

---

## 044 Connect Drop Hose.png
**Swift port:** NOT PORTED
**Purpose (1-line):** (Edge case / different load) Connecting drop hose at Wawa — 4-step dry-break mate wizard, live ESD-bond + leak-test.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Kicker "Connecting drop hose · Wawa Lancaster Bay 6 · Step 2 of 4" | Wizard progress | GAP — no `connectWizard.*` router | — |
| Dry-break mate SVG · LIVE | Visual cue | n/a | — |
| ESD bond LIVE continuity OK | Bond probe reading | GAP | — |
| Pressure check 0 psi EMPTY / Leak test PRIMING NAATS step 1 | Pre-flow sensor readings | GAP | — |
| Connect ladder 4 steps | Checklist | `driverMobile.submitChecklist` | Reusable |
| Spotter note (Sara Q) | Live voice hint | `esangVoice.speak` | OK for playback |
| Help (secondary) | Inline help | `support.*` | OK |
| Confirm seated / Confirm mated (primary) | Advance step | `driverMobile.submitChecklist` | Reusable |

### Backend GAPS
1. Dedicated `connectWizard.*` FSM missing.
2. ESD bond / leak-test sensor ingestion missing.
3. No "hose connected" status transition (needed pre-discharge).

### User-journey entry points
- Upstream: 039 Backing Assist (after brake set) → operator stages hose.
- Event: spotter signals ready; system transitions to connect wizard.
- Backend state: load `status = delivery_checkin`; arm Bay 6 live.

---

## 045 Departing Receiver.png
**Swift port:** NOT PORTED
**Purpose (1-line):** Past-gate summary — seal status, elapsed at dock, next pickup tender preview, start-next-leg / off-duty CTA.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Kicker "Departing receiver · Wawa Lancaster · TRIP DONE" | Leg complete banner | `loads.updateLoadStatus` (loads.ts:2774) | OK |
| Trailer SVG "Clear of dock · 0.3 mi past gate" | Live proximity | `location.getLoadLocation` (location.ts:538), `tracking.getVehicleLocation` | OK |
| Exit status chips (at receiver 47 min elapsed, BOL hash, Sealed) | Trip metadata | `loadLifecycle.getCustodyChain`, `bol.getSummary` | OK |
| "Next pickup · Buckeye Pipeline Malvern" card | Next leg preview | `relay.getMyLegs` (relay.ts:283), `relay.getLegs` (relay.ts:54) | OK |
| HOS window 6h 22m / Sequenced tendered | Driver HOS + tender | `hos.getCurrentStatus` (hos.ts:50), `loadLifecycle.executeTransition` for tender | OK |
| Route preview 24 mi / 33 min elevation chart | Next-leg route shape | `navigation.calculateRoute` (navigation.ts:24) | OK |
| 15-min break / Off-duty (secondary) | Change duty status | `hos.changeStatus` (hos.ts:93), `drivers.stopDriving` (drivers.ts:1272) | OK |
| Start next leg / Start return (primary) | Begin next leg | `relay.updateLegStatus` (relay.ts:196), `loadLifecycle.executeTransition` | OK |

### Backend GAPS
1. "0.3 mi past gate" — facility exit-geofence not in current geofence types (`enter|exit|dwell|approach` — exit exists, just needs facility-exit wiring).
2. "Sealed" final chip depends on unclosed custody-seal mutation (see 041/043).
3. No unified "trip wrap" summary endpoint; client aggregates.

### User-journey entry points
- Upstream: 043 Disconnect Confirmed → Depart receiver.
- Event: facility geofence EXIT.
- Backend state: load `status = delivered` or `complete`; next relay leg in `awarded/assigned` state.

---

## 046 Sequenced Leg Approach.png
**Swift port:** NOT PORTED
**Purpose (1-line):** Approaching next pickup in a sequenced (2/3) relay — pre-rack checklist (EusoShield, MC-306 purge, load-card pinned, rack-in handshake).

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Kicker "APPROACHING PICKUP · GASOLINE LOAD 2 · 2/3 SEQUENCED" | Sequence position | `relay.getMyLegs` (relay.ts:283) | OK |
| Distance 4.8 mi / 7 min / ETA | Live ETA | `navigation.getETA` (navigation.ts:123) | OK |
| Leg handoff card (Leg 1 sealed → Leg 2 open) | Custody handoff | `relay.confirmHandoff` (relay.ts:232), `loadLifecycle.getCustodyChain` | OK |
| Facility Buckeye Pipeline Malvern · Gate 2 · Rack 9 arm 3 | Facility + rack assignment | `facilityIntelligence.search` (facilityIntelligence.ts:37), `facilityIntelligence.getApproachingTrucks` | Partial — arm field GAP |
| Rack contact Danelo Cavalcante + phone | Contact info | `facilityIntelligence.getById`, `contacts.*` | Phone GAP |
| Pre-rack checklist (EusoShield binder extended, MC-306 purge, UN1203 card pinned, Rack-in handshake) | Pre-rack verifications | `driverMobile.submitChecklist` (driverMobile.ts:1127), `hazmat.validateLoad` (hazmat.ts:171) | Reusable; Eusoshield-specific GAP |
| ESANG banner (rack 9 arm 3 staged, pre-read 99.8%) | Spectra pre-read status | `spectraMatch.quickDestinationMatch` (spectraMatch.ts:763) | OK |
| — | Start next leg | `relay.updateLegStatus` | OK |

### Backend GAPS
1. Rack/arm assignment not a first-class facility field.
2. "EusoShield binder extended for load 2" — Eusoshield binder state machine missing.
3. "MC-306 residual-sweep passed" — trailer-specific decon record not exposed (`appointments.getDeconSchedule` exists but read-only).
4. Rack handshake endpoint missing.

### User-journey entry points
- Upstream: 045 Departing Receiver → relay leg 2.
- Event: DELIVERY_APPROACH (Buckeye) geofence ENTER.
- Backend state: leg `status = in_transit → approaching_pickup`; binder state from prior leg.

---

## 047 Arrival Checkpoint.png
**Swift port:** NOT PORTED
**Purpose (1-line):** Arrived at home-yard (Curtis Bay) for 34-hr reset; catalyst yard check-in + post-trip DVIR queued + HOS reset starts.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Kicker "ARRIVED · HOME YARD · 0:02 / 0:04 on site" | Arrival elapsed | `geofencing.recordEvent` (geofencing.ts:194), `location.geofenceEvent` | OK |
| Trailer art "Parked at Curtis Bay Row 4 · S-14" | Parking spot | `yardManagement.assignYardMove` (yardManagement.ts:1722), `yardManagement.getYardMap` (yardManagement.ts:344) | OK |
| Checkpoint card — 78 mi Yara York → Curtis Bay / 49 CFR 396.11 tractor + MC-311 | Leg summary + inspection targets | `loads.getTimeline` (loads.ts:1507), `inspections.getPrevious` (inspections.ts:263) | OK |
| Facility Catalyst Curtis Bay driver yard | Destination meta | `facilityIntelligence.getById` | OK |
| Gate C (badge) / Row 4 · Spot S-14 / Bay 14 · shower+laundry / Yard open 24/7 / Catalyst phone | Facility amenities + contact | `facilityIntelligence.getById`, `facilityIntelligence.getRequirements` | Amenities/hours GAP |
| Post-trip DVIR card — 34-hour reset begins / Residual purity 99.8% RBOB target (pre-read) | Reset timer + spectra | `hos.changeStatus` (hos.ts:93) for reset, `spectraMatch.quickDestinationMatch` (spectraMatch.ts:763) | OK |
| Yard-in checklist (MC-311 decon cleared, EusoShield binder closes, HOS 34-hr primed, Post-trip DVIR pending) | Checklist | `driverMobile.submitChecklist`, `inspections.getTemplate` (inspections.ts:42), `hos.*` | Most reusable |
| Bottom bar (Home/Trips/ESANG/Wallet/Me) | Nav | n/a | — |

### Backend GAPS
1. Home-yard "34-hr reset priming" — HOS engine does not auto-prime reset from arrival event.
2. Yard amenities (shower/laundry/24-7 hours) not exposed in facility router.
3. EusoShield binder closure event not modeled.
4. MC-311 decon "cleared at Yara York" — cross-leg decon cert linkage GAP.

### User-journey entry points
- Upstream: 045 Departing Receiver (final leg) or 046 Sequenced Leg complete.
- Event: home-yard geofence ENTER.
- Backend state: load `status = complete`; next duty status = `off_duty`; DVIR due.

---

## 048 Arrival-Gate Task Active.png
**Swift port:** NOT PORTED
**Purpose (1-line):** Post-trip DVIR walk-around active — confirm placards + ERG 125 copy under visor before sleeper; walk-around gates with pass/verify.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Kicker "Post-trip DVIR · walkaround active · Step 3 of 4 · 3:42" | Wizard progress | `inspections.createDVIR` (inspections.ts:279), `inspections.submit` (inspections.ts:143) | OK (per-step state GAP) |
| Tractor SVG (MC-311 · 396.11) | Vehicle asset art | n/a | — |
| Current step "Placards + ERG 125 copy under visor" | Step instruction | `inspections.getTemplate` (inspections.ts:42), `erg.search` (erg.ts:41) | OK |
| Air tanks / Tires / Lights chips (PSI 2, 10/10, 22/22) | Gauge readouts | GAP — no live air/tire telemetry ingest | — |
| Walkaround gates (tractor, MC-311 trailer sweep, placards + ERG, sign+submit DVIR) | Gate status list | `loadLifecycle.getAvailableTransitions` (loadLifecycle.ts:2140) | Conceptually; DVIR-gates GAP |
| ESANG banner ("DVIR primed · sleeper bay 14 held · 34-hr reset starts · breakfast 06:30 slot held") | Reset context | `hos.getCurrentStatus`, `facilityIntelligence.getRequirements` | Partial — amenity scheduling GAP |
| Need help? (secondary) | Support | `support.*` | OK |
| Confirm placards OK (primary) | Advance gate, eventually submit DVIR | `inspections.submit` (inspections.ts:143), `drivers.submitDVIR` (drivers.ts:978) | OK |

### Backend GAPS
1. DVIR wizard per-step state (gate-by-gate advance with evidence photo hooks) missing; current `inspections.submit` is one-shot.
2. Live air/tire telemetry not in routers (would live under `equipmentIntelligence` or `telemetry`).
3. ERG "copy under visor" photo-verification specific gate missing.
4. Amenity scheduling (sleeper bay 14 held, breakfast slot) not modeled.

### User-journey entry points
- Upstream: 047 Arrival Checkpoint → "Post-trip DVIR pending".
- Event: driver taps DVIR CTA after yard-in checklist.
- Backend state: load `status = complete`, DVIR record created via `inspections.createDVIR`; HOS moving to `off_duty` after submit.

---

## Summary

**Totals**
- Screens audited: 13
- UI elements mapped: ~165
- Elements with direct backend binding: ~95
- Elements flagged GAP: ~70
- **% backed (approx): ~58%**
- Swift port coverage for this bucket: 0/13 (Wave-2 Swift ports stop at 022)

**Top-3 gaps (cross-cutting)**
1. **Physical-transfer telemetry + FSMs are missing end-to-end**: no `discharge.*`, `disconnectWizard.*`, `connectWizard.*`, `backingAssist.*` routers. Live sensor ingestion (pressure, temp, vapor, flow, ESD bond, leak-test, air, tires, LiDAR clearances) has no endpoint. These drive screens 039, 040, 042, 043, 044, and 048. Highest-impact gap since these are the in-bay critical-path screens.
2. **ESANG smart-stop + spotter workflow incomplete**: `esangAI.smartStopSuggestion`, `esangAI.dismissSuggestion`, spotter assignment/notes/live-voice channel, AI co-signature procs are missing. `esangAI.ts`, `esangVoice.ts`, `communicationHub.ts` exist but do not cover these flows. Blocks screens 036, 039, 042, 044.
3. **Custody & facility state gaps**: custody-seal *mutation* (read-only via `loadLifecycle.getCustodyChain`), facility kiosk credential reader, queue position "N of M", rack/arm assignment field, dock receipt operator-ack, facility amenities (shower/hours/contact phone), home-yard 34-hr reset auto-prime. Affects screens 037, 038, 041, 043, 045, 046, 047.

**Secondary gaps worth noting**
- Geofence "exit" event type exists; facility-exit wiring and "0.3 mi past gate" derived distance not exposed.
- Relay leg status transitions (`relay.updateLegStatus`) are good; sequenced pre-rack validations (MC-306 purge, Eusoshield binder extend/close, UN1203 load-card pinning) need dedicated routers.
- SPECTRA-MATCH quick pre-read is wired (`spectraMatch.quickDestinationMatch`); tolerance-gate hook for the "ESANG dispatch brief pre-staged" banner on 048/047 would need an orchestration layer.

**Recommended next routers to scaffold**
- `discharge.ts` (session lifecycle + live telemetry + emergency stop ack)
- `transferWizard.ts` (connect + disconnect shared FSM with per-step gates)
- `backingAssist.ts` (camera feed URLs, clearance ticks, brake-engage event)
- `facilityKiosk.ts` (QR read, bay assign, queue position, dock-receipt ack)
- `spotter.ts` (assign, contact, live voice session, notes)
- `esangAI.smartStop.*` expansion (ranked suggestions, accept/skip feedback, audit log)
- `custodySeal.ts` (seal/unseal mutation, AI co-signature, hash issuance)
