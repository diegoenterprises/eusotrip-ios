# Per-Phase Deep Dive


## Load posting

_400 scenarios · 80 gaps_

### P1 — 40 scenarios

- **S-01-08-01-A** · Hazmat class-7 radioactive · Happy path · Direct shipper→driver — coverage PARTIAL; UF Y / CT N. _Note:_ Hazmat-7 radioactive RAM-OPS schema fields exist but UI lacks NRC license validation
- **S-01-08-01-B** · Hazmat class-7 radioactive · Happy path · Broker-routed — coverage PARTIAL; UF Y / CT N. _Note:_ Hazmat-7 radioactive RAM-OPS schema fields exist but UI lacks NRC license validation
- **S-01-08-01-C** · Hazmat class-7 radioactive · Happy path · Catalyst-managed — coverage PARTIAL; UF Y / CT N. _Note:_ Hazmat-7 radioactive RAM-OPS schema fields exist but UI lacks NRC license validation
- **S-01-08-01-D** · Hazmat class-7 radioactive · Happy path · Multi-stop / chain — coverage PARTIAL; UF Y / CT N. _Note:_ Hazmat-7 radioactive RAM-OPS schema fields exist but UI lacks NRC license validation
- **S-01-08-02-A** · Hazmat class-7 radioactive · Weather delay · Direct shipper→driver — coverage PARTIAL; UF Y / CT N. _Note:_ Hazmat-7 radioactive RAM-OPS schema fields exist but UI lacks NRC license validation
- _… and 35 more (see scenarios.csv)_

### P2 — 40 scenarios

- **S-01-10-01-A** · Oversized / overweight · Happy path · Direct shipper→driver — coverage PARTIAL; UF Y / CT N. _Note:_ Oversized permit + escort flow exists but per-state permit autoload is web-only
- **S-01-10-01-B** · Oversized / overweight · Happy path · Broker-routed — coverage PARTIAL; UF Y / CT N. _Note:_ Oversized permit + escort flow exists but per-state permit autoload is web-only
- **S-01-10-01-C** · Oversized / overweight · Happy path · Catalyst-managed — coverage PARTIAL; UF Y / CT N. _Note:_ Oversized permit + escort flow exists but per-state permit autoload is web-only
- **S-01-10-01-D** · Oversized / overweight · Happy path · Multi-stop / chain — coverage PARTIAL; UF Y / CT N. _Note:_ Oversized permit + escort flow exists but per-state permit autoload is web-only
- **S-01-10-02-A** · Oversized / overweight · Weather delay · Direct shipper→driver — coverage PARTIAL; UF Y / CT N. _Note:_ Oversized permit + escort flow exists but per-state permit autoload is web-only
- _… and 35 more (see scenarios.csv)_


## Load discovery

_400 scenarios · 400 gaps_

### P2 — 400 scenarios

- **S-02-01-01-A** · Dry van · Happy path · Direct shipper→driver — coverage PARTIAL; UF Y / CT Y. _Note:_ Driver search wired; shipper-side mobile catalyst-scout / driver-search UX missing (web only)
- **S-02-01-01-B** · Dry van · Happy path · Broker-routed — coverage PARTIAL; UF Y / CT Y. _Note:_ Broker-routed discovery: UF Lane Explorer 14d forward, CT Exchange (post-Shipwell)
- **S-02-01-01-C** · Dry van · Happy path · Catalyst-managed — coverage PARTIAL; UF Y / CT Y. _Note:_ Driver search wired; shipper-side mobile catalyst-scout / driver-search UX missing (web only)
- **S-02-01-01-D** · Dry van · Happy path · Multi-stop / chain — coverage PARTIAL; UF Y / CT Y. _Note:_ Driver search wired; shipper-side mobile catalyst-scout / driver-search UX missing (web only)
- **S-02-01-02-A** · Dry van · Weather delay · Direct shipper→driver — coverage PARTIAL; UF Y / CT Y. _Note:_ Driver search wired; shipper-side mobile catalyst-scout / driver-search UX missing (web only)
- _… and 395 more (see scenarios.csv)_


