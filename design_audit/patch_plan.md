# Patch Plan — Top 10 fixes for this round

Prioritized by visible impact. Each item lists scope (file · approximate line range), effort (S ≤ 1h, M ≤ ½ day, L ≤ 1–2 days), and what the user will see change.

## 1. Kill the "CAREER · COMPLIANCE · REPUTATION" subtitle — `EusoHeader` rollout  —  **M**

**Why #1:** This is the single biggest AI-template tell and it's on 6 screens (Eusoboards, Wallet, Me, DriverLoadsPane, MyLoadsSheet, DriverWalletPane). Home does NOT have it, which is exactly why Home reads native.

**Scope:** Add `EusoHeader` from `design_tokens.md` to `/EusoTrip/Theme/`. Replace these 6 `topBar` / `header` helpers:
- `Views/Driver/DriverTabPanes.swift` L224 (Eusoboards)
- `Views/Driver/DriverTabPanes.swift` L1397–1428 (MyLoadsSheet)
- `Views/Driver/DriverTabPanes.swift` L1767–1780 (DriverLoadsPane)
- `Views/Driver/DriverTabPanes.swift` L1954 (Wallet)
- `Views/Driver/DriverTabPanes.swift` L2806–2824 (Me)
- `Views/Driver/MeDetailScreens.swift` L162–194 (MeDetailContainer)

Rewrite subtitles as single live sentences or delete them:
- Eusoboards → `"Live load board"` or `"\(filtered.count) loads live"`
- Wallet → `"Available $4,118.22"`
- Me → delete (let the profile avatar card carry the greeting)
- My Loads → delete (segmented control already shows the buckets)

## 2. Fix the Me icon list — gradient-outline tiles instead of gray squares  —  **M**

**Why:** The 15-row gray-square SF-symbol list IS the "AI design elements" the user called out. This is the most repeated visual tell in the app (also appears in Wallet methods list, Settings link rows, Me header).

**Scope:** Add `EusoListRow` from `design_tokens.md`. Replace:
- `Views/Driver/DriverTabPanes.swift` L2777–2804 (`DriverMePane.row`)
- `Views/Driver/DriverTabPanes.swift` L2104–2132 (`DriverWalletPane.methodRow`)
- `Views/Driver/MeDetailScreens.swift` L3520–3534 (`MeSettingsView.linkRow`)

Also update `DriverMePane.body` L2686–2689 — replace `.background + .overlay + .clipShape` with `.eusoCard(radius: Radius.lg)`.

## 3. Promote Wallet / Zeun / Haul to hero cards at the top of Me  —  **M**

**Why:** A 15-row undifferentiated list reads as a generic "features menu". Home's rhythm is hero → metric row → list. Me should follow suit.

**Scope:** `Views/Driver/DriverTabPanes.swift` L2643–2695. Insert three `.eusoCard(intensity: .feature)` cards above the row list: (a) Eusowallet — live balance from `DriverWalletViewModel`; (b) Zeun Mechanics — fleet health %; (c) The Haul — season points + streak. Keep the remaining 12 routes in a single "More" `.eusoCard` below.

## 4. Unify the HOT badge — one `EusoBadge(.hot)` primitive  —  **S**

**Why:** "HOT" appears three different ways today: gradient-fill capsule on `LoadBoardCard` + `SuggestedLoadCard`, plain `Text("HOT LANE")` on `LoadDetailSheet` L108, and a bespoke flame-circle in `HotZonesListSheet`.

**Scope:** Replace:
- `Views/Driver/DriverTabPanes.swift` L1158–1167 (LoadBoardCard)
- `Views/Driver/010_DriverHome.swift` L1101–1111 (SuggestedLoadCard)
- `Views/Components/LoadDetailSheet.swift` L108 (`Text("HOT LANE")`)
- `Views/Driver/HotZonesWidget.swift` L1916–1919 (list-row flame circle)

All become `EusoBadge(text: "HOT", style: .hot, icon: "flame.fill")` or `.hotLane` variant.

## 5. Strip `NavigationStack` from Hot Zones + ELD — use `EusoSheetChrome`  —  **S**

**Why:** `NavigationStack { .navigationTitle("Hot Zones") }` produces a tiny inline iOS-default title that fights the app's 40pt gradient header language everywhere else.

**Scope:**
- `Views/Driver/HotZonesWidget.swift` L1442–1479 (`HotZonesDetailSheet`)
- `Views/Driver/HotZonesWidget.swift` L1837–1869 (`HotZonesListSheet`)
- `Views/Driver/ELDIntegrationView.swift` L55–84 (`ELDIntegrationView`)
- `Views/Driver/ProfileEditView.swift` (same pattern)

