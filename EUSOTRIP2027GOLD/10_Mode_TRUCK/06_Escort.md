# 10 · Mode TRUCK — Escort

**What this covers.** The TRUCK::Escort doctrine — four archetypes (Pilot Car Driver, Hazmat Escort, Oversize/Overweight Escort, Heavy-Haul Convoy Coordinator), 6-phase lifecycle (Receive Tender → Equipment Check → Lead/Follow Assignment → Route Pre-Clearance → Active Escort → Handoff), screens 600–617, backend `escorts.ts` (116 KB — one of largest in codebase), permits + route restrictions (`permits.ts`, `convoy.ts`), multi-escort coordination (front/rear/flagger/police/utility), handoff flow at state lines, pay model (flat/hourly/mileage + reimbursements), safety stack (LiDAR bridge-clearance, mesh radio, `ergoMonitor.ts`), state-by-state licensure (WA, GA, VA, FL, NY, WI, OK etc.), hazmat escort subset (Division 1.1 explosives, Class 7 radioactive, chlorine + anhydrous ammonia). Source: wave-1 shard `team_TRUCK_shipper_escort` Part II.

**When you need this.** When building 600-series screens. When scoping any superload workflow. When wiring mesh-radio, LiDAR clearance, or permit ingestion.

**Cross-links.** Shipper counterpart: [05_Shipper.md](./05_Shipper.md). Convoy + mesh on watch: [60_Offline_First_and_Pulse_Watch.md](./../60_Offline_First_and_Pulse_Watch.md) (F09 MeshRelay, F13 Convoy Coordinator). Verticals: [50_Verticals_Reference.md](./../50_Verticals_Reference.md).

---

## 1. Escort persona

The Escort is the unsung specialist of heavy and oversize freight — pilot-car operator, flagger, convoy coordinator whose presence is legally mandated for loads exceeding state-specific thresholds. Four archetypes:

**Pilot Car Driver.** Operates marked lead or chase vehicle (typically a pickup with rooftop "OVERSIZE LOAD" sign + high-flag poles). Certified in at least one state, often many. Works for escort company or owner-operator. Pay averages $1.50–$3.00/mile with minimums + overnight add-ons.

**Hazmat Escort.** Specialized pilot operator qualified to escort placarded hazmat — particularly Division 1.1 explosives (DoD munitions), Class 7 radioactive (spent nuclear fuel, medical isotopes), Division 2.3 poison-inhalation-hazard gases (chlorine, anhydrous ammonia tank trucks in some jurisdictions).

**Oversize/Overweight Escort.** Pilot operator certified with height-pole calibration, bridge-clearance verification training, route-survey experience. Common on loads exceeding 12' wide, 14'6" high, or 100' long.

**Heavy-Haul Convoy Coordinator.** Operates in multi-vehicle configurations: front car, rear car, often a flagger in separate vehicle for intersection control. Coordinates superloads (> 250,000 lbs combined GVWR) that may require police escort, utility-company pole-raise coordination, pre-run route surveys.

---

## 2. Escort lifecycle — 6 phases

**Phase 1 — Receive Escort Tender.** Escort company or independent operator receives tender from prime carrier (or directly from shipper for in-house moves). Tender includes load dimensions, route, required escort count, state certifications needed, rate.

**Phase 2 — Equipment Check.** Pre-trip inspection of pilot vehicle: signs, flags, flashing amber lights, CB/VHF radio, height pole (with documented calibration), first-aid kit, fire extinguisher, reflective triangles, certification documentation.

**Phase 3 — Lead/Follow Position Assignment.** Escort role confirmed — front (lead) car, rear (chase) car, or flagger. Front car runs height pole, scouts bridges, warns of low clearances. Rear car manages merging traffic + lane-change coverage.

**Phase 4 — Route Pre-Clearance.** For superloads, escort reviews permitted route, identifies all bridges/overpasses, pre-drives critical sections if required, confirms utility-line clearances.