## Bidding

_400 scenarios · 40 gaps_

### P3 — 40 scenarios

- **S-03-01-08-A** · Dry van · Document defect · Direct shipper→driver — coverage PARTIAL; UF Y / CT Y. _Note:_ Bid validation against doc defects (BOL mismatch) is post-bid, not pre-bid
- **S-03-01-08-B** · Dry van · Document defect · Broker-routed — coverage PARTIAL; UF Y / CT Y. _Note:_ Bid validation against doc defects (BOL mismatch) is post-bid, not pre-bid
- **S-03-01-08-C** · Dry van · Document defect · Catalyst-managed — coverage PARTIAL; UF Y / CT Y. _Note:_ Bid validation against doc defects (BOL mismatch) is post-bid, not pre-bid
- **S-03-01-08-D** · Dry van · Document defect · Multi-stop / chain — coverage PARTIAL; UF Y / CT Y. _Note:_ Bid validation against doc defects (BOL mismatch) is post-bid, not pre-bid
- **S-03-02-08-A** · Reefer · Document defect · Direct shipper→driver — coverage PARTIAL; UF Y / CT Y. _Note:_ Bid validation against doc defects (BOL mismatch) is post-bid, not pre-bid
- _… and 35 more (see scenarios.csv)_


## Counter-offer chain

_400 scenarios · 400 gaps_

### P1 — 400 scenarios

- **S-04-01-01-A** · Dry van · Happy path · Direct shipper→driver — coverage PARTIAL; UF N / CT N. _Note:_ Direct shipper<>driver counter chains work shipper-side, no driver inbox
- **S-04-01-01-B** · Dry van · Happy path · Broker-routed — coverage PARTIAL; UF N / CT N. _Note:_ Driver-side counter-receive screen + push notification on counter-inbound MISSING; we lead UF + CT here once driver inbox lands
- **S-04-01-01-C** · Dry van · Happy path · Catalyst-managed — coverage PARTIAL; UF N / CT N. _Note:_ Catalyst-managed: catalyst dispatcher sees counter via web, driver doesn't
- **S-04-01-01-D** · Dry van · Happy path · Multi-stop / chain — coverage PARTIAL; UF N / CT N. _Note:_ Driver-side counter-receive screen + push notification on counter-inbound MISSING; we lead UF + CT here once driver inbox lands
- **S-04-01-02-A** · Dry van · Weather delay · Direct shipper→driver — coverage PARTIAL; UF N / CT N. _Note:_ Direct shipper<>driver counter chains work shipper-side, no driver inbox
- _… and 395 more (see scenarios.csv)_


## Booking / acceptance

_400 scenarios · 40 gaps_

### P2 — 40 scenarios

- **S-05-01-07-A** · Dry van · Missed appointment · Direct shipper→driver — coverage PARTIAL; UF Y / CT Y. _Note:_ Auto-rebook on missed-appointment fallback not implemented (UF Auto-Tender has this)
- **S-05-01-07-B** · Dry van · Missed appointment · Broker-routed — coverage PARTIAL; UF Y / CT Y. _Note:_ Auto-rebook on missed-appointment fallback not implemented (UF Auto-Tender has this)
- **S-05-01-07-C** · Dry van · Missed appointment · Catalyst-managed — coverage PARTIAL; UF Y / CT Y. _Note:_ Auto-rebook on missed-appointment fallback not implemented (UF Auto-Tender has this)
- **S-05-01-07-D** · Dry van · Missed appointment · Multi-stop / chain — coverage PARTIAL; UF Y / CT Y. _Note:_ Auto-rebook on missed-appointment fallback not implemented (UF Auto-Tender has this)
- **S-05-02-07-A** · Reefer · Missed appointment · Direct shipper→driver — coverage PARTIAL; UF Y / CT Y. _Note:_ Auto-rebook on missed-appointment fallback not implemented (UF Auto-Tender has this)
- _… and 35 more (see scenarios.csv)_


