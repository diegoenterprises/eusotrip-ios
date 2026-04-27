# 30 · Mode VESSEL — Terminal Operator

**What this covers.** The `VESSEL_TERMINAL_OPERATOR` role — screens 3380–3399, discharge planning (Gantt-like timeline with crane assignments), crane scheduling (read-only from TOS QCS), reefer plug map, yard ops.

**When you need this.** When building 3380–3399. When integrating with a Terminal Operating System (TOS). When wiring discharge plan visualization.

**Cross-links.** Mode overview: [00_Overview.md](./00_Overview.md). Port Agent (who takes containers out the gate): [03_Vessel_Port_Agent.md](./03_Vessel_Port_Agent.md). First Officer (who tells terminal where containers are on the ship): [02_Vessel_First_Officer.md](./02_Vessel_First_Officer.md).

---

## 1. iOS screen range

**3380–3399** — Terminal Home, Yard Ops, Discharge Plan, Crane Schedule, Reefer Plug Map.

- **3380 Terminal Home** — berth overview + pending vessel arrivals.
- **3382 Discharge Plan** — Gantt-like timeline with crane assignments.
- **3383 Crane Schedule** — read-only crane assignments, move counts, bay completion status.
- **3385 Yard Ops** — real-time yard position map.
- **3387 Reefer Plug Map** — reefer containers + plug availability.

---

## 2. Backend procedures consumed

- `vessel.getBerthSchedule` — berths assigned for incoming vessel.
- `vessel.getPortDetails` — port configuration with berths.
- `vessel.recordContainerMovement` — terminal-level container events.
- `vessel.getContainerPositions` — real-time yard position map.

---

## 3. Discharge planning

On vessel arrival, terminal plans discharge sequence based on:
- Stowage (First Officer's bay plan).
- Priority (reefers + hazmat first).
- Customer service commitments (specific import containers flagged for express release).

Discharge plan screen (3382) is **Gantt-like timeline with crane assignments**.

---

## 4. Crane scheduling

QCS (Quay Crane Scheduling) runs in the TOS (Terminal Operating System). Mobile view is **read-only visibility** into:
- Crane assignments.
- Crane move counts.
- Bay completion status.

The mobile app does not replace the TOS. It augments with real-time visibility for operators walking the yard.

---

## 5. Reefer plug map

Reefer containers must be plugged in to maintain temperature. Plug capacity is finite and planned. Screen 3387 shows plug availability + which containers are plugged where, with temperature readouts from `containerTracking.temperature`.

Unplugged reefers beyond a configurable threshold (typically 2 hours) auto-fire reefer exception events.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
