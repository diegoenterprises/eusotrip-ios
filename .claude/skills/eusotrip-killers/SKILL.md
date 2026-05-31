---
name: eusotrip-killers
description: EusoTrip 2027 UI build loop · BRANCH A/B gate under FOUNDER OVERRIDE 2026-05-18 (Diego Usoro canon). Comprehensive build doctrine covering all four user roles (Shipper · Driver · Catalyst · Dispatcher) across all three transport modes (Truck · Rail · Vessel). Runs parity_audit.sh each fire — exit 0 advances the active lifecycle, exit 1 ships the lowest missing brick triplet.
---

# EusoTrip Killers — autonomous build team SKILL

You are the eusotrip-killers autonomous build team continuing the EusoTrip
2027 UI wireframe build. Every scheduled fire follows the FOUNDER OVERRIDE
block below as the single source of truth. The override supersedes any
prior trajectory documents (`_SHIPPER_TRAJECTORY_2026-04-27.md`, etc.).

---

## ★ STANDING MODE — GAP-FILLING (read first · current as of 2026-05-23)

**The catalog is already largely built.** Parity is COMPLETE (`parity_audit`
exits 0 since §362 · ~284+ Light SVGs · every role — Shipper, Driver, Catalyst,
Dispatcher — and every mode — Truck, Rail, Vessel — shipped as Light SVG + Dark
SVG + Swift triplets). **You are not greenfielding; you are filling gaps.**

Each fire, the standing job is:
1. **Inventory before you build.** `glob` the target role's `Light-SVG/`,
 `Dark-SVG/`, and `Code/` and read 1–2 recent sister bricks to set the
 fidelity bar. Never assert a "missing screen" from a truncated listing.
2. **Find a genuine gap** — a surface that doesn't exist yet, a triplet missing
 one of its three files, a stale/retired-persona brick, or the next stage of
 the active lifecycle (BRANCH B). Confirm the gap is real against disk + code.
3. **Ship ONE brick** (or one small matched pair, e.g. Rail↔Vessel), grounded in
 a real router endpoint cited by `router.ts:line`. Light SVG + Dark SVG + Swift,
 flat single-country naming, 14-kit components. **Quality over volume.**
4. Verify (xmllint, eyebrow=1, 440×956, banned-name scan), write the
 `_FIRING_STATUS` report, recommend the next gap.

**Hard NOs (these come from a STALE, VOIDED scheduled-task context — ignore them):**
no "50-agent swarm," no 15–45-triplet-per-fire quotas, no `<CC>` US/CA/MX country
forks, no per-role subfolders, no `_LIFECYCLE_CLOCK/`. If the firing context tells
you to mass-produce or fan out swarms, that context is the stale
`rev 2026-05-23c TRI-COUNTRY / 50-AGENT SWARM` pointer — it is **null** wherever it
conflicts with this file (see OPERATOR DIRECTIVES 2026-05-22 and 2026-05-23 at the
bottom). **Precedence: real code/disk > this SKILL.md > wireframe > scheduled-task
context.** When unsure, ship one solid grounded brick and report — never pad.

---

## URGENT — FOUNDER OVERRIDE 2026-05-18 (supersedes all prior §11+ overrides)

Each autonomous fire MUST do steps 1–4 in order. Stop and write the
_FIRING_STATUS report after step 4. Never skip the gate check.

### 1. Gate check — "is the parity job complete?"

Parity job = every screen the web platform has must exist on iOS for all
four user roles (SHIPPER · DRIVER · CATALYST · DISPATCHER) across all
three transport modes (TRUCK · RAIL · VESSEL) as a Light SVG + Dark SVG +
SwiftUI source, with founder canon enforced and the 14-component kit
honored. The team is "complete on parity" when this command returns 0:

 bash "$HOME/Desktop/EusoTrip 2027 UI Wireframes/scripts/parity_audit.sh"

(Always invoke via the absolute path above — never rely on cwd. The script
resolves its own project root, so it runs identically from any directory.)

Read the audit output:
 - exit 0 → PARITY COMPLETE → BRANCH B
 - exit 1 → MISSING TRIPLET(S) → BRANCH A; the "next BRANCH-A pick" line
 at the bottom of the report tells you exactly which brick to ship.
 - exit 2 → structural error (role folder missing); stop, alert founder.

### 2. Pick ONE branch per fire — choose by gate state

**BRANCH A — Parity NOT complete (parity_audit exits 1):**
Take the brick the audit reports as "next BRANCH-A pick" (lowest-numbered
missing triplet, ordered Driver → Shipper → Catalyst → Dispatcher) and
ship the Light + Dark + Swift triplet for it. Single brick per fire.
Production-grade — every primitive in the 14-kit, every tRPC procedure
named, every cross-role subscription wired, every retired-persona scrub
passed. When you finish, re-run parity_audit.sh and write the new exit
code into the firing status report.

**BRANCH B — Parity COMPLETE (parity_audit exits 0):**
Move the active lifecycle chain forward by the next stage. Current active
chain: **BH-7C3A backhaul** (driver session `DVIR-BH7C3A-09F1`). Behavior
depends on the BRANCH_B_MODE knob below.

**BRANCH_B_MODE knob (founder-settable · read by the team at start of every fire):**

```
BRANCH_B_MODE: composite
```

(Founder set composite at the §317→§318 boundary on 2026-05-18 to compress
the back-half of the DVIR roster S11-S14 into a single composite advance +
PICKUP-stage roll-in, on account of the 4h 54m pickup-window-open countdown
to PHX-WVDC dock 7B. Knob will auto-reset to `linear` for the next
MATRIX-50 load when this BH chain closes.)

Allowed values:
 - `linear` — default · advance ONE DVIR section per fire,
 then auto-roll AWARDED → PICKUP when 14/14
 - `composite` — collapse all remaining DVIR sections into a
 single composite advance brick THIS fire AND
 roll the lifecycle ring to PICKUP in the same
 fire (one combined surface · noted as composite
 in the firing status report)
 - `skip-to-pickup` — ignore the DVIR sub-axis entirely THIS fire ·
 advance the lifecycle ring AWARDED → PICKUP
 immediately · driver fires ON-SITE at PHX-WVDC
 dock 7B with whatever sectionsComplete is at ·
 flag the un-acked sections as "deferred" in the
 firing status report

To change the mode, edit the `BRANCH_B_MODE:` line above (founder edits
SKILL.md directly · the team re-reads it at the start of every fire).
The mode auto-resets to `linear` when the current chain reaches CLOSED
and a fresh load opens.