## Dispatch communication

_400 scenarios · 360 gaps_

### P0 — 40 scenarios

- **S-06-01-05-A** · Dry van · Accident / incident · Direct shipper→driver — coverage PARTIAL; UF Y / CT N. _Note:_ Accident escalation chain to safety + dispatcher needs SSE + push, currently polling
- **S-06-01-05-B** · Dry van · Accident / incident · Broker-routed — coverage PARTIAL; UF Y / CT N. _Note:_ Accident escalation chain to safety + dispatcher needs SSE + push, currently polling
- **S-06-01-05-C** · Dry van · Accident / incident · Catalyst-managed — coverage PARTIAL; UF Y / CT N. _Note:_ Accident escalation chain to safety + dispatcher needs SSE + push, currently polling
- **S-06-01-05-D** · Dry van · Accident / incident · Multi-stop / chain — coverage PARTIAL; UF Y / CT N. _Note:_ Accident escalation chain to safety + dispatcher needs SSE + push, currently polling
- **S-06-02-05-A** · Reefer · Accident / incident · Direct shipper→driver — coverage PARTIAL; UF Y / CT N. _Note:_ Accident escalation chain to safety + dispatcher needs SSE + push, currently polling
- _… and 35 more (see scenarios.csv)_

### P1 — 320 scenarios

- **S-06-01-01-A** · Dry van · Happy path · Direct shipper→driver — coverage PARTIAL; UF Y / CT N. _Note:_ Polling not real-time; shipper lacks load-scoped chat thread; driver has dispatch chat but routing unclear. ESANG AI dispatcher copilot is a real differentiator vs UF Insights AI (shipper analytics only).
- **S-06-01-01-B** · Dry van · Happy path · Broker-routed — coverage PARTIAL; UF Y / CT N. _Note:_ Polling not real-time; shipper lacks load-scoped chat thread; driver has dispatch chat but routing unclear. ESANG AI dispatcher copilot is a real differentiator vs UF Insights AI (shipper analytics only).
- **S-06-01-01-C** · Dry van · Happy path · Catalyst-managed — coverage PARTIAL; UF Y / CT N. _Note:_ Polling not real-time; shipper lacks load-scoped chat thread; driver has dispatch chat but routing unclear. ESANG AI dispatcher copilot is a real differentiator vs UF Insights AI (shipper analytics only).
- **S-06-01-01-D** · Dry van · Happy path · Multi-stop / chain — coverage PARTIAL; UF Y / CT N. _Note:_ Polling not real-time; shipper lacks load-scoped chat thread; driver has dispatch chat but routing unclear. ESANG AI dispatcher copilot is a real differentiator vs UF Insights AI (shipper analytics only).
- **S-06-01-02-A** · Dry van · Weather delay · Direct shipper→driver — coverage PARTIAL; UF Y / CT N. _Note:_ Polling not real-time; shipper lacks load-scoped chat thread; driver has dispatch chat but routing unclear. ESANG AI dispatcher copilot is a real differentiator vs UF Insights AI (shipper analytics only).
- _… and 315 more (see scenarios.csv)_


## Document exchange

_400 scenarios · 400 gaps_

### P0 — 40 scenarios

- **S-07-08-01-A** · Hazmat class-7 radioactive · Happy path · Direct shipper→driver — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 radioactive needs NRC dual-signature chain + DOT/AEA cross-check; nobody implements this
- **S-07-08-01-B** · Hazmat class-7 radioactive · Happy path · Broker-routed — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 radioactive needs NRC dual-signature chain + DOT/AEA cross-check; nobody implements this
- **S-07-08-01-C** · Hazmat class-7 radioactive · Happy path · Catalyst-managed — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 radioactive needs NRC dual-signature chain + DOT/AEA cross-check; nobody implements this
- **S-07-08-01-D** · Hazmat class-7 radioactive · Happy path · Multi-stop / chain — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 radioactive needs NRC dual-signature chain + DOT/AEA cross-check; nobody implements this
- **S-07-08-02-A** · Hazmat class-7 radioactive · Weather delay · Direct shipper→driver — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 radioactive needs NRC dual-signature chain + DOT/AEA cross-check; nobody implements this
- _… and 35 more (see scenarios.csv)_

