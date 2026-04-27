# Wave-3 Agent 03 — Driver bucket 049-061

Scope: 13 Driver screens (`049 Task Result` through `061 Earnings and Pay`).
Swift ports: **none exist** for this range — Swift port folder stops at `022_DockAssigned.swift`.
Backend router root: `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/`
Schema: `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/drizzle/schema.ts`

Convention: "GAP" = no router/schema match found via grep. All cited router files use `protectedProcedure` / `auditedOperationsProcedure` / `auditedProtectedProcedure` aliases; the `router.procedure` column uses the router export name.

---

## 049 Task Result.png
**Swift port:** GAP (none in `EusoTrip/Views/Driver/`).
**Purpose:** Post-arm-3-active "Spectra-Match pre-read closed" task result — shows match %, scan elapsed, finding rows (Cartridge seated, OPTRX scan, Comparator vs RBOB ref, Auto-file to load card), a dispatcher sign acknowledgement, plus View report and "Submit + open brief" CTAs.

### UI elements -> backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Status chip "Spectra-Match - pre-read closed · MATCH" | Product/crude match result | `spectraMatch.identify` / `spectraMatch.identifyWithAI` | `routers/spectraMatch.ts:36,188` |
| 99.94% RBOB MATCH (target 99.8%) | Match score | `spectraMatch.getCrudeSpecs` | `routers/spectraMatch.ts:298` |
| Residual HC / PPM / Sulfur tiles | Lab output values | `spectraMatch.saveToRunTicket` (inputs) | `routers/spectraMatch.ts:332` |
| Findings 4 rows (Cartridge seated, OPTRX scan 280-2500 nm, Comparator vs RBOB ref, Auto-file to load card) | Spectra sensor checklist | GAP | No `spectraFindings`/`sensorRun` procedure found |
| Buckeye Dispatch · Malvern badge "dispatcher-approved · arm 3 live" | Dispatch approval state | `dispatch.*` / `autopilot.layer.ts` | autopilot layer is only approx match |
| Dispatcher signature row "Michael Eusorone 13:19 ET · tap to sign" | Signature capture | GAP | No `signatures.signTask` procedure found |
| View report button | Fetch report PDF | GAP | Likely `runTickets.export` (`routers/runTickets.ts:282`) |
| Submit + open brief button | Close task, open next brief | `runTickets.complete` + `loads.updateLoadStatus` | `routers/runTickets.ts:215`, `routers/loads.ts:2774` |
| Tab bar (Home/Trips/ESANG/Wallet/Me) | Navigation | n/a | UI-only |

### Backend GAPS
1. Spectra-Match "findings rows" (cartridge seat, OPTRX scan, comparator, auto-file) — no line-item router; `spectraMatch` exposes identify/save but no findings schema.
2. Dispatcher signature capture procedure missing.
3. Task result composite object (task header + findings + ack) — no `tasks.getResult` in any router file.

### User-journey entry points
- From 048 Arrival-Gate Task Active -> task completes -> this screen.
- Requires backend state: load assigned (`loads`), run ticket open (`runTickets.list`), spectra match run (`spectraMatch.saveToRunTicket`), dispatcher online (`dispatch.*`).

---

## 050 Next Beat Live.png
**Swift port:** GAP.
**Purpose:** Live bottom-load arm 3 fill progress (3,240/8,400 gal, 38%), ESANG terminal ops watch list, ETA, product temp/tank PSI, Pause fill / View fill report CTAs.

### UI elements -> backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Fill progress ring 38% · 8,400 gal | Live telemetry | GAP | No `runTickets.liveFill` / `telemetry.bottomLoad` |
| Loading RBOB #2 · arm 3 active chip | Current arm state | GAP | Terminal arm state not in any router |
| Flow 640 GPM / Product temp 62°F / Tank PSI 0.3 | Live sensor readings | GAP | Closest is `telemetry.ts` but no procedure exposes fill metrics |
| "What terminal ops is watching" checklist (Grounding brief closed · Full arm released · BOL stub pre-filled) | Operator checkpoint log | GAP | No `terminalStaff` procedure emits checklist per load |
| ESANG sidebar text | AI commentary | `esangAI.getRecent` | `routers/esangAI.ts:288` |
| Pause fill button | Mutation to pause arm | GAP | No `runTickets.pauseFill` |
| View fill report button | Run ticket detail | `runTickets.getById` | `routers/runTickets.ts:241` |

