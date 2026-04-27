# Wave-3 Audit — Agent 00 (Driver screens 010-022)

Backend root: `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/`
Swift root:    `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/EusoTrip/Views/Driver/`

---

## 010 Driver Home.png

**Swift port:** 010_DriverHome.swift
**Purpose (1-line):** Driver landing dashboard — shows current active load, HOS clocks, pre-trip status, tractor/trailer pairing and ESANG nudge.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Welcome header (name, role, CDL-A HAZMAT) | Driver profile fields | `drivers.ts` getById (via `auditedOperations`) + `users` table | profile via getUser |
| "CURRENT · ACTIVE LOAD" pill / load card | Active load w/ origin→dest, UN #, appt | `driverMobile.getDriverHomeDashboard` line 240 | aggregates home |
| "Continue pre-trip" CTA | Open DVIR inspection flow | `inspections.createDVIR` line 279; `inspectionForms.getTemplate` line 42 | navigates to 011 |
| "Review load brief" CTA | Load detail view | `loads.getById` line 1012 | deep-link to rate-con |
| DRIVE / ON-DUTY / CYCLE timers | HOS remaining clocks | `hos.getCurrentStatus` line 50; `driverMobile.getDriverHosStatus` line 1496 | |
| Pre-trip DVIR card (section progress) | Last DVIR state / % complete | `inspections.getRecent` line 250; `inspections.getOpenDefects` line 223 | |
| HOS / Duty Status tile | Drive-window remaining | `hos.getCurrentStatus` line 50 | tap→019 |
| Nav & Route tile | Active route summary (miles, hazmat) | `navigation.getRoute` line 81; `routes.getActiveRoute` line 834 | |
| Tractor 8142 card (VIN, coupling) | Assigned vehicle + health | `vehicles.get` line 57; `vehicles.getLocation` line 287 | |
| Trailer TK-2204 card (PSI, pressure) | Trailer telemetry (pressure) | GAP — no trailer PSI/coupling telemetry proc | tankMonitor.ts partial |
| Samsara IG-6L sync chip | ELD device sync status | `eld.getConnectionStatus` line 456; `eld.getDriverELDCompliance` line 1084 | |
| ESANG step-lead banner | AI nudge message | `esangAI.ts` (procedures at 288+) | voice coach |
| Bottom nav (Home/Trips/Wallet/Me + center beacon) | Tab switch / ESANG trigger | client-routing + `esangVoice.ts` | |

### Backend GAPS (numbered)
1. **Trailer live telemetry (PSI / coupling / hazmat-ready).** Add `trailerTelemetry.getSnapshot({ trailerId })` in a new `trailerTelemetry.ts` router returning `{ psi, tempF, couplingState, hazmatReady, lastReportedAt }` backed by `trailer_telemetry` time-series table.
2. **Consolidated driver-home aggregator convenience.** `driverMobile.getDriverHomeDashboard` exists but does not yet fan-in HOS + active DVIR + trailer + ESANG nudge in one payload — extend it (or add `driverMobile.getHomeBundle`) so the Swift view hits one endpoint.
3. **ESANG step-lead rendering.** No procedure returning the short "next-step" copy + waveform surface. Propose `esangAI.getNextStepNudge({ loadId, phase })` → `{ text, ssmlUrl, priority }`.

### User-journey entry points
- Entry 1: App launch / deep-link from push → lands here; required state: authenticated driver + optional active `loads.status='assigned'|'in_transit'`.
- Entry 2: After completing 012 DVIR Submitted via "Home" tab.
- Entry 3: Dispatcher assigns load (`dispatch.assignDriver` line 987) → push notification → opens home with new active-load card.

---

## 011 Pre-trip DVIR.png