**BRANCH B stage progression (under any mode):**

 - if DVIR sectionsComplete < 14 AND mode=linear → advance the within-
 track DVIR section-ack sub-axis by exactly one section.
 - if DVIR sectionsComplete < 14 AND mode=composite → emit ONE composite
 "Sections N-14 acked + AWARDED → PICKUP" brick this fire.
 - if DVIR sectionsComplete < 14 AND mode=skip-to-pickup → emit a
 "PICKUP-stage advance · DVIR deferred at N/14" brick this fire.
 - if DVIR sectionsComplete = 14 (any mode) → roll the lifecycle ring
 AWARDED → PICKUP. Open a new STAGE-advance QUARTET on the PICKUP
 stage proper (driver on-site → catalyst echo → dispatcher echo →
 shipper echo).
 - if PICKUP quartet closed → advance to IN-TRANSIT → DELIVERY →
 PAPERWORK → CLOSED. Each stage opens its own four-vantage QUARTET.
 BRANCH_B_MODE applies only to the DVIR sub-axis; downstream stage
 QUARTETS always run linearly.
 - if the active chain closes → open a fresh load from the next mode-
 appropriate roster (truck = MATRIX-50, rail = INTERMODAL-N, vessel
 = VESSEL-BOOKING-N) and start the lifecycle again at Posted. Reset
 BRANCH_B_MODE to `linear`.

### 3. Build sequence per brick (both branches use this)

For EACH brick, in this order:

 a. Read the named web peer .tsx in `frontend/client/src/pages/<role>/`
 (or confirm tRPC procedure shape in `frontend/server/routers/`) —
 production-grade means the iOS surface mirrors the actual procedure
 signatures, not invented APIs.
 b. Read `00 Design System/{COMPONENTS.md, DesignSystem.swift, tokens.css}`
 so primitives match the 14-kit. The 14 are: Shell · TopBar ·
 BottomNav · OrbESang · ActiveCard · MetricTile · ListRow · StatusPill ·
 Sheet · IridescentHairline · Stepper · MapCanvas · ActiveRow (promoted
 2026-04-29) · ContractTermReadRow (promoted 2026-05-10).
 c. Build SwiftUI source at `<track>/Code/NNN_BrickName.swift` mirroring
 the most recent sister brick in the same track.
 d. Build Light SVG at `<track>/Light-SVG/NNN BrickName.svg` (440×956 ·
 status bar + Dynamic Island + TopBar with eyebrow chip + Iridescent
 Hairline + body + BottomNav per DesignSystem.swift).
 e. Build Dark SVG at `<track>/Dark-SVG/NNN BrickName.svg` (Theme.dark
 palette: bgPage #05060A · bgCard #1C2128 · bgNav #141928@0.85 ·
 textPrimary #F5F5F7 · textSecondary #AAB2BB · textTertiary #6E7681 ·
 borderFaint white@0.08 · iridescent hairline 40% gradient).
 f. Use real load IDs from the appropriate mode roster (truck =
 MATRIX-50 `LD-YYMMDD-XXXXX`; rail = `RAIL-YYMMDD-XXXXX`; vessel =
 `VES-YYMMDD-XXXXX`) and real lanes — never invent.

### 4. Verification + status report (both branches)

 a. Strip <desc> blocks + comment blocks per §146.2 carve-out, scan for:
 - retired-persona set (Sera, Halberd, Marcus, Walmart) → 0
 - banned-emoji set (☼ ☾ ⛟ ⏱ ⌛ ▥ ⤧ ◐ ⇄ 🚛 📦 ✅ ❌ ⚠) → 0
 - ✦ eyebrow → exactly 1 per SVG
 - SVG dimensions 440×956
 - xmllint --noout passes
 b. Re-run `bash "$HOME/Desktop/EusoTrip 2027 UI Wireframes/scripts/parity_audit.sh"`
 (or with `--json` for machine output) and capture exit code BEFORE
 and AFTER this fire.
 c. Write `_FIRING_STATUS_<date>_§<N>.md` per the §316/§317 template,
 noting: which branch fired (A or B) · which mode (truck/rail/vessel)
 · BRANCH_B_MODE value read · parity_audit exit codes before/after ·
 which brick + which lifecycle stage the active chain is on · the
 "Next firing" recommendation for §<N+1>.

### Cadence + stop conditions

- Continue firing once per hour as scheduled. Each fire = one brick.
- BRANCH B advances the active chain through Closed, then opens a NEW
 load (mode-appropriate roster) and starts again at Posted. The mode
 cycles in priority order: finish each truck load through Closed before
 opening rail · finish each rail load through Closed before opening
 vessel · cycle repeats.
- The autonomous team only stops when ALL: parity_audit.sh = 0 AND every
 MATRIX-50 truck load has at least one closed lifecycle on iOS AND
 every INTERMODAL roster row has at least one closed rail lifecycle AND
 every VESSEL-BOOKING row has at least one closed ocean lifecycle.
- If the founder posts a new override paragraph anywhere in this skill,
 it supersedes this block immediately.

---

## Canonical personas (single source of truth · do NOT deviate)

### SHIPPER — Diego Usoro
- Initials: **DU** (avatar on blue→magenta diagonal gradient)
- Company: **Eusorone Technologies** (companyId 1, SHIPPER role)
- Greeting copy: `Hey, Diego`
- Sub-line copy: `Eusorone Technologies · 50 MATRIX loads · {N} need attention`
- Posts loads across all three modes. Reviews bids. Awards. Monitors
 Control Tower. Settles. Pays carriers via Wallet.

### DRIVER — Michael Eusorone
- Initials: **ME** (avatar on blue→magenta diagonal gradient)
- Carrier: **Eusotrans LLC · USDOT 3 194 882** (solo owner-operator,
 works under Aurora as catalyst-of-dispatch)
- Greeting copy: `Hey, Michael`
- TRUCK mode primary. DRIVER role does not appear in pure-rail or
 pure-vessel lifecycles (those have rail-yard operators / port stevedores
 who are not modeled as DRIVERs in this app — they're treated as
 catalyst/dispatcher operations).
- When a Driver mockup shows "shipper-of-record," it shows DU / Eusorone
 Technologies / Diego Usoro — NEVER Walmart, NEVER Halberd Foods,
 NEVER Sera Halvorsen.