### Backend GAPS
1. Live fill telemetry (flow, PSI, temp, percent) has no procedure.
2. Terminal ops watchlist (checkpoints per arm/ticket) missing.
3. "Pause fill" mutation missing.
4. Arm-level loading state (`arm 3 active`) missing.

### User-journey entry points
- From 049 Task Result (Submit + open brief) -> this live load view.
- Requires: run ticket in `runTickets` status=open, arm assigned, telemetry feed from terminal gateway.

---

## 051 Beat Complete.png
**Swift port:** GAP.
**Purpose:** Load complete (8,398 gal net, BOL issued with seal numbers), departure queue with next stops, Share BOL and Depart rack CTAs.

### UI elements -> backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| "Load complete" pill + 8,398 net gal | Final volumes | `runTickets.calculateRunTicketVolumes` | `routers/bol.ts:796` |
| "Bill of Lading · e-issued" card | BOL issuance | `bol.generateBOLFromLoad` | `routers/bol.ts:1067` |
| UN1203 RBOB E10 / Net gallons 8,398 @ 60°F | BOL fields | `bol.generateRunTicket` | `routers/bol.ts:612` |
| Seal number SEAL-WAW-11207 | Seal capture | GAP | No seal field in `runTickets` (schema not exposing) |
| BOL hash WAW-23117-C44F-2B71 | Tamper hash | `documentHashes` table | `drizzle/schema.ts:1006` — no router procedure |
| Post-read 99.96% / over/short -2 / time at rack 21m | QC metrics | GAP | No `qcResults` router |
| Queued after depart list (Malvern, transit 72 mi, arrive Wawa York) | Route queue | `loads.getTimeline` | `routers/loads.ts:1507` |
| Share BOL button | Share PDF | `bol.generate` | `routers/bol.ts:374` |
| Depart rack button | Status update | `loads.updateLoadStatus` / `drivers.updateLoadStatus` | `routers/loads.ts:2774`, `routers/drivers.ts:857` |

### Backend GAPS
1. Seal number capture missing as first-class procedure.
2. Document hash expose (`documentHashes` table exists but no router returns hash for a load).
3. QC post-read metrics (%match, over/short, time-at-rack) no procedure.
4. Depart-rack trigger (beyond generic `updateLoadStatus`) — no dedicated rack-depart geofence trigger.

### User-journey entry points
- From 050 Next Beat Live (fill complete) -> BOL issued -> this screen.
- Requires: run ticket completed, BOL generated, next leg queued on `loads.getTimeline`.

---

## 052 Ratecon Tender.png
**Swift port:** GAP.
**Purpose:** Rate confirmation card for current leg (Buckeye Malvern -> Wawa York), $612 rate, Linehaul/Fuel/Accessorials breakdown, EIN company card, Back to trip / View PDF.

### UI elements -> backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Accepted · In-Flight chip | Tender state | `rateConfirmations.getById` | `routers/rateConfirmations.ts:15` |
| $612 · 0.50/mi · 72 mi · Gasoline RBOB | Linehaul rate | `rateSheet.calculateRate` | `routers/rateSheet.ts:812` |
| Lane Buckeye Malvern -> Wawa York | Stops | `loads.getById` | `routers/loads.ts:1012` |
| Rate breakdown rows: Linehaul $450, Fuel surcharge $118, Accessorials $44 | Components | `rateSheet.getPlatformFeeSchedule` / `accessorial.getFeeSchedule` | `routers/rateSheet.ts:1664`, `routers/accessorial.ts:409` |
| Total to driver $599.76 | Net | `earnings.getEarnings` | `routers/earnings.ts:95` |
| Shipper "Wawa Fuel Logistics · Direct · 3pl · A+" | Shipper card | `shippers.*` / `shipperScorecard` | shipperScorecard router exists |
| ESANG banner "haulPay settles T+2 after POD" | Payment timeline | `factoring.getSummary` | `routers/factoring.ts:981` |
| View PDF button | PDF export | `rateConfirmations.send` (assumes PDF) | `routers/rateConfirmations.ts:19` |
| Back to trip button | Nav | n/a | |

### Backend GAPS
1. `rateConfirmations` router is a stub (4 procedures, all returning empty data — see file lines 13-23). No real persistence.
2. No lane-level in-flight status ("in-flight" vs "accepted") procedure.
3. Accessorial line items per load (on the tender) — `accessorial.getLoadExpenses` exists but not exposed as tender line array.

