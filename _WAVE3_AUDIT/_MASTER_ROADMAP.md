# Wave‑3 Master Roadmap · EusoTrip Mobile ↔ Web Platform Parity

**Audit run:** 2026‑04‑18 (10 parallel agents)
**Scope:** 121 Driver Figma screens (light + dark), cross‑referenced against ~286 tRPC routers and the current SwiftUI port.

Individual reports live next to this file:
`agent_00.md` through `agent_09.md`.

---

## 1 · Headline numbers

| Bucket | Screens | Range | Swift ported | Backend coverage | Report |
| --- | ---: | --- | ---: | ---: | --- |
| 00 | 13 | 010 – 022 | **13 / 13** | ~72% | `agent_00.md` |
| 01 | 13 | 023 – 035 | 0 / 13 | ~54% | `agent_01.md` |
| 02 | 13 | 036 – 048 | 0 / 13 | ~58% | `agent_02.md` |
| 03 | 13 | 049 – 061 | 0 / 13 | ~65% | `agent_03.md` |
| 04 | 13 | 062 – 070 | 0 / 13 | ~46% | `agent_04.md` |
| 05 | 13 | 071 – 077 | 0 / 13 | ~61% | `agent_05.md` |
| 06 | 13 | 078 – 089 | 0 / 13 | ~74% | `agent_06.md` |
| 07 | 13 | 090 – 102 | 0 / 13 | ~62% | `agent_07.md` |
| 08 | 13 | 103 – 115 | 0 / 13 | ~69% | `agent_08.md` |
| 09 | 4 | 116 – 119 | 0 / 4 | ~14% | `agent_09.md` |
| **Total** | **121** | 010 – 119 | **13 / 121** (10.7%) | ~62% weighted | — |

**Trendline.** Bucket 00 (already ported) is our working parity reference. Everything from 023 onward is fresh SwiftUI work. Bucket 09 (nav/routing) is the lowest‑coverage bucket — the traffic router is a triple stub and the entire reroute / price‑lock / tank‑status domain is missing.

---

## 2 · Cross‑cutting themes (surfaces touched by multiple screens)

These are the gaps that, if closed, unblock the widest set of screens. Listed by blast radius — most screens affected first.

### 2.1 · Per‑surface ESANG "coach" copy

**Affected:** ~60+ screens (every screen that shows a narrated AI card, coaching tip, or smart‑stop suggestion).

**What's missing.** There is no procedure to generate screen‑contextual LLM copy. `esangAIv2` handles chat, but the static callouts ("You're 12 min ahead", "Detach in 4 steps", etc.) have no endpoint.

**Proposal.** Add `esangAI.getCoachCopy({ screen, context }) → { primary, secondary, cta? }`. Cache per‑screen, invalidate on core state change. Stream via socket.io for live panels (081 ESANG Chat, 053 Dispatch Chat).

---

### 2.2 · Load / run lifecycle state machine incomplete

**Affected:** 014 – 034, 036 – 048 (end‑to‑end pickup + delivery flows).

**What's missing.** `loadLifecycle.ts` covers the common states but lacks tanker‑specific transitions (`LOCKED`, `BACKING_IN`, `LOADING`, `LOAD_LOCKED_FILLED`, `DETACHING`, `UNLOADING`, `DISCONNECTING`, `CONNECTING`) and several dock‑side substates. Chip text on the Figma screens can't be rendered faithfully until these exist.

**Proposal.** Extend the `loadStatus` enum (`drizzle/schema.ts:277`) plus `loadLifecycle.executeTransition` guards. Introduce sub‑state payloads for tanker vs van vs flatbed so one state machine powers all three.

---

### 2.3 · In‑bay critical path — no discharge / disconnect / backing‑assist routers

**Affected:** 023 Backing In, 024 Unloading, 032 Detach, 039 Backing Assist Receiver, 040 Discharge, 042 Disconnect, 043 Disconnect Confirmed, 044 Connect Drop Hose, 048 Arrival‑Gate Task Active.

**What's missing.** No routers for `discharge.*`, `disconnectWizard.*`, `connectWizard.*`, `backingAssist.*`. Camera and sensor streams referenced in the UI (rear‑cam tiles, ultrasonic distance) have no server ingestion surface.

**Proposal.** New router family `bayOps/` with one router per wizard. Each exposes `start`, `advanceStep`, `recordEvidence`, `complete`, `abort`. Back each with a small FSM table keyed on `loadId`. Evidence goes to `bay_ops_events` with blob links to S3.

---

### 2.4 · Telemetry gap — trailer, tank, scale

**Affected:** 010, 016, 018, 030, 085, 101, 117, 118, 119.

**What's missing.** Live fill %, flow rate, pressure, temperature, weight sensor values, tank status, axle/gross scale values. `scales.ts` is read‑only; there's no `trailerTelemetry.*`, `tankMonitor.*`, or `fuel.getTankStatus`.