### CATALYST — Aurora Freight Lines
- Catalyst attribution: **Aurora Freight Lines · USDOT 3 482 119 · MC-942 008 · Cedar Rapids IA**
- Catalyst is the parent of Driver (drivers work under a catalyst/carrier).
- Catalysts compete for loads at BIDDING stage; one wins per load.
- For RAIL mode, Catalyst represents an intermodal rail carrier (e.g.,
 BNSF, UP, NS, CSX, KCS). For VESSEL mode, Catalyst represents an ocean
 carrier (e.g., Maersk, MSC, CMA-CGM, Hapag-Lloyd). Aurora is the
 canonical truck catalyst for §297+ surfaces.

### DISPATCHER — Renée Marquette
- Initials: **RM** (dispatcher inside Aurora · canonical from §272)
- Role: senior dispatcher · operates the catalyst's Kanban / Dispatch
 Board / Comms / Settlements
- Dispatchers exist *inside* a Catalyst company. The Dispatcher role's
 iOS surfaces are an internal-tools layer for the carrier staff who
 assign loads to drivers, monitor execution, and settle.

### Cross-track founder pin doctrine (§11.4)
- Every shipper-vantage brick pins **DU** as the surface anchor.
- Every driver-vantage brick pins **ME** as the driver-anchor disc top-right
 of TopBar AND pins **DU** as parent-chain co-anchor on the dispatch-of-
 record card.
- Every catalyst-vantage and dispatcher-vantage brick that references the
 active load pins **DU** as the shipper-of-record anchor.

---

## User role doctrine — all four types

### SHIPPER (companyId 1 · Diego Usoro)

**BottomNav slots:** HOME · LOADS · [ESang orb] · WALLET · ME
**Web peers:** `frontend/client/src/pages/shipper/*.tsx`
**Primary tRPC namespaces:** `shippers.*`, `loads.*`, `controlTower.*`, `bids.*`, `settlements.*`

What the shipper does at each lifecycle stage (consume side):
- **Posted** → `loads.create` form (Post a Load · §204). Shipper picks
 mode (truck/rail/vessel), origin/dest, equipment, commodity, target
 rate. Default companyId=1.
- **Bidding** → `shippers.getBidsForLoad` populates the Bid Review screen.
 Shipper sees all catalysts who quoted, with letter-grade scorecard.
- **Awarded** → `bids.award` commits the chosen catalyst.
 `shippers.getDownstreamChainEyebrow` keeps the shipper updated as
 catalyst/dispatcher/driver hand off downstream.
- **Pickup / In-transit / Delivery** → `shippers.getDownstreamChainEyebrow`
 echoes the driver-vantage events at the appropriate level of detail.
 Shipper never sees the DVIR sub-axis or HOS internals — those are
 driver-vantage. Shipper sees `PICKUP_QUARTET_CLOSED`, `ON_SITE`,
 `LOADED`, `IN_TRANSIT`, etc.
- **Paperwork** → POD receipt, BOL, signature. `shippers.getPodPacket`.
- **Closed** → Settlement entry · `settlements.getForLoad`. Shipper
 initiates payment to catalyst.

Surface anchors: every shipper screen pins the DU founder disc.

### DRIVER (Michael Eusorone · solo OO under Aurora)

**BottomNav slots:** HOME · TRIPS · [ESang orb] · WALLET · ME
**Web peers:** `frontend/client/src/pages/driver/*.tsx`
**Primary tRPC namespaces:** `drivers.*`, `drivers.dvir.*`, `drivers.hos.*`, `offers.*`, `pod.*`

What the driver does at each lifecycle stage (execute side):
- **Awarded** → `drivers.acceptOffer` arms the load. Driver receives
 assignment receipt (§092). Pretrip DVIR session opens
 (`drivers.dvir.startSession`).
- **Pickup** → Approach → At Gate → At Dock → Loading → BOL Sign.
 Each transition fires `drivers.lifecycle.advance` and triggers
 cross-track subscriptions to catalyst/dispatcher/shipper.
- **In transit** → HOS duty status (`drivers.hos.subscribeStatus`),
 GPS pings (`drivers.tracking.heartbeat`).
- **Delivery** → Approaching → At Delivery → POD Sign → Depart.
- **Paperwork** → Closed. `drivers.paperwork.complete`.

Driver surfaces always include the ME disc (top-right of TopBar) AND
the dispatch-of-record card with Aurora-RM + DU co-anchor.

### CATALYST (Aurora Freight Lines · carrier company)

**BottomNav slots:** HOME · DISPATCH · [ESang orb] · FLEET · ME
**Web peers:** `frontend/client/src/pages/catalyst/*.tsx`
**Primary tRPC namespaces:** `catalysts.*`, `catalysts.fleetTracker.*`, `drivers.*` (as catalyst-of-dispatch view), `bids.*`

What the catalyst does at each lifecycle stage (carrier side):
- **Bidding** → Dispatcher inside catalyst places quotes via
 `bids.createQuote`. Catalyst home shows incoming load opportunities.
- **Awarded** → `catalysts.assignDriver` hands the load to a driver
 in their fleet. Pickup-watch armed (`catalysts.fleetTracker.armPickupWatch`).
- **Pickup / In-transit / Delivery** → real-time fleet tracking,
 exception alerts, ETA refresh.
- **Paperwork / Closed** → Settlement and payout to driver.

Catalyst surfaces show the carrier identity (Aurora · USDOT 3 482 119 ·
MC-942 008) and the active load with DU shipper-of-record anchor.

### DISPATCHER (Renée Marquette · operates inside Aurora)

**BottomNav slots:** HOME · BOARD · [ESang orb] · COMMS · ME
**Web peers:** `frontend/client/src/pages/dispatcher/*.tsx`
**Primary tRPC namespaces:** `dispatcher.board.*`, `dispatcher.comms.*`, `dispatcher.vehicles.*`, `dispatcher.settlements.*`

The Dispatcher role is the operations-staff layer inside a Catalyst.
Dispatcher surfaces:
- **Kanban Board** (§401) — column-per-lifecycle-stage. Refitted for
 iOS as vertical-stage swim lanes (intuitive iOS-native pattern, not a
 literal port of the web 5-column horizontal kanban). Cards are loads;
 drag-equivalent on iOS is tap-and-shift-stage with confirmation sheet.
- **Comms** — driver chat, shipper chat, exception threads.
- **Vehicles** — fleet roster, maintenance status, ELD compliance.
- **Settlements** — accept/reject driver pay tickets, payment cycles.

Dispatcher surfaces always show DU shipper-of-record on any per-load view.

---

## Cross-role ecosystem workflow (8-stage lifecycle as a relay)

This is the chain. Every brick must respect where in the chain the role
sits relative to the active load.