### P1 — 360 scenarios

- **S-07-01-01-A** · Dry van · Happy path · Direct shipper→driver — coverage PARTIAL; UF Y / CT Y. _Note:_ Driver-side document upload (pre-pickup BOL exchange + post-delivery POD) lacks dedicated capture screen; OCR-based BOL parsing absent (UF gap too)
- **S-07-01-01-B** · Dry van · Happy path · Broker-routed — coverage PARTIAL; UF Y / CT Y. _Note:_ Driver-side document upload (pre-pickup BOL exchange + post-delivery POD) lacks dedicated capture screen; OCR-based BOL parsing absent (UF gap too)
- **S-07-01-01-C** · Dry van · Happy path · Catalyst-managed — coverage PARTIAL; UF Y / CT Y. _Note:_ Driver-side document upload (pre-pickup BOL exchange + post-delivery POD) lacks dedicated capture screen; OCR-based BOL parsing absent (UF gap too)
- **S-07-01-01-D** · Dry van · Happy path · Multi-stop / chain — coverage PARTIAL; UF Y / CT Y. _Note:_ Driver-side document upload (pre-pickup BOL exchange + post-delivery POD) lacks dedicated capture screen; OCR-based BOL parsing absent (UF gap too)
- **S-07-01-02-A** · Dry van · Weather delay · Direct shipper→driver — coverage PARTIAL; UF Y / CT Y. _Note:_ Driver-side document upload (pre-pickup BOL exchange + post-delivery POD) lacks dedicated capture screen; OCR-based BOL parsing absent (UF gap too)
- _… and 355 more (see scenarios.csv)_


## Pre-trip / driver readiness

_400 scenarios · 400 gaps_

### P0 — 40 scenarios

- **S-08-08-01-A** · Hazmat class-7 radioactive · Happy path · Direct shipper→driver — coverage MISSING; UF Y / CT ?. _Note:_ Hazmat-7 needs NRC license + dosimetry pull
- **S-08-08-01-B** · Hazmat class-7 radioactive · Happy path · Broker-routed — coverage MISSING; UF Y / CT ?. _Note:_ Hazmat-7 needs NRC license + dosimetry pull
- **S-08-08-01-C** · Hazmat class-7 radioactive · Happy path · Catalyst-managed — coverage MISSING; UF Y / CT ?. _Note:_ Hazmat-7 needs NRC license + dosimetry pull
- **S-08-08-01-D** · Hazmat class-7 radioactive · Happy path · Multi-stop / chain — coverage MISSING; UF Y / CT ?. _Note:_ Hazmat-7 needs NRC license + dosimetry pull
- **S-08-08-02-A** · Hazmat class-7 radioactive · Weather delay · Direct shipper→driver — coverage MISSING; UF Y / CT ?. _Note:_ Hazmat-7 needs NRC license + dosimetry pull
- _… and 35 more (see scenarios.csv)_

### P1 — 360 scenarios

- **S-08-01-01-A** · Dry van · Happy path · Direct shipper→driver — coverage PARTIAL; UF Y / CT ?. _Note:_ Shipper sees carrier-level FMCSA, not assigned-driver readiness (HOS clock left, insurance current, hazmat endorsement valid)
- **S-08-01-01-B** · Dry van · Happy path · Broker-routed — coverage PARTIAL; UF Y / CT ?. _Note:_ Shipper sees carrier-level FMCSA, not assigned-driver readiness (HOS clock left, insurance current, hazmat endorsement valid)
- **S-08-01-01-C** · Dry van · Happy path · Catalyst-managed — coverage PARTIAL; UF Y / CT ?. _Note:_ Shipper sees carrier-level FMCSA, not assigned-driver readiness (HOS clock left, insurance current, hazmat endorsement valid)
- **S-08-01-01-D** · Dry van · Happy path · Multi-stop / chain — coverage PARTIAL; UF Y / CT ?. _Note:_ Shipper sees carrier-level FMCSA, not assigned-driver readiness (HOS clock left, insurance current, hazmat endorsement valid)
- **S-08-01-02-A** · Dry van · Weather delay · Direct shipper→driver — coverage PARTIAL; UF Y / CT ?. _Note:_ Shipper sees carrier-level FMCSA, not assigned-driver readiness (HOS clock left, insurance current, hazmat endorsement valid)
- _… and 355 more (see scenarios.csv)_


