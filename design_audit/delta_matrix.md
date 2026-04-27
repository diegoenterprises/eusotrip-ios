# Delta Matrix — Home vs everything else

Each row lists the specific token/modifier that deviates from Home's canonical spec and the exact fix (file · line · modifier).

## 1. Eusoboards (`DriverTabPanes.swift` L222 `DriverTripsPane`)

| # | Delta | Home uses | Eusoboards uses | Fix |
|---|---|---|---|---|
| 1 | Header subtitle is a 3-term bullet list "Available freight · book & dispatch" | Home has NO bullet subtitle (right-rail time+location) | `topBar(title:"Eusoboards", subtitle:"AVAILABLE FREIGHT · BOOK & DISPATCH")` L224–225 | Replace bullet subtitle with a single descriptive line: `subtitle:"Live load board"`. Or remove subtitle and show right-rail chip (`{filtered.count} live loads`) like Home's right-rail meta. |
| 2 | "Book now" button on every `LoadBoardCard` (line 1234) is a full-width `LinearGradient.diagonal` pill | Home CTA is scoped to ONE active-load card; list rows are taps, not buttons | `LoadBoardCard` L1230–1244 | Remove the "Book now" primary gradient. Leave a single `info.circle` chevron and let the whole card be a tap target into `LoadDetailSheet` (already selectable). Gradient CTA belongs on the detail sheet's primary action, not every row. |
| 3 | "My Loads" CTA (L849–908) is a full-gradient feature card with dual blue/magenta shadow | Home gradient card is reserved for the active load | Tolerable — but downgrade to `.eusoCard(intensity: .feature)` outline (keeps gradient rim, loses fill) | `DriverTripsPane.myLoadsButton`: swap `.fill(LinearGradient.diagonal)` background for `.eusoCard(intensity: .feature)`; keep white icon tile, make Text use `LinearGradient.diagonal` on title. |

## 2. My Loads sheet & tab (`DriverTabPanes.swift` L1286 `MyLoadsSheet` + L1653 `DriverLoadsPane`)

| # | Delta | Home uses | My Loads uses | Fix |
|---|---|---|---|---|
| 1 | Subtitle is "ACTIVE · PENDING · FINISHED" / "ACTIVE · PENDING · FINISHED · MAINTENANCE" | No bullet subtitle | L1403 and L1772 | These four terms are already visible in the segmented control directly below — the subtitle is redundant. Delete subtitle. |
| 2 | Sheet header is 28pt, tab header is 40pt | Home is 40pt | Inconsistent between surfaces that show the same content | Unify to 40pt gradient heavy; OR use 28pt for all SHEETS, 40pt for all PANES. Current: inconsistent. |
| 3 | Zeun Mechanics card (L1876–1915) uses `.fill(LinearGradient.diagonal)` AND `Brand.magenta@0.35 r=18 y=6` shadow — full feature-card treatment | Home's feature cards (`ActiveCard`) use outline, not fill | L1905–1913 | Replace `RoundedRectangle...fill(LinearGradient.diagonal)` with `.eusoCard(intensity: .feature)`. Change icon tile `.fill(.white.opacity(0.18))` to `.fill(LinearGradient.diagonal)` so the gradient carries on the icon only. Text "Zeun Mechanics" should use `.foregroundStyle(LinearGradient.diagonal)` on a `palette.bgPage` card. Remove the magenta shadow. |
| 4 | `MyLoadCard` uses `.eusoCard(radius: Radius.lg)` — consistent with Home suggested cards | — | L1572 OK | No change. |

## 3. Me (`DriverTabPanes.swift` L2596 `DriverMePane`)

This is the screen that prompted the audit. Three distinct AI-tells stacked.

