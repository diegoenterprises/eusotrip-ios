# EusoTrip iOS — Mock Data Inventory

**Audit date:** 2026-04-22
**Repo:** `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/`
**Scope:** iPhone app target (`EusoTrip/`). Watch targets excluded.
**Target:** 0% mock data across all surfaces.

---

## Summary

- **Real tRPC API client exists:** yes — `EusoTrip/Services/EusoTripAPI.swift` (~2,100 LOC, ~80 async endpoints, Azure backend).
- **Screens already wired to live data:** Driver Home (010), HOS Duty Status (019), DVIR (011/012), News (MeNewsView), HotZones widget, Auth (001–006), Registration, ELD integration, AddPaymentAccount (Plaid + Stripe).
- **Screens still on seeded arrays:** Eusoboards load board, My Loads sheet, EusoWallet transactions & earnings, most `MeDetail*` screens, Driver Conversation / Dispatch chat, ESANG coach composer canned replies, Fleet Mgmt, Tax, Haul (gamification), Missions, Rewards, Badges, Availability.
- **Total offenders flagged below:** ~70 rows across ~30 files.

---

## Inventory Table

Legend — **Effort**: S = <1h rewire (endpoint already in `EusoTripAPI.swift`), M = 1–4h (needs small tRPC tweak or new model glue), L = 4h+ (backend endpoint missing — belongs in Phase 3 empty state).

### Eusoboards / Loads

| File | Line | What is fake | Suggested real source | Effort |
|---|---|---|---|---|
| `Views/Driver/DriverTabPanes.swift` | 89 | `equipmentChips` hardcoded 7-item list ("All", "Dry Van", …) | Static enum is fine — keep in client, not mock data. | — |
| `Views/Driver/DriverTabPanes.swift` | 96–151 | `board: [AvailableLoad]` — 6 fake loads (Dallas→Atlanta, Memphis→Chicago, PACCO Logistics, rate/rpm, hot scores) | `loads.search` / new `loads.listAvailable` tRPC — `EusoTripAPI.Loads.search()` already exists at line 393 | M |
| `Views/Driver/DriverTabPanes.swift` | 1296–1342 | `MyLoadsSheet.loads` — 8 fake MyLoad entries across active/pending/finished buckets | `loads.search(status: "assigned/pending/completed")` — endpoint exists | S |
| `Views/Driver/DriverTabPanes.swift` | 1673–1718 | Duplicate `MyLoad` array inside 2nd tab-content view (same dummy data) | Same; consolidate to single store then hydrate | S |
| `Views/Driver/010_DriverHome.swift` | 67–113 | `suggestedLoads: [AvailableLoad]` — 5 dummy loads for "no active load" carousel | `loads.listAvailable` (add) — or reuse Eusoboards query | M |
| `Views/Components/HereMapView.swift` | 496, 500, 513 | Preview sample routes Dallas→Atlanta, Memphis→Chicago | Gated to preview — flag & keep behind `#Preview` only | S |

### EusoWallet / Earnings / Tax / Fleet