Wrap body in `EusoSheetChrome(title:"Hot Zones", subtitle:"Live demand · rate · L/T")` etc.

## 6. Replace the "Book now" full-width gradient button on every LoadBoardCard  —  **S**

**Why:** Home uses ONE full-width gradient button (Start pre-trip) on the ONE active load. Showing it on every list row makes the board feel like a pitch deck.

**Scope:** `Views/Driver/DriverTabPanes.swift` L1229–1260. Delete the "Book now" button + the details chip. Make the whole card a single tap target into `LoadDetailSheet` (`selectedLoadID = load.id`). The detail sheet already has the primary CTA.

## 7. Downgrade the Zeun card on DriverLoadsPane — outline instead of fill  —  **S**

**Why:** `.fill(LinearGradient.diagonal) + .shadow(Brand.magenta@0.35 r=18)` is a "hero-of-the-whole-screen" treatment. Home reserves that for the active load only.

**Scope:** `Views/Driver/DriverTabPanes.swift` L1876–1917 (`zeunCard`). Replace `.background(.fill(LinearGradient.diagonal))` with `.eusoCard(intensity: .feature)`. Change text to gradient foregroundStyle, keep the white-on-gradient icon tile at the left. Remove the magenta-only shadow (the feature-intensity glow is already in `.eusoCard`).

## 8. Unify segmented controls — one `EusoSegmentedControl`  —  **S**

**Why:** Three segmented-control implementations exist: MyLoadsSheet L1432, DriverLoadsPane L1784, MeHaulView tab capsules L2921 — each subtly different (gradient underline vs gradient capsule fill vs pill group).

**Scope:** Replace all three. The canonical is the MyLoadsSheet pattern (gradient underline + count chip) because it preserves text legibility on long labels.

## 9. Normalize Hot Zones summary tiles and pulse chips to `MetricTile`  —  **S**

**Why:** `HotZonesWidget.pulseChip` (L1101) and `HotZonesListSheet.summaryTile` (L1886) ship two parallel "little tinted metric" implementations. The canonical `MetricTile` (DesignSystem.swift L1104) does the same job.

**Scope:** Extend `MetricTile` with an optional `tint: Color?` parameter to support the semantic-colored numerals (success/danger/warning). Swap the two call sites.

## 10. `EusoBadge` migration pass — replace remaining `StatusPill` bespoke variants  —  **M**

**Why:** Once `EusoBadge` ships (fix #4), complete the migration so every badge in the app comes from one API. Specifically:
- `HaulLobbyTab` role capsules (L3027–3034) → `EusoBadge(.role(.driver))` etc.
- `MeHaulView` "7-day streak" flame capsule (L2904–2914) → `EusoBadge(text:"7-day streak", style:.warning, icon:"flame.fill")`
- `HotZonesDetailSheet.hero` demand capsule (L1488–1496) → `EusoBadge(style:.demand(level:.critical))`
- Lifecycle screens' hand-rolled "HAZMAT + TANK", "HAZMAT PLACARD SET C" (~8 call sites across 011–048) → `EusoBadge(style:.hazmat)`

## Effort summary

| Fix | Effort |
|---|---|
| 1. EusoHeader rollout | M |
| 2. EusoListRow + Me icon tiles | M |
| 3. Me hero-card promotion | M |
| 4. EusoBadge HOT unification | S |
| 5. Sheet chrome strip | S |
| 6. Kill "Book now" per card | S |
| 7. Zeun card outline | S |
| 8. Segmented control unify | S |
| 9. MetricTile tint param | S |
| 10. EusoBadge full migration | M |

**Total:** 4M + 6S ≈ 3–4 days of focused work.

## Ship order inside the round

1. Add `EusoDesignTokens.swift` (fixes 1, 2, 4, 5, 8 are all one-liner swaps once the primitives exist).
2. Land fix #1 alone — it will visibly delete the "AI template" subtitle across 6 screens in one commit.
3. Land fix #2 + #3 together — Me gets its new identity.
4. Land fix #4 + #10 — badge consistency across the app.
5. Land fix #5 — Hot Zones & ELD stop fighting the chrome.
6. Fixes #6, #7, #8, #9 can ship in any order.

## The single green-light fix

**Fix #1 (EusoHeader rollout).** One landed commit removes the single most recognizable "AI template" pattern from 6 screens — the "TITLE / WORD · WORD · WORD" header — and replaces it with the personalized, live-sentence header language Home already uses. Every reviewer will feel the difference before reading a line of code.