**Phase 5 — Active Escort.** Convoy executes move. Continuous radio communication, height-pole strikes trigger emergency stop, rear car manages slowdown of following traffic, front car coordinates with police at major intersections.

**Phase 6 — Handoff.** At state lines or shift changes, escort hands off to next certified operator. Handoff packet includes route notes, incidents, remaining mileage, fuel/lunch status.

---

## 3. iOS screens — 600s range

- **600 — Escort Home.** Active assignment card, equipment checklist, certifications status.
- **601 — Tender Inbox.** Incoming escort offers.
- **602 — Tender Detail.** Route map, load specs, pay, accept/decline.
- **603 — Pre-Trip Inspection.** Photo-driven checklist of pilot vehicle.
- **604 — Height-Pole Calibration Log.** Proof of recent calibration.
- **605 — Certifications Wallet.** State-by-state escort licenses.
- **606 — Convoy Dashboard.** Live map of all convoy vehicles, radio channel indicator.
- **607 — Mesh Radio Panel.** Push-to-talk across convoy.
- **608 — Bridge/Clearance Alerts.** Upcoming low structures with LiDAR-verified clearance.
- **609 — Route Pre-Clear.** Turn-by-turn annotated with hazards.
- **610 — Incident Report.** Strike, detour, traffic stop.
- **611 — Handoff Ticket.** State-line or shift-change transfer.
- **612 — Pay Ledger.** Flat-fee vs hourly, lunch/overnight accruals.
- **613 — Permits Viewer.** All load permits, state-by-state.
- **614 — Convoy Brief.** Pre-departure briefing sheet signed by all escorts.
- **615 — Hazmat Escort Module.** Class-specific protocols.
- **616 — Superload Thresholds Reference.** Each state's oversize/overweight triggers.
- **617 — Ergo Monitor.** Fatigue/posture alerts for long escort days.

---

## 4. Backend — `escorts.ts` (116 KB)

At 116 KB, `escorts.ts` is one of largest routers in codebase — rivaled only by Carrier + Broker modules. Size reflects operational depth:

- Multi-state certification matrix (50 states, each with own licensure rules).
- Convoy composition rules (front-only, front+rear, front+rear+flagger, police-escort-required).
- Dynamic escort-count calculation based on load dimensions, route classification, state-specific thresholds.
- Tender-matching engine respecting escort company dispatch boards + owner-operator availability.
- Handoff state-machine with audit trail.
- Mesh-radio session management + recording.
- LiDAR bridge-clearance telemetry ingestion.
- Pay calculation engine (flat-fee, hourly, mileage, reimbursement).
- Integration hooks to `permits.ts`, `convoy.ts`, `safety.ts`, `compliance.ts`.

---

## 5. Permits + route restrictions

**`permits.ts`** manages oversize/overweight permits at state, province, county, municipal levels. Each state's permitting portal (TxDOT, Caltrans, FDOT, PennDOT, etc.) exposes different APIs and workflows. EusoTrip abstracts behind unified interface: submit dimensions, receive permit PDF + permitted-route GIS trace, surface bridge-clearance minimums along route.

**`convoy.ts`** orchestrates multi-vehicle movement. Convoy state modeled as single logical entity with member vehicles, each streaming position, speed, radio-channel state. Bridge clearances checked against load's permitted height at every upcoming structure; if margin drops below configurable threshold (default 6 inches), convoy auto-halted and operator prompted to verify visually.

---

## 6. Multi-escort coordination

Typical superload convoy runs four to six operators:

- **Front car** — height pole, primary scout, intersection-clearance coordinator.
- **Rear car** — merging-traffic control, lane-change coverage, rear-end-collision prevention.
- **Flagger** — at intersections and turns too tight for through-traffic; deploys ahead on foot with stop/slow paddle.
- **Police escort** — state-trooper or contracted off-duty officer for signal preemption + traffic holds.
- **Utility coordinator** — rides ahead coordinating pole-raises + line-lifts with local utility.

All convoy members share single mesh-radio channel (607). Radio transcripts auto-recorded, retained 90 days, available for incident review.

