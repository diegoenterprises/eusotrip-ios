# 20 · Mode RAIL — Overview

**What this covers.** The top-level map of the RAIL mode on EusoTrip — 19-state rail lifecycle, FRA / PHMSA / STCC regulatory spine, the 6 rail roles and their iOS screen ranges (3100–3219), Class I roster, interchange gateways, demurrage automation, lease management, and links to per-role files. Source: wave-1 shard `team_RAIL_VESSEL_intermodal`.

**When you need this.** When starting any rail story, when scoping a rail backend change, when a rail PM asks "what's in scope for RAIL."

**Cross-links.** Per-role detail: [01_Rail_Operator.md](./01_Rail_Operator.md), [02_Rail_Dispatcher.md](./02_Rail_Dispatcher.md), [03_Rail_Yard_Master.md](./03_Rail_Yard_Master.md), [04_Rail_Shipper.md](./04_Rail_Shipper.md), [05_Rail_Broker.md](./05_Rail_Broker.md), [06_Rail_Conductor.md](./06_Rail_Conductor.md). Intermodal + cross-border (rail segments in multi-modal journeys): [40_Intermodal_and_Cross_Border.md](./../40_Intermodal_and_Cross_Border.md). Schema + state machine: [04_Database_and_Schema.md §5.2](./../04_Database_and_Schema.md).

---

## 0. Opening premise — why rail diverges from trucking

Trucking is 14-hour HOS windows, individual driver agency, single-leg freight event. Rail inverts every one of those. A rail shipment is a 7- to 21-day asset-bound journey where the shipper never sees the railcar, the conductor cannot swap duty with a stranger, and an STCC miscode can halt a train 900 miles from origin.

Mobile doctrine assumes operator is away from a desk: a conductor on a head-end in a canyon between Winslow and Flagstaff, a yard master holding a tablet in the rain at Willow Springs, a broker composing EDI 404s on an iPad at 22:30. Screens must be skimmable, forms large-touch-target, every compliance gate visible BEFORE committing a status transition, not as a server-side rejection after the fact.

---

## 1. Mode charter

Rail mode covers North American Class I, Class II/III (shortline), and transborder rail traffic. Backend structured around `railShipments` table, `trainConsists` table, `railYards` directory, and integrations with Railinc (Umler equipment tracking), FRA (inspection records), CloudMoyo (crew), Vizion (container visibility), and the six major Class I EDI pipelines (BNSF, UP, CSX, NS, KCS/CPKC, CN, CP).

- `railShipments.ts` exposes 16 core procedures.
- `railTenderWorkflow.ts` implements EDI 404/990 dialogue.
- `railDemurrageAuto.ts` runs accrual clock with country-specific free-time (US 48h, CA 48h, MX 24h).
- `railFreightAudit.ts` reconciles invoices against tariff.
- `railLeaseMgmt.ts` handles railcar lease + per-diem for TTX, GATX, CIT, private fleets.

---

## 2. 6 rail roles (SKILL §16 slice 03)

| Role enum | Screen range | File |
|---|---|---|
| `RAIL_DISPATCHER` | 3100–3119 | [02_Rail_Dispatcher.md](./02_Rail_Dispatcher.md) |
| `RAIL_CATALYST` / `RAIL_OPERATOR` (carrier) | 3120–3139 | [01_Rail_Operator.md](./01_Rail_Operator.md) |
| `RAIL_YARD_MASTER` | 3140–3159 | [03_Rail_Yard_Master.md](./03_Rail_Yard_Master.md) |
| `RAIL_BROKER` | 3160–3179 | [05_Rail_Broker.md](./05_Rail_Broker.md) |
| `RAIL_SHIPPER` | 3180–3199 | [04_Rail_Shipper.md](./04_Rail_Shipper.md) |
| `RAIL_CONDUCTOR` / `RAIL_ENGINEER` | 3200–3219 | [06_Rail_Conductor.md](./06_Rail_Conductor.md) |

