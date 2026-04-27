# Wave-3 Agent 05 — Driver Bucket 05 Audit

Bucket: 13 screens (6 duplicate numbers 072–077). Backend root: `/Users/diegousoro/Desktop/eusoronetechnologiesinc/frontend/server/routers/`. Swift port root: `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/EusoTrip/Views/Driver/` (ports exist only for screens 010–022; none of the Wave-3 bucket screens are ported).

---

## 071 Daily Streak and Quest.png
**Swift port:** MISSING (no 071 file under Views/Driver)
**Purpose:** Gamification home tile showing current streak, tier progress, this-week check-ins, today's quest, ESANG narration, and XP claim.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Header clock "14:55 / 22:59" | Device time | n/a | Local |
| "Active streak · 11 / 17 day streak" big tile | Driver streak counter | `advancedGamification.getStreakTracker` (advancedGamification.ts:1476) | Returns streak data |
| "PD 22" / "PD 28" badge + "Next tier Day 14 · +3% fuel card" | Streak perk / tier | GAP — no `streakTiers.get` procedure (advancedGamification returns but no tier-perk map) | Fuel card bonus not wired |
| "On-time Wawa Lancaster drop · Cleared" quest card | Quest item (completed) | `advancedGamification.getDailyQuests` (l.1227) | Lists today's quests |
| "Bay 6 gasoline drop verified Fri 14:24…" sub-text | Quest verification detail | GAP — quest schema lacks verification timestamp field | |
| This Week calendar row (M-S dots) | Weekly streak history | `advancedGamification.getStreakTracker` (l.1476) | Partial — shape unknown |
| "Today's Quest — ESANG No Saturday haul…" card | Quest content from ESANG copilot | `advancedGamification.getDailyQuests` + `esangAI.*` | Copy overlay likely via `esangAI.generateBrief` (verify) |
| "History" button | Navigate to past streaks | GAP — `getStreakHistory` not present | |
| "Claim +40 XP →" CTA | Mutation to award XP | `advancedGamification.completeDailyQuest` (l.1311) | Maps to claim |
| Tab bar: Home / Trips / Ctr pylon / Wallet / Me | Nav | n/a (router-level) | |

### Backend GAPS (numbered)
1. No dedicated `streakTiers` data source returning fuel-card % perk thresholds.
2. Quest verification evidence (POD timestamps) not exposed on quest item payload.
3. No `getStreakHistory` procedure for the "History" button.

### User-journey entry points
- Tab bar Home → scroll down from Home Today card (076) → Streak tile.
- Notification deeplink "Streak at risk" (from notifications.getSummary).
- Required backend state: `gamificationProfiles` row for userId (advancedGamification uses `ctx.userId` implicitly).

---

## 072 ERG Reference.png
**Swift port:** MISSING
**Purpose:** Emergency Response Guidebook lookup for hazmat (UN1203 gasoline / UN1005 ammonia), with related guides and ESANG callout.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Guide header "Guide 128 · Flammable Liquids · Gasoline (UN1203)" | Guide page metadata | `erg.getGuidePage` (erg.ts:116) | |
| "UN 1203 · Class 3 · PG II" chips | Hazard class | `erg.getHazardClass` (l.127) | |
| Inhalation / Fire / Spill blocks | Guide body | `erg.getGuidePage` (l.116) | Guide body structured |
| Protective Distance "Initial 150 ft / Protective 0.3 mi" | Distance data | `erg.getGuidePage` (payload includes distances) | |
| Related guides list (128, 127, 129 etc.) | Related cross-refs | GAP — no `erg.getRelatedGuides`; exists only search-by-name | Could use `erg.searchByName` as fallback |
| ESANG callout | AI narration | `esangAI.*` (needs generateErgCallout) | GAP as dedicated procedure |
| History button | Recent lookups | `erg.getRecentLookups` (l.170) | |
| "Open full guide →" CTA | Full-text guide render | `erg.getGuidePage` (l.116) | Same endpoint, larger payload |
| Tab bar | Nav | n/a | |

