# Wave-3 Audit — Agent 01 (Driver screens 023-035)

Scope: 13 Driver screens from `_bucket_01`. Swift porting for this bucket hits a cliff at `022_DockAssigned.swift`; everything 023+ is **NOT PORTED**.

Backend root scanned: `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/` (280+ router files) plus `drizzle/schema.ts` (referenced in `drivers.ts:13`).

Routers cited most often below:
- `driverMobile.ts` (driver UI dashboards/schedule/HOS wrappers)
- `drivers.ts` (`getCurrentAssignment`, `updateLoadStatus`, `submitDVIR`, `acceptLoad`, `declineLoad`, `startDriving`, `stopDriving`, `getMyHOS`)
- `loadLifecycle.ts` (state machine, `transitionState`, `checkIn`, `getCustodyChain`, `getActiveTimers`)
- `location.ts` (`locationBatch`, `geofenceEvent`, `calculateRoute`, `recalculateETA`, `getActiveRoute`, `checkRouteDeviation`, `createForLoad`)
- `bol.ts` (`generate`, `list`, `generateRunTicket`, `calculateRunTicketVolumes`, `generateCompletionTicket`, `generateBOLFromLoad`)
- `pod.ts` (`submitPOD`, `approvePOD`, `rejectPOD`)
- `signatures.ts` (`save`, `verify`, `getPending`)
- `spectraMatch.ts` (`identify`, `identifyWithAI`, `getCrudeSpecs`, `saveToRunTicket`, `getDestinationIntelligence`, `quickDestinationMatch`)
- `erg.ts` (`searchByUN`, `getGuidePage`, `getHazardClass`)
- `hazmat.ts` (`determinePlacards`, `validateLoad`, `verifyDriverEndorsement`, `getHazmatRoute`, `getRouteRestrictions`)
- `hos.ts` (`getStatus`, `getCurrentStatus`, `changeStatus`, `certifyLog`)
- `eld.ts` (`getDriverStatus`, `getDriverELDCompliance`)
- `routing.ts` (`calculateRoute`, `getRoute`, `getETA`, `updateETA`, `updateWaypointStatus`, `activateRoute`, `completeRoute`)
- `navigation.ts` (`calculateRoute`, `getHOSRoutePlan`, `optimizeRoute`, `getFuelStops`)
- `geofencing.ts` (`createLoadGeofences`, `checkLocation`, `recordEvent`)
- `detentionAccessorials.ts` (`getActiveDetentions`, `calculateDetention`, `disputeDetention`)
- `yardManagement.ts` (`getDockSchedule`, `checkInTrailer`, `checkOutTrailer`, `assignTrailer`, `updateTrailerPosition`)
- `messaging.ts` (`sendMessage`, `getConversations`, `getInbox`)
- `wallet.ts` (`getBalance`, `getSummary`)
- `earnings.ts` (`getWeeklySummary`, `getEarnings`, `getPayStatement`)
- `appointments.ts` (`checkIn`, `startLoading`, `complete`)
- `runTickets.ts` (`create`, `addExpense`, `complete`, `validateRunTicket`)
- `hazmat.ts`, `inspections.ts`, `tankMonitor.ts`

---

## 023 Backing In.png

**Swift port:** NOT PORTED
**Purpose (1-line):** Live backing-aid camera view with ESANG alignment coaching and dock distance sensors while reversing into a receiver door.

### UI elements to backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Status chip "BACKING IN · DOOR 47" | Load lifecycle sub-state | `loadLifecycle.ts:3021 transitionState` | sub-state not in enum, GAP |
| Header "Driver-side · Aisle 5 · grocery receiving" | Dock assignment metadata | `yardManagement.ts:928 assignTrailer`, `:456 getDockSchedule` | reads dock + aisle |
| Subtitle "Trailer TR-2118 · Load EUSO-2026-04-16-004182" | Load+trailer IDs | `drivers.ts:215 getCurrentLoad`, `loads.ts:1012 getById` | basic |
| Pause button | Pause backing-aid session | GAP | new `backingAid.pauseSession` |
| Live camera viewport (LIVE · DOOR 47 · REAR · 1080P) | Dock camera stream | GAP | no camera/streaming router |
| Timer `16:04:31` | Session elapsed timer | GAP | client-only OK, else `loadLifecycle.getActiveTimers` |
| Cam ID pill `cam4 · 1080p` | Camera source id | GAP | `backingAid.listCameras` |
| Driver-side distance card "18" · to jamb" | Ultrasonic sensor | GAP | `backingAid.getSensorReadings` |
| Center rear card "2' 4" · to dock rubber" | Ultrasonic sensor | GAP | same |
| Blind-side card "32" · door 48" | Ultrasonic sensor | GAP | same |
| Alignment slider "-2° ease right" | Steering delta value | GAP | `backingAid.getAlignment` |
| ESANG coaching banner ("Ease right, then back…") | AI instruction stream | `esangAI.ts` ecosystem exists but no backing-aid channel | GAP: `esangAI.coachBacking` |
| "Pull up & redo" button | Reset attempt counter | GAP | `backingAid.resetAttempt` |
| "Set brakes" primary CTA | Commit brake set, end backing | `loadLifecycle.ts:3021 transitionState` (new event `BRAKES_SET`) | GAP: event missing |
| Tab bar (Home/Trips/ESANG/Wallet/Me) | Nav only | n/a | |