### User-journey entry points
- From 051 Beat Complete (Depart rack) or from load offer -> tap current leg -> tender card.
- Requires: load with ratecon record, shipper scorecard, earnings precomputed.

---

## 053 ESANG Dispatch Chat.png
**Swift port:** GAP.
**Purpose:** Chat thread with ESANG AI assistant for load WAW-23117, suggested replies, quick chips (Pre-arm-drop, Call store, Photo dock on arrival, Accept tender, Show radar, Counter offer), message composer.

### UI elements -> backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Header ESANG + BOL / ETA / mileage chips | Conversation meta | `messages.getConversation` | `routers/messages.ts:800` |
| Message thread (AI + driver bubbles) | Messages | `messages.getMessages` / `messages.sendMessage` | `routers/messages.ts:186,279` |
| Parsed dock staging card "Wawa #8077 dock 4 Open" | AI-structured attachment | `esangAI.execute` / `esangVoiceOrchestrator` | `routers/esangAI.ts:460` |
| Suggested reply chips (Pre-arm-drop / Call store / Photo dock on arrival) | AI action chips | GAP | No `esangAI.getSuggestedReplies` procedure |
| Quick chips (Accept tender / Show radar / Counter offer) | Quick actions | `loads.acceptBid`/`negotiations.*` | partial coverage in `negotiations.ts` |
| Mic / send buttons | Voice / text send | `esangVoice.speak` / `messages.sendMessage` | `routers/esangVoice.ts:59` |
| Tab bar | Nav | n/a | |

### Backend GAPS
1. Suggested reply generator (chips under thread) — no procedure.
2. Inline action chips producing tender accept/counter from chat — no unified action router.
3. Structured message attachment (dock staging card) schema — `messageAttachments` table exists (schema.ts:2571) but no router returns the typed card payload.

### User-journey entry points
- From tab bar (ESANG), or from tender "counter offer" chip.
- Requires: conversation existing, ESANG agent session, load context.

---

## 054 HaulPay Settlement.png
**Swift port:** GAP.
**Purpose:** Post-POD settlement card — load BOL Buckeye->Wawa York, $599.76 net, gross invoice +$612, deductions (HaulPay factoring, EusoPlatform fee, HazmatPool escrow), Instant/24-hr/Pre-sweep options, Confirm 24-hr pay CTA.

### UI elements -> backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| HaulPay header + load + net $599.76 | Settlement summary | `earnings.getPayStatement` / `settlementBatching.getInvoiceForLoad` | `routers/earnings.ts:224`, `routers/settlementBatching.ts:829` |
| Gross invoice card MC-306 BOL +$612.00 | Invoice | `factoring.getInvoices` / `factoring.submitInvoice` | `routers/factoring.ts:419,443` |
| HaulPay factoring -$9.18 | Factoring fee | `factoring.getFeeSchedule` | `routers/factoring.ts:681` |
| EusoPlatform fee -$3.06 | Platform fee | `platformFees.calculateFee` | `routers/platformFees.ts:629` |
| HazmatPool escrow $0.00 waived | Hazmat escrow | GAP | No `hazmatPool` router; hazmat router has no escrow procedure |
| Three option tiles (Instant $598.26 / 24-hour $599.76 / Pre sweep $599.76) | Payout option | `wallet.getInstantPayoutEligibility` / `wallet.requestInstantPay` | `routers/wallet.ts:785,1254` |
| ESANG line "clears POD tonight, 24-hr free is cheapest" | AI advice | `esangAI.getAlerts` | `routers/esangAI.ts:378` |
| Statement button | View statement | `wallet.getPayoutHistory` | `routers/wallet.ts:2162` |
| Confirm 24-hr pay button | Payout mutation | `wallet.requestPayout` | `routers/wallet.ts:536` |

### Backend GAPS
1. HazmatPool escrow has no router (`hazmatPool`/`escrow` missing). Closest is `wallet.getEscrowHolds` but tied to generic escrow.
2. No "pre-sweep" payout option — `wallet` exposes instant/standard only.
3. Per-load settlement composite with deduction stack — no aggregator procedure; UI must compose.

### User-journey entry points
- From 051 Beat Complete after POD; from Wallet tab -> pending settlements.
- Requires: POD uploaded, invoice submitted to factoring, platform fee computed.

---