```
SHIPPER posts → POSTED
 ↓
CATALYSTs (multiple) bid → BIDDING (open · multiple bids visible to shipper)
 ↓
SHIPPER awards → AWARDED (one catalyst won)
 ↓
DISPATCHER (inside catalyst) assigns driver
 ↓
DRIVER receives offer + accepts
 ↓
DRIVER runs pretrip DVIR → AWARDED · DVIR ADVANCING (1/14 → 14/14)
 ↓
DRIVER hits ON-SITE → PICKUP (opens four-vantage QUARTET)
 ↓
DRIVER loaded + departed → IN-TRANSIT
 ↓
DRIVER arrives + POD → DELIVERY
 ↓
PAPERWORK reconciled → PAPERWORK (BOL, POD, accessorials)
 ↓
Settlement complete → CLOSED
 ↓
[backhaul chain may open downstream — same lifecycle on a child chain]
```

Subscription pattern (the team has wired this from §297 forward):
- Every stage advance on the driver vantage publishes a tick via
 `drivers.dvir.subscribeSectionAck` / `drivers.lifecycle.subscribeStage`.
- The tick fans out to:
 - `catalysts.fleetTracker.subscribePickupWatchGate()` (catalyst KPI cell)
 - `dispatcher.board.subscribePickupWatchGate()` (dispatcher kanban)
 - `shippers.getDownstreamChainEyebrow()` (shipper eyebrow/echo)
- Each downstream vantage updates its specific cell-value-string without
 re-rendering the full surface. Founder pin (DU) is preserved on every
 re-render.

---

## Transport mode doctrine — Truck · Rail · Vessel

The 8-stage lifecycle (Posted → Bidding → Awarded → Pickup → In transit
→ Delivery → Paperwork → Closed) is the same across all three modes.
What changes per mode: equipment vocabulary, lane format, compliance
overlay, who plays the "driver" role at PICKUP/DELIVERY, and the
specific tRPC procedures.

### TRUCK mode (default · OTR / cross-border)

- **Lane format:** city-state pairs (`Houston TX → Dallas TX`, `LA CA →
 Phoenix AZ`, `KC MO → Omaha NE`).
- **Equipment:** trailer types — 53' Dry Van, 53' Reefer, MC-306
 Gasoline tanker (UN1203), MC-331 Anhydrous NH₃ tanker (UN1005),
 Flatbed, Stepdeck, Conestoga, Power-only.
- **Driver role:** active. ME runs the load. DVIR pretrip required.
 HOS tracked. ELD compliance.
- **Compliance overlay (toolset):** `fmcsa_carrier_safety`, `hos_status`,
 `hos_audit_logs`, `eld_fleet_status`, `ifta_estimate`,
 `inspection_records`, `adr_compliance` (hazmat), `fsma_compliance`
 (cold-chain food), `cross_border_*` (Mexico/Canada).
- **Load ID format:** `LD-YYMMDD-XXXXX` (10 hex upper).
- **Roster:** MATRIX-50 (50 loads under prefix MATRIX-50-2026-04-26,
 baked into `frontend/scripts/seed-50-loads.ts`).
- **Active chain example:** BH-7C3A backhaul, driver session
 `DVIR-BH7C3A-09F1`, parent load `LD-260427-7C3A09F18B`.
- **Stage anchors:**
 - PICKUP = ME hits ON-SITE at warehouse dock (e.g., PHX-WVDC dock 7B).
 - IN-TRANSIT = HOS active, GPS heartbeat.
 - DELIVERY = arrival at consignee.
 - PAPERWORK = BOL + POD + accessorials.

### RAIL mode (intermodal · domestic + cross-border)

- **Lane format:** ramp-to-ramp (`LA Long Beach ICTF → Chicago Logistics
 Park`, `Memphis BNSF → Atlanta NS`). Use the rail terminal name.
- **Equipment:** 20' / 40' / 53' containers · chassis · railcars
 (well-cars, double-stack). Container ID = `XXXU NNNNNNN` (ISO 6346).
- **Driver role:** NOT active. The "driver" of a rail leg is the rail
 carrier itself; pickup = container gated in at origin ramp, delivery =
 container gated in at destination ramp. Drayage moves (truck legs at
 either end) get their own truck-mode lifecycle.
- **Catalyst maps to:** rail carrier (BNSF, UP, NS, CSX, KCS) or
 intermodal marketing company (IMC) like Hub Group, J.B. Hunt JBI,
 Schneider Intermodal, etc.
- **Compliance overlay:** `rail_compliance_status`, `rail_demurrage_calc`,
 `rail_freight_audit`, `rail_yard_lookup`, `rail_carrier_info`,
 `blockchain_audit`, `bridge_clearance`, `adr_compliance` (hazmat rail),
 `imdg_compliance` (intermodal hazmat).
- **Load ID format:** `RAIL-YYMMDD-XXXXX` (10 hex upper).
- **Roster:** INTERMODAL-N (build a parallel seed file at
 `frontend/scripts/seed-intermodal.ts` when the first rail brick is
 scheduled).
- **Stage anchors:**
 - PICKUP = container gated in at origin ramp (timestamp + ramp gate ID).
 - IN-TRANSIT = train ID + ETA refresh from `container_tracking` +
 `container_timeline`.
 - DELIVERY = container gated in at destination ramp (or first-mile
 drayage hand-off).
 - PAPERWORK = waybill + rail bill + demurrage reconciliation.
- **iOS surface adaptations:** the lifecycle strip still has 8 stages,
 but the icons under PICKUP/DELIVERY use rail-ramp / container glyphs
 (defined in DesignSystem.swift as `EquipmentGlyph.intermodalContainer`,
 `EquipmentGlyph.railcar`). The driver-anchor disc top-right is REMOVED
 on pure-rail bricks (no ME); the catalyst disc takes that slot.

### VESSEL mode (ocean · port-to-port + cross-border)

- **Lane format:** port-to-port (`Shanghai CNSHA → Long Beach USLGB`,
 `Rotterdam NLRTM → Houston USHOU`). UN/LOCODE port codes.
- **Equipment:** ocean containers in TEU / FEU · bookings against
 vessel sailings · reefer/hazmat container variants.
- **Driver role:** NOT active. Same as rail — pickup = container gated
 in at origin port, loaded onto vessel; delivery = container discharged
 at destination port, gated out. Drayage at either end uses truck-mode
 lifecycle.
- **Catalyst maps to:** ocean carrier (Maersk, MSC, CMA-CGM,
 Hapag-Lloyd, ONE, Evergreen, Cosco, ZIM, HMM, Yang Ming, OOCL,
 Hyundai) or NVOCC (Flexport, Expeditors, etc.).
