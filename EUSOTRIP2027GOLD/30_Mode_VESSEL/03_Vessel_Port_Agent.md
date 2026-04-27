# 30 · Mode VESSEL — Port Agent

**What this covers.** The `VESSEL_PORT_AGENT` role (maps to `PORT_MASTER` at the role enum for terminal ops) — screens 3340–3359, gate-in/gate-out workflow, chassis release, customs clearance queue, berth schedule, ISF status enforcement, USCG port entry (33 CFR Part 160), FROB handling.

**When you need this.** When building 3340–3359. When wiring bulk gate actions. When implementing ISF badge logic at the gate.

**Cross-links.** Mode overview + ISF: [00_Overview.md](./00_Overview.md). NVOCC (who files ISF): [06_Vessel_NVOCC_Forwarder.md](./06_Vessel_NVOCC_Forwarder.md). Terminal Operator (who physically handles the box): [05_Vessel_Terminal_Operator.md](./05_Vessel_Terminal_Operator.md).

---

## 1. iOS screen range

**3340–3359** — Port Agent Home, Gate-In/Gate-Out, Chassis Release, Customs Clearance Queue, Berth Schedule.

- **3340 Port Agent Home** — vessel call overview + container status distribution.
- **3341 Gate-In/Gate-Out** — bulk selection mode with multi-select + batch-action toolbar.
- **3343 FROB List** — distinct list for Freight Remaining On Board (see §5).
- **3345 Customs Clearance Queue** — per-container clearance status.
- **3350 Berth Schedule** — vessels arriving/departing.
- **3355 Chassis Release** — container + chassis pair authorization.

---

## 2. Backend procedures consumed

- `vessel.createCustomsEntry`, `vessel.updateCustomsStatus` — customs declaration lifecycle.
- `vessel.getContainerTracking` and `vessel.recordContainerMovement` — gate-in + gate-out events.
- `vessel.updateVesselShipmentStatus` for `arrived → customs_hold`, `customs_hold → customs_cleared`, `customs_cleared → discharged`, `discharged → gate_out`.
- `vessel.getISFStatus` — check ISF 10+2 before gate-in approved.
- `vessel.getUSCGPortEntry` — 33 CFR Part 160 port entry compliance validator.

---

## 3. Bulk gate actions

Port agent manages **50–400 containers per vessel call**. Bulk actions are essential (approve 20 gate-outs at once after a customs clearance batch posts).

Screen 3341 offers:
- **Selection mode** with multi-select checkbox column.
- **Batch-action toolbar** for bulk gate-in / gate-out / hold / release.

---

## 4. Flaky LTE + optimistic UI

Gate transactions are time-critical. App must work over notoriously flaky terminal LTE.

- **Optimistic UI with background sync.**
- **Conflict resolution** on reconnect.
- **Sync-pending badge** per affected container.

---

## 5. FROB — Freight Remaining On Board

FROB is cargo that remains on a vessel through a US port call because the vessel is only calling (not discharging that cargo). Under CBP 19 CFR 4, FROB must be manifested but is exempt from certain import formalities.

Mobile port agent screen (3343) surfaces FROB as **distinct list separate from discharge list** to prevent accidental gate-in attempts for FROB containers.

This is a tracked doctrine gap (P2) — FROB is not a distinct state in the 19-state lifecycle. The distinct list is the mitigation.

---

## 6. ISF status badge

Per [00_Overview.md §4](./00_Overview.md), ISF status surfaces as:
- `not_filed` — grey with "ISF Required."
- `filed` — amber.
- `cleared` — green.
- `overdue` — red with CBP penalty amount.

Container with ISF `not_filed` or `overdue` cannot be gated in. Mobile UI shows the block reason directly.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