## En-route tracking

_400 scenarios · 0 gaps_

All 400 scenarios in this phase pass. Nothing to fix.


## Pickup operations

_400 scenarios · 320 gaps_

### P1 — 320 scenarios

- **S-10-01-01-A** · Dry van · Happy path · Direct shipper→driver — coverage PARTIAL; UF Y / CT N. _Note:_ Lifecycle screens don't reliably round-trip appointments.* mutations; shipper can't assign dock door from iOS; UF Scheduling API SSC-standard GA H2 2024
- **S-10-01-01-B** · Dry van · Happy path · Broker-routed — coverage PARTIAL; UF Y / CT N. _Note:_ Lifecycle screens don't reliably round-trip appointments.* mutations; shipper can't assign dock door from iOS; UF Scheduling API SSC-standard GA H2 2024
- **S-10-01-01-C** · Dry van · Happy path · Catalyst-managed — coverage PARTIAL; UF Y / CT N. _Note:_ Lifecycle screens don't reliably round-trip appointments.* mutations; shipper can't assign dock door from iOS; UF Scheduling API SSC-standard GA H2 2024
- **S-10-01-01-D** · Dry van · Happy path · Multi-stop / chain — coverage PARTIAL; UF Y / CT N. _Note:_ Lifecycle screens don't reliably round-trip appointments.* mutations; shipper can't assign dock door from iOS; UF Scheduling API SSC-standard GA H2 2024
- **S-10-01-02-A** · Dry van · Weather delay · Direct shipper→driver — coverage PARTIAL; UF Y / CT N. _Note:_ Lifecycle screens don't reliably round-trip appointments.* mutations; shipper can't assign dock door from iOS; UF Scheduling API SSC-standard GA H2 2024
- _… and 315 more (see scenarios.csv)_


## In-transit telemetry

_400 scenarios · 360 gaps_

### P1 — 360 scenarios

- **S-11-01-01-A** · Dry van · Happy path · Direct shipper→driver — coverage PARTIAL; UF Y / CT N. _Note:_ Shipper SSE/WebSocket stream missing; driver-facing milestone confirmation UI absent
- **S-11-01-01-B** · Dry van · Happy path · Broker-routed — coverage PARTIAL; UF Y / CT N. _Note:_ Shipper SSE/WebSocket stream missing; driver-facing milestone confirmation UI absent
- **S-11-01-01-C** · Dry van · Happy path · Catalyst-managed — coverage PARTIAL; UF Y / CT N. _Note:_ Shipper SSE/WebSocket stream missing; driver-facing milestone confirmation UI absent
- **S-11-01-01-D** · Dry van · Happy path · Multi-stop / chain — coverage PARTIAL; UF Y / CT N. _Note:_ Shipper SSE/WebSocket stream missing; driver-facing milestone confirmation UI absent
- **S-11-01-02-A** · Dry van · Weather delay · Direct shipper→driver — coverage PARTIAL; UF Y / CT N. _Note:_ Shipper SSE/WebSocket stream missing; driver-facing milestone confirmation UI absent
- _… and 355 more (see scenarios.csv)_


## Delivery operations

_400 scenarios · 40 gaps_


## POD capture & approval

_400 scenarios · 76 gaps_

### P0 — 40 scenarios

