# 20 · Mode RAIL — Broker

**What this covers.** The `RAIL_BROKER` role — screens 3160–3179, backend procedures, EDI 404 submit / EDI 990 receive dialogue, 24-hour lifecycle card, rate calculator with monthly-indexed fuel surcharge (different from weekly-indexed trucking FSC), invoice audit with duplicate detection.

**When you need this.** When building 3160–3179. When wiring EDI 404/990 encoders. When scoping rail-rate-calculator workflows.

**Cross-links.** Mode overview + state machine: [00_Overview.md](./00_Overview.md). Truck broker counterpart (data-first, desk-first, similar mobile asymmetry): [../10_Mode_TRUCK/04_Broker.md](./../10_Mode_TRUCK/04_Broker.md). Catalyst counterpart (rail catalyst = `RAIL_CATALYST`): not currently spec'd — see truck [../10_Mode_TRUCK/03_Catalyst.md](./../10_Mode_TRUCK/03_Catalyst.md) for the general pattern.

---

## 1. iOS screen range

**3160–3179** — Broker Home, Tender Board, Class I Submit, Rate Calculator, Margin Ledger.

- **3160 Broker Home** — brokered lane pipeline + margin strip.
- **3161 Tender Board** — 24-hour lifecycle cards (see §3).
- **3162 Class I Submit** — EDI 404 composition + preview (see §4).
- **3163 Rate Calculator** — FSC breakdown (see §5).
- **3165 Margin Ledger** — per-lane margin roll-up.

---

## 2. Backend procedures consumed

- `railTenderWorkflow.submitTender` — assembles **EDI 404** (Rail Carrier Shipment Information) and submits to a Class I (BNSF, UP, NS, CSX, CPKC, CN, KCS, FXE).
- `railTenderWorkflow.receiveTenderResponse` — parses **EDI 990** back (response code A = accepted, D = declined, P = pending).
- `railTenderWorkflow.tenderHistory` — tender lifecycle ledger.
- `rail.createRailShipment` — broker-originated shipments pre-populate STCC, car type, pickup date for downstream tender.
- `rail.getRailShipments` — pipeline view of all brokered lanes.
- `railFreightAudit.auditInvoice` — reconcile carrier invoice against tariff, flag duplicates, overcharges (>5% variance = warning, >15% = critical).

---

## 3. 24-hour lifecycle card

Trucking brokers book in minutes. Rail brokers book in hours-to-days.

Tender Board (3161) uses a **24-hour lifecycle card** that visually ages:
- Turns **amber** at 30 min without EDI 990 response.
- Turns **red** at 60 min.
- **Push notification** if overnight tender is still pending at 0800 local.

---

## 4. EDI 404 composition preview

Composition done server-side, but broker mobile screen must show **human-readable preview** (shipper, consignee, origin SCAC, destination SCAC, STCC, car type, pickup, railcar count) before submission.

**Accidental tender to wrong Class I is hard to recall.** The preview is the gate.

---

## 5. Rate Calculator — monthly-indexed FSC

Screen 3163 pulls from `railRateService`. Must surface **fuel-surcharge (FSC) component separately from linehaul**.

**Rail FSC is indexed to monthly average HDD diesel prices**, not weekly like trucking. This is material — a rail FSC that works like trucking FSC will over-index short-term volatility and under-compensate trend moves.

Line-item layout:
1. Linehaul (contract or spot).
2. Accessorials.
3. FSC (monthly-indexed).
4. Subtotal.

---

## 6. Unique UX considerations vs trucking

- 24-hour lifecycle cards, not 30-minute countdowns.
- EDI 404 preview mandatory — accidental Class I tender is not easily recalled.
- FSC line is separate and monthly-indexed, distinctive from trucking.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