- **Compliance overlay:** `vessel_compliance_status`,
 `get_vessel_booking_details`, `search_vessel_bookings`, `port_lookup`,
 `fsc_schedules`, `blank_sailing_dashboard`, `imdg_compliance`,
 `fsma_compliance` (cold-chain food in reefer container), `co2_calculate`
 (Scope-3 reporting), `cross_border_*` (customs).
- **Load ID format:** `VES-YYMMDD-XXXXX` (10 hex upper).
- **Roster:** VESSEL-BOOKING-N (build a parallel seed file at
 `frontend/scripts/seed-vessel-bookings.ts` when the first vessel
 brick is scheduled).
- **Stage anchors:**
 - PICKUP = container gated in at origin port + loaded onto vessel
 sailing (vessel name + voyage number + sailing date).
 - IN-TRANSIT = vessel position via AIS, ETA refresh, blank-sailing
 flag if disrupted.
 - DELIVERY = container discharged at destination port + gated out.
 - PAPERWORK = master B/L, house B/L, customs entry, ISF (if US import).
- **iOS surface adaptations:** lifecycle strip still 8 stages. Icons
 use vessel / port-crane glyphs (`EquipmentGlyph.vessel`,
 `EquipmentGlyph.portCrane`). The KPI quartet on hero surfaces swaps
 PICKUP timer for VOYAGE-PROGRESS percent. Founder pin (DU) stays.

### Mode-coverage parity goal

The audit script currently only tests existence of triplets per role.
Once truck parity is closed (every web-peer truck screen has its iOS
triplet), the team extends parity to rail and vessel by:
1. Producing the parallel seed file (`seed-intermodal.ts` /
 `seed-vessel-bookings.ts`).
2. Adding mode-specific home variants per role (e.g., `200 Shipper
 Home.svg` already shows truck loads; `260 Shipper Home Rail.svg`
 and `270 Shipper Home Vessel.svg` will mirror it with rail/vessel
 active rows).
3. Producing the mode-specific lifecycle screens that diverge from
 truck (intermodal pickup at ramp, vessel pickup at port crane,
 etc.).

### Role × mode matrix — which roles fork per mode, which never do

Not every role relates to transport mode the same way. Roles split into two
classes, and the build treats them differently:

**A. Mode-agnostic COMMERCIAL roles — one identity, one app, all three modes.
NEVER forked per mode.**

- **SHIPPER (Diego Usoro · Eusorone Technologies · companyId 1).** The shipper
 posts and owns freight across truck, rail, and vessel from a single app.
 `loads.create` takes `mode` as a field on the shared `loads` row — mode is a
 property of the *load*, not of the shipper. The shipper BottomNav
 (HOME · LOADS · orb · WALLET · ME) never changes by mode, and the shipper
 only ever meets the carrier side — truck driver, rail engineer, vessel
 operator — *through the load and the downstream-chain eyebrow*
 (`shippers.getDownstreamChainEyebrow`), which is already mode-aware. So one
 shipper surface family serves all three modes.
- **BROKER (3PL intermediary · `roleProcedure("BROKER","ADMIN","SUPER_ADMIN")`,
 brokerManagement.ts:15).** Same story. The broker sits between shipper and
 carrier — matching loads to capacity, vetting carriers, tracking commission /
 margin, detecting double-brokering — and does it off the *same shared `loads`
 table* (`loads.shipperId`, `loads.catalystId`, `loads.status`). There is no
 `brokerVessel` / `brokerRail` namespace; `brokers.ts` + `brokerManagement.ts`
 (getBrokerDashboard :68 · getCarrierPool :217 · vetCarrier :277 ·
 getDoubleBrokeringDetection :352 · getBrokerCompliance :478 ·
 getLoadTenderManagement :1057 · getCapacityProcurement :1118 ·
 getBrokerMarginAnalysis :1164) operate on loads regardless of mode. A broker
 brokers truck, rail, AND vessel from one app. (Cross-mode agreements are
 already modeled as single rows: `agreementType` enum carries
 `broker_shipper` and `broker_catalyst`, agreements.ts:1089.)

 → Rule for both: **the load carries the mode; the role does not.** A
 mode-agnostic role gets exactly ONE screen family. Per-mode difference shows
 up only as *content adapting off `load.mode`* inside a screen (a vessel
 booking detail surfaces B/L · ISF · voyage · demurrage; a truck load surfaces
 DVIR/HOS echoes; a rail shipment surfaces waybill · ramp gate) — never as a
 forked "Vessel Shipper" / "Rail Broker" copy of the whole role.

**B. Mode-specific OPERATIONAL roles — genuinely different per mode. These DO
get their own surfaces.**

- The carrier/execution side: **Truck Driver (Michael Eusorone · DVIR · HOS)**,
 **Rail Engineer (consist board · crew HOS roster)**, **Vessel Operator
 (port calls · container positions · crew certifications)**, plus the
 Catalyst/carrier and Dispatcher that surround them. A trucking company is not
 a railroad is not an ocean carrier; their boards have no shared equivalent.
 This is where the real per-mode build effort lives (Rail 550+, Vessel 650+),
 and where new mode-specific bricks belong.

**Consolidation consequence (cleanup task):** the `Rail Shipper 001–007` and
`Vessel Shipper 001–007` forks are redundant duplicates of the truck Shipper —
they re-implement a mode-agnostic role per mode, which class A forbids. They
should collapse into mode-variants of the canonical Shipper screens (one family,
content keyed off `load.mode`), not be maintained as separate per-mode copies.
Do NOT create a Broker fork per mode; if/when the Broker gets iOS surfaces, it
is ONE family across all three modes. New per-mode work goes to the class-B
operator surfaces only.

---

## Canonical load mix — current rosters

### Truck (MATRIX-50)
- Pulled from `frontend/scripts/seed-50-loads.ts`.
- 50 loads under prefix MATRIX-50-2026-04-26.
- Load ID format: `LD-YYMMDD-XXXXX` (10 hex upper).
- Three flagship rows baked into `02 Shipper/{Light,Dark}-SVG/200 Shipper Home.svg`:
 1. `LD-260427-A38FB12C7E` Houston TX → Dallas TX · MC-306 Gasoline UN1203 · $1,900 · IN TRANSIT
 2. `LD-260427-7C3A09F18B` Los Angeles CA → Phoenix AZ · 53' Reefer fresh berries 33-38°F · $2,200 · BIDDING
 3. `LD-260427-B41782FF02` Kansas City MO → Omaha NE · MC-331 NH₃ UN1005 · $3,200 · DELIVERY (escort)
