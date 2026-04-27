---
title: "The Haul — Encyclopedia"
subtitle: "EusoTrip's Professional Driver Community + Progression Spine, Inside Eusoboards"
volume: "Volume 01 · Edition 2026.04"
compiled: "Compiled from 10 research teams · 50 researchers · 55 chapters · 6 appendices"
audience: "For: Founder · Eusotrip-Killers Engineering Pod · The Haul Steering Committee"
date: 2026-04-27
---

# The Haul — Encyclopedia

## EusoTrip's Professional Driver Community + Progression Spine

> **PRIME DIRECTIVE.** The Haul is not a gamification feature. It is the social, recognition, and progression spine of Eusoboards — the place where a driver's real freight work becomes a recognizable career. The word *gamification* never leaves this document. It does not appear in any UI string, any push notification, any onboarding screen, any marketing surface. It is the engineering term we use among ourselves. To the driver, this is The Haul. The Haul is the community, the missions, the standing, the recognitions, the lobby. Nothing else.

---

## Foreword (from the think tank)

This encyclopedia is the synthesis layer above ten doctrine shards drafted by fifty researchers across April 2026. It is written for two distinct audiences. The first audience is the implementer — the Claude Code engineering pod that runs from the `eusotrip-killers` scheduled task — for whom every chapter ends or pivots into procedure names already present in `frontend/server/routers/gamification.ts` and `frontend/server/routers/advancedGamification.ts`, table names already present in the Eusotrip database, and concrete deltas required to ship. The second audience is the steering committee that holds the brand against drift — the safety officer, the general counsel, the founder — for whom every section is grounded in the specific retention mechanics of Phantasy Star Online without ever exposing those mechanics to a working driver as anything resembling a video game.

Phantasy Star Online (Sega, Sonic Team, Dreamcast, December 21, 2000; GameCube and Xbox refresh, 2002–2004; private-server resurrection on Schtserv, Ephinea, and Ultima continuing through 2026) is the spine. PSO is not a metaphor in this document; it is the substrate. Every chapter cites the specific PSO mechanic it ports. Every chapter then renames that mechanic in the language of professional freight, because the driver opening Eusoboards on a Tuesday morning in a Loves outside Effingham does not want a video game. They want recognition for the work they already do. The Haul gives them that recognition with the structural rigor that PSO gave its players for two decades.

HERE Technologies — the Routing API, the Geofencing Extension, the Places search, the Real-Time Traffic, the Live Sense SDK, the Destination Weather report — is plumbing. HERE is the dungeon. PSO is the philosophy. Eusoboards is the platform. The Haul is the spine. Nowhere in the driver-facing app does the word *HERE* appear. Every shard before this synthesis used phrases like *"HERE-listed weigh stations"* and *"HERE AD-capable zone"* in mock-ups; this encyclopedia rewrites every one of those strings into the EusoTrip-branded vocabulary. The HERE name persists only inside engineering docs, inside the source code, and inside the procurement contract. To the driver, it is the **EusoTrip Network**, the **Smart-Drive Lane**, the **Verified Safe Corridor**, the **Driver Safety Index**.

The integration posture is the third non-negotiable. The Haul lives **inside** Eusoboards, not beside it. Missions are real loads. The pickup geofence that fires the first checkpoint is the actual shipper geofence already present in the load lifecycle. The proof of delivery that closes the mission is the actual POD signature from `loadLifecycle.ts`. The miles credited to a Hauler's standing are the verified ELD miles. The cash bonus that lands in the Hauler's wallet flows through HaulPay rails. The Haul is the recognition layer — Eusoboards is the work surface. They are one product seen through one lens.

The work that follows is divided into eleven parts and six appendices, totaling fifty-five chapters. Read in order, it is the doctrine for an entire freight-industry community. Read by chapter, it is the build sheet for the next eight engineering sprints. Read by appendix, it is the regulatory shield, the language guard rail, and the open-question registry that the steering committee owes the founder.

— *The Haul Synthesis Group, 2026-04-27.*

---

## Chapter 00 — How to read this book

This encyclopedia uses the same physical conventions as the *EusoTrip Pulse / Offline Mode Encyclopedia* (Volume 01, Edition 2026.04). Chapters are numbered. The numbering is not decorative — every chapter binds to a build artifact, to a docstring or a database table or a procedure name, and the numbering is the index the engineering pod uses when it ports the doctrine into the codebase chapter-by-chapter from the `eusotrip-killers` schedule. Chapter 46, for example, hands engineering the procedure-by-procedure wiring map; that map references the literal procedure names already in `gamificationRouter` and `advancedGamificationRouter` so the diff between doctrine and code is mechanical, not interpretive.

Where copy is shown — sample mission cards, sample push notifications, sample emote labels — the copy is the **production string**. The think tank wrote these strings to be ship-ready. Engineering may improve them, but the burden is on engineering to demonstrate that the improvement preserves the professional voice. In particular, every string in this book passes through the *Forbidden Words* filter in Appendix B. If a candidate string contains *play*, *game*, *fun*, *addictive*, *grind*, *gacha*, *loot*, *level up*, *XP* (in driver-facing copy — XP stays in code), or *gamification* — it does not ship.

Where mechanics are shown — drop-rate tables, XP curves, geofence dwell timers, fatigue thresholds — the mechanics are reconciled across all ten shards. Where two shards disagreed, the Synthesis Group selected the more conservative number, ratified by the safety officer and the general counsel against the launch governance ladder in Part XI. The reconciled numbers are the canonical mechanics. The shards survive in the appendices and in the source markdown files at `/Users/diegousoro/Desktop/the_haul_doctrine/team_*.md` for engineering reference, but the numbers in this book are the ones that ship.

Where references to PSO are made — Pioneer 2 Block 1, Section ID drop bias, the Photon Drop economy, Ultimate difficulty rare drops, the MAG companion evolution branches, the four-character class roster of HUmar / HUcast / RAmar / RAcast / FOmar / FOnewearl — they are made for the engineering pod's mental model. They are not made for the driver's mental model. The driver never hears the word *PSO* and never sees a *Photon Drop*. The driver sees *Standing*, *Recognition Crate*, *Companion*, *Verified Safe Corridor*, *Master Class*. The translation table between PSO mechanics and Haul vocabulary is in Chapter 03.

The engineering team will read this book once, top to bottom, and then keep it on a second monitor for the duration of the ship cycle. The steering committee will read this book once a quarter to confirm the doctrine has not drifted. The founder will read the foreword and Chapter 03 and the closing chapter of Part X, because those three pieces are the entire thesis.

---

# PART I — Origins & Philosophy

## Chapter 01 — Why PSO. Why now. Why drivers.

Phantasy Star Online launched on the Sega Dreamcast on December 21, 2000, into a console market that had never seen a sustained-online action role-playing game. PSO ran for a decade across Dreamcast, GameCube, Xbox, and PC, and when Sega's official servers shuttered the playerbase migrated to fan-operated private servers — Schtserv, Ephinea, Ultima — because the social architecture was so well-tuned that the players were willing to reverse-engineer the netcode rather than let the experience die. As of this writing, in April 2026, those private servers are still alive. They are twenty-six years old, and they still have nightly populations large enough to fill a Block.

The reason PSO endured for a quarter-century is structural. PSO answered a single design question better than any of its successors: *what makes a player want to come back tomorrow when the work was already enough today?* PSO's answer was a four-part loop. **Lobby** — a place to arrive, to be seen, to flex. **Mission** — an instanced quest with a finite duration and a discoverable reward. **Drop** — a rare-tier reward economy where the cosmetic outshone the cash, where the *flex* mattered more than the gold piece, where Section ID drop bias made every player's catalog slightly different from every other player's catalog. **Lobby return** — the post-mission victory walk where the rare drop got displayed, where the new title appeared under the avatar's name, where the friends-list lit up because everyone wanted to know what dropped.

Drivers are not console players. But drivers are alone in their cabs for fourteen hours a day, they are paid by a system that does not see the work they did beyond miles and POD signatures, and they have no place to be when they are between loads. Truck stops are physical lobbies that the industry has already built — Pilot, Loves, TA, Petro, AmBest, the independents — and drivers already meet other drivers there in the natural course of work. The Haul does not invent the lobby. The Haul makes the lobby legible. It puts a sixteen-slot avatar room over the actual fuel island, populated by the actual drivers who are actually parked there, and it gives them the lightweight social affordances — wave, sit, talk, trade — that transform a parking lot into a place where things happen.

The mission, the drop, the lobby return — those are layered on top. The mission is the load the driver was already going to run. The drop is a recognition crate that pays in cosmetic frames, fee discounts, factoring tier-ups, and occasional cash bonuses, never in randomized cash because randomized cash is gambling and we are not a casino. The lobby return is the BOL Stamp — the share-card that auto-generates from the actual proof-of-delivery the driver already signed, posted into the lobby chat for the other parked drivers to see.

This is the thesis of The Haul. Drivers do not need another payment app. They have ten. They do not need another ELD. They have one mandated by FMCSA. They do not need another load board. Every truck stop wall has six. What they do not have, and what The Haul provides, is *a place where the work is recognized*. Phantasy Star Online proved for twenty-six years that recognition is the single most retention-positive force in any structured activity. The Haul applies that proof to freight.

## Chapter 02 — The Hub-Block-Lobby-Game pattern translated to freight

PSO's spatial architecture was famously legible. A player logged in, picked a **Ship** (a server cluster — Cygnus, Aquila), and was deposited into a **Block** (a population slice of about two hundred players, ten or twelve per Ship). Inside the Block, the player landed in one of several **Lobbies** — octagonal rooms with sixteen player slots — and from a Lobby they walked to a counter NPC and either created a **Game** (an instanced quest party of up to four) or joined an existing one filtered by difficulty and quest title. Ship → Block → Lobby → Game. Four steps. Anyone could explain it in fifteen seconds. Anyone, twenty-six years later, can still explain it in fifteen seconds.

The Haul ports this hierarchy onto physical geography:

**Region → Lane → Lobby → Mission.**

- **Region** is the continental zone the driver operates in. The eleven Regions in v1.0 are PNW, Mountain West, Texas Triangle, South Central, Southeast, Atlantic, Northeast, Great Lakes, Midwest, California Central, and Cross-Border Corridor. Drivers either declare a home Region during onboarding or auto-lock to the Region the Pulse watch is currently inside.
- **Lane** is a corridor slice within a Region. I-10 EB El Paso → San Antonio is a Lane. I-80 WB Des Moines → North Platte is a Lane. Lanes are cultural slices the way PSO Blocks were — they self-sort, and the architecture surfaces the sorting.
- **Lobby** is the geofenced physical truck stop the driver is currently parked at. It is resolved in real time by the EusoTrip Network's reverse-geocode of the Pulse watch GPS fix. Sixteen avatar slots per lobby instance, identical to PSO. If a stop has more than sixteen opted-in drivers, the lobby shards into Lobby A / Lobby B / Lobby C with one-tap switching, identical to PSO's Block-shard logic on busy nights.
- **Mission** is the load. It is the actual load. It is dispatched from the same load board the driver already uses. The Haul layer reads the `load.completed` event from `loadLifecycle.ts` and credits the appropriate Mission, recognition, and standing.

The four-step legibility is preserved. A new Hauler can be told the entire spatial model in two sentences: "Pick the Region you run. The Lobby is the truck stop you're parked at. Missions are the loads you're already running." That sentence is the entire onboarding. It is the same sentence Pioneer 2 needed twenty-six years ago. The architecture is older than smartphones, and it still holds.

## Chapter 03 — Professional language doctrine — what The Haul calls things

The single most common failure mode in adjacent gamified-work systems — Uber's Quests, DoorDash's Challenges, Amazon Flex's Streaks, Trucker Path's Pro tier — is *juvenile copy*. The driver-facing strings in those systems are written by gaming teams, and the gaming-team voice leaks into the professional surface. The result is a working adult opening their app and seeing the word *level up*, the phrase *unlock the rare drop*, or the cheerful *"You crushed it!"* over a $14.50 settlement, and the working adult's trust collapses. The system stops being a tool and starts being a manipulation. The driver disengages.

The Haul does not make this mistake. The translation table below is binding on every UI string, every push notification, every voice line, and every email or SMS the driver receives from Eusoboards. Engineering teams shipping copy through the build pipeline will run the Forbidden Words filter (Appendix B); strings that fail the filter cannot ship.

**The translation table:**

| PSO / engineering term | The Haul professional vocabulary |
|---|---|
| Lobby | Lobby (kept — neutral, freight-resonant — see Chapter 20) |
| Quest / instance | **Mission** (kept — military, heavy-haul, escort use this word) |
| Party / group | **Crew** or **Convoy** |
| Block | **Block** (kept — radio dispatch term, freight-resonant) |
| XP | **Miles Earned** in driver copy; XP in code |
| Level / level up | **Standing** / **advanced to <Tier>** |
| Class | **Specialty** |
| Achievement | **Mark** or **Milestone** |
| Loot / drop | **Recognition** or **Earned** |
| Loot crate / box | **Recognition Crate** |
| Gacha | (forbidden, no replacement — we do not run gacha) |
| MAG / pet | **Companion** (the ESANG Companion — see Chapter 13) |
| Section ID | **Lane Color** |
| Photon drop / currency | **Standing Points** (cosmetic-bound, not cashable) |
| Prestige / reset | **Rebirth** (the Eight Lights — see Chapter 19) |
| Boss | **Surge Mission** |
| Rare drop | **Verified Recognition** |
| Player shop | **Marketplace** |
| Buff | **Bonus** or **Multiplier** |
| Grinding | (forbidden — replace with *running* or *hauling*) |
| Endgame | (forbidden — replace with *Master tier* or *Veteran lane*) |
| Play / game / fun / addictive | (forbidden) |
| HERE-listed weigh station | **EusoTrip Network weigh station** |
| HERE AD-capable zone | **Smart-Drive Lane** |
| HERE low-incident corridor | **Verified Safe Corridor** |
| HERE truck-safety score | **Driver Safety Index** |
| HERE Routing API | (never surfaced — internal) |

The translation is mechanical. The implementer pastes the table into the code-review checklist and rejects any pull request whose driver-facing strings match a left-column term. There is no negotiation; there is no "this one time we kept *level up* because the driver focus group liked it." The driver focus group did like it. The driver focus group is mistaken about what works in production for the next five years. PSO's longevity is the proof: the games that succeeded were the ones that took their players seriously.

## Chapter 04 — How The Haul lives INSIDE Eusoboards (not beside it)

The architecture decision that distinguishes The Haul from every other gamified-work product on the market is the *integration posture*. The Haul is not a separate app. The Haul is not a separate tab that runs a parallel state machine. The Haul does not have its own load list, its own trip lifecycle, its own POD flow. The Haul reads the actual Eusoboards work events and applies a recognition layer.

Concretely, the integration is event-driven and one-way (the work flow is authoritative, the Haul layer subscribes):

**Eusoboards emits — The Haul subscribes:**
- `load.accepted` (from `loadLifecycle.ts`) — Mission state moves AVAILABLE → ACCEPTED.
- `load.in_transit` — Mission state moves ACCEPTED → IN_PROGRESS, route polyline locked, geofence checkpoints armed.
- `load.checkpoint.geofence_entered` — Mission CHECKPOINT, partial XP credited, watch surface updates.
- `load.bol.signed` — Mission first-leg recognition (the BOL Stamp generation).
- `load.pod.signed` (from `loadLifecycle.ts`) — Mission state moves IN_PROGRESS → COMPLETED, drop roll fires.
- `load.settled` (from `factoring.ts` and `wallet.ts`) — Mission state moves COMPLETED → REWARDED, recognition crate is opened, fee discount applied at settlement, factoring tier re-evaluated.
- `load.dispute.opened` — Mission state moves to DISPUTED (frozen).
- `load.dispute.resolved` — Mission moves back to REWARDED (driver wins) or FAILED (driver loses).

This is the whole integration. There is no parallel mission state. There is no separate POD. There is no "are you sure you want to start the Mission?" flow that interrupts the load. The driver runs the load they already accepted. The Haul reads the events. The recognition appears.

The implementation pattern is a single subscriber service named `gamificationDispatcher` (already present in the codebase at `frontend/server/services/gamificationDispatcher.ts`, called as `fireGamificationEvent` from the `gamification` router). The dispatcher consumes the load-lifecycle events and emits gamification events through `emitGamificationEvent` (the WebSocket pipe defined in `frontend/server/_core/websocket.ts`). The client renders the recognition. The client never authors mission state — the client is a view over server-authoritative state.

The architectural payoff is enormous. It means The Haul never blocks a load. It means a load that runs without a driver opening the Haul tab still credits the driver's standing — the recognition is waiting in the next lobby visit. It means engineering can roll back the Haul independently of the load flow without breaking dispatch. It means safety can kill the Haul layer with a single feature flag (`haul.global.enabled = false` from `team_10_launch_governance.md`, Phase 0) and the underlying freight operation continues uninterrupted. It is the strongest possible separation of concerns between *recognition* and *work*, and it is the architecture that lets The Haul ship at scale without becoming a regulatory or operational liability.

---

# PART II — The Mission Grammar (ported from PSO quest grammar)

## Chapter 05 — Mission archetypes (12 templates)

The ten doctrine shards converged on twelve mission archetypes, the same number PSO's quest catalog distilled to once you collapsed the offline and online quest pools. Twelve is not arbitrary — it is the number of structural primitives a freight career produces if you classify by *shape of work*, not by *commodity carried*. Twelve archetypes cover ~98% of dispatched freight scenarios while remaining mechanically distinct in copy, in reward, and in cadence.

The twelve archetypes, with the ship-ready professional copy that engineering will paste into the catalog and the PSO referent so engineering knows what the spine is:

