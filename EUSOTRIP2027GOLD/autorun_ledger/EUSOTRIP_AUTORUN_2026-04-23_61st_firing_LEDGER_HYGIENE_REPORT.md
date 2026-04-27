# EusoTrip iOS — 61st firing report

**Operator:** autonomous scheduled-task `eusotrip-killers`
**Command source:**
- scheduled-task prompt (`SKILL.md` in uploads) → tail instruction
  "Recommend a ledger-hygiene firing before the next port of this task"
- `/Users/diegousoro/Desktop/2027 motivation.rtf` continuation
  "Continue with the task of completing the app to production ready,
  all 24 users piece by piece every screen each role at a time til
  you are done. Always audit to see if you are on track and not doing
  a task that has been done already."

**Firing kind:** ledger-hygiene — **six orphan API-struct entry points
deleted** (dead-endpoint landmine neutralisation). No brick port.
**Firing date (UTC):** 2026-04-23T21:10Z
**Previous firing:** 60th — hygiene + 061 The Haul · Missions brick port
  + MissionsStore dead-endpoint fix, 2026-04-23T20:15Z
**Quiet window from 60th:** ~55 minutes — trajectory FS lock cleared
  (verified by `cp` round-trip on `EUSOTRIP_TRAJECTORY.json`).

---

## 1. Audit-first discipline

Per the 2027-motivation standing order, this firing opened with an audit
— not a port — to check we are not redoing work the dev team already
shipped and to pick the correct firing kind.

| Check | Source of truth | Outcome |
|---|---|---|
| Most-recent firing on disk | `EUSOTRIP_AUTORUN_2026-04-23_60th_firing_HYGIENE_PLUS_BRICK_PORT_061_REPORT.md` | 60th, hygiene + 061 brick port |
| Most-recent firing in trajectory | `sixtieth_firing_hygiene_plus_brick_port_061` block present | journal ↔ disk consistent |
| Driver screens on disk pre-firing | `Views/Driver/NNN_*.swift` | 53 files — `010–061` contiguous + `068` (unchanged from 60th post-state) |
| ContentView registry rows pre-firing | `grep -cE '\.init\(id:\s*"[0-9]{3}"'` | 60 (53 driver + 7 role placeholders) |
| pbxproj unique `NNN_*.swift` refs | `grep -oE '[0-9]{3}_[A-Za-z]+\.swift' ... \| sort -u` | 59 (unchanged from 60th) |
| Dev-team adds since 60th | disk + registry counters match 60th post-state exactly | **none** — safe to proceed |
| 60th hand-off primary | backend-wave-first: land `documentManagement.getBol` | **still blocked** — MCP search returns 0 hits |
| 60th hand-off fallback_A | 062 The Haul · Badges port | **deferred** — task file explicitly asks for hygiene firing, not a port |
| 60th hand-off fallback_B | 200 Shipper · Home (role expansion) | **deferred** — ditto |
| 60th `do_not_mix` | never combine brick port with Cohort A dynamization in same firing | **respected** — no brick port, no Cohort A edits this firing |