### Backend GAPS (numbered)
1. **No backing-aid camera/sensor router.** Propose a new `backingAid` router with `startSession({loadId, dockId})`, `streamCameras({sessionId})` (WS), `getSensorReadings({sessionId})` → `{driverSideIn, centerRearIn, blindSideIn, alignmentDeg}`, `pauseSession`, `resetAttempt`, `completeSession({sessionId, outcome})`.
2. **Load lifecycle has no `BACKING_IN` sub-state.** Extend `loadLifecycle.getStateMachine` (`loadLifecycle.ts:2127`) with `AT_DOCK → BACKING_IN → BRAKES_SET → UNLOADING`.
3. **ESANG has no `coachBacking` topic.** Add `esangAI.coachBacking({sessionId, sensorSnapshot})` that returns coaching text. No mobile-facing esang coach endpoint exists today.
4. **Dock cameras not modeled.** Drizzle schema has no `dock_cameras` table; need one keyed to `facilities`/`yardLocations`.

### User-journey entry points
- Entry 1: from `022 Dock Assigned` via `Start backing` CTA once trailer reverse gear detected; required state: load in `AT_DOCK`, dock assigned via `yardManagement.assignTrailer`, driver HOS = on_duty (`hos.getCurrentStatus`).
- Entry 2: auto-push from geofence `approach` event on facility dock polygon (`geofencing.recordEvent` at `geofencing.ts:194`).
- Entry 3: dispatch deep-link "Help this driver back in" from command center (`dispatch.sendDriverMessage` at `dispatch.ts:1433`).

---

## 024 Unloading.png

**Swift port:** NOT PORTED
**Purpose (1-line):** Live pallet-by-pallet unloading dashboard with detention free-time counter and facility contact.

### UI elements to backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Chip "UNLOADING · LIVE" | Load sub-state | `loadLifecycle.transitionState` (`:3021`) | needs UNLOADING state |
| Title "Door 47 · 14 of 26 pallets off" | Pallet progress | GAP | `loads.getUnloadProgress` |
| Trailer/Load subtitle | IDs | `loads.ts:1012 getById` | |
| Pallet map grid (refreshed 16:49) | Real-time pallet positions | GAP | `warehouse.getPalletMap` |
| Toggle "on trailer / unloaded" | Filter map view | client-side | |
| "14 / 26 pallets · Est 0:42 remaining" | ETA calc | GAP | compute from rate |
| Progress bar STARTED 16:49 RATE 15 PALLETS/HR | Unload metrics | GAP | `loads.getUnloadMetrics` |
| Detention card "0:42 · FREE" counting up | Free-time timer | `loadLifecycle.getActiveTimers` (`:3175`), `detentionAccessorials.getActiveDetentions` (`:256`) | partial — timer exists, free-time threshold missing |
| Detention rules text ("$60/hr auto-bills") | Rate card | `detentionAccessorials.getAccessorialCatalog` (`:660`) | |
| Consignee card "MidAtlantic Distributing · grocery receiving · DOCK 47" | Receiver info | `customers.ts`, `facilities.ts` | exists |
| Phone link | click-to-call | handled by OS | |
| ESANG note banner | AI dispatch tip | GAP | no mobile ESANG channel |
| "Chat" button | Open shipper chat | `messaging.sendMessage` (`messaging.ts:215`), `messaging.getConversations` (`:137`) | covered |
| "View BOL" primary CTA | Fetch BOL | `bol.generateBOLFromLoad` (`bol.ts:1067`), `documents.ts getDocuments` | covered |
| Tab bar | Nav | n/a | |

### Backend GAPS (numbered)
1. **No unload-progress telemetry.** Add `yardManagement.getUnloadProgress({loadId})` → `{palletsOff, palletsTotal, rate, etaRemaining}` and `yardManagement.reportPalletRemoved({loadId, palletId})`.
2. **Pallet map table missing.** Drizzle schema has no `pallets` table; add `pallets(id, loadId, position, status, removedAt)`.
3. **Free-time vs billed-time threshold not expressed in detention router.** `detentionAccessorials.calculateDetention` (`:355`) exists but needs `getFreeTimeRemaining({loadId})`.
4. **No door-cam/real-time unloading camera feed.** Same `dock_cameras` gap as 023.

### User-journey entry points
- Entry 1: from `023 Backing In` via `Set brakes` CTA; required state: load in `AT_DOCK → UNLOADING`, geofence `enter` on dock polygon.
- Entry 2: from push notification "Unloading started" after shipper scans arrival (`appointments.startLoading` (`appointments.ts:342`) equivalent needed for unload).
- Entry 3: deep-link from command center exception "Unload delayed".

---

## 025 Paperwork.png

**Swift port:** NOT PORTED
**Purpose (1-line):** Post-unload BOL signed summary with next-pickup brief and "Mark delivered" CTA.

### UI elements to backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Chips "LOAD CLOSED · SIGNED" | Lifecycle status | `loadLifecycle.getStateMachine` | |
| Title "26 of 26 delivered · door 47" | Final count | `pod.getPODForLoad` (`pod.ts:49`) | |
| BOL panel (number, shipper, consignee, pieces, signed by) | BOL data | `bol.ts:374 generate`, `bol.ts:305 list`, `pod.getPODForLoad` | good |
| "Signed by Angela Park" with signature image | Stored signature | `signatures.ts:20 save`, `:143 getHistory` | covered |
| OS&D line "No over / short / damage" | Exception flags | GAP | `pod.getExceptionReport` |
| Timeline row START 16:05 / END 17:32 / DOOR TIME 1h 27m | Dwell analytics | `loadLifecycle.getActiveTimers`, `detentionAccessorials.calculateDetention` | partial |
| Detention KPI "$0.00 · 1h 27m inside 2h free window" | Detention status | `detentionAccessorials.getActiveDetentions` | covered |
| Next pickup brief banner | Upcoming load teaser | `loads.getTrackedLoads` (`loads.ts:689`), `drivers.getPendingLoads` (`drivers.ts:1141`) | covered |
| "View BOL" | Open BOL doc | `bol.generateBOLFromLoad` | covered |
| "Mark delivered" primary CTA | Transition to DELIVERED | `loads.updateLoadStatus` (`loads.ts:2774`), `loadLifecycle.transitionState` (`:3021`) | covered |
| Tab bar | Nav | n/a | |

