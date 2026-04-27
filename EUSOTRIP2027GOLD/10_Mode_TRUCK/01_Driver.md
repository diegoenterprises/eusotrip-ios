# 10 · Mode TRUCK — Driver

**What this covers.** The canonical TRUCK::Driver doctrine — seven persona variants, 21-step daily lifecycle from wake to settlement, 010–099 screen map, HOS regime (49 CFR 395), DVIR pre/post/in-trip, Pulse watch integration, offline-first in long-haul dead zones, voice dispatch via ESANG on watch, cross-border (US⇄CA, US⇄MX), hazmat specifics, reefer specifics, vertical add-ons, settlement + pay (three payout tracks), safety (SOS, fatigue, crash detection), compliance (IFTA, 150-air-mile, sleeper-berth, personal conveyance), first-login wizard, The Haul gamification, wallet 8-section flows, messaging, pitfalls + edge cases, non-negotiables. Source: wave-1 shard `team_TRUCK_driver`.

**When you need this.** When building or reviewing any of the 010–099 screens. When wiring anything to `drivers.*`, `hos.*`, `loadLifecycle.*`, `fleet.*`. When a driver story asks "what does X look like" and it's a corner case.

**Cross-links.** Backend procedures: [03_Backend_API_Contract.md](./../03_Backend_API_Contract.md). Brand + primitives: [01_Brand_DNA_and_Design_Rules.md](./../01_Brand_DNA_and_Design_Rules.md). Journeys: [80_User_Journeys_and_Load_Lifecycle.md](./../80_User_Journeys_and_Load_Lifecycle.md). Offline + Pulse: [60_Offline_First_and_Pulse_Watch.md](./../60_Offline_First_and_Pulse_Watch.md). Messaging + ESANG: [70_Messaging_and_ESANG_AI.md](./../70_Messaging_and_ESANG_AI.md). Verticals × countries: [50_Verticals_Reference.md](./../50_Verticals_Reference.md).

---

> Section owner: TRUCK mode, role = DRIVER.
> Canonical source: `frontend/server/routers/drivers.ts` + `hos.ts` + `loadLifecycle.ts` + `fleet.ts`, inspections/DVIR inside the compliance-safety slice, iOS surface under `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/EusoTrip/Views/Driver/`.
> Applies to the entire 010–099 Driver brick queue.
> **Rule**: there is no `TRUCK_DRIVER` role in the backend. Truck driver is `role = DRIVER`, `transportModes contains TRUCK`. MX drivers are same role with `country = MX` and a CARTA_PORTE profile attached. Do not invent `TRUCK_DRIVER` in code; gate by `role === 'DRIVER' && transportModes.includes('TRUCK')`.

---

## 1. Persona surface

The TRUCK::Driver role is deliberately a single SwiftUI surface that dynamically reshapes into seven real-world persona variants. The client never forks the Driver tab by persona. Instead, the Driver record exposes a `profileFlags` bitfield and `classification` enum that the home screen reads on mount to decide which cards, CTAs, and compliance counters to hydrate.

**Solo OTR.** Long-haul over-the-road, 48-state or 11-western. Default 70-hour / 8-day cycle. Home prioritises multi-day trip planning, fuel optimiser, truckstop parking reservations, weekly settlement pacing. Sleeper-berth rules always enabled. Personal conveyance eligible with company policy gate.

**Team.** Two drivers on one tractor, alternating drive / sleeper. HOS clock surfaces both co-drivers side by side. Duty-status changes fire a `team_switch` geotag. Load acceptance requires both drivers' HOS to clear; backend `canDriverAcceptLoad` runs twice (per co-driver userId), accept CTA gated by stricter result.

**Regional.** 500–800 mile lanes, home every 5–7 days. Same mechanics as Solo OTR but with weekly home-time planning in The Haul streaks tab.

**Local / P&D.** Pickup and delivery, 100-air-mile radius. Driver qualifies for 150-air-mile short-haul exemption when `radiusMiles <= 150`, `returnToTerminal === true`, `maxOnDuty <= 14h`. When exemption trips, HOS clock switches to exemption mode and ELD logging pauses — client must still render gradient-orange pill so driver knows regime.

**Owner-operator.** Driver owns tractor (and usually trailer). Wallet flow adds Business tab: IFTA accruals, fuel card balances, factoring offers, 1099 summaries. Rate-cons surface margin, not just line-haul. Settlement runs against driver's Connect account directly, bypassing carrier settlement.

**Company driver.** Paycheck runs through carrier. Wallet shows net after deductions. No 1099 — W-2 summary only. Factoring offers hidden.

**Hazmat-endorsed.** `hazmatEndorsement === true` on `drivers` row. Unlocks hazmat-flagged loads in Dispatch, exposes ERG lookup in Me → Compliance, forces HM-232 security plan check on every load assignment whose cargo UN class requires.

**CDL-A vs CDL-B.** `licenseClass` field gates trailer types dispatch surfaces. CDL-B sees straight trucks, single-axle reefers, dry vans under 26,001 lb GVWR; CDL-A sees everything. Client must HIDE — not grey out — equipment the driver cannot legally operate, and surface neutral "Upgrade your CDL to unlock" card when dispatch board thin due to class filtering.