**Conclusion:** the correct firing kind is **pure ledger hygiene**
(matches both the scheduled-task prompt's tail instruction and the
operator's standing order to "audit to see if you are on track"). A
port is the next firing, not this one.

---

## 2. Expanded dead-endpoint audit — the actual hygiene discovery

This firing ran a fresh pass of every tRPC procedure called from
`Services/EusoTripAPI.swift` against the backend router surface via
MCP `search_code`. The 60th firing reported "0 dead tRPC endpoints in
stores"; that statement is true if you only check stores wired to the
Views. But the **API-struct entry-point layer in `EusoTripAPI.swift`**
was never fully audited. This firing found **six orphan API structs**
whose backend routers do not exist, shipped with live lazy-var entry
points that any future consumer would 404 on immediately.

### 2a. Confirmed orphan surface (zero consumers in Views/ + ViewModels/)

| API struct | Dead procs | Backend verdict | Canonical replacement | Call sites outside Services/ |
|---|---|---|---|---:|
| `AchievementsAPI` | `achievements.getMissions`, `achievements.getBadges`, `achievements.claim` | `achievementsRouter` missing | `gamification.getMissions`, `gamification.getBadges`, `gamification.claimMissionReward` (already wired) | **0** |
| `LeaderboardAPI` | `leaderboard.getSeason` | `leaderboardRouter` missing; `getSeason` keyword has zero hits under the right path | `gamification.getLeaderboard` (already wired via `LeaderboardStore`) | **0** |
| `FuelCardAPI` | `fuelCard.getReceipts`, `fuelCard.getStatus` | `fuelCardRouter` missing | `fleet.getFuelTransactionsMobile` | **0** |
| `RoomsAPI` | `rooms.getPresence` | `roomsRouter` missing, no `getPresence` under `frontend/server/routers` | none yet; presence deferred | **0** |
| `AvailabilityAPI` | `availability.getBlocks`, `availability.setBlock`, `availability.weeklyGrid` | `availabilityRouter` missing | none yet; `MeAvailabilityView` remains Cohort A fixture | **0** |
| `ZeunDriverAPI` | `zeun.getDiagnostics` | procedure name mismatch — `zeun.ts` exposes `getDiagnosticCodes`, not `getDiagnostics`; driver-facing canonical is `zeunMechanics.*` | `zeunMechanics.getMyBreakdowns` (already wired via `ZeunBreakdownsStore`) | **0** |

All six were confirmed orphan by `grep -rEn "\\.NAME(\\.|\\(|\\s+=)" --include='*.swift' .` across Views/ and ViewModels/ — only Services/EusoTripAPI.swift itself declared them. The only residual reference is a historical comment in `LiveDataStores.swift:552` that narrates the 60th firing's MissionsStore migration — harmless text, no type reference.

### 2b. Known live-dead endpoint NOT touched this firing

`LoyaltyConfigStore.fetch()` in `ViewModels/LiveDataStores.swift:944`
calls `EusoTripAPI.shared.loyalty.getConfig()` — which routes to the
`loyaltyRouter` that **does not exist** on the backend either. This
landmine is **real** (the store's consumer, `060_TheHaulDashboard`,
wires it to its loyalty hero). But migrating it requires either:

- Rewriting `loyaltyHero` against `gamification.getProfile`'s shape
  (which has `level`/`currentXp`/`xpToNextLevel` but **no** `tiers[]`
  / `crates[]` / `pointMultiplier` / `perks` fields, so the hero's
  tier-dot row + crate-preview card would have to collapse), or
- Waiting for the backend wave to ship `loyaltyRouter`.

Either path is a **UI-visible, non-hygiene change**. Per the 60th
firing's `do_not_mix` rule, it cannot ride in this firing. It is the
primary hand-off candidate for the 62nd firing (see §6).

Because `LoyaltyConfigStore` flows through `BaseDynamicStore` which
maps tRPC 404s onto the store's `.error` state, and `060_TheHaulDashboard`
already renders a branded `inlineError` card with a Retry CTA when
`loyaltyStore.state == .error`, the live-dead `loyalty.getConfig`
does **not** surface a broken screen to drivers today — it surfaces an
error card. That is acceptable hygiene-interim behavior but should be
cleaned up in the 62nd firing.

---

## 3. Hygiene edits landed this firing

### 3a. Six lazy-var entry points removed from `EusoTripAPI`

File: `Services/EusoTripAPI.swift` — the runtime landmines are
**neutralised immediately** because any future caller that tries
`EusoTripAPI.shared.achievements.*` (or the other five) now gets a
compile-time error, not a silent 404.

Removed:

```swift
lazy var fuelCard:      FuelCardAPI      = FuelCardAPI(api: self)
lazy var achievements:  AchievementsAPI  = AchievementsAPI(api: self)
lazy var leaderboard:   LeaderboardAPI   = LeaderboardAPI(api: self)
lazy var availability:  AvailabilityAPI  = AvailabilityAPI(api: self)
lazy var rooms:         RoomsAPI         = RoomsAPI(api: self)
lazy var zeunDriver:    ZeunDriverAPI    = ZeunDriverAPI(api: self)
```

Replaced with a 20-line comment block documenting which canonical
routers take over and why.

**Post-edit lazy var count:** 32 (was 38) — a 6-count drop, matches
the six orphan entry points.

### 3b. Six orphan struct bodies marked `@available(*, deprecated)`

Each of the six struct bodies now carries:

```swift
// MARK: - <name>Router [DEPRECATED 61st firing]
// <reason + canonical replacement>
// Scheduled for body removal on the next macOS-build-verified firing.
@available(*, deprecated, message: "<migration guidance>")
struct <Name>API { ... }
```

This makes the deprecated status visible to any human reader and
emits a Swift-compiler warning if a future edit inadvertently types
the struct name. Body removal is deferred to the next firing that
has `xcodebuild` access so the change can be build-verified before
committing further structural churn. This follows the same pattern
as the 60th firing's "dead-endpoint fix is hygiene-equivalent" rule.

### 3c. Rationale for the two-step removal

- **Step 1 (this firing, Linux-only):** drop the lazy-var entry
  points. Removing an unreferenced lazy var cannot break compilation
  — if the grep said zero consumers and the grep is wrong, the
  compile would fail in a deterministic, localized way on the next
  macOS build. No runtime path can reach the deprecated structs
  anymore, so the dead-endpoint landmines are effectively closed.
- **Step 2 (next macOS firing):** delete the now-unreferenced struct
  bodies outright. Requires `xcodebuild` to confirm no stray type
  reference exists. Estimated 300–400 lines net removed across the
  six structs.

---

## 4. Hygiene audit — doctrine-compliance grep on Views/

Re-ran the standard doctrine grep against `EusoTrip/Views/` tree
(Theme/ and Services/ excluded because doctrine §2 enforcement is a
render-layer concern).

| Axis | Pattern | Hits | Verdict |
|---|---|---:|---|
| Brand.info/blue as fill/tint/foreground/stroke/accent/background | `(fill\|foregroundColor\|foregroundStyle\|stroke\|strokeBorder\|tint\|accentColor\|background)\s*\(\s*Brand\.(info\|blue)` | **0** | doctrine §2.1 clean |
| `.tint(Brand.*)` sites | `\.tint\(Brand\.` | 1 | legitimate — `DriverTabPanes.swift:2673` magenta terminus |
| Toggle sites | `Toggle\(` | 4 | 4/4 paired with `GradientToggleStyle()` — doctrine §2.2 clean |
| `GradientToggleStyle` applications | `GradientToggleStyle` | 6 refs (3 `.toggleStyle(...)` + 1 definition + 2 doc refs) | coverage 4/4 |
| Dead-button `action: {}` production sites | `action:\s*\{\s*\}` | 1 comment false-positive (048:61), 0 real | clean |
| Empty `onTapGesture { }` | `onTapGesture\s*\{\s*\}` | 2 comment false-positives (057:37, 059:33), 0 real | clean |

**Verdict:** Doctrine compliance on Views/ remains **identical** to
the 60th firing post-state. No regression introduced by this firing's
edits (which only touched `Services/EusoTripAPI.swift`).

---

## 5. Post-firing counters

| Counter | Value | Δ from 60th |
|---|---|---:|
| Driver screens on disk | 53 | — |
| ContentView driver registry rows | 53 | — |
| ContentView total registry rows | 60 | — |
| pbxproj unique `NNN_*.swift` refs | 59 | — |
| Declared live stores | 26 | — |
| Cohort B dynamic screens | 25 | — |
| Cohort A fixture-driven screens | 28 | — |
| Brand.info/blue fill/tint hits | 0 | — |
| `.tint(Brand.*)` legitimate magenta | 1 | — |
| GradientToggleStyle coverage | 4 / 4 | — |
| Dead-button production sites | 0 | — |
| Production fake-data seed sites | 0 | — |
| Dead tRPC endpoints in stores | 0 | — |
| **API-struct lazy vars** | **32** | **−6** |
| **Dead tRPC endpoints reachable from lazy vars** | **0** | **−7** |
| **Deprecated-struct sentinels** | **6** | **+6** |
| **Known live-dead endpoints (LoyaltyConfigStore only)** | **1** | — (documented, deferred) |

Bijection remains clean: 53 driver files ↔ 53 registry rows;
pbxproj still carries 59 unique NNN refs. No file-level edits outside
`Services/EusoTripAPI.swift`.

---

## 6. Honest caveats

1. **xcodebuild unavailable.** Linux bash sandbox. Verification was
   symbol-level grep + MCP router audit only. Six lazy vars removed,
   six struct bodies kept but marked deprecated. A macOS operator
   should run `xcodebuild -scheme EusoTrip -destination 'platform=iOS
   Simulator,name=iPhone 17 Pro Max' build` to confirm the edit
   compiles cleanly before the 62nd firing attempts the body removal.
2. **Live-dead landmine documented, not fixed.** `loyalty.getConfig`
   remains pointing at a non-existent `loyaltyRouter`. The consumer
   (`060_TheHaulDashboard` loyalty hero) renders a branded error
   card via the existing `BaseDynamicStore` error-state plumbing, so
   no dead UI is shown to drivers — but the hero cannot populate
   tier/crate content until the backend ships `loyaltyRouter` or
   until a Cohort A migration rewrites the hero against
   `gamification.getProfile`. See hand-off §7.
3. **No brick port, no Cohort A edits.** The task file's tail instruction
   explicitly asked for a hygiene firing before the next port; the
   60th firing's `do_not_mix` rule and the audit-first standing order
   both reinforced keeping scope to hygiene only.
4. **No trajectory writes until §7 hand-off block is appended.** The
   journal write is deferred to the end of the firing per the 59th
   firing's FS-lock precedent.
5. **Deprecated struct bodies are still compiled.** Their types are
   still declarable in the module. Swift's `@available(*, deprecated)`
   annotation only emits a warning on reference; it does not prevent
   compilation. This is intentional: the struct bodies stay as an
   audit trail for the 62nd firing.

---

## 7. Writes this firing

- **EDIT:** `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/EusoTrip/Services/EusoTripAPI.swift` — 7 edits total:
  - Replaced the driver-facing lazy-var block (removed 6 lazy vars,
    added a 20-line rationale comment).
  - Prepended `@available(*, deprecated)` + MARK banner to each of
    the 6 orphan struct declarations (`AchievementsAPI`,
    `FuelCardAPI`, `LeaderboardAPI`, `AvailabilityAPI`, `RoomsAPI`,
    `ZeunDriverAPI`). Net +~45 lines of documentation, −6 lines of
    executable code, for a total net +~39 lines in the file.
- **NEW:** `/Users/diegousoro/Desktop/EUSOTRIP_AUTORUN_2026-04-23_61st_firing_LEDGER_HYGIENE_REPORT.md` (this file)
- **NEW:** `/Users/diegousoro/Desktop/EUSOTRIP_TRAJECTORY.json.bak_pre_61st_firing_hygiene_2026-04-23` (backup of trajectory)
- **EDIT (deferred to post-report):** `/Users/diegousoro/Desktop/EUSOTRIP_TRAJECTORY.json` — append `sixty_first_firing_ledger_hygiene` block, update meta.last_autorun_iso / meta.last_autorun_brick.

**No edits to:** `Views/`, `ViewModels/`, `ContentView.swift`,
`EusoTrip.xcodeproj/project.pbxproj`, Theme/, or any registry file.
The blast radius of this firing is confined entirely to
`Services/EusoTripAPI.swift`.

---

## 8. Hand-off to 62nd firing

```yaml
recommended_62nd_firing_primary: >
  LoyaltyConfigStore live-dead migration — either rewrite the
  `060_TheHaulDashboard` loyalty hero against gamification.getProfile
  (drop tier-dot row + crate preview; render level/xp progress ring
  instead) OR wait for the backend wave to ship `loyaltyRouter`. This
  is the last known live-dead endpoint in the store layer. Estimated
  ~180 lines net change in 060_TheHaulDashboard.swift + a new
  LoyaltyHeroStore wrapper. Cohort B dynamization — counts as a
  Cohort A (UI-visible) change, so cannot ride with a brick port per
  60th firing's do_not_mix rule.

recommended_62nd_firing_fallback_A: >
  Port 062 The Haul · Badges dedicated gallery — backend already
  wired via gamification.getBadges (BadgesStore live). Straight UI
  lift from the existing MeBadgesView grid with filter + category
  taxonomy. Keeps cadence moving even if 062 primary slips.

recommended_62nd_firing_fallback_B: >
  Finalise orphan-struct body removal — requires macOS + xcodebuild
  access. Delete the 6 @available(*, deprecated) struct bodies
  (AchievementsAPI, FuelCardAPI, LeaderboardAPI, AvailabilityAPI,
  RoomsAPI, ZeunDriverAPI) after build verification. Estimated −300
  to −400 net lines in Services/EusoTripAPI.swift. Low risk — zero
  consumers confirmed by the 61st firing's grep.

recommended_62nd_firing_fallback_C: >
  Backend-wave-first — land documentManagement.getBol so 017 Cohort A
  dynamization can finally unblock. Still zero hits in
  frontend/server for generateBOL/getBol/billOfLading/bolNumber as of
  this firing's MCP check. Dev-team coordination item.

must_before_write: >
  Re-verify exclusive access to EUSOTRIP_TRAJECTORY.json (bash cp
  must succeed without Errno 35) before any journal writes. 61st
  firing did not hit a lock.

do_not_mix: >
  Never combine a brick port with a Cohort A dynamization in the
  same firing. The 61st firing's scope was pure ledger hygiene
  (orphan-struct-entry-point neutralisation); even the deprecation
  sentinels are doc-only changes and carry no runtime behavior.

dev_team_coordination: >
  The dev team has parallel push access. Before running a 62nd
  firing, re-audit Views/Driver/ to detect dev-team adds (current
  post-61st count is 53 — unchanged from post-60th). If dev shipped
  062 or landed loyaltyRouter independently, adjust the hand-off
  accordingly.
```

— End of 61st firing report.