- **S-13-08-01-A** · Hazmat class-7 radioactive · Happy path · Direct shipper→driver — coverage MISSING; UF Y / CT N. _Note:_ Hazmat-7 POD needs NRC chain-of-custody signatures + final dosimetry log
- **S-13-08-01-B** · Hazmat class-7 radioactive · Happy path · Broker-routed — coverage MISSING; UF Y / CT N. _Note:_ Hazmat-7 POD needs NRC chain-of-custody signatures + final dosimetry log
- **S-13-08-01-C** · Hazmat class-7 radioactive · Happy path · Catalyst-managed — coverage MISSING; UF Y / CT N. _Note:_ Hazmat-7 POD needs NRC chain-of-custody signatures + final dosimetry log
- **S-13-08-01-D** · Hazmat class-7 radioactive · Happy path · Multi-stop / chain — coverage MISSING; UF Y / CT N. _Note:_ Hazmat-7 POD needs NRC chain-of-custody signatures + final dosimetry log
- **S-13-08-02-A** · Hazmat class-7 radioactive · Weather delay · Direct shipper→driver — coverage MISSING; UF Y / CT N. _Note:_ Hazmat-7 POD needs NRC chain-of-custody signatures + final dosimetry log
- _… and 35 more (see scenarios.csv)_


## Detention / accessorial

_400 scenarios · 40 gaps_

### P1 — 40 scenarios

- **S-14-01-07-A** · Dry van · Missed appointment · Direct shipper→driver — coverage PARTIAL; UF Y / CT Y. _Note:_ 30-min pre-detention notification (UF policy) + signed in/out BOL metadata not wired
- **S-14-01-07-B** · Dry van · Missed appointment · Broker-routed — coverage PARTIAL; UF Y / CT Y. _Note:_ 30-min pre-detention notification (UF policy) + signed in/out BOL metadata not wired
- **S-14-01-07-C** · Dry van · Missed appointment · Catalyst-managed — coverage PARTIAL; UF Y / CT Y. _Note:_ 30-min pre-detention notification (UF policy) + signed in/out BOL metadata not wired
- **S-14-01-07-D** · Dry van · Missed appointment · Multi-stop / chain — coverage PARTIAL; UF Y / CT Y. _Note:_ 30-min pre-detention notification (UF policy) + signed in/out BOL metadata not wired
- **S-14-02-07-A** · Reefer · Missed appointment · Direct shipper→driver — coverage PARTIAL; UF Y / CT Y. _Note:_ 30-min pre-detention notification (UF policy) + signed in/out BOL metadata not wired
- _… and 35 more (see scenarios.csv)_


## Settlement / payment

_400 scenarios · 40 gaps_

### P1 — 40 scenarios

- **S-15-01-08-A** · Dry van · Document defect · Direct shipper→driver — coverage PARTIAL; UF Y / CT Y. _Note:_ Doc-defect settlement hold (BOL mismatch flips payable to held) not auto-wired
- **S-15-01-08-B** · Dry van · Document defect · Broker-routed — coverage PARTIAL; UF PARTIAL / CT N. _Note:_ Doc-defect settlement hold (BOL mismatch flips payable to held) not auto-wired
- **S-15-01-08-C** · Dry van · Document defect · Catalyst-managed — coverage PARTIAL; UF Y / CT Y. _Note:_ Doc-defect settlement hold (BOL mismatch flips payable to held) not auto-wired
- **S-15-01-08-D** · Dry van · Document defect · Multi-stop / chain — coverage PARTIAL; UF Y / CT Y. _Note:_ Doc-defect settlement hold (BOL mismatch flips payable to held) not auto-wired
- **S-15-02-08-A** · Reefer · Document defect · Direct shipper→driver — coverage PARTIAL; UF Y / CT Y. _Note:_ Doc-defect settlement hold (BOL mismatch flips payable to held) not auto-wired
- _… and 35 more (see scenarios.csv)_


## Dispute

_400 scenarios · 400 gaps_

### P0 — 400 scenarios