### Backend GAPS (numbered)
1. **No dedicated exception/OS&D endpoint.** `pod.submitPOD` accepts freeform but no typed OS&D. Add `pod.submitException({loadId, over, short, damaged, notes, photos})`.
2. **Signature verification chain.** `signatures.verify` (`:73`) exists but audit lineage linking signer → load → POD is implicit. Add `signatures.getForLoad({loadId})` returning verified chain.
3. **"Door time" analytic not exposed.** Add `loadLifecycle.getDwellSummary({loadId})` wrapping start/end geofence events.

### User-journey entry points
- Entry 1: from `024 Unloading` when pallet count = total and consignee signs; required state: `signatures.save` succeeded, POD submitted.
- Entry 2: from push "BOL is signed" when shipper portal closes the load.
- Entry 3: Trips tab → past load → Paperwork (read-only).

---

## 026 Off Duty.png

**Swift port:** NOT PORTED (Swift `019_HosDutyStatus.swift` exists for duty status but not this screen)
**Purpose (1-line):** Post-delivery off-duty/reset card showing next brief countdown, HOS clocks, daily banker.

### UI elements to backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Chip "OFF DUTY · HOME" / "SLEEPER BERTH" | Duty status | `hos.getCurrentStatus` (`hos.ts:50`), `drivers.getMyHOS` (`drivers.ts:1259`), `eld.getDriverStatus` (`eld.ts:232`) | covered |
| Title "Shift closed · evening off" | Shift summary | `hos.getDailyLog` (`hos.ts:114`) | |
| Yard parking line "TR-2118 parked" | Trailer last location | `location.getDriverLocation`, `yardManagement.updateTrailerPosition` (`:394`) | covered |
| Big countdown "14:28 h:m" to next brief | Countdown clock | GAP | `drivers.getNextLoadBriefUnlock` |
| "PICKUP BRIEF 08:00 TOMORROW" pill | Brief unlock time | GAP | same |
| Location row "Winchester, VA" | City | `location.getDriverLocation` | covered |
| HOS rings (Drive 6:00/11, Window 5:00/14, Cycle 30:00/70) | HOS clocks | `hos.getStatus` (`hos.ts:32`), `drivers.getHOSAvailability` (`drivers.ts:1254`) | covered |
| Today banker card "$327.68 · 512 mi · 0.64/mi" | Daily earnings | `earnings.getEarnings` (`earnings.ts:95`), `earnings.getSummary` (`:24`) | covered |
| Detention share line | Accessorial share | `detentionAccessorials.getActiveDetentions` | covered |
| "View pay slip" button | Open pay statement | `earnings.getPayStatement` (`:224`), `earnings.getWeeklySummary` (`:136`) | covered |
| "Good night" / "Dim & sleep" primary CTA | Enter sleeper berth | `hos.changeStatus` (`hos.ts:93`), `drivers.stopDriving` (`drivers.ts:1272`) | covered |
| Tab bar | Nav | n/a | |

### Backend GAPS (numbered)
1. **No "next load brief unlock" endpoint.** Add `drivers.getNextLoadBriefUnlock()` → `{unlocksAt, loadId}` backed by assignment table.
2. **No "dim & sleep" UX hook.** Optional — client-only unless ELD needs explicit `SLEEPER` transition; `hos.changeStatus` covers it.
3. **Daily banker in earnings router lacks detention-share breakout.** Extend `earnings.getEarnings` output schema with `accessorialShare` field.

### User-journey entry points
- Entry 1: from `025 Paperwork` via `Mark delivered` after POD; required state: load status = DELIVERED, HOS transitioned to OFF_DUTY.
- Entry 2: from `019 HOS Duty Status` when driver manually sets OFF_DUTY.
- Entry 3: auto-pushed when ELD stream reports 30-min stop in home/yard geofence.

---

## 027 Next Load Brief.png

**Swift port:** NOT PORTED
**Purpose (1-line):** Pre-accept load preview card with route, commodity, HOS fit, pay estimate, auto-accept countdown.

### UI elements to backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Chip "BRIEF READY · NEW LOAD" | Assignment status | `drivers.getPendingLoads` (`drivers.ts:1141`), `drivers.getCurrentAssignment` (`drivers.ts:751`) | covered |
| Header "Malvern, PA → Richmond, VA" | Lane | `loads.getById` (`loads.ts:1012`) | covered |
| Subtitle load ID + "Routed via EusoMap · Auto-accept in 4:58" | Load id, timer | `loads.getById`; timer GAP | `drivers.getAutoAcceptTimer` missing |
| Origin card with time window | Pickup window | `loads.getById` | |
| Miles card "256" | Distance | `routing.calculateRoute` (`routing.ts:70`) | covered |
| Destination card with delivery time | Delivery window | `loads.getById` | |
| Product chip "UN1203 Gasoline · CL 3 · ERG 128" | Hazmat metadata | `erg.searchByUN` (`erg.ts:65`), `hazmat.determinePlacards` (`hazmat.ts:121`) | covered |
| Product details "8600 gal pallets · MC-306 placard · flammable 3" | Commodity specs | `spectraMatch.getCrudeSpecs` (`spectraMatch.ts:298`), `hazmat.validateLoad` (`hazmat.ts:171`) | covered |
| HOS fit card "Comfortable · 3h 45m headroom · 5h 10m of 11h…" | HOS check | `navigation.getHOSRoutePlan` (`navigation.ts:201`), `drivers.getHOSAvailability` | covered |
| Pay estimate card "$224.00 · 256mi · 0.60 + 58.56 FSC · EusoWallet" | Rate preview | `loads.calculateRate` (`loads.ts:1676`), `wallet.getSummary` (`wallet.ts:288`) | covered |
| ESANG brief text (tunnel, hazmat path, ERG 128) | AI route note | `navigation.ts` + `hazmat.getHazmatRoute` (`hazmat.ts:768`), `hazmat.getRouteRestrictions` (`hazmat.ts:401`) | covered |
| "Decline" button | Reject load | `drivers.declineLoad` (`drivers.ts:1130`) | covered |
| "Accept · drive" primary CTA | Accept load | `drivers.acceptLoad` (`drivers.ts:1122`) | covered |

