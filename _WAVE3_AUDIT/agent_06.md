# Wave-3 Agent 06 Audit — Driver Screens 078–089

Scope: 13 Figma screens in `_bucket_06` (Driver app – Home Compliance, Trip History, Certifications, Messages, ESANG Chat, Settings, Schedule, HOS, Fuel Card, Roadside Inspection, DVIR, Maintenance Scheduler, Earnings).

Note: Swift Driver views under `EusoTrip/Views/Driver/` only cover screens 010–022, so every screen in this bucket has **Swift port: NOT PORTED**.

Backend router root: `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/`.

---

## 078 Home Compliance.png
**Swift port:** NOT PORTED (no driver view `078_*` exists; see `Views/Driver/` max `022_DockAssigned.swift`).
**Purpose:** Driver home card summarizing HOS/DOT duty window, 8-day rolling tender-window bar chart, today/tomorrow DVIR badges, next 3 trip chips (origin→dest, rate), ESANG compliance-signal insight, CTA "Open compliance vault".

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| HOS chip "08 ON DUTY 7:52" | Current duty-status + remaining | `hos.getCurrentStatus` (hos.ts:50) | |
| "Driver record" / 8-day window bar chart | Daily drive/duty totals | `hos.getLogHistory` (hos.ts:148) | chart buckets likely client-derived |
| "Tonight's tender stays inside cap" headline | Compliance forecast insight | `esangAIv2.getInsights` (esangAIv2.ts:236) or `compliance.getDashboardSummary` (compliance.ts:638) | narrative copy is ESANG |
| DVIR chips Pre-trip/Post-trip (today) CLEAN | Latest DVIR pass/fail | `inspections.getRecent` (inspections.ts:250) / `inspections.getDVIRHistory` (inspections.ts:317) | |
| Upcoming trip tiles (Wawa, Loves, TA York with $) | Assigned/queued loads with rate | `drivers.getPendingLoads` (drivers.ts:1141) + `loads.getById` (loads.ts:1012) | |
| "05-EU-Q Compliance signal" insight bubble | Compliance narrative | `compliance.getRecentViolations` (compliance.ts:207) + `esangAIv2.getInsights` | |
| "Open compliance vault" CTA | Navigate to docs/certs | `certifications.list` (certifications.ts:25) + `documentManagement.*` | nav-only |
| Bottom tab bar (Home / Trips / ESANG / Wallet / Me) | Navigation | n/a | client routing |

### Backend GAPS
1. No dedicated "driver home summary" aggregator procedure that bundles HOS + DVIR + next loads + compliance signal in one round-trip.
2. Rolling 8-day HOS window bar-chart buckets are not exposed; only raw `hos.getLogHistory` rows — aggregation is client-side.

### User-journey entry points
- Post-login → Driver Home (default tab).
- Deep link from push notification (`push.ts`) for compliance/HOS alerts.
- Required state: authenticated driver user, active `drivers` row, recent `hos_logs`, today's `dvir_reports`.

---

## 078 Trip History.png
**Swift port:** NOT PORTED.
**Purpose:** "Trip History" tab with period totals (loads, miles, net pay, score), segmented period filter (This week / This month / Quarter / YTD / Hazmat only), scrollable rows of completed trips (date, origin→dest, $, status badges SETTLED/POSTING), ESANG insight, Filter + Export PDF buttons.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Period totals card (24 loads / 9,180 mi / $28,940 / score 94) | Aggregates for period | `loads.getHistoryStats` (loads.ts:1316) + `earnings.getYTDSummary` (earnings.ts:244) | score is unclear — likely `carrierScorecard.*` |
| Period pill group (Week/Month/Quarter/YTD/Hazmat only) | Filter param | `loads.getHistory({period})` (loads.ts:1338) | "Hazmat only" filter param unsupported by schema — GAP |
| Trip rows | List of completed loads | `loads.getHistory` (loads.ts:1338) / `drivers.getCompletedTrips` (drivers.ts:1239) | |
| Status badges (SETTLED/POSTING) | Settlement status per load | `earnings.getSettlementHistory` (earnings.ts:265) | join on client |
| ESANG insight ("most consistent lane") | Pattern insight | `esangAIv2.getInsights` (esangAIv2.ts:236) | GAP for lane-specific pattern |
| Filter button | Opens filter sheet | n/a | client |
| Export PDF button | Export trip history | GAP | no `loads.exportHistory`; `exports.ts` is tenant-level |
| Bottom tab bar | Nav | n/a | |