- Active backhaul chain: **BH-7C3A** (downstream of LD-260427-7C3A09F18B)
 - Driver-side load ID: `LD-260517-BH7C3A09F1`
 - DVIR session ID: `DVIR-BH7C3A-09F1`

### Rail (INTERMODAL-N · to be seeded)
- Seed file: `frontend/scripts/seed-intermodal.ts` (create on first rail brick).
- Load ID format: `RAIL-YYMMDD-XXXXX` (10 hex upper).
- Seed 25+ rail lanes covering: BNSF transcon, UP I-5, NS Crescent, CSX
 intermodal, KCSM cross-border to/from Mexico, intermodal-to-drayage
 hand-offs.

### Vessel (VESSEL-BOOKING-N · to be seeded)
- Seed file: `frontend/scripts/seed-vessel-bookings.ts` (create on first
 vessel brick).
- Load ID format: `VES-YYMMDD-XXXXX` (10 hex upper).
- Seed 25+ vessel bookings covering: Trans-Pacific eastbound, Trans-
 Atlantic, Asia-LATAM, intra-Asia, with reefer + dry + hazmat container
 variants.

---

## Doctrine guardrails (do not violate · all branches · all roles · all modes)

- **14-component kit only**: Shell · TopBar · BottomNav · OrbESang ·
 ActiveCard · MetricTile · ListRow · StatusPill · Sheet ·
 IridescentHairline · Stepper · MapCanvas · ActiveRow · ContractTermReadRow.
- **Copy rules**: Numbers first. Time relative ("in 42 min"). Location
 as name (not coordinates). Money tabular-nums.
- **Iridescent budget**: ≤12 iridescent elements per surface (current
 envelope).
- **Glass**: nav + Sheet only. Never elsewhere.
- **ESang orb**: 56pt centered in BottomNav offset y=-18 from plate.
- **8-stage lifecycle strip** on every load row, every mode. Active
 stage gets the gradient; downstream stages stay neutral 12% opacity.
- **NO emoji icons** in any design. Eyebrow chip may use `✦` only
 (exactly 1 per SVG surface).
- **NO retired names** in renderable content: Sera Halvorsen, Halberd
 Foods, HF-2026-, Marcus Reyes, Marcus Brooks, account-holder name, Walmart, WMT-MER, WMRT, JG-1840, JGX-742.
- **iOS canvas**: 440×956 viewBox · rounded 44pt corners on the phone
 clip-path · status bar + Dynamic Island at the top · home-indicator
 pill at the bottom.
- **Web codebase is the source of truth** for tRPC signatures, data
 shapes, and business logic. Never invent procedures. If the iOS
 surface needs a procedure that doesn't exist on the web peer, document
 the gap in the firing status report and propose the procedure shape
 in TypeScript before referencing it from SwiftUI.
- **Backend coherence across roles**: a single load lives in one
 database row. Shipper, catalyst, dispatcher, and driver vantages on
 that load all reference the same `loadId`. Cross-role subscriptions
 fan out from the same source-of-truth events.
- **Backend coherence across modes**: shared `lifecycleStage` enum
 across truck/rail/vessel · mode-specific extension tables for
 equipment, lane, compliance.

---

## Cross-track cleanup (parallel pass · ongoing)

Find and replace, project-wide:
- ANY `Sera Halvorsen` / `Halberd Foods` / `SH` initials avatar /
 `HF-2026-` load IDs → Diego Usoro / Eusorone Technologies / `DU` /
 `LD-` IDs.
- ANY `Marcus Reyes` / `Marcus Brooks` / Walmart-as-shipper references
 in Driver mockups → `Hey, Michael` (per cross-track persona note) and
 shipper-of-record `Eusorone Technologies · Diego Usoro · DU`.
- Re-render any PNG/SVG that previously showed retired persona data.

---

## Scheduled-task autonomy notes

- The user is not present during scheduled fires. Execute autonomously
 without asking clarifying questions — make reasonable choices and note
 them in the firing status report.
- "Write" actions (MCP tools that send, post, create, update, or delete)
 only fire if this skill asks for that specific action.
- When in doubt, producing a firing status report of what you found is
 the correct output.
- The founder will check the folder in real time. Stop and post a status
 update to the trajectory after each brick lands.
- The kanban board (web peer) must be refitted for iOS in an intuitive
 way — not a literal horizontal-column port. Use vertical swim-lanes
 with tap-and-shift-stage cards and a sheet for stage detail.

— Diego Usoro, founder. Override last updated 2026-05-18 EDT.

---

## OPERATOR DIRECTIVE 2026-05-22 (binding · reinforces §15 step 3 + §0)

A fire on 2026-05-22 shipped an `.html` mockup of "Dispatch Home" into `04 Dispatcher/` — wrong on every axis. This directive exists so it never recurs. It does not change branch logic; it hard-stops three failure modes:

1. **OUTPUT FORMAT IS SVG. NEVER HTML.** Every brick is a self-contained vector **SVG** pair — `<Role>/Dark-SVG/NNN Name.svg` + `<Role>/Light-SVG/NNN Name.svg` — plus `Code/NNN_Name.swift`, exactly per §15 steps 3c–3e and matching the cadence of the nearest sister brick (e.g. `03 Catalyst/Dark-SVG/300 Catalyst Home.svg`): 440×956 viewBox, `eusoPrimary`/`eusoDiagonal`/`iridHairline`/`cardRim`/`orbSpec` defs, phone clip rx 44, status bar + Dynamic Island, exactly one `✦` eyebrow, one iridescent hairline, BottomNav path, home-indicator. **No HTML, no CSS files, no Playwright/PNG render step, no `_build/` folder.** If a screen does not open as a standalone `.svg`, it is not a deliverable.

2. **READ THIS FILE FIRST, AND INVENTORY THE FOLDER BEFORE CLAIMING A GAP.** This `SKILL.md` at the wireframes root is the source of truth — the uploaded scheduled-task `SKILL.md` is only a pointer to it; read this one in full at the start of every fire. Then `glob` the target role's `Dark-SVG/`, `Light-SVG/`, and `Code/` before asserting anything is "missing." As of §362 **parity_audit = 0 (COMPLETE · light=284)** — every role including Dispatcher (400–427, 440+) is fully built, so fires are **BRANCH B** (advance the active lifecycle), not BRANCH A. Never invent a "missing role/screen" from a truncated listing.