### Backend GAPS (numbered)
1. **Auto-accept countdown not a real endpoint.** Add `loads.getAutoAcceptTimer({loadId})` → `{expiresAt}` or field on `loads` table.
2. **"Spectra-Match expects grounding + 2-valve check" copy** comes from product profile but there's no composed "load brief narrative". Add `loads.getBriefNarrative({loadId})` consolidating hazmat + spectra + route notes.
3. **Pay estimate breakdown** (`rate + FSC`) — `loads.calculateRate` returns scalar; extend with `{linehaul, fsc, accessorialExpected}`.

### User-journey entry points
- Entry 1: from `026 Off Duty` when `nextLoadBriefUnlock` passes; required state: `drivers.getPendingLoads` non-empty.
- Entry 2: from push "Load offer" via `push.ts` when dispatch runs `dispatch.assignDriver` (`dispatch.ts:987`) or `loads.assign` (`loads.ts:1413`).
- Entry 3: Trips tab → Pending → tap load.

---

## 028 Load Locked Prehaul.png

**Swift port:** NOT PORTED
**Purpose (1-line):** Hazmat pre-haul checklist (8 items) that must all clear before driver can roll; acknowledgements, photo capture, sign-off.

### UI elements to backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Chip "LOCKED · EUSO-…" | Load state LOCKED | `loadLifecycle.transitionState` | `LOCKED` state missing in sample enum |
| Title "Hazmat pre-haul · 7 checks · 2 open · Roll by 08:40 for 07:30 rack window" | Countdown + counter | GAP | `loads.getPrehaulStatus` |
| Load info panel (EUSO id, MC-306, UN1203, ERG 128) | Metadata | `loads.getById`, `erg.getGuidePage` (`erg.ts:116`) | covered |
| Rolloff time pill "08:40" | Target departure | GAP | computed |
| Check row "Shipping papers in cab ready" [VIEW] | Doc check | `documents.ts`, `driverMobile.getDriverDocuments` (`driverMobile.ts:1280`) | partial |
| Check row "ERG Guide 128 acknowledged" [REOPEN] | Ack log | `erg.logLookup` (`erg.ts:155`) | covered |
| Check row "Placards verified" [CAPTURE] | Photo capture | GAP | `inspections.submitDVIR` (`inspections.ts:143`) or new `loads.attachPrehaulPhoto` |
| Check row "MC-306 current inspection" [PINNED] | Cert check | `certifications.getCertifications`, `drivers.getCertifications` (`drivers.ts:1857`) | partial |
| Check row "Endorsements green" [4/4] | Driver endorsements | `hazmat.verifyDriverEndorsement` (`hazmat.ts:260`), `cdlVerification.ts` | covered |
| Check row "EusoShield binder active · $2M…" [BINDER] | Insurance | `insurance.ts` | likely covered |
| Check row "Driver acknowledgement · I confirm…" [SIGN] | E-sign | `signatures.save` (`signatures.ts:20`) | covered |
| "Remind in 5" | Snooze | GAP | `loads.snoozePrehaul` |
| "Roll to Buckeye" primary CTA (disabled until 0 open) | Transition to EN_ROUTE | `loadLifecycle.transitionState`, `drivers.updateLoadStatus` (`drivers.ts:857`) | covered |

### Backend GAPS (numbered)
1. **Pre-haul checklist table missing.** Propose `loads.getPrehaulChecklist({loadId})`, `loads.completePrehaulItem({loadId, itemKey, payload})`, `loads.attachPrehaulPhoto({loadId, itemKey, url})`. Back with `load_prehaul_items` table.
2. **`LOCKED` state in lifecycle SM.** Extend `loadLifecycle.getStateMachine` with `ASSIGNED → LOCKED → EN_ROUTE_PICKUP`.
3. **Snooze endpoint.** `loads.snoozePrehaul({loadId, minutes})` logging into audit.
4. **MC-306/DOT placard inspection linkage.** `inspections` router has generic DVIR but no tanker-cert validity; add `inspections.getTankerCertStatus({vehicleId})`.

### User-journey entry points
- Entry 1: from `027 Next Load Brief` after `drivers.acceptLoad`; required state: load `LOCKED`, hazmat = true.
- Entry 2: from push "Prehaul items still open" if `rolloff − 30m` and items incomplete.
- Entry 3: re-entry from nav when driver tries to `Start nav` with open checks.

---

## 029 Pickup Arrival.png

**Swift port:** NOT PORTED
**Purpose (1-line):** Bay-side bond & vapor-recovery step wizard (2/4) with ESANG leading, Spectra-Match purity handshake.