### Backend GAPS (numbered)
1. `erg.getRelatedGuides(guideNum)` not implemented.
2. ESANG ERG-specific brief generator not defined (only generic AI router).
3. No log-on-open telemetry beyond `erg.logLookup` — UI does not expose it (minor).

### User-journey entry points
- Trip Detail hazmat chip tap → ERG screen.
- Active load with hazmat class → Home Today hazmat pill → ERG.
- Required backend state: Load row with `hazmatUN`/`hazmatClass` fields, driver's `activeLoadId`.

---

## 072 Trips Home.png
**Swift port:** MISSING
**Purpose:** Driver trips dashboard — in-progress trip card, next-up tendered list, week KPIs, recently completed, ESANG margin tip, "View all trips" CTA.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Header "Week of Apr 13 · 2026 / 4 trips" pill | Weekly trip counter | `loads.getHistoryStats` (loads.ts:1316) | Partial — "trips" = loads assigned |
| Active trip card (Yara York → Wawa Lanc. Bay 6 · EUSO-2481) | Active load detail | `loads.getById` (l.1012) + `tracking.getTrackedLoads` | |
| Status pill "Active" / ETA 15:48 / Revenue $1,762 | Live telemetry | `tracking.getTrackedLoads` (loads.ts:689) + `loads.getById` | Revenue from loads row |
| Progress bar (Miles to Wawa) | ETA miles | `routes.getETA` (routes.ts:225) | |
| Next Up section · 2 tendered rows | Upcoming tendered loads | `loads.list` or `loads.getMarketplaceLoads` (l.2866) | Filter status=tendered |
| "Runs 3 / Miles 812 / Revenue $5,284 / On-time 100%" KPI row | Weekly driver metrics | `loads.getHistoryStats` (l.1316) + `dashboard.getDriverScorecards` (dashboard.ts:571) | On-time score may be GAP field |
| Recently completed loads list | History | `loads.getHistory` (l.1338) | |
| ESANG "Hazmat multiplier +22%…" callout | AI brief | `esangAI.*` | Verify |
| "View all trips →" | Navigate | n/a | |
| Tab bar | Nav | n/a | |

### Backend GAPS (numbered)
1. On-time percentage field not explicit on `dashboard.getDriverScorecards` payload.
2. No dedicated `trips.getWeekly` procedure — must aggregate loads.
3. "Anchors / load count" chip (5 anchors) has no matching procedure for the "anchors" concept.

### User-journey entry points
- Tab bar "Trips" icon.
- Push notification "Load assigned" → Trips Home.
- Required backend state: at least one `loads` row with `assignedDriverId = ctx.userId` and status in active/tendered set.

---

## 073 Tax and 1099 Detail.png
**Swift port:** MISSING
**Purpose:** YTD 1099 contractor earnings summary with gross / factoring fee / net paid, mileage, hazmat equip, per diem nights, filed 1099 card, ESANG projection, Export CSV & Download 1099 CTAs.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| YTD Net Paid 2026 tile ($21,258.94 / $33,426.18) | 1099 YTD | `taxReporting.getContractorSummary` (taxReporting.ts:24) + `taxReporting.getDashboard` (l.287) | |
| "Across 27 hauls · Gasoline lane contributed 62% · Home carrier Catalyst Transport" sub-text | Haul counts + top lane + carrier | GAP — summary does not break down by lane | |
| Gross Earnings / Platform+Factoring Fee / Net Paid breakdown | Tax breakdown | `taxReporting.getContractorSummary` (l.24) | |
| Mileage 7,210 mi / Hazmat Equip $742 / Per-diem 22 nights tiles | Deductible metrics | `taxReporting.getContractorSummary` (mileage) + GAP for hazmat equip & per-diem breakdown | per-diem nights not in schema |
| "Form 1099-NEC - 2025 · FILED · $118,842.50" card | 1099 detail row | `taxReporting.get1099Detail` (l.209) + `taxReporting.list1099s` (l.157) | |
| ESANG "Q1 run-rate projects…" | AI projection | `esangAI.*` | Verify |
| Export CSV button | CSV export | `exports.create` (exports.ts:16) | Generic |
| Download 1099 → CTA | PDF download | GAP — no `taxReporting.download1099` (form served via `get1099Detail` only) | |
| Tab bar | Nav | n/a | |