---

## 3. 19-state rail lifecycle

Canonical state machine in `railShipments.ts` lines 182–202 as `VALID_RAIL_TRANSITIONS`. Mobile transition UI must respect this table exactly. The 19 canonical states with SKILL §16 slice 03 terminology mapped to the backend enum:

1. **`pending`** (API: `requested`) — shipment record created, no car ordered. Next: `car_ordered, cancelled, on_hold`. Screen: `RailShipmentDraftView`. Button: "Order Car."
2. **`car_ordered`** — carrier acknowledged car order, equipment being located. Next: `car_placed, cancelled, on_hold`. Amber "Car Ordered" badge. Countdown timer to placement SLA (typically 48h US, 24h MX).
3. **`car_placed`** — railcar spotted at shipper's facility, ready to load. Next: `loading, cancelled, on_hold`. Triggers push to shipper. Demurrage clock starts if shipper doesn't begin loading inside free time.
4. **`loading`** — loading in progress. "Loading-in-progress" state with weight-capture widget.
5. **`loaded`** — car loaded, seals applied, BOL-5A signed. Next: `in_consist, cancelled, on_hold`. Captures seal numbers (typically 2–4 per car).
6. **`in_consist`** — switched into train consist at origin yard. Join point between single-car and train-level workflow.
7. **`departed`** — train departed origin yard. Tracked via `multiModal.getRailOperations` and Vizion.
8. **`in_transit`** — moving between yards/interchanges. Location updates at yard-to-yard intervals, not GPS-pulse.
9. **`at_interchange`** — at Class I to Class I handoff point (Chicago, Memphis, New Orleans). Next: `in_transit, in_yard, cancelled, on_hold`. Interchange dwell is largest source of transit variability.
10. **`in_yard`** — arrived at destination railroad's classification yard. Next: `spotted, in_transit, cancelled, on_hold`.
11. **`spotted`** — spotted at consignee's siding. Demurrage clock starts on consignee side.
12. **`unloading`** — unloading in progress.
13. **`unloaded`** (SKILL alias: `delivered`) — all contents removed, car cleaned (if required). Next: `empty_returned`.
14. **`empty_returned`** — empty car returned to carrier. Per-diem accrual closes.
15. **`invoiced`** — carrier invoice issued.
16. **`settled`** — payment cleared. Auto-fires gamification events `load_completed` + `earnings_received` (lines 256–263).
17. **`cancelled`** — terminal cancellation. Reachable from any non-terminal state.
18. **`on_hold`** — reversible pause. Reachable from any non-terminal state, can return to any prior workable state except terminal ones.
19. **Three exception states** (`derailment_hold, hazmat_exception, interchange_delay`) — distinct from `on_hold` because they trigger regulatory notifications (FRA for derailment, PHMSA for hazmat release, neither for routine interchange delay). Mobile renders these in a red band with mandatory follow-up task.

---

## 4. FRA compliance

Most material to mobile doctrine:
- **49 CFR 213** — Track safety standards. Class 1–9 track classifications bound maximum speed (Class 1 = 10 mph freight, Class 5 = 80 mph freight). Dispatcher screen must display Class of route segment, not just ETA.
- **49 CFR 215** — Freight car safety standards: inspection interval (initial terminal air brake test before departure) and defects constituting bad-order condition.
- **49 CFR 217** — Operating rules: each railroad files operating rules with FRA. Mobile surfaces applicable rulebook version in conductor panel.
- **49 CFR 232** — Brake system safety standards: air brake test workflow (see [06_Rail_Conductor.md](./06_Rail_Conductor.md)).
- **49 CFR 240/242** — Engineer and conductor certification. Mobile cert-expiry warnings required.

---

## 5. PHMSA hazmat rail — HMR 49 CFR 171–180

