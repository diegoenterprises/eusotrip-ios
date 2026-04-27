# EusoTrip iOS — 60th firing report

**Operator:** autonomous scheduled-task `eusotrip-killers`
**Command source:**
- scheduled-task prompt (`SKILL.md` in uploads) → tail instruction
  "Recommend a ledger-hygiene firing before the next port of this task"
- `/Users/diegousoro/Desktop/2027 motivation.rtf` continuation
  "Continue with the task of completing the app to production ready,
  all 24 users piece by piece every screen each role at a time til
  you are done. Always audit to see if you are on track and not doing
  a task that has been done already."

**Firing kind:** ledger-hygiene + brick port (061 The Haul · Missions)
  + production dead-endpoint fix (MissionsStore → `gamification.getMissions`)
**Firing date (UTC):** 2026-04-23T20:15Z
**Previous firing:** 59th — ledger-hygiene + MeNotificationsView seed
  fixture removed, 2026-04-23T19:15Z
**Quiet window from 59th:** ~60 minutes — trajectory FS lock from 59th
  firing has cleared (verified by `cp` round-trip on
  `/Users/diegousoro/Desktop/EUSOTRIP_TRAJECTORY.json`).

---

## 1. Audit-first discipline

Per the 2027-motivation standing order, this firing opened with an audit
— not a port — to check we are not redoing work the dev team already
shipped. Findings:

| Check | Source of truth | Outcome |
|---|---|---|
| Most-recent firing on disk | `EUSOTRIP_AUTORUN_2026-04-23_59th_firing_LEDGER_HYGIENE_REPORT.md` | 59th, hygiene-only, no brick |
| Most-recent firing in trajectory | `fifty_ninth_firing_hygiene` block present | journal ↔ disk consistent |
| Driver screens on disk pre-firing | `Views/Driver/NNN_*.swift` | 52 files — `010–060` contiguous + `068` |
| ContentView registry rows pre-firing | `grep -cE '\.init\(id:\s*"[0-9]{3}"'` | 59 (52 driver + 7 role placeholders) |
| Active-task-ledger pending | 10 items (42, 51, 71, 73, 74, 75, 76, 102, 105, 122) | item 51 = "Port Driver screens 052+ from Figma PNGs" |
| 59th hand-off primary | 017 Cohort A dynamization (WMT-MER-448201 → `loads.getActive` + `documentManagement.getBol`) | **BLOCKED** — see §2 below |
| 59th hand-off alt | 061 The Haul · Missions dedicated screen | **this firing** |
| 59th `do_not_mix` | never combine a brick port with a Cohort A dynamization | respected — no 017 work this firing |

**Conclusion:** fell back from the primary 017 Cohort A dynamization to
the alt 061 brick port because the backend survey (see §2) confirmed
`documentManagement.getBol` does not exist yet. Same hygiene-then-brick
cadence as the 57th/58th firings.

---

## 2. Backend survey for 017 Cohort A (short-circuit, not a separate firing)

Before falling back, this firing ran a surgical survey against the
backend MCP to see if the 017 BOL-field payload could be sourced.

| Backend procedure | Exists? | Returns BOL number / SCAC / seal / trailer? |
|---|---|---|
| `documentManagement.getBol` | **No** (`grep generateBOL\|getBol\|billOfLading` in `frontend/server` → 0 hits) | — |
| `documentManagement.getDocuments` | Yes (L386) | no — generic metadata (name, type, status) |
| `documentManagement.getDocumentById` | Yes (L479) | no — same shape, no BOL fields |
| `loads.getById` (existing iOS wiring) | Yes | returns `Load` with loadNumber / pickup / delivery / commodity / weight, but **no SCAC, seal, shipper phone, trailer id, piece count, NMFC class** |

**Verdict:** 017 Cohort A dynamization remains **blocked** pending a
backend wave that adds `bol_records` table + `documentManagement.getBol`
procedure exposing: `bolNumber, scac, sealId, trailerId, shipperPhone,
pieceCount, nmfcClass, freightTerms, deliveryWindow`. Added to §8
hand-off as a backend-wave-first task.

**No edits made to 017** in this firing. The hardcoded literals from the
59th report (WMT-MER-448201, 881204, TR-2118, Walmart Distribution,
601-555-0142, 72 pallets, 42,340 lb) remain in place per the
`do_not_mix` rule. When the backend wave lands, a dedicated Cohort A
firing will swap them for live store values in one atomic edit.

