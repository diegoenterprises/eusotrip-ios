# Wave-3 Agent 08 — Driver Bucket 08 (103–115) Audit

Audit scope: 13 Driver Figma screens (103–115), both Light + Dark variants inspected.
Backend root: `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/`
Swift root:   `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/EusoTrip/Views/Driver/`

Note: The Swift Driver port currently stops at `022_DockAssigned.swift` (see Glob listing). **None of the 13 screens (103–115) has a corresponding Swift view yet** — every row below shows `Swift port: MISSING`.

---

## 103 Fuel Optimizer.png
**Swift port:** MISSING (no `103_*.swift` or `FuelOptimizer*.swift` in `EusoTrip/Views/Driver/`).
**Purpose:** Live "Fuel Plan" screen. Shows tank range/gallons, next fill, ranked fuel stops along corridor (Pilot/Loves/TA), corridor median price board, loyalty progress, AI recommendation ("Camp Hill is 2¢ below median…"), `Skip next` / `Lock Camp Hill` actions. Dark variant shows archived plan with `Compare` / `Open receipts`.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Fuel plan header (range, gal, next fill, avg MPG) | Fleet/trip telemetry + fuel math | `fuel.getSummary` (fuel.ts:20), `fuel.getEfficiencyReport` (fuel.ts:189) | covers mpg/range roll-up |
| "Plan A Locked" pill | Plan state | **GAP** — no `fuelPlan.lock` / plan entity | only per-card `toggleCard` at fuel.ts:385 |
| Ranked next stops (Pilot #285, #702, Loves) w/ price, savings | Nearby station list + corridor price | `fuel.getNearbyStations` (fuel.ts:351), `fuel.getCurrentPrices` (fuel.ts:66), `fuel.getPrices` (fuel.ts:235) | |
| Per-stop brand chips (PILOT/GOLD, LOYALTY, TA/ULSD) | Loyalty/program meta | **GAP** — no loyalty program router; `fuel.getFuelCards` (fuel.ts:206) returns cards not chain loyalty |
| Price board corridor bars (Pilot/Loves/TA/Speedway) | Corridor median | `fuel.getAverages` (fuel.ts:329), `fuel.getTrends` (fuel.ts:340) | |
| Loyalty Today (+110) | Loyalty accrual | **GAP** |
| AI recommendation text | AI narration | `esangVoiceOrchestrator.generateVoicePrompts` (esangVoiceOrchestrator.ts:159) reuse OR **GAP** for fuel-domain LLM advisor |
| `Skip next` button | Mark stop skipped | **GAP** — no plan-mutation procedure |
| `Lock Camp Hill` primary CTA | Commit plan choice | **GAP** — no `fuel.lockPlan` / `fuelPlan.commit` |
| Dark: `Compare` / `Open receipts` | Diff planned vs actual, receipt drawer | `fuel.getTransactions` (fuel.ts:116), `fuel.reportPurchase` (fuel.ts:255) — partial; no `comparePlanVsActual` | |

### Backend GAPS (numbered)
1. No persisted fuel-plan entity (`fuelPlan`/`lockPrice`/`skipStop`).
2. Loyalty program (Pilot Gold, Loves, TA) not modeled.
3. No corridor-AI/advisor procedure for the "Pilot Camp Hill is 2¢ below median…" narrative text.
4. No plan-vs-actual comparison endpoint for the archived/Compare state.

### User-journey entry points
- Driver Home → Fuel tile/quick-action (`driverMobile.getQuickActions` driverMobile.ts:1599).
- En-route Active Load (Swift `018_ActiveEnrouteLoaded.swift`) deep link on upcoming fuel stop.
- Required state: active HOS duty = `driving`, active load assigned, telemetry MPG/range available, geolocation permission.

---

## 104 DVIR.png
**Swift port:** MISSING (Swift has `011_PretripDVIR.swift` + `012_DvirSubmitted.swift` for the trip-start flow; no 104-equivalent post-trip detail view).
**Purpose:** DVIR form (Pre-Trip / Post-Trip toggle). Shows tractor/trailer, odometer, location, 49 CFR 396.11 categories with green/yellow check state, Defects section ("Rear marker light — intermittent flicker"), driver signature, AI sidebar coaching. Dark variant shows archived post-trip with 0 defects and "View PDF" / "Photos".

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Pre-Trip / Post-Trip toggle | DVIR type | `inspections.createDVIR` (inspections.ts:279) accepts type |
| Progress pill "11/12 + 1 minor" | Template progress | `inspections.getTemplate` (inspections.ts:42) |
| Tractor / Trailer / Odometer / Location | Vehicle + location ctx | `vehicle.*` + `location.*` routers (ctx prefill) |
| 12 category check tiles (Service brakes, Steering, Tires…) | DVIR items | `inspections.getDVIRCategories` (inspections.ts:366) + `inspections.createDVIR` payload |
| Defect card (marker light, MINOR) | Defect list | `inspections.getOpenDefects` (inspections.ts:223) |
| Driver signature block | Signature capture | **GAP** — no `signatures.signDVIR`; `signatures.ts` exists generically but no DVIR-sign binding |
| Drafting/Locked state | Review/lock | `inspections.reviewDVIR` (inspections.ts:340) |
| AI sidebar note ("Minor flicker — not a no-go for FMCSA…") | Advisor text | **GAP** — no DVIR advisor procedure |
| Dark: `Photos` / `View PDF` | Evidence + export | **GAP** — no `dvir.getPhotos` / `dvir.exportPdf`; generic `documents.*` exists |

### Backend GAPS (numbered)
1. DVIR signature attachment (sign + stamp) has no dedicated procedure.
2. DVIR PDF export + photo gallery endpoints missing.
3. DVIR-specific AI advisor narrative missing.

### User-journey entry points
- Driver Home at shift start (Swift `010_DriverHome.swift`).
- Pre-trip required before `activeEnroute`; post-trip on dock-depart.
- Required state: `drivers.assignedVehicle`, `eld.currentDuty ≠ off_duty`, HOS ready.

---

## 105 Safety Score.png
**Swift port:** MISSING.
**Purpose:** Driver safety scorecard — today's composite (97.4), streak, fleet rank, sub-metric tiles (hard brake, lane keep, speeding, smooth start, following distance, attention) with delta arrows, 7-day trend line, today's events timeline.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Today's composite score + streak + fleet rank | Driver scorecard | `safety.getDriverScorecards` (safety.ts:476), `safety.getDriverScores` (safety.ts:812), `safety.getDriverScoreDetail` (safety.ts:820) |
| "Top 2% live" pill | Leaderboard | `driverMobile.getDriverLeaderboard` (driverMobile.ts:1752) |
| 6 metric tiles (hard brake/lane/speed/start/following/attention) | Per-metric breakdown | `safety.getDriverScoreDetail` (safety.ts:820) — likely carries sub-metrics; **GAP** if sub-metrics missing |
| 7-day trend sparkline | Historical | `safety.getTrends` (safety.ts:604) |
| Today recent events (late brake on I-95, smooth merge…) | Event list | `safety.getRecentIncidents` (safety.ts:157), `telemetry.*` for raw events |
| AI coaching paragraph | Narrative | **GAP** — no safety-coach LLM procedure |
| Dark: "Weekly score / Week events / placement text" | Period aggregate | `safety.getMetrics` (safety.ts:577) |

### Backend GAPS (numbered)
1. Sub-metric scoring payload (hard-brake, lane-keep, attention etc.) not confirmed in response shape.
2. AI safety coach narrative endpoint absent.
3. Fleet percentile + "moved up N spots" rank delta not explicit.

### User-journey entry points
- Driver Home → Safety tile (`driverMobile.getDriverHomeDashboard` driverMobile.ts:240).
- Required state: driverId, telemetry events for day, CSA baseline.

---

## 106 Maintenance.png
**Swift port:** MISSING.
**Purpose:** Vehicle maintenance dashboard. Next major DOT annual service banner, odometer/brake-pad/tire life bars, upcoming live queue (DOT inspection, slack-adjuster, oil, tire), last 200 work orders, preferred shop card, `Details` / `Confirm Apr 21` CTAs. Dark variant "Fit for Duty".

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Next major service banner | Predictive/scheduled | `fleetMaintenance.getPreventiveSchedule` (fleetMaintenance.ts:350), `fleetMaintenance.getPredictiveAlerts` (fleetMaintenance.ts:1898) |
| Odometer/brake-pad/tire tiles | Live telemetry | `fleetMaintenance.getTireManagement` (fleetMaintenance.ts:1049), `telemetry.*` |
| Upcoming queue (DOT, slack adjuster, oil, tire) | Service queue | `fleetMaintenance.getPreventiveSchedule` (fleetMaintenance.ts:350), `maintenance.getScheduled` (maintenance.ts:112) |
| Last 200 work orders | Repair history | `fleetMaintenance.getRepairHistory` (fleetMaintenance.ts:650), `fleetMaintenance.getWorkOrders` (fleetMaintenance.ts:492) |
| Preferred shop card (Volvo Tampa) | Vendor | `fleetMaintenance.getVendorManagement` (fleetMaintenance.ts:1747) |
| AI rec "Catch slack adjuster on Apr 21 visit" | Narrative | **GAP** — predictive advisor copy not exposed |
| `Details` button | Work-order detail | `fleetMaintenance.getWorkOrders` (fleetMaintenance.ts:492) |
| `Confirm Apr 21` primary CTA | Accept suggested slot | **GAP** — no `maintenance.confirmAppointment` / `fleetMaintenance.confirmSlot` (only `createWorkOrder` at 437 / `updateWorkOrder` at 597) |

### Backend GAPS (numbered)
1. No appointment-confirm procedure (accept predictive slot w/ vendor).
2. Predictive narrative ("catch slack adjuster") not a dedicated endpoint.
3. DOT-annual countdown banner (days left %) — no explicit `nextMajor` procedure.

### User-journey entry points
- Driver Home → Maintenance tile.
- Dispatcher-push notification when predictive alert fires.
- Required state: `vehicle.assigned`, telemetry reporting, preferred vendor set.

---

## 107 Roadside.png
**Swift port:** MISSING.
**Purpose:** Roadside assistance / FleetNet coverage screen. Status "No active incidents", last 365 days stats, primary-coverage card, recent 1 assist list, Quick-request grid (Tire/Lockout/Fuel/Tow/Mechanical/Glass), AI coverage narrative, `Coverage` / `Open assist` CTAs. Dark variant "Incident 0416 — Fuel solenoid cutout — resolved" with event timeline.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Coverage header + "All clear" pill | Status roll-up | `driverMobile.getRoadsideAssistance` (driverMobile.ts:742) |
| 365-day stats (assists, downtime, OOP) | Aggregate | **GAP** — no roadside aggregate procedure |
| Primary coverage card (FleetNet — 1-tap) | Policy | **GAP** — no `insurance.getRoadsidePolicy` of this shape; `insurance.ts` exists (see files listing) but no direct lookup |
| Recent assist list (fuel solenoid, DEF PSI…) | Ticket history | **GAP** — no roadside ticket list procedure (only request creation at driverMobile.ts:742) |
| Quick-request grid 6 buttons | Open ticket w/ issueType | `driverMobile.getRoadsideAssistance` (driverMobile.ts:742) — supports enum `tire/lockout/tow/fuel_delivery/mechanical/other` but NOT `glass` |
| AI coverage narrative | | **GAP** |
| `Open assist` primary CTA | Start new ticket flow | `driverMobile.getRoadsideAssistance` (driverMobile.ts:742) |
| Dark: event timeline (trouble code → assist → tech → cleared) | Ticket lifecycle | **GAP** — no roadside status/lifecycle procedure |
| Dark: `Claim doc` / `Close case` | Evidence + close | **GAP** |

### Backend GAPS (numbered)
1. No roadside ticket list / detail / close procedures (only "create").
2. `glass` issue type missing from driverMobile roadside enum (driverMobile.ts:746).
3. Coverage / policy lookup endpoint missing.
4. Ticket event timeline not modeled.

### User-journey entry points
- Driver Home Quick Action "Roadside Help" (driverMobile.ts:1605 — `QA-004 roadside_assistance`).
- En-route crash/breakdown auto-trigger via `emergencyProtocols` router.
- Required state: driverId, vehicleId, geolocation, coverage record.

---

## 108 Available Loads.png
**Swift port:** MISSING.
**Purpose:** Ranked "available loads" board. Live origin filters (return-to/NH4-qualified/Sat 06:00+/drop-only), top ESANG-ranked match card ($/mile), three alternates ranked, AI rationale, `Compare lanes` / `Book #1` CTAs.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Live origin search header + filter chips | Search | `loadBoard.search` (loadBoard.ts:655), `loads.search` (loads.ts:1788) |
| Top match card (rate, miles, pickup, deliver, equip, tags) | Top match | `loadBoard.getStats` (loadBoard.ts:1586), `loads.calculateRate` (loads.ts:1676) |
| Alternate list (#2–#4) | Ranked list | `loadBoard.search` (loadBoard.ts:655) |
| AI rationale ("Marcus Hook → Plant City is your best-paying return in 4 months") | Narrative | **GAP** — no load-match LLM advisor |
| `Compare lanes` | Lane diff | `loads.getRateHistory` (loads.ts:1752), `loadBoard.getLaneContractRates` (loadBoard.ts:2520) |
| `Book #1` primary CTA | Book load | `loadBoard.bookLoad` (loadBoard.ts:934), `loads.book` (loads.ts:1897) |
| Dark: "Filter more" | Filter drawer | `loadBoard.getSavedSearches` (loadBoard.ts:1124) |
| Dark: "6 matches" count | Search meta | `loadBoard.search` result size |

### Backend GAPS (numbered)
1. ESANG-rank/score field not a dedicated procedure — only generic search.
2. AI narrative advisor not exposed.

### User-journey entry points
- Driver Home → Loads tab.
- Completed delivery deep-link (`018_ActiveEnrouteLoaded.swift` final step).
- Required state: driverId, hosRemaining > minimum, preferredEquip, homeLocation.

---

## 109 Load Detail.png
**Swift port:** MISSING.
**Purpose:** Load detail drawer. Banner rate + ESANG match pct, stops itinerary, pay breakdown (linehaul, fuel surcharge, drop+hook, weekend premium), commodity + restrictions, shipper card (Yara North America, TRUSTED), AI rationale.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Header rate/total + ESANG #1 match | Detail | `loadBoard.getById` (loadBoard.ts:725), `loads.getById` (loads.ts:1012) |
| Stops itinerary (Marcus Hook Terminal → Plant City Fert Plant) | Stops | `loadStops.*` router; `loads.getTimeline` (loads.ts:1507) |
| Pay breakdown rows (linehaul/FSC/drop+hook/weekend) | Rate decomposition | `loads.calculateRate` (loads.ts:1676), `rates.*`, `fuelSurchargeIndex.ts` |
| Commodity + restrictions (urea ammonium nitrate / hazmat / tank endorsement) | Hazmat | `hazmat.*` router, `loadBoard.getHazmatClassRequirements` (loadBoard.ts:1981) |
| Shipper card (Yara NA, TRUSTED, EFS factoring) | Shipper profile | `shippers.*` + `factoring.*` |
| AI narrative | | **GAP** — no load-advisor procedure |
| Book/Accept CTA (primary, not labeled on this frame) | Book | `loadBoard.bookLoad` (loadBoard.ts:934) |

### Backend GAPS (numbered)
1. "TRUSTED" broker badge (tier) not exposed as a field-level procedure (generic `carrierTier.ts` exists but no broker-tier lookup wired here).
2. Load-specific AI rationale absent.

### User-journey entry points
- Tap a row on 108 Available Loads → push to detail.
- Required state: loadId, driverId permission to view, hazmat eligibility flags.

---

## 110 Accessorial.png
**Swift port:** MISSING.
**Purpose:** Accessorial claim composer / detail. Header status "DRAFT • WAWA LANCASTER • DRAFTING • BELOW THRESHOLD", Detention amount $0.00 auto-rule, GPS + dock stamps (scheduled/arrival/start/complete), Claim Items list (detention/lumper/ESANG appeal req), Requesting total, Evidence (GPS log, Signed BOL, Add photo), Driver notes.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Header status pill | Claim lifecycle | `detentionAccessorials.getDetentionDashboard` (detentionAccessorials.ts:129) |
| Detention amount + "auto-rule" | Computed charge | `detentionAccessorials.calculateDetention` (detentionAccessorials.ts:355), `accessorial.calculateDetention` (accessorial.ts:546) |
| Stop/Policy chips (Drop 2 / $50/hr) | Rate config | `detentionAccessorials.configureAccessorialRate` (detentionAccessorials.ts:690) |
| GPS + dock stamps grid | Timestamps | `tracking.*`, `geofencing.*` |
| Claim items rows (detention/lumper/ESANG appeal) | Itemized charges | `detentionAccessorials.applyAccessorial` (detentionAccessorials.ts:712), `accessorial.getFeeSchedule` (accessorial.ts:409) |
| Evidence buttons (GPS log / Signed BOL / Add photo) | Attach evidence | `accessorial.submitClaim` (accessorial.ts:141) payload — no dedicated "attach evidence" endpoint separate from submit |
| Driver notes freeform | Note | **GAP** — no `accessorial.addNote` (claims.ts:246 has `addNote` but for claims domain) |
| Requesting total ($95.00) | Sum | client-side |
| `Submit` CTA (implicit) | File claim | `accessorial.submitClaim` (accessorial.ts:141), `detentionAccessorials.fileTonu` (detentionAccessorials.ts:820) |

### Backend GAPS (numbered)
1. No standalone "add evidence" procedure for accessorial drafts (must be submitted as one payload).
2. No draft persistence endpoint (`accessorial.saveDraft`).
3. Driver-notes on accessorial claim not modeled (only claims.ts note).

### User-journey entry points
- Geofence dwell > threshold auto-creates draft (geofencing router triggers).
- Driver Home → Claims tile → New.
- Required state: loadId, stopId, dock arrival/departure events, evidence permissions.

---

## 111 Claims.png
**Swift port:** MISSING.
**Purpose:** Claims dashboard. Live YTD approved $1,842, counts (approved 12 / pending 1 / denied 1), in-flight claim card (Wawa Lancaster appeal, 4-of-4 verified), tabs (Filed/Verified/Review/Decision), recent decisions list, AI rationale, `Filter` / `View appeal` CTAs. Dark variant YTD summary + `Filter year` / `New claim`.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| YTD approved banner | Aggregate | `claims.getStatistics` (claims.ts:286), `freightClaims.getClaimsAnalytics` (freightClaims.ts:1160), `accessorial.getDashboardStats` (accessorial.ts:422) |
| Counts (approved/pending/denied) | Summary | `claims.getSummary` (claims.ts:77), `freightClaims.getClaimsDashboard` (freightClaims.ts:75) |
| In-flight claim card | Active | `claims.list` (claims.ts:26), `freightClaims.getClaims` (freightClaims.ts:172) |
| Tabs (Filed/Verified/Review/Decision) | Status filter | `claims.list` filter arg |
| Recent decisions list w/ outcome chips | List | `claims.list` (claims.ts:26) |
| AI approval-probability narrative | | **GAP** — no claim-probability advisor |
| `View appeal` | Open detail | `claims.getById` (claims.ts:102), `freightClaims.getClaimById` (freightClaims.ts:246) |
| `Filter year` | Date filter | `claims.list` input |
| `New claim` primary CTA | Compose | `claims.file` (claims.ts:135), `freightClaims.fileClaim` (freightClaims.ts:332) |

### Backend GAPS (numbered)
1. Approval-probability / appeal prediction narrative endpoint missing.
2. No per-claim "verification steps" (4 of 4 verified) substate procedure.

### User-journey entry points
- Driver Home → Claims tab.
- Accessorial draft (110) submit → redirect here.
- Required state: driverId, historical claims, aggregate window (YTD/quarter).

---

## 112 Inbox.png
**Swift port:** MISSING.
**Purpose:** Driver message inbox. Header "5 unread" + filter chips (All/Dispatch/Brokers/Urgent), active pinned thread (Sarah Castillo, typing), action chips (`Copy ID` / `Voice note` / `Acknowledge`), thread list, AI typing indicator narrative, `Mark all read` / `Reply Sarah`.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| "5 unread" badge | Unread count | `messages.getUnreadCount` (messages.ts:573), `messaging.getUnread` (messaging.ts:318), `channels.getSummary` (channels.ts:364) |
| Filter chips (All/Dispatch/Brokers/Urgent) | Category filter | `messaging.getInbox` (messaging.ts:92), `channels.list` (channels.ts:47) |
| Active thread pinned card w/ typing | Thread w/ presence | `messages.getConversation` (messages.ts:800), **GAP** on live-typing indicator feed (only `messaging.getTypingIndicators` stub at messaging.ts:881 returns empty) |
| Inline action chips (Copy ID / Voice note / Acknowledge) | Quick-reply actions | `messages.sendMessage` (messages.ts:279), `esangVoice.speak` (esangVoice.ts:59), **GAP** for "acknowledge" intent type |
| Thread list rows | List | `messages.getConversations` (messages.ts:45), `messaging.getConversations` (messaging.ts:137) |
| AI narrative ("Sarah typing now…") | | **GAP** |
| `Mark all read` | Mass-read | `announcements.markAllRead` (announcements.ts:79), `channels.markRead` (channels.ts:338), **no generic messages.markAllRead** — messages.ts has `markAsRead` per-thread only (messages.ts:531) |
| `Reply Sarah` primary CTA | Open compose | `messages.sendMessage` (messages.ts:279) |
| "Yara Fleet Broadcast" row (URGENT badge) | Broadcast | `resourceBroadcasts.getActiveAlerts` (resourceBroadcasts.ts:15), `communicationHub.getEmergencyBroadcastHistory` (communicationHub.ts:1525) |

### Backend GAPS (numbered)
1. No real typing-indicator realtime channel (stub returns empty).
2. No `messages.markAllRead` bulk procedure.
3. "Acknowledge" message intent not modeled.

### User-journey entry points
- Driver Home → Inbox tab (bottom nav).
- Push notification → deep link thread.
- Required state: driverId session, channel/conversation memberships.

---

## 113 Thread.png
**Swift port:** MISSING.
**Purpose:** Individual conversation thread with Sarah Castillo. Message bubbles, file attachment row (Wawa_Policy_4.2_grace.pdf), ESANG Draft Ready suggestions (Acknowledged / Share dock photo / Ping me on dock), typing input with voice icon.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Header back + avatar + thread ref (C-22501) | Thread meta | `messages.getConversation` (messages.ts:800), `messaging.getThreadView` (messaging.ts:826) |
| "Appeal in Review" pill | Linked claim status | `claims.getById` (claims.ts:102) join — **GAP** on thread-to-claim linkage procedure |
| Message bubbles (incoming/outgoing) | Messages | `messages.getMessages` (messages.ts:186), `messaging.getMessages` (messaging.ts:153) |
| PDF attachment card | Attachment | `messages.uploadAttachment` (messages.ts:862), `channels.uploadAttachment` (channels.ts:534) |
| ESANG Draft Ready chips | AI suggested replies | **GAP** — no `esang.suggestReplies(threadId)` procedure (generic `esangVoice.speak` unrelated) |
| Composer (text + mic) | Send | `messages.sendMessage` (messages.ts:279), `voiceESANG.processVoiceCommand` (voiceESANG.ts:20), `voiceESANG.transcribeAudio` (voiceESANG.ts:88) |
| Read receipts / typing | Presence | `messaging.getReadReceipts` (messaging.ts:686); typing — GAP |
| AI narrative ("Sarah is fast-tracking…") | | **GAP** |

### Backend GAPS (numbered)
1. Thread ↔ claim/appeal linkage lookup absent.
2. AI suggested-replies procedure for a thread absent.
3. Realtime typing indicator absent (see 112).

### User-journey entry points
- Tap row on 112 Inbox.
- Voice Reply (115) after dictation → lands here.
- Required state: conversationId, participantIds, linked-entity (claim/load) id optional.

---

## 114 Broadcasts.png
**Swift port:** MISSING.
**Purpose:** Fleet broadcast center. Counts (urgent/advisory/resolved 48h), active broadcast card (NH4 pump downtime, ack required), broadcast feed (traffic/weather), subscription chips (NH4 hazmat/Yara fleet/Weather-PA/FL), AI routing narrative, `Snooze 2h` / `Acknowledge`. Dark variant "Manage subs" + `History`.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Counts banner (urgent/advisory/resolved) | Aggregate | `resourceBroadcasts.getActiveAlerts` (resourceBroadcasts.ts:15), `resourceBroadcasts.getAlertHistory` (resourceBroadcasts.ts:32) |
| Active broadcast card w/ ack-required | Single alert | `resourceBroadcasts.getActiveAlerts` (resourceBroadcasts.ts:15), `communicationHub.getEmergencyBroadcastHistory` (communicationHub.ts:1525) |
| Feed rows (pump / construction / weather) | Feed | `resourceBroadcasts.getAlertHistory` (resourceBroadcasts.ts:32), `safetyAlerts.*`, `hotZones.*` |
| Subscription chips | User subs | `resourceBroadcasts.getSubscriptions` (resourceBroadcasts.ts:60), `resourceBroadcasts.updateSubscription` (resourceBroadcasts.ts:70) |
| AI advisory narrative ("You're already routed to dock 4…") | | **GAP** |
| `Snooze 2h` | Mute | **GAP** — no `broadcast.snooze` (only channel mute at channels.ts:426) |
| `Acknowledge` primary CTA | Mark ack | **GAP** — no `resourceBroadcasts.acknowledge` (no ack mutation in the router) |
| Dark: `Manage subs` | Settings | `resourceBroadcasts.updateSubscription` (resourceBroadcasts.ts:70) |
| Dark: `History` | Past alerts | `resourceBroadcasts.getAlertHistory` (resourceBroadcasts.ts:32) |

### Backend GAPS (numbered)
1. Broadcast acknowledge mutation missing.
2. Broadcast snooze (time-based mute) missing.
3. Per-broadcast "affected loads" join procedure absent.

### User-journey entry points
- Push notification ("URGENT: NH4 pump…") → deep link.
- Driver Home → Broadcasts tile.
- Required state: driverId, subscription list, active loadId for contextual "already routed" message.

---

## 115 Voice Reply.png
**Swift port:** MISSING.
**Purpose:** Voice-reply composer in the context of a thread (Sarah Castillo C-22501). Mic orb + live waveform + timer, live transcription pane with confidence %, quick alternates (Acknowledged / Running on time / Fueling now / Share dock photo), driving-mode pill ("En route · voice-only capture … hands-free safe"), `Cancel` / `Stop + send`. Dark variant shows pre-record state with carried replies and "Record" CTA.

### UI elements → backend map
| Element | Data/Action | Backend | Notes |
|---|---|---|---|
| Thread header (reply target + thread id) | Thread ref | `messages.getConversation` (messages.ts:800) |
| Live mic + waveform | Audio capture | client-side |
| Live transcription + confidence | STT | `voiceESANG.transcribeAudio` (voiceESANG.ts:88), `voiceESANG.processVoiceCommand` (voiceESANG.ts:20) |
| Quick alternate chips (Acknowledged / Running on time / Fueling now / Share dock photo) | Snippet insert | **GAP** — no `voiceESANG.getQuickReplies` / no messaging.ts `getQuickResponses` contents (stub at messaging.ts:681 returns `{items: []}`) |
| Driving-mode pill ("voice-only") | HOS-aware mode | `driverMobile.getDriverHosStatus` (driverMobile.ts:1496), `eld.currentDuty` |
| `Stop + send` primary CTA | Send transcribed msg w/ GPS stamp | `messages.sendMessage` (messages.ts:279) + `voiceESANG.transcribeAudio` (voiceESANG.ts:88); **GAP** — no combined "send-voice-message-with-gps" procedure |
| `Cancel` | Discard | client-side |
| AI rationale ("Sarah's 12/14 approved…") | | **GAP** |
| Dark: "Carried replies" list | Draft queue | **GAP** — no voice-draft queue procedure |
| Dark: "Parked — safe to record" gate | Motion guard | `telemetry.*`; **GAP** for explicit motion-gate procedure |

### Backend GAPS (numbered)
1. Pre-populated quick-reply snippets procedure missing (stub returns empty).
2. No atomic voice+transcript+GPS-stamp send endpoint.
3. No voice-draft / carried-replies queue.
4. Motion-gate ("is it safe to record") not exposed.

### User-journey entry points
- Thread (113) mic icon.
- Inbox row (112) "Voice note" chip.
- Dispatch radio (`communicationHub.getDispatchRadio` communicationHub.ts:953) escalation.
- Required state: driverId, conversationId, microphone permission, optional HOS status, GPS.

---

## Summary

**Totals**
- Screens audited: 13 (103–115), Light + Dark for every screen.
- Swift ports wired: **0 / 13** (Swift Driver folder ends at `022_DockAssigned.swift`).
- UI elements mapped (approx): ~110 across all screens.
- Elements with a real backend procedure: ~76.
- Elements marked GAP (no procedure or stub): ~34.
- **% backed: ~69% (76/110).**
- Backend GAPS enumerated: **28 numbered items** across the 13 screens.

**Top-3 gaps (impact-weighted)**
1. **AI narrative / advisor endpoints are missing across every screen** — fuel, DVIR, safety, maintenance, loads, claims, inbox, thread, broadcasts, voice reply all surface LLM copy that no `.query` returns. A single `esangAdvisor.narrate({screen, context})` procedure would close 10+ gaps.
2. **Acknowledge / snooze / markAllRead mutations are inconsistent** — `resourceBroadcasts` has no `acknowledge`/`snooze` (114), `messages` has per-thread `markAsRead` but no bulk `markAllRead` (112), accessorial has no `saveDraft` (110). These are small mutations blocking core CTAs.
3. **Roadside ticket lifecycle is half-built** — `driverMobile.getRoadsideAssistance` (driverMobile.ts:742) only *creates* a ticket; there is no list, detail, event-timeline, close, or policy-lookup procedure, yet screen 107 (light + dark) shows the full lifecycle UI including an event stream.

Report authored 2026-04-18.