- **S-16-01-01-A** · Dry van · Happy path · Direct shipper→driver — coverage MISSING; UF Y / CT ?. _Note:_ UF TMS Financials with bulk dispute tooling claims 20% faster resolution. Build disputes.* router with create/counterclaim/evidence/arbitration + iOS screens both sides
- **S-16-01-01-B** · Dry van · Happy path · Broker-routed — coverage MISSING; UF Y / CT ?. _Note:_ UF TMS Financials with bulk dispute tooling claims 20% faster resolution. Build disputes.* router with create/counterclaim/evidence/arbitration + iOS screens both sides
- **S-16-01-01-C** · Dry van · Happy path · Catalyst-managed — coverage MISSING; UF Y / CT ?. _Note:_ UF TMS Financials with bulk dispute tooling claims 20% faster resolution. Build disputes.* router with create/counterclaim/evidence/arbitration + iOS screens both sides
- **S-16-01-01-D** · Dry van · Happy path · Multi-stop / chain — coverage MISSING; UF Y / CT ?. _Note:_ UF TMS Financials with bulk dispute tooling claims 20% faster resolution. Build disputes.* router with create/counterclaim/evidence/arbitration + iOS screens both sides
- **S-16-01-02-A** · Dry van · Weather delay · Direct shipper→driver — coverage MISSING; UF Y / CT ?. _Note:_ UF TMS Financials with bulk dispute tooling claims 20% faster resolution. Build disputes.* router with create/counterclaim/evidence/arbitration + iOS screens both sides
- _… and 395 more (see scenarios.csv)_


## Cancellation

_400 scenarios · 100 gaps_


## Rating / review

_400 scenarios · 400 gaps_

### P1 — 400 scenarios

- **S-18-01-01-A** · Dry van · Happy path · Direct shipper→driver — coverage PARTIAL; UF Y / CT ?. _Note:_ Driver side ships in 025_Paperwork (counterparty rating with 5-star overall + 4 axis breakdown + comment + anonymous toggle). Shipper side fast-follow — pending settlement→loadId resolution wiring inside 227_ShipperSettlementDetail.
- **S-18-01-01-B** · Dry van · Happy path · Broker-routed — coverage PARTIAL; UF Y / CT ?. _Note:_ Driver side ships in 025_Paperwork (counterparty rating with 5-star overall + 4 axis breakdown + comment + anonymous toggle). Shipper side fast-follow — pending settlement→loadId resolution wiring inside 227_ShipperSettlementDetail.
- **S-18-01-01-C** · Dry van · Happy path · Catalyst-managed — coverage PARTIAL; UF Y / CT ?. _Note:_ Driver side ships in 025_Paperwork (counterparty rating with 5-star overall + 4 axis breakdown + comment + anonymous toggle). Shipper side fast-follow — pending settlement→loadId resolution wiring inside 227_ShipperSettlementDetail.
- **S-18-01-01-D** · Dry van · Happy path · Multi-stop / chain — coverage PARTIAL; UF Y / CT ?. _Note:_ Driver side ships in 025_Paperwork (counterparty rating with 5-star overall + 4 axis breakdown + comment + anonymous toggle). Shipper side fast-follow — pending settlement→loadId resolution wiring inside 227_ShipperSettlementDetail.
- **S-18-01-02-A** · Dry van · Weather delay · Direct shipper→driver — coverage PARTIAL; UF Y / CT ?. _Note:_ Driver side ships in 025_Paperwork (counterparty rating with 5-star overall + 4 axis breakdown + comment + anonymous toggle). Shipper side fast-follow — pending settlement→loadId resolution wiring inside 227_ShipperSettlementDetail.
- _… and 395 more (see scenarios.csv)_


## Recurring loads

_400 scenarios · 400 gaps_

### P1 — 400 scenarios

