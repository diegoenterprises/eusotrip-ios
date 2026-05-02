# Shipper↔Driver Scenario Taxonomy (8000-scenario E2E sweep)

This is the canonical taxonomy that powers `generate_scenarios.py`. The
combinatorial product of the four dimensions below yields exactly
**8 000** unique scenarios, each one capturing a distinct interaction
between a shipper and a driver under a specific cargo profile, event
trigger, and counter-party arrangement.

```
PHASES (20) × CARGO (10) × TRIGGER (10) × CONTEXT (4) = 8 000
```

Every scenario answers four questions:

1. *What phase of the trip lifecycle are we in?*
2. *What is being moved?*
3. *What's going wrong (or going right)?*
4. *Who is between the shipper and the driver — direct, broker, catalyst,
   or chain?*

---

## Dimension 1 — Phase (20)

Every shipper-driver interaction lives in one of these phases. The
ordering walks the load lifecycle from posting through post-trip.

| #  | Phase                       | Direction (shipper→driver / driver→shipper) |
|----|-----------------------------|---------------------------------------------|
| 01 | Load posting                | shipper → market → driver                   |
| 02 | Load discovery              | driver-pull (search / filters)              |
| 03 | Bidding                     | driver → shipper                            |
| 04 | Counter-offer chain         | bidirectional                               |
| 05 | Booking / acceptance        | shipper → driver                            |
| 06 | Dispatch communication      | bidirectional (chat, ESANG)                 |
| 07 | Document exchange           | bidirectional (rate-con, BOL pre-pickup)    |
| 08 | Pre-trip / driver readiness | driver-attest, shipper-verify               |
| 09 | En-route tracking           | driver-emit, shipper-consume                |
| 10 | Pickup operations           | bidirectional (dock door, weight ticket)    |
| 11 | In-transit telemetry        | driver-emit, shipper-consume                |
| 12 | Delivery operations         | bidirectional                               |
| 13 | POD capture & approval      | driver-emit → shipper-approve               |
| 14 | Detention / accessorial     | driver-claim → shipper-approve              |
| 15 | Settlement / payment        | shipper-release → driver-receive            |
| 16 | Dispute                     | bidirectional                               |
| 17 | Cancellation                | bidirectional (TONU, late cancel)           |
| 18 | Rating / review             | bidirectional                               |
| 19 | Recurring loads             | shipper-schedule → driver-recurring         |
| 20 | Compliance signals          | system-driven (FMCSA pulls, insurance)      |

## Dimension 2 — Cargo type (10)

Each cargo class triggers different regulatory, equipment, and
documentation requirements. Hazmat variants get individual entries
per the doctrine that hazmat is the most stringent lens.

| #  | Cargo type                  | Equipment baseline       |
|----|-----------------------------|--------------------------|
| 01 | Dry van                     | 53' van                  |
| 02 | Reefer (refrigerated)       | 53' reefer + temp probe  |
| 03 | Flatbed (open deck)         | 48' flat + tarp + chains |
| 04 | Tanker — petroleum          | DOT-406 cargo tank       |
| 05 | Tanker — chemical           | DOT-407 / -412 spec      |
| 06 | Hazmat class-3 flammable    | placards + ERG + UN+PG   |
| 07 | Hazmat class-8 corrosive    | placards + ERG + UN+PG   |
| 08 | Hazmat class-7 radioactive  | placards + ERG + RAM-OPS |
| 09 | Container (intermodal)      | chassis + drayage docs   |
| 10 | Oversized / overweight      | permit + escort + route  |

## Dimension 3 — Event trigger (10)

The "what's going on" axis. Most scenarios are NOT happy-path — that's
where the value of an exhaustive sweep lives.

| #  | Trigger                     | Frequency profile                |
|----|-----------------------------|----------------------------------|
| 01 | Happy path                  | baseline (no exception)          |
| 02 | Weather delay               | regional, hours-to-days impact   |
| 03 | Mechanical breakdown        | unplanned, often roadside        |
| 04 | Traffic / road closure      | acute, route-recompute           |
| 05 | Accident / incident         | escalation chain to safety       |
| 06 | Customs hold (cross-border) | applicable to USMCA + maritime   |
| 07 | Missed appointment          | dock-window violation            |
| 08 | Document defect             | BOL mismatch, missing seal #     |
| 09 | Route deviation             | driver-initiated detour          |
| 10 | HOS violation risk          | predictive — clock running short |

## Dimension 4 — Counter-party context (4)

Who sits between the shipper and the driver?

| Letter | Context                  | Mediator                       |
|--------|--------------------------|--------------------------------|
| A      | Direct shipper→driver    | none — owner-operator          |
| B      | Broker-routed            | broker (TIA-style intermediary) |
| C      | Catalyst-managed         | carrier company employs driver  |
| D      | Multi-stop / chain       | shipper of record + receivers   |

---

## Coverage Flag Vocabulary

For each scenario, EusoTrip's coverage is one of:

- **PASS** — End-to-end implementation present: backend procedure
  exists, iOS surface consumes it, no web-continuation gap.
- **PARTIAL** — Implemented for one party (shipper OR driver) but not
  both; OR: implementation exists but routes through a Safari sheet for
  the user-facing form; OR: implementation works for happy-path but
  not for the trigger condition.
- **MISSING** — No backend procedure or no client surface — the
  business cannot run this scenario today.

For Uber Freight and CloudTrucks: `Y` (offered), `N` (not offered),
`?` (no public info).

## Severity Vocabulary

For gap rows where EusoTrip is MISSING or PARTIAL:

- **P0** — Business cannot run without this. Blocker for "1000% able to
  run" claim.
- **P1** — Material parity gap. Competitor has it; we don't.
- **P2** — Quality-of-life or edge-case gap.
- **P3** — Nice-to-have / future surface.

---

## Generator output

`generate_scenarios.py` reads the coverage map at
`eusotrip_shipper_driver_coverage.md` and the competitor catalogs at
`uber_freight_features.md` + `cloudtrucks_features.md`, then emits:

- `scenarios.csv` — 8 000 rows, one per scenario, full coverage matrix
- `gap_summary.md` — executive summary, prioritized fix list
- `gap_by_phase.md` — per-phase deep-dive of every MISSING/PARTIAL row

Run: `python3 generate_scenarios.py`