### UI elements to backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Chip "RIG PARKED · EUSO-…" | Load state | `loadLifecycle.transitionState`, `drivers.updateLoadStatus` | covered |
| Title "Pickup · ESANG leading · Step 2 of 4 · bond + vapor recovery · ~6 min to first crack" | Wizard state | GAP | `loads.getPickupWizardState` |
| Terminal layout panel (EusoMap · Bay 12 · Gasoline rack · top-load) | Terminal map tile | GAP | `terminals.ts` exists but no detailed bay map |
| ESANG step-lead card with 5 checklist items (engine off, vapor boot, bond cable, gauge stick temp, purity gate) | AI-guided steps | GAP | composed of many pieces |
| Bond-cable step badge "READING" | Real-time sensor | GAP | `tankMonitor.getTankReadings` (`tankMonitor.ts:25`) is close but terminal-side |
| "Boot looks tight… once the bond clamps…" copy | ESANG narration | GAP | `esangAI.guidePickup` |
| Spectra-Match card "last sample RVP 8.9 psi · target 8.5-9.5" [QUEUED] | Purity reading | `spectraMatch.identify` (`spectraMatch.ts:36`), `spectraMatch.getCrudeSpecs` (`:298`), `spectraMatch.saveToRunTicket` (`:332`) | covered |
| EusoShield window "09:00 – 17:38" | Policy window | `insurance.ts` | likely covered |
| "Notify shack" button | Alert shipper dispatcher | `messaging.sendMessage`, `messaging.sendLobbyMessage` (`messaging.ts:570`) | covered |
| "Confirm bonded" primary CTA | Advance wizard | GAP | `loads.advancePickupStep` |

### Backend GAPS (numbered)
1. **Pickup wizard state machine.** Add `loads.getPickupWizardState`, `loads.advancePickupStep({loadId, stepId, payload})`, back with `load_pickup_steps` table.
2. **Terminal bay/rack model.** Extend `terminals.ts` (or add `racks` table) with `rack`, `bayNumber`, `loadType` (top/bottom), `productLine`.
3. **Live bond-cable / vapor-recovery telemetry.** New `terminalTelemetry.getBayReading({bayId, sensor})` — currently only `tankMonitor` exists.
4. **ESANG pickup coach.** `esangAI.coachPickup({loadId, currentStep})`.

### User-journey entry points
- Entry 1: from `028 Load Locked Prehaul` → "Roll" → geofence enter terminal → auto-progress; required state: `EN_ROUTE_PICKUP`, geofence event at rack polygon.
- Entry 2: from ESANG push "You're parked at Bay 12 — start step 1".
- Entry 3: re-entry from pause/resume via `drivers.getCurrentAssignment`.

---

## 030 Loading in Progress.png

**Swift port:** NOT PORTED
**Purpose (1-line):** Live loading dashboard — percent fill, flow rate, ETA full, vapor return PSIG, Spectra-Match live sample band.

### UI elements to backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Chip "LOADING ACTIVE · EUSO-…" | Lifecycle | `loadLifecycle.transitionState` | covered |
| Title "Loading gasoline · Bay 12 · Sample 1/4 in range · vapor recovery flowing · bond holding" | Composite live status | GAP | `loads.getLoadingStatus` |
| Progress card "22% · 1,892 of 8,600 GAL · STARTED 09:36 · ETA FULL 09:45" | Fill telemetry | GAP | `loads.getLoadingTelemetry` — nothing exists for tanker fill |
| Flow rate KPI "950 gpm · +6% vs Buckeye baseline" | Rate telemetry | GAP | same |
| ETA full KPI "7:02 min" | ETA | GAP | derived |
| Vapor return KPI "0.6 psig" | Vapor pressure | GAP | `tankMonitor` partial |
| Product temp KPI "19.4°C" | Tank temp | `tankMonitor.getTankReadings` | possibly covered |
| Spectra-Match live card "sample 1 of 4 · last RVP 8.92 · target 8.5-9.5 · IN RANGE" with sparkline | Live purity | `spectraMatch.identify`, `spectraMatch.saveToRunTicket` | partial — no live streaming |
| ESANG monitoring card "flow steady, no vapor leak at the boot · CATALYST DISPATCH ON THE LOOP · HAULPAY METERING LIVE" | AI monitor stream | GAP | `esangAI.monitorLoading` |
| "Pause" button | Pause load (e-stop soft) | GAP | `loads.pauseLoading` |
| "E-STOP" button (red) | Emergency stop | `emergencyResponse.ts` / `emergencyProtocols.ts` exists | maybe — no tanker-specific E-stop |
| Tab bar | Nav | n/a | |

### Backend GAPS (numbered)
1. **No loading telemetry router.** Add `loadingOps` router: `getLoadingTelemetry({loadId})` → fill%, gallons, flowRate, etaFull, vaporPSIG, productTempC; `pauseLoading({loadId})`; `resumeLoading({loadId})`; `eStopLoading({loadId, reason})`.
2. **Spectra-Match streaming.** `spectraMatch` router returns point reads; add `spectraMatch.streamSamples({loadId})` (tRPC subscription) or polling `getSampleHistory({loadId})`.
3. **ESANG loading monitor.** `esangAI.monitorLoading` not implemented; today `esangAI.ts` is chat-only.
4. **Terminal meter integration.** Drizzle schema has no `meter_readings` table keyed to `loadId`; add one.

### User-journey entry points
- Entry 1: from `029 Pickup Arrival` after "Confirm bonded" at step 4; required state: all handshake steps green, meter start received.
- Entry 2: from push "Load started" triggered by terminal meter.
- Entry 3: from TRIPS → current load → Now loading.