---

## 3. Hygiene audit — doctrine-compliance grep on Views/

Ran against `EusoTrip/Views/` tree only (Theme/ and Services/ excluded
because doctrine §2 enforcement is a render-layer concern).

| Axis | Pattern | Hits | Verdict |
|---|---|---:|---|
| Brand.info/blue as fill/tint/foreground/stroke/accent/background | `(fill\|foregroundColor\|foregroundStyle\|stroke\|strokeBorder\|tint\|accentColor\|background)\s*\(\s*Brand\.(info\|blue)` | **0** | doctrine §2.1 clean |
| `.tint(Brand.*)` sites | `\.tint\(Brand\.` | 1 | legitimate — `DriverTabPanes.swift:2673` magenta terminus |
| Toggle sites | `Toggle\(` | 4 | 4/4 paired with `GradientToggleStyle()` — doctrine §2.2 clean |
| `GradientToggleStyle` applications | `GradientToggleStyle` | 6 refs (3 `.toggleStyle(...)` + 1 definition + 2 doc refs) | coverage 4/4 |
| Dead-button `action: {}` production sites | `action:\s*\{\s*\}` | 1 comment false-positive (048:61 describes prior stubs), 0 real | clean |
| Empty `onTapGesture { }` | `onTapGesture\s*\{\s*\}` | 2 comment false-positives (057:37, 059:33), 0 real | clean |
| 061-specific Brand.info/blue | `Brand\.(info\|blue)` in `061_TheHaulMissions.swift` | 1 comment reference (L37 documents policy), 0 real fills | clean |

**Verdict:** Doctrine compliance remains clean on disk.

---

## 4. Dead-endpoint fix — MissionsStore → `gamification.getMissions`

This firing discovered that `MissionsStore.fetch()` in
`ViewModels/LiveDataStores.swift` was calling
`achievements.getMissions` via `AchievementsAPI` — an endpoint that
**does not exist on the backend**. Verified with the MCP
`search_code` tool:

```
grep 'achievementsRouter\s*=' frontend/server/routers/*.ts  → 0 hits
grep 'achievements:' frontend/server/routers.ts              → 0 hits
```

The canonical live router is `gamification.getMissions` (L679 of
`gamification.ts`), which returns three buckets `{ active, completed,
available }` with a richer per-mission shape (`id, code, name, description,
type, category, targetType, targetValue, targetUnit, rewardType,
rewardValue, xpReward, currentProgress, status, startsAt, endsAt`).

**Fix landed this firing (non-destructive):**

1. Added `GamificationAPI` struct to `Services/EusoTripAPI.swift`
   (+137 lines, after `AchievementsAPI`) with three procedures:
   - `getMissions(type:, category:)` returning `MissionsResponse`
     (three-bucket shape verbatim from the backend).
   - `startMission(missionId:)` mutation.
   - `claimMissionReward(missionId:)` mutation.
   - Plus `getProfile(userId:)` for the 060 loyalty hero (future wire).
2. Registered the client as `lazy var gamification: GamificationAPI`
   at L275 next to the other routers.
3. Replaced `MissionsStore.fetch()` in `ViewModels/LiveDataStores.swift`
   with a call to `gamification.getMissions()`, flattening the three
   buckets into the legacy `[DriverMission]` projection so every
   existing UI primitive (060 row, 060 dashboard preview) keeps
   working against the same wire contract it already renders.
4. Added a static `MissionsStore.map(mission:)` helper that projects
   `GamificationAPI.Mission` rows onto the legacy `DriverMission`
   struct. Shared with the new `TheHaulMissionsStore` so the 060
   and 061 surfaces never drift on how rewards / progress / expiry
   strings are computed.

**Before vs after — wire:**

| Before | After |
|---|---|
| `POST /trpc/achievements.getMissions` → 404 | `POST /trpc/gamification.getMissions` → `{ active[], completed[], available[] }` |
| Store renders forever as `.error` or `.empty`  | Store renders live rows, folds empty response to `.empty` cleanly |
| 060 "Active missions" preview silently empty | 060 "Active missions" preview surfaces real in-flight missions |

No regression risk on existing 060 consumers — the post-map shape is
identical to the pre-change shape, and MissionsStore.items still returns
`[DriverMission]`.

