# Patch Plan — 0% Mock Data Rollout

Three ordered phases. Each phase ends with a build that's shippable to TestFlight.

---

## Phase 1 — Wire where the endpoint already exists (Swap-In Wave)

**Goal:** everything in the **Backend Map §B** list flips from seeded array → live `EusoTripAPI` call, behind a shared Store pattern.

**Prereq:** Ship `EusoEmptyState` component first (per `empty_state_spec.md`). It's the fallback every store uses when it has no rows.

**Ordered tasks:**

| # | Scope | Files | Endpoint | ETA |
|---|---|---|---|---|
| 1 | Add `EusoEmptyState.swift` | `Theme/Components/EusoEmptyState.swift` | — | 1h |
| 2 | Replace `DriverWalletPane` hero balance literal with `WalletStore.balance` | `DriverTabPanes.swift:2021` | wallet.getBalance | 1h |
| 3 | Replace `DriverWalletPane.txns` seed with `WalletStore.transactions` (empty → `EusoEmptyState("dollarsign.circle", …)`) | `DriverTabPanes.swift:2144` | wallet.getTransactions (P2 — see Phase 2) | — |
| 4 | New `LoadBoardStore`; swap `DriverTripsPane.board` seed | `DriverTabPanes.swift:96` | loads.search(status:"available") | 2h |
| 5 | `MyLoadsStore`; swap duplicated `loads` seeds in `MyLoadsSheet` | `DriverTabPanes.swift:1296, 1673` | loads.search(status:"assigned/pending/completed") | 2h |
| 6 | Reuse `LoadBoardStore` for `DriverHome.suggestedLoads` carousel | `010_DriverHome.swift:67` | loads.search | 30m |
| 7 | Replace `MeZeunView.dvirEntries` seed | `MeDetailScreens.swift:1954` | inspections.getHistory | 1h |
| 8 | Replace `MeTaxView.entries` seed (DVIR subtitle) | `MeDetailScreens.swift:384` | inspections.getHistory | 30m |
| 9 | Remove hardcoded `"Marcus Reyes · CDL TX"` in 017 BOL sign | `017_PickupBolSigning.swift:35` | auth.me | 20m |
| 10 | Replace `MessagingConversationList` inbox seed | `DriverTabPanes.swift:3131`+ | messaging.getConversations | 1h |
| 11 | Replace `DriverPulseLobby.messages` seed | `MeDetailScreens.swift:3052` | messaging.getMessages(conversationId:"driver-lobby") | 2h |
| 12 | Remove fallback `"Dallas, TX"` city literal in WeatherService | `WeatherService.swift:148` | — (return "Current location") | 10m |
| 13 | Gate `Load.preview` and all HereMapView preview samples with `#if DEBUG` explicitly | various | — | 30m |
| 14 | `DriverProfileStore` defaults fall back to empty strings, not "Marcus Reyes" / "driver@eusotrip.com" / "Dallas · TX" / "4.92" / "127 loads completed" | `DriverProfileStore.swift` | auth.me | 45m |

**Phase 1 exit:** ~14 items wired. Headline UI no longer lies — wallet, boards, inbox, DVIR, profile are all live.

---

## Phase 2 — Near-close backend tweaks (Service-Wave)

**Goal:** the endpoints listed in **Backend Map §C** ship on the server side, then the iOS side consumes them on the next release. Each one is a tight, narrow router — days not weeks.

**Proposed router additions (backend, web team):**

