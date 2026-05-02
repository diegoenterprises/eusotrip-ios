# Per-Phase Deep Dive


## Load posting

_400 scenarios · 40 gaps_

### P2 — 40 scenarios

- **S-01-08-01-A** · Hazmat class-7 radioactive · Happy path · Direct shipper→driver — coverage PARTIAL; UF N / CT N. _Note:_ Hazmat-7 radioactive RAM-OPS schema fields exist; UI accepts but lacks NRC license validation. UF + CT both N — civilian freight platforms don't validate NRC. We're at parity-or-ahead for hazmat-7 posting.
- **S-01-08-01-B** · Hazmat class-7 radioactive · Happy path · Broker-routed — coverage PARTIAL; UF N / CT N. _Note:_ Hazmat-7 radioactive RAM-OPS schema fields exist; UI accepts but lacks NRC license validation. UF + CT both N — civilian freight platforms don't validate NRC. We're at parity-or-ahead for hazmat-7 posting.
- **S-01-08-01-C** · Hazmat class-7 radioactive · Happy path · Catalyst-managed — coverage PARTIAL; UF N / CT N. _Note:_ Hazmat-7 radioactive RAM-OPS schema fields exist; UI accepts but lacks NRC license validation. UF + CT both N — civilian freight platforms don't validate NRC. We're at parity-or-ahead for hazmat-7 posting.
- **S-01-08-01-D** · Hazmat class-7 radioactive · Happy path · Multi-stop / chain — coverage PARTIAL; UF N / CT N. _Note:_ Hazmat-7 radioactive RAM-OPS schema fields exist; UI accepts but lacks NRC license validation. UF + CT both N — civilian freight platforms don't validate NRC. We're at parity-or-ahead for hazmat-7 posting.
- **S-01-08-02-A** · Hazmat class-7 radioactive · Weather delay · Direct shipper→driver — coverage PARTIAL; UF N / CT N. _Note:_ Hazmat-7 radioactive RAM-OPS schema fields exist; UI accepts but lacks NRC license validation. UF + CT both N — civilian freight platforms don't validate NRC. We're at parity-or-ahead for hazmat-7 posting.
- _… and 35 more (see scenarios.csv)_


## Load discovery

_400 scenarios · 0 gaps_

All 400 scenarios in this phase pass. Nothing to fix.


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

_400 scenarios · 0 gaps_

All 400 scenarios in this phase pass. Nothing to fix.


## Booking / acceptance

_400 scenarios · 0 gaps_

All 400 scenarios in this phase pass. Nothing to fix.


## Dispatch communication

_400 scenarios · 0 gaps_

All 400 scenarios in this phase pass. Nothing to fix.


## Document exchange

_400 scenarios · 120 gaps_

### P0 — 40 scenarios

- **S-07-08-01-A** · Hazmat class-7 radioactive · Happy path · Direct shipper→driver — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 radioactive needs NRC dual-signature chain + DOT/AEA cross-check; nobody implements this
- **S-07-08-01-B** · Hazmat class-7 radioactive · Happy path · Broker-routed — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 radioactive needs NRC dual-signature chain + DOT/AEA cross-check; nobody implements this
- **S-07-08-01-C** · Hazmat class-7 radioactive · Happy path · Catalyst-managed — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 radioactive needs NRC dual-signature chain + DOT/AEA cross-check; nobody implements this
- **S-07-08-01-D** · Hazmat class-7 radioactive · Happy path · Multi-stop / chain — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 radioactive needs NRC dual-signature chain + DOT/AEA cross-check; nobody implements this
- **S-07-08-02-A** · Hazmat class-7 radioactive · Weather delay · Direct shipper→driver — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 radioactive needs NRC dual-signature chain + DOT/AEA cross-check; nobody implements this
- _… and 35 more (see scenarios.csv)_


## Pre-trip / driver readiness

_400 scenarios · 40 gaps_

### P0 — 40 scenarios