| File | Line | What is fake | Suggested real source | Effort |
|---|---|---|---|---|
| `Views/Driver/DriverTabPanes.swift` | 2021 | `$4,118.22` balance text literal | `wallet.getBalance` — already in `EusoTripAPI.Wallet.getBalance()` (line 1003) | S |
| `Views/Driver/DriverTabPanes.swift` | 2025 | "Settlement preview · POD clears in 21h · Factoring available at 1.5%" static subtitle | `wallet.getInstantPayoutEligibility` (line 1017) + settlement endpoint (missing) | M |
| `Views/Driver/DriverTabPanes.swift` | 2029–2031 | MetricTiles This week $2,440 / Pending $1,820 / YTD $68.4k | New `wallet.getEarningsSummary` router (missing) | L |
| `Views/Driver/DriverTabPanes.swift` | 2078–2085 | Hardcoded Chase 4921 + Visa 7088 payment method rows | `wallet.listPaymentMethods` (missing on backend; Plaid/Stripe attach procs exist at 923, 975) | M |
| `Views/Driver/DriverTabPanes.swift` | 2144–2155 | `txns: [Txn]` — 5 fake transactions (Load TRP-4492 Memphis→Atlanta, Flying J Dallas, Platform fee) | New `wallet.getTransactions({filter,cursor})` router (missing) | L |
| `Views/Driver/DriverTabPanes.swift` | 2258+ | Factoring offer "Advance $1,820 · 1.5%" (§5) | New `factoring.getOffer` router (missing) | L |
| `Views/Driver/DriverTabPanes.swift` | 2290+ | "Earnings breakdown" section — per-mile / detention / surcharge hardcoded amounts | Same earnings summary router (missing) | L |
| `Views/Driver/DriverTabPanes.swift` | 2350+ | "Tax & 1099" card — hardcoded YTD totals, 1099 availability | New `tax.getSummary` router (missing) | L |
| `Views/Driver/DriverTabPanes.swift` | 2376–2390 | Fuel card row "EusoFuel •••• 2214" + "$0.32/gal savings" | New `fuelCard.getStatus` router (missing) | L |
| `Views/Driver/MeDetailScreens.swift` | 223–228 | `MeEarningsView.weeks: [WeekRow]` — 4 fake weekly rollups | `wallet.getWeeklyHistory` (missing) | L |
| `Views/Driver/MeDetailScreens.swift` | 240 | `"$68,420"` YTD hardcoded hero | Same | L |
| `Views/Driver/MeDetailScreens.swift` | 244 | "Projected $184k … 46 loads completed YTD" literal | Same | L |
| `Views/Driver/MeDetailScreens.swift` | 250–256 | 4 MetricTiles $4,118 / $15,820 / $2.47 RPM / 9.2% deadhead | Same | L |
| `Views/Driver/MeDetailScreens.swift` | 384–390 | `MeTaxView.entries: [Entry]` — 5 fake inspections Apr 16–19 (moved to Zeun) | `inspections.getHistory` — already exists at line 733 | S |
| `Views/Driver/MeDetailScreens.swift` | 2653–2657 | `MeFleetView.assets: [Asset]` — ZEUN-4412 tractor, ESOR-DRY-2201 trailer, APU, Dallas home base | New `fleet.listAssets` router (missing) | L |
| `Views/Driver/MeDetailScreens.swift` | 2660–2664 | `maintenance: [Maintenance]` — PM-B, DOT annual, trailer brake, tire rotation | `zeun.getMaintenanceSchedule` (missing) | L |
| `Views/Driver/MeDetailScreens.swift` | 2667–2672 | `fuel: [FuelReceipt]` — Love's OKC $312.46, Pilot Amarillo $343.04, etc. | New `fuel.getReceipts` router (missing) | L |
| `Views/Driver/MeDetailScreens.swift` | 2682–2694 | "Utilization 88%", "2 units active", "217,840 odometer" | `fleet.getPosture` (missing) | L |
| `Views/Driver/MeDetailScreens.swift` | 1954–1959 | `MeZeunView.dvirEntries` — 5 fake DVIR entries | `inspections.getHistory` — wire to EusoTripAPI | S |

### Me Hub · Gamification / Badges / Rewards / Missions / Haul