| # | Router | Procedures | Consuming screens | Blocker? |
|---|---|---|---|---|
| 1 | `wallet` (extend) | `getTransactions({filter,cursor,limit})`, `getEarningsSummary`, `getWeeklyHistory`, `listPaymentMethods`, `getSettlementPreview` | EusoWallet §§4,6; MeEarnings | No |
| 2 | `factoring` | `getOffer(loadId)`, `accept(loadId)` | EusoWallet §5 | No |
| 3 | `rewards` | `getCatalog`, `getHistory`, `redeem({itemId})` | MeRewards | No |
| 4 | `achievements` (iOS-adapt) | `getMissions`, `getBadges`, `claim({missionId})` | MeMissions, MeBadges | Server router **already drafted** in `_WAVE4_BUILD/server/routers/achievements.ts` — iOS mirror only |
| 5 | `tax` | `getSummary(year)`, `get1099(year)`, `getYtdGross` | MeTax | Partial draft in `_WAVE4_BUILD/server/routers/taxReporting.append.ts` |
| 6 | `fuelCard` | `getStatus`, `getReceipts({cursor})`, `getTransactions` | EusoWallet §8, MeFleet fuel block | No |
| 7 | `leaderboard` | `getSeason({seasonId?})` | MeHaul | No |
| 8 | `fleet` | `listAssets`, `getMaintenanceSchedule`, `getAsset({id})` | MeFleet | No |

**iOS consuming work (once each ships):**

| # | Screen / Card | Store to add | Effort |
|---|---|---|---|
| 1 | EusoWallet transactions list + filter | `WalletStore.transactions` + `filter` subscription | 2h |
| 2 | EusoWallet earnings breakdown §6 | `EarningsStore` | 2h |
| 3 | EusoWallet payment methods §3 | `PaymentMethodsStore` | 1h |
| 4 | Factoring card §5 | `FactoringStore` | 1h |
| 5 | MeRewards · catalog + history | `RewardsStore` | 3h |
| 6 | MeMissions | `AchievementsStore` | 3h |
| 7 | MeBadges | `AchievementsStore` (shared) | 1h |
| 8 | MeTax | `TaxStore` | 2h |
| 9 | Fuel card row + receipts | `FuelCardStore` | 2h |
| 10 | MeHaul leaderboard | `LeaderboardStore` | 2h |
| 11 | MeFleet assets + maintenance + fuel receipts | `FleetStore` | 4h |

**Phase 2 exit:** ~11 surfaces graduated from seed array to live. MeDetailScreens.swift shrinks substantially (a ton of seeded arrays can be deleted).

---

## Phase 3 — Backend absent → Branded empty state now, backend later (Ship-the-Truth Wave)

**Goal:** screens where the backend doesn't exist and isn't close to existing render `EusoEmptyState` with the `.comingSoon` badge, using the verbatim copy in `empty_state_spec.md §4`. No mocks. Ever.

**Screens flipped to `EusoEmptyState`:**

| # | Screen | Mock being removed | Empty-state copy | Effort |
|---|---|---|---|---|
| 1 | MeAvailabilityView grid + blocks | 7×24 duty grid, 3 fake blocks | "Availability is coming soon — set DOT/medical/maintenance blocks and your clock will respect them." | 1h |
| 2 | 030 LoadingInProgress telemetry triplet | fake fill/flow/temp metrics | "Live telemetry coming soon." | 30m |
| 3 | 031 SpectraMatchVerdict lanes | 7 fake lane samples | "Spectra verdicts wire in once the sensor stack is online." | 30m |
| 4 | 032 DetachSequence gauges/steps | fake gauges + wizard steps | "Detach wizard is being finalised — follow your carrier SOP until it ships." | 1h |
| 5 | 034 DepartingPickup summary + firstLegPills | fake summary rows | — (render leg from `loadLifecycle.getCurrentLeg` or empty) | 1h |
| 6 | 036 ESangSmartStop amenities | fake amenity icons | "Smart Stop coverage is expanding." | 30m |
| 7 | 040–044 Discharge / Disconnect / Connect Drop Hose wizards | fake step lists + evidence | "Bay-ops wizards roll out with the sensor partner integration in Q3." | 2h |
| 8 | 048 ArrivalGateTaskActive | fake task list | "Arrival checkpoint tasks wire in with the geofence service rollout." | 1h |
| 9 | ESANG static callouts (primary/secondary strings across ~60 screens) | hardcoded coach copy in every view | Leave actual copy in code with a `// TODO: esangAI.getCoachCopy` header marker; replace with `EusoEmptyState` only where the card is entirely the callout (not inline subtitles). Track separately. | Est 20h total, phased |
| 10 | Legacy hardcoded dispatch/broker call-ins | mock P2P + convoy bridges | `EusoEmptyState.comingSoon` | 1h |