## 055 Day Close Wallet.png
**Swift port:** GAP.
**Purpose:** End-of-day wallet summary (Friday 2026-04-17 $1,548.26 running, trend line, day ledger 3 legs, fuel/tolls/per-diem, net pay $3,856.50, Share / Accept Day-2 CTAs).

### UI elements -> backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Daily total $1,548.26 running · delivered/in-flight/queued badges | Day aggregate | `earnings.getWeeklySummary` / `earnings.getEarningsSummary` | `routers/earnings.ts:136,339` |
| Trend sparkline | Rolling 14-day avg | GAP | No time-series procedure; sparkline not backed |
| Day ledger rows (Wawa Lancaster, Buckeye -> Wawa York, Univar Curtis -> Yara York NH3) | Per-leg earnings | `earnings.getEarnings` | `routers/earnings.ts:95` |
| Fuel -$182.30 / Tolls -$22.40 / Per diem $0.00 | Expense rollup | `driverMobile.getExpenseTracker` / `fleet.getFuelTransactions` | `routers/driverMobile.ts:603`, `routers/fleet.ts:983` |
| Net pay $3,856.50 / Miles 862 | Net + miles | `earnings.getYTDSummary` + `drivers.getPerformanceMetrics` | `routers/earnings.ts:244`, `routers/drivers.ts:544` |
| ESANG "day-2 NH3 tender locks your weekend bonus tier · 6 loads · +3% RPM" | Tier nudge | `carrierTier.getDispatchBoost` | `routers/carrierTier.ts:219` |
| Share button | Share day summary | GAP | No shareable day-ledger export |
| Accept Day-2 button | Accept pre-booked day-2 tender | `loads.acceptBid` / `rateConfirmations.send` | `routers/loads.ts:2586` |

### Backend GAPS
1. Day trend sparkline series procedure missing.
2. "Accept Day-2" composite (multi-load weekend acceptance) — no bulk accept procedure beyond `loads.bulkImportCSV`.
3. Share day summary export missing.

### User-journey entry points
- From Wallet tab; from ESANG nudge at day close; from 054 HaulPay Settlement after confirming pay.
- Requires: earnings rows, fuel transactions, per-diem accrual state.

---

## 056 Driver Profile.png
**Swift port:** GAP.
**Purpose:** Driver identity card (Michael Eusorone Brooks, MC-306/331, DOT 2154053, 4.95/411 runs), on-time/safety/tier tiles, credentials list (CDL Class A, Hazmat & Tanker, DOT Medical, TWIC), HazmatPool Tier 2 progress 70%, Runs / Queue renewal CTAs.

### UI elements -> backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Avatar + name + hazmat class + MC/DOT | Driver header | `profile.getMyProfile` / `drivers.getById` | `routers/profile.ts:27`, `routers/drivers.ts:378` |
| Rating 4.95 / 411 runs | Rating | `ratings` table (schema.ts:7089) | No router exposes driver rating aggregate |
| On-time 99.1% / 27-day streak | Streak | `advancedGamification.getStreakTracker` | `routers/advancedGamification.ts:1476` |
| Safety A+ / 0 incidents | Safety grade | `safety.getDriverScoreDetail` / `drivers.getScorecard` | `routers/safety.ts:820`, `routers/drivers.ts:1402` |
| Tier T2 · 3 wks -> T3 | Tier | `carrierTier.getCarrierTier` | `routers/carrierTier.ts:27` |
| Credentials list (CDL, Hazmat, DOT Medical, TWIC) | Credentials | `profile.getCertifications` / `certifications.list` | `routers/profile.ts:164`, `routers/certifications.ts:25` |
| HazmatPool Tier 2 progress 70% | Pool-tier progress | GAP | No `hazmatPool` router |
| ESANG nudge (2 more clean loads -> T3) | AI | `carrierTier.getTierBenefits` | `routers/carrierTier.ts:141` |
| Runs button | Navigate to runs/trip history | `loads.getHistory` | `routers/loads.ts:1338` |
| Queue renewal button | Renew credential | `certifications.sendRenewalReminder` | `routers/certifications.ts:308` |

### Backend GAPS
1. Driver-rating aggregate procedure missing (`ratings` table exists, no `ratings.*` router procedure found to surface per-driver avg).
2. `hazmatPool` domain entirely missing (tier %, saturdays clean, promo window).

### User-journey entry points
- From Me tab; from performance scorecard drill.
- Requires: driver record, certifications, carrier tier assigned.