### Backend GAPS
1. `loads.getHistory` input lacks `hazmat=true` filter; needs schema extension.
2. Driver trip-history PDF export procedure missing (no `loads.exportDriverHistory` / `earnings.exportDriverTrips`).
3. "Lane pattern / most consistent lane" narrative not a first-class procedure.

### User-journey entry points
- Bottom nav TRIPS tab.
- Deep link from settlement notification.
- Required state: driver with completed `loads` + `settlements`.

---

## 079 Certifications Documents.png
**Swift port:** NOT PORTED.
**Purpose:** Driver CDL header card (class, issue/exp, endorsements H N T X), tile grid (exp-soon/medical/tags/hazmat days), scrollable list of certifications (NH₃₂083 cargo-tank, defensive driving, tanker endorsement, DOT medical card, MVR+PSP pull) with status (CURRENT / IN 41D / CLEAN), ESANG renewal insight, CTAs "Book renewal" / "Upload document".

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| CDL header (class, exp, endorsements) | Driver qualification | `driverQualification.*` (driverQualification.ts) + `drivers.getById` (drivers.ts:378) | |
| Tile summary (847/274/1,143/108) | Totals (loads/medical/tags/hazmat days?) | `certifications.getSummary` (certifications.ts:93) | |
| Certification list rows | Certs with expiry | `certifications.list` (certifications.ts:25) | |
| Status badges CURRENT/IN 41D/CLEAN | Expiry state | `certifications.getExpiring` (certifications.ts:212) | |
| ESANG hazmat re-fingerprint insight | Renewal reminder narrative | `certifications.sendRenewalReminder` (certifications.ts:308) + `esangAIv2.getInsights` | |
| "Book renewal" button | Schedule renewal | GAP | no `certifications.bookRenewal` / IdentoGO appointment |
| "Upload document" button | Upload file | `certifications.uploadDocument` (certifications.ts:263) | |
| Bottom tabs | Nav | n/a | |

### Backend GAPS
1. No "book renewal appointment" procedure (e.g., IdentoGO/TSA Hazmat fingerprint scheduler integration).
2. No endorsement-level CRUD on CDL (drivers router exposes drivers but endorsements are flat strings).

### User-journey entry points
- Home "Open compliance vault" CTA (from screen 078).
- Push alert for expiring cert.
- Required state: `drivers.cdl*`, `certifications` rows with `expiryDate`.

---

## 080 Messages Inbox.png
**Swift port:** NOT PORTED.
**Purpose:** Search bar, filter chips (All / Dispatch / Shippers / Brokers / ESANG), message rows (sender, snippet, timestamp, unread count, tag DISPATCH/EASTLAND/COMPLIANCE COACH), ESANG summary insight, "Mark all read" + "New message" CTAs.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Search bar | Search messages | `messages.search` (messages.ts:610) | |
| Filter chips (All/Dispatch/Shippers/Brokers/ESANG) | Channel filter | `messages.listConversations` (messages.ts:847) w/ filter | ESANG channel filter not explicit — GAP (ESANG lives in `esangAIv2`) |
| Conversation rows | List | `messages.getConversations` (messages.ts:45) | |
| Unread badges | Unread count per convo | `messages.getUnreadCount` (messages.ts:573) | |
| ESANG insight tile | Summary narrative | `esangAIv2.getInsights` (esangAIv2.ts:236) | |
| "Mark all read" | Bulk mark read | `messages.markAsRead` (messages.ts:531) | |
| "New message" | Compose | `messages.createConversation` (messages.ts:455) + `messages.searchUsers` (messages.ts:758) | |

### Backend GAPS
1. No typed channel enum (`dispatch|shipper|broker|esang`) on conversation filter.
2. No bulk-mark-all-read across all conversations at once — current `markAsRead` is per-conversation.

### User-journey entry points
- Home header bell → Inbox.
- Push message notification tap.
- Required state: `conversations` rows linked to driver userId.

---

