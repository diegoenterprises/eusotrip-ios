# 30 · Mode VESSEL — First Officer

**What this covers.** The `VESSEL_FIRST_OFFICER` role (maps to `VESSEL_OPERATOR` at the role enum) — screens 3320–3339, cargo plan (Bay Plan in 3D bay/row/tier), lashing inspection, IMDG segregation enforcement.

**When you need this.** When building 3320–3339. When wiring bay-plan visualization. When implementing lashing workflow.

**Cross-links.** Mode overview + IMDG: [00_Overview.md](./00_Overview.md). Captain (who authorizes): [01_Vessel_Captain.md](./01_Vessel_Captain.md). Terminal (who loads): [05_Vessel_Terminal_Operator.md](./05_Vessel_Terminal_Operator.md).

---

## 1. iOS screen range

**3320–3339** — First Officer Home, Cargo Plan, Lashing Inspection, Stability Calculator, Hatch Log.

- **3320 First Officer Home** — voyage snapshot + pending actions.
- **3322 Cargo Plan (Bay Plan)** — 3D bay/row/tier grid.
- **3323 Lashing Inspection** — per-bay checklist.
- **3326 Stability Calculator** — draft, trim, GM.
- **3330 Hatch Log** — opened/closed/secured per watch.

---

## 2. Backend procedures consumed

- `vessel.getVesselShipmentDetail` — per-container cargo detail.
- `vessel.recordContainerMovement` — mark containers as loaded, lashed, stowed with bay/row/tier coordinates.
- `vessel.getContainerTracking` — view movement history.
- `vessel.getVesselCompliance` — inspection records, ISPS (International Ship and Port Facility Security).

---

## 3. Cargo plan (Bay Plan)

Container ships stowed in 3D bay/row/tier coordinate system:
- **Bay**: longitudinal section (odd numbers for 20' slots, even for 40').
- **Row**: transverse column (even starboard, odd port, 00 at centerline).
- **Tier**: vertical layer (02–08 below deck, 82–92 above deck).

Mobile First Officer bay plan (3322) renders as **scrollable grid**, each cell a container:
- **Hazmat containers highlight in red.**
- **Reefers in blue with temperature readouts** from `containerTracking.temperature`.
- **Pinch-to-zoom + two-finger rotation mandatory** — 2D top-down (bay-row) combined with elevation (tier).

---

## 4. Lashing

Lashing rods, twistlocks, bridge fittings secure containers against heave/pitch/roll forces. First Officer walks deck at sea and inspects lashing after any heavy weather.

Screen 3323 Lashing Inspection is a **per-bay checklist** writing each bay's status to `vesselShipmentEvents` with `eventType: "lashing_inspection"`.

Must work in gloves + saltwater spray. Large buttons, high contrast, no swipe gestures for destructive actions.

---

## 5. IMDG segregation enforcement

Per [00_Overview.md §5](./00_Overview.md), IMDG Class 1 (explosives) cannot be stowed near Class 5 (oxidizers), etc. First Officer cargo plan must enforce segregation before marking bay as loaded. Screen 3322 highlights any stowage conflict in red.

The mobile UI is the gate — not just a visualization. If segregation conflict, the "mark bay loaded" action is disabled.

---

## 6. Unique UX considerations vs trucking

- 3D cargo coordinate system (bay/row/tier), not a list of loads.
- Pinch-zoom + two-finger-rotate mandatory.
- Lashing inspection is per-bay, post-weather-event, glove-operable.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