- **S-08-08-01-A** · Hazmat class-7 radioactive · Happy path · Direct shipper→driver — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 needs NRC license + dosimetry pull. Neither UF nor CT ships civilian-freight NRC chain-of-custody. Vertical specialty for a future EusoTrip Hazmat-7 Pro tier.
- **S-08-08-01-B** · Hazmat class-7 radioactive · Happy path · Broker-routed — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 needs NRC license + dosimetry pull. Neither UF nor CT ships civilian-freight NRC chain-of-custody. Vertical specialty for a future EusoTrip Hazmat-7 Pro tier.
- **S-08-08-01-C** · Hazmat class-7 radioactive · Happy path · Catalyst-managed — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 needs NRC license + dosimetry pull. Neither UF nor CT ships civilian-freight NRC chain-of-custody. Vertical specialty for a future EusoTrip Hazmat-7 Pro tier.
- **S-08-08-01-D** · Hazmat class-7 radioactive · Happy path · Multi-stop / chain — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 needs NRC license + dosimetry pull. Neither UF nor CT ships civilian-freight NRC chain-of-custody. Vertical specialty for a future EusoTrip Hazmat-7 Pro tier.
- **S-08-08-02-A** · Hazmat class-7 radioactive · Weather delay · Direct shipper→driver — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 needs NRC license + dosimetry pull. Neither UF nor CT ships civilian-freight NRC chain-of-custody. Vertical specialty for a future EusoTrip Hazmat-7 Pro tier.
- _… and 35 more (see scenarios.csv)_


## En-route tracking

_400 scenarios · 0 gaps_

All 400 scenarios in this phase pass. Nothing to fix.


## Pickup operations

_400 scenarios · 0 gaps_

All 400 scenarios in this phase pass. Nothing to fix.


## In-transit telemetry

_400 scenarios · 0 gaps_

All 400 scenarios in this phase pass. Nothing to fix.


## Delivery operations

_400 scenarios · 40 gaps_


## POD capture & approval

_400 scenarios · 40 gaps_

### P0 — 40 scenarios

- **S-13-08-01-A** · Hazmat class-7 radioactive · Happy path · Direct shipper→driver — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 POD needs NRC chain-of-custody signatures + final dosimetry log. UF + CT both N — civilian freight platforms don't implement NRC integration.
- **S-13-08-01-B** · Hazmat class-7 radioactive · Happy path · Broker-routed — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 POD needs NRC chain-of-custody signatures + final dosimetry log. UF + CT both N — civilian freight platforms don't implement NRC integration.
- **S-13-08-01-C** · Hazmat class-7 radioactive · Happy path · Catalyst-managed — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 POD needs NRC chain-of-custody signatures + final dosimetry log. UF + CT both N — civilian freight platforms don't implement NRC integration.
- **S-13-08-01-D** · Hazmat class-7 radioactive · Happy path · Multi-stop / chain — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 POD needs NRC chain-of-custody signatures + final dosimetry log. UF + CT both N — civilian freight platforms don't implement NRC integration.
- **S-13-08-02-A** · Hazmat class-7 radioactive · Weather delay · Direct shipper→driver — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 POD needs NRC chain-of-custody signatures + final dosimetry log. UF + CT both N — civilian freight platforms don't implement NRC integration.
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

_400 scenarios · 0 gaps_

All 400 scenarios in this phase pass. Nothing to fix.


## Dispute

_400 scenarios · 0 gaps_

All 400 scenarios in this phase pass. Nothing to fix.


## Cancellation

_400 scenarios · 0 gaps_

All 400 scenarios in this phase pass. Nothing to fix.


## Rating / review

_400 scenarios · 0 gaps_

All 400 scenarios in this phase pass. Nothing to fix.


## Recurring loads

_400 scenarios · 0 gaps_

All 400 scenarios in this phase pass. Nothing to fix.


## Compliance signals

_400 scenarios · 40 gaps_

### P0 — 40 scenarios

- **S-20-08-01-A** · Hazmat class-7 radioactive · Happy path · Direct shipper→driver — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 NRC license + dosimetry continuous pull still requires NRC integration; outside the 8000-scenario doctrine. UF + CT both N — vertical specialty.
- **S-20-08-01-B** · Hazmat class-7 radioactive · Happy path · Broker-routed — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 NRC license + dosimetry continuous pull still requires NRC integration; outside the 8000-scenario doctrine. UF + CT both N — vertical specialty.
- **S-20-08-01-C** · Hazmat class-7 radioactive · Happy path · Catalyst-managed — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 NRC license + dosimetry continuous pull still requires NRC integration; outside the 8000-scenario doctrine. UF + CT both N — vertical specialty.
- **S-20-08-01-D** · Hazmat class-7 radioactive · Happy path · Multi-stop / chain — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 NRC license + dosimetry continuous pull still requires NRC integration; outside the 8000-scenario doctrine. UF + CT both N — vertical specialty.
- **S-20-08-02-A** · Hazmat class-7 radioactive · Weather delay · Direct shipper→driver — coverage MISSING; UF N / CT N. _Note:_ Hazmat-7 NRC license + dosimetry continuous pull still requires NRC integration; outside the 8000-scenario doctrine. UF + CT both N — vertical specialty.
- _… and 35 more (see scenarios.csv)_