## 081 ESANG Chat Panel.png
**Swift port:** NOT PORTED.
**Purpose:** ESANG "Day Coach" live panel with status pill (WAWA DROP CONFIRMED / NH3 CLOSED), threaded chat bubbles w/ tool-call traces (e.g., `dispatch.getNextAssignment(driverId=..)` → RESOLVED), structured fuel-stop recommendation card, action chips ("Reroute to Pilot" / "Skip the reset" / "Confirm fuel + reset"), chat input with attachments.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Chat history thread | Prior turns | `esangAIv2.getHistory` (esangAIv2.ts:183) | |
| Send user message | Send + LLM response | `esangAIv2.chat` (esangAIv2.ts:66) | |
| Tool-call badges (e.g., `dispatch.getNextAssignment`) | Surfaces tool traces | GAP | no `esangAIv2.getToolTrace` or chat.returnToolCalls in chat payload |
| "Best fuel within 12 mi" card with TA Carlisle details | Structured fuel recommendation | `fuel.getNearbyStations` (fuel.ts:351) + `fuel.getCurrentPrices` (fuel.ts:66) | |
| "Reroute to Pilot" action | Trigger reroute | `navigation.*` / `routeOptimization.*` | GAP: no direct "reroute" procedure exposed |
| "Skip the reset" action | HOS override/acknowledge | GAP | no `hos.skipReset`; at best `hos.addRemark` (hos.ts:196) |
| "Confirm fuel + reset" action | Accept recommendation | GAP | no `esangAIv2.actOnRecommendation` procedure (only `actOnInsight`) |
| Mic + send button | Voice input/submit | `esangVoice.speak` (esangVoice.ts:59) + `voiceESANG.*` | |
| Status pill live | Realtime status | GAP | no SSE/WebSocket subscription yet in router |

### Backend GAPS
1. `esangAIv2.chat` does not return tool-call traces in a typed structure UI can render.
2. No first-class "rerouting" action endpoint (only read-only routing queries).
3. `hos.skipReset` / skip-restart-break endpoint missing.
4. No "apply ESANG recommendation" mutation returning downstream state transitions.
5. No live/streaming chat subscription procedure.

### User-journey entry points
- Bottom nav ESANG tab (center icon).
- From Home insight → "Explain" deep link.
- Required state: `esang_conversations` + `esang_messages` rows; `hos`, `loads`, `fuel` state for tool-calls.

---

## 082 Settings Privacy.png
**Swift port:** NOT PORTED.
**Purpose:** Settings screen with groups Appearance (Theme Auto/Light/Dark, Text size), Notifications (Dispatch alerts / Shipper pings / Broker rate pitches / ESANG proactive), Units & Voice (Distance MILES/KM, Temperature F/C, Voice coach), Privacy & Data (Location sharing, Export my data, Sign out all devices), ESANG footer insight.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Theme Light/Dark/Auto | Display prefs | `settings.updateDisplaySettings` (settings.ts:89) + `users.updatePreferences` (users.ts:341) | |
| Text size | Display prefs | `settings.updateDisplaySettings` (settings.ts:89) | |
| Notification toggles (Dispatch/Shipper/Broker/ESANG) | Per-channel notif settings | `settings.updateNotificationSettings` (settings.ts:69) + `users.updateNotifications` (users.ts:1079) | |
| Distance / Temperature unit toggles | Unit prefs | `users.updatePreferences` (users.ts:341) | GAP: no dedicated temperature-unit field on server |
| Voice coach toggle | Voice setting | `esangVoice.getMyVoice` (esangVoice.ts:42) + settings pref | partial |
| Location sharing "On Duty" segment | Privacy setting | `settings.updatePrivacySettings` (settings.ts:109) | |
| "Export my data" request | Data export | `settings.exportData` (settings.ts:245) / `users.exportPersonalData` (users.ts:664) | |
| "Sign out all devices" | Terminate sessions | `users.terminateAllSessions` (users.ts:799) | |
| ESANG insight footer | Insight | `esangAIv2.getInsights` | |

### Backend GAPS
1. Temperature unit (F/C) not a recognized key in `users.updatePreferences` schema (only distance/locale common).
2. Per-notification-channel granularity (dispatch vs shipper vs broker vs ESANG) not explicit on `updateNotificationSettings`; needs enum.
3. "Voice coach" toggle has no dedicated settings procedure linking users→ESANG voice on/off.

### User-journey entry points
- Me tab → Settings.
- Required state: `user_preferences`, `user_sessions`.

---