### Backend GAPS (numbered)
1. Lane-contribution percentage not computed by `taxReporting.getContractorSummary`.
2. Hazmat equipment deduction + per-diem nights counter not in taxReporting schema.
3. No `download1099` endpoint returning signed URL for FILED PDF.

### User-journey entry points
- Me/Profile → Wallet & Payouts → Tax section.
- Wallet screen "Tax docs" pill → this screen.
- Required backend state: `contractorProfile` row, at least one `taxForm` entry for 2025 (status = FILED).

---

## 073 Trip Detail.png
**Swift port:** MISSING (closest related: 013_ActiveEnroute, 017_PickupBolSigning)
**Purpose:** Deep detail for a single load (#EUSO-2481 / #EUSO-2488) — stops timeline, shipper/consignee, revenue breakdown, document chips, ESANG timeline, Report issue & Open in map CTAs.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Header back + "#EUSO-2481 · Gasoline · MC-306" | Load id + carrier | `loads.getById` (loads.ts:1012) | |
| Status pill "In transit / Delivered" | Status | `loads.getById` + `loads.updateLoadStatus` (l.2774) | |
| Route hero "Yara York, PA → Wawa Lanc." | Origin/dest | `loads.getById` | |
| Hazmat / Class chips | Hazmat fields | `loads.getById` (hazmat props on row) | |
| Miles 58 / ETA 15:48 / Revenue $1,762 tiles | Live metrics | `routes.getETA` (routes.ts:225) + `loads.getById` | |
| Timeline pickup / transit / drop rows | Stop events | `loads.getTimeline` (l.1507) | |
| Shipper "Yara North America Inc." + Destination | Party info | `shippers.*` via `loads.getById` join | |
| Revenue table (Linehaul / Hazmat premium / FSC / Net) | Settlement preview | GAP — `earnings.getPayStatement` (earnings.ts:224) returns per-settlement not per-load | |
| Action chips: BOL / POD / Ratecon / Manifest | Document open | `loads.getDocuments` (l.1586) + `documents.*` | |
| ESANG "On glide · Bay 6 staged · Grounding strap verified" | AI narration | `esangAI.*` | |
| Report issue button | Create issue | `driverMobile.reportSafetyIssue` (driverMobile.ts:1679) | |
| Open in map → | Launch nav | GAP for server — client-only | |
| Tab bar | Nav | n/a | |

### Backend GAPS (numbered)
1. Per-load revenue breakdown (linehaul / FSC / hazmat premium / net-to-driver) not returned by `loads.getById` — must pull from `settlements`.
2. "Grounding strap verified" telemetry not surfaced as load event.
3. No dedicated `loads.getDocuments` chip state (open/signed/pending) — only list.

### User-journey entry points
- Trips Home active-trip tap → Trip Detail.
- Notification "Load delivered" → Trip Detail.
- Required backend state: `loads` row owned by ctx.userId; at least one stop timeline entry.

---

## 074 Notification Center.png
**Swift port:** MISSING
**Purpose:** Driver inbox with filter pills (All / Unread / Hauls / Wallet), grouped by Today/Yesterday, per-item badges (Hauls, Wallet, Alert), Clear + Mark-all-read actions, ESANG summary.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Filter pills (All 28 / Unread 12 / Hauls / Wallet) | Filtered lists | `notifications.list` (notifications.ts:51) + `notifications.getCategoryCounts` (l.140) | |
| Notification row "Monday NH3 pickup confirmed · Hauls" | Single item | `notifications.list` | |
| Sub-text (slot, load id) | Notification payload | `notifications.list` payload | |
| "Open" / "Paid" / "Verify" action chip | Deep link / mark action | GAP — per-item action token not in schema | |
| "Today / Yesterday" section headers | Date grouping | Client-side grouping of `notifications.list` | |
| ESANG summary bar | AI narration | `esangAI.*` | |
| Clear button | Bulk delete | `notifications.delete` (l.252) × selection | No bulk endpoint |
| Mark all read → | Bulk read | `notifications.markAllAsRead` (l.198) | |
| Tab bar | Nav | n/a | |

### Backend GAPS (numbered)
1. No `notifications.clearAll` / `bulkDelete` — only per-id delete.
2. No action-token field returned to drive the per-row "Open/Paid/Verify" CTA.
3. No `notifications.getGroupedByDay` — client must aggregate.

### User-journey entry points
- Tab bar bell icon or swipe-right from Home.
- Push-notification tap.
- Required backend state: rows in `notifications` for ctx.userId with `isRead = false` counts; `notifications.getSummary` feeds the badge.

---

## 074 Trip History.png
**Swift port:** MISSING
**Purpose:** 30-day trip ledger with filter chips (This week / Hazmat / Dry / Cancelled / 30 days), KPI row, grouped by week with per-trip revenue, ESANG trend note, Export 30-day ledger CTA.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Header "Trip history · Mar 18 – Apr 17 · 30 days" + trips pill | Range selector | `loads.getHistory` (loads.ts:1338) + `loads.getHistoryStats` (l.1316) | |
| Filter chips (This Week / Hazmat / Dry / Cancelled / 30 days) | Filters | `loads.getHistory` via input.status / input.period | Hazmat / dry filter GAP (no product-type filter on endpoint) |
| KPI row (Runs 9 / Miles 3,842 / Revenue $26,410 / $/mi $6.87) | Aggregates | `loads.getHistoryStats` (l.1316) | Returns basic stats; $/mi may be GAP |
| Per-trip rows w/ class badges (GS, NH3, CL2) | Product class | `loads.getHistory` with product profile join | `productProfiles` |
| Cancelled line (strikethrough) | Cancelled row | `loads.getHistory` status filter | |
| PTO / "Off-duty" row in week block | HOS off-duty day | `hos.getLogHistory` (hos.ts:146) | Separate call, client merges |
| ESANG "Hazmat +22% vs dry · NH3 nights driving +1 lift" | AI | `esangAI.*` | |
| Export 30-day ledger → CTA | Export | `exports.create` (exports.ts:16) + `loads.exportCSV` (l.1986) or `loads.exportHistory` (l.3247) | |
| Tab bar | Nav | n/a | |

### Backend GAPS (numbered)
1. No product-class filter input on `loads.getHistory` (needs hazmat/dry filter).
2. `$/mi` (rev-per-mile) not returned by `getHistoryStats` — client computes.
3. Merging HOS off-duty row with load rows needs a unified `tripHistory.feed` endpoint (not present).

### User-journey entry points
- Trips Home → "View all trips" CTA.
- Me/Profile → Trip history row.
- Wallet → settlement detail → linked trips.
- Required backend state: at least one `loads` row delivered/cancelled within period.

---

## 075 Lane Radar.png
**Swift port:** MISSING
**Purpose:** Driver-authored lane watchlist (3 lanes / 250 mi radius) surfacing live load hits, match rate, response TTL, per-lane push toggle + $/mi floor, ESANG advice, Accept NH3 tender CTA.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Header "Lane radar · 3 lanes / 250 mi radius · 1 match" | Watchlist summary | `loadBoard.getSavedSearches` (loadBoard.ts:1124) + `loadBoard.getAlerts` (l.1164) | |
| "Dry market cooling…" digest card w/ matches / Top $/mi / Response TTL | Market digest | GAP — no `laneRadar.getDigest` procedure | Could compose from `loadBoard.getMarketRates` (l.1229) |
| Lane chips (NH3 Yara→Wawa / GS Yara→Harrisburg / CL2 Allentown→Beth.) | Saved lanes | `loadBoard.getSavedSearches` (l.1124) | |
| "Live hits" list (#EUSO-2498 / #EUSO-2501) | Matching loads | `loadBoard.search` (l.655) w/ saved search filters | |
| Push toggle / $/mi floor slider / Radius 250 mi | Notification rule | `notifications.updatePreferences` (notifications.ts:337) + `loadBoard.saveSearch` (l.1133) | Partial — `minRatePerMile` field GAP on saveSearch |
| ESANG "Tender best margin tonight · hold 60 min" | AI | `esangAI.*` | |
| "+ Add lane" button | Create saved search | `loadBoard.saveSearch` (l.1133) | |
| "Accept NH3 tender →" CTA | Book matched load | `loads.book` (loads.ts:1897) or `loadBoard.bookLoad` (l.934) | |
| Tab bar | Nav | n/a | |

### Backend GAPS (numbered)
1. No unified `laneRadar.getDigest` returning matches + top $/mi + response TTL.
2. `saveSearch` input does not currently accept `minRatePerMile` and radius combined.
3. No `laneRadar.toggleAlerts(searchId, on)` — uses generic `notifications.updatePreferences`.

### User-journey entry points
- Home Today "Hazmat multiplier +22%" banner → Lane radar.
- Tab bar Trips → Lane radar sub-tab (likely).
- Required backend state: ≥1 saved search in `savedLoadSearches` for ctx.userId; open loads matching.

---

## 075 Load Board Search.png
**Swift port:** MISSING
**Purpose:** Outbound load-board search from Carlisle, PA with hazmat / class / sun-mon / 120 mi / tanker filter chips, Top Spectra-match hero card, alternate matches list, saved search context, Save search + Request load CTAs.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Origin/Dest row "Carlisle, PA → Open" | Search inputs | `loadBoard.search` (loadBoard.ts:655) | |
| Filter chips (Hazmat · Class 3 · Sun-Mon · 120 mi · Tanker) | Query params | `loadBoard.search` input | |
| Top Spectra-Match score pill "91 / 94 · Excellent" | Match score | `loads.enhancedMatchLoadsToCarrier` (loads.ts:2579) or `spectraMatch.*` | Verify `spectraMatch` router |
| Hero card Wawa Lancaster → Philadelphia w/ miles, drive, pickup, gross | Top match | `loadBoard.search` first result | |
| Alternate Matches rows (Sunoco, Citgo, Shell) | Search hits | `loadBoard.search` (l.655) | |
| "Matched from your saved lane Carlisle · Class 3 · Short-run · Auto-notify weekends · Score 4.98" | Saved-search context | `loadBoard.getSavedSearches` (l.1124) | |
| ESANG "Top match chains cleanly…" | AI | `esangAI.*` | |
| Save search button | Persist | `loadBoard.saveSearch` (l.1133) | |
| Request load → CTA | Submit bid / book | `loads.submitBid` (loads.ts:2542) or `loadBoard.bookLoad` (l.934) | |
| Tab bar | Nav | n/a | |

### Backend GAPS (numbered)
1. Match "score" surfaced as single 0-100 not fully exposed; `enhancedMatchLoadsToCarrier` returns list but score schema needs verification.
2. "Auto-notify weekends" flag not in `saveSearch` input schema.
3. No `loadBoard.requestLoad` flow — must dual-call bid + notify broker.

### User-journey entry points
- Lane Radar "+ Add lane" → Load board search.
- Home Today empty-next-trip state → search.
- Required backend state: driver has origin (current city) cached in profile; at least one matching open load row.

---

## 076 Home Today.png
**Swift port:** MISSING (closest: 010_DriverHome.swift covers similar pattern)
**Purpose:** Driver home hub — greeting, active trip card, today's timeline (anchors), ESANG morning brief, quick-action buttons (Resume map / BOL ready / HOS log / Dispatch), HOS+fuel+score KPI row, Resume-drive CTA.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Greeting "Afternoon, Driver Marcus" | Profile | `profile.getMyProfile` (profile.ts:27) | |
| Active trip hero w/ revenue & ETA | Active load | `loads.getById` + `tracking.getTrackedLoads` | Same as Trips Home |
| Today / Tomorrow anchor rows (Drop Wawa Bay 6 / Sinclair NH3 overnight / Yara Harrisburg dry-gas) | Stop queue | `driverMobile.getDriverSchedule` (driverMobile.ts:1379) | |
| Hazmat pill | Product profile | `productProfiles.*` | |
| ESANG "Morning brief · Hazmat multiplier +22%…" | AI brief | `esangAI.*` generateBrief | verify |
| Quick actions: Resume map / BOL ready / HOS log / Dispatch | 4 action buttons | `driverMobile.getQuickActions` (l.1599) lists them; each maps to: routes.plan, bol.generate, hos.getStatus, dispatch.* | Partial — "Resume map" client-only |
| HOS Left 07:52 / Fuel 78% / $/mi Good | Status tiles | `hos.getStatus` (hos.ts:32) + `eld.getVehicleLocations` (eld.ts:407) | $/mi-rating GAP |
| "Resume drive to Bay 6 →" CTA | Launch nav + update status | `loads.updateLoadStatus` (loads.ts:2774) + `hos.changeStatus` (hos.ts:93) | |
| Tab bar | Nav | n/a | |

### Backend GAPS (numbered)
1. No `driverMobile.getMorningBrief` — ESANG copy computed ad-hoc.
2. Fuel-% comes from `eld.*` but no consolidated `driverMobile.getVehicleStatus` combining fuel + HOS + score.
3. "$/mi score Good" color band mapping not specified in any procedure.

### User-journey entry points
- App launch → Tab bar Home (default).
- Push "Your day starts at 04:30" → Home.
- Required backend state: `gamificationProfiles`, `hosLogs`, at least one open `loads` row assigned to driver.

---

## 076 Me Profile.png
**Swift port:** MISSING
**Purpose:** Driver "Me" tab — avatar, identity, verified + role chips, KPI tiles (Score 92 / Loads 241 / $/mi 37.3 / Streak 8d), status chips, nav rows to Vehicle & Trailer, Trip history, Certifications, Wallet, Settings, ESANG renewal note, Sign out + Edit profile.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Avatar + name "Michael Eusorone" | Profile | `profile.getMyProfile` (profile.ts:27) + `profile.updateAvatar` (l.90) | |
| Role chips "Driver · Owner-operator · Carlisle PA" | Profile data | `profile.getMyProfile` | |
| Verified / MC-306 chips | Verification | `profile.getMyProfile` + `authority.*` | |
| "Member since Mar 2024" | Profile meta | `profile.getMyProfile` | |
| KPI tiles (Score 92 / Loads 241 / $/mi 37.3 / Streak 8d) | Driver KPIs | `profile.getDriverProfile` (l.110) + `advancedGamification.getStreakTracker` (l.1476) | $/mi may be GAP field on profile |
| Status chips (Off-duty / On-break / Class 3 R=847 / Safety 4) | HOS + safety | `hos.getCurrentStatus` (hos.ts:50) + `safety.*` | safety "4" source unclear |
| Vehicle & Trailer row | Nav to 077 | `vehicles.get` (vehicles.ts:57) | Links via `vehicles.assignDriver` |
| Trip history row | Nav | `loads.getHistory` | |
| Certifications & documents row | Nav | `certifications.list` (certifications.ts:25) + `certifications.getExpiring` (l.212) | |
| Wallet & payouts row | Nav | `wallet.getSummary` (wallet.ts:288) | |
| Settings & privacy row | Nav | `settings.*` | |
| ESANG "MC-306 hazmat endorsement renews in 41 days…" | AI note | `certifications.getExpiring` + `esangAI.*` | |
| Sign out button | Auth | `users.signOut` (verify) | |
| Edit profile → | Navigate | `profile.updateProfile` (l.59) | |
| Tab bar | Nav | n/a | |

### Backend GAPS (numbered)
1. Safety score (integer "4") not exposed by any single procedure (likely from `safetyRisk.*` but not aggregated on profile).
2. $/mi KPI not precomputed — currently ad-hoc.
3. No `profile.getKpiTile` returning all four tiles in one call.

### User-journey entry points
- Tab bar Me icon.
- Deep-link from Catalyst onboarding.
- Required backend state: `users` row, `driverProfile`, `gamificationProfiles`, assigned `vehicle`, `certifications` rows.

---

## 077 Home Schedule.png
**Swift port:** MISSING
**Purpose:** Week schedule view — day tabs Mon-Sun, Next substantive block card (Sinclair NH3 overnight · hold by 17:30), Today/Tomorrow/Future grouped rows, off-duty reset, ESANG weekly digest, Plan next week CTA.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Schedule "This week · Apr 13 – 19" header | Period | `driverMobile.getDriverSchedule` (driverMobile.ts:1379) | |
| Day chips M-S with numbers (13-19) | Week days | `driverMobile.getDriverSchedule` shape | |
| "Next substantive block — Sinclair NH3 overnight" card | Flagged anchor load | GAP — no "substantive block" flag on schedule item | |
| Pickup 18:30 / Load #EUSO-2498 / Revenue $1,923 | Anchor detail | `loads.getById` (l.1012) | |
| Today / Saturday / Sunday row grouping | Daily agenda | `driverMobile.getDriverSchedule` | |
| "Off-duty · Dekalb yard" row | HOS reset block | `hos.getLogHistory` (hos.ts:146) | |
| ESANG "Hazmat multiplier +22%…" | AI | `esangAI.*` | |
| Weekly digest tiles (Week miles 1,240 / Hazmat loads 3 / Off-duty hrs 18h) | Aggregates | `dashboard.getDriverScorecards` (dashboard.ts:571) + `hos.getLogHistory` | GAP for hazmat loads counter field |
| Plan next week → CTA | Open week planner | GAP — no `driverMobile.planNextWeek` mutation | |
| Tab bar | Nav | n/a | |

### Backend GAPS (numbered)
1. No "substantive block" flag (the most-important anchor of the week) on schedule items.
2. Weekly hazmat-load counter not part of scorecards payload.
3. `planNextWeek` planner endpoint absent (CTA has no target).

### User-journey entry points
- Tab bar Home → swipe left to Schedule view (likely).
- ESANG "plan next week" push.
- Required backend state: `loads` rows with future `pickupDate`; `hosLogs` for week; `gamificationProfiles.stats`.

---

## 077 Vehicle Trailer.png
**Swift port:** MISSING
**Purpose:** Assigned rig detail — tractor + trailer hero (EP-T-1840, MC-306 NH3 tanker), health tiles (Days/Fuel/DEF/PSI-Brake), maintenance schedule (PM-A oil & filter, brake-stroke, NH3 re-cert), Docs chips (Reg / Insurance / Annual 1460 / IFTA Q1), ESANG recert note, DVIR + Schedule maintenance CTAs.

### UI elements → backend map
| Element | Data/Action | Backend (router.procedure or "GAP") | Notes |
|---|---|---|---|
| Hero row tractor + trailer ids | Assigned vehicle + trailer | `vehicles.get` (vehicles.ts:57) + `equipment.getById` (equipment.ts:70) | |
| "Staged / Home ready" chip | Vehicle status | `vehicles.updateStatus` (l.163) + `vehicles.get` | |
| "Last seen Wawa Lancaster PA · 3m ago" | Telemetry | `vehicles.getLocation` (l.287) + `telemetry.*` | |
| Tile row: Day cabs / DOLS / 186 HP / 18-speed | Vehicle spec | `vehicles.get` | |
| Tile row: 411 mi / 42 fuel / 71 DEF / 122 PSI brake | Telemetry | `vehicles.getLocation` (partial) + `telemetry.*` | DEF & PSI-brake fields likely GAP |
| Maintenance Schedule rows (PM-A / Brake / NH3 re-cert) | PM items | `fleetMaintenance.getPreventiveSchedule` (fleetMaintenance.ts:350) | |
| "IN 4,100 MI / IN 180 / IN 56" chips | Due indicator | `fleetMaintenance.getPredictiveAlerts` (l.1898) or `getMaintenanceDue` on vehicles (vehicles.ts:321) | |
| Docs chips (REG CURRENT / INSURANCE / ANNUAL 1460 / IFTA Q1 OK) | Vehicle docs | `vehicles.getDocuments` (l.266) + `certifications.list` | |
| ESANG "NH3 coupler recert due in 9 days…" | AI | `esangAI.*` + `fleetMaintenance.getComplianceCalendar` (l.2058) | |
| DVIR button | Start DVIR | GAP in routers — maps to Swift `011_PretripDVIR.swift`; needs `dvir.create` | No explicit DVIR router found |
| Schedule maintenance → CTA | Book PM | `fleetMaintenance.createWorkOrder` (l.437) or `vehicles.scheduleMaintenance` (l.382) | |
| Tab bar | Nav | n/a | |

### Backend GAPS (numbered)
1. No `dvir` router or `dvir.create` procedure — Swift DVIR view has no backing endpoint documented.
2. DEF % and PSI-brake readings not in `vehicles.getLocation` payload — needs `telemetry.getVehicleMetrics`.
3. Vehicle doc chips don't have a unified "status color" (current/expiring/expired) payload.

### User-journey entry points
- Me tab → "Vehicle & trailer" row.
- Home Today morning brief → DVIR required → 077.
- Required backend state: driver has `assignedVehicleId` on `driverProfile`; vehicle has PM schedule + docs.

---

## Summary
- **Total screens audited:** 13
- **Swift ports present:** 0 / 13 (0%). All Wave-3 Driver bucket-05 screens are **unported** (Swift coverage stops at 022).
- **UI elements fully backed by backend procedures:** ~58 / ~95 = **≈61% backed**. Most header chrome, list endpoints, and core CRUD exist; gaps cluster around (a) aggregate/digest endpoints, (b) ESANG-specific copy generators, (c) mobile-first composite procedures, and (d) DVIR and lane-radar specialization.

### Top-3 backend gaps across the bucket
1. **No DVIR router.** 077 Vehicle Trailer's DVIR CTA (and Swift 011_PretripDVIR) have no procedures (`dvir.create`, `dvir.submit`, `dvir.list`) in `frontend/server/routers/`.
2. **ESANG per-screen copy generators missing.** Each screen shows an ESANG callout, but there is no dedicated `esangAI.generateBrief({screen, context})` — routers exist but the screen-specific variants (morning brief, lane digest, trip narration, ERG guide blurb) are not implemented.
3. **Aggregate / digest endpoints missing.** `laneRadar.getDigest`, `driverMobile.getMorningBrief`, `trips.getWeekly`, `profile.getKpiTile`, `notifications.getGroupedByDay` and `taxReporting.download1099` would each collapse multiple client calls into one and are not present.

### Cross-cutting recommendations
- Add a `dvir` router wired to `driverQualification` and `vehicles`.
- Extend `loadBoard.saveSearch` input schema to include `minRatePerMile`, `radiusMiles`, `autoNotifyDays[]`.
- Add `scoreCategory` (numeric 0-100) + color band to `dashboard.getDriverScorecards`.
- Add per-load settlement preview (`loads.getRevenueBreakdown(loadId)`).
- Port screens 071–077 to Swift under `Views/Driver/`.
