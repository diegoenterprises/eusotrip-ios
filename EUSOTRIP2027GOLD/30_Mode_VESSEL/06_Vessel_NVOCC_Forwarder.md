# 30 · Mode VESSEL — NVOCC / Forwarder

**What this covers.** The `VESSEL_BROKER` / `VESSEL_FORWARDER` (NVOCC) role — screens 3400–3419, booking creation, BOL issuance (Master / House / Express / Seaway), the BOL surrender workflow (irreversible, requires Face/Touch ID), rate sheet, consolidation.

**When you need this.** When building 3400–3419. When wiring BOL surrender (critical — irreversible). When implementing MBL vs HBL distinctions.

**Cross-links.** Mode overview + state machine + ISF: [00_Overview.md](./00_Overview.md). Shipping Line Ops (where slots come from): [04_Vessel_Shipping_Line_Ops.md](./04_Vessel_Shipping_Line_Ops.md). Port Agent (where ISF must be green before gate-in): [03_Vessel_Port_Agent.md](./03_Vessel_Port_Agent.md).

---

## 1. iOS screen range

**3400–3419** — NVOCC Home, Booking, BOL Issuance, Rate Sheet, Consolidation.

- **3400 NVOCC Home** — booking pipeline + ISF status per booking.
- **3401 Booking** — create booking (VS-##### numbered).
- **3402 BOL Issuance** — MBL / HBL / Express / Seaway.
- **3403 BOL Surrender** — irreversible workflow with biometric (see §4).
- **3410 Rate Sheet** — per-lane rates, per-container-size.
- **3415 Consolidation** — LCL booking aggregation.

---

## 2. Backend procedures consumed

- `vessel.createVesselBooking` — create booking with `bookingNumber` (VS-#####).
- `vessel.createBOL` — issue master, house, express, or seaway BOL.
- `vessel.getBOL`, `vessel.listBOLs`, `vessel.surrenderBOL` — BOL lifecycle.
- `vessel.createVesselBid` — bid on booking with rate types `per_teu, per_ton, per_cbm, lump_sum`.

---

## 3. BOL types

- **Master BOL (MBL)** — issued by carrier to NVOCC/forwarder.
- **House BOL (HBL)** — issued by NVOCC to shipper under their own identity.
- **Express BOL (Sea Waybill Express)** — non-negotiable, consignee takes delivery without surrender.
- **Seaway Bill** — non-negotiable, reference document.

The distinction matters operationally and legally. MBL flows up the chain to the carrier; HBL is issued downward to the shipper.

---

## 4. BOL surrender — irreversible, biometric-gated

Trucking BOL is effectively a single-use receipt. **A vessel MBL is a negotiable document** controlling title to goods and can be endorsed to banks under LC transactions.

Surrender workflows (screen 3403 surrender action) must be:
- **Irreversible.**
- **Require secondary authentication (Face ID / Touch ID)** before `surrenderBOL` mutation is called.
- **Audit-logged** with user + timestamp + device + geolocation.

A surrender error cannot be rolled back. The mobile UI must reflect that weight.

---

## 5. Unique UX considerations vs trucking

- BOL surrender is not "close the ticket" — it is a legal instrument release. Biometric gate is mandatory.
- MBL vs HBL is a UI + data distinction throughout the booking + tracking flow.
- ISF status visible prominently on NVOCC Home (3400) because NVOCC is often the ISF filer.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