**Proposal.** New `telemetry/` router family:
- `trailerTelemetry.getSnapshot({ trailerId })`
- `tankMonitor.getLoadingSnapshot({ loadId })`
- `fuel.getTankStatus({ vehicleId })`
- `scales.recordWeigh({ loadId, axle, gross, lat, lng })`

Ingestion is MQTT from ELD / sensor gateway into a new `telemetry_events` hypertable.

---

### 2.5 · Navigation / routing pipe disconnected

**Affected:** 013, 018, 020, 037, 116, 117, 118, 119.

**What's missing.** `navigation.calculateRoute` returns polyline + ETA but no per‑step maneuvers; `traffic.getIncidents / getConstruction / getDelays` all return `[]`; `routes.requiredBreaks` / `fuelStops` schema columns exist but are never written; no `routing.compareAlternatives`, no `routing.applyReroute`, no reroute‑decision log.

**Proposal.**
- Wire `trafficNerve` service output through `traffic.*` procedures (remove stubs).
- Add `navigation.getNextManeuver({ routeId, lat, lng })`.
- Add `routing.compareAlternatives({ routeId })` + `routing.applyReroute({ routeId, alternativeId, reason })`.
- Create `reroute_decisions` table and write on every apply.
- Add `tolls.estimateForRoute({ routeId, axleCount })` via ITA Tolls or INRIX Tolls API.

---

### 2.6 · Driver‑side yard / facility

**Affected:** 015, 021, 022, 029, 038, 047, 086.

**What's missing.** `yardManagement.*` exists for dispatchers but there's nothing driver‑facing for queue position, guard check‑in, dock‑push ETA, kiosk reader integration, facility wait prediction.

**Proposal.**
- `yardManagement.getMyQueuePosition({ loadId })`
- `yardManagement.predictDockPush({ loadId })`
- `facilities.guardCheckIn({ loadId, gateId, evidencePhoto })`
- `facilities.scanKiosk({ kioskId, code })`

---

### 2.7 · Notifications — mutation surface missing

**Affected:** 064 Notifications Inbox, 074 Notification Center, 095 Notifications, 112 Inbox, 113 Thread, 114 Broadcasts.

**What's missing.** Read/list procedures exist (`notifications.list`, `getGroupedByDay`) but drivers can't snooze, mark‑all‑read, or draft replies. No typed `channel` enum for filtering.

**Proposal.** Extend `notifications.ts` with `snooze`, `clearRead`, `markAllRead`, `setChannelPreferences`, and a `notifications.draft` subsurface for compose/save/send.

---

### 2.8 · Gamification / missions / streaks

**Affected:** 067 The Haul Mission, 068 The Haul Leaderboard, 069 Achievements Wall, 071 Daily Streak, 070 Invite a Driver.

**What's missing.** `gamification.ts` lacks cash‑reward missions, a "Verifying" objective state, HOLD rank‑lock, per‑rarity badge counts, share endpoints, and the `users.getReferralInfo` return isn't persisted.

**Proposal.** Split into `missions.ts` + `achievements.ts`. Add `missions.listForMe`, `missions.redeem`, `achievements.share`, `referrals.create/claim`, and a `rankLocks` table.

---

### 2.9 · Feedback / EusoTicket / roadside‑ticket

**Affected:** 065 EusoTicket Exception, 065 Help and Support, 066 Feedback and Ratings, 086 Roadside Inspection, 107 Roadside.

**What's missing.** `feedback.ts` is a stub (feedback.ts:13‑20). No exception‑observation mutation (category + severity + witnesses + voice + photo + GPS). `driverMobile.getRoadsideAssistance` only creates tickets, no list/detail/close/policy.

**Proposal.** Rewrite `feedback.ts`. New `exceptions.ts` with `create`, `attachEvidence`, `close`. New `roadsideTickets.ts` with `list`, `getById`, `update`, `close`, `policyForCarrier`.

---

### 2.10 · Availability / scheduling / utilization

**Affected:** 083 Schedule Availability, 077 Home Schedule, 078 Home Compliance.

**What's missing.** No `availability` router, no `blockTime` / `setAvailability`, no utilization metric.

**Proposal.** New `availability.ts` with weekly‑grid CRUD + ICS export + conflict resolution against `hos_logs`.

---

### 2.11 · Financial composition / settlement detail

**Affected:** 054 HaulPay Settlement, 055 Day Close Wallet, 089 Earnings Detail, 092 Settlement Detail, 093 Tax Vault, 073 Tax and 1099.

**What's missing.** Driver‑facing earnings composition is thin — deductions, adders rollup, goal procedures, 1040‑ES quarterly, atomic trip‑wrap submit, 1099 download.

**Proposal.** Extend `earnings.ts` with `getComposition({ loadId })`, `getGoal`, `setGoal`. Extend `taxReporting.ts` with `download1099`, `estimateQuarterly`.

---

## 3 · Per‑bucket top‑3 gap summary (click through to agent reports for detail)