---

## 031 Spectra-Match Verdict.png

**Swift port:** NOT PORTED
**Purpose (1-line):** Final-sample purity verdict — PASS/FAIL with sparkline, comparison to last 3 lanes, "Lock fill, detach" CTA.

### UI elements to backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Chip "SPECTRA-MATCH · VERDICT IN" | Verdict status | `spectraMatch.identify` (`spectraMatch.ts:36`), `spectraMatch.identifyWithAI` (`:188`) | covered for verdict, not composed screen |
| Title "Gasoline load signed · RVP 8.92 · final sample 4/4 · pump stopped at 8,600 gal" | Summary | `spectraMatch.saveToRunTicket` (`:332`), `runTickets.complete` (`runTickets.ts:215`) | covered |
| Verdict card "PASS · 8.92 psi RVP vs target 8.5-9.5" with chart | Sample result | `spectraMatch.identify` | covered |
| Statistics row "σ 0.013 psi · max-min 0.03 psi" over 4 samples | Aggregated stats | GAP | `spectraMatch.getSampleStats({loadId})` |
| Lane comparison "THIS LOAD 8.92 / LANE-1 8.95 / LANE-2 8.88 / LANE-3 8.91" | Historical lane vals | `spectraMatch.getDestinationIntelligence` (`:694`), `:763 quickDestinationMatch` | partial |
| Lineage footer "Load … signed at RVP 8.92 · SPECTRA-MATCH · EUSOSHIELD · ESANG AI LINEAGE" | Audit chain | `blockchainAudit.ts`, `auditLogs.ts` | covered |
| "Hold for retest" button | Retest command | GAP | `spectraMatch.flagRetest({loadId})` |
| "Lock fill, detach" primary CTA | Seal + transition | `loadLifecycle.transitionState` | partial — need `LOCK_FILL` event |

### Backend GAPS (numbered)
1. **Aggregate stats + lane benchmark missing.** Add `spectraMatch.getSampleStats({loadId})` returning σ, max-min, trend; `spectraMatch.getLaneBenchmarks({loadId, lanesBack})`.
2. **Retest workflow.** `spectraMatch.flagRetest({loadId, reason})` → creates QA case, stays LOADING until resolved.
3. **Verdict immutability / lineage.** Use `blockchainAudit.ts` ledger entries; ensure `spectraMatch.saveToRunTicket` writes lineage row.
4. **Lock-fill state transition.** Add `LOAD_LOCKED_FILLED` to state machine.

### User-journey entry points
- Entry 1: from `030 Loading in Progress` when meter reports 100% + sample 4/4 captured; required state: LOADING, all samples IN_RANGE.
- Entry 2: from push "Sample verdict ready".
- Entry 3: from Trips → current load → Verdict tab (historical view after completion).

---

## 032 Detach Sequence.png

**Swift port:** NOT PORTED
**Purpose (1-line):** Hazmat detach wizard (6 steps) — close valves, purge, disconnect, sign — with ESANG step-lead and gauge verification.

### UI elements to backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Chips "FILL LOCKED · DETACH SEQUENCE" | Substate | `loadLifecycle.transitionState` | GAP — need DETACHING |
| Title "Gasoline detach in progress · Step 3 of 6 · -3 min remaining · rig still bonded" | Wizard state | GAP | `loads.getDetachState` |
| ESANG step-lead card "Gauge stick verify" with physical witness copy | AI coach | GAP | `esangAI.coachDetach` |
| Tank vapor KPI "0.3 psig" | Vapor reading | `tankMonitor.getTankReadings` | partial |
| Tank temp KPI "19.5°C" | Temp | same | partial |
| 6-step list (close pump, disengage vapor boot, gauge stick verify NOW, disconnect arm+cap, remove bond, sign BOL) with timestamps | Step list | GAP | `loads.getDetachChecklist`, `loads.completeDetachStep` |
| BOL lineage footer "BOL EUSO-…· PRE-FILLED · AWAITS DRIVER SIG" + "Spectra cert · RVP 8.92 · SIGNED BY ESANG AI LINEAGE" | Chain | `bol.generate` (`bol.ts:374`), `blockchainAudit.ts` | covered |
| "Pause" button | Pause | GAP | `loads.pauseDetach` |
| "Gauge OK → disconnect arm" primary CTA | Advance step | GAP | `loads.completeDetachStep` |

### Backend GAPS (numbered)
1. **Detach wizard/checklist missing.** New procedures under `loads` or new `tankerOps` router: `getDetachChecklist({loadId})`, `startDetachStep`, `completeDetachStep({loadId, stepId, readings, photos})`, `pauseDetach`, `abortDetach`.
2. **DETACHING state.** Extend lifecycle SM with `LOAD_LOCKED_FILLED → DETACHING → RELEASED`.
3. **ESANG detach coach.** `esangAI.coachDetach`.
4. **Gauge-stick reading ingestion.** New `tankerOps.submitGaugeReading({loadId, tankVaporPsig, tempC, stickHeightIn})` — no current endpoint.

### User-journey entry points
- Entry 1: from `031 Spectra-Match Verdict` via "Lock fill, detach"; required state: `LOAD_LOCKED_FILLED`, bond still active.
- Entry 2: re-entry if driver backs out mid-sequence (check `loads.getDetachState`).

---

## 033 BOL Sign-off.png

**Swift port:** NOT PORTED
**Purpose (1-line):** Final BOL + Spectra cert signing card — 30-second sign window, driver e-signature, Reject / Sign-and-release.