| # | Delta | Home uses | Me uses | Fix |
|---|---|---|---|---|
| 1 | Subtitle `"Career · compliance · reputation"` uppercased to "CAREER · COMPLIANCE · REPUTATION" | No bullet subtitle | L2633 | Replace with a single descriptive line: `subtitle: "\(profile.loadsCompletedYTD) loads YTD · \(profile.reputationSummary)"` — numbers-first per doctrine §3. Or delete subtitle and place a `StatusPill(text:"Top 3%",.info)` on the right of the greeting. |
| 2 | 15 rows of identical `palette.tintNeutral` rounded-square SF-symbol tiles (36×36, Radius.md, 14pt semibold glyph) | Home row glyph is 40×40 `palette.bgCardSoft` with iconography set by row kind | L2777–2804 | (a) Tint the icon itself with `LinearGradient.diagonal` on hover/selection; (b) replace `palette.tintNeutral` square with an iridescent-hairline stroke `RoundedRectangle.strokeBorder(LinearGradient.diagonal.opacity(0.35), lineWidth:1)` + `palette.bgPage` fill — the "card melts into page, gradient outline is the only decoration" doctrine; (c) make 3–4 priority rows (Eusowallet, Zeun, The Haul) render as `.eusoCard(intensity: .feature)` FULL-WIDTH cards at the top with their live numbers (wallet balance, fleet health, Haul points) and demote the rest into a single "More" scroll below. |
| 3 | List container is `palette.bgCard` + `borderFaint` + `Radius.lg` — NOT `.eusoCard()` | `.eusoCard()` is the canonical list wrapper | L2686–2689 | Replace the three modifiers with `.eusoCard(radius: Radius.lg)`. |
| 4 | `profileAvatar` 56×56 is initials-gradient; same treatment as Settings (accountAvatar 52×52) — good but sized differently | — | L2741–2761 vs L3491–3511 | Normalize to one size (56pt hero, 40pt list). |

## 4. Hot Zones — `HotZonesWidget.swift` widget + `HotZonesListSheet` + `HotZonesDetailSheet`

| # | Delta | Home uses | Hot Zones uses | Fix |
|---|---|---|---|---|
| 1 | `HotZonesListSheet` and `HotZonesDetailSheet` both use `NavigationStack { … .navigationTitle("Hot Zones") }` | Home, panes, and Me use custom 40pt gradient `topBar(title:subtitle:)` | L1854, L1471 | Strip the `NavigationStack` + `.navigationTitle`. Replace with the shared `paneHeader(title:"Hot Zones", subtitle:"…")` helper (see `design_tokens.md` — `EusoHeader`). Keep a leading "close" 32×32 chip matching `MeDetailContainer` L175–187. |
| 2 | Summary tiles (L1886–1906) use flat `palette.bgCard`+`borderFaint`, not `.eusoCard()` | `MetricTile` is canonical tile | L1886–1906 | Replace with `MetricTile(label:, value:, gradientNumeral: (tint==Brand.success||Brand.warning))` — or a new `SemanticMetricTile(tint:)` variant. |
| 3 | Pulse chips (L1077–1099) use `palette.bgCardSoft` tiles | — | L1124–1130 | Swap to `MetricTile` or `.eusoCard(intensity: .whisper)`. |
| 4 | List-row chrome (L1958–1966) uses `palette.bgCard` + `borderFaint` + `Radius.md` | Me-list-row post-fix spec: `.eusoCard(intensity: .whisper)` | L1958–1966 | `.eusoCard(intensity: .whisper, radius: Radius.md)`. |
| 5 | `demand.label` capsule in list row uses `demand.color.opacity(0.18)` circle + color label — new visual language | `StatusPill` with `.danger/.warning/.info` | L1913–1919, L1931–1933 | Replace with `StatusPill(text: demand.label, kind: demand.statusKind)` where statusKind maps CRITICAL→.danger, HIGH→.warning, ELEVATED→.info. |

## 5. The Haul (`MeDetailScreens.swift` L2864 `MeHaulView`)

| # | Delta | Home uses | The Haul uses | Fix |
|---|---|---|---|---|
| 1 | Tab bar uses gradient-fill capsule + `palette.bgCardSoft` capsule (L2933–2946) — bespoke | Home has no tab bar; `MyLoadsSheet` uses underlined text tabs (L1432–1468) with gradient-underline + gradient counter pill | L2921–2950 | Standardize on the `MyLoadsSheet` segmented style. Extract `EusoSegmentedControl(items:, selection:)` primitive; delete both bespoke variants. |
| 2 | "7-day streak" orange flame capsule (L2904–2914) uses hand-rolled `Brand.warning.opacity(0.18)` background | Home uses `StatusPill` | L2904–2914 | Replace with `StatusPill(text:"7-day streak",.warning)` + leading `flame.fill` via a new `StatusPill` overload: `StatusPill(text:icon:kind:)`. |
| 3 | "THE HAUL · SEASON APRIL" eyebrow is just uppercase micro text | Home uses the same (L390–395, L2633) — OK | — | No change. |
| 4 | `HaulLeaderboardTab.CTAButton("Claim daily bonus")` is the only CTA — good, matches Home | — | L2997 | OK. |

## 6. The Lobby (`MeDetailScreens.swift` L3015 `HaulLobbyTab`)