**Swift port:** 011_PretripDVIR.swift
**Purpose (1-line):** 14-section pre-trip DVIR inspection screen, currently on Section 3 (Brakes) with a minor defect logged.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Header "Pre-trip DVIR / Inspector" | Form + driver identity | `inspectionForms.getTemplate` line 42 | |
| Progress pill "21%", "11m 03s elapsed" | Form progress, time spent | GAP — client-side timer not persisted | see GAP 1 |
| Section pager "SECTION 3 OF 14 · BRAKES" | Current checklist section | `inspectionForms.getTemplate` line 42 | sections from template |
| Item rows (Service/Parking/Air system, pass/pending) | Checklist item state | `inspections.submit` line 143 | writes item status |
| "DEFECT FLAGGED · MINOR" card | Defect entry, description | `inspections.createDVIR` line 279 (includes defects[]) | |
| Submit defect button | Log defect & notify | GAP — no `notifyDispatcherOnDefect` | see GAP 2 |
| "NOTIFY DISPATCHER · RESUME CHECKLIST" CTA | Toast dispatcher + continue | `messages.send` line 392 + `inspections.submit` | compose shim |
| Progress bar ($396.11 compliant) | Compliance/fine-avoidance heuristic | GAP — no compliance-dollar calc proc | synthetic |
| Bottom nav | Navigation | client-side | |

### Backend GAPS (numbered)
1. **DVIR autosave + elapsed-time tracking.** Add `inspections.autosave({ dvirId, sectionIndex, items[], elapsedSec })` so interrupted inspections resume; persist `dvir_drafts` table.
2. **`inspections.notifyDispatcherOnDefect({ dvirId, defectId, severity })`** — fires Twilio/push to assigned dispatcher, adds note to `loads.notes` via `loads.addNote` (line 1625).
3. **Compliance-dollar heuristic.** New `compliance.estimateDvirFineExposure({ defects[] })` returning CSA-style point value for the "$396.11 compliant" display.

### User-journey entry points
- Entry 1: from `010 Driver Home` via "Continue pre-trip" button; required state: assigned `vehicleId`, open or resumable DVIR.
- Entry 2: from push notification "Pre-trip overdue" (reminder job).

---

## 012 DVIR Submitted.png