- **S-19-01-01-A** · Dry van · Happy path · Direct shipper→driver — coverage PARTIAL; UF Y / CT N. _Note:_ iOS shipper create form routes to web (MeAction.fire('shipper.recurring.schedule')); driver-side recurring-inbox missing. UF Power Lane is the parity benchmark
- **S-19-01-01-B** · Dry van · Happy path · Broker-routed — coverage PARTIAL; UF Y / CT N. _Note:_ iOS shipper create form routes to web (MeAction.fire('shipper.recurring.schedule')); driver-side recurring-inbox missing. UF Power Lane is the parity benchmark
- **S-19-01-01-C** · Dry van · Happy path · Catalyst-managed — coverage PARTIAL; UF Y / CT N. _Note:_ iOS shipper create form routes to web (MeAction.fire('shipper.recurring.schedule')); driver-side recurring-inbox missing. UF Power Lane is the parity benchmark
- **S-19-01-01-D** · Dry van · Happy path · Multi-stop / chain — coverage PARTIAL; UF Y / CT N. _Note:_ iOS shipper create form routes to web (MeAction.fire('shipper.recurring.schedule')); driver-side recurring-inbox missing. UF Power Lane is the parity benchmark
- **S-19-01-02-A** · Dry van · Weather delay · Direct shipper→driver — coverage PARTIAL; UF Y / CT N. _Note:_ iOS shipper create form routes to web (MeAction.fire('shipper.recurring.schedule')); driver-side recurring-inbox missing. UF Power Lane is the parity benchmark
- _… and 395 more (see scenarios.csv)_


## Compliance signals

_400 scenarios · 400 gaps_

### P0 — 40 scenarios

- **S-20-08-01-A** · Hazmat class-7 radioactive · Happy path · Direct shipper→driver — coverage MISSING; UF Y / CT ?. _Note:_ Hazmat-7 NRC license + dosimetry continuous pull
- **S-20-08-01-B** · Hazmat class-7 radioactive · Happy path · Broker-routed — coverage MISSING; UF Y / CT ?. _Note:_ Hazmat-7 NRC license + dosimetry continuous pull
- **S-20-08-01-C** · Hazmat class-7 radioactive · Happy path · Catalyst-managed — coverage MISSING; UF Y / CT ?. _Note:_ Hazmat-7 NRC license + dosimetry continuous pull
- **S-20-08-01-D** · Hazmat class-7 radioactive · Happy path · Multi-stop / chain — coverage MISSING; UF Y / CT ?. _Note:_ Hazmat-7 NRC license + dosimetry continuous pull
- **S-20-08-02-A** · Hazmat class-7 radioactive · Weather delay · Direct shipper→driver — coverage MISSING; UF Y / CT ?. _Note:_ Hazmat-7 NRC license + dosimetry continuous pull
- _… and 35 more (see scenarios.csv)_

### P1 — 360 scenarios

- **S-20-01-01-A** · Dry van · Happy path · Direct shipper→driver — coverage PARTIAL; UF Y / CT ?. _Note:_ Driver in-app compliance dashboard missing (insurance expiry, hazmat endorsement, MVR pull alerts)
- **S-20-01-01-B** · Dry van · Happy path · Broker-routed — coverage PARTIAL; UF Y / CT ?. _Note:_ Driver in-app compliance dashboard missing (insurance expiry, hazmat endorsement, MVR pull alerts)
- **S-20-01-01-C** · Dry van · Happy path · Catalyst-managed — coverage PARTIAL; UF Y / CT ?. _Note:_ Driver in-app compliance dashboard missing (insurance expiry, hazmat endorsement, MVR pull alerts)
- **S-20-01-01-D** · Dry van · Happy path · Multi-stop / chain — coverage PARTIAL; UF Y / CT ?. _Note:_ Driver in-app compliance dashboard missing (insurance expiry, hazmat endorsement, MVR pull alerts)
- **S-20-01-02-A** · Dry van · Weather delay · Direct shipper→driver — coverage PARTIAL; UF Y / CT ?. _Note:_ Driver in-app compliance dashboard missing (insurance expiry, hazmat endorsement, MVR pull alerts)
- _… and 355 more (see scenarios.csv)_