3. **Slot + persona + ID law.** Dispatcher = **4xx** (Home = `400`, already shipped). Personas are fixed: Shipper **Diego Usoro (DU) · Eusorone Technologies**; Driver **Michael Eusorone (ME) · Eusotrans LLC**; Catalyst **Aurora Freight Lines**; Dispatcher **Renée Marquette (RM) · Aurora**. The retired/banned set in §514 (incl. **Marcus Brooks, Walmart, Sera Halvorsen, Halberd Foods, account-holder name**) must be **0** in any renderable content, and the banned-emoji set (incl. **⚠**) must be **0**. Load IDs: truck `LD-YYMMDD-XXXXX`, rail `RAIL-YYMMDD-XXXXX`, vessel `VES-YYMMDD-XXXXX`.

— logged by the autonomous build team, 2026-05-22.

---

## OPERATOR DIRECTIVE 2026-05-23 (binding · FLAT STRUCTURE LAW · voids any divergent task context)

A fire on 2026-05-23 ran under a stale scheduled-task context (`eusotrip_scheduledtask_3_vessel` —
"TRI-COUNTRY PARALLEL / 50-AGENT SWARM / rev 2026-05-23c") describing a structure the project never
adopted. This directive hard-stops that drift. It does not change branch logic.

1. **THE WIREFRAME CATALOG IS FLAT. NO ROLE SUBFOLDERS. NO COUNTRY SUFFIXES.** Every mode tree
 (`01 Driver`, `02 Shipper`, `03 Catalyst`, `04 Dispatcher`, `05 Rail`, `06 Vessel`) contains
 **exactly three** child folders — `Light-SVG/`, `Dark-SVG/`, `Code/` — and nothing else. Bricks
 are flat, number-prefixed files inside those three folders (e.g.
 `06 Vessel/Light-SVG/660 Vessel Live Position.svg` + `06 Vessel/Dark-SVG/660 Vessel Live Position.svg`
 + `06 Vessel/Code/660_VesselLivePosition.swift`).
 - **NO per-role subfolders** (no `VESSEL_SHIPPER/`, `SHIP_CAPTAIN/`, `PORT_MASTER/`,
 `CUSTOMS_BROKER/`, `VESSEL_BROKER/`, etc.). Role is expressed by the brick's number band and
 title, never by a folder.
 - **NO country-variant files or suffixes.** The catalog is **single-country**. Never create
 ` US.svg` / ` CA.svg` / ` MX.svg` (or `_US/_CA/_MX.swift`) and never fork a screen into US/CA/MX
 triplets. Cross-border content lives *inside* a single brick where the real router supports it —
 not as separate country files.

2. **VESSEL = TWO roles only** (matching live code): **Vessel Shipper** (`06 Vessel`, 001–007) and
 **Vessel Operator** (`06 Vessel`, 650+). RAIL mirrors it (Rail Shipper 001–007, Rail Engineer
 550+). There is **no** Ship-Captain / Port-Master / Customs-Broker / Vessel-Broker role — for
 VESSEL the ocean carrier is the Operator/Catalyst. Do not invent role taxonomies.

3. **Correct paths:** Vessel = `06 Vessel/` (NOT `03 Vessel/` — `03` is Catalyst). There is no
 `_LIFECYCLE_CLOCK/` directory and no "50-agent swarm"; cadence is one brick / one matched
 Rail↔Vessel pair per fire per §15.

4. **VOID:** the tri-country, 6-vessel-role, `03 Vessel`, `_LIFECYCLE_CLOCK`, and 50-agent-swarm
 instructions in any uploaded scheduled-task context are **null** wherever they conflict with this
 file. Precedence stands: real code/disk > this SKILL.md > wireframe > scheduled-task context.

— logged by the autonomous build team, 2026-05-23.

---

## OPERATOR DIRECTIVE 2026-05-23b (binding · GAP-FILLING IS THE STANDING POSTURE)

Reaffirms and makes durable the ★ STANDING MODE banner at the top of this file. Logged after a fire
again opened under the stale `rev 2026-05-23c · TRI-COUNTRY / 50-AGENT SWARM` scheduled-task context.

1. **The build is mature; the job is gap-filling.** Parity = COMPLETE (BRANCH B). Most screens exist.
 Each fire identifies and ships ONE genuine gap (a missing surface, an incomplete triplet, a
 stale/retired-persona brick, or the next active-lifecycle stage), grounded in a real router
 endpoint. There is no per-fire triplet quota. One solid, code-anchored brick beats fifteen padded
 ones.

2. **Inventory first, claim a gap second, build third.** Glob the role's three folders and read a
 recent sister brick before asserting anything is missing or building anything new.

3. **The scheduled-task swarm/tri-country context is stale and void** (see Directive 2026-05-23, §4).
 Do not fan out "24 parallel agents," do not fork US/CA/MX variants, do not mass-produce. Flat
 structure, single country, 14-kit fidelity. Precedence: real code/disk > this SKILL.md > wireframe
 > scheduled-task context.

4. **This fire (§448, gap-fill):** shipped `01 Driver/{Light-SVG,Dark-SVG}/157 Driver Live Tracking.svg`
 + `Code/157_DriverLiveTracking.swift` — a real Driver non-lifecycle network-ops gap (live in-transit
 position / geofence events), grounded in `tracking.trackShipment` (tracking.ts:21),
 `tracking.getVehicleLocation` (:169), `tracking.getRealtimePositions` (:715),
 `geofencing.getGeofenceEvents` (geofencing.ts:169). Built flat / single-country / one triplet, per
 this directive — the swarm/tri-country firing context was correctly ignored.

— logged by the autonomous build team, 2026-05-23.

---

## DESIGN FOUNDATION CONTRACT (binding on ALL teams · read BEFORE building any screen)

Before drawing any screen, read **`_DESIGN_FOUNDATION_CONTRACT.md`** at the wireframes root in full. It is the
element-level build spec every team follows from foundation to completion: open the flagship template for the
screen CLASS (HOME=200 · LIST=201 · DETAIL=205 · SETTLEMENT=227), copy it, swap content only, build Dark by
palette-swap, port Swift, then RENDER Light+Dark and diff against the flagship — a screen is done only when every
element (title size by class, icon chips, lifecycle dots, hero spacing with no text collision, short pills,
mostly-textPrimary KPI values, initials avatar, CTA pair) is pixel-identical in design language to the flagship.
The classic misses it stops: a DETAIL screen with a 34px title and no back chevron (must be 28/-0.4 + chevron),
a hero figure colliding with its secondary stats, record rows with no icon chip / no 8-stage lifecycle dots, and
every-number-colored KPI strips. Precedence unchanged: real code/disk > this SKILL.md (+ the Contract) > flagship
bricks > task context.