**Swift port:** 012_DvirSubmitted.swift
**Purpose (1-line):** Confirmation — DVIR passed, receipt details, self-certified signature, CTA to start trip.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Success badge "DVIR submitted" | UI state only | n/a | |
| Receipt card (receipt #, inspector, unit, sections, defects, duration, logged-at, regulation) | Full DVIR record | `inspections.createDVIR` line 279 + `inspections.getDVIRHistory` line 317 | |
| "Signed · self-certified" row + tap-to-sign hash | Signature verify | `signatures.verify` line 73; `signatures.save` line 20 | |
| View PDF button | Render DVIR PDF | GAP — no `inspections.exportPdf` | see GAP 1 |
| "Start trip · En route" CTA | Transition load → `in_transit` | `loadLifecycle.transitionState` line 3021; `loadLifecycle.executeTransition` line 2247 | |
| Bottom nav | Nav | client | |

### Backend GAPS (numbered)
1. **PDF render of DVIR.** Add `inspections.exportPdf({ dvirId })` returning signed S3 URL; reuse existing PDF service used by `bol.generate` (line 374).
2. **HOS-aware start-trip gate.** `loadLifecycle.transitionState` does not currently reject if `hos.getCurrentStatus` shows 0 drive remaining — add pre-check in a wrapper `loadLifecycle.startDrivingFromDvir({ loadId, dvirId })`.

### User-journey entry points
- Entry 1: from `011 Pre-trip DVIR` after final section submit; required state: `dvir.status='submitted'` with no out-of-service defects.

---

## 013 En Route to Pickup.png

**Swift port:** 013_ActiveEnroute.swift
**Purpose (1-line):** Live map + next-turn card + pickup shipper summary while driving empty to Koch Fertilizer.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Next-turn card ("In 1.1 mi · Right · 5th Ave SW") | Turn-by-turn step | GAP — no streaming turn step proc | see GAP 1 |
| Progress bar "18 mi of 22 mi" + remaining time | Route progress | `navigation.getETA` line 123; `routes.getActiveRoute` line 834 | |
| Route polyline on map | Route geometry | `navigation.getRoute` line 81; `routes.calculateRoute` line 793 | |
| Hazmat route-locked chip | Hazmat route state | `hazmat.ts` (see routing hazmat tunnels) `routes.checkHazmatTunnels` line 905 | |
| UN1005 / NH3 · empty-in chip | Load hazmat + equipment state | `loads.getById` line 1012 + `hazmat.ts` | |
| No low-clearance chip | Clearance validation | GAP — no low-clearance proc (relies on LiDAR layer) | `eld.getLiDARAtPoint` partial |
| Pickup card (Koch Fertilizer) | Stop detail w/ address, appt | `loadStops` getForLoad; `loads.getById` line 1012 | |
| DISTANCE / DRIVE TIME / FUEL BURN tiles | Trip KPIs | `navigation.getETA` (distance/time); fuel → GAP | see GAP 2 |
| "Call shipper" button | Dial phone from contact | `messages.getUserPhone` line 674 | |
| "Continue route" CTA | Resume nav | `routes.activateRoute` line 237 | |
| Location ping (implicit) | Breadcrumb writes | `location.locationBatch` line 129; `location.getLoadBreadcrumbs` line 563 | |
| Geofence approach chip | Geofence enter/approach event | `location.geofenceEvent` line 182; `geofencing.checkLocation` line 146 | |

### Backend GAPS (numbered)
1. **Turn-by-turn step stream.** Add `navigation.getNextManeuver({ routeId, currentLat, currentLng })` → `{ instruction, distanceMeters, type }`, or a tRPC subscription.
2. **Per-load fuel-burn estimator.** New `fuel.estimateForRoute({ routeId, mpg, currentGallons })` in `fuel.ts` — uses equipment MPG + grade from LiDAR.
3. **Low-clearance validator.** `routes.checkLowClearance({ routeId, truckHeight })` returning blocker list.

### User-journey entry points
- Entry 1: from `012 DVIR Submitted` via "Start trip · En route"; required state: `load.status='in_transit_to_pickup'`, active route row.
- Entry 2: from home tab after app resume — `routes.getActiveRoute` line 834 decides active route.

---

## 014 Approaching Pickup.png

**Swift port:** 014_ApproachingPickup.swift
**Purpose (1-line):** Pre-gate checklist (bobtail receipt, hazmat placards, shipper call, PPE, ERG brief, grounding) 2 of 6 done.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Header "Approaching · Koch Fertilizer" | Stop context | `loads.getById` / `loadStops.getForLoad` | |
| Distance "1.8 mi TO GATE" | Live distance | `navigation.getETA` line 123 | |
| ESANG preps-checklist banner | AI preamble | `esangAI.ts` (line 288+); `esangVoice.ts` | |
| Progress "2 of 6 · 33%" | Checklist completion | `driverMobile.getDriverChecklist` line 1107; `driverMobile.submitChecklist` line 1127 | |
| Checklist item: Bobtail trailer clean-out receipt | Upload/attach receipt | GAP — no bobtail-receipt table | see GAP 1 |
| Checklist item: Hazmat placards swapped to NH3 | Placard verification | GAP — no placard verify proc | see GAP 2 |
| Checklist item: Call shipper 10 min out | Dial + log | `messages.getUserPhone` line 674 + `messages.sendMessage` line 279 | |
| Checklist item: PPE donned | Toggle | `driverMobile.submitChecklist` | |
| Checklist item: ERG 125 brief re-read | Read-confirm | `erg.ts` procedures | ERG lookup |
| Checklist item: Grounding cable ready | Toggle | `driverMobile.submitChecklist` | |
| "Dial Koch gate" CTA | Phone dial | client + `messages.getUserPhone` | |
| Bottom nav | Nav | client | |

### Backend GAPS (numbered)
1. **Bobtail / clean-out receipt capture.** New `driverMobile.uploadBobtailReceipt({ loadId, receiptUrl, emptyAtIso, prevCommodity })` writing to `bobtail_receipts`.
2. **Placard verification.** New `hazmat.verifyPlacards({ loadId, photoUrl, expectedUN })` — leverages `photoInspection.analyzePhoto` line 29 but returns pass/fail against expected UN.
3. **Structured pre-gate checklist template per hazmat class.** Extend `driverMobile.getDriverChecklist` to accept `{ stage: 'approach_pickup', hazmatClass }` and return template items with required evidence types.

### User-journey entry points
- Entry 1: Geofence approach event (`location.geofenceEvent` line 182, 0.5-2 mi ring) pushes from `013`. Required state: active approaching ring.
- Entry 2: Manual tap from 013's pickup card.

---

## 015 At Gate · Awaiting Dock.png

**Swift port:** 015_AtGateAwaitingDock.swift
**Purpose (1-line):** At gate, queue-position #4 of 6, dwell policy, ESANG idle-watch, log-dwell / open-bay-brief actions.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Header "At the gate / Bay 03 gate 2 / check-in complete" | Facility arrival state | `yardManagement.checkInTrailer` line 632; `loadLifecycle.checkIn` line 3466 | |
| Queue position "#4 of 6 trucks waiting" | Live queue | GAP — no driver-view queue proc (yardMgmt has some) | see GAP 1 |
| Est. wait & advance pace | Derived wait stats | GAP — queue dwell prediction | see GAP 1 |
| Load ID card (LD-2026..., UN1005 NH3 tanker) | Load header | `loads.getById` line 1012 | |
| Dwell policy card "2h free, detention after 2h" | Facility SOP | `detentionAccessorials.ts` + `facilities.ts` | |
| Dwell elapsed "+6 min" | Live dwell timer | `loadLifecycle.getActiveTimers` line 3175 | |
| Gate guard card (Odell K., Koch-012) | Guard contact | `facilities.ts` (contacts) | |
| Appt shift "+6 min vs. scheduled 15:15 CDT" | Appt delta | `appointments.getById` line 86; `appointments.updateStatus` line 194 | |
| ESANG idle-watch banner | AI advice | `esangAI.ts` | |
| "Log dwell" CTA | Write dwell event | `location.geofenceEvent` line 182 + `detentionAccessorials.ts` | |
| "Open bay brief" CTA | View hazmat bay brief | `appointments.getHazmatBays` line 370 | |

### Backend GAPS (numbered)
1. **Driver-facing queue position.** New `yardManagement.getMyQueuePosition({ facilityId, loadId })` returning `{ position, total, etaMinutes, advanceRatePerTruckSec }`.
2. **Dwell-exceedance auto-accrual.** Hook into `loadLifecycle.getActiveTimers` so crossing detention threshold writes a `detentionAccessorials.create` draft automatically.

### User-journey entry points
- Entry 1: from `014 Approaching Pickup` → gate geofence enter → `yardManagement.checkInTrailer` fires.
- Entry 2: push from facility guard check-in.

---

## 016 Pickup Loading.png

**Swift port:** 016_PickupLoading.swift
**Purpose (1-line):** Tank loading in progress — fill %, pressure, product temp, grounding, live bay sequence, emergency E-stop.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Header "Loading / Bay 03 · Koch Belle Plaine" | Active bay | `yardManagement.getDockSchedule` line 456 | |
| 38% LOADED ring w/ gal progress | Tank fill gauge | GAP — no tank/meter ingestion proc for driver view | see GAP 1 |
| Arm flow normal chip, "+204 gpm · 32 min to full" | Flow rate | GAP — tank/flow telemetry | see GAP 1 |
| Pressure 189 psi tile | Telemetry | `tankMonitor.ts` (exists) | pressures |
| Product temp -26°F tile | Reefer/product telemetry | `reeferTemp.getReadings` line 19 | partial |
| Grounding OK tile | E-ground status | GAP — no grounding-sensor proc | see GAP 2 |
| ESANG watchdog banner | AI monitor msg | `esangAI.ts` | |
| Bay sequence (Chock, Grounding, Arm, Transfer, Line blow-down, Release) | Sequence step list | `loadLifecycle.getStateHistory` line 2176 or NEW `loadingSequence.*` | see GAP 3 |
| E-Stop button | Emergency halt | `emergencyProtocols.ts` + `scada.ts` | SCADA halt cmd |
| Log bay note | Note add | `loads.addNote` line 1625 | |

### Backend GAPS (numbered)
1. **Hazmat tank loading telemetry stream.** Add `tankMonitor.getLoadingSnapshot({ loadId })` → `{ fillPct, gallonsNow, targetGallons, gpm, pressurePsi, tempF, groundingOhms }`. Augment SCADA integration already under `scada.ts`.
2. **Grounding cable sensor.** `tankMonitor.getGroundingStatus({ trailerId })` backed by `trailer_grounding_events` or SCADA.
3. **Loading sequence state machine.** New `loadingSequence.getSequence({ loadId })`, `loadingSequence.advanceStep({ loadId, step })`. Extend `loadLifecycle` namespace.

### User-journey entry points
- Entry 1: from `015 At Gate` → dock-assigned event → `appointments.startLoading` line 342.
- Entry 2: from guard scan that triggers SCADA flow-start.

---

## 017 BOL Signing.png

**Swift port:** 017_PickupBolSigning.swift
**Purpose (1-line):** BOL signature capture page — shipper vs driver co-sign of non-negotiable BOL for NH3 shipment.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| BOL card (ID KOCH-BP-...,  ship date, per cft 172.202, hazmat) | BOL header | `bol.getSummary` line 346; `bol.generate` line 374; `bol.generateBOLFromLoad` line 1067 | |
| Shipper / consignee blocks | Entity details | `loads.getById` line 1012 | |
| Commodity / hazard / net weight / placards / emergency contact rows | BOL body | `bol.generate` line 374 | |
| ESANG BOL-validator banner | AI check of BOL diffs | GAP — no BOL diff proc | see GAP 1 |
| Shipper signer row (Odell Kastner) | Counter-signer identity | `signatures.getPending` line 197 | |
| Driver signer row (Michael Eusorone · awaiting) | Driver sign | `signatures.save` line 20 | |
| View PDF | Render BOL pdf | `bol.generate` line 374 (returns doc) | |
| "Request shipper sign · PING BAY 3 SUPERVISOR" CTA | Notify supervisor for counter-sig | GAP — `signatures.requestCountersign` missing | see GAP 2 |

### Backend GAPS (numbered)
1. **BOL vs rate-con variance check.** New `bol.validateAgainstLoad({ loadId, bolId })` — uses `aiRateConReader.ts` + `aiDocProcessor.ts` to compare line items, weights, placards.
2. **Request countersignature.** New `signatures.requestCountersign({ documentId, signerUserId, channel: 'sms'|'push' })` — fires `messages.sendMessage` + creates pending row.
3. **Blockchain hash anchoring.** Optional: extend `signatures.save` to write hash into `blockchainAudit.ts` for immutable BOL custody.

### User-journey entry points
- Entry 1: from `016 Pickup Loading` → sequence step "Release from gantry" → auto-advance to BOL.
- Entry 2: Guard or shipper initiates BOL (`pod.submitPOD` or `bol.generate`).

---

## 018 En Route Loaded.png

**Swift port:** 018_ActiveEnrouteLoaded.swift
**Purpose (1-line):** Loaded en route to Braskem — next-turn, tank telemetry chips (tank loaded/locked, pressure, chill, toll), hand-off-to-co-driver option.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Next-turn card "In 3.8 mi · Keep left · I-802 split" | Turn step | GAP — same as 013 GAP 1 | |
| Progress "612 mi of 1,040 mi · 4h remaining" | Route progress | `navigation.getETA` line 123 | |
| NH3 10,500 gal LOCKED chip | Tank sealed state | `bol.generate` line 374 (seal #); GAP for realtime lock | partial |
| TANK 142 PSI · CHILL -29°F chip | Live telemetry | `tankMonitor.ts`; `reeferTemp.getReadings` line 19 | |
| Toll · $24 projected chip | Toll projection | GAP — no toll projection proc | see GAP 1 |
| ESANG transit-copilot banner | AI nudge | `esangAI.ts` | |
| Delivery stop card (Braskem America · appt 09:00 EDT) | Next stop | `loadStops.getForLoad`; `loads.getById` line 1012 | |
| DISTANCE / DRIVE TIME / HOS LEFT tiles | Trip + HOS mix | `navigation.getETA`; `hos.getCurrentStatus` line 50 | |
| "Plan break" CTA | Suggest rest stop | `restStops.getNearby` line 72; `routes.ts` | |
| "Hand off to co-driver" CTA | Team driver swap | GAP — no team-driver handoff proc | see GAP 2 |
| Bottom nav | Nav | client | |

### Backend GAPS (numbered)
1. **Toll projection.** `tolls.estimateForRoute({ routeId, axles, weightLb })` — new router or under `routes.ts`. Integrate with TollGuru/PrePass.
2. **Team-driver handoff.** `hos.transferDrivingToCoDriver({ loadId, fromDriverId, toDriverId, reason })` — records HOS line change for both, re-keys ELD.
3. **Seal-integrity check.** `bol.verifySealIntact({ bolId, photoUrl })` using `photoInspection.analyzePhoto`.

### User-journey entry points
- Entry 1: from `017 BOL Signing` after driver sig → state `in_transit_loaded` via `loadLifecycle.transitionState`.
- Entry 2: after a break — resuming driving → HOS status change.

---

## 019 HOS Duty Status.png

**Swift port:** 019_HosDutyStatus.swift
**Purpose (1-line):** HOS duty selector (OFF / SB / D / ON), 24-hour log graph, drive/on-duty/cycle totals, 30-min break timer, certify / add-remark.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Header "HOS / 70-hour 8-day / §395.8 compliant" | HOS compliance header | `hos.getCurrentStatus` line 50; `hos.getViolations` line 203 | |
| Current status "Off-Duty · break 30 min · resumes 21:23" | Live status + timer | `hos.getCurrentStatus` line 50; `loadLifecycle.getActiveTimers` line 3175 | |
| Duty-status selector (OFF/SB/D/ON) | Change duty state | `hos.changeStatus` line 93 | |
| 24-hour log graph | Log timeline | `hos.getDailyLog` line 114 | |
| DRIVE / ON-DUTY / CYCLE totals | Aggregate clocks | `hos.getCurrentStatus` line 50; `eld.getDriverELDCompliance` line 1084 | |
| 30-min break timer w/ progress | §395.3(a)(3)(ii) timer | `loadLifecycle.getActiveTimers` line 3175 | |
| "Certify yesterday" CTA | Certify driver log | `hos.certifyLog` line 185 | |
| "Add remark" CTA | Remark entry | `hos.addRemark` line 194 | |
| Footer (ELD Samsara IG-6L, VIN, driver self-certified) | ELD device info | `eld.getConnectionStatus` line 456; `eld.getProviderConfig` line 377 | |
| Bottom nav | Nav | client | |

### Backend GAPS (numbered)
1. **Per-driver split-sleeper calculator.** New `hos.evaluateSplitSleeper({ driverId })` — today's logic lives only in `hosEngine` service; expose at router level with recommended pairings.
2. **HOS log export (PDF/ELD format).** `hos.exportLogs({ driverId, startIso, endIso, format: 'pdf'|'csv'|'eld' })` for roadside audit.

### User-journey entry points
- Entry 1: Tile on `010 Driver Home` ("HOS / Duty Status").
- Entry 2: HOS warning push (approaching 30-min break / 11-hr limit).

---

## 020 Approaching Delivery.png

**Swift port:** 020_ApproachingDelivery.swift
**Purpose (1-line):** Approaching Walmart DC delivery — geofence armed, pre-gate checklist (seal, BOL copies, dash-cam, lumper), "I'm at the gate" CTA.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Back chevron + "Approaching delivery" header | Context | client | |
| Next-turn "In 1.0 mi · Turn right onto Rockfish Rd" | Turn step | GAP — see 013 GAP 1 | |
| Geofence chip "0.6 mi · arming dash-cam on entry" | Active geofence w/ payload | `geofencing.getNearbyGeofences` line 349; `geofencing.checkLocation` line 146 | |
| Receiver card (Walmart SC 2718 · 4600 Post Rd · appt 16:00–16:30 EDT · on-time) | Delivery stop | `loads.getById` line 1012; `loadStops.getForLoad` | |
| "2.4 mi to dock" | Distance | `navigation.getETA` line 123 | |
| Checklist item: Load sealed 881204 | Seal recorded | `bol.generate` line 374 (seal field); GAP for per-step verify | |
| Checklist item: BOL on file · 3 copies | Document presence | `loads.getDocuments` line 1586 | |
| Checklist item: Dash-cam armed for gate entry | Dash-cam state | GAP — no dash-cam state proc | see GAP 1 |
| Checklist item: Unload lumper | Lumper required? | `detentionAccessorials.ts` (accessorial); GAP for specific lumper flag | |
| "I'm at the gate" primary CTA | Transition arrival | `loadLifecycle.checkIn` line 3466; `loadLifecycle.transitionState` line 3021 | |
| "Call receiver" CTA | Phone dial | `messages.getUserPhone` line 674 | |

### Backend GAPS (numbered)
1. **Dash-cam arm/disarm control.** `dashCam.arm({ vehicleId, reason, triggerGeofenceId })`, `dashCam.getStatus({ vehicleId })` — new `dashCam.ts` router or under `fleet.ts`.
2. **Lumper requirement evaluator.** `accessorial.evaluateLumper({ loadId, facilityId })` returning need + pre-auth amount.
3. **Seal integrity check on approach.** `bol.verifySealIntact` as described in 017 GAP.

### User-journey entry points
- Entry 1: from `018 En Route Loaded` → geofence enter event (approach ring).
- Entry 2: manual nav from map "I'm arriving" press.

---

## 021 At Receiver Gate.png

**Swift port:** 021_AtReceiverGate.swift
**Purpose (1-line):** At Walmart receiver gate — guard checking BOL, queue #2, arrived timestamp, ETA for dock door push, CTAs to call guard, open BOL, message receiver.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Header "At receiver gate" | Context | client | |
| Trailer + Seal strip (TR-2118 · Seal 881204) | Trailer + seal | `yardManagement.getTrailerDetails` line 876; `bol.generate` seal | |
| Geofence chip "0.0 mi · DASH-CAM ARMED" | Active geofence state | `geofencing.checkLocation` line 146 + GAP dash-cam (see 020) | |
| Guard-check card "Checking in B · Walmart SC 2718 · 1875 Rockfish Rd" | Guard session | `facilities.ts` + GAP `guard check-in` | see GAP 1 |
| Arrived time / queue / dock-push ETA tiles | Arrival data | `loadLifecycle.checkIn` line 3466; GAP queue = 015 GAP 1 | |
| "Seal 881204 intact" banner | Seal status | GAP — see 017/020 seal GAP | |
| Call guard / Open BOL / Message receiver tiles | Quick actions | `messages.getUserPhone` line 674; `bol.generate` line 374; `messages.sendMessage` line 279 | |
| "I'm checked in" primary CTA | Transition to checked-in | `loadLifecycle.transitionState` line 3021 (checked_in) | |
| "Call dispatch" CTA | Dispatcher phone | `dispatch.sendDriverMessage` line 1433 (reverse); `messages.getUserPhone` | |

### Backend GAPS (numbered)
1. **Guard check-in workflow.** New `facilities.guardCheckIn({ facilityId, driverId, loadId, photoIdUrl })` returning queue number + estimated door push; write to `facility_gate_log` table. Mirrors `yardManagement.getGateLog` line 1508 but for drivers.
2. **Live dock-push ETA model.** `yardManagement.predictDockPush({ facilityId, loadId })` backed by historical arrival-to-door minutes.

### User-journey entry points
- Entry 1: from `020 Approaching Delivery` via "I'm at the gate".
- Entry 2: guard scans load barcode → push notification.

---

## 022 Dock Assigned.png

**Swift port:** 022_DockAssigned.swift
**Purpose (1-line):** Dock assigned — door #47, aisle 5 grocery receiving, yard map thumbnail, call-lumper, "I'm at door" CTA.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Header "Dock assigned · Walmart SC 2718 · cleared 16:02 dwell 17m" | Assignment state | `yardManagement.getDockSchedule` line 456; `loadLifecycle.getActiveTimers` line 3175 | dwell timer |
| Dock number "47 · Aisle 5 · grocery receiving · Driver-side · flush to rubber" | Dock details | `yardManagement.getDockSchedule` line 456 | |
| DOOR / AISLE / APPROACH tiles | Dock meta | `yardManagement.getDockSchedule` line 456 | |
| Yard map visualization w/ B Gate + dock row | Live yard map | `yardManagement.getYardMap` line 344 | |
| Expand yard map button | Full-view switcher | client | |
| Yard map full view tile | Map nav | `yardManagement.getYardMap` line 344 | |
| Dock cam door 47 tile | Live camera feed | GAP — no dock-cam feed proc | see GAP 1 |
| Message lumper tile | Msg to lumper service | `messages.sendMessage` line 279 + GAP lumper contact | |
| Green-at-door instructions banner | Static/sourced text | `yardManagement.getDockSchedule` (notes) | |
| "I'm at door 47" primary CTA | Arrival at door event | `loadLifecycle.transitionState` line 3021; `yardManagement.updateTrailerPosition` line 394 | |
| "Call dispatch" CTA | Dispatcher phone | `messages.getUserPhone` line 674 | |

### Backend GAPS (numbered)
1. **Dock camera feed.** `yardManagement.getDockCameraStream({ facilityId, door })` returning HLS URL + arming state. Ties to `fleet.ts` camera inventory.
2. **Lumper contact + dispatch.** `facilities.getLumperContact({ facilityId, door })` — return phone, rate, pre-auth.
3. **Door-arrival auto-event.** New `yardManagement.recordDoorArrival({ loadId, door, lat, lng, photoUrl })` that fires both `loadLifecycle.transitionState` and `yardManagement.updateTrailerPosition`.

### User-journey entry points
- Entry 1: from `021 At Receiver Gate` after guard push to dock (push notification with door #).
- Entry 2: yard-manager manual assign → pushes to driver's active screen.

---

## Summary

- **Total UI elements audited:** 137 across 13 screens (avg 10.5/screen).
- **Already backed by concrete tRPC procedures:** ~98 elements (approx **72%**). The `loadLifecycle`, `hos`, `inspections`, `navigation`, `yardManagement`, `bol`, `eld`, `driverMobile`, `messages`, `geofencing`, `signatures`, and `appointments` routers provide strong coverage for the core driver flow.
- **Swift port coverage:** 13 of 13 screens have a `.swift` file (100%).

### Top-3 most urgent gaps
1. **Hazmat tank loading & trailer telemetry stream** (screens 010, 016, 018). No driver-facing snapshot procedure for live fill %, flow rate, pressure, temp, grounding. Propose `tankMonitor.getLoadingSnapshot({ loadId })` and `trailerTelemetry.getSnapshot({ trailerId })` — blocks screens 016 and 018's primary data.
2. **Facility queue / guard check-in / dock-push ETA** (screens 015, 021, 022). Yard data exists for dispatchers (`yardManagement.getGateLog`, `getDockSchedule`) but there is no driver-side `getMyQueuePosition`, `guardCheckIn`, or `predictDockPush`. These are the marquee numerics on three screens.
3. **Turn-by-turn maneuver streaming + dash-cam control + toll projection** (screens 013, 018, 020, 021). The navigation router returns ETA and route geometry but not per-step maneuvers. Dash-cam arming and toll projections are entirely absent. Propose `navigation.getNextManeuver`, `dashCam.arm/getStatus`, and `tolls.estimateForRoute`.

Secondary notable gaps: DVIR PDF export, bobtail/clean-out receipts, placard verification, BOL vs rate-con validator, seal-integrity photo check, team-driver HOS handoff, split-sleeper evaluator, lumper evaluator, and loading-sequence state machine.