---

## 7. Handoff flow

State-line transfers are defining operational moment for interstate superloads. Escort certified in Texas may not be certified in Louisiana; convoy must swap at or near state line.

1. Outgoing escort submits handoff ticket (611): remaining route, incidents so far, fuel status, known upcoming hazards.
2. Incoming escort reviews + acknowledges.
3. Both parties sign digital trip ticket.
4. Pay ledgers adjust: outgoing crystallizes; incoming begins.
5. Radio channel re-keyed; radio re-check performed.

---

## 8. Pay model

- **Flat-fee per trip** — common for short point-to-point (e.g., $350 for 40-mile rural).
- **Hourly** — typical for urban or stop-and-go ($65–$85/hour).
- **Mileage** — $1.50–$3.00/loaded mile.
- **Deadhead** — reduced rate for return-empty.
- **Lunch reimbursement** — $15–$25/day, receipted or per-diem.
- **Overnight reimbursement** — hotel + $50 incidental, or per-diem $100–$150.
- **Minimum-day guarantee** — 4 or 8 hour minimum even on short jobs.

Pay engine computes all components automatically from escort's timesheet, GPS trail, receipted expenses.

---

## 9. Safety stack

**LiDAR Bridge-Clearance Check.** Pilot vehicles equipped with roof-mounted LiDAR continuously measure overhead clearance ahead of convoy. Measurement compared against load's height (stored at tender); alarm triggers if projected clearance falls below threshold.

**Mesh Radio Network.** Purpose-built mesh-networking layer allows convoy members to remain in voice contact across 2–5 miles of separation without relying on cellular or FRS/GMRS fragility. Digital push-to-talk with automatic channel health monitoring.

**`ergoMonitor.ts`.** Escort work is sedentary-but-attentive — hours of high-alert driving. Ergo monitor samples wheel-grip tension, gaze direction (via inward-facing camera, opt-in), stint duration. Suggests micro-breaks, flags fatigue indicators, enforces 15-minute rest after 4 continuous hours that several state regulations require.

---

## 10. Regulatory — state-by-state licensure

No federal escort license. Each state defines own regime:

- Some states (Washington, Georgia, Virginia, Florida, New York, Wisconsin, Oklahoma) require formal certification with background check, written exam, driving-record review.
- Others require only carrier-provided training.
- A few have no formal requirement.

Superload thresholds also vary:
- Texas: > 254,300 lbs gross OR > 16' wide OR > 18'11" high.
- California: varies by route classification.
- Pennsylvania: > 201,000 lbs.
- New York: > 200,000 lbs, with NYC-specific overlays.

616 provides real-time reference; `escorts.ts` enforces correct escort count + certification at tender-acceptance time.

---

## 11. Hazmat escort subset

Dedicated subset work placarded hazmat:

**Division 1.1 Explosives.** DoD munitions (AA&E — Arms, Ammunition, Explosives). Requires Secret-clearance driver, constant surveillance rule (49 CFR 397.5), safe-haven route planning, often DoD-contracted escorts in lead-and-chase configuration.

**Class 7 Radioactive.** Spent nuclear fuel (NRC-regulated), medical isotopes, industrial radiography sources. Requires NRC route approval, pre-notification of governors of transit states, real-time tracking feed to NRC operations center.

**Chlorine and Anhydrous Ammonia Tank Trucks.** Not always escort-required, but in dense urban corridors or through designated hazmat-restricted zones, state DOTs mandate escort. Emergency-response plan (HM-232) must be on-vehicle, escort app surfaces nearest TRANSCAER-registered response team.

---

## Closing note

The Shipper and Escort roles sit at opposite ends of the freight workflow — Shipper originating demand, Escort enabling supply to move safely when that demand involves extraordinary cargo. Both are first-class personas in EusoTrip Mobile App Doctrine 2027, with dedicated screen ranges, deeply-instrumented backend routers, compliance overlays, wallet instruments. Neither is an afterthought bolted onto a driver-centric app; both are built as the respected professionals they are.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