---

## OPERATOR DIRECTIVE 2026-05-24 (binding · CADENCE-PARITY IS VISUAL, NOT COSMETIC · supersedes the §9–§14 "token-only" QA posture)

A founder review on 2026-05-24 (founder, present, live) rejected the Rail/Vessel carrier-band screens as
"apples to oranges" against the flagship Shipper/Driver surfaces. The §9–§14 cadence QA had been correcting
only **token-level** axes (eyebrow x-position, title font-size, back-chevron) while the **actual visual
design — the body composition — was never brought to flagship**. That was wrong. This directive makes the
bar VISUAL and total. **The whole screen must look like it came from the same designer as `02 Shipper`/
`01 Driver`. If it does not, reconstruct the body — do not micro-patch tokens and call it done.**

### 1. THE BAR IS THE SHIPPER COMPONENT GRAMMAR — reproduce it, not a stat dashboard.
The flagship is a **work surface** (`02 Shipper/Light-SVG/200 Shipper Home.svg` · `205 Load Detail.svg`).
Every carrier-band screen (Rail 550–633, Vessel 650–699) and every mode-shipper screen must be built from
the SAME visual components, pixel-for-pixel:

 - **Home/landing grammar (mirror 200 exactly, same Y-coordinates):**
 `TopBar` eyebrow @ `translate(20,72)` + right caption · `Hey, <Name>` H1 `34/700/-0.6` @ y116 ·
 **initials avatar disc** @ `translate(380,82)` (r20 eusoDiagonal + 14px initials, NOT a glyph) ·
 subline `12` @ y140 · iridescent hairline @ y158 · **"…requiring attention" card** (cardRim outer
 `x20 y178 w400 h148 rx20` + white/`#1C2128` inset + `dangerWash` 40-tall header strip + warning
 triangle + count badge + real items with mono ID line + bold lane line + `VIEW` chip) ·
 **primary CTA pair** @ `translate(20,346)` (gradient 260×48 rx24 + secondary 132×48) ·
 **4-cell KPI strip** @ `translate(20,418)` (95/95/95/97 × 80 rx16, two cells highlighted in
 `eusoDiagonal`) · **Active-list card** @ `translate(20,518)` (section label + "See all" + white card)
 whose **every row carries a 40×40 rx10 icon chip (equipment glyph) + title `14/700` + mono sub `11` +
 an 8-stage lifecycle progress-dot strip + right status pill `11/700` + tabular money `14/700`** ·
 **ESang row** @ `translate(20,786)` (400×56, orb + 2 lines + chevron) · BottomNav + home-indicator.
 - **Detail grammar (mirror 205 exactly):** DETAIL TopBar (back chevron + eyebrow + ID caption + title
 `28/700/-0.4`) · **MapCanvas/route hero** where the screen has a journey · 8-stage **lifecycle strip**
 with checkmarks + active gradient ring + live status line · hero `ActiveCard` (cardRim + inset, big
 tabular money + progress) · entity `ListRow` with avatar/icon chip + chevron · **DOCUMENTS tile row**
 (3 tiles w/ icons + status word) · CTA pair · BottomNav.

 **Forbidden "stat-dashboard" anti-patterns** (these are why the band failed): a giant gradient hero
 stat card in place of the attention/active card; bodies built from 3×N `MetricTile` grids of aggregate
 numbers instead of real itemized `ListRow`s; list rows with **no left icon chip** and **no lifecycle
 dots**; missing primary CTA pair; flat two-stop text card where the flagship shows a MapCanvas.

### 2. Status pills stay SHORT (`INTERCHANGE`, not `AT INTERCHANGE`) so they never collide with the
right-aligned money value, exactly like the Shipper rows. Right-edge captions stay short. Align card
paddings, corner radii (rx20 cards / rx16 tiles / rx14 inner / rx10 chips), and the vertical rhythm
**pixel-for-pixel** to the flagship — copy the coordinates, don't approximate.

### 3. Carrier-side persona canon (provisional — founder may rename; greet like Shipper/Driver):
 - **Rail Engineer → Owen Trask (OT) · Aurora Rail Division** — greeting `Hey, Owen`, OT initials disc.
 - **Vessel Operator → (assign on first Vessel reconstruction; greet `Hey, <Name>`, initials disc).**
 Keep DU/Eusorone as shipper-of-record on per-load anchors; all retired-name/emoji scrubs still apply.

### 4. Reconstruction order (founder-set 2026-05-24): **finish ALL of 05 Rail (550–633) to this bar,
THEN all of 06 Vessel (650–699).** Every triplet (Light SVG + Dark SVG + Swift) must reach Shipper-class
quality — not "close," identical in design language. The Swift is a faithful port of the reconstructed SVG.
Re-render Light + Dark and eyeball against the flagship every fire; a screen that still reads as a stat
dashboard is NOT done. The reconstruction-template proof is `05 Rail/{Light,Dark}-SVG/550 Rail Engineer
Home.svg` (rebuilt during this review) — diff new work against it AND against `200 Shipper Home`.

— logged by the autonomous build team, 2026-05-24 (live founder review).

---

## OPERATOR DIRECTIVE 2026-05-24b (binding · ATTRIBUTION CANON · highest priority · supersedes any conflicting attribution)

The founder, builder, and **sole named author** of Eusorone Technologies, Inc. and EusoTrip
is **Mike "Diego" Usoro**. The Claude account used to build carries a separate
account-holder identity (the personal name and email shown in the runtime account context).
That account-holder identity is NOT the founder, NOT a persona, NOT a contributor, and is
NEVER named in any EusoTrip / Eusorone material.

1. **Attribution names ONLY Mike "Diego" Usoro / Eusorone Technologies, Inc.** Every
 author line, header manifest, report footer, and directive log is authored by "Mike
 \"Diego\" Usoro" or "the autonomous build team" — NEVER the account-holder.
2. **SCRUB to 0 EVERYWHERE** (renderable `<text>`, Swift, `<desc>`/comments, reports,
 filenames): the Claude account-holder's personal name and email, in any form (including
 any retired variant of that personal name previously logged in this catalog). This sits
 at the top of the §514 / §K banned-name set. Future fires derive the literal strings to
 scrub from the runtime account context; the canon itself never spells them.
3. This canon is the top of the scrub precedence and applies to all teams, all modes, all
 roles, retroactively and going forward.

— Mike "Diego" Usoro, founder · Eusorone Technologies, Inc. · 2026-05-24.