### UI elements to backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Chip "STEP 6 / 6 · SIGN TO RELEASE" | Wizard final | `loadLifecycle.transitionState` | |
| Title "Sign BOL + Spectra cert · Last step before you roll · review then sign · -30 sec" | Countdown | GAP | `loads.getSignWindow` |
| BOL panel (BOL number, MC-306, DOT 406, shipper, consignee, UN1203 Class 3, net 8600 gal, temp 19.4°C captured) | BOL doc | `bol.generate` (`bol.ts:374`), `bol.generateBOLFromLoad` (`:1067`) | covered |
| Shipping description + placard "FLAMMABLE 3" + emergency contact | Hazmat papers | `hazmat.determinePlacards`, `hazmat.validateLoad` | covered |
| Spectra-Match cert row "RVP 8.92 psi · hash SPM-…· ESANG AI LINEAGE" [ATTACHED] | Cert attachment | `spectraMatch.saveToRunTicket`, `blockchainAudit.ts` | covered |
| Insurance banner "EusoShield in-transit binder $2M activates · consignee gets ETA" | Policy | `insurance.ts` | covered |
| Certification text paragraph | Legal statement | static copy | |
| Signature panel "Michael Eusorone · CDL MX-A · endorsements N+H+T+X · TWIC valid" [STORED] | Driver credentials snapshot | `drivers.getById`, `drivers.getCertifications` (`drivers.ts:1857`), `cdlVerification.ts` | covered |
| "Reject" button | Reject load (rare) | `loads.cancel` (`loads.ts:1245`) + `loads.dispute` (`loads.ts:1924`) | covered |
| "Sign and release rig" primary CTA | E-sign + release | `signatures.save` (`signatures.ts:20`), `bol.generate`, `loadLifecycle.transitionState` | covered |

### Backend GAPS (numbered)
1. **Sign countdown window.** Add `loads.getSignWindow({loadId})` → `{expiresAt}` to enforce 30s reminder; else auto-escalate to dispatch.
2. **Reject-at-BOL edge case.** `loads.cancel` is too broad — add `loads.rejectAtBOL({loadId, reason, evidenceUrl})` that notifies shipper + keeps rig bonded.
3. **Spectra cert hash linkage.** Ensure `spectraMatch.saveToRunTicket` writes cert hash + BOL id to immutable ledger — check `blockchainAudit.ts`.

### User-journey entry points
- Entry 1: from `032 Detach Sequence` step 6; required state: DETACHING step 6 ready, BOL pre-filled, Spectra cert attached.
- Entry 2: re-entry if driver aborted sign (resume via `loads.getCurrentAssignment`).

---

## 034 Departing Pickup.png

**Swift port:** NOT PORTED
**Purpose (1-line):** Released-and-rolling handoff — route preview, load facts, first-leg instructions, "Start nav".

### UI elements to backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Chips "RELEASED · EN ROUTE TO RECEIVER" | State EN_ROUTE | `loadLifecycle.transitionState`, `drivers.updateLoadStatus` | covered |
| Title "Rolling to Wawa Distribution · Lancaster PA · 95 MI · ETA 10:42 · in-transit binder live" | Load header | `loads.getById`, `routing.getETA` (`routing.ts:123`) | covered |
| Route preview mini-map | Route polyline | `routing.getRoute` (`routing.ts:81`), `location.getActiveRoute` (`location.ts:834`) | covered |
| Route KPI cards: DISTANCE 32 mi, ETA 10:42, VIA US-30 W | Route stats | `routing.calculateRoute` | covered |
| Load fact "LOADED · NET AT FILL · 8,600 gal" | Fill data | `runTickets.ts`, `bol.generateBOLFromLoad` | covered |
| Load fact "SPECTRA-MATCH · FINAL SAMPLE · RVP 8.92 psi" | Cert | `spectraMatch.identify` | covered |
| Load fact "BOL · SIGNED 09:54 · EUSO-…1234" | BOL | `bol.generate` | covered |
| EusoShield chip "$2M active LIVE" | Insurance | `insurance.ts` | covered |
| First-leg instruction card "Left out of Bay 12 onto Pottstown Pike, then continue to US-30 W" | Turn-by-turn first step | `navigation.calculateRoute` (`navigation.ts:70`), `routing.getRoute` | covered |
| Telemetry row HOS 9h 15m · FUEL 92% · BAY LIGHT Green | Composite | `hos.getStatus`, `fuel.ts` / `fuelManagement.ts`, GAP for bay light | bay-light = terminal signal GAP |
| "Trip log" button | Open activity log | `activity.ts`, `drivers.getRecentEvents` (`drivers.ts:1470`) | covered |
| "Start nav" primary CTA | Begin navigation | `routing.activateRoute` (`routing.ts:237`), `navigation.calculateRoute` | covered |

### Backend GAPS (numbered)
1. **Terminal "bay light" signal.** Add `terminals.getBayLight({bayId})` or broadcast via `geofencing` exit event.
2. **Composite "departing summary".** Convenience `loads.getDepartureBrief({loadId})` that composes BOL, cert, route, HOS.
3. **Fuel-level read not linked to driver HUD.** `fuelManagement` exists but no `getCurrentFuelPct({vehicleId})` mobile wrapper.

### User-journey entry points
- Entry 1: from `033 BOL Sign-off` via "Sign and release rig"; required state: BOL signed, rig detached, geofence exit primed.
- Entry 2: from push "You're released — begin route".

---

## 035 En Route Drive.png

**Swift port:** NOT PORTED
**Purpose (1-line):** Full-screen turn-by-turn with hazmat-aware rerouting, speed/limit, HOS drive-left, "Exit".