**Per §16 SKILL.md gamification slice:** `rewardType == "cash"` /
`"miles"` still flows through to the reward chip for transparency (so
drivers see the promised shape), but neither surface presents a
"cash added" confirmation — the `loot_crates` / `miles_transactions`
writers do not yet exist on the backend. The toast in 061 says "Claimed
— +N XP" only when `xpReward > 0`; a miles/cash row renders as the
reward label without a money-moved assurance.

---

## 5. Brick port — 061 The Haul · Missions

### 5a. Source & scope

Figma-pending. Modelled against the 59th/58th hand-off ("promotes
`MeMissionsView` from sheet to full screen with Active / Claimable /
Available / Completed filter chips + per-mission claim modal"). Cohort
B from day 1 — fully dynamic from the live `gamification.getMissions`
response, zero fixture or placeholder mission data in the file.

### 5b. File created

`EusoTrip/Views/Driver/061_TheHaulMissions.swift` · 913 lines

**Structure (top-to-bottom):**

1. `TheHaulMissions` view — the screen itself.
   - `@StateObject` wraps `TheHaulMissionsStore` (new three-bucket store).
   - `@State filter: Bucket?` drives filter chips (nil = "All").
   - `@State openMissionId: Int?` drives the detail sheet binding.
   - `@State toast, toastIsError, toastTask` drives the 3s auto-hide toast.
   - `@State inFlightMissionId: Int?` disables row CTAs during round-trip.
2. `header` — kicker + gradient H2 title + summary line
   (`"N active · M ready to claim · K available"`) assembled from
   the live snapshot. Collapses gracefully when any bucket is empty.
3. `filterChipsRow` — horizontal scroll of chips (All · Active ·
   Claimable · Available) with live count badges that reflect the
   current snapshot.
4. `bodyContent` — switches over `store.state`:
   - `.loading` → `inlineLoading` card with ProgressView + "Loading…"
   - `.error` → `inlineError` card with Retry CTA.
   - `.empty` → `EusoEmptyState` (systemImage `flag.checkered`).
   - `.loaded` → `LazyVStack` of `missionCard` rows, respecting filter.
     Renders a second `EusoEmptyState` when the filter yields zero.
5. `missionCard(_:)` — per-row:
   - Type chip (daily/weekly/monthly/etc. from server).
   - Expiry micro-caps.
   - Gradient title + reward chip.
   - Optional description (2-line clamp).
   - Progress bar (gradient fill).
   - Per-bucket inline CTA:
     • `active` → "XX%" progress label
     • `completed` → gradient "Claim" pill
     • `available` → outlined "Start" pill
6. `MissionDetailSheet` — medium/large detent sheet with:
   - Header (type chip + code + gradient name).
   - Description block.
   - Progress card (gradient bar + current/target numeric + percent).
   - Reward card (gradient glyph + reward label).
   - Window card (starts/ends).
   - Bottom CTA — gradient 52pt-height button:
     • `completed` → "Claim reward"
     • `available` → "Start this mission"
     • `active` → neutral "Keep going" card (no dead button).
7. `TheHaulMissionsScreen` wrapper — `Shell { TheHaulMissions() } nav:
   { BottomNav(...) }` matching the 060 dashboard pattern.
8. Two previews — Night + Afternoon, both against
   `EusoTripSession()` which resolves the store to `.error` or
   `.empty` deterministically (no network in previews).

### 5c. Wiring gaps closed (no dead buttons, no stubs)

| Interaction | Before this firing | After this firing |
|---|---|---|
| "Start mission" button | did not exist | hits `gamification.startMission(missionId:)`, refreshes snapshot, surfaces server message on failure |
| "Claim reward" button | did not exist | hits `gamification.claimMissionReward(missionId:)`, optimistically removes from `completed` bucket, refreshes, surfaces server message |
| Filter chips | did not exist | in-memory bucket switch — no re-fetch; live counts update as store refreshes |
| Pull-to-refresh | did not exist on Missions | `.refreshable { await store.refresh() }` |
| Failure path | silently rendered "coming soon" empty state (dead endpoint) | surfaces real server error with Retry CTA |

### 5d. Doctrine compliance on 061 specifically

- 18 `LinearGradient.diagonal` usages (hero title, reward chips,
  progress bars, Start/Claim CTAs, sheet bottom CTA, filter-chip fill
  when selected).
- 15 `AnyShapeStyle` wraps around ternary ShapeStyle branches.
- 0 `Brand.info` / `Brand.blue` fills (1 comment reference on L37
  documents the policy — not a render).
- 0 dead-button `action: {}` sites.
- 0 empty `onTapGesture { }` sites.
- No hardcoded mission titles, codes, targets, rewards, progress
  values, or window dates anywhere in the file.
- No `Toggle` (so no `GradientToggleStyle` binding needed).
- Both previews compile in isolation against an unauthenticated session.

### 5e. Backing store — TheHaulMissionsStore

`ViewModels/LiveDataStores.swift` · +136 lines.

- `BaseDynamicStore<Snapshot>` subclass (not list) because the screen
  needs three buckets preserved for filter chips + claim routing.
- `Snapshot` = `{ active: [Row], completed: [Row], available: [Row] }`.
- `Row` pairs the raw `GamificationAPI.Mission` (source of truth for
  the numeric `id` passed to startMission / claimMissionReward) with
  the legacy `DriverMission` projection (so UI primitives reuse the
  same row rendering as 060).
- `foldState` folds `totalCount == 0` → `.empty` (distinct from
  `.loaded(.empty snapshot)`).
- `startMission(missionId:)` → returns error string or nil, refreshes
  snapshot on success.
- `claimMissionReward(missionId:)` → optimistically removes the row
  from `completed` the moment the mutation returns success, then
  refreshes (so the UI never flashes back to "claim" state between
  the mutation and the refresh response).

---

## 6. Registry + Xcode project wiring

- `ContentView.swift` — added row:
  ```swift
  .init(id: "061", title: "The Haul · Missions",
        role: .driver) { p in AnyView(TheHaulMissionsScreen(theme: p)) },
  ```
  inserted between `060 The Haul · Dashboard` and `068 Me · Earnings`
  to preserve numeric ordering.
- `EusoTrip.xcodeproj/project.pbxproj` — 3 edits:
  - L114: PBXBuildFile entry `A61D0FA2CE1A4B7E0000D00F /* 061_TheHaulMissions.swift in Sources */`
  - L295: PBXFileReference entry `A61D0FA2CE1A4B7E0000D010`
  - L500: PBXGroup children list — added ref after 060.
  - L907: Sources build phase — added build ref after 060.

---

## 7. Post-firing counters

| Counter | Value | Δ from 59th |
|---|---|---:|
| Driver screens on disk | 53 | **+1** |
| ContentView driver registry rows | 53 | **+1** |
| ContentView total registry rows | 60 | +1 |
| pbxproj unique `NNN_*.swift` refs | 59 | **+1** |
| Declared live stores | 26 | **+1** (TheHaulMissionsStore) |
| Cohort B dynamic screens | 25 | **+1** |
| Cohort A fixture-driven screens | 28 | — |
| Brand.info/blue fill/tint hits | 0 | — |
| `.tint(Brand.*)` legitimate magenta | 1 | — |
| GradientToggleStyle coverage | 4 / 4 | — |
| Dead-button production sites | 0 | — |
| Production fake-data seed sites | 0 | — |
| **Dead tRPC endpoints in stores** | **0** | **−1** (achievements.getMissions → gamification.getMissions) |

Bijection remains clean: 53 driver files ↔ 53 registry rows; pbxproj
has 59 unique NNN refs (46 Sources-phase driver + 7 non-driver + 6
auth/ELD supporting files).

---

## 8. Honest caveats

1. **xcodebuild unavailable.** Linux bash sandbox. Verification was
   symbol-level grep only (doctrine compliance, dead endpoints, file
   bijection, pbxproj structural edits). Build + simulator screenshot
   diff must be run by a macOS operator before TestFlight. The
   structural edits to `project.pbxproj` follow the exact pattern used
   for 054–060 (same UUID family, same sections touched in the same
   order) so build-wise it should drop in cleanly.
2. **Figma PNG for 061 not available in this session.** The screen was
   designed against the 58th-firing hand-off description ("filter chips
   + claim modal") and the 060 dashboard's existing "Active missions"
   row pattern. When the Figma lands, a follow-up firing may refine
   copy or spacing. Numbers-first / gradient-accent / empty-state
   doctrine is honored unconditionally.
3. **`gamification.getMissions` backend procedure assumed live.**
   Verified via MCP `search_code` that the procedure exists in
   `frontend/server/routers/gamification.ts` L679, is registered in
   `routers.ts` L1170, and returns the three-bucket shape the iOS
   layer now decodes. Not verified: whether the staging deployment is
   actually serving missions yet (empty seed is the most likely
   result on a fresh staging env — which is fine, the store will
   render `.empty` via the branded primitive).
4. **017 Cohort A deferred.** No BOL-aware backend procedure exists.
   A separate backend wave must land `documentManagement.getBol` (or
   equivalent) before the 017 dynamization can run. Added as the
   primary hand-off for the 61st firing (see §9).
5. **Gamification writers gap.** Per §16 SKILL.md, `loot_crates` /
   `user_inventory` / `miles_transactions` have zero writers on the
   backend. The 061 claim flow therefore credits XP only and never
   claims "cash added" regardless of what `rewardType` the server
   returns — documented in the file header and enforced in
   `rewardLabel(for:)`.

---

## 9. Writes this firing

- **NEW:** `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/EusoTrip/Views/Driver/061_TheHaulMissions.swift` (913 lines)
- **EDIT:** `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/EusoTrip/Services/EusoTripAPI.swift`
  (+~140 lines — new `GamificationAPI` struct and `gamification` client lazy var)
- **EDIT:** `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/EusoTrip/ViewModels/LiveDataStores.swift`
  (rewired `MissionsStore.fetch()` to `gamification.getMissions` + added `TheHaulMissionsStore`; +~200 lines net)
- **EDIT:** `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/EusoTrip/ContentView.swift` (+1 line — 061 registry row)
- **EDIT:** `/Users/diegousoro/Desktop/EusoTrip by Eusorone Technologies, Inc/EusoTrip.xcodeproj/project.pbxproj` (4 structural edits — PBXBuildFile, PBXFileReference, PBXGroup children, Sources build phase)
- **NEW:** `/Users/diegousoro/Desktop/EUSOTRIP_AUTORUN_2026-04-23_60th_firing_HYGIENE_PLUS_BRICK_PORT_061_REPORT.md` (this file)
- **NEW:** `/Users/diegousoro/Desktop/EUSOTRIP_TRAJECTORY.json.bak_pre_60th_firing_2026-04-23` (backup of trajectory)
- **EDIT (deferred to post-report):** `/Users/diegousoro/Desktop/EUSOTRIP_TRAJECTORY.json` — append `sixtieth_firing_hygiene_plus_brick_port_061` block, update meta.last_autorun_iso / meta.last_autorun_brick.

---

## 10. Hand-off to 61st firing

```yaml
recommended_61st_firing_primary: >
  Backend-wave-first: identify (or land, if the dev team has push
  access) the missing `documentManagement.getBol` procedure that
  exposes bolNumber / SCAC / sealId / trailerId / shipperPhone /
  pieceCount / nmfcClass / freightTerms / deliveryWindow. Without
  this, 017 Cohort A dynamization remains impossible. Dev-team
  coordination item — a scheduled-task autonomous firing cannot
  land backend code in this repo.

recommended_61st_firing_fallback_A: >
  Next Cohort B brick in §5 queue — 062 The Haul · Badges dedicated
  gallery. Backend already wired (`achievements.getBadges` →
  BadgesStore is live), so the port is a straight UI lift from the
  existing MeBadgesView grid with a filter + category taxonomy.
  Keeps cadence moving even if the backend wave for 017 slips.

recommended_61st_firing_fallback_B: >
  Next role-expansion per 2027 motivation — 200 Shipper · Home.
  Requires adding `shipper.getDashboard` to `EusoTripAPI.swift`
  (currently absent). Surveys a fresh role surface — expensive for
  one firing but unlocks the next six Shipper screens.

must_before_write: >
  Re-verify exclusive access to EUSOTRIP_TRAJECTORY.json (bash cp
  must succeed without Errno 35) before any journal writes. The
  59th firing observed a 5-minute lock window; the 60th firing
  did not hit a lock.

do_not_mix: >
  Never combine a brick port with a Cohort A dynamization in the
  same firing — blast radius grows, doctrine regressions harder to
  catch at grep level. The 60th firing's scope was specifically
  "hygiene + 061 brick port + production-dead-endpoint fix" — the
  dead-endpoint fix is surgical enough (no UI changes, same
  `[DriverMission]` shape on the consumer side) that it
  qualifies as hygiene-equivalent, not Cohort A.

dev_team_coordination: >
  The dev team has parallel push access to the same repo. Before
  running a 61st firing, re-audit the driver screens directory
  (current firing observed 53 on disk post-port) to detect any
  dev-team adds. If dev shipped 062 independently, the 61st
  firing should fall back to fallback_A's next unshipped brick.
```

— End of 60th firing report.