---

## 057 Performance Scorecard.png
**Swift port:** GAP.
**Purpose:** Rolling scorecard (Top 8% / DD-avoid is lowest dim), dimension bars (On-time, Safety, Hazmat, DD-avoid, Comms), active streaks, recent ratings list, Plan weekend / By lane CTAs.

### UI elements -> backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Top 8% banner + trend line | Percentile | `drivers.getLeaderboard` | `routers/drivers.ts:1432` |
| Dimension bars (99/100/98/88/96) | Multi-dim score | `drivers.getScorecard` | `routers/drivers.ts:1402` |
| Active streaks (On-time delivery 27, Day-1 same-lane 4, DD-free weeks) | Streak | `advancedGamification.getStreakTracker` | `routers/advancedGamification.ts:1476` |
| Recent ratings list with stars + shipper comment | Ratings feed | GAP | `ratings` table exists, no per-driver-ratings procedure |
| ESANG "clear 2 clean loads, Tier 3 locks, +3% RPM" | AI nudge | `esangAI.getRecent` | `routers/esangAI.ts:288` |
| By lane button | Lane filter | `drivers.getLaneHistory` | `routers/drivers.ts:2195` |
| Plan weekend button | Plan weekend tenders | GAP | No `drivers.planWeekend` / lane-plan mutation |

### Backend GAPS
1. Ratings feed per driver (comments) — `messages` covers text but rating comments per-load not exposed.
2. "Plan weekend" composite action missing.
3. DD-avoid / Comms / Hazmat dimensions — `drivers.getScorecard` returns generic scorecard but dimension breakdown not verified in schema.

### User-journey entry points
- From Me tab -> Scorecard; from 056 Driver Profile.
- Requires: scorecard rows, streaks, ratings populated.

---

## 058 Credentials Detail.png
**Swift port:** GAP.
**Purpose:** Hazmat/Tanker CDL detail (license 34-108-441, class A HNXT, issue/expiry dates, 42 days to window), refresh timeline, docs on file (License front/back, DOT Medical card, MVR & PSP), History / Queue refresh CTAs.

### UI elements -> backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Credential header + state PA + class letters | CDL | `cdlVerification.getCDLRecord` | `routers/cdlVerification.ts:164` |
| HNXT/P tiles (Hazmat/Tanker/Doubles/Passenger) | Endorsements | `cdlVerification.checkCDLForLoad` | `routers/cdlVerification.ts:155` |
| Refresh timeline (Issued / Refresh opens / Expires) | Refresh schedule | `certifications.getExpiring` | `routers/certifications.ts:212` |
| Documents on file list (License front/back, DOT Medical PDF, MVR & PSP) | Docs | `documents.*` / `profile.getCertifications` | `routers/profile.ts:164`, `drizzle/schema.ts:1634` |
| Status tags (Clear / Queued) per doc | Verification state | `certifications.verify` | `routers/certifications.ts:193` |
| ESANG "Harrisburg DLC slot May 26-30" | Scheduling hint | GAP | No DLC/DMV slot scheduling router |
| History button | Credential history | GAP | Not in `certifications` router |
| Queue refresh button | Schedule renewal | `certifications.sendRenewalReminder` | `routers/certifications.ts:308` |

### Backend GAPS
1. DLC/DMV appointment slot search/scheduling missing.
2. Credential renewal-history timeline procedure missing.
3. MVR & PSP pull-status not exposed (may live in `driverQualification.ts` — not verified procedure).

### User-journey entry points
- From 056 Driver Profile (tap credential row).
- Requires: cdl record + certifications rows + documents rows.

---

## 059 Vehicle and Equipment.png
**Swift port:** GAP.
**Purpose:** Tractor "Unit 2041 · gasoline tank / NH3 tank" spec card (GVW 80,000, fuel 305 gal diesel, MPG 7.38), last DVIR checklist (Brakes, Tires, Lights, Tank & hose), miles to change / DOT annual / tire rotate counters, Log / Book oil CTAs.