All seven variants share the same 010–099 screen set. Selection is a read of `drivers.getProfile` at boot, cached in `DriverHomeVM` so sub-screens don't re-fetch.

---

## 2. Daily lifecycle — wake to settlement

Every action maps to a real screen, tRPC call, Pulse watch haptic. This is the canonical day.

1. **Wake / app resume (010 `DriverHomeScreen`).** App cold-launches or resumes. Client fires `drivers.getProfile, hos.getStatus, loads.getActive, dispatch.getCurrent, zeunMechanics.getActiveBreakdowns` in parallel. Home renders hero card (active load if any else "Ready for dispatch"), HOS ring with drivingRemaining/onDutyRemaining/cycleRemaining, weather-animated sky, messages count, wallet chip. Pulse pings soft "good morning" haptic if driver's calendar shows active load within 4 hours.

2. **Pre-trip DVIR (011 `PretripDVIRScreen`).** Driver taps "Start pre-trip". Client drives checklist against inspection schema; backend persists each item to `inspections` table with `type = 'pre_trip'`. Mandatory items (brakes, tires, lights, coupling, mirrors, horn, wipers, emergency equipment) must all be marked pass/fail with at least photo for any fail. Discretionary (fluid top-off, trailer sweep) can skip but logged. Defect severity: `minor` (proceed with note), `major` (call dispatch before departing), `oos` (refuses `en_route_pickup` until mechanic clears via Zeun).

3. **DVIR submitted (012 `DvirSubmittedScreen`).** Shows signed inspection sheet with timestamp + geotag. Duplicate pushed to dispatcher + carrier compliance manager as document artefact (`documents`, `docType = DVIR_PRE`).

