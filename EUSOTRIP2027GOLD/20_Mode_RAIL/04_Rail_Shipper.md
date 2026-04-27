# 20 · Mode RAIL — Shipper

**What this covers.** The `RAIL_SHIPPER` role — screens 3180–3199, backend procedures, STCC (Standard Transportation Commodity Code) picker, AAR Bill of Lading format 5A, waybill tracker, hazmat shipper workflow with UN-number-triggered secondary form.

**When you need this.** When building 3180–3199. When integrating STCC lookup. When wiring BOL-5A form generation.

**Cross-links.** Mode overview + state machine: [00_Overview.md](./00_Overview.md). Truck shipper counterpart: [../10_Mode_TRUCK/05_Shipper.md](./../10_Mode_TRUCK/05_Shipper.md). Verticals (hazmat rail overlaps with hazmat truck): [../50_Verticals_Reference.md](./../50_Verticals_Reference.md).

---

## 1. iOS screen range

**3180–3199** — Shipper Home, Car Order, STCC Picker, Bill of Lading 5A, Waybill Tracker.

- **3180 Shipper Home** — active car orders + tracking. The primary action is **"Order Cars"** (plural by default), NOT "Post Load." Verbs differ from trucking throughout the shipper UI.
- **3181 Car Order** — tender workflow with equipment-type picker (boxcar, tankcar, hopper, flatcar, gondola, intermodal, autorack, centerbeam, coilcar, reefer, covered_hopper, open_hopper).
- **3182 STCC Picker** — type-ahead against STCC master table. 7-digit format enforced (no dashes on wire).
- **3184 BOL-5A** — form-first layout matching printed original.
- **3186 Waybill Tracker** — lifecycle visibility in railcar-days.

---

## 2. Backend procedures consumed

- `rail.createRailShipment` — origination with `stccCode, unNumber, hazmatClass, weight, carType`.
- `rail.getRailShipmentDetail` — full detail with waybills, events, demurrage, origin yard, destination yard.
- `rail.getRailTracking` — real-time event stream with most recent location.
- `search_rail_shipments` (MCP) — portfolio search for shipper's own pipeline.

---

## 3. STCC classification — mandatory field

Standard Transportation Commodity Code (STCC) is a 7-digit rail commodity identifier. Unlike HS codes or NMFC, STCC is the **ONLY acceptable commodity code** on a rail waybill.

Mobile STCC picker (3182) must:
- Type-ahead search against STCC master table.
- Enforce **7-digit format with no dashes** on the wire (UI may display `26 113 35` for readability but serializes `2611335`).
- **Warn when selected STCC is in hazmat range `48-xx-xx` or `49-xx-xx`** and force secondary hazmat form (UN number, hazmat class, placard choice).

---

## 4. Bill of Lading format 5A

AAR Bill of Lading Format 5A is the uniform straight bill of lading adopted by AAR. Unlike trucking's BOL (varies by carrier), Format 5A has **fixed field positions** and must include:
- Shipper name + complete address.
- Consignee name + complete address.
- Car initial and number (reporting marks).
- STCC.
- Description of articles.
- Weight.
- Car mark and seal numbers.
- Route.
- Phrase "Subject to uniform freight classification."

Mobile BOL-5A screen (3184) renders as **form-first** layout with same field order as printed original — enables operators to transcribe paper BOLs rapidly.

---

## 5. Unique UX considerations vs trucking

**Ship cars, not loads.** Shipper does not dispatch a truck; they **order a car**. Primary action on 3181 is "Order Cars" (plural by default), not "Post Load." Verbs throughout shipper UI differ.

**Time horizon.** Lifecycle visibility is in railcar-days, not miles. ETA display uses days and half-days, not hours, except on the final spot/unloading leg.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
