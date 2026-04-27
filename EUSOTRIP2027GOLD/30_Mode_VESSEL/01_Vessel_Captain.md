# 30 · Mode VESSEL — Captain

**What this covers.** The `SHIP_CAPTAIN` role — screens 3300–3319, bridge-mode UX, SMCP (Standard Marine Communication Phrases), 18–22-day satcom offline handling, weather-routing, vessel fleet view.

**When you need this.** When building 3300–3319. When wiring satcom sync. When scoping bridge-log or radio panel.

**Cross-links.** Mode overview + state machine: [00_Overview.md](./00_Overview.md). First Officer (who manages cargo plan): [02_Vessel_First_Officer.md](./02_Vessel_First_Officer.md). Offline doctrine: [../60_Offline_First_and_Pulse_Watch.md](./../60_Offline_First_and_Pulse_Watch.md).

---

## 1. iOS screen range

**3300–3319** — Captain Home, Voyage Plan, Bridge Log, Radio/SMCP Panel, Navigation Chart, Weather Overlay.

- **3300 Captain Home** — active voyage + weather overview.
- **3301 Navigation Chart** — AIS positions + route polyline.
- **3302 Voyage Plan** — port-to-port schedule.
- **3303 Radio / SMCP Panel** — pre-canned SMCP phrases (quick-tap).
- **3304 Bridge Log** — watch-by-watch append-only log.
- **3310 Weather Overlay** — DTN Marine Weather routing.

---

## 2. Backend procedures consumed

- `vessel.getVesselShipmentDetail` — full booking detail for voyage.
- `vessel.getVesselSchedules` — master's view of voyage plan.
- `vessel.updateVesselShipmentStatus` for `departed → in_transit`, `in_transit → arrived`.
- `marineTrafficService` (via `vessel.getVesselFleet` and `vessel.getContainerPositions`) — AIS positions.
- DTN Marine Weather overlay — at-sea weather routing.

---

## 3. SMCP (Standard Marine Communication Phrases)

IMO SMCP is the standardized English vocabulary for shipboard-to-shipboard and ship-to-shore radio traffic.

Mobile Radio Panel (3303) provides **pre-canned SMCP phrases** for common events:
- Pilot request.
- Anchor station.
- Distress relay.
- Pilotage.
- Anchor reporting.
- Vessel traffic service.

**Quick-tap UI, not keyboard input** — captain on bridge needs to transmit standard phrases without composing text.

---

## 4. Offline — 18–22 day satcom

Captain is offline for 18–22 days at a stretch between ports. **Full offline mode is mandatory** for screens 3300–3309 with a **satcom sync** strategy:
- App queues outbound events and flushes them on 30-second satcom burst windows.
- Screens designed to render with stale (last-sync) data and display sync timestamp prominently.
- Pending-sync badge visible.

---

## 5. Bridge-watch UX

- Bridge watch mode dims non-essential UI.
- Defaults to **red-light night mode after local sunset** (preserves bridge team's night vision).
- All primary actions glove-operable.

---

## 6. Unique UX considerations vs trucking

- Device can be out of connectivity for weeks, not hours. Offline is NOT a fallback — it is the primary operating mode.
- Red-light night mode by local sunset, not system dark-mode toggle.
- Every screen shows a visible sync timestamp. Not decorative — load-bearing.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