4. **Dispatch accept (047 / 048).** If new offer, driver sees hero card "Review offer" chip. Tap opens offer: lane, stops, miles, rate, cargo class, special requirements (hazmat, reefer set-point, tarping, team, escort). Accept calls `dispatch.accept(loadId)` → runs `canDriverAcceptLoad` server-side (checks HOS, CDL class, hazmat endorsement, medical card validity, TWIC if port, driver's current location vs pickup ETA vs HOS clock). Decline routes to 049 with reason code.

5. **En-route to pickup (013 `ActiveEnrouteScreen`).** Load transitions to `en_route_pickup`. GPS ticks every 30s, geotags into `gpsTracking`. Lifecycle engine auto-transitions to `at_pickup` on pickup geofence entry (radius from `fleet.getGeofences`). Weather sky animates by time. Pulse fires short "transit engaged" haptic.

6. **Approaching pickup (014).** Within 3 miles of shipper, dock-in instructions, gate code, appointment window, "Notify shipper I'm close" CTA firing `messages.send` to driver-shipper conversation.

7. **At gate / awaiting dock (015).** Driver checks in at guard shack. Detention clock starts — `financialTimers.startTimer('detention', loadId)` — server-authoritative counter flips to `detention_pending` after free-time window (typically 2h). **Clock never client-trusted.**

8. **Pickup loading (016).** Dock assigned. Cargo, pieces, weight, temperature set-point (reefer), placards (hazmat), tarping (flatbed). Driver can tap "Report exception" → 043 loading exception.

9. **BOL signing (017).** Shipper hands BOL; driver scans or captures. Uploaded to `documents` with `docType = BOL` tagged to loadId. Signature captured on-screen, hashed into BlockchainService audit chain. Load transitions `loaded` → `in_transit` on pickup geofence exit.

10. **En-route loaded (018).** Same as 013 but hero shows cargo details, ETA, next waypoint, live HOS ring. Reefer → temperature strip on bottom. Hazmat → placard chip pinned top-right.

11. **HOS duty status (019 `HosDutyStatusScreen`).** Driver manually changes duty (off_duty, sleeper, on_duty_not_driving, driving) by tapping HOS ring. Mutation hits `hos.changeStatus` — ELD-aware (Motive/Samsara/Omnitracs token syncs both ways). If no ELD token, in-memory HOS engine logs and compliance manager gets synthetic log.

12. **Approaching delivery (020).** Mirrors 014 for receiver.

13. **At receiver gate (021) / dock assigned (022).** Mirrors 015/016.

14. **Unloading (024 `Unloading`).** Unload progress, accessorial entries (lumper fee receipt, layover request), exception filing.

15. **POD capture (041 — shipped as paperwork/signoff variants).** Receiver signs on screen or driver photographs stamped BOL. Upload to `documents` `docType = POD`. Load transitions `pod_pending` → `delivered` once receiver/broker confirms POD.

16. **Off-duty (026 `OffDuty`).** HOS ring flips to green-idle, The Haul XP ticker fires, wallet hero updates with newly-posted settlement line item.

17. **Settlement (054 `HaulPaySettlement`, 055 `DayCloseWallet`).** Engine creates line item and, based on driver elections, queues for weekly settlement, offers HaulPay quickpay (24-48h factoring), or routes instant payout via Stripe Connect same-day to linked debit card. 1099 accumulator (owner-ops) increments. Wallet activity feed updates.

Every step persisted server-side and gamified client-side.

---

## 3. Screen map — the 010–099 surface

| # | Title | Shipped | Canonical procedure(s) |
|---|---|---|---|
| 010 | Driver Home | yes | `drivers.getProfile`, `hos.getStatus`, `loads.getActive`, `dispatch.getCurrent` |
| 011 | Pre-trip DVIR | yes | `inspections.create` (pre_trip), `documents.upload` |
| 012 | DVIR Submitted | yes | `inspections.getById`, `documents.get` |
| 013 | Active En-route | yes | `loads.getById`, `gps.heartbeat`, `hos.getStatus` |
| 014 | Approaching Pickup | yes | `loadLifecycle.transition('at_pickup')`, geofence |
| 015 | At Gate / Awaiting Dock | yes | `financialTimers.start('detention')`, `messages.send` |
| 016 | Pickup Loading | yes | `loadLifecycle.transition('loading')` |
| 017 | Pickup BOL Signing | yes | `documents.upload(BOL)`, BlockchainService.record |
| 018 | Active En-route Loaded | yes | `loadLifecycle.transition('in_transit')` |
| 019 | HOS Duty Status | yes | `hos.changeStatus`, `hos.getCurrentStatus` |
| 020 | Approaching Delivery | yes | geofence `at_delivery` |
| 021 | At Receiver Gate | yes | `financialTimers.start('detention_delivery')` |
| 022 | Dock Assigned | yes | receiver dock mutation (fleet/terminal) |
| 023 | Backing In | yes | Pulse watch haptic primer |
| 024 | Unloading | yes | `loadLifecycle.transition('unloading')` |
| 025 | Paperwork | yes | `documents.upload(lumper, POD)` |
| 026 | Off Duty | yes | `hos.changeStatus('off_duty')` |
| 027 | Next Load Brief | yes | `dispatch.getNextOffer` |
| 028 | Load Locked Pre-haul | yes | `dispatch.accept` effect |
| 029 | Pickup Arrival | yes | geofence arrival |
| 030 | Loading In Progress | yes | vertical-specific (tanker SpectraMatch) |
| 031 | SpectraMatch Verdict | yes | `intelligence.spectraMatch.verdict` |
| 032 | Detach Sequence | yes | tanker/drop-hook gate |
| 033 | BOL Sign-off | yes | `documents.sign(BOL)` |
| 034 | Departing Pickup | yes | geofence exit |
| 035 | En-route Drive | yes | `gps.heartbeat` loop |
| 036 | ESANG Smart Stop | yes | `intelligence.esang.suggestStop` |
| 037 | Approaching Receiver | yes | geofence |
| 038 | At Receiver Gate (tanker) | yes | financial timers |
| 039 | Backing-Assist Receiver | yes | Pulse haptic |
| 040 | Discharge In Progress | yes | tanker discharge |
| 041 | Discharge Complete | yes | `loadLifecycle.transition('unloaded')` |
| 042 | Disconnect & Verify | yes | tanker hose sensors |
| 043 | Disconnect Confirmed | yes | geotag + signature |
| 044 | Connect Drop Hose | yes | tanker gate |
| 045 | Departing Receiver | yes | geofence exit |
| 046 | Sequenced Leg Approach | yes | intermodal leg advancement |
| 047 | Arrival Checkpoint | yes | `loadLifecycle.transition` |
| 048 | Arrival Gate Task Active | yes | checkpoint workflow |
| 049 | Task Result | yes | checkpoint completion |
| 050 | Next Beat Live | yes | dispatch beat feed |
| 051 | Beat Complete | yes | gamification XP dispatch |
| 052 | Rate-con Tender | yes | `documentManagement.generateRateConfirmation` |
| 053 | ESANG Dispatch Chat | yes | `messages.*` + ESANG agent |
| 054 | HaulPay Settlement | yes | `haulpay.*`, `settlementBatching.*` |
| 055 | Day Close Wallet | yes | `wallet.getBalance`, `money.getSettlements` |
| 056 | Driver Profile | yes | `drivers.getProfile` |
| 057 | Driver Vehicle Card | yes | `fleet.getVehicle` |
| 058 | Driver Weekly Plan | yes | dispatch weekly plan |
| 059 | Driver Trips History | yes | `loads.getHistory` |
| 060 | The Haul Dashboard | yes | `gamification.*` |
| 061 | The Haul Missions | yes | `gamification.getMissions` |
| 062 | The Haul Badges | to port | `gamification.getBadges` |
| 063 | The Haul Crates | to port | display-only (no writers) |
| 064 | The Haul Leaderboard | to port | `gamification.getLeaderboard` |
| 065 | The Haul Streaks | to port | `gamification.getStreaks` |
| 066 | The Haul Cosmetics | to port | `gamification.equipCustomization` (titles only persist) |
| 067 | Me · Profile | yes | `drivers.getProfile`, `users.updateProfile` |
| 068 | Me · Earnings | yes | `money.getSettlements` |
| 069 | Me · Wallet (8-section) | partial | `wallet.*`, `money.*`, `factoring.*` |
| 070 | Me · Settlements | to port | `settlementBatching.*` |
| 071 | Me · Tax | to port | `taxReporting.mobile.*` |
| 072 | Me · Docs (CDL / Medical / TWIC / Hazmat) | to port | `documents.*`, `certifications.*` |
| 073 | Me · Vehicle | to port | `fleet.getVehicle` |
| 074 | Me · HOS Logs | to port | `hos.getDailyLog`, `hos.certifyLog` (stub — flag) |
| 075 | Me · Safety Score | to port | `drivers.getSafetyScore` |
| 076 | Me · Training | to port | `certifications.*` |
| 077 | Zeun · Dashboard | to port | `zeunMechanics.getDashboard` |
| 078 | Zeun · Breakdown | to port | `zeunMechanics.createBreakdown` |
| 079 | Zeun · ESANG Diagnose | to port | `zeunMechanics.diagnose` |
| 080 | Zeun · Repair Shops | to port | `zeunMechanics.findShops` |
| 081 | Zeun · Maintenance Schedule | to port | `zeunMechanics.getSchedule` |
| 082 | Zeun · Recalls | to port | `zeunMechanics.getRecalls` |
| 083 | Zeun · DTC Codes | to port | `zeunMechanics.lookupDTC` |
| 084 | HOS · Clock | to port | `hos.getCurrentStatus` |
| 085 | HOS · Log Edit | to port | `hos.editLog` |
| 086 | HOS · Certify | to port | `hos.certifyLog` (stub — neutral empty) |
| 087 | HOS · Remark | to port | `hos.addRemark` (stub — neutral empty) |
| 088 | ELD · Diagnostics | to port | `eld.getStatus` |
| 089 | ELD · Fault Codes | to port | `eld.getFaults` |
| 090 | Cross-border · US→CA | to port | `crossBorder.aci`, `crossBorder.fast` |
| 091 | Cross-border · US→MX | to port | `crossBorder.vucem`, `crossBorder.cartaPorte` |
| 092 | Cross-border · Carta Porte | to port | `crossBorder.cartaPorte.generate` |
| 093 | Cross-border · ACE/ACI | to port | `crossBorder.ace`, `crossBorder.aci` |
| 094 | Escort · Active | to port | `escorts.getAssignment` |
| 095 | Escort · Handoff | to port | `escorts.handoff` |
| 096 | Autonomous · Monitor | to port | `autonomous.getStatus` |
| 097 | Autonomous · Handoff | to port | `autonomous.handoff` |
| 098 | Emergency · SOS | to port | `safety.sos`, telephony |
| 099 | Shutdown | to port | session end, HOS off-duty, settlement cut |

**Shipped**: rendered into `ContentView.ScreenRegistry.all` and verified in both registers. **to port**: Figma exists, not yet wired. **partial**: wired but not to full spec.

---

## 4. Hours of Service (HOS) regime

49 CFR 395 property-carrying rules with FMCSA-aligned exemptions.

**14-hour clock.** Starts at first on-duty event of workday. Cannot be extended by off-duty inside window. Outer ring on HOS dial.

**11-hour drive.** Max 11 cumulative hours of driving inside 14-hour window. Inner ring.

**30-minute break.** After 8 cumulative driving hours without 30-minute non-driving break, driving prohibited. Persistent banner when `drivingSinceLastBreak >= 7.5h`.

**8/2 sleeper-berth split.** Qualifying 8-hour sleeper period pauses (not resets) 14-hour clock; paired 2-hour off-duty/sleeper pairs. Same for 7/3. HOS engine handles math; client renders used AND paused portions of 14-hour ring as banded gradient.

**34-hour restart.** Two consecutive 1am–5am home-terminal periods, 34 hours off-duty or sleeper, resets 60/70-hour cycle. "Plan restart" CTA on HOS clock screen calculates earliest legal restart.

**Short-haul exemption (150-air-mile).** Drivers within 150-air-mile of normal work-reporting location who return within 14 hours and are released within 14 are exempt from ELD record-keeping and detailed logging. Client surfaces gradient-orange "Short-haul mode" pill, HOS dial switches to simplified "time on duty" count. Exiting radius or exceeding 14 on-duty drops driver back into full ELD mode mid-day.

**Ag exemption.** 150-air-mile radius from source of commodity during planting/harvest seasons per state. Client gates to `agExemption = true` and requires manual season activation per trip.

**Personal conveyance.** Off-duty movement of CMV for driver's personal benefit. Strict rules: must be laden or unladen with load delivered, cannot advance load commercially, reasonable distance. Client implements dedicated "Personal Conveyance" duty sub-state writing to ELD log with correct annotation. Carrier policy may disable via company flag.

Backend truth: `frontend/server/services/hosEngine.ts + hosEngineELD.ts`. `hos.certifyLog` and `hos.addRemark` are currently **stubs** — client must render screens but show neutral empty state with "Certification pending — coming soon" message, not fake a success.

---

## 5. DVIR — pre, post, in-trip

Legal gate between driver and load.

**Pre-trip (011).** Required before any driving on a given workday. Items: brakes (service + parking), steering, lights (clearance, tail, stop, headlamps, turn), tires (tread depth ≥ 4/32 steer, 2/32 others), wheels/rims, horn, windshield wipers, rear-vision mirrors, coupling devices, emergency equipment (triangles, fire extinguisher, spare fuses), trailer air lines, trailer lights, trailer brakes, kingpin/fifth wheel, load securement.

**Post-trip.** Required after workday. Same items + fuel-level log + odometer. Any defect routed to fleet maintenance through Zeun.

**In-trip.** Ad-hoc inspections triggered by event — weigh station referral, roadside inspection, accident aftermath. Creates `inspections` row with `type = 'in_trip'` and linked `safetyIncidents` row if severity warrants.

**Mandatory vs discretionary.** 16-item FMCSA mandatory set cannot be skipped. Discretionary (fluid check, trailer sweep, reefer pre-cool) driver-elected, logged as optional. Client visually separates groups and disables "Submit" until every mandatory has pass/fail.

**Defect severity:**
- `minor` (burned-out clearance lamp with redundancy, worn wiper insert): may proceed, fleet-maintenance ticket, 30-day fix.
- `major` (one headlamp out, loose mud flap): must call dispatch; dispatcher may authorise proceed-to-repair.
- `out-of-service (OOS)` (air-brake leak, steer-tire below 4/32, non-working emergency brake): lifecycle engine refuses `en_route_pickup`. Vehicle flips `status = 'out_of_service'`. Zeun creates high-priority breakdown, routes to nearest certified repair shop.

Backend storage: `inspections` + `documents`. **There is no standalone `dvir.ts` router** — DVIR writes flow through `inspections.create` and `documents.upload`. Do not invent `dvir.*` namespace; call the real procedures.

---

## 6. Pulse watch integration

Driver's wrist surface. Every watch action is a shadow of a phone action with stricter input budget and wider haptic vocabulary.

- **Wake → morning brief.** Soft double-tap haptic. Complication shows HOS drive-remaining, next load distance, weather icon.
- **Pre-trip checklist.** 16-card swipe deck. Swipe = pass. Long-press = fail + voice note. Photos require phone. Submit does server sync on return to phone proximity.
- **Duty-status change.** Double-tap HOS ring → confirm sheet → `hos.changeStatus`. Single taps ignored to prevent accidental off-duty.
- **Approach / arrival.** Single crisp haptic at 3 miles, triple haptic at geofence edge. Announces dock number if pre-assigned.
- **Detention timer.** Subtle 15-minute tick haptic while running, sharper pulse once free window closes.
- **Emergency SOS.** Side-button long-press triggers SOS flow.
- **Dispatch offer.** New offer = rising gradient chime + haptic. Swipe left decline, swipe right accept into confirm detent.
- **Voice dispatch.** Raise-to-wake + "Hey ESANG" wakes voice agent for messaging, navigation, or quick settlement check.

Every action echoed to phone via WatchConnectivity, mirrored into same tRPC procedure phone would call. No watch action is local-only no-op.

---

## 7. Offline-first in long-haul dead zones

Driver must run full day even in LTE-dark corridors (Wyoming I-80, Montana, Mojave, northern Ontario, US–Mexico border pull-off zones).

**Local queue.** All tRPC mutations go through local write-ahead queue backed by SwiftData. Every mutation has client-UUID, created-at, retry budget. On reconnect, queue drains in order; conflicts (duty status changed on ELD while client offline) resolved server-side with last-writer-wins per field, but HOS engine re-derives totals from authoritative log.

**Preload.** On dispatch-accept, client pre-caches load record, route, shipper + receiver profiles, BOL template, Carta Porte (MX), hazmat ERG (hazmat), reefer set-point (reefer). Maps tiles along planned route pre-downloaded at two zoom levels.

**Geotags.** GPS recorded locally at 30s cadence even without connectivity. Each geotag signed with device key, stamped with monotonic clock so later upload cannot be back-dated.

**DVIR.** Pre-trip must work fully offline; photos stored locally, `inspections` row queued. Lifecycle guard tolerant of late DVIR arrivals as long as client timestamp precedes first driving-status entry.

**HOS.** On-device engine is full simulator mirroring `hosEngine.ts`. Offline, driver sees same rings server would show. Once online, engine resyncs and server is source of truth for anything that matters legally.

**Messages.** Drafts local. Send-on-reconnect.

**Settlement / payout.** Never offline. Surface neutral "Will sync when online" rather than faking balance.

See [60_Offline_First_and_Pulse_Watch.md](./../60_Offline_First_and_Pulse_Watch.md) for F01–F16 full system.

---

## 8. Voice dispatch via ESANG on watch

Voice surface includes:
- "What's my drive time?" → reads HOS ring.
- "How far to pickup?" → reads route ETA.
- "Start my pre-trip" → opens watch checklist.
- "Accept the offer" → confirms outstanding offer. **Requires second voice confirmation with scrambled two-word phrase** to prevent drive-by radio accidents.
- "Set off-duty" → duty-status change with confirm detent.
- "Text dispatch: I'm stuck at the weigh station" → composes and sends.
- "Find me the closest certified diesel mechanic" → Zeun shop lookup, 3 results read aloud.
- "What's the forecast for the I-40 corridor?" → weather summary.
- "Read me the rate-con" → TTS of rate-confirmation.

All voice actions logged to same audit chain as phone actions. ESANG responses via Gemini 2.5 Flash through `intelligence.esang.*`; client must **never cache ESANG outputs as authoritative** for HOS, route, or money data.

---

## 9. Cross-border crossings

**US → Canada.** ACI filing via CBSA, FAST card for trusted-trader lane, PARS barcode on carrier docs. Screens 090/093 surface ACI status, FAST eligibility (driver + carrier combined), PARS barcode. `crossBorder.aci` is stub with `_note` field — client renders UI, shows neutral "Filing status available shortly" until live CBSA integration lands.

**US → Mexico.** ACE filing (US), VUCEM manifest (MX), Carta Porte (SAT electronic bill-of-lading), IMMEX / OEA trusted-trader where applicable. Screen 092 pulls shipper, receiver, vehicle, driver, route, cargo weight, UN numbers (hazmat), tax classification → `crossBorder.cartaPorte.generate` returns CFDI-compatible XML + PDF. Driver screens PDF on-device, presents at border.

**FAST / C-TPAT.** Certified drivers with both endorsements get express lane. Client reads `certifications` for `FAST, CTPAT, OEA`, exposes pill on home when active.

**Cabotage.** Mexican drivers hauling US subject to cabotage rules. Backend `runMXPreDispatchChecks` enforces; client surfaces gradient-orange warning if requested load would violate cabotage for MX driver.

See [40_Intermodal_and_Cross_Border.md](./../40_Intermodal_and_Cross_Border.md) for full cross-border system.

---

## 10. Hazmat-specific

**Placards.** Driver affixes per UN class. Client shows placard graphic on pickup and in-transit hero. Driver photographs placarded trailer, uploads to `documents` `docType = HAZMAT_PLACARD_PHOTO` before load transitions out of `loaded`.

**UN numbers.** Load record carries UN numbers, proper shipping name, packing group, reportable quantity per commodity line. Cargo card shows verbatim from shipper manifest.

**Emergency contacts.** Every hazmat load carries 24/7 emergency response contact. Pinned to hazmat sheet + Pulse complication for load duration.

**Route restrictions.** Certain UN classes prohibit tunnels, dense-urban corridors, some bridges. Backend route planner enforces; client renders restricted-corridor banner and refuses to file route that violates.

**HM-232 security plan.** For highway route-controlled quantities (largely Class 7 radioactives, selected Class 1 explosives, selected toxics), carrier must have HM-232 plan and driver must be trained. Client gates acceptance: `canDriverAcceptLoad` includes `hm232Trained` check against `certifications`. If missing, accept CTA replaced with "Training required — open".

**ERG lookup.** Emergency Response Guidebook available offline on-device. Driver taps UN number on hazmat sheet → ERG entry: health hazards, fire + explosion hazards, public safety distances, first-aid, spill response. **Critical offline-first feature** — must work with zero connectivity.

---

## 11. Reefer-specific

**Temperature logging.** Reefer unit reports set-point, supply-air, return-air, fuel level. Client subscribes via `fleet.streamReefer(loadId)`, renders live temperature strip. Every 15 minutes persisted to `reeferLogs` attached to load. FSMA compliance requires continuous log; gap > 30 minutes flips load to `reefer_exception` and notifies shipper.

**FSMA compliance.** Food Safety Modernization Act — Sanitary Transportation of Human and Animal Food rule — requires written procedures, training records, temperature-controlled chain of custody. Client validates at accept time via compliance-safety slice (FSMA exists only as service, no tRPC router — neutral empty state on FSMA sub-screen).

**Set-point alerts.** If supply-air deviates > 3°F from set-point for > 5 min, Pulse fires haptic, gradient-red banner on hero with "Call shipper now" CTA.

**Pre-cool check.** Before pickup-loading transition, driver confirms box reached within 2°F of set-point. Signature-style swipe.

---

## 12. Vertical add-ons

Trucking surface modulates based on `verticalType`:

- **Flatbed.** Tarp count, strap count, corner protectors, tie-down inspection. Securement photos mandatory at pickup departure. Wind-speed gate: `windGustMph > 40` → storm pause card.
- **Tanker.** SpectraMatch verification (crude 12-parameter assay, 031), detach sequence (032), hose connect/disconnect (042/044), inner-tank wash records. Tanker sub-statuses from `TANKER_LOAD_STATUSES` — client case-folds against `LOAD_STATES`.
- **Auto-hauler.** Multi-unit manifest, VIN scans at pickup/delivery, tie-down check per unit, damage inspection photos both ends.
- **LTL.** Multiple stops with digital stop-list. Each stop has own BOL, POD, detention clock. Client renders as vertical progress list.
- **Livestock.** Animal-welfare logs, feed-and-water stop requirements (per 28-hour rule), temperature tolerance, cross-border USDA VEHCS / CFIA filings.

See [50_Verticals_Reference.md](./../50_Verticals_Reference.md) for complete vertical deep dive.

---

## 13. Settlement + pay — three payout tracks

- **Quickpay / factoring.** Via HaulPay. Settlement purchased at 1–3% discount, funded 24–48h. Eligibility per-load via `factoring.eligibility`. Client renders offer inline on wallet when eligible. **Known bug**: `haulpay.router.ts` `health` double-calls `requireRole` — client guards with role pre-check, surfaces neutral state if errors.
- **Standard.** Weekly batch via `settlementBatching.*`. Me → Settlements. **Note**: `settlementBatching.processBatchPayment` does NOT set `application_fee_amount` — backend landmine, not client concern, but client must not claim "platform fee applied" on standard settlements until fixed.
- **Instant payout.** Stripe Connect Instant Payout to linked debit card, same-day. Fee disclosed in confirm sheet.

**Wallet hero.** Big balance + Available / Pending split + gradient ring. From `wallet.getBalance + money.getSettlements`.

**Tax withholdings (owner-ops).** YTD withheld, quarterly estimate, 1099 download (gated to Jan 31+ of following year).

---

## 14. Safety

**SOS (098).** Side-button long-press on watch OR three-tap on home hero on phone. Opens confirm sheet with 5-second countdown. On commit, `safety.sos`: (1) high-priority notification to carrier safety + dispatcher, (2) opens 911 telephony via `tel://911`, (3) geotags `safetyIncidents` with severity = critical, (4) streams GPS at 5s cadence until driver cancels.

**Fatigue monitoring (Pulse).** HRV + wrist motion. Threshold crossing fires gentle prompt: "You may be fatigued — consider a break." Client never auto-changes duty status based on fatigue; it recommends.

**Crash detection.** Accelerometer + gyroscope + CarPlay. Detected crash triggers SOS flow with 10-second cancel window.

**Emergency protocols.** On confirmed crash/SOS, client locks lifecycle state at current node, creates `safetyIncidents` row, prevents any further transitions until carrier safety manager reopens.

---

## 15. Compliance

- **IFTA quarterly.** Owner-ops + carriers running multi-jurisdiction file quarterly. Client accumulates per-jurisdiction mileage from `gpsTracking` + per-jurisdiction fuel purchases from `fuelTransactions`. Me → Tax → IFTA surfaces running quarterly position. Actual filing is admin-side.
- **150-air-mile exemption.** See §4.
- **Sleeper-berth rules.** 8/2 and 7/3 splits only; 5/5 not legal under property-carrier rules. Client refuses to let driver set 5/5.
- **Personal conveyance limits.** Must be off-duty, CMV, driver personal benefit. Cannot advance load. Subject to carrier policy. Client writes duty-status entries annotated "Personal Conveyance" + PC reason.

---

## 16. Training + onboarding

**First-login wizard.** First time user opens app:
1. Verify CDL number + class + state + expiry (OCR CDL photo, driver confirms).
2. Verify DOT medical card (upload, expiry).
3. Verify TWIC if driver handles port cargo (optional).
4. Verify hazmat endorsement if applicable.
5. Verify FAST / C-TPAT if cross-border.
6. Link vehicle (company-provided → assigned by dispatch; owner-op → driver adds).
7. Link bank account for settlement (Stripe Connect onboarding).
8. Elect payout preference (weekly / quickpay / instant).
9. Enable Pulse watch pairing.
10. Enable location services + background GPS.
11. Enable push notifications.
12. Run first DVIR in training mode.

Each step writes to `drivers.updateProfile / documents.upload / certifications.create`. None skippable; driver cannot accept load until all green.

**Mandatory training modules** (per carrier policy + endorsement): defensive driving (annual), HOS compliance (annual), hazmat general awareness + function-specific + safety + security (triennial, HM-181/HM-232), FSMA (reefer), cargo securement (flatbed), cross-border (international). Client tracks via `certifications`; gradient-orange chip on home when any training within 30 days of expiry, gradient-red inside 7 days.

---

## 17. The Haul gamification

**XP per completed load.** `rewardsEngine` awards XP on each state transition — accept, loaded, delivered, POD — with multipliers for on-time, no-exceptions, clean inspection, streak bonuses. **Known bug**: XP formula duplicated between `rewardsEngine` and `gamificationDispatcher`; streak/prestige multipliers defined but not applied. Client displays XP value server returns — no client-side math.

**Badges.** Long-haul milestone (100k miles, 500k, 1M), cross-border, hazmat, perfect-week, rookie, veteran. Persisted in `gamification.badges`.

**Streaks.** Consecutive on-time delivery, consecutive clean-inspection, consecutive weeks no HOS violations. Me → The Haul → Streaks.

**Leaderboard.** Weekly + monthly, scoped company or global. `gamification.getLeaderboard`.

**Crates.** Display-only per backend gap — no wallet writers. Client renders but must not show any "cash added" toasts. Equip customisation only persists `type = title`; frames / emotes / trailer skins are in-memory only, must surface neutral "saved locally".

**Haul Lobby.** Cross-company chat. Backed by raw-SQL `haul_lobby_*` tables not declared in Drizzle — bootstrapped via `CREATE TABLE IF NOT EXISTS`. Client uses canonical `messages.*` router (see [70_Messaging_and_ESANG_AI.md](./../70_Messaging_and_ESANG_AI.md)), not legacy `messaging.*`.

---

## 18. Wallet flows (8 sections)

For TRUCK::Driver:
1. **Hero balance** — available + pending, gradient ring. `wallet.getBalance`.
2. **Quick actions** — Transfer, Deposit, Withdraw, Card.
3. **Weekly chart** — 7-day bars, gradient fill, from `money.getSettlements` aggregated.
4. **Upcoming settlements** — 3–5 rows, from `settlementBatching.getUpcoming`.
5. **Activity feed** — infinite scroll from `wallet.getTransactions`.
6. **Factoring offer** — conditional on `factoring.eligibility`.
7. **Linked accounts** — bank + debit, masked last-4, from Stripe Connect.
8. **Tax withholdings** — YTD + quarterly + 1099 link, from `taxReporting.mobile.*`.

No mock data. Empty state: graceful "Connect your bank to see activity" when onboarding incomplete.

---

## 19. Messaging

Three canonical surfaces, all on `messages.*` (not `messaging.*`):
- **Dispatcher thread.** 1:1 with driver's assigned dispatcher. Persistent.
- **Broker thread.** Per-load, with broker of record. Auto-created at dispatch accept, auto-archived 30 days after delivery.
- **Haul Lobby.** Cross-company community (raw-SQL, §17).

Pulse surfaces message previews as complications with double-tap to open. Voice dispatch can compose and send.

Push delivery stubbed — register/unregister procedures missing per codebase map. Client exposes Settings notifications toggle but treats as local-only until backend lands.

---

## 20. Pitfalls and edge cases

- **Expired CDL.** `certifications.CDL.expiry < today` → `canDriverAcceptLoad` returns false. Gradient-red banner on home, "Renew now" CTA deep-links to Me → Docs.
- **Failed DOT medical.** `certifications.MEDICAL_CARD.expiry < today` → same. Driver can complete in-flight load but cannot accept new.
- **Suspended authority.** Carrier's FMCSA authority suspended (detected by `fmcsa_carrier_safety`) → every assigned driver's dispatch frozen with banner "Carrier authority suspended — contact fleet manager". Already-accepted loads complete.
- **Customer no-show at pickup.** Detention runs, flips `detention_pending`. After carrier-configured timeout (default 4h past free time), "Request reassignment" CTA fires dispute event.
- **Reefer breakdown in transit.** Deviation > 3°F for > 5 min → `reefer_exception`. Options: "Find nearest reefer repair", "Notify shipper", "File claim". Zeun creates high-severity breakdown.
- **Out-of-service DVIR defect mid-route.** Vehicle flips `status = 'out_of_service'`, load `on_hold`, Zeun surfaces nearest certified shop. Driver cannot resume driving-duty until mechanic-signed inspection clears.
- **Lost connectivity through entire shift.** Local write-ahead queue holds everything. On-device HOS keeps driver legal. Server re-derives totals on reconnect; violation → gradient-red banner referencing exact log timestamps.
- **Hazmat accept without endorsement.** Server rejects. Client "Hazmat endorsement required — open Me → Docs".
- **Cross-border attempt without Carta Porte / ACE / ACI.** Server rejects at `dispatch.accept` with clear reason code. Client deep-links to filing screen.
- **Two co-drivers, one out of hours.** `canDriverAcceptLoad` per-co-driver; stricter result gates. Client shows both HOS rings, marks blocker.
- **Personal conveyance misuse.** If driver uses PC to advance load (geofence direction + PC duration), server logs warning; carrier policy engine may auto-disable PC for that driver.
- **Fatigue crash false positive.** 10-second cancel on SOS sheet. Cancel fires `safety.incidentCancelled`; no carrier notification; event audit-logged.

---

## 21. Non-negotiables for the Driver surface

1. **No mock data.** Every screen wires to real tRPC or shows neutral empty state.
2. **No hard-coded blue.** Gradient (blue → magenta, topLeading → bottomTrailing) is only accent; every toggle uses `GradientToggleStyle()`.
3. **Every duty-status change** goes through `hos.changeStatus` and is echoed to ELD when connected.
4. **Every state transition** geotags server-side via `createGeotag` — client never authorises its own transitions.
5. **Every DVIR photo upload** goes to `documents` with right `docType`.
6. **Every settlement read from server**; client never computes pay.
7. **Offline-first.** Local queue + on-device HOS simulator + pre-cached route + pre-cached ERG.
8. **Pulse parity.** Any action on phone, driver must also be able to take on watch, voice-first where possible.
9. **Persona-agnostic frames.** 010–099 is one screen set; persona and vertical data reshape dynamically.
10. **Legal-first.** HOS, DVIR OOS, CDL expiry, medical expiry, hazmat endorsement — gates, not warnings. Client refuses to proceed, never "just warn and continue."

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