| File | Line | What is fake | Suggested real source | Effort |
|---|---|---|---|---|
| `Views/Driver/MeDetailScreens.swift` | 1161–1230 | `missions: [Mission]` — 10 fake missions (Ten in flight, Fuel saver, Night owl, etc.) | `achievements.*` routers exist in `_WAVE4_BUILD/server/routers/achievements.ts` — frontend mirror missing | M |
| `Views/Driver/MeDetailScreens.swift` | 1505–1514 | `catalog: [Item]` — 8 fake reward catalog items (Love's fuel card, merino tee, cooler) | New `rewards.getCatalog` router (missing) | L |
| `Views/Driver/MeDetailScreens.swift` | 1517–1522 | `history: [History]` — 4 fake redemptions | New `rewards.getHistory` (missing) | L |
| `Views/Driver/MeDetailScreens.swift` | 1525–1536 | Hardcoded tiers Bronze/Silver/Gold/Platinum/Diamond + 3 crates Epic/Rare/Common | Catalog is static ok; XP thresholds need `loyalty.getConfig` | M |
| `Views/Driver/MeDetailScreens.swift` | 1801–1807 | `badges: [Badge]` — 6 fake badges (First 100, Road warrior, Safety seal, Eco driver, On-time hero, Haul champion) | `achievements.getUnlocked` (missing) | M |
| `Views/Driver/MeDetailScreens.swift` | 2871–2877 | Leaderboard `board: [Rival]` — Alisha P. / Marcus T. / You / Nina O. / Raj S. | `leaderboard.getSeason` router (missing) | L |
| `Views/Driver/MeDetailScreens.swift` | 2884 | "TOP 3%" status pill — hardcoded | Same `leaderboard` endpoint | L |
| `Views/Driver/MeDetailScreens.swift` | 2891 | Hero score `"4,640"` hardcoded | Same | L |
| `Views/Driver/MeDetailScreens.swift` | 488 | `days: [DayKey]` — static Mon–Sun (legit, not mock) | — | — |
| `Views/Driver/MeDetailScreens.swift` | 505 | `MeAvailabilityView.grid: [[Cell]]` — 7×24 duty grid preseeded | New `availability.getGrid` (missing) | L |
| `Views/Driver/MeDetailScreens.swift` | 558–561 | `blocks: [Block]` — 3 fake blocked slots (DOT Volvo of OKC, Zeun bay 3, Dentist Dr. Chen) | New `availability.getBlocks` (missing) | L |

### Conversation / Messages / ESANG Chat

| File | Line | What is fake | Suggested real source | Effort |
|---|---|---|---|---|
| `Views/Driver/MeDetailScreens.swift` | 3052–3077 | `DriverPulseLobby.messages` — 8 fake group-chat messages (Alisha P., Marcus T., Dispatch Nia, Raj S., Nina O., Fleet Eusorone, You) | `messaging.getMessages(conversationId:)` — exists at line 1552 | S |
| `Views/Driver/MeDetailScreens.swift` | 3079 | `activeCount = 143` hardcoded live-room count | New `rooms.getPresence` (missing) | L |
| `Views/Driver/DriverTabPanes.swift` | 3733–3740 | ESANG coach composer `messages: [Msg]` initial bank | `esangAIv2.chat` — exists at line 855; first greeting is cosmetic (keep) | — |
| `Views/Driver/DriverTabPanes.swift` | 3755–3760 | Canned quick-action chips (HOS buffer, Route weather, Fuel stop, Detention log) | Static chip array ok; canned replies live in code — migrate to `esangAI.getCoachCopy` | M |
| `Views/Driver/DriverTabPanes.swift` | 3131 | `InboxThread` array empty until filled — currently seeded hardcoded in code path | `messaging.getConversations` — exists at line 1546 | S |

### Trip lifecycle (screens 013 – 051)

| File | Line | What is fake | Suggested real source | Effort |
|---|---|---|---|---|
| `Views/Driver/017_PickupBolSigning.swift` | 35 | `driverName = "Marcus Reyes · CDL TX"` literal | `auth.me()` — exists at 553; already wired on 010 | S |
| `Views/Driver/028_LoadLockedPrehaul.swift` | 60+ | `checks: [PrehaulCheck]` hardcoded | New `loadWizard.prehaul.getChecks(loadId)` — `loadWizard.*` family exists at lines 1154+ | M |
| `Views/Driver/029_PickupArrival.swift` | 78+ | `steps: [PickupStep]` hardcoded | `loadLifecycle.executeTransition` (exists line 1069); steps should come from router | M |
| `Views/Driver/030_LoadingInProgress.swift` | 67+ | `triplet: [LoadingMetric]` fake fill/flow/temp | `tankMonitor.getLoadingSnapshot` (MISSING — _WAVE3_AUDIT §2.4 gap) | L |
| `Views/Driver/031_SpectraMatchVerdict.swift` | 61+ | `lanes: [LaneSample]` fake spectrographic lane data | New `spectra.getVerdict(loadId)` (missing) | L |
| `Views/Driver/032_DetachSequence.swift` | 67, 74 | `gauges`, `steps` hardcoded | New `bayOps/disconnectWizard.*` (MISSING — _WAVE3_AUDIT §2.3 gap) | L |
| `Views/Driver/033_BolSignoff.swift` | 84+ | `metrics: [BolMetric]` fake BOL confirmation metrics | `loadWizard.recordEvidence` — shape it from there (line 1172) | M |
| `Views/Driver/034_DepartingPickup.swift` | 71, 88 | `summary`, `firstLegPills` hardcoded | `loadLifecycle.getCurrentLeg` (missing) | M |
| `Views/Driver/036_ESangSmartStop.swift` | 155+ | `amenities: [AmenityIcon]` | `smartStops.getAmenities` (missing) | L |
| `Views/Driver/040_DischargeInProgress.swift` | 558 | `pts: [CGPoint]` — chart polyline (legit UI, not mock) | — | — |
| `Views/Driver/HotZonesWidget.swift` | 326 | `pts: [CLLocationCoordinate2D]` hardcoded polygon in preview | Gated to preview block | S |

### Auth · Profile · Settings

| File | Line | What is fake | Suggested real source | Effort |
|---|---|---|---|---|
| `Views/Driver/ProfileEditView.swift` | — | Initial values seeded from `DriverProfileStore` (UserDefaults) — ok, but defaults include fake name/email | `auth.me()` — wired | — |
| `Services/DriverProfileStore.swift` | multiple | Defaults "Marcus Reyes", driver@eusotrip.com, Dallas · TX, "4.92", "127 loads completed" | `auth.me()` — wired on first launch, but defaults persist if unauthenticated | S |
| `Models/Load.swift` | 153, 211 | `Load.preview` sample with Dallas/Atlanta — gated to `#if DEBUG`? | Verify DEBUG gating; flag regardless | S |

### Preview & Sample Data (not user-facing but still flagged)

| File | Line | What is fake | Suggested real source | Effort |
|---|---|---|---|---|
| `Views/Components/WeatherCard.swift` | 797 | Preview `city: "Dallas, TX"` | Inside `#Preview` — keep, low priority | — |
| `Views/Components/HereMapView.swift` | 496–513 | 3 preview route examples | Inside preview only | — |
| `Services/WeatherService.swift` | 148 | Fallback "Dallas, TX" when geolocation unavailable | Replace with "Current location" only; never leak city | S |

---

## Files with NO detectable mock data (already clean)

- `EusoTrip/Services/EusoTripAPI.swift` — 100% real tRPC surface
- `EusoTrip/Services/HOSLiveStore.swift`
- `EusoTrip/Services/NewsFeedStore.swift`
- `EusoTrip/Services/PushService.swift`
- `EusoTrip/Services/WeatherService.swift` (aside from one fallback string)
- `EusoTrip/Services/HereMaps/*` (geocoding, routing, matrix clients — all real HERE API)
- `EusoTrip/Views/Auth/001_SignIn.swift`
- `EusoTrip/Views/Driver/019_HosDutyStatus.swift`
- `EusoTrip/Views/Driver/MeNewsView.swift`
- `EusoTrip/Views/Driver/MeNotificationsView.swift`
- `EusoTrip/Views/Driver/HotZonesWidget.swift` (only preview-gated sample)
- `EusoTrip/Views/Driver/ELDIntegrationView.swift`
- `EusoTrip/Views/Driver/AddPaymentAccountSheet.swift`

---

## Key themes

1. **The real backend exists and is mature.** `EusoTripAPI` has ~80 procedures across auth, loads, HOS, DVIR, messaging, wallet (Plaid+Stripe), ELD, news, esangAI, loadLifecycle, loadWizard, notifications, crossBorder. A Phase-1 wave of swap-ins is trivial.
2. **The mock hotspot is the EusoWallet + Me Detail pantheon** (`DriverTabPanes.swift` §§4–8 + all of `MeDetailScreens.swift`). One file is 5k lines of seeded arrays.
3. **Bay-ops, fleet, rewards, leaderboard, fuel card, tax, availability have no backend yet.** These are the Phase-3 empty-state targets flagged in `_WAVE3_AUDIT/_MASTER_ROADMAP.md` §§2.3–2.4 and should not be wired blindly — they need routers first.