## 083 Schedule Availability.png
**Swift port:** NOT PORTED.
**Purpose:** Weekly schedule (Apr 13–19) with day chips (on/off), today's duty bar chart (Marcus, Wawa segments), 7-day upcoming assignments (date, origin→dest, miles, tag NH3/SPOT/FUEL/SHOP), ESANG lock-utilization insight, CTAs "Block time" / "Set availability".

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Week date chips | Calendar navigation | n/a (client) | |
| "72% UTILIZED" badge | Utilization metric | GAP | no `drivers.getUtilization` procedure |
| Today duty bar (Marcus/Wawa segments) | Duty-status timeline | `hos.getDailyLog` (hos.ts:116) | |
| Upcoming assignments list | Next 7 days | `drivers.getPendingLoads` (drivers.ts:1141) + `drivers.getCurrentAssignment` (drivers.ts:751) | GAP: no "next 7 days schedule" aggregator |
| Tag chips (NH3/SPOT/FUEL/SHOP) | Load type/purpose | `loads.getById` (loads.ts:1012) | derived client-side |
| ESANG insight | Narrative | `esangAIv2.getInsights` | |
| "Block time" button | Mark unavailable window | GAP | no `drivers.blockTime` / `availability.block` |
| "Set availability" button | Set on/off days | GAP | no `drivers.setAvailability` |

### Backend GAPS
1. Driver availability model missing entirely — no availability table / router (confirmed by grep: no `availability` nor `setAvailability` matches).
2. Utilization % metric not exposed.
3. No 7-day schedule aggregator combining `loads` + blocked time.

### User-journey entry points
- Me tab → Schedule, or Home "Upcoming" tile tap.
- Required state: `loads.assignedDriverId` rows + future `driver_availability` (not yet modeled).

---

## 084 HOS Status ELD Logs.png
**Swift port:** NOT PORTED (non-driver-active version; overlaps conceptually with `019_HosDutyStatus.swift` but that is mid-trip).
**Purpose:** HOS dashboard — current status card (On-Duty / Off-Duty with timer), segmented status switch (Off-Duty / Sleeper / Driving / On-Duty), three dials (Drive 5:00/5:03/18:45 remaining), today's ELD graph, recent entries list (Wawa drop close, Depart Marcus Hook, etc.), ESANG cushion insight.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Status header (On-Duty since HH:MM) | Current duty status | `hos.getCurrentStatus` (hos.ts:50) | |
| ELD SYNCED / HOS ETTODAYGRAPH badges | Provider sync state | `eld.getDriverStatus` (eld.ts:232) + `eld.getConnectionStatus` (eld.ts:456) | |
| Status switch (Off-Duty / Sleeper / Driving / On-Duty) | Change duty status | `hos.changeStatus` (hos.ts:95) | |
| Three dials (Drive/Shift/Cycle remaining) | Hours remaining | `hos.getCurrentStatus` (hos.ts:50) / `drivers.getHOSAvailability` (drivers.ts:1254) | |
| Today graph | ELD log chart | `hos.getDailyLog` (hos.ts:116) + `eld.getLogs` (eld.ts:163) | |
| Recent entries list | Duty-status event log | `hos.getLogHistory` (hos.ts:148) | |
| Entry row status badges (OD/D/ON) | Log row state | derived | |
| ESANG cushion insight | Narrative | `esangAIv2.getInsights` | |

### Backend GAPS
1. No explicit procedure to "certify today's log" from this view; `hos.certifyLog` (hos.ts:187) exists but not obviously reached from this layout (no Certify button in Figma).
2. No direct "annotate entry / add remark from history row" on this screen; `hos.addRemark` exists but not linked.

### User-journey entry points
- Home HOS chip tap.
- Me tab → HOS.
- ESANG tool-call deep link.
- Required state: active `hos_duty_log` + connected `eld_provider`.

---