### UI elements to backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Map background with route polyline | Route | `routing.getActiveRoute`-style + `location.getActiveRoute` (`location.ts:834`) | covered |
| Next-turn banner "0.6 mi Exit 286 · Old Rt 30 → Gap PA · THEN continue US-30 W" | Next maneuver | `routing.getRoute` (`routing.ts:81`) | partial — no maneuver-level endpoint |
| "Then →" card | 2nd upcoming turn | GAP | needs maneuvers list |
| Hazmat advisory banner "HAZMAT · LINCOLN HWY VIADUCT SKIPPED" | Route restriction applied | `hazmat.getRouteRestrictions` (`hazmat.ts:401`), `hazmat.getHazmatRoute` (`hazmat.ts:768`) | covered |
| FAB: mute audio | Nav controls | client-only | |
| FAB: recenter | same | client-only | |
| FAB: warnings (triangle badge) | Alerts list | `alerts.ts` + `hazmat.checkProximity` (`hazmat.ts:1272`) | covered |
| Speed limit shield "55" | Road attribute | `navigation.ts` needs `getSpeedLimit(lat,lng)` or part of route response | GAP |
| Current speed "53 mph" | GPS | `location.locationBatch` (`location.ts:129`), `eld.getDriverStatus` | covered |
| Distance/ETA row "28m · 16 mi · arrive 10:42" | ETA | `routing.getETA`, `routing.updateETA` (`routing.ts:144`) | covered |
| "Exit" red button | End nav / park | `routing.completeRoute` (`routing.ts:252`), `drivers.stopDriving` (`drivers.ts:1272`) | covered |
| HOS drive-left "8h 48m" | HOS clock | `hos.getStatus`, `drivers.getMyHOS` | covered |
| EusoShield "LIVE · $2M Gas" | Binder | `insurance.ts` | covered |
| Tab bar | Nav | n/a | |

### Backend GAPS (numbered)
1. **Maneuver-level route response.** `routing.getRoute` returns waypoints; extend with `maneuvers: [{distanceFt, instruction, exit, next}]`.
2. **Speed-limit service.** No `roads.getSpeedLimit({lat,lng})` endpoint. Needed for shield UI.
3. **Route deviation + rerouting hooks.** `location.checkRouteDeviation` (`location.ts:868`) exists but does not auto-rebuild; add `routing.rerouteIfDeviated({loadId, threshold})`.
4. **Hazmat viaduct/tunnel skip log.** Ensure `hazmat.getRouteRestrictions` result is surfaced via `routing.getRoute` payload as `skipped: ['Lincoln Hwy viaduct']`.

### User-journey entry points
- Entry 1: from `034 Departing Pickup` via "Start nav"; required state: active route (`routing.activateRoute`), load status EN_ROUTE, geofence exit of origin recorded.
- Entry 2: re-entry from background notification "Resume nav" (push via `push.ts`).
- Entry 3: auto-re-enter on route-deviation alert from `location.checkRouteDeviation`.

---

## Summary

**Scope stats**
- Screens audited: **13** (all driver 023-035)
- Swift ports: **0 / 13** (bucket is entirely unported; Driver Swift views end at `022_DockAssigned.swift`)
- Total distinct UI elements enumerated: **~175**
- Elements already backed by a cited existing procedure: **~95** (~54%)
- Elements flagged as GAP (needing new/extended procedure or field): **~80** (~46%)

**Top-3 urgent gaps (highest downstream unblock value)**

1. **Tanker live-ops telemetry + wizard routers are entirely missing.** Screens 029, 030, 031, 032, 033 all depend on a coherent "pickup wizard → loading telemetry → verdict → detach wizard" backend. Propose a single new `tankerOps` router with `getPickupWizardState / advancePickupStep`, `getLoadingTelemetry / pauseLoading / eStop`, `getDetachChecklist / completeDetachStep`, plus a `load_pickup_steps` + `load_detach_steps` + `meter_readings` trio in Drizzle schema. Today only `spectraMatch.ts`, `tankMonitor.ts` (terminal-side), and `runTickets.ts` exist.

2. **Dock-side backing-aid and unload-progress (023, 024) have no equivalent backend.** No dock-camera streaming, no ultrasonic sensor ingest, no pallet map/progress. Propose a `dockOps` router: `backingAid.*` (session/sensor/alignment) and `yardManagement.getUnloadProgress / reportPalletRemoved` + `pallets` table keyed to `loadId`.

3. **Lifecycle state machine is under-specified for tanker flow.** `loadLifecycle.ts` exposes generic `transitionState` but the enum has no `LOCKED`, `BACKING_IN`, `LOADING`, `LOAD_LOCKED_FILLED`, `DETACHING`, `UNLOADING` states that these screens visually rely on. Action: enumerate full tanker FSM and add those transitions so `transitionState` can be called from 023, 028, 030, 031, 032, 034.

**Cross-cutting themes**
- **ESANG mobile coaching channels are absent.** `esangAI.ts` is chat-oriented; every live screen (023, 029, 030, 032) wants a `coach*` subscription. Recommend a unified `esangAI.coach({sessionType, loadId})` subscription feed.
- **Countdown timers** (auto-accept, rolloff, sign-window, free-time) appear on 027, 028, 033, 024 but are not uniformly backed. Recommend a `timers` mini-router or a `timers` column group on `loads`.
- **Next-load brief unlock** (026 → 027 handoff) needs a first-class endpoint: `drivers.getNextLoadBriefUnlock()`.
- **Blockchain audit lineage** is invoked visually on 031/032/033; verify `blockchainAudit.ts` actually writes hashes keyed to `loadId` when Spectra, BOL, and signature events occur.
