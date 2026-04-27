# 30 · Mode VESSEL — Shipping Line Operations

**What this covers.** The `VESSEL_SHIPPING_LINE` role — screens 3360–3379, blank sailing dashboard, slot allocation against MQC (Minimum Quantity Commitment), schedule management, service performance analytics.

**When you need this.** When building 3360–3379. When wiring blank-sailing alerts. When scoping slot-allocation UX for shipping-line ops teams.

**Cross-links.** Mode overview + blank sailings: [00_Overview.md](./00_Overview.md). NVOCC (who books slots from the line): [06_Vessel_NVOCC_Forwarder.md](./06_Vessel_NVOCC_Forwarder.md).

---

## 1. iOS screen range

**3360–3379** — Line Ops Home, Blank Sailing Dashboard, Slot Allocation, Schedule, Service Performance.

- **3360 Line Ops Home** — service overview + alerts.
- **3361 Blank Sailing Dashboard** — trade-lane-by-week heatmap with each cell tappable for affected bookings.
- **3362 Slot Allocation** — contracted MQC, YTD-used, current-sailing availability.
- **3365 Schedule** — full scheduled voyages, reefer + hazmat overlays.
- **3370 Service Performance** — schedule reliability (on-time port calls), transit-time drift.

---

## 2. Backend procedures consumed

- `multiModal.SHIPPING_LINES` catalog — Maersk, MSC, CMA CGM, COSCO, Hapag-Lloyd, ONE, Evergreen, Yang Ming, ZIM.
- `vessel.getVesselSchedules` — full scheduled voyages.
- `blank_sailing_dashboard` (MCP tool) — integrated view of announced blank sailings by line/trade lane.
- `vessel.searchRates` — rate card queries by lane and container size.

---

## 3. Blank sailings

A **blank sailing** is an announced cancellation of a scheduled port call. In soft market conditions, carriers blank 15–25% of capacity on trans-Pacific eastbound to prop up rates.

Blank sailings cascade into:
- Chassis shortages.
- Drayage bottlenecks.
- Warehouse receiving chaos.

Mobile Blank Sailing Dashboard (3361) renders a **trade-lane-by-week heatmap** with each cell tappable for affected bookings.

Every blank sailing affecting an active booking auto-generates a `booking_rolled` event on the affected shipment (transition `booking_confirmed → rolled`). Customer notified within 5 minutes of blank announcement.

---

## 4. Slot allocation

A shipping line allocates slots (TEU capacity per sailing) across contracted shippers, BCOs (beneficial cargo owners), and NVOCCs.

Slot allocation panel (3362) shows:
- **Contracted MQC** (Minimum Quantity Commitment).
- **YTD-used** against commitment.
- **Current-sailing availability.**

MQC shortfalls flag automatically — line-ops can initiate customer conversations early.

---

## 5. Service performance

Screen 3370 tracks:
- **Schedule reliability** — % port calls on time, by service + by port.
- **Transit-time drift** — observed vs advertised.
- **Blank sailing ratio** — blanks as % of scheduled.

These feed contract renegotiation + customer scorecards.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