## 085 Fuel Card.png
**Swift port:** NOT PORTED.
**Purpose:** Virtual fuel-card UI (EUSOTRIP FLEET, card #4418, driver name, exp 07/29), cycle spend $1,477.26 with "-$66 saved", metrics (gallons 377, avg $3.92, stops 4, saved -$66), recent fuel transactions (TA Carlisle pending, Pilot Florence, Pilot Tampa, Love's Carlisle, Pilot Allentown w/ $ delta), ESANG pump-savings insight, CTAs "Block card" / "Find fuel".

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Card header (number, driver, exp) | Card metadata | `fuelCards.list` (fuelCards.ts:15) + `fuel.getFuelCards` (fuel.ts:206) | |
| Cycle spend / vs market saving | Period summary | `fuelCards.getSummary` (fuelCards.ts:35) + `fuel.getSummaryDetailed` (fuel.ts:149) | |
| Metric tiles (Gallons/Avg/Stops/Saved) | Aggregated metrics | `fuel.getEfficiencyReport` (fuel.ts:189) + `fuelCards.getSummary` (fuelCards.ts:35) | |
| Recent transactions list | Purchase history | `fuelCards.getRecentTransactions` (fuelCards.ts:65) + `fuel.getTransactions` (fuel.ts:116) | |
| Txn price/delta green badges | Price vs market | `fuel.getCurrentPrices` (fuel.ts:66) compared client-side | GAP: no "savings per txn" field |
| ESANG pump savings insight | Narrative | `esangAIv2.getInsights` | |
| "Block card" | Freeze card | `fuelCards.toggleStatus` (fuelCards.ts:88) / `fuel.toggleCard` (fuel.ts:385) | |
| "Find fuel" | Navigate to nearest station | `fuel.getNearbyStations` (fuel.ts:351) | |

### Backend GAPS
1. No per-transaction "vs market price delta" field computed server-side.
2. "Pending" txn status not modeled on fuel-card txn (only settled/recorded).
3. No "request temporary lift / raise limit" procedure (card controls are binary block/unblock).

### User-journey entry points
- Wallet tab → Fuel Card, or Home ESANG fuel-stop recommendation → Card.
- Required state: `fuel_cards` row, `fuel_transactions` rows for period.

---

## 086 Roadside Inspection Assist.png
**Swift port:** NOT PORTED.
**Purpose:** Inspection-readiness dashboard — 11/12 or 12/12 "flagged/ready" score, hazmat FP renewal countdown, category groups (CDL & Medical, Truck reg+ins, Trailer reg+ins, IFTA+IRP, Hazmat+Ship-papers, BOL+Manifest) each with count and check, recent inspections list (VA State Police Winchester, PA Carlisle, GA DOT Jackson) with CLEAN badges, ESANG renewal insight, CTAs "Practice" / "Inspector mode".

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Overall readiness score (11/12 or 12/12) | Bundle status | GAP | no "roadside readiness" aggregator procedure |
| Hazmat FP renewal days | Cert countdown | `certifications.getExpiring` (certifications.ts:212) | |
| Category tiles (CDL/Truck/Trailer/IFTA/Hazmat/BOL) | Bundle per category | GAP (piecewise): `certifications.list` + `vehicles.getDocuments` (vehicles.ts:266) + `bol.*` | no single "inspectionBundle.get" procedure |
| Recent inspections list | Roadside inspection history | `inspections.list` (inspectionForms.ts:20) / `compliance.getAuditHistory` (compliance.ts:914) | GAP: no `roadsideInspections` table/router distinct from DVIR |
| CLEAN badges | Outcome per inspection | derived from inspection row | |
| ESANG insight | Narrative | `esangAIv2.getInsights` | |
| "Practice" button | Mock inspection flow | GAP | no `inspections.startPractice` |
| "Inspector mode" button | Present credentials | GAP | no "inspector presentation" procedure / QR token |

### Backend GAPS
1. No first-class roadside-inspection entity (separate from DVIR) — no router for Level 1/2/3 roadside events.
2. No "readiness bundle" procedure aggregating all documents needed at the scale.
3. No "Inspector Mode" token issuance (QR / short-lived credential packet).
4. No "practice inspection" simulator procedure.

### User-journey entry points
- Home "Open compliance vault" CTA → Inspection assist.
- Push on entering known weigh-station geofence (`geofencing.ts`).
- Required state: driver CDL/med card, vehicle reg/ins, active BOL for current load.

---

## 087 DVIR Builder.png
**Swift port:** NOT PORTED (standalone builder). Pre-trip creation covered partially by `011_PretripDVIR.swift` + `012_DvirSubmitted.swift` but this is a richer unified builder.
**Purpose:** DVIR form — tab Pre-trip / Post-trip (SUBMITTED), tractor/trailer pickers (EP-T-1840 / EP-L-2207), 8 category checkbox tiles (Brakes, Lights, Tires, Coupling, Emergency kit, Cargo securement, Fluid levels, NH3 coupler), signature capture block with timestamp, recent reports list, ESANG queue insight.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Pre-trip / Post-trip tabs | Report type | `inspections.getTemplate({type})` (inspectionForms.ts:42) | |
| Tractor/Trailer picker | Vehicle selection | `drivers.getAssignedVehicle` (drivers.ts:910) + `vehicles.list` (vehicles.ts:26) | |
| Category tiles (8) with pass/fail | Inspection items | `inspections.getDVIRCategories` (inspectionForms.ts:366) | |
| "8/8 inspected" counter | Progress tracker | client-derived | |
| Signature capture + timestamp | Driver e-signature | `signatures.*` (signatures.ts) + `inspections.submit` (inspectionForms.ts:82) | |
| Submit button (implicit) | Create DVIR | `inspections.createDVIR` (inspectionForms.ts:279) / `drivers.submitDVIR` (drivers.ts:978) | |
| Report defect flow | File defect | `inspections.reportDefect` (inspectionForms.ts:125) | |
| Recent reports list | Past DVIR rows | `inspections.getDVIRHistory` (inspectionForms.ts:317) + `drivers.getLastInspection` (drivers.ts:933) | |
| Status badges (SUBMITTED/REPAIRED) | Defect/review state | `inspections.reviewDVIR` (inspectionForms.ts:340) | |
| ESANG queue insight | Narrative | `esangAIv2.getInsights` | |

### Backend GAPS
1. `inspections.createDVIR` requires `odometerMiles` and `overallCondition` but Figma does not show an odometer field — mismatch (either UI gap or hidden field).
2. Trailer DVIR binding is informal — schema does not have explicit `trailerId` column on `dvir_reports` per create input.
3. No "saved draft" procedure; abandoned builds are lost.

### User-journey entry points
- Home DVIR chip → Builder.
- Pre-trip checklist at shift start.
- Required state: driver assigned to a tractor/trailer; inspection templates seeded.

---

## 088 Maintenance Shop Scheduler.png
**Swift port:** NOT PORTED.
**Purpose:** Vehicle maintenance card (EP-T-1840 2024 Volvo VNL 760, HEALTHY badge), odometer / best MPG / engine hrs, active ticket (SR-2049 PM-A + NH₃ coupler recert), due date Wed Apr 22 06:00 CONFIRMED, parts list with IN STOCK flags, stat tiles (Last mi since PM, etc.), recent service rows (PM-B DPF regen, DOT inspection, tire rotation), ESANG "add wash-out" insight, CTAs "Report defect" / "Manage appointment".

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Vehicle header (ID, year, model, HEALTHY) | Vehicle record + health | `vehicles.get` (vehicles.ts:57) + `fleetMaintenance.getMaintenanceDashboard` (fleetMaintenance.ts:156) | |
| Stat tiles (odometer / best MPG / engine hrs) | Telemetry | `fleetMaintenance.getFuelEfficiency` (fleetMaintenance.ts:1510) + `vehicles.get` | |
| Active service ticket | Open work order | `fleetMaintenance.getWorkOrders` (fleetMaintenance.ts:492) | |
| Parts list w/ IN STOCK | Work-order parts | `fleetMaintenance.getPartsInventory` (fleetMaintenance.ts:722) | |
| Stats strip (Last mi / miles since PM) | PM countdown | `fleetMaintenance.getPreventiveSchedule` (fleetMaintenance.ts:350) | |
| Recent service list | Repair history | `maintenance.getHistory` (maintenance.ts:132) + `fleetMaintenance.getRepairHistory` (fleetMaintenance.ts:650) | |
| ESANG wash-out insight | Narrative | `esangAIv2.getInsights` + `maintenance.schedule` (maintenance.ts:184) | |
| "Report defect" | Log vehicle defect | `inspections.reportDefect` (inspectionForms.ts:125) | |
| "Manage appointment" | Book / change shop slot | `maintenance.schedule` (maintenance.ts:184) / `fleetMaintenance.createWorkOrder` (fleetMaintenance.ts:437) | partial; see gaps |
| "Confirmed" badge on ticket | Shop confirmation | GAP | no explicit `confirmAppointment` mutation |

### Backend GAPS
1. No dedicated "shop appointment" entity (shop identity, dock/bay, appt window) — current schedule is flat on the work order.
2. No procedure to confirm/reschedule/cancel shop appt as a distinct mutation (`maintenance.updateStatus` is generic).
3. Parts "ETA if out of stock" not surfaced by `getPartsInventory`.

### User-journey entry points
- Me / Wallet tab → Maintenance.
- DVIR defect → "Schedule shop" CTA.
- Required state: `vehicles` row, optional open `work_orders`, parts inventory seeded.

---

## 089 Earnings Detail.png
**Swift port:** NOT PORTED.
**Purpose:** Pay-period card (Apr 13–Apr 26, wk 1 of 2), status OPEN, net est $2,932, gross / loads settled / deposit date, line-items (trip pay by day with lane + net mi + $), adders (Hazmat premium, Fuel surcharge, Detention), deductions (Federal, FICA+Medicare, PA state tax, Equipment lease), running NET, YTD stats strip (YTD NET / YTD MI / YTD loads / % goal).

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Pay-period header (dates, wk, status) | Current settlement period | `earnings.getSummary` (earnings.ts:24) + `earnings.getWeeklySummary` (earnings.ts:136) | |
| Net estimate / gross / loads settled / deposit date | Aggregates | `earnings.getWeeklySummary` (earnings.ts:136) + `earnings.getPayStatement` (earnings.ts:224) | |
| Trip pay line-items | Per-load settled pay | `earnings.getEarnings` (earnings.ts:95) / `earnings.list` (earnings.ts:178) | |
| Adders (Hazmat premium, Fuel surcharge, Detention) | Accessorials | `detentionAccessorials.*` + `fscEngine.*` + `accessorial.*` | GAP: no single "adder rollup" procedure |
| Deductions (Federal, FICA, State, Equipment lease) | Payroll deductions | `payroll.*` | GAP: driver-facing deductions breakdown not exposed as a procedure in earnings router |
| Running NET | Computed | client-derived | |
| YTD stats (YTD NET / YTD MI / YTD loads / % goal) | Yearly aggregates | `earnings.getYTDSummary` (earnings.ts:244) | GAP: "% goal" requires goals table |
| % goal badge (+$340) | Goal delta | GAP | no `earnings.getGoal` / `users.setEarningsGoal` |
| OPEN status pill | Settlement state | `earnings.getSettlementById` (earnings.ts:269) | |

### Backend GAPS
1. Driver-facing deductions detail (federal, FICA, state, lease) is not surfaced through `earnings.*`; `payroll.ts` is employer-oriented.
2. No "adders rollup" procedure combining hazmat/FSC/detention for a settlement.
3. No driver-facing earnings-goal CRUD (`setEarningsGoal` / `getGoal`), so "% goal" cannot be backed.
4. Settlement `OPEN` vs `POSTING` vs `SETTLED` vocab not documented in driver-facing enum on `earnings.getSettlementHistory`.

### User-journey entry points
- Wallet tab → Earnings.
- Home period-ending push.
- Required state: `settlements`, `settlement_line_items`, `payroll_deductions`, `earnings_goals` (missing).

---

## Summary
- **Screens audited:** 13
- **Distinct UI elements mapped:** ~125
- **Elements with a backing procedure:** ~92 (≈74%)
- **GAP elements:** ~33 (≈26%)
- **% backed (screen-level, elements):** ~74%
- **Swift ports present:** 0/13 (all NOT PORTED — Swift Driver views stop at 022).

**Top-3 gap themes:**
1. **Driver availability / scheduling model is absent** (083 Schedule). No `availability` table, no `blockTime`/`setAvailability` procedures, no utilization metric, no 7-day schedule aggregator.
2. **Roadside-inspection and inspector-presentation stack is missing** (086). No roadside-inspection entity separate from DVIR, no readiness-bundle aggregator, no Inspector-Mode credential-packet / QR procedure, no practice-inspection simulator.
3. **Driver-facing settlement composition is thin** (089). Deductions, adders, earnings goals, and "% goal" are not exposed through `earnings.*`; ESANG "apply recommendation" actions (081) and compliance-signal summary (078) also lack typed mutations and aggregators.

**Cross-cutting secondary gaps:**
- ESANG chat lacks typed tool-call traces and action-application mutations (081).
- No driver trip-history PDF export endpoint (078 Trip History).
- Certifications renewal booking (IdentoGO-style appointment) not modeled (079).
- No `bookShopAppointment` / confirm mutation on maintenance scheduler (088).
- Notification-channel enum + temperature-unit preference missing on settings (082).