| # | Delta | Home uses | The Lobby uses | Fix |
|---|---|---|---|---|
| 1 | Role colors: driver=info (blue), dispatch=success (green), fleet=warning (amber), staff=magenta | Home palette only uses blue/magenta gradient + semantic pills | L3027–3034 | Keep role colors but REDUCE to: driver=`Brand.info`, dispatch=`Brand.success`, fleet=`Brand.warning`, staff=`LinearGradient.diagonal` (brand gradient, not solid magenta) — staff should read as "EusoTrip-native". |
| 2 | Message bubbles are hand-rolled (not using `.eusoCard` or any shared chat primitive) | — | Lobby bubbles | Extract a `ChatBubble(role:, body:, self_:)` primitive from `DriverConversationView` and share with HaulLobbyTab. |

## 7. Wallet (`DriverTabPanes.swift` L1929 `DriverWalletPane`)

| # | Delta | Home uses | Wallet uses | Fix |
|---|---|---|---|---|
| 1 | Subtitle "EUSOWALLET · SETTLEMENTS · PAYOUTS" | No bullet subtitle on Home | L1954 | Replace with "Available · $4,118.22" (single live metric) or delete. |
| 2 | Quick-action tiles (L2051–2070) use `palette.bgCard` + `borderFaint` — third card treatment in the same screen | Home reserves flat-`bgCard` only for `MetricTile` | L2063–2066 | Replace with `MetricTile`-style or `.eusoCard(intensity: .whisper)`. |
| 3 | Payment-methods list rows (L2104–2132) use `palette.tintNeutral` 36×36 icon tile — identical to Me row AI-tell | — | L2106–2114 | Same fix as Me row #2: iridescent-hairline tile or gradient icon on `palette.bgPage`. |

## 8. ELD (`Views/Driver/ELDIntegrationView.swift`)

| # | Delta | Home uses | ELD uses | Fix |
|---|---|---|---|---|
| 1 | `NavigationStack` + `.navigationTitle("ELD Integration")` inline (L73–74) | 40pt gradient `topBar` | L72–80 | Strip NavigationStack. Use shared `EusoHeader(title:"ELD", subtitle:"Provider · credentials · compliance")` + trailing "Done" chip (32×32 palette.bgCardSoft + borderFaint, like MeDetailContainer L175–187). |
| 2 | Status card (L96–145) is `ActiveCard` with gradient "headlineText" — matches Home | — | — | No change. |

## 9. Settings (`MeDetailScreens.swift` L3369 `MeSettingsView`)

| # | Delta | Home uses | Settings uses | Fix |
|---|---|---|---|---|
| 1 | "ACCOUNT" card profile row uses `ActiveCard` + chevron | Home active card is gradient-rim; this is same — OK | L3387–3410 | No change. |
| 2 | `MeDetailContainer` title at 28pt solid `palette.textPrimary` (L167) — inconsistent with panes' 40pt gradient | Home 40pt gradient | `MeDetailContainer` L165–168 | Upgrade to `EusoHeader` (40pt gradient). Sheet-vs-pane size can stay a concession: 34pt gradient for sheets. |

## 10. Notifications (`MeNotificationsView.swift`)

| # | Delta | Home uses | Notifications uses | Fix |
|---|---|---|---|---|
| 1 | Status hero uses 28pt gradient headline (L196–198) — inconsistent with Home 52pt hero numeric | Home = 52pt number / 40pt greeting | L196–198 | No hero number here (there's no number to show). 28pt is fine. |
| 2 | Category toggles inside `.eusoCard` — good | — | L180 | No change. |

## 11. Driver Intel / MeNewsView

| # | Delta | Home uses | News uses | Fix |
|---|---|---|---|---|
| 1 | Bypasses `MeDetailContainer` scroll+padding wrapper (L134–136) | Uniform container gutter | `MeDetailContainer` L134 | Unnecessary special-case. Give it the same Space.s5 gutter as every other Me child. |

## 12. Edit Profile / Conversation / Load Detail / SOS

Load Detail sheet (`LoadDetailSheet.swift` L108) has a bespoke `Text("HOT LANE")` label — NOT using `StatusPill` or the `HOT` gradient capsule used on `LoadBoardCard`. Unify to one "HOT" gradient capsule primitive (see `design_tokens.md` — `EusoHotChip`).

Edit Profile and Conversation keep their own chrome (appropriate for focused forms / chat).

## 13. Lifecycle journey screens (011–048)

These 38 screens predate the pane-header system and each ships bespoke chrome in `Shell`. Out of scope for this round but flag: they use `"HAZMAT+TANK"`, `"HAZMAT PLACARD SET C"`, etc. as hand-rolled pills (e.g. `037_ApproachingReceiver.swift` L301, `038_AtReceiverGate.swift` L44, `047_ArrivalCheckpoint.swift` L182). Unify after the Me / Hot Zones / Eusoboards fixes land.