### UI elements -> backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Unit header + VIN / plate / soft-note chip | Vehicle header | `fleet.getVehicleById` / `equipment.getById` | `routers/fleet.ts:1049`, `routers/equipment.ts:70` |
| GVW / fuel / MPG tiles | Vehicle stats | `fleetMaintenance.getFuelEfficiency` | `routers/fleetMaintenance.ts:1510` |
| Last DVIR rows (Brakes pass, Tires pass, Lights pass, Tank pass) | Last DVIR | `drivers.getDVIRHistory` / `fleet.getDVIRs` | `routers/drivers.ts:1712`, `routers/fleet.ts:870` |
| Oil 1,100 mi to change | Oil counter | `fleetMaintenance.getPreventiveSchedule` | `routers/fleetMaintenance.ts:350` |
| DOT 30 days to annual | DOT annual | `fleetMaintenance.getComplianceCalendar` | `routers/fleetMaintenance.ts:2058` |
| Tire rotate 8,950 mi | Tire mgmt | `fleetMaintenance.getTireManagement` | `routers/fleetMaintenance.ts:1049` |
| ESANG "oil service opens Saturday, save 38 mi" | AI suggestion | `esangAI.getRecent` | `routers/esangAI.ts:288` |
| Log button | Log maintenance event | `fleetMaintenance.logTireEvent` / `fleet.scheduleMaintenance` | `routers/fleetMaintenance.ts:1185`, `routers/fleet.ts:768` |
| Book oil button | Schedule maintenance | `fleetMaintenance.createWorkOrder` | `routers/fleetMaintenance.ts:437` |

### Backend GAPS
1. "Soft note" tag on unit card — no free-text note per vehicle exposed.
2. Combined tractor+trailer spec card (NH3 tank certification + gasoline tank) — no unified procedure.
3. Book-oil instant scheduling with shop availability — `createWorkOrder` exists but no shop-slot procedure.

### User-journey entry points
- From 056 Driver Profile; from 011 Pretrip DVIR header.
- Requires: vehicle record, DVIR history, maintenance schedule.

---

## 060 HazmatPool Tier.png
**Swift port:** GAP.
**Purpose:** HazmatPool tier progression (Tier 2 Spark, 2 of 3 Saturdays, next Tier 3 Ember), pool take %, priority (Second/First), streak days, perks live (Pool revenue share, Tender first-refusal, Heated bay, Same-day HaulPay), qualifying runs list, Preview T3 CTA.

### UI elements -> backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Tier 2 · Spark + "70% to Tier 3" | Pool tier | GAP | No `hazmatPool` router |
| 3 perfect Saturdays / 1 to go counter | Saturday streak | GAP | No Saturday-specific streak procedure |
| Pool take 1.8% / Priority Second / Streak 26 tiles | Perks/priority | GAP | No procedure |
| Perks live rows with Live/Next badges | Perk state | GAP | No procedure |
| Qualifying runs list (Yara York, Yara Baltimore, CF Industries Cantons, Yara York baseline) | Recent run qualification | Partial: `loads.getHistory` | run-eligibility gating missing |
| ESANG "clean pod tomorrow -> Yara York unlocks T3 at 22:40" | AI | `esangAI.getRecent` | `routers/esangAI.ts:288` |
| History button | Pool history | GAP | |
| Preview T3 button | Projected tier benefits | `carrierTier.getTierBenefits` (generic) | `routers/carrierTier.ts:141` |

### Backend GAPS
1. `hazmatPool` domain entirely missing: pool definitions, Saturday counts, priority, streak, perks, qualification rules.
2. Tier promotion preview/projection procedure missing (`carrierTier.getTierBenefits` is generic, not time-boxed preview).
3. No Pool-revenue-share ledger or payout linkage.

### User-journey entry points
- From 056 Driver Profile (HazmatPool card); from ESANG nudge after clean haul.
- Requires: HazmatPool membership row, Saturday clean-haul counts, tier definitions.

---

## 061 Earnings and Pay.png
**Swift port:** GAP.
**Purpose:** YTD earnings $47,979.18 (15 wks · 4 legs T2 pool · 78% to T3, 27,612 mi), 8-week bar chart, recent legs (4 most recent: Buckeye->Wawa York, ->Wawa Lancaster, Univar Curtis->Yara PA, Buckeye->Wawa Pottsville), 1099 reserve $8,280.98 (Q1 filed / Q2 queued), HaulPay routing EusoWallet T2 fee 0.0% instant, Statement / History CTAs.

