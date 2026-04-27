# 20 · Mode RAIL — Yard Master

**What this covers.** The `RAIL_YARD_MASTER` role — screens 3140–3159, backend procedures, switchlist + blocking plan UX, the departure checklist gate (air-brake test, FRED, consist signed, hazmat placards verified, bad-order cars flagged). A yard master manages 800–2,500 railcars per shift.

**When you need this.** When building 3140–3159. When wiring switchlist haptics or departure checklist gating.

**Cross-links.** Mode overview + state machine: [00_Overview.md](./00_Overview.md). Dispatcher (receives the consist): [02_Rail_Dispatcher.md](./02_Rail_Dispatcher.md). Operator (whose crew runs the train out): [01_Rail_Operator.md](./01_Rail_Operator.md).

---

## 1. iOS screen range

**3140–3159** — Yard Home, Switchlist, Blocking Plan, Departure Checklist, Hump/Flat Yard Ops.

- **3140 Yard Home** — inventory count, outbound consist queue, shift-handoff notes.
- **3141 Switchlist** — ultra-dense table with physical track layout (tracks 1-40 with car positions). **Haptic feedback on reordering a car position is mandatory** — touch alone without tactile confirmation is error-prone when yard master is wearing gloves in winter.
- **3142 Blocking Plan** — color-coded groupings using **Okabe-Ito palette** (correct rendering under color-blind assistive modes) rather than red/green combos.
- **3143 Departure Checklist** — gating checklist (see §3).
- **3145 Hump/Flat Yard Ops** — hump-yard retarder scheduling vs flat-yard manual switching.

---

## 2. Backend procedures consumed

- `rail.getRailcars` with `yardId` filter — cars on yard master's inventory.
- `rail.createConsist` — after switching + blocking, yard master builds outbound consist and hands off to dispatcher.
- `rail.updateRailShipmentStatus` — yard master transitions: `in_yard → spotted`, `spotted → unloading`, and can push `loaded → in_consist` for outbound blocks.
- `multiModal.getRailOperations` for at-ramp visibility.
- `rail_yard_lookup` (MCP tool) — cross-yard lookup when equipment routed to foreign yard.

---

## 3. Departure checklist — the gate

Screen 3143 enforces:
- Air-brake test status.
- FRED (Flashing Rear-End Device) confirmed.
- Train consist signed.
- Hazmat placards verified against waybill.
- Bad-order cars flagged.

Each checkbox maps to event record via `rail.updateRailShipmentStatus` with notes.

Until every checkbox is green, dispatcher cannot push `in_consist → departed`. This is the gate.

---

## 4. Unique UX considerations vs trucking

**Scale.** 800–2,500 railcars per shift. Switchlist (3141) is ultra-dense, not a friendly list. Haptic feedback on reorder is mandatory — winter gloves + rain + heavy equipment = touch is unreliable.

**Blocking.** Grouping cars by destination/interchange. Color-coded groupings must render correctly under color-blind assistive modes. Okabe-Ito palette, not red/green.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