**1. RESCUE** — Recover a refused or rejected load. *Production card copy:* "Refusal Recovery — Reefer pickup re-routed at Phoenix DC. Driver dispatched to recover and re-deliver to backup consignee in El Paso." *PSO referent:* the rescue quest archetype (Lost Heat Sword, Tinkerer's Greed). *Mechanic:* detention split paid on top of base.

**2. EXPLORATION** — First-time shipper or first-time lane. *Production card copy:* "New Lane — Sysco DC, San Antonio → Sysco DC, Houston. First run for this Hauler on this corridor." *PSO referent:* area-map first-clear bonus. *Mechanic:* +50% Atlas-track contribution for the lifetime collection in Chapter 18.

**3. DEFENSE** — Escort hot freight (high-value, time-critical, regulated). *Production card copy:* "Verified High-Value Run — semiconductor wafers, $3.4M declared, white-glove delivery with continuous geofence perimeter check." *PSO referent:* the Defense quest line — Maximum Attack escort. *Mechanic:* perimeter geofence soft-alert on lateral deviation.

**4. SURGE** — Single high-rate ultra-rare load, weekly per region. *Production card copy:* "Texas Triangle Surge — wind blade, Pueblo CO → Amarillo TX, three pilot cars, +2.5× linehaul." *PSO referent:* the boss-room rare-spawn (Dragon, De Rol Le, Vol Opt, Dark Falz). *Mechanic:* visible only inside the geofenced zone (Chapter 25), atomic claim with five-minute confirmation, cooldown 168 hours per Hauler.

**5. SURVIVAL** — Long-haul OTR continuous run (>72 continuous hours, no break >11h). *Production card copy:* "Transcontinental — Long Beach to Charleston in five drive days. Single Hauler. Sustainable pace." *PSO referent:* the endurance quest — Towards the Future. *Mechanic:* fatigue gating (Chapter 54) is mandatory; the mission auto-pauses on fatigue score above 90.

**6. STEALTH** — Silent run (no dispatcher pings, no shipper check-in calls, no ELD nag). *Production card copy:* "Veteran Run — Knoxville → Mobile. We will not bother you. Drive." *PSO referent:* the lone-wolf quest design. *Mechanic:* Veteran-tier and above only; tests the "we don't bother veterans" promise.

**7. COLLECTION** — Multi-stop pickup (LTL or partials). *Production card copy:* "Reefer Collection — four pickups consolidating into one delivery at Sysco Houston DC." *PSO referent:* the fragment hunt. *Mechanic:* each stop awards a partial; mission completes only when full set is collected.

**8. RACE** — Dual-Hauler on same lane, larger purse to faster delivery. *Production card copy:* "Lane Sprint — Memphis to Birmingham. Two Haulers accepted. Larger payout to first delivery; both earn base." *PSO referent:* the head-to-head time-trial quest. *Mechanic:* free entry, no buy-in, no gambling adjacency. Cap two entries per Hauler per week.

**9. PUZZLE** — Cross-border multi-doc (US ↔ MX, US ↔ CA). *Production card copy:* "Border Run — Laredo southbound, Carta Porte Complemento 4.0, ACE manifest pre-filed, FAST lane 14:00 window." *PSO referent:* the lock-and-key quest. *Mechanic:* errors cost time, not money; Bilingual Pedimento card auto-displays in-cab (see Chapter 28).

**10. CO-OP** — Convoy escort (2–6 Haulers as Crew). *Production card copy:* "Crew Run — oversize wind blade, Convoy of three with two pilot cars. Shared comms. Veteran lead." *PSO referent:* the four-player party quest. *Mechanic:* shared mission state, shared chat thread, shared recognition.

**11. ARENA** — Closed-yard precision (timed, scored, no public-road risk). *Production card copy:* "Yard Drill — alley dock 53'er, blind side, scored." *PSO referent:* the challenge mode. *Mechanic:* the only archetype with no real freight; a leaderboard-only training surface that pays cosmetics and Driver Safety Index credit, not load pay.

**12. DAILY** — Rotating quick missions (24-hour rotation). *Production card copy:* "Pre-Trip Verified — DVIR with photo evidence before 06:00, +75 Standing Points." *PSO referent:* the daily login quest. *Mechanic:* short, low-friction, satisfies the engagement loop without manufacturing freight pressure.

Each archetype has an XP multiplier, a cash multiplier, and a cooldown structure that the next chapter ratifies. Engineering should treat the twelve archetypes as a static enum (`MissionArchetype`) seeded into the `missions.type` and `missions.category` columns already present in the database.

## Chapter 06 — Difficulty tiers — Standard / Pro / Veteran / Master

PSO codified four difficulty tiers — *Normal*, *Hard*, *Very Hard*, *Ultimate* — and the tiers were both the new-player ramp and the veteran retention engine. The same encounter at a different tier was a different experience: the boss had four times the HP, dropped a different rare item, and required a different group composition. PSO's tier ladder is the cleanest precedent in twenty-six years of online RPG design.

The Haul inherits the four-tier ladder and renames it for professional resonance. *Normal* becomes **Standard**. *Hard* becomes **Pro**. *Very Hard* becomes **Veteran**. *Ultimate* becomes **Master**. The names are clean, freight-resonant, and never juvenile. An owner-operator with twelve years on the road will wear a Master tier badge on their profile in the lobby; that owner-operator will not wear an *Ultimate* badge, because *Ultimate* sounds like the protein shake at a gas station.

The four tiers, with their gating, multipliers, and XP yield (the canonical reconciled numbers, harmonized across all ten shards):

| Tier | Rate Multiplier | Window | Conditions | Endorsement Gate | XP Base |
|---|---|---|---|---|---|
| **Standard** | 1.00× | Pickup +24h, Delivery +48h | Daylight, fair weather, single-state or low-complexity interstate | None — CDL-A only | 100 |
| **Pro** | 1.15× | Pickup +12h, Delivery +24h | Mixed daylight/dusk, light precip OK | 1 endorsement OR 90 days clean MVR | 175 |
| **Veteran** | 1.35× | Pickup +8h, Delivery +18h | Night drive 22:00–05:00, adverse weather, mountain grades >6% | 2 endorsements + 1 year clean MVR + Hauler Pro Class | 280 |
| **Master** | 1.60× + bonus | Pickup +4h, Delivery +12h | Hazmat / high-value (>$250K) / cross-border / oversize | Hazmat + TWIC + 2yr clean MVR + 250 Veteran completions | 450 |

The rate multipliers are anchored to DAT regional median for the lane–equipment–week tuple, queried at mission-vend time so the multiplier is always relative to current market reality. The XP base rolls into the canonical Standing curve in Chapter 17.

The endorsement gate is hard, not soft. A driver without TWIC cannot accept Master tier even if every other condition is met. The reason is regulatory and operational: Master tier missions carry hazmat exposure, cross-border friction, and high-value cargo, and a driver who is not licensed for the work creates real liability for the platform. The system surfaces exactly which gate is blocking advancement (`classTierPendingReason` in the `driverCharacter` schema addition), so a driver who is grinding toward Master sees, in plain English, "Hazmat endorsement not on file" or "MVR clean window 47 days short of 24-month requirement." There is no opacity. PSO's Ultimate tier was famous for being opaque about its unlock conditions; The Haul's Master tier is the opposite — every gate is published, every distance to the gate is visible, every recovery path from a slipped gate is documented.

The drop tables scale by tier, with the Master tier introducing a Mythic class that does not exist at any other tier — the freight equivalent of PSO's S-rank weapons. The drop probabilities are reconciled in Chapter 10.

## Chapter 07 — Mission state machine — AVAILABLE→ACCEPTED→...→REWARDED

Every mission in The Haul is a finite state machine with eight live states and three terminal branches. The state machine is canonical because it is the contract between the Haul layer and Eusoboards' load lifecycle — the Haul layer's state transitions are driven entirely by the load's state transitions, and engineering must enforce the binding strictly. A Haul state cannot advance without the corresponding load event firing.

The eight live states:

```
                                    ┌───────────┐
                                    │ AVAILABLE │  ← vended by Mission Board (NPC or surge)
                                    └─────┬─────┘
                              accept       │
                                           ▼
                                    ┌───────────┐
                                    │ ACCEPTED  │  ← load.accepted fired
                                    └─────┬─────┘
                              start        │       abandon
                                           ▼          └─────────────┐
                                    ┌──────────────┐                 ▼
                                    │ IN_PROGRESS  │           ┌──────────┐
                                    └──┬────────┬──┘           │ ABANDONED│
                            checkpoint │        │ HOS violation└──────────┘
                                       ▼        ▼ or timeout
                                 ┌──────────┐  ┌────────┐
                                 │CHECKPOINT│  │ FAILED │
                                 └────┬─────┘  └────────┘
                                       │
                              POD signed
                                       ▼
                                    ┌───────────┐
                                    │ COMPLETED │  ← load.pod.signed fired; drops roll here
                                    └─────┬─────┘
                              dispute      │
                                           ▼
                                    ┌───────────┐    settle to wallet
                                    │ REWARDED  │  ────────────────────► CLOSED
                                    └───────────┘
                                       │
                                       └─── disputed → DISPUTED (frozen)
```

The state machine is implemented in the existing `gamification.ts` router via the procedures listed below. Each procedure name is a literal grep-able identifier in the source tree, present at the line numbers shown:

- `gamificationRouter.create` (line 71) — bookkeeping for new reward events.
- `gamificationRouter.getMissions` (line 679) — returns AVAILABLE missions filtered by `type` and `category`.
- `gamificationRouter.startMission` (line 810) — ACCEPTED → IN_PROGRESS.
- `gamificationRouter.claimMissionReward` (line 880) — COMPLETED → REWARDED.
- `gamificationRouter.cancelMission` (line 1001) — ACCEPTED → ABANDONED.
- `gamificationRouter.getActiveTripMissions` (line 1666) — IN_PROGRESS lookup for the watch surface.
- `gamificationRouter.refreshMissions` (line 1678) — admin-vended Mission Board rotation.

The procedures `checkpointMission`, `failMission`, and `disputeMission` do not yet exist in the router as of this writing; they are flagged in Appendix F as engineering work for Sprint 2. The work is straightforward — each is a server-driven state transition keyed to a load-lifecycle event from `loadLifecycle.ts`.

The XP grant schedule across the state transitions is incremental, not all-at-once, so that a FAILED mission still credits the partial effort rather than punishing rage-quit:

```
state_xp = {
  ACCEPTED:    0,                            // anti-spam; no XP for accepting alone
  IN_PROGRESS: base_xp * 0.05,               // small "you started" credit
  CHECKPOINT:  base_xp * 0.10 per checkpoint,// capped at 0.40 across all checkpoints
  COMPLETED:   base_xp * 0.50,
  REWARDED:    base_xp * remainder + bonuses // formula in Chapter 17
}
```

Total XP at REWARDED equals the canonical formula in Chapter 17. The incremental schedule is the doctrine — partial credit for partial work — and it is the single most positive driver-experience choice in the state machine. Drivers who get into a snowstorm and have to abort still keep what they earned to that point. The system is patient.

## Chapter 08 — Mission discovery and the Mission Board UI (Pioneer 2 quest counter parity)

PSO's Pioneer 2 quest counter was a single NPC at a podium. You walked up. You read flavor text. You saw a one-line difficulty rating and a one-line reward. You pressed accept. The friction was deliberate: every quest felt like a contract entered into with a person, not a row in a database. The Haul replicates this in the Lobby's *Mission Board* — an experience designed to make a driver feel they are *taking work*, not *picking from a list*.

The Mission Board surfaces four NPC archetypes, each with a domain, a refresh cooldown, an inventory size, and a voice. The NPCs are not whimsical — they are professional personae that resonate with the freight world's actual operations vocabulary, designed and reviewed by the brand voice team:

**Vega — Dispatch Officer.** Vends RESCUE, EXPLORATION, DEFENSE, SURVIVAL, RACE missions. Avatar gradient indigo-to-cyan, headset visible, ops-room background. Voice line on first daily visit: "Got three lanes I think you'll like. Take a look." Refresh cooldown 4 hours. Inventory size 8 visible, 24-mission backing pool.

**Ridge — Quartermaster.** Vends DAILY and ARENA missions (the maintenance and training surface). Avatar gradient olive-to-amber, weathered, parts-counter background. Voice line: "DEF tank low? PM due? Knock these out, they pay." Refresh cooldown 24 hours. Inventory size 4 visible, 12-mission pool.

**Marcellus — Recruiter.** Vends CO-OP and referral missions (the social surface). Avatar gradient violet-to-rose, suit, lobby background. Voice line: "Bring me a friend. We both win. They both win." Refresh cooldown 7 days. Inventory size 2 visible, 6-mission pool.

**Captain Okafor — Haulmaster.** Vends SURGE, STEALTH, and PUZZLE missions (the prestige surface). Avatar gradient crimson-to-gold, captain's bars, command-deck background. Voice line: "If you're standing here, you're ready. Show me you are." Refresh cooldown weekly for SURGE, seasonal for special events. Inventory size 1 SURGE + 1 seasonal, 4-mission pool.

The voice lines are kept tightly in the freight register — no theatrics, no hype, no "Welcome adventurer!" The driver opens the Mission Board, sees the four NPCs in a vertical list with a portrait and a one-line teaser, taps the one whose archetype matches the work they want, and reviews the mission preview card.

The mission preview card is non-negotiably transparent. Every drop pool, every probability, every requirement is visible **before** the driver commits any action:

```
┌─────────────────────────────────────────────────┐
│  PHOENIX → EL PASO — Refused Reefer Recovery   │
│  Pro Tier · Rescue · Reefer endorsement         │
├─────────────────────────────────────────────────┤
│  Pickup window:   12 hours                      │
│  Delivery window: 24 hours                      │
│  Linehaul:        $2,400                        │
│  Bonus tier:      Pro (1.15×)                  │
│  Standing:        ~ 322 Miles Earned            │
├─────────────────────────────────────────────────┤
│  Recognition Crate (rolls on POD):              │
│    Common      1 of 8     Bronze frame variant  │
│    Uncommon    1 of 32    Refusal Recovery mark │
│    Rare        1 of 256   Phoenix Sunset orb    │
│    Verified    1 of 2048  Highway Saint wrap    │
├─────────────────────────────────────────────────┤
│  Requirements: Reefer endorsement · 90 days     │
│                clean MVR                        │
└─────────────────────────────────────────────────┘
                    [ ACCEPT ]
```

The drop preview is mandatory. It is both a regulatory firewall (Belgium, Netherlands, the UK Gambling Commission, the Australian Senate inquiry of 2018 — all turn on the question of *informed-action loot mechanics*; we publish all rates and the recognition is earned by work, never purchased) and a cultural choice (drivers are professionals; they negotiate rates with brokers all day; they will not accept a mission whose recognition floor is hidden).

## Chapter 09 — How a real Eusoboards load BECOMES a Mission (the integration model)

This chapter is the linchpin of the entire doctrine, because the architectural decision documented here is the difference between *The Haul as a layer* and *The Haul as a parallel app*. We chose layer. The chapter shows how.

A load is born inside Eusoboards in the canonical lifecycle (`loadLifecycle.ts` in the codebase): a shipper or broker posts a load → it appears on the load board → a driver searches and accepts → the load enters the in-transit lifecycle → the BOL is signed at pickup → checkpoints fire as the truck moves → the POD is signed at delivery → the invoice is factored through HaulPay → the wallet is credited. This entire flow exists today, in production, in `frontend/server/routers/loadBoard.ts`, `loads.ts`, `loadLifecycle.ts`, `factoring.ts`, and `wallet.ts`. The Haul does not replace any of it.

What The Haul does, instead, is *enrich the load with a mission shape* at the moment the load is posted, and then *credit the driver's standing* at every state transition. The enrichment is a server-side decoration. The driver never sees a "load + mission" duplicate — they see one card on their load board, decorated with the Mission tier, the archetype, the recognition crate preview, and the standing yield.

The enrichment pipeline:

1. **At load posting.** When the load is created in `loads.ts`, a hook calls `gamificationRouter.refreshMissions` (line 1678) which classifies the load against the twelve archetypes (Chapter 5) and the four tiers (Chapter 6), generates the recognition crate snapshot (Chapter 10), and writes a row to the `missions` table with `type`, `category`, `targetType`, `targetValue`, `xpReward`, `rewardData`, and the foreign key back to the underlying load. The load is now a Mission as well. From the driver's perspective, the load board *is* the Mission Board.

2. **At driver acceptance.** When the driver accepts the load via `loads.ts` accept procedure, the Eusoboards lifecycle fires `load.accepted`. The `gamificationDispatcher` subscribes to this event and calls `gamificationRouter.startMission` (line 810) which writes a row to `mission_progress` with `status = 'in_progress'`, `userId`, `missionId`, and the initial `currentProgress` of zero.

3. **At each checkpoint.** The geofence enter/exit events from `loadLifecycle.ts` fire `load.checkpoint.geofence_entered` events. The dispatcher updates `mission_progress.currentProgress` proportionally (e.g., 25% on pickup geofence, 25% on each major checkpoint, 100% on delivery geofence) and emits a `gamification.event.checkpoint` over the WebSocket so the watch surface and lobby UI can show the progress bar.

4. **At BOL signing.** The `load.bol.signed` event fires the BOL Stamp generator (Chapter 21), which composes the share-card from the load metadata and the driver's profile, server-signs it against the ledger entry, and posts it to the driver's lobby if the driver has the lobby-share toggle enabled.

5. **At POD signing.** The `load.pod.signed` event is the recognition trigger. The dispatcher calls `gamificationRouter.claimMissionReward` (line 880), which transitions the mission to COMPLETED, rolls the recognition crate against the published drop table, applies pity-timer logic (Chapter 10), and writes a row to the `loot_crates` table — but with the contents not yet revealed to the client. The reveal animation fires when the driver next opens the Haul tab, preserving the post-mission ceremony.

6. **At settlement.** The `load.settled` event from `factoring.ts` and `wallet.ts` triggers the fee discount (Chapter 11) and re-evaluates the factoring tier (Chapter 11). The reduced fee is applied at the moment of settlement, which means a driver at Master Class actually pays the lower fee on the very next invoice, with no manual claim required.

This is the entire integration. Six events, one dispatcher, one router. The Haul is a recognition layer over the work. It is not a parallel work surface. It is the architecture that lets us ship at scale without becoming a regulatory liability and without ever interrupting the actual freight operation.

The downstream consequence: when the doctrine says "the driver accepts a Mission" or "the Mission completes," engineering should mentally substitute "the driver accepts a load" and "the load delivers." The two are the same event from the system's point of view — only the recognition layer is named differently.

---

# PART III — The Reward Economy (PSO drops, professionally restated)

## Chapter 10 — Cosmetic recognition tiers (no gambling, transparent tables)

The recognition economy is six tiers wide, color-coded against the Eusoboards brand gradient. Tier names are deliberately legible to a driver who has never picked up a controller, and resonant for the driver who put four thousand hours into Phantasy Star Online. Either driver instantly understands what they are looking at: a public, deterministic, ratio-disclosed reward shape that pays in cosmetics earned by real work.

The six tiers (the canonical reconciled probabilities):

| Tier | Color treatment | Drop weight per Mission | Notes |
|---|---|---|---|
| **Common** | White, flat fill | 60.000% | No animation; first-line recognition |
| **Uncommon** | Highway-green | 28.000% | Subtle pulse on the recognition card |
| **Rare** | DOT-blue | 9.000% | Slow sheen left-to-right |
| **Epic** | Brand gradient (purple→magenta) | 2.500% | Animated brand-gradient edge |
| **Legendary** | Brand gradient + iridescent overlay | 0.495% | Iridescent shimmer + heat-haze ripple |
| **Mythic** | One-of-N global, founder-signature variant | 0.005% | Holographic, animated founder watermark |

The drop weights sum to 100.000%. They are published in the app under Settings → Recognition → Drop Rate Disclosure, and the published table is the source of truth — not marketing copy, not patch notes, not the brand team's preference of the week. Any change to a weight requires a 30-day driver-facing changelog notice. This is what makes The Haul non-gambling under the Belgian Gaming Act (2018), the Dutch Kansspelautoriteit ruling, the UK DCMS 2023 response, and the Australian eSafety / ACMA framework: the driver has full information *before* the action, the recognition is earned by real labor (a delivered load), the recognition is never purchasable for cash or for a virtual currency that is purchasable for cash, and the recognition itself cannot be cashed out.

The tier-by-tier-by-archetype matrix yields the per-Mission drop table that surfaces in the preview card (Chapter 8). The Master tier introduces a seventh, never-public probability — the **Mythic** rate of 0.005%, which corresponds to PSO's S-rank weapons and is the freight equivalent of a Heaven Striker. Mythic items are one-of-N globally — fifty Founder-signature Companion orbs ever exist, twenty-five Founder-signature truck-wraps, ten personally-signed BOL stamps. They are explicitly soulbound (Chapter 14) and they are never tradeable.

The pity-timer system, borrowed from Genshin Impact's "soft pity" and Diablo III's "bad luck protection," is the second guard rail. After N consecutive completions at a tier without a Rare-or-better recognition, the next completion is guaranteed to roll at least at that rarity level. The pity counter is per-tier, per-driver, per-rarity-class, and resets on a hit. The reconciled thresholds:

```
pity_threshold = {
  Standard: { rare: 100, legendary: 600 },
  Pro:      { rare: 80,  legendary: 480 },
  Veteran:  { rare: 60,  legendary: 320 },
  Master:   { rare: 40,  legendary: 200, mythic: 2000 }
}
```

The pity state is exposed to the driver under Settings → Recognition → My Streaks. PSO never showed players their bad-luck-protection state; The Haul does. The driver should be able to see exactly how close they are to a guaranteed recognition. Opacity is a casino move; we are not a casino.

The cosmetic families are seven: Orb Skins (the visual shell of the ESANG Companion in Chapter 13), Profile Frames (border around the avatar in lobby, leaderboards, dispatch), Truck-Wrap Textures (3D rig skin in the lobby — never on the real truck), BOL Stamp Graphics (the decorative seal on the share-card), Title Cards (the suffix that appears under the driver handle), Lobby Emotes (the 3D avatar animations), and Companion Voice Packs (the audible persona of the ESANG companion). Not every family rolls every tier — some are inherently rare-or-better.

Engineering mapping: the families are an enum on the `cosmetic_items.family` column to be added to the schema (Appendix F). The drop weights are basis points on `cosmetic_items.drop_weight_bp` (60000 = 60.000%). The pity state lives on a new `pity_state` table indexed by `(driver_id, tier, rarity_class)`. The `loot_crates` and `reward_crates` tables (already present in the database — see the table dump in Appendix F) are the existing infrastructure that the drop-event ledger writes against.

## Chapter 11 — Functional rewards: Standing, fee discounts, factoring tier-ups

Cosmetics are dopamine. Functional rewards are *real money in the driver's pocket*. The Haul stacks two financial layers on top of the cosmetic recognition layer, both deterministic, both audited, both compounding on a calendar.

**Standing (the renamed XP system, 1–100).** Every completed mission grants base Miles Earned (the driver-facing name for XP) plus modifiers. The reconciled grant schedule:

| Source | Miles Earned |
|---|---|
| Mission completion (base) | varies by tier (100 / 175 / 280 / 450) |
| On-time delivery (within 30 minutes of ETA) | +25 |
| Clean BOL (no exception) | +25 |
| Hazmat endorsement used | +15 |
| Tanker endorsement used | +15 |
| Cross-border (US-MX or US-CA) | +50 |
| Long haul (>500 miles) | +30 |
| Night-shift completion (00:00–05:00 local) | +15 |
| Detention <30 min (clean dock turn) | +10 |
| Streak day (consecutive day with at least one mission) | +5/day, capped at +50 |

The Standing curve is gentle quadratic, calibrated so a steady driver completing four to six loads per week with average bonus modifiers reaches Standing 100 in roughly 18 to 22 months — the same calendar window in which they cross the Hauler Pro to Hauler Master class gate (Chapter 15). The two systems are deliberately phase-locked so that the average sustainable driver hits Level 100 and Master Class within a few months of each other, producing a satisfying double-promotion moment.

The canonical curve formula:
```
xp_required(level n) = 500 * n + 50 * n^2
```
Level 2 = 600 XP. Level 10 = 10,000 XP. Level 50 = 150,000 XP. Level 100 = 550,000 XP. Total ~10 million Miles Earned to reach 100.

**Fee discount ladder (HaulPay platform fee).** The platform fee is the cut HaulPay takes when factoring an invoice or facilitating a load match. Standard is 1.0%. Each ten Standing levels takes off 0.05 percentage points:

| Standing | Platform fee |
|---|---|
| 1–9 | 1.00% |
| 10–19 | 0.95% |
| 20–29 | 0.90% |
| 30–39 | 0.85% |
| 40–49 | 0.80% |
| 50–59 | 0.75% |
| 60–69 | 0.70% |
| 70–79 | 0.65% |
| 80–89 | 0.60% |
| 90–99 | 0.55% |
| 100 | 0.50% |

A Hauler invoicing $250,000/year saves $1,250/year between Standard and Standing 100. Not life-changing, but durable, and it stacks with the factoring tier-up below. Lifetime savings across the L1-to-L100 climb is approximately $3,500 cumulative plus $1,000+/yr in perpetuity.

**Factoring tier-ups (the real financial benefit).** The HaulPay account itself moves through four tiers. These are the real money:

| Factoring tier | Fee | Unlock requirement |
|---|---|---|
| Standard | 3.00% | Default at signup, post-KYC |
| Pro | 2.50% | Standing 25 + 50 successful invoices factored + zero chargebacks 90 days |
| Elite | 2.00% | Standing 50 + 200 successful invoices + zero chargebacks 180 days + clean DOT/MC |
| Black | 1.50% | Standing 75 + 500 successful invoices + zero chargebacks 365 days + invitation by HaulPay risk team |

A driver factoring $500K/year at Black tier saves $7,500/year vs. Standard. That is real, durable, compounding savings. It is the functional reward the Haul layer pays back for sustainable, professional operation.

Engineering mapping: the Standing level is the `gamification_profiles.level` column (already present, see the table dump). The fee discount is computed at settlement time inside `factoring.ts` via a lookup against `gamification_profiles.level`. The factoring tier is a new column `factoring_tier` to be added to the user/driver model (Appendix F), driven by the `tier_locked_until` clause to prevent thrash on a single bad event. The fee ladder is published to drivers under Settings → Standing → Fee Schedule, alongside the lifetime savings tracker.

## Chapter 12 — Cash bonuses — streak, referral, milestone (HaulPay rails)

Cash flows alongside the cosmetic recognition layer through three deterministic, never-randomized rails: streaks, referrals, and milestones. None of the three is gacha-adjacent. Every cash reward is earned by a clearly defined, pre-published action.

**Streak rewards.** A streak day is any UTC-offset-anchored 24-hour window in which the driver completes at least one mission OR declares a rest day in advance:

| Streak length | Cash bonus |
|---|---|
| 7 consecutive days | $50 |
| 14 consecutive days | $100 |
| 30 consecutive days | $250 |
| 60 consecutive days | $500 |
| 90 consecutive days | $1,000 |
| 180 consecutive days | $3,000 |
| 365 consecutive days | $10,000 + Founder-signed truck plaque (physical) |

Streak rewards are cumulative — a 365-day streak collects all seven payouts in order, totaling $14,300 plus the plaque. Streaks reset on a missed day, but with a one-time-per-quarter humane freeze (illness, breakdown, family emergency, weather closure). The freeze is granted on driver attestation, no proof required. Trust & Safety only audits if the freeze is invoked more than three times in twelve months.

The freeze is the de-coercion mechanism. A streak system without a humane reset *is* the gambling-adjacent variable-reinforcement schedule we are explicitly engineering against. The driver-psychology research literature is unambiguous on this point: streaks without escape become coercive. The Haul ships streaks with an off-ramp because the driver is a working adult, not a slot machine player.

Engineering: `streak_state` is a new table (Appendix F) with `(driver_id, current_streak_days, last_qualifying_day, freezes_used_quarter, freezes_used_year, longest_streak_ever)`. Cash payouts post to the existing `cash_rewards` ledger line via HaulPay's Stripe Connect integration. Tax form: 1099-MISC, Box 3 (Other Income) — the same classification used by airline frequent-flyer cash-out programs. This routing is critical because it preserves the driver's contractor classification — a stream of "performance bonuses" tied tightly to work product can drift into 1099-NEC territory and start to look like wages.

**Referral rewards.** Single-tier, flat, verified-outcome:

| Referral type | Payout | Trigger |
|---|---|---|
| Driver | $500 | Referred driver signs + completes 10 loads + 90 days clean MVR |
| Owner-Operator | $500 | Same |
| Mid-Carrier (3–9 trucks) | $2,000 | Onboards + 3 trucks dispatch + 90 days clean |
| Carrier (10+ trucks) | $5,000 | Onboards + 5 trucks dispatch + 90 days clean |
| Broker | $1,000 | Posts and clears 25 loads + 90 days no payment disputes |
| Shipper (direct) | $1,500 | Tenders 20 loads + 90 days no disputes |

Multi-tier referrals are explicitly forbidden — paying on the recruits-of-your-recruits creates pyramid-scheme classification risk under FTC guidance (FTC v. BurnLounge, Koscot Interplanetary). The Haul stays single-tier. Cap is 24 referrals/year/driver to prevent farming.

Clawback: 50% if the referred party churns within 6 months; 100% if suspended for fraud within 12 months. Tax form: 1099-MISC, Box 3.

**Milestone bonuses.** The renamed mission-completion bonus stack from `team_07_driver_money.md` Agent 31. Each is deterministic: completing a Hazmat Master mission with zero violations and on-time delivery pays a flat $500 bonus on top of linehaul. Cross-border bilingual run pays $250. Storm-routed critical run pays $600. First-of-month pays $100. The full table — seventeen archetype-specific bonuses, floor $25, ceiling $5,000 per single mission — lives in the catalog seeded into the `missions.rewardData` JSON column. Tax form: 1099-NEC, Box 1 (nonemployee compensation), aggregated with the driver's load pay.

The wellness floor across all three rails is mandatory and absolute: **no cash bonus releases if the driver violated HOS during the qualifying activity, or if the qualifying activity would have required HOS violation to complete.** This is not a guideline; it is a hardcoded invariant in the bonus-issuance pipeline. A bonus that would reward unsafe behavior is forfeited, not reduced. The driver retains the underlying load pay; the bonus is gone. Diego signed off on this floor personally. It is not negotiable.

## Chapter 13 — The ESANG Companion (PSO MAG → driver AI companion)

PSO's MAG was a tiny floating pet-AI that grew based on what you fed it. You carried it into every mission, every battle, every Photon Drop run for hundreds of hours, and it evolved into a form unique to your play style. The MAG was the most personal object in the game because it was *yours alone* — no other player's MAG looked or behaved exactly like yours. Twenty-six years later, MAG screenshots are still the most-shared social artifact in the PSO private-server community.

The ESANG Companion is the answer to that brief, transposed onto trucking. Every Hauler gets one ESANG Companion at HaulPay onboarding, post-KYC. It is a voice-and-visual entity bound to the driver's account, visible as an orb in the lobby and audible as the dispatch voice in the cab. It evolves with the driver across the lifetime of the account. The name *ESANG* is the codename for the Eusoboards brand voice palette (magenta, green, amber, danger red, listening blue) and the voice assistant surface — the Companion is the named persona of that surface.

The feeding mechanic: each completed Mission "feeds" the Companion an amount equal to the Miles Earned awarded. The Companion has its own level (1–500, far higher cap than driver Standing), and visual stages evolve every 25 levels:

| Companion Level | Visual stage | Vibe |
|---|---|---|
| 1–24 | Stage 0 — basic floating orb | Blank slate, slowly pulsing |
| 25–49 | Stage 1 — orb with internal core texture | First identity emerging |
| 50–99 | Stage 2 — drone (small wings, lights) | Companion form |
| 100–199 | Stage 3 — mech-orb (mechanical limbs, articulated) | Working companion |
| 200–299 | Stage 4 — liquid metal sphere | Mature, fluid |
| 300–399 | Stage 5 — constellation (dispersed point-cloud) | Transcendent |
| 400–499 | Stage 6 — constellation with internal weather | Living constellation |
| 500 | Stage 7 — Founder-signature evolution (one-of-50) | Mythic culmination |

The branching evolution — the PSO MAG echo — is determined by the Hauler's *diet of mission archetypes*. The Companion's form depends not just on level but on the percentage breakdown of missions across categories over the rolling 90-day feeding window:

| Dominant feeding (>40%) | Persona | Visual signature | Voice characteristic |
|---|---|---|---|
| Hazmat | Companion Hazmat | Amber-warning core glow, hazard-diamond accents | Steady, careful, precise |
| Tanker | Companion Tanker | Liquid-mercury internal flow, slosh-physics animation | Calm, low-frequency baritone |
| Reefer | Companion Reefer | Frost crystal patterning, breath-fog aura | Crisp, alert |
| Flatbed | Companion Flatbed | Steel-rebar internal lattice, strap-tension visualizers | Gruff, rigging-vocabulary heavy |
| Cross-border | Companion Frontera | Bilingual EN/ES voice, dual-flag accent on form | Code-switching naturally |
| Long-haul | Companion Solo | Aurora-trail particle effect, distant constellation | Quiet, philosophical |
| Auto-hauler | Companion Carrier | Multi-deck mechanical lattice, vehicle silhouettes | Methodical, checklist-oriented |
| Generalist (no >40%) | Companion Wanderer | Shifting form, no fixed lattice | Adaptive, draws from all packs |

Switching personas is not free — once the Companion has spent 90 days on a dominant diet, it locks the persona for at least 30 days even if the diet shifts. This prevents whiplash and respects the *commitment* a persona represents. The persona is the Hauler's career biography rendered as a glowing orb.

Engineering: the new tables `esang_companion` and `esang_feeding_history` (Appendix F) track per-driver state. The 90-day persona window is computed by aggregating `esang_feeding_history` — which means a regulator (or a curious driver) can audit exactly *why* their Companion took the form it did. Existing DB has `esang_memories` already (the AI's narrative memory store with embeddings, dimensions, and source-conversation links — see the table dump). The feeding history extends that.

The voice cloning consent: any voice pack derived from a real person (the founder's voice, celebrity guests) is licensed via a written voice-likeness agreement on file with Eusorone Legal, with clear scope ("voice pack for ESANG Companion within The Haul platform only, perpetual, royalty per driver activation"). No deepfake risk — the voice is delivered only through the Companion interface and never generated on demand for arbitrary text in a private individual's voice.

The driver psychological hook: three years in, sitting in a truck stop comparing Companions with another driver, and seeing that the other Hauler's Companion Tanker has a slightly different liquid-mercury flow, a different voice cadence, a different constellation pattern at stage 5 because their diet has been 60% tanker / 40% reefer instead of 80% tanker / 20% flatbed. *That* is the PSO MAG moment. That is the moment the driver realizes they have been raising this entity for three years and cannot replicate it on any other platform. That is the lock-in.

## Chapter 14 — Trading, marketplace, anti-laundering rules

The cosmetic-to-cosmetic trading economy is enabled but heavily scoped. PSO's Trade Window collapsed under item duplication and laundering on Sega's official servers, and the lesson is unambiguous: *a peer economy is culturally indispensable but must be engineered against fraud from day zero*. The Haul ships those guard rails as code, not as policy.

The five binding rules:

1. **Cosmetic for cosmetic only.** The trade UI does not even render a cash field. No cash component, no HaulPay-wallet-to-HaulPay-wallet transfer with the cosmetic.
2. **KYC'd accounts only.** Both sides must have completed HaulPay KYC. No anonymous wallet-to-wallet movement.
3. **Both sides in the same lobby.** No remote trades. The driver must be physically/virtually in a Lobby with the counterparty's avatar present. The friction is by design.
4. **24-hour escrow on first trade between two accounts.** The cosmetics enter a 24-hour cancelable window; either side can pull out. This prevents impulse-regret and gives the anti-laundering system a window to flag.
5. **Mythic-tier items are non-tradable.** The one-of-50 Founder-signature Companion orb stays with the Hauler who earned it. Mythics are soulbound on grant.

The marketplace — the renamed *Glass-Case Showcase* from `team_02_PSO_lobby_to_haul_lobby.md` — extends the cosmetic-to-cosmetic system with a paid services layer: ride-along day auctions, training session listings, route walkthrough videos, regulatory cheat sheets, consultation calls, coaching subscriptions, custom lane reports. Each listing requires Standing 25 minimum and a verified expertise tag. Listings are content-moderated before going live. EusoTrip takes 15% platform fee; the Hauler keeps 85%. Tax form: 1099-K (Stripe-issued).

The anti-laundering detection rule:

```
auto_flag IF
  item.tier IN (legendary, mythic) AND
  COUNT(DISTINCT owning_driver_id) OVER (item, 30 day window) >= 3
```

A legendary or mythic item that moves through three or more distinct accounts in a 30-day window is auto-frozen. Trust & Safety reviews within 72 hours. False-positive rate target: <0.5%. If laundering is confirmed, the item is destroyed (no value transfer), and all involved accounts lose Surge mission access for 60 days. Repeat offense: permanent ban from cash rewards and cosmetic reset.

Carrier-sponsored cosmetic packs are permitted with strict constraints: the carrier pays Eusoboards per-driver-per-pack, the cosmetic is granted to the driver deterministically (no randomization, so this is B2B SaaS revenue not loot-box revenue), and **the cosmetic is bound to the driver's KYC, not the carrier**. Carriers cannot revoke a cosmetic after grant. This is a deliberate worker-protection design. If the driver leaves the carrier, the cosmetic stays with the driver.

Engineering: `cosmetic_inventory`, `cosmetic_trades`, and `carrier_cosmetic_sponsorships` are new tables (Appendix F). The trade flow is implemented atop the existing `gamification.purchaseItem` (line 1634) and `gamification.getInventory` (line 1693) procedures, with a new `gamification.proposeTrade` and `gamification.confirmTrade` pair to be added.

---

# PART IV — Progression & Identity

## Chapter 15 — The four standings — Rookie / Pro / Veteran / Legend

PSO's class triad — Hunter, Ranger, Force — gave the player a baseline silhouette before any other choice was made. The Haul's progression is structurally different but visually identical in legibility: the four Standings are a *vertical career arc*, not a parallel choice. A Hauler does not "pick" Master at character creation; they earn it through years of clean operation. The four standings mirror the journeyman model the trucking industry has used informally since the Motor Carrier Act of 1980.

**Rookie (Hauler).** Tenure: 0 to 6 months from CDL issuance, OR fewer than 50,000 verified platform miles. Mission access: Standard tier only. The XP curve is intentionally generous — a rookie can hit Standing 30 in their first six weeks. **Rookie protection** activates for the first 30 calendar days after first verified delivery: +25% Miles Earned modifier, immunity from public scorecard ranking (their score is calculated but not displayed), Mentor Match queue access. Rookie protection prevents the cliff-edge experience where a new driver is matched into a lobby of veteran haulers, gets compared unfavorably, and quits within a week.

**Pro (Hauler Pro).** Tenure: 6 months to 2 years, OR 50,001 to 250,000 verified miles. **Specialty branches unlock here** (Chapter 16). A Pro can run Standard and Pro tier missions. The driver can begin to declare a primary specialty, which biases their mission feed and unlocks specialty-flavored cosmetics. The XP curve at this tier flattens — the cubic component starts to bite.

**Veteran (Hauler Master).** Tenure: 2 to 10 years, OR 250,001 to 1,000,000 verified miles. Veteran unlocks all difficulty tiers including Master tier. Veterans carry a silver-bordered avatar frame. Veteran is the working tier — most experienced Haulers settle here for years.

**Legend (Hauler Legend).** Tenure: 10+ years, AND 1,000,000+ verified miles, AND clean MVR (no preventable accidents, no DOT-recordable injuries, no out-of-service violations) for the most recent 36-month rolling window. Projected steady-state Legend population: 2.5 to 4 percent of the active driver base. Legends receive exclusive Master-tier mission subset, gold-and-onyx "Aurum" cosmetic palette, and a **lobby presence buff**: any lobby containing a Legend gives every other driver in that lobby a +5% Miles Earned modifier and a +2% rare-recognition bonus. This is the systemic incentive that gets Legends to actually show up in lobbies and mentor — the highest standing in the system is structurally tied to making other drivers better.

The class advancement gating, harmonized:

| Gate | Rookie → Pro | Pro → Veteran | Veteran → Legend |
|---|---|---|---|
| Tenure | 6 months | 24 months | 120 months |
| Verified miles | 50,000 | 250,000 | 1,000,000 |
| MVR clean window | 90 days | 24 months rolling | 36 months rolling |
| Skill missions | 10 of 25 | 50 of 75 | 200 of 300 |
| Inspection completion | 95% | 98% | 99.5% |
| HOS violations (12mo) | <3 | 0 | 0 |
| On-time delivery | 88% | 93% | 97% |

A driver who hits the Standing requirement but fails any gate is held at the previous Class with a visible "Pending Promotion" badge, and the system surfaces exactly which gate is blocking them. This is critical for fairness — drivers must always be able to see why they are not advancing.

A Legend who incurs an at-fault DOT-recordable in the rolling window is demoted to Veteran for a 12-month probation, after which they can re-earn Legend through the standard gate. Class is monotonic with this single exception.

Engineering: extend the `gamification_profiles` table with `classTier`, `classTierAchievedAt`, `tenureMonthsSnapshot`, `verifiedPlatformMiles`, `mvrCleanWindowDays`, `skillMissionsCompleted`, `inspectionCompletionPct`, `hosViolations12mo`, `onTimeDeliveryPct`, `classTierPendingReason`. The advancement check is a nightly job that re-evaluates against the FMCSA Driver Information Resource and state DMV pulls.

## Chapter 16 — Specialty tracks

Seven specialties cover the trucking sub-industries that require distinct equipment, endorsements, and embodied knowledge. Each unlocks at Pro standing and remains available through Legend.

**Hazmat Specialist.** Active Hazmat (H or X) endorsement, current TSA security threat assessment, 5 successful Pro-tier hazmat missions. Mission track: Class 3 flammables, Class 8 corrosives, Class 5 oxidizers, lithium battery transport, and at Master tier Class 1 explosives and Class 7 radioactive. Cosmetic: orange-and-black diamond livery. Standing multiplier: 1.35× hazmat, 0.85× non-hazmat.

**Reefer Engineer.** >10,000 verified miles with continuous temperature logging. Pharma cold-chain (FSMA-validated), produce, frozen, and at Master tier the brutal +2/-2 °C narrow-window pharma. Cosmetic: arctic-blue with frost-pattern decals. Multiplier: 1.30× reefer, 0.90× dry.

**Flatbed Architect.** >15,000 verified flatbed miles with strap/tarp/coil-rack documentation. Steel coils, lumber, machinery, oversize/overweight permitted loads. Cosmetic: rust-and-steel with tarp-flap motif. Multiplier: 1.30× flatbed, 0.90× van/reefer.

**Tanker Master.** Tanker (N) endorsement, 8,000 verified tanker miles. Liquid food-grade, fuel, chemical, and at Master tier cryogenic and compressed-gas. Cosmetic: chrome-and-cobalt cylinder motif. Multiplier: 1.30× tanker.

**Auto Hauler.** Verified car-hauler miles. Dealer transport, exotic and concours-grade auto, white-glove enclosed. Cosmetic: silver-and-platinum with chrome accents. Multiplier: 1.25× auto-hauler. (Note: short loading/unloading videos posted as proof-of-careful-handling become highly-watched lobby content.)

**Cross-Border Diplomat.** FAST card or USMCA program enrollment, 25 successful US-MX or US-CA crossings. US-MX manifold-pairing with Carta Porte and Complemento de Pago, US-CA ACI/ACE manifests. At Master tier, the high-frequency Laredo-Nuevo Laredo lanes (40% of US-MX freight). Cosmetic: tri-flag motif. Multiplier: 1.40× cross-border (highest single multiplier — reflects the operational complexity).

**Long-Haul Veteran.** 100,000 verified solo OTR miles in a single 12-month window with zero HOS violations. Transcontinental dedicated lanes, multi-day single-driver runs. Cosmetic: deep navy with star-field constellation decals. Multiplier: 1.20× on multi-day OTR. **Carries the strongest burnout-prevention guard rails of any specialty** (Chapter 54).

A Hauler may declare a primary specialty (full multiplier) and one alt (half multiplier on the alt's mission track). The alt is capped at Pro-tier specialty mastery even if the Hauler is Master overall. Respec the primary once every 90 days; the alt monthly. Respec costs a 10% Standing debt but never real currency. Identity is never paywalled.

## Chapter 17 — Standing curve, daily caps, burnout protections

The cubic curve calibration:

```
xp_required(level n) = 500 * n + 50 * n^2
xp_to_next(L) = 100 * L^3 / 3 + 100 * L^2 + 200 * L  // alternative cubic from team_05
```

Across all ten shards the convergent calibration places Standing 100 at approximately 10 million Miles Earned cumulative, achievable in 18–24 months at four to six missions per week with average modifier stack. The curve is gentle at the start (Standing 1→2 is 333 Miles), spikes in the late game (Standing 99→100 is 33,000,000 Miles). Drivers feel rewarded for trying the platform; veterans feel earned at the top.

**Catch-up bonuses.** Two mechanisms prevent social fragmentation:
- *Lobby co-op modifier.* When a Standing <30 driver is in a lobby with at least one Standing >70 driver, the low-level driver receives +10% Miles Earned. The high-level driver receives a small +2% mentorship rep (separate ledger, see Chapter 22).
- *Rookie protection (first 30 days).* +25% flat Miles Earned plus immunity from public ranking, regardless of class tier.

**Daily Standing cap.** The structural choice that proves the platform is patient: 50,000 Miles Earned per UTC day. Once hit, mission Miles drop to 25% (not zero — the load itself is still credited). The cap is intentionally generous enough that even a focused multi-stop day cannot exhaust it through legitimate work, but tight enough that a driver attempting to chain back-to-back-to-back loads beyond what HOS or fatigue should permit gets a strong signal that the system does not want them to do that. The cap is not paywallable — there is no "premium pass" that lifts it. Driver wellness is the principle.

The system surfaces a "Recommended rest" banner at 80% of cap, and in-app push notifications throttle to zero between cap-reached and next reset. The Haul does not push the driver to work more once they have hit the cap.

## Chapter 18 — Lane Color identity (Section ID → driver lane color)

PSO's Section ID was a stroke of design genius: a permanent flavor attribute, assigned semi-randomly at character creation, that biased rare drops toward different items. It made trading meaningful. It made co-op valuable. It gave every character a piece of identity the player did not choose and could not respec.

The Haul's **Lane Color** ports this exactly. Lane Color is assigned by the Hauler's home-base ZIP code at onboarding, and changes only when the home base changes (verified by registered address, IFTA jurisdiction, and a 60-day residency confirmation). The ten Lane Colors:

| Lane Color | Zone | Rare-recognition bias |
|---|---|---|
| Crimson | Northeast corridor (I-95 BOS–DC) | Pharma reefer, fashion-retail dry van |
| Cobalt | Great Lakes (I-94/I-80 Chicago–Detroit–Cleveland) | Auto-parts JIT, steel coils |
| Verdant | Southeast (Carolinas–Georgia–Florida) | Agricultural reefer, citrus, poultry |
| Amber | Texas Triangle (Dallas–Houston–San Antonio) | Petrochemical, oilfield, cross-border MX |
| Onyx | Appalachian (Ohio Valley, KY, WV, TN) | Coal, lumber, Class-8 chemical |
| Silver | Mountain West (CO, UT, ID, MT, WY) | Mining, livestock, oversize permitted |
| Pearl | Pacific Northwest (WA, OR, AK) | Lumber, seafood reefer, port drayage |
| Sun | California Central Valley | Produce reefer, Port of LA/LB drayage |
| Sand | Desert Southwest (AZ, NM, NV) | Solar/wind components, cross-border, datacenter |
| Aurora | Northern Tier and Canada | Grain, energy, US-CA cross-border |

The bias is roughly 1.6× within-lane, 0.8× cross-lane, with each Lane having two or three exclusive seasonal items per quarter — exactly the structure that turned PSO Section IDs into the trade economy's animating force. A Crimson Hauler who pulled a Sand-exclusive decal from a cross-country mission has something a Sand Hauler desires. Running with an out-of-Lane partner exposes you to that partner's recognition pool with a 1.2× cross-pollination bonus.

Lane Color is the dominant background hue of the avatar portrait card. It is the single most legible visual attribute at lobby distance — a Hauler across the lobby looks "Crimson" or "Cobalt" before any other detail registers. The Lane also tints the chat-bubble border and the pin on the global Haul map.

**The wellness clause is non-negotiable: Lane Color does not gate any safety-critical mission category.** A Sand Lane Hauler is not blocked from running pharma reefer; they just see fewer pharma cosmetics drop. The bias is purely cosmetic. We never want a Hauler to feel they must take a load they shouldn't, or skip a rest, because of a Lane-Color recognition chase. Recognition hunting is dessert, not the main course.

## Chapter 19 — Prestige + Rebirth (First Light through Eighth Light)

At Standing 100 the question every progression system has to answer: what comes next? PSO answered with post-200 grind on stat ceilings. Modern games answer with prestige systems — reset to Level 1 in exchange for permanent buffs and visible badges. The Haul adopts the prestige model and names the iterations the **Eight Lights**.

At Standing 100 the Hauler is offered the Rebirth option. It is never required and never expires. A Hauler can sit at 100 indefinitely. But a Hauler who chooses to Rebirth resets Standing to 1, retains every cosmetic, retains Class (Hauler Master remains Hauler Master), retains Lane Color and specialties, and gains a permanent +5% Miles Earned buff that stacks across Rebirths (capped at +40% at Eighth Light).

The visual UX for Rebirth is deliberately ceremonial. A Hauler who selects Rebirth gets a fade-to-white "First Light" cinematic, their lobby portrait briefly animates a halo effect, and a short broadcast goes out to every driver in their Lane: *"Diego of Crimson Lane has crossed into First Light."* The community ritual matters.

| Tier | Name | Cumulative buff | Unlock |
|---|---|---|---|
| 0 | (no rebirth) | +0% | default |
| 1 | First Light | +5% | first Rebirth from Standing 100 |
| 2 | Second Light | +10% | second |
| 3 | Third Light | +15% | third |
| 4 | Fourth Light | +20% | fourth |
| 5 | Fifth Light | +25% | fifth |
| 6 | Sixth Light | +30% | sixth |
| 7 | Seventh Light | +35% | seventh |
| 8 | Eighth Light | +40% | eighth — terminal prestige |

Eighth Light is the terminal tier. There is no Ninth. An Eighth Light driver has accumulated approximately 80 million lifetime Miles Earned — roughly 12,000 to 16,000 completed missions — over a real-world arc of 8 to 15 years for a sustainably-paced career. By design Eighth Light remains under 0.5% of the active driver base for the lifetime of the platform.

**The Eighth Light privilege.** Eighth Light Haulers earn the right to host their own mission-design event. They submit a mission concept (a unique route, a themed cargo, a charity-partnership lane, a memorial run), and Eusorone product, subject to operational and compliance review, instantiates that mission as a limited-time seasonal event open to the platform. The hosting Hauler receives a permanent named-credit on the mission listing ("a Diego Crimson Memorial Run") and a one-time custom cosmetic that no other driver can earn. This is the doctrine's deepest commitment to driver agency: at the very top of the progression ladder, the system gives back content authorship.

The wellness clause: Rebirth is **never** marketed via FOMO push notifications. The system tells a Standing 100 driver, once, that the option exists. It does not nag. The XP buff applies to Mission Miles only — it does not increase pressure to drive longer hours. A First Light driver still hits the same daily cap, still falls under the same fatigue-aware mission feed, still gets the same recommended-rest banners. Prestige is permanent recognition, not permanent grind acceleration.

---

# PART V — The Lobby

## Chapter 20 — The Lobby, geofenced to physical truck stops

The Lobby is the social heart of The Haul. It mirrors PSO's Pioneer 2 Block 1 but reframed as a **truck-stop POI** in the EusoTrip Network. Drivers physically present at a real truck stop (geofenced) appear as 3D avatars in a shared scene rendered at a fixed isometric angle (the canonical 35.264° pitch, 45° yaw — the iso angle PSO used on every Block lobby for twenty-six years).

The Lobby skeleton:

- 3D isometric scene of the truck-stop diorama. Pre-baked .usdz environment (~4MB) with neon signage, parked rigs, a coffee window, a small picnic table. Lighting: a single directional sun + ambient skybox.
- Avatars: 3D characters (~2k tris LOD0, ~800 LOD1, ~200 LOD2). Each carries a banner above the head with name + Lane Color + Rebirth count.
- Sixteen avatar slots per lobby instance. If a stop has more than sixteen, lobby shards into A/B/C with one-tap switching.
- Pulse watch reports presence on a 30-second tick. Avatars fade in over 2 seconds when a driver arrives, fade out over 5 seconds when they leave or go off-grid.
- The sleeper-berth zone is dimmed and silent. Drivers in sleeper berths render as a soft pulsing icon, no avatar fidelity, because privacy matters more than presence.
- Camera is fixed iso. Two-finger drag pan (clamped to scene), pinch-zoom 0.7× to 1.4×. **No rotation.** The fixed angle is essential to the doctrine's visual cohesion.

Performance budget: 60fps on iPhone 12+, 100k triangles total, 64MB texture memory, ≤80 draw calls, ≤4%/10min battery delta, thermal target Nominal-Fair, never Serious. iPhone 11 and below, or any device where `MTLDevice.recommendedMaxWorkingSetSize < 1.5GB`, falls back to a 2D Lobby — a flat scrollable grid of 64pt avatar cards, preserving the social meaning without the GPU cost.

The bottom-edge action bar holds four tap-targets: **Wave**, **Talk** (push-to-talk voice channel scoped to the lobby, max sixteen participants, half-duplex, latency <250ms), **Trade**, and **Mission** (walks the avatar to the Dispatcher Window, the renamed Mission Board NPC counter from Chapter 8).

The geofence verification is non-negotiable: an avatar cannot appear in a lobby unless the Pulse watch GPS has been stationary within the truck-stop polygon for at least 90 seconds. **No lobby teleporting.** This is the integrity floor that keeps the lobby a place where actual drivers physically present meet.

The privacy floor (master opt-out) is also non-negotiable: Settings → Lobby Visibility → "Ghost Mode." A driver in Ghost Mode renders as an empty parking slot to others while still seeing the lobby themselves. Sleeper Berth Auto-Hide kicks in after 4 hours stationary OR HOS sleeper status, dimming the avatar and silencing inbound emote. Block list is unilateral, immediate, and mutual — blocked drivers literally do not render to each other.

Engineering: lobby state is a single `LobbyChannel` WebSocket pushing `LobbyEvent` updates. Position is throttled server-side to 10Hz; client interpolates. The existing `messages` router and the `haul_lobby_messages` table (already in the database) handle the chat surface. The new `getLobbyMessages` (line 1272 in `gamificationRouter`) and `postLobbyMessage` (line 1331) procedures are already in place. The 3D rendering layer, the geofence verification, and the avatar fade transitions are net-new client work.

## Chapter 21 — Crew commands, BOL Stamps, Symbol Chat parity

PSO's Symbol Chat was a 4×4 emote composer. You picked a face, two body parts, two background symbols, and a typed phrase. The result rendered in a comic-book speech bubble over your avatar. Symbol Chats were saved, traded, customized — they were the first social-graph emoji, eight years before iMessage shipped them.

The Haul replicates Symbol Chat as the **emote wheel** bound to the Pulse watch crown. The reconciled v1.0 emote vocabulary:

- `/wave` — basic wave. Free, unlimited.
- `/coffee` — your avatar lifts a thermos. Costs 1 Standing Point to send to another driver as a "buy you a cup" gesture (redeemable at participating chains).
- `/breakdown` — your avatar squats beside the rig with a shop light. Signals you need help. Auto-pings nearest opted-in mechanic-tier drivers within 25 miles. Logs as a soft request to the Mutual Aid Fund.
- `/wrench` — offer mechanical help. Logs as a soft credit toward the Helping Hand mark.
- `/freebie` — a rare emote (one per driver per 72 hours). Your avatar tosses a glowing object into the air. Whichever opted-in driver in the lobby first taps it receives a randomized cosmetic recognition (truck-wrap pattern, hat skin, dash bobblehead).
- `/sit` — your avatar perches on the running board. Idle pose for stationary lobbying.
- `/cheer` — applause animation. Free, capped at 8 per minute per driver (anti-spam).

The hard rate limits on emote spam: max 8 emotes per minute per driver. The eleventh emote auto-mutes the offender for 10 minutes and notifies a moderator.

**The BOL Stamp** is the Haul's renamed Symbol Chat for victory moments. When a Mission completes and the BOL is signed (electronically through the Eusoboards POD flow), the system auto-generates a square share-card with origin/destination cities, mileage, paid rate per mile, total revenue, bonus tier earned, marks dropped, the Hauler's avatar in a victorious pose, and the Eusoboards gradient frame. The Hauler can post the BOL Stamp into their current lobby with one tap — it hovers above the avatar in a glowing speech-card for 90 seconds, and is permanently archived to the Hauler's Profile.

The BOL Stamp is server-signed against the ledger entry. **They cannot be edited or fabricated.** No fake flexes. The rate stamp-shaming filter blurs sub-$1.50/mile rates and replaces them with a generic "Rate: visible to receiver only" tag, to prevent low-rate public mockery while still allowing celebratory post.

Engineering: BOL Stamp generation lives in a new `bolStampRouter` to be added in Sprint 2. Server-side asset composition <1.2 seconds from POD signature. Stamp render in lobby <600ms from tap. Profile-card open <400ms including pre-cached 3D model. The renderer uses the SwiftUI `ImageRenderer` for the share card; the lobby chat bubble uses the existing `messages` flow.

## Chapter 22 — Marketplace + driver-to-driver economy (KYC + AML)

The Marketplace is the renamed Glass-Case Showcase — a kiosk standing in the corner of the 3D lobby. Tap it, browse Hauler listings:

- **Ride-Along Day auctions:** Legend-tier Haulers list a ride-along seat for a rookie. Highest bid wins. Educational, mentor-driven, capped at one ride-along per quarter per Hauler. KYC mandatory both sides. $250–$1,500 typical price.
- **Training Session listings:** Verified instructor endorsements only. 1:1 90-minute sessions ($120 typical). EusoTrip 5% platform fee.
- **Premium Playlist subscriptions:** Curated "Mile Music" playlists, $1.99/month, 70/30 split favoring the Hauler. Music licensing handled centrally by Eusorone Music negotiation.
- **Audio content / Audio CB Comedy bundles:** Drivers list audio they have rights to or have authored.
- **Route Walkthrough Videos:** Pre-recorded videos of complex shipper or receiver sites (gate codes scrubbed). $10–$50.
- **Regulatory Cheat Sheets:** Hauler-authored PDFs on niche regulations. $5–$40.
- **Consultation Calls:** Phone calls for specific problems (DOT inspection prep, broker dispute strategy). $75–$200.
- **Coaching Subscriptions:** Monthly access to a senior Hauler. $30–$150/month.
- **Custom Lane Reports:** Written analysis of specific lanes. $100–$500.

The marketplace floor is $5 per listing (below this, transaction costs eat the value). The single-listing ceiling is $1,500 (above this, IRS scrutiny on individual transactions elevates). The per-driver per-year ceiling is $50,000 gross — above this, the system requires a separate business-account onboarding with full S-corp / LLC documentation.

The fraud-and-laundering guard rails are exhaustive:

1. All transactions KYC-verified at both ends. No anonymous trade.
2. Rate-limited: max 20 trades per Hauler per day, max $1,000 cumulative gifted per day. Higher limits unlock with tenure.
3. Dual-direction reputation: every trade rates both giver and receiver; lopsided ratings (too many one-direction transfers) auto-flag for compliance review.
4. Compliance visibility: all peer-to-peer money flow is visible in real time to the Trust & Safety + AML compliance team. Patterns matching laundering typologies (structured deposits, fan-in/fan-out, geographically improbable rapid transfer) auto-escalate.
5. No item duplication possible: every cosmetic unlock code is a unique server-issued nonce, single-use, retired on redemption. There is no "duping" because there is no client-authoritative inventory state.
6. Marketplace listings are reviewable: a Trust & Safety reviewer signs off on each new listing before it goes live. Time-to-approval target: 4 hours business, 24 hours weekend.
7. Dispute escalation: every transaction has a 72-hour reversal window with adjudication by a human reviewer.

Tax routing: marketplace sales are 1099-K (Stripe-issued) at year-end. The Hauler is the seller of record; EusoTrip is the marketplace facilitator (similar to Etsy or eBay). The Hauler is selling their own product to a third-party buyer, not performing services for The Haul — this keeps the marketplace clear of any worker-classification concerns.

## Chapter 23 — Seasonal events (Driver Appreciation Week, MATS, ATA, Eusoversary)

PSO's lobbies were living rooms — they re-skinned themselves around real-world holidays. Christmas brought falling snow and festive lighting. Halloween brought pumpkins and dim purples. Players logged in not just to play but to *see what the lobby looked like that month*. The seasonal lobby was an FOMO engine — miss Halloween, miss the Halloween cosmetic, wait a year.

The Haul ports this to the trucking world's actual cultural calendar:

- **Truck Driver Appreciation Week (mid-September annually):** lobbies get bunting, banner-flags above each parking slot, free coffee tokens dropped to every active Hauler, double Miles Earned all week. Special boss-tier Mission unlocks: *The Appreciation Run* — a high-paying, hand-curated load broadcast to top-rep Haulers.
- **MATS — Mid-America Trucking Show, Louisville, late March:** the Louisville-region lobby skins as the Kentucky Exposition Center showroom. Haulers parking in Louisville during MATS week get an exclusive *Louisville '26* truck-wrap.
- **Great American Trucking Show, Dallas, August:** Dallas-region equivalent skin.
- **ATA Management Conference & Exhibition, October:** themed lobby, leadership-tier marks drop, a "Policy Panel" mini-mission lets Haulers RSVP to virtual roundtables with EusoTrip leadership.
- **Christmas / Hanukkah / Festivus / Three Kings / Diwali:** rotating multi-cultural decoration packs Haulers can choose between, no forced single-tradition skin. Holiday airhorn emote unlocks 12/15 through 1/6.
- **Independence Day, Cinco de Mayo, Canada Day, Mexican Independence (Sept 16):** flag-themed regional rotations.
- **Memorial Day & Veterans Day:** somber skin, no celebratory flair, dedicated mark for veteran drivers (verified through SkillBridge or DD-214 upload).
- **Eusoversary (founding day, every year):** company anniversary, double Miles Earned, the Founder's commemorative cosmetic of the year, a charity tie-in.

The Eusoversary charity rotation: Year 1 Truckers Against Trafficking. Year 2 St. Christopher Truckers Relief Fund. Year 3 Wreaths Across America. Year 4 National Association of Independent Truckers Health Fund. Drivers can opt into a "Round Up for the Cause" toggle — every load settlement rounds the payout down to the nearest dollar and donates the cents to the year's charity, with the platform matching dollar-for-dollar up to a published cap of $250,000/year. Live ticker in the lobby shows year-to-date raised. Marks drop at $100/$500/$1,000 personal cumulative.

Politicized event guard: national-political holidays (election-adjacent) get neutral skinning — no candidate references, no party imagery, just generic civic engagement. Holiday-adjacent religious observance: Haulers can mute event skinning during personal observance windows (Ramadan, Lent, Yom Kippur) without losing event-mission eligibility.

Engineering: the seasonal rotation is server-driven, with asset bundles pre-downloaded 24 hours in advance during overnight idle. The existing `seasons` table and `seasonalRank`/`seasonalXp` columns on `gamification_profiles` are the ledger. New: `getSeasonalEvents` (line 890 in `advancedGamificationRouter`) and `getSeasonalProgress` (line 899) are already in place; needs the asset-bundle delivery pipeline added.

## Chapter 24 — Cross-Mode Lobby (truck ↔ rail ↔ vessel)

PSO's high-level lobbies were the prestige floors — accessible only to characters of significant level. The Haul ports this not to player level but to *transportation mode*. EusoTrip is multi-modal: trucking, rail, vessel (ocean and inland marine). Each mode has its own operator culture; The Haul makes mingling a feature.

Each mode has its own native lobby:

- **Truck Lobby** — at truck stops, geofenced.
- **Rail Lobby** — at intermodal yards, locomotive crew rooms. Yard tower diorama.
- **Vessel Lobby** — at port operations centers, harbor pilot stations, container terminal break rooms. Quayside diorama with cranes in the skyline.

A driver, conductor, or captain sees their own mode's lobby by default. Adjacent-mode lobbies are visible as ghosted halls through stylized doorways at the edge of the diorama. Tap a doorway, peer through, see the adjacent lobby's avatars and engage in cross-mode chat.

**Multi-modal handoff missions** are the killer use case. A Hauler drops a forty-foot container at the Memphis BNSF intermodal ramp and pings the rail-side lobby — *"container 7841 dropped, headed for Long Beach, anyone picking up the rail leg?"* The rail crew on shift sees the ping in their lobby's mission feed and claims it. Settlement, paperwork, and chain-of-custody flow through one ledger entry — no email, no phone tag, no fax.

A vessel captain arriving at the Port of Newark pings the trucker lobby — *"twenty containers cleared customs, dispatch slots open between 0600 and 1400."* Haulers in the Newark trucker lobby see the ping with EusoTrip Network ETAs to the gate, claim slots, fill them.

**The Triathlete mark.** A driver who completes at least one mission in *all three* modes within a thirty-day rolling window earns Triathlete — an elite tier above even Legend. Triathletes get reserved Tier-1 Lobby slots on the Triathlete Hall (a cross-mode lobby visible to Triathletes only across the entire EusoTrip fleet), a chrome-and-aurora name color, priority boarding on EusoTrip's executive driver-input panels, and an annual real-world Triathlete dinner at the Eusoversary.

Triathlete annual maintenance: complete one mission in each of two of three modes per quarter to retain status. (Not all three each quarter — that would be operationally impossible. Two of three is the keepable bar.)

The Tier-1 Lobby is the trucking equivalent of an executive lounge — quieter, fewer slots (eight per shard rather than sixteen), better lighting, exclusive emote pack, access to a Mentor Channel push-to-talk where rookies can request 30-minute mentorship slots.

The cross-mode handoff fraud guard is biometric: chain-of-custody requires Pulse-watch confirmation at both ends of the handoff (driver dropping, rail crew claiming) to settle. No phantom containers.

---

# PART VI — Live Mission Triggers (using EusoTrip routing/geofence backend)

## Chapter 25 — Surge missions — geofenced spawn events

A Surge Mission (the renamed Boss Mission) is a high-value load that exists only inside a defined polygon, only for a defined window, and only for Haulers who can physically claim it within that window with available HOS hours and trailer capacity. It is the trucking equivalent of a PSO red-box drop from a rare enemy: you do not farm it, you stumble into it, and if you are not ready you watch someone else take it. Scarcity is the entire point.

The inaugural Surge Zone is the **Texas Triangle Q4**:

```
ZONE_ID: SURGE_TX_TRI_Q4_001
TYPE: CIRCLE_APPROX_AS_POLYGON (32 vertices)
CENTER: 32.7767°N, 96.7970°W (Dallas)
RADIUS: 200 statute miles
BUFFER: 1 mile interior buffer (prevents edge-flapping)
ACTIVE_WINDOW: Oct 1 00:00 CST → Dec 31 23:59 CST
SUBZONES: DFW intermodal, Houston petrochem, Laredo border
```

The trigger rules:

1. **Entry trigger:** Hauler enters polygon AND remains inside ≥ 90 seconds AND has ≥ 6 HOS hours remaining AND has trailer status `EMPTY` or `PARTIAL`.
2. **Spawn condition:** A Surge Load is held in escrow by the broker partner; spawn is gated by load availability. We pre-load 1–4 Surge Loads per zone per day during peak.
3. **Visibility window:** 4 hours from spawn. If unclaimed at hour 3:30, push a "Last Call" notification to all eligible Haulers within 25 miles.
4. **First-come, first-served:** Atomic claim via Redis `SETNX boss_load:{id}:claim {driver_id} EX 300`. Five-minute confirmation window — Hauler must accept in-app, after which the load is locked.
5. **Expiration:** If unclaimed at the 4-hour mark, the load returns to the standard load board at base rate; the Surge reward modifiers are stripped.

The reward economy:
- **Base rate:** Standard market rate for the lane (DAT spot, refreshed hourly).
- **Surge multiplier:** 2.5× the base linehaul. On a $1,800 Dallas–Houston run, that is $4,500 to the Hauler/carrier.
- **Miles Earned:** 5,000 on pickup + 5,000 on delivery + 2,500 "clean run" bonus if no service failures. Total: 12,500 — roughly 8–10 standard hauls.
- **Recognition crate:** Guaranteed Legendary-tier from the Surge pool. RNG-weighted within Legendary; no two completions in the same week yield identical items for the same Hauler.

Anti-abuse: a Hauler may claim no more than 2 Surge Missions per rolling 7-day window, preventing whales from monopolizing inventory.

The professional copy on the surface is restrained:

> **Texas Triangle Surge — Wind Blade Run**
> Verified high-rate load · Pueblo CO → Amarillo TX
> Three pilot cars · 2.5× linehaul
> Legendary recognition guaranteed
> Window: 4 hours from now

No "Boss spawn!" hype. No "Defeat the dragon!" copy. Just the work, the rate, the window, and what the recognition will look like. The internal mechanism is the PSO red-box; the external presentation is the broker call you've always wanted.

## Chapter 26 — Hot Zone capture — cooperative buffs

Hot Zones are areas of elevated freight density or rate spikes — the trucking analog of a PSO field map. Capture mechanics turn Hot Zones from a passive overlay into an active cooperative event: when five or more Crew-mates dwell in the same Hot Zone for two cumulative hours, the zone is "Captured," and the entire Crew (potentially 80–200 Haulers nationwide) gets a 24-hour Miles Earned bonus.

Hot Zones are dynamically generated nightly by the freight-density layer based on a 14-day rolling window of load-board volume, rate-per-mile spikes (>1.3σ above corridor mean), and weather/holiday modifiers. Approximately 45–60 Hot Zones live globally at any given moment.

The capture rules:
1. **Dwell accumulation:** Each Hauler banks dwell-minutes per Hot Zone, decaying at 1 minute per hour of absence (so leaving for fuel does not reset progress, but a 2-day vacation does).
2. **Capture trigger:** When the sum of any 5 Crew members' dwell-minutes inside the same Hot Zone reaches 600 minutes (120 minutes × 5 Haulers), Capture fires.
3. **Crew buff window:** 24 hours starting at Capture timestamp. Buff = +20% Miles Earned on all completed missions, all Crew members, anywhere.
4. **Cooldown:** That Hot Zone cannot be re-captured by the same Crew for 72 hours; other Crews remain eligible.
5. **Expire:** Hot Zones themselves expire weekly when the freight-density recompute runs.

No direct cash payout — this is a buff event, intentionally aligned with PSO's PSE Burst precedent. The Capture-team bonus: the five Haulers who actually contributed the qualifying dwell minutes split a 25,000 Miles Earned "Anchor" bonus (5,000 each) and receive a "Zone Anchor" mark for the captured zone. Three Anchor marks in different zones unlock the "Cartographer" Epic title.

The existing `hotZones.ts` router is already exposed in the iOS Home tab; the dwell-aggregator and capture-event logic is net-new work.

## Chapter 27 — Truck-stop micro-missions

Truck-stop micro-missions convert dead time at Pilot/Loves/TA into Miles-Earned-bearing micro-tasks. Deliberately small (30 seconds to 5 minutes), exploiting sensors the Hauler's phone already has: CoreMotion for step counting, BLE proximity for "talk to a Hauler in the lobby," POI feedback for star ratings.

The four micro-missions:

| Mission | Miles Earned | Cash | Loyalty |
|---|---|---|---|
| Walk 200 Steps | 75 | $0.50 | +5 myRewards / Loves points |
| Crew Social (talk with another Hauler ≥5min via BLE proximity) | 150 | $1.00 | +10 |
| Rate This Stop (4-question rating: cleanliness, food, parking, showers) | 50 | $0.25 | +5 |
| Inspect the Cab (6-photo pre-trip checklist, ML-verified) | 200 | $1.50 | +15 |

A Hauler completing all four daily across 250 working days nets ~118,750 Miles Earned and $807 cash + $5,375 in loyalty equivalents — modest, but compounds. Crucially, all of it is earned during legally-mandated downtime that would otherwise be unpaid.

Loyalty point integration is real-money valuable: Pilot myRewards converts at roughly 1¢/point on showers and food. The partnership term sheet gives The Haul a 12% rebate on point issuance, funding the cash side of the micro-mission economy.

The doctrine choice: **passive, in-app discovery only.** No push notifications fire for micro-mission availability. The intent is in-app discovery during the rest break, not interruption of driving. The only push is an "all four completed today" celebration card.

## Chapter 28 — Cross-border missions — Carta Porte, ACE, ACI

The Mexican and Canadian border crossings are the highest-cognitive-load events in any OTR Hauler's week. Carta Porte (Mexican electronic shipment manifest), ACE (US-bound), ACI (Canada-bound), FAST lane eligibility, Pedimento clearance — Haulers juggle five document standards in three languages on a tablet that wasn't designed for the job.

Cross-Border Missions wrap that ordeal in a checklist: arrive at the geofence, the cab tablet auto-displays your filing status, prompts for missing pieces, times the run, and pays bonus. Not adding work — reskinning the paperwork the Hauler already has to do.

The reconciled trigger logic for the Laredo World Trade Bridge example:

```
ZONE_ID: BORDER_LRD_WBINTL_FAST_SB
PORT: Laredo / Nuevo Laredo (World Trade Bridge)
DIRECTION: Southbound (US → MX)
LANE_TYPE: FAST
POLYGON: rectangle, 8 vertices (with curve approximation)
ENTRY_VERTEX: 27.6017°N, 99.5217°W
EXIT_VERTEX: 27.5894°N, 99.5283°W
PAIRED_ZONE: BORDER_NLD_WBINTL_FAST_SB (Mexican side, fires on exit)
ACTIVE: 24/7, surge multiplier weekdays 0500–1700 CT
```

Rules:
1. **Approach trigger:** Geofence entry on the approach polygon (1.5 mi out from the port). Mission card opens.
2. **Doc check:** Backend pulls latest filing status. If anything is missing, mission goes into `DOCS_INCOMPLETE` with a red checklist; Hauler can call dispatch from the card.
3. **Crossing window:** Mission active until either driver clears exit polygon on the foreign side, or 4 hours elapse.
4. **Clean-run criteria:** Crossed in under [historical median for that port × 0.85], zero secondary inspections, zero document corrections at the booth.

Reward economy:
- Base 1,000 Miles Earned per crossing.
- Clean Run bonus: +1,500 Miles Earned.
- Cash bonus: 5% of linehaul rate, capped at $250 per crossing.
- Mexican-corridor perk: Spanish-language Pedimento and Carta Porte annotated translation in-cab, "Vaquero" Epic title at 25 verified MX crossings.
- Canadian-corridor perk: Bilingual EN/FR ACI summary, "Voyageur" Epic title at 25 CA crossings.
- Border Master meta-mark: Both titles + 100 total crossings = "El Camino" Legendary title with animated triple-flag dashboard ornament.

Engineering: integrates Geofencing with the EusoTrip Network's truck-routing and customs-broker partner APIs (Livingston, Expeditors, A.N. Deringer). Carta Porte XML pulled via SAT credentials the carrier has already registered. Translation by a custom 4,200-entry Mexican trucking glossary (caja seca, plataforma, dolly, etc.). Pre-arrival push 30 minutes out: "Border Run prepping — docs status: [GREEN/YELLOW/RED]."

## Chapter 29 — Crisis-response missions — disaster relief

Hurricanes, wildfires, blizzards, and flooding events all create freight emergencies that reroute thousands of trucks within hours: bottled water into Florida, generators into the Carolinas, hay into Texas during snap freezes. Crisis Mode missions formalize what good Haulers already do — they answer the call — and put the recognition engine behind it.

This is the moral spine of the brand. The Hauler-as-hero arc is not marketing copy; it is a payable mission line. We earn the right to call our Haulers heroes by literally paying them more when the country needs them.

The eligibility gate is strict:
1. Hauler has toggled Crisis Mode ON.
2. Hauler has completed the Haul "Hazardous Conditions" CBT module (90 minutes).
3. Hauler has current TWIC + medical card + clean MVR within last 12 months.
4. Hauler has ≥ 8 HOS hours and ≥ 24 cycle hours remaining.

Crisis polygons refresh every 15 minutes during active events from FEMA OpenFEMA and NWS feeds. Driver opt-in is mandatory — Crisis Mode never auto-engages a driver who has not toggled it on and signed the Crisis Mission rider.

Reward economy:
- **Base rate multiplier:** 2.0× FEMA emergency rate schedule (already elevated above standard).
- **Crisis Miles Earned:** 25,000 per completed Crisis run. Highest single-mission yield in The Haul.
- **Hero ladder:** 1 Crisis run unlocks "Responder" mark. 5 unlocks "First In" Epic title. 15 unlocks "Hurricane Heart" Legendary title with custom in-cab animation (rain on windshield with subtle Red Cross accent).
- **Charity match:** 5% of the Hauler's gross earnings on each Crisis run is matched 1:1 by Eusoboards corporate and routed to American Red Cross. Hauler receives a personalized impact card ("Your run delivered 3,200 meals worth of relief").
- **Death-and-injury rider:** $250,000 supplementary AD&D coverage active for the duration of any Crisis mission, paid by Eusoboards, no Hauler cost.

HOS exemption (49 CFR 390.23) is auto-checked when a federal disaster is declared. Auto-cancel triggers: conditions deteriorate beyond severity 5, mandatory evacuation order issued for the destination, or Hauler requests abort. **No penalty for invoking abort.**

Post-event reporting: every Crisis run generates a public (Hauler-anonymized) impact post on the Haul community feed. *"73 Haul Haulers, 1.4M lbs of relief, $112K to Red Cross"* — this is brand story, fueled by data the system captures automatically.

---

# PART VII — Driver Monetization (5 paths)

## Chapter 30 — Mission completion bonuses

Floor $25 per mission. Ceiling $5,000 per single mission. The seventeen-archetype bonus catalog is canonical:

| Mission archetype condition | Bonus | Conditions |
|---|---|---|
| Hazmat Master | +$500 | Hazmat placard load, zero violations, on-time within 30 min, all chain-of-custody scans |
| Cross-Border Spanish Translation | +$250 | Self-certified bilingual, MX crossing, customs paperwork in Spanish without broker assist |
| Cross-Border French (Canada) | +$200 | Quebec crossing, French-language CBSA documentation |
| First Completion of the Month | +$100 | First load delivered between 00:00 local on the 1st and 06:00 on the 2nd |
| Reefer Perfect Temp Log | +$150 | Reefer load, continuous temp log, zero excursions |
| Oversized / Permit Load | +$400 | Permit load, escort coordination, route adherence verified by GPS |
| Tanker Endorsement Run | +$300 | Liquid bulk, no slosh-event flagged |
| Doubles / Triples | +$350 | Multi-trailer config, documented |
| White-Glove High-Value | +$450 | Cargo > $250K declared, signature chain, no claims |
| Storm-Routed Critical | +$600 | NOAA-flagged severe weather corridor, opts in, completes safely with HOS adherence |
| Live Unload Endurance | +$75 | >4 hr live unload completed without detention dispute |
| Same-Day Expedite | +$500 | Pickup-to-delivery under 12 hr, single-driver legal HOS |
| Team Run Coordination | +$300 per Hauler | Two-driver team, both certified, full continuous coverage |
| Hazmat + Cross-Border Stack | +$750 | Both Hazmat Master AND Cross-Border conditions met on same load |
| Veteran Mentor Run | +$200 | Verified veteran Hauler paired with rookie observer (non-driving) |
| First-Year Anniversary Mission | +$1,000 | One full year on platform, completed on anniversary load |
| Founder's Pick (rotating) | +$250 to +$5,000 | Hand-curated weekly mission; ceiling enforced |

A qualified mission-active Hauler running 200 loads/year and opting into ~35% of available missions: 70 missions accepted × $275 average = ~$19,250/yr. A high-frequency Hazmat / Cross-Border specialist: 120 × $400 = ~$48,000/yr.

Tax form: 1099-NEC, Box 1 (nonemployee compensation), aggregated with load pay.

## Chapter 31 — Streak rewards

Reconciled cumulative table from Chapter 12:
$50 + $250 + $1,000 + $3,000 + $10,000 = $14,300 across a full 365-day streak, plus the Founder-signed truck plaque. Two 180-day streaks (one break) = $4,300 + $4,300 = $8,600. Chronic 30-day breaker = ~$300 × 8 = ~$2,400.

A consistent veteran should expect $10,000 to $14,300/yr from streaks alone.

Tax form: 1099-MISC Box 3.

The freeze provision and the wellness floor are non-negotiable. Streaks are a reward for sustainable consistency, not for grinding through exhaustion.

## Chapter 32 — Referral economy

Single-tier, flat, verified outcome:
- Driver / Owner-Op: $500
- Mid-Carrier: $2,000
- Carrier (10+): $5,000
- Broker: $1,000
- Shipper: $1,500

Casual referrer (2/yr): $1,000. Active (4 drivers + 1 broker): $3,000. Power (8 drivers + 2 brokers + 1 carrier): $11,000. Realistic ceiling: ~$15,000/yr (above this, manual review).

Clawback 50% if referred party churns within 6 months; 100% if suspended for fraud within 12 months. Tax form: 1099-MISC Box 3.

## Chapter 33 — Tier-based fee + factoring discounts (HaulPay)

The combined math (Chapter 11):

A Hauler at $200K annual load revenue saves $1,000/yr at Standing 100 versus baseline. A Hauler at Black factoring tier on $500K saves $7,500/yr versus Standard tier. The cumulative climb across both ladders banks roughly $3,500 + perpetual $1,000+/yr.

These are deterministic, audited, IRS-clean, durable financial benefits that compound the longer the Hauler stays on the platform.

## Chapter 34 — Marketplace earnings (ride-along, training, premium playlists)

Floor $5/listing, ceiling $1,500/listing, per-Hauler-per-year cap $50K gross.

Casual seller (5 listings/yr): $500–$2,000 net. Active (1 listing/week): $5,000–$10,000 net. Power seller (subscriptions + multiple training calls + ride-alongs): $15,000–$40,000 net.

EusoTrip 15% platform fee. Tax form: 1099-K (Stripe-issued).

The wellness floor: a Hauler cannot fulfill a live training session or consultation call while their ELD shows on-duty driving. Calls scheduled during driving hours are auto-rescheduled. Maximum 8 hours per week of live marketplace fulfillment. Marketplace pause on safety violation. *The marketplace is a side rail, not a substitute for the road.*

**Cross-path summary.** A qualified Hauler with full participation across all five paths can expect, in a strong year:

| Path | Mid-tier ARR | High-tier ARR |
|---|---|---|
| Mission bonuses | $19,250 | $48,000 |
| Streaks | $4,300 – $14,300 | $14,300 |
| Referrals | $1,000 – $3,000 | $11,000 |
| Fee reductions | $300 – $500 | $1,000 – $2,000 |
| Marketplace | $500 – $5,000 | $15,000 – $40,000 |
| **Total beyond load pay** | **~$25,000 – $30,000** | **~$90,000 – $115,000** |

A $200K load-revenue Hauler becomes a $225K–$315K total-revenue Hauler depending on engagement breadth.

---

# PART VIII — Eusorone Revenue Model

## Chapter 35 — Engagement → Volume → Take Rate

The flywheel: 10K active Haulers Y1 × $200K gross freight × 18% completion lift × 1.0% take rate = $3.6M Y1 ARR from lift alone. Y3 35K Haulers = $12.6M. Y5 100K Haulers = $36M.

Driver CAC compresses from 14 months payback to 7 months. LTV expands from $410 to $1,180 — a 2.9× LTV expansion that materially changes the economics of paid acquisition.

TAM: 3.5M U.S. CDL holders × $200K avg billings × 1% take = $7B addressable. SAM: 1.1M owner-operators × $200K = $220B / 1% take = $2.2B SAM.

## Chapter 36 — Sponsored mission monetization

Three tiers:
- **Tier 1 ($50/mission):** Small carriers, regional truck-stop chains, local repair shops. Cosmetic-only placement.
- **Tier 2 ($500/mission):** National truck-stop chains (Pilot, Loves, TA), tire brands (Bridgestone, Michelin), regional fuel networks. Mission-card branding + lobby billboard.
- **Tier 3 ($5,000/mission):** ELD providers, OEMs (Freightliner, Peterbilt, Volvo), insurance carriers, financial services (Comdata, EFS). Full mission-takeover.

Y1: 10K Haulers × 6 missions/day × 16.7% sponsored = 10K sponsored/day × $30 blended = $300K/day floor → $109.5M annualized ceiling. Realistic Y1 capture: 15% sell-through = ~$16M ARR. Y3 $48M. Y5 $82M.

FTC native-advertising disclosure rules require clear "sponsored" labeling on each mission card. UX accommodates without breaking the professional voice. Brand-safety: a Hauler injured during a sponsored mission creates liability. Mission design avoids time-pressure framings ("get to Pilot in 30 minutes" — never).

## Chapter 37 — EusoTrip Network data resale

Every Hauler running The Haul is a sensor: confirming whether a truck-stop entry ramp is passable in winter, whether a weigh station is open, whether a Pilot's diesel lane is backed up, whether a bridge-strike-prone overpass actually clears 13'6". These confirmations are micro-tasks worth 50 datapoints/day per Hauler.

Pricing: $0.01 (commodity confirmations) to $0.10 (premium data). Blended $0.05/datapoint. Y1: 500K datapoints/day × $0.05 = $25K/day = $9.1M ARR. Y3: $57M. Y5: $80M.

Buyer mix: HERE Technologies 40%, FreightWaves 20%, shippers 20%, brokers 10%, OEMs/insurance 10%. *Driver consent must be explicit and feel like a perk, not an extraction.* Each Hauler opts in via "Earn cosmetics by becoming a Network Sensor" framing.

## Chapter 38 — Hauler Plus subscription

$9.99/month, $107.89/yr (one-month-free annual prepay). Conversion: 15% Y1 ramping to 22% Y5. Y1: 1,500 subs × $107.88 = $180K. Y3: $1.18M. Y5: $4.36M.

Carrier-sponsored employee subscriptions: $7.99/seat/mo for fleets buying 50+ seats. 5% capture of W-2 carrier population (Schneider, Werner, U.S. Xpress, Knight-Swift): 3,500 sponsored subscriptions = $336K ARR.

Benefits: priority queue on hot loads (90 seconds early), exclusive Chrome Stack cosmetic line, advanced analytics (per-lane profitability, fuel-burn-vs-revenue ratios), personalized lane recommendations, Plus-only "Convoy" channel.

**Cannibalization risk:** If priority-queue access materially disadvantages free-tier Haulers, regulators may construe as discriminatory dispatching. Priority window must be narrow and disclosed.

## Chapter 39 — Carrier/Broker/Shipper engagement-score SaaS

Productize the engagement telemetry as a B2B SaaS dashboard. Pricing:
- SMB (<50 trucks): $99/seat/month × 12 = $1,188/seat/yr
- Mid-market (50–500): $499/month flat per fleet = $5,988/yr
- Enterprise (>500): $25K–$120K/yr ACV
- Insurance partners: $2/driver/month for low-risk cohort feed

Y1: 200 SMB × $1,188 + 40 mid × $5,988 + 5 enterprise × $60K + 2 insurance × $50K = $878K. Y3: $4.6M. Y5: $17M.

Cohort sizes must be ≥30 drivers for any fleet-level metric (CCPA / BIPA / proposed FMCSA Driver Data Rule).

**Consolidated five-year stack:**

| Lever | Y1 | Y3 | Y5 |
|---|---|---|---|
| Engagement → Take Rate | $3.6M | $12.6M | $36.0M |
| Sponsored Missions | $16.4M | $48.0M | $82.0M |
| Network Data Feedback | $9.1M | $57.0M | $80.0M |
| Hauler Plus | $0.18M | $1.18M | $4.36M |
| Engagement Score SaaS | $0.88M | $4.60M | $17.0M |
| **TOTAL** | **$30.2M** | **$123.4M** | **$219.4M** |

Blended gross margins Y1 ~91%, Y5 ~80%. Each Hauler is amortized across five revenue lines, not one. This is the structural advantage over single-revenue-line competitors.

---

# PART IX — UX & Visual Language (inside Eusoboards)

## Chapter 40 — The Haul tab anatomy

The Haul lives behind a single tab in Eusoboards' bottom bar (icon: a stylized recognition crate with a gradient ring, 24×24pt). Selecting the tab pushes a NavigationStack whose root is `HaulHomeView` at screen 060.0.

| Screen # | Name | SwiftUI primitive | Purpose |
|---|---|---|---|
| 060.0 | HaulHome | NavigationStack + ScrollView | Today's Mission digest, daily Streak, Standing Points balance |
| 060.1 | HaulMissions | List with custom cells | All available Missions, filterable by tier/lane |
| 060.2 | HaulLobby | SceneKit-hosted UIViewRepresentable | 3D iso truck-stop with live drivers |
| 060.3 | HaulCrates | LazyVGrid(2-col) | Recognition crate locker — items, marks, Companion-bound cosmetics |
| 060.4 | HaulLeaderboard | Sectioned List | Lane-color-bucketed top Haulers, weekly + lifetime |
| 060.5 | HaulProfile | ScrollView with sticky header | Hero-flex page |
| 060.6 | HaulOnboarding | TabView .page | First-run pager, 4 cards, skippable on card 2+ |

**HaulHome layout (iPhone 15 Pro reference, 393×852pt, safe-area inset 59pt top + 34pt bottom):**

- **EusoHeader** pinned, height 88pt. Title "The Haul" in `.title2.weight(.heavy)`, gradient fill `LinearGradient(colors: [.eusoRed, .eusoMagenta], startPoint: .leading, endPoint: .trailing)`. Trailing slot: `EusoBadge(rebirth: user.rebirthCount, lane: user.laneColor)` at 28pt.
- **Standing capsule** at y=96, x=16, full-width minus 32pt margins. Background: `Material.ultraThin` over the gradient stripe. Left: Standing-Point glyph 32pt, right-aligned balance in `.largeTitle.monospacedDigit()`. Below, hairline progress bar showing weekly Miles Earned progress.
- **Daily Streak strip** at y=176, height 72pt. Horizontal scroll, 7 day-cells at 56×64 each. Today's cell is gradient-ringed; completed days are filled; future days are dashed. Today pulses (`scaleEffect 1.0 → 1.04`, 1.6s autoreverse).
- **Today's Featured Missions** at y=264. LazyVStack with 3 mission cards (Chapter 41). Each card 120pt tall, 16pt spacing.
- **Quick actions row** at the bottom of scroll, 4 64×64 tiles (Lobby, Recognition Crates, Leaderboard, Profile).

Gradient accents are reserved for moments of identity, status, or reward. **Never** apply to body text. The gradient is the brand's recognition signal.

## Chapter 41 — Mission card design

The mission card is the single most-rendered atom in The Haul. Card frame: 361×120pt, 20pt corner radius, `Material.regular` background.

- **Difficulty gradient ring** — 2pt stroke. Standard solid gray, Pro green, Veteran blue, Master gradient purple→magenta animated, Legendary gold angular gradient (8s cycle), Mythic iridescent shader (12s cycle, 4×4 mesh control points).
- **Lane stripe** — 4pt-wide vertical bar pinned to the leading edge inside the ring, colored to the load's origin-Lane.
- **Title row** — 16pt leading offset. Title `.headline`, max 1 line, truncating tail. Subtitle `.subheadline.foregroundStyle(.secondary)`.
- **Stats row** at y=68. Three pills, 24pt tall each. Distance ("420 mi"), ETA ("6h 15m"), Tier label ("VETERAN").
- **Reward preview slot** — Right side, 80×80pt. **Hidden by default**: silhouette of a crate with a "?" overlay. After accept, the silhouette flips (Y-axis 180°, 600ms spring) to reveal the actual recognition icon and Standing Point amount. Server signs the envelope; client decrypts only on accept.
- **Accept button** — 44pt × 120pt, trailing-bottom. Text: "Accept" for Standard/Pro, "Hold to Accept" for Veteran+, with circular progress fill completing at 1.2s of long-press for Master/Mythic. Mis-tap prevention is the explicit goal.

The anticipation loop: tier ring tells the **floor**, the silhouette hides which specific item dropped. Reward is rolled the instant the user accepts; silhouette dissolves; actual icon spirals in from below the card with 60° rotation correction.

```swift
.gesture(
    LongPressGesture(minimumDuration: tier.holdDuration)
        .onEnded { _ in acceptMission() }
)
// holdDuration: Standard 0s, Pro 0s, Veteran 0.4s, Master 0.8s, Master+Mythic 1.2s + double-confirm sheet
```

Reduce-Motion fallback: no tier ring rotation (static gradient). Silhouette flip becomes 200ms cross-dissolve. Spiral-in becomes 150ms opacity fade. Hold-to-accept still works as a safety affordance.

## Chapter 42 — Recognition Reveal animation — the "Red Box" moment, professionalized

The 1.2-second sequence — the most ceremonial moment in The Haul:

- **0–80ms anticipation hold.** Screen darkens to 75% black. Subtle 40Hz rumble via `CHHapticEngine` (60ms). No visual yet beyond the dim. The PSO equivalent: the drop sound that played a quarter-second before the box appeared.
- **80–280ms gradient ring spin-up.** From the center, a 4pt-stroke ring expands 0 → 220pt over 200ms with `.spring(response: 0.28, damping: 0.82)`. Ring spins clockwise at 720°/s, decelerating to 90°/s by frame 280.
- **280–520ms Standing-Point burst.** Ring center fills with the Standing-Point glyph at 64pt. Splits into N particles where N = `min(reward.standingPoints / 10, 24)`. Particles fly outward 360° fan, decelerating into circular orbit at 110pt radius. 240ms ease-out-cubic.
- **520–720ms the box.** A red recognition crate appears at the ring center. Scale 0 → 1.15 → 1.0 with spring 0.36/0.68. Soft white inner glow. At 700ms, `.notification(.success)` haptic fires.
- **720–960ms reveal.** Crate lid hinges open (3D rotation, X-axis 0 → -110°). The recognition emerges with scale 0.6 → 1.0 and slight Y-axis bob. Legendary or Mythic: additional particle burst (gold or iridescent), second `.success` haptic chains 80ms after.
- **960–1200ms settle and label.** Text label: "[Item Name] — [Tier]". 240ms fade-in. Dim layer lifts. 1200ms tap-anywhere dismiss; auto-dismiss at 4500ms.

Sound: low rumble synth at 0–80ms. Single chime (C5→G5 glissando, 180ms) at 280ms. For Legendary+: layered chord (C5+E5+G5+B5). Box "thunk" at 520ms. Lid creak + reveal sparkle at 720ms.

Haptic chain (Legendary):
```swift
hapticEngine.play([
  .continuous(intensity: 0.4, sharpness: 0.2, duration: 0.06, at: 0.00),
  .transient(intensity: 0.8, sharpness: 0.6, at: 0.28),
  .transient(intensity: 1.0, sharpness: 1.0, at: 0.72),
  .transient(intensity: 1.0, sharpness: 0.8, at: 0.80),
])
```

The dual-tap haptic at 720/800ms is the somatic signature of a high-tier recognition. Drivers learn it within 3–4 reveals and start to feel anticipation between the first and second tap — exactly the way PSO trained players to recognize the red-box drop sound mid-fight before they even saw the box.

Reduce-Motion fallback (mandatory): single 400ms cross-dissolve. Screen dims (75% black) for 200ms, then a centered card fades in showing the recognition icon, name, tier, and Standing Point amount. No particles, no ring spin, no box flip. Haptic and sound still fire.

## Chapter 43 — Lobby 3D iso-view at the truck stop

(See Chapter 20 for the canonical Lobby spec — this chapter is the UX layer on top of the architectural one.)

The bottom-screen UI overlay on the SceneKit/RealityKit view:

- **EusoHeader** semi-transparent black, 88pt. Gradient title "Lobby — \(currentPOI.name)". POI name updates as the Hauler travels.
- **Player roster strip** at the bottom, 96pt tall, horizontal-scrollable list of mini-avatars (32pt EusoBadges). Tap an entry, camera dollies-toward-tapped-avatar over 320ms with `.spring(response: 0.42, damping: 0.78)`, the MiniCardSheet slides up (380pt tall, 28pt corner radius top-only).
- **Floating action cluster** bottom-right, 56pt circle, gradient. Long-press opens a radial menu: /wave, /trade, /sit, /coffee.
- **Sector pill** top-right, shows current Block. If full, a "Block 2" tap-to-switch chip.

LOD strategy: LOD0 (full detail, ~2k tris) for the nearest 6 avatars. LOD1 (~800 tris) for the next 8. LOD2 (~200 tris) for the remaining. Beyond 20 → 2D sprite fallback.

Camera dolly to tapped avatar 320ms spring. Avatar animation cross-fade 200ms. Mini-card sheet present 380ms `.spring(response: 0.45, damping: 0.85)`. /wave: 1.4s wave animation; small floating "wave!" emoji above the head with 600ms scale-up + 400ms fade-out.

Reduce-Motion: camera does not dolly (cuts directly). Avatar idle animations remain (motion is the avatar's identity, not the UI's transition). Mini-card sheet fade 200ms.

The motion-sickness toggle is independent of system Reduce Motion: Settings → Haul → "Reduce Camera Motion" pins the camera and disables dolly.

## Chapter 44 — Profile flex page

The profile is The Haul's flex page — the "show off your hunter" surface borrowed wholesale from PSO's character-status screen. Intentionally maximalist. Where most of Eusoboards' UI is restrained and functional, the profile is permitted to be peacock-loud — the only screen in the app where the gradient, the shimmer, the particles converge on a single subject: the Hauler.

**Hero header (sticky, 0–360pt):**
- Hero EusoBadge at center, 200×200pt at scroll-top, scaling to 96pt on scroll (parallax driven by `GeometryReader`).
- Background: full-bleed `LinearGradient` keyed to the Hauler's Lane Color, at 90° (top→bottom).
- Rebirth count below the badge, 32pt monospaced. Each Rebirth cycle adds a glowing ring around the badge; up to 5 rings visible, 6th+ consolidates into a single "5+" gold pip.
- Lane Color stripe 8pt vertical bar pinned to leading edge, full-height of the hero.

**Mark case (360–800pt):** "Mark Case" header in `.title3.weight(.bold)`, with a chip showing "\(unlockedCount)/\(totalCount)" trailing. LazyVGrid of 64×64pt mark cells, 4 per row, 12pt spacing. Each cell rounded rect 16pt corner, `Material.thin` background. **Mythic marks get an iridescent shimmer overlay**: a `MeshGradient` running 12s/cycle through pink/gold/cyan/violet, masked to the mark silhouette. This is the visual analog of PSO's rare-shield glow — passive flex visible from across a chat thread.

**Lifetime stats (800–1200pt):** Six stat cards in 2-col `LazyVGrid`, each 168×96pt, `Material.regular`, 20pt corner. Stats: Total miles, Total loads, Total Standing Points earned, Best streak, Mythic recognitions, Trade reputation. Best Streak card pulses if current streak ties or breaks the lifetime record (subtle 1pt outline pulse, 1.6s autoreverse).

**Recent missions log (1200pt+):** Last 10 completed missions, condensed cell variant of the mission card (72pt instead of 120pt).

**Share-to-lobby flow:** Share button pinned to the trailing edge of the hero header (32pt SF Symbol `square.and.arrow.up`, gradient-tinted). Generates a 1080×1920 social card via `ImageRenderer<HaulFlexCard>`. One-tap post to current lobby (visible to all 19 other drivers in the Block as a chat-message card). Save to Photos. Share via system share sheet.

The flex psychology: the dopamine here is **status conferred by visible work**. Every element on the profile is something the Hauler did — miles driven, missions completed, Rebirth cycles burned, marks unlocked. Nothing is purchasable. The screen is loud because the work was loud, and the visibility of the work motivates the next mission.

## Chapter 45 — Pulse watch surface

The Pulse watch is a first-class surface for The Haul. Three contexts, three screens:

**Context 1: Missions in flight.** During IN_PROGRESS, the watch face displays:
- Top: archetype icon + tier color band (Standard blue, Pro green, Veteran orange, Master red).
- Middle: linear progress bar (% to ETA, not % to deadline — these differ).
- Bottom: next checkpoint label + time-to-deadline countdown.

The progress bar uses EusoTrip Network routing recompute every 5 minutes to update ETA. Traffic, weather, and HOS-clock-remaining all factor.

**Context 2: Recognition pending claim.** When a Mission completes (POD signed) and a recognition rolled, the watch vibrates once (40Hz, 60ms continuous), shows the recognition silhouette and tier band, and surfaces a "Claim at next safe stop" prompt. The actual reveal animation fires when the Hauler next opens the Haul tab on the phone — preserving the post-mission ceremony.

**Context 3: Lobby presence.** When the watch detects truck-stop dwell ≥90 seconds and the Hauler is opted into the lobby, a small lobby pip appears on the watch face. Tap for one-line driver count and emote-wheel access (rotation crown selects `/wave`, `/coffee`, `/sit`). The full lobby experience is on the phone; the watch is the lightweight presence-and-emote surface.

The watch is HOS-aware throughout. If the Hauler is approaching an HOS limit (within 30 minutes), the in-flight surface pivots to a "rest recommendation" card with the next Verified Safe Lane parking option. The recommendation never blocks driving — it surfaces and respects the Hauler's autonomy.

---

# PART X — Engineering Specifications

## Chapter 46 — Backend wiring map

This is the procedure-by-procedure binding between the doctrine and the running code. Every left-column reference is the literal grep-able procedure in the `eusotrip` repo at the line numbers shown; every right-column reference is the doctrine chapter the procedure implements. Engineering can read this chapter as a build sheet: any chapter that is *not* satisfied by an existing procedure is an implementation gap and is captured in Appendix F.

**Existing procedures in `frontend/server/routers/gamification.ts` (1,871 lines, exporting `gamificationRouter`):**

| Line | Procedure | Doctrine chapter binding |
|---|---|---|
| 71 | `create` | Reward bookkeeping for Chapter 11 (functional rewards) and Chapter 12 (cash bonuses). Insert into `rewards` with `type`, `rewardType`, `amount`, `status='pending'`. |
| 94 | `update` | Reward state transitions (`pending→claimed→expired`). Used by Chapter 7 mission state machine on REWARDED → CLOSED. |
| 112 | `delete` | Soft-delete via `status='expired'`. Used by Chapter 7 abandon path. |
| 123 | `getProfile` | Returns the Standing/Class/Lane snapshot for Chapter 15 + Chapter 18. |
| 215 | `getAchievements` | Marks list (Chapter 10 cosmetic recognitions). Reads from `userBadges` joined to `badges`. |
| 294 | `getLeaderboard` | Chapter 18 lobby leaderboard (Lane-Color-bucketed). |
| 377 | `getRewardsCatalog` | The published recognition catalog for Chapter 8 preview cards (regulatory firewall). |
| 403 | `redeemReward` | Cosmetic and fee-discount redemption. |
| 472 | `getPointsHistory` | The Standing Points ledger for the profile screen (Chapter 44). |
| 522 | `getChallenges` | Daily archetype rotation (Chapter 5 archetype 12). |
| 528 | `getBadges` | Mark catalog read. |
| 570 | `updateDisplayBadges` | Chapter 44 mark-case pinning. |
| 586 | `getTeamStats` | Crew/Convoy aggregate (Chapter 24). |
| 607 | `getMyAchievements` | Driver's own marks (Chapter 44). |
| 631 | `getStats` | Lifetime stats for the profile hero stats grid. |
| 679 | `getMissions` | Chapter 5 mission listing. Has the `templateFallback` graceful-degradation path (line 39) for when the DB is empty — generates from in-memory templates. |
| 810 | `startMission` | Chapter 7 ACCEPTED → IN_PROGRESS. |
| 880 | `claimMissionReward` | Chapter 7 COMPLETED → REWARDED. Triggers the recognition-crate roll. |
| 1001 | `cancelMission` | Chapter 7 ACCEPTED → ABANDONED. |
| 1039 | `getCrates` | Recognition crate inventory for Chapter 10. |
| 1066 | `openCrate` | Crate reveal; triggers the Chapter 42 animation. |
| 1158 | `getCurrentSeason` | Seasonal event state (Chapter 23). |
| 1189 | `createMission` (admin) | Mission catalog admin authoring. |
| 1234 | `createBadge` (admin) | Mark catalog admin authoring. |
| 1272 | `getLobbyMessages` | Chapter 21 lobby chat read. |
| 1331 | `postLobbyMessage` | Chapter 21 lobby chat write, with `moderateMessage` from `frontend/server/services/lobbyModeration.ts` and `getStrikeAction` enforcing the rate-limit and toxicity floors. |
| 1487 | `getAIMissions` | Companion-suggested mission feed (Chapter 13). |
| 1585 | `awardBadge` (admin) | Manual mark grants for ops adjustments. |
| 1634 | `purchaseItem` | Marketplace purchase (Chapter 22). |
| 1666 | `getActiveTripMissions` | Watch-surface active mission lookup (Chapter 45). |
| 1678 | `refreshMissions` | Mission Board NPC inventory rotation (Chapter 8). |
| 1693 | `getInventory` | Cosmetic/marketplace inventory read. |
| 1715 | `getModerationLog` (admin) | Trust & Safety log read. |
| 1762 | `reviewModerationLog` (admin) | T&S adjudication. |
| 1806 | `getUserStrikes` (admin) | Strike inspection. |
| 1841 | `unbanUser` (admin) | Ban appeal release. |

**Existing procedures in `frontend/server/routers/advancedGamification.ts` (exporting `advancedGamificationRouter`):**

| Line | Procedure | Doctrine binding |
|---|---|---|
| 334 | `getGuilds` | Chapter 24 Crew/Convoy registry. |
| 366 | `getGuildDetails` | Crew detail. |
| 432 | `createGuild` | Crew creation. |
| 504 | `joinGuild` | Crew join. |
| 550 | `getGuildLeaderboard` | Crew leaderboard. |
| 571 | `getGuildChallenges` | Crew co-op missions. |
| 637 | `getPrestigeSystem` | Chapter 19 Eight Lights state. |
| 675 | `getPrestigeRewards` | Rebirth permanent buffs catalog. |
| 686 | `activatePrestige` | Rebirth ritual. |
| 749 | `getRewardsStore` | Marketplace listings (Chapter 22). |
| 796 | `purchaseReward` | Marketplace purchase. |
| 859 | `getRewardsPurchaseHistory` | Marketplace history. |
| 890 | `getSeasonalEvents` | Chapter 23 calendar. |
| 899 | `getSeasonalProgress` | Per-driver seasonal progress. |
| 964 | `getSeasonalRewards` | Seasonal cosmetic catalog. |
| 979 | `getTournaments` | Race/Arena leaderboard events (Chapter 5 archetype 8 and 11). |
| 1037 | `getTournamentBracket` | Brackets. |
| 1090 | `joinTournament` | Tournament entry. |
| 1166 | `getAchievements` | Mark catalog (advanced). |
| 1204 | `getAchievementProgress` | Per-mark progress. |
| 1215 | `getRareAchievements` | Verified Recognition catalog. |
| 1227 | `getDailyQuests` | Chapter 5 archetype 12. |
| 1311 | `completeDailyQuest` | Daily completion. |
| 1387 | `getWeeklyMissions` | Weekly archetype rotation. |
| 1476 | `getStreakTracker` | Chapter 12 streak state read. |
| 1548 | `getSocialFeed` | Lobby and BOL Stamp feed. |
| 1616 | `getDriverProfile` | Other-Hauler profile inspection (Chapter 21 long-press). |
| 1786 | `getCustomizationOptions` | Cosmetic customization read. |
| 1794 | `equipCustomization` | Cosmetic equip. |
| 1817 | `getMilestones` | Lifetime mark progress. |
| 1839 | `getLeaderboardHistory` | Historical leaderboards. |

**Supporting services (already in the codebase):**
- `frontend/server/services/missionGenerator.ts` — `pickWeeklyMissions`, `getRewardsCatalogForRole`, `generateWeeklyMissions`, `forceRotateMissions`. The template-fallback engine that generates Mission inventory when the DB pool is empty.
- `frontend/server/services/gamificationDispatcher.ts` — `fireGamificationEvent`. The single-entry-point dispatcher for load-lifecycle → mission-state events.
- `frontend/server/services/hosEngine.ts` — `canDriverAcceptLoad`. The HOS-aware mission gate (Chapter 54 — engineering must wire this in front of every `acceptMission` call).
- `frontend/server/services/lobbyModeration.ts` — `moderateMessage`, `getStrikeAction`. The lobby-chat AML/toxicity moderation.
- `frontend/server/_core/websocket.ts` — `emitGamificationEvent`, `emitNotification`, `WS_EVENTS`. The realtime fanout pipe.

**Implementation gaps (engineering work captured in Appendix F):**
- `checkpointMission`, `failMission`, `disputeMission` — Chapter 7 state-machine completions.
- `proposeTrade`, `confirmTrade` — Chapter 14 cosmetic-to-cosmetic trading flow.
- `bolStampRouter` (or `gamificationRouter.generateBOLStamp`) — Chapter 21 share-card auto-generation.
- `pityState` table + `getPityState` — Chapter 10 transparency exposure.
- `companionRouter` — Chapter 13 ESANG Companion evolution + persona feeding.

## Chapter 47 — Database schema (existing tables + additions needed)

**Existing tables (confirmed via INFORMATION_SCHEMA query, 2026-04-27):**

- `gamification_profiles` — 18 columns. Columns: `id`, `userId`, `level`, `currentXp`, `totalXp`, `xpToNextLevel`, `totalMilesEarned`, `currentMiles`, `activeTitle`, `rank`, `streakDays`, `longestStreak`, `lastActivityAt`, `seasonalRank`, `seasonalXp`, `stats` (JSON), `createdAt`, `updatedAt`. **This is the canonical Hauler-progression table.** Engineering must extend it with the columns from Chapter 15 (`classTier`, `classTierAchievedAt`, `tenureMonthsSnapshot`, `verifiedPlatformMiles`, `mvrCleanWindowDays`, `skillMissionsCompleted`, `inspectionCompletionPct`, `hosViolations12mo`, `onTimeDeliveryPct`, `classTierPendingReason`), Chapter 16 (`primarySpecialization`, `altSpecialization`, `primarySpecMasteryLevel`, `altSpecMasteryLevel`, `lastPrimaryRespecAt`, `lastAltRespecAt`, `specEndorsementsVerified`), Chapter 17 (`dailyXpEarnedUtc`, `dailyXpResetAt`, `rookieProtectionUntil`, `lobbyCoopMultiplier`), Chapter 18 (`laneColor`, `laneColorAssignedAt`, `homeBaseZip`, `homeBaseChangePendingUntil`, `crossLanePollinationBonusPct`), and Chapter 19 (`rebirthTier`, `rebirthCount`, `lastRebirthAt`, `permanentXpBuffPct`, `eighthLightHostingTokens`, `eighthLightMissionsHosted`).

- `missions` — 24 columns. Canonical Mission catalog. Has `code`, `name`, `description`, `type` (enum), `category` (enum), `targetType` (enum), `targetValue`, `targetUnit`, `requirements` (JSON), `rewardType` (enum), `rewardValue`, `rewardData` (JSON), `xpReward`, `cooldownHours`, `maxCompletions`, `applicableRoles` (JSON), `seasonId`, `sortOrder`, `isActive`, `startsAt`, `endsAt`. **This is canonical for Chapters 5–8.** The twelve archetypes seed into `type`; the four tiers seed into `category` (or a new `tier` enum column to be added).

- `mission_progress` — 14 columns. Per-driver mission state. Has `userId`, `missionId`, `currentProgress`, `targetProgress`, `status` (enum), `completionCount`, `lastProgressAt`, `completedAt`, `claimedAt`, `expiresAt`, `metadata` (JSON). **This is canonical for Chapter 7.** The eight states (AVAILABLE, ACCEPTED, IN_PROGRESS, CHECKPOINT, COMPLETED, REWARDED, CLOSED, ABANDONED, FAILED, DISPUTED) must be added to the `status` enum.

- `badges` — 14 columns. The Mark catalog. Has `code`, `name`, `description`, `category` (enum), `tier` (enum), `iconUrl`, `criteria` (JSON), `xpValue`, `isRare`, `sortOrder`, `isActive`. **This is canonical for Chapter 10.**

- `user_badges` — 7 columns. Mark grants. Has `userId`, `badgeId`, `earnedAt`, `displayOrder`, `isDisplayed`, `metadata` (JSON). Canonical for Chapter 44 Mark Case.

- `loot_crates` — 9 columns. Recognition crates. Has `userId`, `tier` (enum), `source`, `sourceReferenceId`, `contentsJson` (JSON), `isOpened`, `openedAt`, `expiresAt`. Canonical for Chapter 10. Note: the table name is the legacy "loot_crates" — engineering should keep the table name in the database for migration ease, but **never** surface "loot" in driver-facing copy. Internal docs name this "Recognition Crates."

- `reward_crates` — 9 columns. Alternate crate path (likely seasonal/event variant). Has `crateType` (enum), `source`, `sourceId`, `status` (enum), `contents` (JSON). Reconcile with `loot_crates` in Sprint 1.

- `rewards` — 11 columns. The cash/Standing-Point/cosmetic reward ledger. Has `type` (enum: `mission_completion`, `badge_earned`, `level_up`, `crate_opened`, `referral`, `achievement`, `seasonal`, `bonus`), `sourceType`, `sourceId`, `rewardType` (enum: `miles`, `cash`, `xp`, `badge`, `title`, `fee_reduction`, `priority_perk`, `crate`), `amount`, `description`, `status` (enum: `pending`, `claimed`, `expired`), `claimedAt`, `expiresAt`, `metadata` (JSON). Canonical for the unified reward audit log.

- `haul_lobby_messages` — 8 columns. Lobby chat. Has `userId`, `userName`, `userRole`, `message`, `messageType` (enum), `isDeleted`, `isPinned`. Canonical for Chapter 21.

- `haul_lobby_moderation_log` — exists per the table dump; canonical for Chapter 21 Trust & Safety review.

- `haul_lobby_user_strikes` — exists; canonical for the three-strike harassment policy.

- `esang_memories` — 14 columns. The ESANG Companion's narrative memory store. Has `user_id`, `content`, `category` (enum), `critical`, `embedding` (JSON), `dimensions`, `token_count`, `access_count`, `source_conversation_id`, `metadata`. Canonical for Chapter 13's voice continuity.

**Tables to add (Sprint 1 schema work):**

- `cosmetic_items` — `(item_id PK, family enum, tier enum, drop_weight_bp int, global_supply_cap int NULL, bound_to_kyc bool default true, created_at, retired_at)`. Chapter 10.
- `drop_events` — `(event_id UUID PK, driver_id, trigger enum, rolled_item_id, rolled_tier, rng_seed BIGINT, rolled_at, client_ack_at)`. Chapter 10 audit trail; rng_seed reproducibility for regulatory review.
- `pity_state` — `(driver_id, tier, rarity_class, dryspell_count)`. Chapter 10.
- `streak_state` — `(driver_id PK, current_streak_days, last_qualifying_day, freezes_used_quarter, freezes_used_year, longest_streak_ever)`. Chapter 12.
- `cash_rewards` — `(reward_id, driver_id, reward_type enum, amount_usd_cents, triggered_by, paid_at, ledger_entry_id, created_at)`. Chapter 12.
- `cosmetic_inventory` — `(inventory_id, driver_id, item_id, acquired_via enum, acquired_at, soulbound bool, soulbound_at, escrow_until, flag_status enum)`. Chapter 14.
- `cosmetic_trades` — `(trade_id, party_a_driver_id, party_b_driver_id, party_a_item_id, party_b_item_id, initiated_at, escrow_release_at, status enum, lobby_id, ip_a, ip_b)`. Chapter 14.
- `carrier_cosmetic_sponsorships` — `(sponsorship_id, carrier_id, pack_id, driver_count, total_cost_usd, granted_at, invoice_id)`. Chapter 14.
- `esang_companion` — `(driver_id PK, current_level, current_stage, current_persona enum, persona_locked_until, active_orb_skin, active_voice_pack, total_feeding_xp, evolved_at, created_at)`. Chapter 13.
- `esang_feeding_history` — `(feeding_id, driver_id, mission_id, mission_category, xp_fed, fed_at)`. Chapter 13.
- `geofences` — `(zone_id PK, type, polygon GEOJSON, active_from, active_to, attributes JSON)`. Chapters 25, 26, 28, 29.
- `lobby_zone_progress` — `(driver_id, zone_id, dwell_minutes, decayed_at)`. Chapter 26 capture.

## Chapter 48 — Mission triggers (load-event subscriptions, geofence webhooks)

The dispatcher pattern. The `gamificationDispatcher` service subscribes to a fixed set of upstream events and routes each to the appropriate gamification procedure. The full subscription map:

| Upstream event | Source router | Dispatcher handler | Downstream procedure |
|---|---|---|---|
| `load.posted` | `loads.ts` | `enrichLoadAsMission` | `gamificationRouter.refreshMissions` (line 1678), classifies to archetype + tier, writes `missions` row |
| `load.accepted` | `loads.ts` | `startMissionForLoad` | `gamificationRouter.startMission` (line 810) |
| `load.in_transit` | `loadLifecycle.ts` | `markInProgress` | mission_progress.status='in_progress' |
| `load.checkpoint.geofence_entered` | `loadLifecycle.ts` | `awardCheckpoint` | `gamificationRouter.checkpointMission` (gap — Sprint 2) |
| `load.bol.signed` | `loadLifecycle.ts` | `generateBolStamp` | `bolStampRouter.generate` (gap — Sprint 2) |
| `load.pod.signed` | `loadLifecycle.ts` | `completeMissionAndRoll` | `gamificationRouter.claimMissionReward` (line 880); rolls drops via Chapter 10 logic |
| `load.settled` | `factoring.ts`, `wallet.ts` | `settleRewards` | applies fee discount; re-evaluates factoring tier; payout cash bonuses |
| `load.dispute.opened` | `loadLifecycle.ts` | `freezeMission` | `gamificationRouter.disputeMission` (gap — Sprint 2) |
| `load.dispute.resolved` | `loadLifecycle.ts` | `unfreezeOrFail` | back to REWARDED or to FAILED |
| `geofence.surge_zone.entered` | `hotZones.ts` | `evaluateSurgeSpawn` | spawns Surge Mission per Chapter 25 rules |
| `geofence.hot_zone.dwell_aggregated` | `hotZones.ts` | `evaluateCapture` | fires Crew capture buff per Chapter 26 |
| `geofence.truck_stop.entered_dwell_5min` | location service | `unlockMicroMissions` | shows Chapter 27 menu |
| `geofence.border.approach_polygon_entered` | `crossBorder` service | `openBorderRunCard` | Chapter 28 |
| `crisis.fema_polygon.driver_eligible` | `crisis-svc` | `offerCrisisMission` | Chapter 29 |
| `pulse.fatigue_score.crossed_threshold` | Pulse Health service | `evaluateFatigueGate` | Chapter 54 lockout |
| `hos.violation.detected` | ELD compliance service | `forfeitBonusesAndStreak` | invariant: bonuses zero, streak breaks |

Each handler logs to an audit table `gamification_event_log` with full input payload, decision, and downstream effect, retained 7 years per Chapter 52 governance.

## Chapter 49 — APIs to add

The Sprint-by-Sprint API list. Each row is the procedure to add, the router it lives in, and the doctrine chapter it implements.

| Sprint | Procedure | Router | Chapter |
|---|---|---|---|
| 1 | `getDropTablesPublic` | `gamificationRouter` | 10 — public, no auth, the regulatory firewall |
| 1 | `getPityState` | `gamificationRouter` | 10 — driver-facing pity counter exposure |
| 1 | `getStreakState` + `freezeStreak` | `gamificationRouter` | 12 — humane freeze invocation |
| 2 | `checkpointMission` | `gamificationRouter` | 7 |
| 2 | `failMission` | `gamificationRouter` | 7 (system-triggered only, gated by HOS engine) |
| 2 | `disputeMission` | `gamificationRouter` | 7 |
| 2 | `generateBolStamp` | new `bolStampRouter` | 21 |
| 3 | `proposeTrade` + `confirmTrade` | `advancedGamificationRouter` | 14 |
| 3 | `flagLaunderingPattern` (system-only) | `advancedGamificationRouter` | 14 |
| 3 | `getCompanion` + `feedCompanion` (event-driven) + `respecCompanionPersona` | new `companionRouter` | 13 |
| 4 | `getCrisisMissions` + `optInCrisis` + `acceptCrisis` | new `crisisRouter` | 29 |
| 4 | `getBorderRunCard` | new `borderRunRouter` | 28 |
| 5 | `getCrossModeLobby` + `crossModeHail` + `multiModalHandoff` | `advancedGamificationRouter` | 24 |

## Chapter 50 — iOS implementation primitives

The SwiftUI / Swift Package primitives that engineering should already have (or build first):

- **`EusoBadge`** — the canonical identity primitive. Three sizes: `.small` (20pt), `.medium` (28pt), `.hero` (96pt). Composites Lane-color base ring + photo or monogram + Rebirth subscript + optional Mythic shimmer overlay. Used everywhere from message lists to the profile hero.
- **`EusoHeader`** — standardized 88pt (132pt with subtitle). Brand gradient title fade-on-scroll (60% opacity at-rest, 100% at-scrollEdge). Leading slot 24pt back-chevron, trailing slot for `EusoBadge` or sector pill.
- **`MissionCardView`** — the 361×120pt card from Chapter 41. Conforms to `Mission` model exposing `tier: MissionTier`, `lane: LaneColor`, `revealedReward: RewardEnvelope?`. Tier ring uses a custom `MissionTierShape` stroked with the tier-appropriate gradient. Mythic wraps in iOS 18 `MeshGradient` inside a `Canvas` for performance.
- **`RewardOverlayPresenter`** — environment object so any 060.x screen can trigger the Chapter 42 reveal without re-implementing.
- **`HaulLobbyView`** — `SceneKit` (iOS 16) or `RealityKit` (iOS 17+) iso-camera 3D scene. Avatar mesh is a single shared skeleton with per-driver texture+accessory layering.
- **`PulseWatchSurface`** — three context views (in-flight, recognition-pending, lobby-presence). Driven by `WCSession` from the phone with explicit minimal payloads (no full mission state on the watch — only what the watch needs to render).
- **`HaulFlexCard`** — the 1080×1920 share card via `ImageRenderer` (iOS 16+).
- **`LongPressGesture` + progress ring** — the mis-tap-prevention accept gesture from Chapter 41.

The build order from Chapter 41:
1. **Sprint 1:** Screens 060.0 + 060.5 (the static surfaces, validates `EusoHeader`, `EusoBadge`, gradient tokens).
2. **Sprint 2:** Screen 060.1 + reward overlay (the core loop — accept and complete).
3. **Sprint 3:** Screens 060.3 + 060.4 (recognition crates and leaderboard, content-heavy but mechanically simple).
4. **Sprint 4:** Screen 060.2 (Lobby 3D — highest risk, dedicated sprint).
5. **Sprint 5:** Polish — shimmer optimization, haptic tuning, share-card image renderer, Reduce-Motion paths, full accessibility audit.

Performance targets are from Chapters 20 and 41: 60fps on iPhone 12+, 100k triangles, 64MB texture, ≤80 draw calls, ≤4%/10min battery delta. iPhone 11 and below auto-downgrade to the 2D Lobby fallback.

---

# PART XI — Launch & Governance

## Chapter 51 — Phased launch (50 internal → pilot → regional → national → cross-border)

The Haul will not see a national US launch before it has run for at least 210 cumulative days in production-shaped environments with progressively larger driver populations. Phase progression is gated, not time-boxed: a phase ends only when its success criteria are met for two consecutive review periods, never by calendar.

**Phase 0 — Internal Closed Beta.** 50 internal Eusorone Haulers (W-2 employees of the pilot fleet, all CDL-A, all consenting in writing). Texas only, within 500 miles of HQ. **Cosmetic rewards only. No HaulPay cash earnings.** Surge Missions disabled. Lobby chat enabled with full moderation. 100% session recording. Mandatory daily 10-question driver survey. 30-day minimum, ends on two-consecutive-week success-criteria pass.

Success criteria (all must be met):
- Zero CSA recordable safety events causally linked to Haul activity.
- Crash-free user rate ≥ 99.5%.
- Mission accept-to-confirm latency ≤ 800ms p95, ≤ 1500ms p99.
- Driver NPS ≥ +30.
- HOS violation rate among Haul-active ≤ identical control cohort (must not exceed by even 0.1%).
- Zero loot-box / RNG complaints filed internally.

Kill criteria (any one triggers immediate phase termination):
- One or more recordable injuries causally linked to Haul.
- HOS violation rate among Haul cohort exceeds control by 5% relative.
- Crash-free below 98.0% for any 72-hour rolling window.
- Three or more drivers report compulsive engagement (>16 hour play day) within 14 days.
- Any regulatory inquiry from FMCSA, DOT, or state AG referencing Haul.

Rollback: feature flag `haul.global.enabled = false` flipped by VP Engineering. All cosmetic state preserved in HaulVault. Driver communications scripted in advance, sent within 4 hours of kill decision.

**Phase 1 — Pilot Carrier Beta.** 5 fleet partners, 500 total Haulers (mix of W-2 and 1099). 90 days minimum. South Central freight corridor (TX, LA, OK, AR). Cosmetic + first-tier HaulPay cash rewards capped at $250/month per Hauler. Surge Missions limited to 1/Hauler/week. Cross-fleet Lobby chat enabled. 100% mission logging, sampled session recording (10%), weekly survey, monthly fleet-manager interview.

Phase 1 success criteria add: 12-week driver retention ≥ 85%. 1099 reporting test (quarterly mock 1099-NEC reconciled to the penny). Anti-cheat false-positive rate <0.5%.

**Phase 2 — Regional Rollout (Texas + Louisiana).** Open to any CDL-A Hauler domiciled in TX or LA who passes KYC. Soft cap 25,000, hard cap 40,000. 120 days minimum. Full cosmetic, full HaulPay cash (no per-driver cap, but per-mission cap remains $5,000). Surge at full cadence. Lobby fully open. Regional leaderboards live.

Reasoning for TX+LA: highest CDL density in South Central, mature ELD adoption, both states W-2/1099-friendly, neither has loot-box-adjacent legislation pending, both have functioning state-level FMCSA enforcement to give early signal on regulatory tone.

**Phase 3 — National US.** All 50 states + DC. Soft cap removed. Expected steady-state 250,000–600,000 Haulers within 18 months. **Washington and Hawaii receive a feature-flag-gated subset (no randomized HaulPay cash drops even though we don't use loot boxes — extra cushion);** cash rewards in WA and HI are deterministic only.

**Phase 4 — Canada + Mexico (Cross-Border).** Prerequisites: 12 months stable Phase 3, written legal opinions from CA/MX outside counsel, FAST/C-TPAT compliance, currency conversion + tax treatment review for cross-border 1099/T4A/CFDI. Initial cap 10,000 Haulers, border corridors first (Laredo, El Paso, Detroit, Buffalo, Blaine), interior expansion after 180 days.

## Chapter 52 — Regulatory + legal (loot-box laws, IRS classifications, anti-trust)

**Loot-box and RNG posture (the core regulatory shield).** The Haul does not run loot boxes. This is a design constraint, not a marketing claim:
- All drop tables are public, machine-readable, versioned. Every Recognition shows its exact probability **before** the Hauler commits any action.
- No randomized recognition is purchasable for cash or for a virtual currency that is purchasable for cash.
- Recognition rarity is randomized only on outcomes from real driving work (e.g., complete a 1,000-mile mission with zero hard-brakes → 5% chance of a Legendary livery), never on a paid action.

Jurisdictional sign-off:
- **Belgium:** 2018 Gambling Commission opinion confirmed compliant — no in-app purchase of randomized items exists.
- **Netherlands:** Kansspelautoriteit ruling — same basis.
- **United Kingdom:** Gambling Commission position on skin-betting and loot boxes; we additionally implement DCMS voluntary principles. (Parental controls moot — all Haulers 21+.)
- **Australia:** Interactive Gambling Act and 2022 NSW position. Outside Australian counsel review filed.

App store posture statement (filed at submission, re-filed annually):
> "The Haul implements transparent drop tables, no-cash-RNG, all participants are CDL-licensed adults (21+), and all randomized outcomes are gated by real-world labor (driving work)."

US state matrix touchy states: **Washington** (RCW 9.46 "thing of value" — mitigation: WA-resident Haulers receive deterministic-only cash, all randomized are cosmetic). **Hawaii** (total prohibition — same mitigation). Utah, Idaho monitored quarterly.

**1099 / Tax classification (the unified reporting matrix):**
- 1099-NEC — load pay + mission completion bonuses (Chapter 30).
- 1099-MISC, Box 3 — streak rewards (Chapter 31), referral payouts (Chapter 32).
- 1099-K — marketplace earnings (Chapter 34, Stripe-issued).

Three forms maximum per Hauler per year. Canadian equivalent: T4A for residents, NR4 for non-residents. Mexican equivalent: CFDI version 4.0 emitted via authorized PAC.

**Driver classification (W-2 vs 1099) — critical defense:** The Haul is reward-neutral with respect to employment status. Haul rewards never modify, condition, or imply employment status. W-2 fleet drivers and 1099 owner-operators receive identical mission availability, identical drop tables, identical Surge cadence. The Haul does not direct the manner or means of work — it rewards already-completed work that was directed by the Hauler's own employer or self. Annual outside-labor-counsel opinion letter on file.

**Anti-trust.** All Haulers equal access. No preferential drop rates, no preferential mission availability, no preferential leaderboard treatment for fleet-owned Haulers vs owner-operators. Annual independent audit, findings published to Trust Center.

**Children's online safety.** The Haul has zero children. CDL-A issuance requires age 21 for interstate, 18 for intrastate. HaulPay cash earnings require 21+ across all jurisdictions. KYC enforces. Therefore COPPA does not apply; documented in Privacy Policy with legal basis cited.

## Chapter 53 — Anti-cheat + integrity

**Geofence spoofing detection.** Mission credit awarded only if EusoTrip Network position and ELD position agree to within 250 meters at every checkpoint AND the trajectory between checkpoints is physically plausible. Three disagreements > 250m within 30 days → manual review. Five → automatic 30-day Surge ban, restored after review.

**Multi-account abuse.** One Hauler, one CDL, one Haul account. CDL number hashed and indexed. Duplicate detection runs nightly. Confirmed multi-accounting → permanent ban from HaulPay cash rewards on all accounts, cosmetic reset, IRS reporting reconciled across all accounts (the most painful penalty).

**Power-leveling / referral fraud.** Weighted relationship graph (referral, shared addresses, shared phone numbers, shared bank routing, shared device fingerprints). Tight cluster (clustering coefficient > 0.6) of more than 3 accounts where referral bonuses flow inward without proportional driving activity is flagged. Referral bonuses paid only after the referee has independently completed 30 days of active driving with at least 2,000 miles logged via ELD.

**Cosmetic laundering.** Auto-flag if Legendary or Mythic moves through 3+ accounts in 30 days. Item locked, all involved accounts flagged for manual review within 7 days. False-positive target <0.5%. If laundering confirmed: item destroyed (no value transfer), all involved accounts lose Surge access for 60 days. Repeat: permanent ban.

**Reputation score.** Numeric 0–1000, default 750, decays toward 750 over time. **Visible only to the driver, never to other drivers** (avoids social stigma cascades). Two confirmed-against-driver chargebacks within 12 months → ineligible for "Trustworthy", "Honor Badge", "Veteran" marks for 24 months.

False-positive recovery paths are explicit: spoofing detector >1% false positive → algorithm rolled back, escalation to Eng Director. Multi-account false positive (driver sold company, re-registered as owner-op) reviewed within 24 hours. Item-freeze appeal 14-day window.

## Chapter 54 — Driver wellness + safety override (HOS-locked, fatigue gates, crisis surface)

**The Prime Directive.** The Haul never incentivizes an Hours-of-Service violation. This is not a guideline; it is a hardcoded invariant in the mission scheduler, gated through `frontend/server/services/hosEngine.ts::canDriverAcceptLoad`. If a mission, when accepted, would push the driver's projected schedule into HOS violation under 49 CFR 395, the mission button is **locked** and the UI displays the reason: "This mission would breach your HOS. Locked for your safety."

**HOS-aware mission scheduling.** Inputs: ELD log, projected route time including known traffic and weather, mandatory break windows, 14-hour driving window, 11-hour driving limit, 70-hour/8-day or 60-hour/7-day cycle. Decision: any mission consuming more hours than the driver has remaining in any of the three relevant clocks → locked. **30-minute safety buffer** is added to all projections — we would rather lock a mission the driver could have legally completed than risk one violation. If mid-mission a traffic jam pushes the driver into violation, the mission auto-pauses, the driver receives the partial reward for distance covered, and an in-app prompt explains why.

**Fatigue scoring via Pulse Watch.** Pulse driver wearable (HRV, skin temp, motion) provides real-time fatigue score 0–100. Companion AI integrates the signal:
- Fatigue >65 → no new Surge missions offered.
- Fatigue >80 → in-cab Companion voice prompt: "Your fatigue indicators are elevated. Please consider pulling over at the next safe location."
- Fatigue >90 sustained for 10 minutes → Haul disables, Companion advises emergency rest. **The trucking OS continues to function (SOS, ELD compliance, navigation never disabled).**

Privacy: fatigue data is the driver's. Fleet managers see only the aggregate "fit-to-drive Yes/No" boolean, never underlying biometrics.

**Counsel-mode for compulsive engagement.** Threshold: >16 hours of Haul-active app time in a single calendar day, OR >100 hours in 7 days. Level 1: in-app card "You've been engaged with Haul for X hours. Consider a wellness pause." Level 2 (third occurrence in 30 days): mandatory 24-hour Surge cooldown. Level 3 (sustained pattern): outreach call from a human Wellness Specialist — not from Trust & Safety, not from Support, a dedicated trained role.

**Crisis hotline auto-surfacing.** Lobby chat moderation includes language detection for self-harm, suicidal ideation, acute crisis signals. Multi-language classifier (English, Spanish, French) tuned with truck-driver-context vocabulary. Auto-surface a private card with 988 Suicide & Crisis Lifeline (US), Truckers Final Mile, and the local-equivalent hotline by GPS. Lobby moderator notified; if moderator concurs, a non-judgmental check-in message from a real human within 30 minutes. **Boundaries:** no public action ever taken on chat-detection alone; only private resources surfaced. Negligible harm if false positive.

**SOS independence.** The trucking emergency SOS function is architecturally independent of The Haul. SOS works when Haul is off, when Haul is paused, when Haul is killed, when the entire app is in low-power mode. **Verified by daily synthetic SOS test** from a non-Haul process. SOS test failure is a P0 incident; if not fixed in 4 hours, system-wide Haul pause until restored.

## Chapter 55 — Metrics, SLOs, postmortem triggers

**North Star metrics.**
- Monthly Active Rep Growth: drivers earning at least one Standing Point in the calendar month. Target +8% MoM Phase 2, +5% Phase 3, +3% mature Phase 3.
- 12-Month Retention: percentage of drivers active in month M who remain active in M+12. Target ≥70% by Phase 3 month 6, ≥75% steady state.

**Counter-metrics (the metrics that, if they move wrong, kill the launch):**
- Fatigue events per million driver miles, Haul-active vs control. Threshold: ratio ≤ 1.0. 10% excess → escalation to Chief Safety Officer.
- Near-miss rate (CSA proxies): hard-brake, lane-departure, speeding-percentile per million miles. Each metric must remain at or below non-Haul control. 5% degradation → feature review.
- Lobby toxicity reports per 1,000 driver-days: ≤2 per 1,000 driver-days. Median moderation response ≤4 hours, p95 ≤24 hours.
- HaulPay dispute rate: ≤0.5% disputed, ≤0.1% confirmed our error.

**Service Level Objectives.**
- Mission accept-to-confirm latency: ≤800ms p95, ≤1500ms p99. Error budget 0.5%/month.
- Crash-free user rate: ≥99.5%. Error budget 0.5%/week.
- HaulPay payment processing: ≤24h earn-to-available, ≤72h available-to-bank-cleared.
- Trust & Safety review SLA: multi-account flag ≤72h, crisis escalation acknowledgment ≤30min, payment-dispute review ≤7 days.

**Architectural roadblocks (immutable invariants — not tunable):**
- SOS unaffected by any Haul code path. Verified daily.
- ELD compliance unaffected. ELD subsystem in a separate process with separate IPC.
- HOS lock cannot be overridden by reward incentive. Hardcoded; no feature flag.
- No driver under 21 can earn cash. Hardcoded; KYC gate.
- No randomized cash reward in WA or HI. Hardcoded; geo-fenced by domicile.

**Postmortem triggers.**
- Any single driver injured during a mission: immediate phase pause for that driver's region. Causation review by Chief Safety Officer + outside FMCSA counsel within 14 days. Public postmortem within 30 days. If causally linked, responsible feature is killed system-wide pending remediation.
- Any single driver killed during a mission, regardless of attribution: immediate nationwide Surge pause within 4 hours. Independent third-party safety firm investigation. Public postmortem within 60 days. If causally linked, Haul paused indefinitely pending root-cause remediation, board review, and public sign-off by CSO + General Counsel.
- Any regulatory enforcement action: postmortem within 30 days, published to Trust Center.
- Any data breach >500 drivers: GDPR-style 72-hour notification, postmortem within 30 days.
- Crash-free <99.0% for 7 consecutive days: engineering postmortem within 14 days.
- Three or more drivers report compulsive engagement in 14 days: wellness postmortem within 30 days.

**Postmortem process.** Blameless. Five Whys + Causal Tree. Action items with named owner, due date, verification check. Verification meeting within 60 days confirming closure. Public posting on Trust Center.

**The Single Veto.** The Chief Safety Officer holds an unconditional veto on any phase advance, any feature ship, any rollback decision, any postmortem outcome. This veto cannot be overridden by the CEO, the board, or this document. It can only be overridden by the CSO themself in writing, after consultation. This is the asymmetric safeguard that says: when in doubt about driver safety, we do not ship.

---

# Appendix A — PSO quote book (verbatim references the Haul honors)

The Haul's design lineage is from Phantasy Star Online (Sega / Sonic Team, Dreamcast 2000; GameCube/Xbox 2002–2004; modern Ephinea/Schtserv private servers continuing through 2026). Where this encyclopedia uses paraphrase from PSO design retrospectives, we identify the source rather than directly quote (copyright respect — PSO design documentation is not in the public domain for verbatim reproduction).

The honored design artifacts:

1. **Pioneer 2 Block 1** (the original lobby) — sixteen avatar slots, octagonal room, fixed 35.264°/45° iso camera, soft ambient soundtrack, dance/wave/sit emotes, Symbol Chat composer. The Haul Lobby in Chapters 20–24 honors this exactly.

2. **The Quest Counter NPC** — single point of mission vending, one-line difficulty rating, one-line reward preview, partial reward concealment ("Rare Drop: ???"). The Mission Board in Chapter 8 honors this with the four-NPC Dispatcher (Vega, Ridge, Marcellus, Captain Okafor).

3. **The four difficulty tiers — Normal, Hard, Very Hard, Ultimate.** The Haul Standard / Pro / Veteran / Master in Chapter 6 are the same ladder, professionally renamed.

4. **Section ID drop bias** — Bluefull, Greenill, Pinkal, Purplenum, Redria, Skyly, Viridia, Whitill, Yellowboze, Oran. Ten IDs assigned at character creation, biasing rare drops. Chapter 18 Lane Color (Crimson, Cobalt, Verdant, Amber, Onyx, Silver, Pearl, Sun, Sand, Aurora) is the exact ten-color port.

5. **MAG companion evolution** — Mind/Power/Defense/Skill stats fed into branching forms (Estlla, Sato, Pian, Kalki...). Chapter 13 ESANG Companion's diet-based persona branching (Hazmat, Tanker, Reefer, Flatbed, Frontera, Solo, Carrier, Wanderer) honors this.

6. **The Photon Drop economy** — the universal currency for rare-item trading, with brutal drop rates (1/512, 1/2048, 1/16384). Chapter 10 publishes our drop rates transparently — the same brutal scarcity at the Mythic tier (0.005%) but with the regulatory firewall PSO never shipped.

7. **The Forest 1 → Ruins 3 quest progression** — five environments, escalating mob waves, three rare-drop bosses (Dragon, De Rol Le, Vol Opt), final boss Dark Falz. Chapter 5's twelve archetypes and Chapter 25's Surge Missions honor the spawn-discoverability pattern.

8. **The lobby return — the post-quest victory walk** — players returned to the lobby to flex the rare drop, post a Symbol Chat, watch the friends-list react. Chapter 21 BOL Stamp shipping into the lobby chat thread is the exact mechanic.

9. **The four-tier rare table per drop** — common, uncommon, rare, S-rank. Chapter 10 Common / Uncommon / Rare / Epic / Legendary / Mythic (six tiers, expanding the canonical four to support our segmentation) honors the structure with one extra granularity step.

10. **Christmas Lobby, Halloween Lobby, anniversary events** — the seasonal calendar that drove return visits. Chapter 23 Driver Appreciation Week / MATS / ATA / Eusoversary is the exact calendar play, retargeted to the freight industry's actual cultural rhythm.

# Appendix B — Forbidden words (driver-facing copy guard rail)

Engineering must run every driver-facing string through this filter. Strings that match any left-column term cannot ship.

| Forbidden term | Replacement |
|---|---|
| play / playing / player | Hauler / driver / running |
| game / gameplay / gaming | The Haul / mission / running |
| fun / enjoyable / addictive | (no replacement — rewrite without the trait claim) |
| gamification | (forbidden in driver-facing copy entirely) |
| level up / levelling | advanced to <Tier> |
| XP | Miles Earned / Standing Points |
| achievement | Mark / Milestone |
| loot / loot crate / loot drop | Recognition / Recognition Crate |
| drop (as noun, alone) | Recognition |
| gacha | (forbidden — no replacement) |
| grind / grinding | running / hauling / sustained work |
| endgame | Master tier / Veteran lane |
| win / winning / winner | completed / earned / cleared |
| quest | Mission |
| boss / boss fight | Surge Mission |
| dungeon | (forbidden — no surface need) |
| character | Hauler |
| class (RPG sense) | Specialty |
| pet / familiar | Companion |
| guild | Crew / Convoy |
| rare drop | Verified Recognition |
| crit / critical hit | (forbidden — no surface need) |
| respawn | (forbidden — no surface need) |
| HERE-listed | EusoTrip Network |
| HERE AD-capable | Smart-Drive Lane |
| HERE low-incident | Verified Safe Corridor |
| HERE truck-safety | Driver Safety Index |
| HERE | (never surfaced; engineering term only) |

The filter is implemented as a code-review pre-commit hook in the `eusotrip` repo. Pull requests with driver-facing strings (any string in `*.swift`, `*.tsx`, `*.html`, or copy YAML files within `frontend/client/src/copy/`) that match a forbidden term are blocked at CI.

# Appendix C — Approved mission name patterns (12 templates × naming rules)

The naming convention for production Mission cards across the twelve archetypes:

1. **RESCUE.** "<Origin> → <Destination> — <Cargo> Recovery." Example: *"Phoenix → El Paso — Refused Reefer Recovery."*
2. **EXPLORATION.** "New Lane — <Shipper>, <Origin> → <Destination>." Example: *"New Lane — Sysco DC, San Antonio → Sysco DC, Houston."*
3. **DEFENSE.** "Verified High-Value Run — <Cargo Description>, <Origin> → <Destination>." Example: *"Verified High-Value Run — Semiconductor wafers, Phoenix → Austin."*
4. **SURGE.** "<Region> Surge — <Cargo> Run." Example: *"Texas Triangle Surge — Wind Blade Run."*
5. **SURVIVAL.** "Transcontinental — <Origin> to <Destination> in <Days> drive days." Example: *"Transcontinental — Long Beach to Charleston in five drive days."*
6. **STEALTH.** "Veteran Run — <Origin> → <Destination>." Example: *"Veteran Run — Knoxville → Mobile."*
7. **COLLECTION.** "<Equipment> Collection — <N> pickups → <Consignee>." Example: *"Reefer Collection — Four pickups consolidating into Sysco Houston DC."*
8. **RACE.** "Lane Sprint — <Origin> to <Destination>." Example: *"Lane Sprint — Memphis to Birmingham."*
9. **PUZZLE.** "Border Run — <Port> <Direction>, <Doc Suite>." Example: *"Border Run — Laredo southbound, Carta Porte 4.0 + ACE pre-filed."*
10. **CO-OP.** "Crew Run — <Cargo Type>, Convoy of <N> with <pilot car details>." Example: *"Crew Run — Oversize wind blade, Convoy of three with two pilot cars."*
11. **ARENA.** "Yard Drill — <Maneuver>, <Equipment>." Example: *"Yard Drill — Alley dock 53'er, blind side."*
12. **DAILY.** "<Daily Action> — <Outcome>." Examples: *"Pre-Trip Verified — DVIR with photo evidence before 06:00."*, *"Safety Module — Watch the 4-minute brake-check refresher."*

The naming rules:
- Always specifies origin and destination cities (or yard, or stop name) for situational clarity.
- Never uses adjectival hype ("epic," "legendary," "incredible") — those words are tier indicators in the UI, not mission name decoration.
- Always uses sentence case, with em-dashes between phrases. No exclamation points.
- Always under 60 characters total to fit the mission card.
- Never uses ALL CAPS in the mission name itself (caps are reserved for tier pills).

# Appendix D — The 24-role-aware Haul (which roles see what)

The Haul is not driver-only. Eusoboards has 24 distinct user roles, and The Haul's recognition layer surfaces differently to each. The mapping (canonical):

- **Driver / Owner-Operator (1099)** — full mission flow, full Lobby, full recognition crates, full marketplace seller and buyer.
- **W-2 Company Driver** — full mission flow with carrier-sponsored cosmetic packs (Chapter 14), Streak Pass-Through routing if carrier opted in.
- **Carrier Dispatcher** — sees the team mission map (`getTeamStats`), carrier-sponsored cosmetic budget panel, the engagement-score B2B SaaS dashboard (Chapter 39).
- **Carrier Operations Manager** — same as Dispatcher plus payroll integration views.
- **Broker** — sees broker-side referral economy (Chapter 32), engagement-score dashboard for vetting carriers.
- **Shipper** — sees shipper-side scorecard, chooses preferred carriers from engagement leaderboard.
- **Insurance Underwriter Partner** — sees aggregated low-risk cohort feed (Chapter 39 insurance partners line).
- **Trust & Safety Reviewer** — sees the moderation log (`getModerationLog`), strikes (`getUserStrikes`), trade-flag queue.
- **AML Compliance Reviewer** — sees the laundering-pattern auto-flags (Chapter 14), full peer-to-peer money flow.
- **Wellness Specialist** — sees the Counsel-mode escalation queue (Chapter 54 level 3).
- **Eusorone Internal Ops** — admin views of mission catalog, mark catalog, season management.
- **Eusorone Customer Success (Carrier)** — sees fleet-level adoption metrics, tier progression at the carrier level.
- **Eusorone Customer Success (Shipper / Broker)** — same at shipper/broker level.
- **HaulPay Risk** — sees the factoring-tier promotion queue (Chapter 11 Black tier invitation).
- **Founder / Executive Steering** — board-level safety briefing dashboards, North Star + counter-metric trending.
- **Chief Safety Officer** — full causation review surface, the Single Veto button (Chapter 55).
- **General Counsel** — regulatory filing log, jurisdictional matrix, app-store posture statements.
- **VP Engineering** — feature-flag dashboard, kill-switch UI.
- **VP Launch** — phase-gate state machine, success/kill criteria board.
- **VP Product** — North Star + counter-metric instrumentation.
- **External Auditor (regulatory)** — audit trail read-only access, drop-table reproducibility from `rng_seed`.
- **External Auditor (financial)** — read-only ledger access, 1099 reconciliation.
- **Driver Council Representative** — read-only access to fleet-wide aggregate sentiment, ability to flag culturally-insensitive seasonal skin proposals (Chapter 23 multicultural review).
- **Eighth Light Hauler (Mission Designer)** — content authoring access for one approved mission per Eighth Light unlock (Chapter 19).

The role-level access is enforced via the `applicableRoles` JSON column already present in the `missions` table — engineering extends that pattern across the new tables (Appendix F).

# Appendix E — Glossary

- **Block** — population-shard subdivision of a Lobby when more than sixteen Haulers are present at one truck stop. Splits A/B/C with one-tap switching.
- **BOL Stamp** — auto-generated server-signed share-card from a completed Mission's BOL.
- **Companion** — ESANG, the AI voice-and-visual entity bound to the Hauler's account, evolving across the lifetime of the account.
- **Crew** — temporary or permanent group of Haulers running together (Convoy, Co-op mission, mentor-rookie pair).
- **Convoy** — synonym for Crew when 2–6 Haulers are running the same Co-op mission.
- **Dispatcher Window** — the in-Lobby NPC counter that vends Missions (Vega, Ridge, Marcellus, Captain Okafor).
- **Eight Lights** — the prestige system, First Light through Eighth Light, granting cumulative permanent +5%–+40% Miles Earned buffs.
- **EusoTrip Network** — the doctrine-canonical name for the routing/geofencing/POI/weather backbone (HERE Technologies, never named to drivers).
- **Hauler** — driver-facing role name; the on-screen identity.
- **Hot Zone** — dynamically-generated polygon of elevated freight density.
- **Lane Color** — the home-base ZIP-derived identity attribute (Crimson, Cobalt, Verdant, Amber, Onyx, Silver, Pearl, Sun, Sand, Aurora).
- **Lobby** — the geofenced 3D iso-view truck-stop scene, sixteen-slot population, 30-second presence tick.
- **Mark** — driver-facing word for *badge / achievement*.
- **Master tier** — Master Class Hauler, the top of the four standings.
- **Miles Earned** — driver-facing word for *XP*.
- **Mission** — the unified word for *load + recognition envelope*. A Mission is a load, with a tier, archetype, and recognition shape.
- **Mission Board** — the in-Lobby UI surface where the four Dispatcher NPCs vend Missions.
- **NPC archetype** — Vega (Dispatch), Ridge (Quartermaster), Marcellus (Recruiter), Captain Okafor (Haulmaster).
- **Pioneer 2** — the PSO lobby station; engineering reference only, never surfaced.
- **Pity timer** — the bad-luck-protection counter exposed transparently to the Hauler.
- **Pulse** — the Eusorone driver wearable (HRV, motion, fatigue) that drives Lobby presence and fatigue-aware mission gating.
- **Rebirth** — the Standing 100 reset that grants +5% permanent Miles Earned buff per cycle (capped at +40% at Eighth Light).
- **Recognition** — the cosmetic, mark, fee-discount, or cash payout that drops on Mission completion.
- **Recognition Crate** — the on-claim envelope containing the recognition (the renamed loot crate).
- **Specialty** — the renamed RPG Class — Hazmat Specialist, Reefer Engineer, Flatbed Architect, Tanker Master, Auto Hauler, Cross-Border Diplomat, Long-Haul Veteran.
- **Standing** — the renamed Level (1–100); the Hauler's progression dial.
- **Standing Points** — the in-app currency Haulers earn alongside Recognition; cosmetic-bound, non-cashable, not gambling-adjacent.
- **Surge Mission** — the renamed Boss; the geofenced, time-windowed, scarcity-driven high-rate load.
- **Triathlete** — the cross-mode Master tier (truck + rail + vessel) above Legend.
- **Verified Safe Corridor** — the renamed HERE low-incident corridor; the EusoTrip-branded driver-facing term.

# Appendix F — Open questions for the Claude Code team

Engineering decisions still pending the steering committee's review. Each item is a concrete deliverable, not a philosophical question.

**Sprint 1 (Phase 0 readiness):**
1. *Schema additions to `gamification_profiles`.* Confirm the column list in Chapter 47 is complete; Drizzle migration ready for review.
2. *New tables (`cosmetic_items`, `drop_events`, `pity_state`, `streak_state`, `cash_rewards`, `cosmetic_inventory`, `cosmetic_trades`, `carrier_cosmetic_sponsorships`, `esang_companion`, `esang_feeding_history`, `geofences`, `lobby_zone_progress`).* Schema PR ready for review.
3. *Reconciliation between `loot_crates` and `reward_crates`.* Two existing tables with overlapping semantics. Decision needed: merge into one, or formalize the distinction (e.g., `loot_crates` = mission-completion drops, `reward_crates` = seasonal/event drops).
4. *Public drop-table endpoint.* Decision: should it require auth or be fully public (regulatory shield argument favors public, brand argument favors auth-walled)? Recommendation: public, no auth.
5. *Forbidden Words pre-commit hook.* Build the regex linter that blocks PRs with driver-facing strings matching Appendix B.

**Sprint 2 (Phase 1 readiness):**
6. *State machine procedures (`checkpointMission`, `failMission`, `disputeMission`).* tRPC procedures + state transition logic, gated by `hosEngine.canDriverAcceptLoad` for `failMission`'s HOS-violation auto-trigger.
7. *BOL Stamp generator.* New `bolStampRouter` with `generate(missionId)` returning the 1080×1920 ImageRenderer payload + the lobby-post side effect.
8. *Mythic-tier shimmer perf prototype.* MeshGradient on iOS 18 vs. LinearGradient + hueRotation fallback on iOS 17. Validate 8+ Mythic marks visible simultaneously without dropping below 60fps.
9. *Reward signing latency.* Server-signed reward envelope must arrive before the 1200ms reveal animation completes. Prototype the pre-fetch on accept + sign-on-completion pattern.

**Sprint 3 (Phase 2 readiness):**
10. *Cosmetic-to-cosmetic trading.* `proposeTrade` + `confirmTrade` with the 24-hour escrow, KYC double-check, and laundering-pattern auto-flag.
11. *Companion router and evolution logic.* `companionRouter.getCompanion`, `feedCompanion` (event-driven from mission-completion), `respecPersona`. The 90-day persona window aggregation logic.
12. *Carrier sponsorship pack purchasing.* B2B endpoint for fleet partners to buy and grant cosmetic packs to their W-2 drivers.

**Sprint 4 (Phase 3 readiness):**
13. *Lobby 3D scene asset pipeline.* Pre-baked .usdz diorama bundles per truck-stop chain (Pilot, Loves, TA, Petro, AmBest) + a generic fallback.
14. *Cross-mode lobby doorway pattern.* Rail, vessel lobby surfaces and the cross-mode hailing flow.
15. *Mythic supply caps and global counters.* Schema + lock for one-of-N items.

**Sprint 5 (polish):**
16. *Reduce-Motion fallback completeness audit.* Every animation in Chapters 40–45 has a documented Reduce-Motion path; audit ensures no animation exists without one.
17. *Dynamic Type AX1–AX5 verification.* Mission cards reflow at AX3+, profile stat cards reflow to single-column at AX3+; full verification pass.
18. *Battery target validation on iPhone 12.* Real-world the 60fps + 4%/10min battery budget; mitigation auto-30fps when on battery and below 20%.

**Open product questions:**
19. *Eighth Light hosting committee structure.* Who reviews the Eighth Light Hauler's submitted mission concept? Composition of the review panel.
20. *Lane Color reassignment cadence.* The 60-day residency proof is documented (Chapter 18). Edge case: a Hauler whose home base legitimately changes mid-quarter — what cosmetic experience do they have during the transition? Recommendation: dual-Lane visual treatment for 60 days.
21. *Crisis Mode opt-in cadence.* Is opt-in a one-time toggle or an annual re-confirmation? Recommendation: annual re-confirmation, with the 90-min CBT module re-issued on each annual cycle.
22. *Carrier vs Driver cosmetic cap interaction.* If a carrier sponsors 50 Hazmat-themed packs to its W-2 drivers and 30 of those drivers leave the carrier mid-year, the cosmetics stay with the drivers. Confirm the carrier's sponsorship invoice is non-refundable.
23. *Triathlete annual maintenance.* Two-of-three modes per quarter — which two? Driver's choice each quarter. Confirm.
24. *Charity round-up cap.* $250,000/year per the platform-match cap (Chapter 23). At what scale does the cap revisit? Recommendation: re-evaluate at each Eusoversary.

---

## Closing

The Haul ships when these chapters are reflected in the running code, when the schema additions are migrated, when the procedures listed in Chapter 49 exist on the backend, when the iOS primitives in Chapter 50 are merged, when Phase 0 closes its success criteria for two consecutive review periods, and when the Chief Safety Officer signs the launch document. That is the doctrine.

The thresholds in this book are concrete because the thresholds in this work are concrete. A driver injured during a Surge Mission is not an abstraction. A class-action filing on loot-box theory is not an abstraction. A Hauler whose Companion has been with them for three years and is now uniquely *theirs* is not an abstraction. Every threshold here exists because somewhere on some prior platform someone paid the cost of not having it. We will not repeat their failures.

We are building a recognition layer on top of the most physically grounded job in the modern economy. We are doing it in the language of professional freight, not in the language of video games, even though the structural genius of Phantasy Star Online is the spine. We are doing it inside Eusoboards, not beside it, because the work is the only thing that matters. The Haul is the recognition the work has always deserved.

— *The Haul Synthesis Group, 2026-04-27. Volume 01, Edition 2026.04.*

— *END OF ENCYCLOPEDIA.*