### Bucket 00 · 010–022 (13/13 ported · ~72% backed)
1. Hazmat tank‑loading & trailer telemetry — no fill %, flow rate, pressure, temp feed.
2. Driver‑side facility queue / guard check‑in / dock‑push ETA.
3. Turn‑by‑turn maneuver + dash‑cam control + toll projection.

### Bucket 01 · 023–035 (0/13 ported · ~54% backed)
1. Tanker live‑ops router missing (pickup wizard → telemetry → verdict → detach).
2. Dock backing‑aid cam/sensor router + unload/pallet model.
3. `loadLifecycle.ts` missing tanker sub‑states (LOCKED, BACKING_IN, …).

### Bucket 02 · 036–048 (0/13 ported · ~58% backed)
1. In‑bay routers absent (`discharge.*`, `disconnectWizard.*`, `connectWizard.*`, `backingAssist.*`).
2. ESANG smart‑stop + spotter workflow.
3. Custody‑seal mutation + kiosk reader + rack/arm assignment.

### Bucket 03 · 049–061 (0/13 ported · ~65% backed)
1. HazmatPool domain missing entirely (054, 056, 060, 061).
2. Spectra‑Match findings + live run telemetry (049, 050).
3. `rateConfirmations.ts` is a 4‑procedure stub returning `[]` (052, 055).

### Bucket 04 · 062–070 (0/13 ported · ~46% backed)
1. `feedback.ts` stub + `users.getReferralInfo` not persisted.
2. No EusoTicket exception mutation.
3. Gamification gaps (cash rewards, Verifying state, HOLD rank‑lock).

### Bucket 05 · 071–077 (0/13 ported · ~61% backed)
1. No `dvir` router at all.
2. No per‑screen ESANG copy generator.
3. Missing aggregate/digest endpoints (`laneRadar.getDigest`, `driverMobile.getMorningBrief`, `trips.getWeekly`).

### Bucket 06 · 078–089 (0/13 ported · ~74% backed — highest unbuilt bucket)
1. Driver availability/scheduling model absent (083).
2. Roadside‑inspection stack missing (Level 1/2/3 entity, readiness bundle, inspector token).
3. Earnings composition thin (deductions, adders, goal).

### Bucket 07 · 090–102 (0/13 ported · ~62% backed)
1. Per‑surface ESANG context procedure missing.
2. Evidence/receipt ↔ claim linking schema absent (092, 096, 097, 098).
3. `scales.ts` is read‑only — no pass/pull logging, streaks, PrePass receipts.

### Bucket 08 · 103–115 (0/13 ported · ~69% backed)
1. AI‑advisor narration endpoint missing (~10 screens show LLM copy with no backing query).
2. Ack / snooze / markAllRead / draft mutations absent (110, 112, 114).
3. Roadside‑ticket lifecycle half‑built.

### Bucket 09 · 116–119 (0/4 ported · ~14% backed)
1. Traffic router is stubs → `trafficNerve` service is unconsumed.
2. No reroute mutation and no alternate‑route persistence.
3. Fuel price‑lock + tank‑status missing entirely.

---

## 4 · Recommended attack order (which gaps to close first)

Ordered by **(impact × reach × unblock‑rate)**.

1. **Extend `loadLifecycle.ts` + `loadStatus` enum** (Theme 2.2) — unblocks ~30 screens of chip/state rendering.
2. **`trafficNerve` → `traffic.*` procedures + reroute mutations** (Theme 2.5) — unblocks bucket 09 entirely.
3. **`telemetry/` router family** (Theme 2.4) — unblocks the tanker live‑ops and scales screens.
4. **`bayOps/` routers for wizards** (Theme 2.3) — unblocks 9 in‑bay screens.
5. **`esangAI.getCoachCopy`** (Theme 2.1) — unblocks ~60 coach cards at once.
6. **`notifications.*` mutation surface + `feedback.ts` rewrite** (Themes 2.7, 2.9).
7. **`dvir` router + `availability.ts` + `missions.ts/achievements.ts` split** (parallelizable).
8. **Financial composition** (Theme 2.11) — earnings/tax deep detail.
9. **Driver‑side yard/facility** (Theme 2.6).

---

## 5 · SwiftUI port backlog

After closing backend gaps, the port work is **108 screens** (010–022 is done). The existing 010–020 files are the canonical pattern — glass cards, `@Environment(\.palette)`, `GlassField`, `CTAButton`, `BottomNav`, `HereMapView` — reuse all of these. The port itself is a separate wave and can begin in parallel with backend gap #1 and #2 since those don't block the UI skeleton (only the wiring).

---

## 6 · Next action

Spin Wave‑4: 10 agents, one per theme (2.1 – 2.11 minus any we merge), each writing a concrete router diff (files changed, new files created, new schema migrations, new types in `@eusotrip/api-contract`). Produce diffs, not code — we review before we let them touch the web repo.