### UI elements -> backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| YTD Gross $47,979.18 + delta chip | YTD | `earnings.getYTDSummary` | `routers/earnings.ts:244` |
| 15 weeks / 4 legs / 78% to T3 / miles badges | Rollup | `earnings.getEarningsSummary` + `carrierTier.getCarrierTier` | `routers/earnings.ts:339`, `routers/carrierTier.ts:27` |
| 8-week bar chart | Weekly series | `earnings.getWeeklySummaries` | `routers/earnings.ts:201` |
| Recent legs rows with $ amounts and status (settle, instant pay, pending POD) | Per-leg list | `earnings.getHistory` / `earnings.getSettlementHistory` | `routers/earnings.ts:261,265` |
| 1099 reserve $8,280.98 · Q1 filed / Q2 queued | Tax reserve | `wallet.getTaxDocuments` | `routers/wallet.ts:758` |
| HaulPay routing EusoWallet · T2 · fee 0.0% | Routing rule | `wallet.getPayoutMethods` + `factoring.getFeeSchedule` | `routers/wallet.ts:421`, `routers/factoring.ts:681` |
| ESANG "booking the Wawa York bol closes the week" | AI | `esangAI.getRecent` | `routers/esangAI.ts:288` |
| History button | Earnings history | `earnings.getHistory` | `routers/earnings.ts:261` |
| Statement button | Pay statement | `earnings.getPayStatement` | `routers/earnings.ts:224` |

### Backend GAPS
1. Tax reserve / quarterly 1099 queue rollup — `wallet.getTaxDocuments` returns docs but not quarter-filed/queued status.
2. HaulPay routing rule ("Euso wallet T2 fee 0.0%") — no `factoring.getRoutingRule` procedure.
3. "Pending POD" per-leg status chip — no unified status combining settlement + POD.

### User-journey entry points
- From Wallet tab -> Earnings; from 055 Day Close Wallet -> statement.
- Requires: YTD aggregate, weekly series, settlement history, tax doc metadata.

---

## Summary
- Screens audited: **13** (049-061).
- Swift ports: **0 / 13** — entire bucket has no Swift implementation (Swift halts at 022).
- Total UI elements mapped: ~130.
  - Elements with a matching backend procedure: ~85 (~65% backed).
  - Elements with partial / proxy match: ~18 (~14%).
  - Pure GAPs: ~27 (~21%).
- % backed (fully): **~65%**. % backed (including partial proxies): **~79%**.

### Top 3 gaps (by blast radius)
1. **HazmatPool domain missing entirely** — hits screens 054 (escrow), 056 (tier %), 060 (whole screen), 061 (T2 routing). No router, no schema table for pool membership/Saturday streak/perks.
2. **Spectra-Match findings + run-telemetry procedures missing** — hits 049 (findings rows, dispatcher signature), 050 (live fill %, flow/PSI/temp, pause fill, terminal ops watchlist). `spectraMatch.ts` covers identify/save but not live run lifecycle.
3. **Rate confirmation persistence is a stub** — `rateConfirmations.ts` is 4 empty procedures; screen 052 (entire tender view) and screen 055 (day-2 tender accept) depend on it. Also missing: tender in-flight state, lane-level accessorial breakdown per tender, PDF export.

Secondary gaps: driver-rating aggregate surfacing (`ratings` table unused by any router), day sparkline time-series, dispatcher signature capture, DLC/DMV appointment scheduling, "pre-sweep" payout option, "plan weekend" composite action, shareable day-ledger export, bulk Day-2 tender accept.

### User-journey entry-point map (for bucket)
- **Trip lifecycle inbound:** 048 Arrival-Gate Task Active -> 049 -> 050 -> 051 -> (052 rate review) -> 054 HaulPay.
- **Wallet branch:** tab bar -> 054 / 055 / 061; 055 can cross to 056 via ESANG tier nudge.
- **Me/Profile branch:** tab bar -> 056 -> 057 / 058 / 059 / 060; 060 gates routing shown on 054 & 061.
- **ESANG branch:** tab bar -> 053; 053 inline actions reach 052 (tender), 054 (settlement), 050 (live fill).

Required backend state for bucket to function end-to-end:
`users` + `drivers` row, `loads` + `loadStops`, `runTickets`, `bol`, `settlements` + `settlementBatches`, `wallets` + `walletTransactions`, `factoringInvoices`, `certifications`, `vehicles` + `inspections`, `carrierTier` record, `messages` + `conversations`, `esangAI` logs, plus MISSING: `hazmatPool` tables, `rateConfirmations` real persistence, `spectraFindings` / live-telemetry table, `driverRatingsAggregate` view.