**Phase 3 exit:** every screen either (a) shows live data, (b) shows a real empty state because the data set is empty, or (c) shows `EusoEmptyState.comingSoon`. **Zero mock data. Zero `.init(…seeded value…)` arrays in any `Views/` file.**

---

## Rollout ordering summary

- **P1 (week 1):** ship `EusoEmptyState`, consolidate 14 swap-ins above. Release v3.1.
- **P2 (weeks 2–4):** backend ships the 8 new routers. iOS ships 11 `Store` consumers one per day. Release v3.2, v3.3, v3.4 incrementally.
- **P3 (weeks 5–6):** flip remaining screens to `EusoEmptyState.comingSoon` with the copy table. Release v3.5.

---

## Regression gate (CI check)

Add a Danger / Swift-linter rule: **fail the build if a new file contains `.init(` at the top-level of a `private let … : [X] = [` array inside `Views/`.**

Grep pattern:

```
rg --pcre2 "private (static )?let \w+(\s*:)?\s*\[\w+\]\s*=\s*\[" --glob 'EusoTrip/Views/**/*.swift'
```

Budget today: 28 hits. Target: 0. Rule bites every commit that tries to sneak seeded data back in.

---

## Files created / modified (summary across all 3 phases)

**Created**
- `EusoTrip/Theme/Components/EusoEmptyState.swift`
- `EusoTrip/Stores/LoadBoardStore.swift`
- `EusoTrip/Stores/MyLoadsStore.swift`
- `EusoTrip/Stores/WalletStore.swift`
- `EusoTrip/Stores/EarningsStore.swift`
- `EusoTrip/Stores/PaymentMethodsStore.swift`
- `EusoTrip/Stores/RewardsStore.swift`
- `EusoTrip/Stores/AchievementsStore.swift`
- `EusoTrip/Stores/TaxStore.swift`
- `EusoTrip/Stores/FuelCardStore.swift`
- `EusoTrip/Stores/LeaderboardStore.swift`
- `EusoTrip/Stores/FleetStore.swift`
- `EusoTrip/Stores/FactoringStore.swift`

**Modified (mock removals)**
- `Views/Driver/DriverTabPanes.swift` — cuts ~350 lines of seeded arrays.
- `Views/Driver/MeDetailScreens.swift` — cuts ~500 lines of seeded arrays across Earnings/Tax/Missions/Rewards/Badges/Fleet/Haul.
- `Views/Driver/010_DriverHome.swift` — cuts `suggestedLoads` block.
- `Views/Driver/017_PickupBolSigning.swift` — cuts driver-name literal.
- `Views/Driver/028_…` through `Views/Driver/051_…` — each trip-lifecycle screen swaps seeded step/metric arrays for empty-state fallback.
- `Services/DriverProfileStore.swift` — default values become empty strings.
- `Services/WeatherService.swift` — "Dallas, TX" fallback becomes "Current location".

**Backend (web team, not iOS)**
- `server/routers/wallet.ts` — adds getTransactions, getEarningsSummary, listPaymentMethods, getSettlementPreview, getWeeklyHistory.
- `server/routers/factoring.ts` — new.
- `server/routers/rewards.ts` — new.
- `server/routers/achievements.ts` — already drafted, finish + publish.
- `server/routers/taxReporting.ts` — already drafted, finish + publish.
- `server/routers/fuelCard.ts` — new.
- `server/routers/leaderboard.ts` — new.
- `server/routers/fleet.ts` — new.