- **Tank car specs — DOT-111 vs DOT-117.** Legacy DOT-111 ("soda cans on wheels") phased out of flammable liquids. Current standard for Class 3 flammable liquids (crude oil, ethanol) is DOT-117 — 9/16" steel shell, thermal protection, full-height head shields, improved top-fittings protection, bottom outlet handle removal. Mobile shipper STCC workflow must cross-check: if STCC in Class 3 flammable range and `carType = tankcar`, tank car spec on `railcars.carSpec` must be DOT-117 or DOT-117R (retrofitted) or DOT-117P (performance). DOT-111 paired with Class 3 STCC throws PRECONDITION_FAILED at `car_placed → loading` transition.
- **Placarding.** Each hazmat car displays placards on all four sides per 49 CFR 172 Subpart F. Mobile captures placard photos at loading stage (Camera + AI text recognition of UN number validates against manifest).
- **Emergency response information.** Every hazmat manifest includes Emergency Response Guidebook (ERG) reference. Mobile conductor manifest renders inline.
- **Hazmat permits.** `railHazmatPermits` table (referenced at railShipments.ts line 33) stores permit numbers for restricted commodities. Shipper cannot move `requested → car_ordered` for restricted hazmat STCC without valid permit record.

---

## 6. Class I railroads and interchange agreements

North American Class I roster:
- **BNSF** (reporting mark BNSF), **Union Pacific** (UP), **CSX Transportation** (CSX), **Norfolk Southern** (NS), **Canadian National** (CN, CNRL), **Canadian Pacific Kansas City** (CPKC — legacy CP + KCS merged 2023).
- Mexican Class I: **FXE** (Ferromex, Grupo México Transportes), **Ferrosur** (FSRR), **Kansas City Southern de México** (now CPKCM under CPKC).

`railTenderWorkflow.submitTender` validates carrier enum against `["BNSF", "UP", "NS", "CSX", "CPKC", "CN", "KCS", "FXE"]`. Mobile UI keeps display labels synchronized — "KCS" retained as legacy identifier for pre-merger tenders.

**Interchange agreements.** Class I carriers interchange at gateway locations via AAR-administered rules. Chicago dominant (six of seven Class I meet there), Memphis secondary, New Orleans handles Gulf, Kansas City handles West-Central, East St Louis Midwest-East. Dispatcher Interchange Map (3104) marks gateways with railroads that hand off and their historical median dwell (72h at Chicago is operational watermark).

---

## 7. Demurrage + detention automation

`railDemurrageAuto.ts` country-specific free time + rate:
- **US**: 48h free, $35/hr after.
- **CA**: 48h free, $35/hr after.
- **MX**: 24h free, $40/hr after.

Mobile surfaces `rail.calculateAccrual` on any shipment in `car_placed` or `spotted`, rendering live countdown. Dispute workflow (`rail.createDispute`) accepts reason codes `service_failure, weather, customer_error, data_error, other` + `requestedWaiverAmount`. Tap-to-dispute from demurrage card surfaces pre-filled dispute sheet. Bulk accrual runs hourly by cron invoking `rail.runBulkAccrual`.

---

## 8. Lease management — `railLeaseMgmt`

TTX (pooled industry flatcar fleet), GATX, CIT, Trinity, Union Tank Car, and private-fleet lessors = 80% of North American rolling stock (leased, not owned by operating railroad).

`railLeaseMgmt.ts` exposes:
- `dashboard` — active leases, renewals in next 30/90 days, monthly payment burn.
- `calculateLeaseCost` — car count × rate/car/day × 30.4 × term months + fees.
- `renewalCalendar` — 30/60/90/180 day lookahead.
- `perDiemAccrual` — per-diem on foreign cars, default $45/day.

Mobile renewal alerts critical: missed renewal can force lessee to return cars during peak demand at punitive spot rates.

---

## 9. Doctrine gaps tracked to resolution (RAIL-specific)

| Gap | Severity | Owner |
|---|---|---|
| Rail cert-expiry push notification not implemented | P2 | Mobile alerts team |

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
