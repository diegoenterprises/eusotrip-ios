# 10 · Mode TRUCK — Shipper

**What this covers.** The TRUCK::Shipper doctrine — six sub-personas (Manufacturer, Retailer, CPG, Food Processor, Oil & Gas, Ag Co-op), 8-phase lifecycle (Inventory → RFQ → Carrier Selection → Pickup Scheduling → Tracking → POD → Invoice Approval → Payment), screens 200–229, backend (`shippers.ts` 28KB, `shipperContracts.ts`, `shipperScorecard.ts`, `customerPortal.ts` 54KB), A/P wallet, vertical-specific needs (reefer FSMA temp logs, hazmat HM-232 manifests, flatbed securement photos, livestock CVI, food-grade chain-of-custody), load templates + bulk upload, track & trace, appointment scheduling (`appointments.ts` 29KB with strict vs flex windows), claims (Carmack 49 U.S.C. § 14706), document hub, mobile-first sub-views (Warehouse Manager / Sales-Rep). Source: wave-1 shard `team_TRUCK_shipper_escort` Part I.

**When you need this.** When building 200-series screens. When wiring shipper onboarding. When working on compliance artifacts (FSMA, HM-232, CVI, wash tickets).

**Cross-links.** Escort counterpart: [06_Escort.md](./06_Escort.md). Verticals: [50_Verticals_Reference.md](./../50_Verticals_Reference.md). Journeys: [80_User_Journeys_and_Load_Lifecycle.md](./../80_User_Journeys_and_Load_Lifecycle.md). Cross-border: [40_Intermodal_and_Cross_Border.md](./../40_Intermodal_and_Cross_Border.md).

---

## 1. Shipper persona

The Shipper is the economic engine of the freight ecosystem — the party with cargo that needs to move. Within EusoTrip's TRUCK vertical, Shipper is not a monolith; it is a federation of sub-personas, each with distinct operational rhythms, compliance overlays, technology expectations. The platform must accommodate every one without forcing a lowest-common-denominator UX.

**Manufacturer.** Industrial producers — Tier-1 auto suppliers to machined-parts shops — ship finished goods to DCs + customer plants. Loads predictable, often recurring, frequently tied to EDI 204 tenders from OEM customers. Care about OTIF (on-time-in-full) metrics — chargebacks from Walmart, Ford, GM can erase margin on a month of shipments.

**Retailer.** Big-box, specialty, e-commerce retailers shipping between DCs, stores, fulfillment centers. Demand appointment discipline, MABD (must-arrive-by-date) compliance, store-ready pallet configurations. A missed Target appointment window triggers automated OTIF penalty up to 3% of invoice value.

**CPG.** Beverage, personal care, paper products, household goods. High-velocity, high-SKU-count — often 50+ daily outbound from single DC. Lean heavily on load templates, drop-trailer pools, preferred-carrier routing guides.

**Food Processor.** Meat, dairy, produce, frozen, bakery. Subject to FSMA Sanitary Transportation Rule (21 CFR Part 1 Subpart O) — must verify carrier sanitation, temperature pre-cooling, reefer continuous-temp logging. Shipper portal must enforce temp-log attachment before POD can be accepted.

**Oil & Gas Operator.** Midstream + upstream shipping crude, condensate, frac sand, pipe, chemicals, produced water. Hazmat-heavy, HM-232 security plan requirements, frequent tank-truck movements, field-to-terminal pedigree documentation. RFID/seal integration + ticket-based load confirmation.

**Agriculture Co-op.** Grain, fertilizer, seed, livestock. Seasonal surge (harvest), hopper and livestock trailer specialization, mix of member-to-elevator, elevator-to-terminal, terminal-to-export-port. Care deeply about weight-ticket accuracy, grade docking, livestock CVI (Certificate of Veterinary Inspection).

EusoTrip's Shipper persona engine detects vertical at onboarding (NAICS code, self-declaration, first-load signature) and activates appropriate compliance module stack.

---

## 2. Shipper lifecycle — 8 phases

**Phase 1 — Inventory.** Shipper maintains (or syncs from ERP: SAP, NetSuite, Oracle, Dynamics) cargo ready to ship. `inventory.ts` populated via CSV, EDI 846, or real-time API from WMS.

**Phase 2 — RFQ.** Shipper publishes load requirements: origin/destination, pickup/delivery windows, equipment type (dry van, reefer, flatbed, tanker, hopper, livestock), commodity, weight, special handling. Single-carrier tendered (routing guide auto-offer) or spot-bid (open marketplace).

**Phase 3 — Carrier Selection.** Matching engine ranks responding carriers by price, scorecard, capacity fit, insurance validity, geographic density. Shipper approves, auto-awards, or counters. Award triggers signed rate confirmation (e-signature via `signaturePad`).

**Phase 4 — Pickup Scheduling.** Awarded carrier accepts pickup appointment or proposes alternative. `appointments.ts` brokers three-way negotiation (shipper dock schedule, carrier ETA, driver HOS window).

**Phase 5 — Tracking.** Active monitoring. GPS ping cadence, geofence arrival/departure, temperature logging (reefer), door sensor events (if trailer telematics connected), ETA drift alerts flow to shipper's ops dashboard.

**Phase 6 — POD.** Driver captures signature, photos, exception notes. POD instantly available in shipper portal, stamped with geocoordinates + cryptographic hash (audit-grade integrity).

**Phase 7 — Invoice Approval.** Carrier submits invoice; EusoTrip matches against rate confirmation, accessorials (detention, layover, lumper), chargebacks. Three-way match (PO, BOL, invoice) automatic; exceptions queued for shipper review.

**Phase 8 — Payment.** Shipper releases per terms (Net 30, Net 60, QuickPay 2/10). ACH/wire/virtual-card rails (`payments.ts`) execute transfer. Carrier's factoring company notified if assigned.

---

## 3. iOS screens — 200s range

- **200 — Shipper Home / Command Deck.** KPI tiles: open loads, in-transit, delivered-pending-POD, invoice exceptions, detention accruing.
- **201 — Load Board (Outbound).** Filterable list of all shipper loads with status chips.
- **202 — Create Load (Single).** Guided form: origin, destination, commodity, equipment, windows.
- **203 — Create Load (Template).** Pick from saved; pre-fills 80%.
- **204 — Bulk Upload.** CSV / XLSX / EDI 204 ingestion with preview-and-commit.
- **205 — RFQ Dispatch.** Choose routing-guide carriers or open marketplace.
- **206 — Carrier Response Grid.** Side-by-side carrier bids with scorecard overlay.
- **207 — Rate Confirmation e-Sign.** Final approval.
- **208 — Tracking Detail.** Map, timeline, temperature graph (reefer), geofence events.
- **209 — POD Inbox.** All PODs awaiting review.
- **210 — POD Detail.** Signature, photos, exceptions, geo-hash.
- **211 — Invoice Queue.** Three-way-match status per invoice.
- **212 — Exception Review.** Drill into unmatched invoices.
- **213 — Payment Authorization.** Biometric-gated release.
- **214 — Shipper Wallet.** Balances, pending, scheduled payments.
- **215 — Scorecard Hub.** Carrier performance dashboards.
- **216 — Appointment Calendar.** Dock door schedule, drag-to-reschedule.
- **217 — Claims Filing.** Start freight claim.
- **218 — Claims Inbox.** Track filed claims.
- **219 — Document Hub.** BOLs, PODs, invoices, PO sync status.
- **220 — ASN Builder.** Advance Ship Notice generation (EDI 856).
- **221 — Vertical: Reefer Temp Logs.** FSMA-compliant continuous temperature audit trail.
- **222 — Vertical: Hazmat Manifest.** HM-232 security plan, emergency response info.
- **223 — Vertical: Flatbed Securement.** Photo capture grid (4-side, tarped, chained).
- **224 — Vertical: Livestock CVI.** Veterinary inspection upload, head count.
- **225 — Vertical: Food-Grade Chain-of-Custody.** Seal number log, wash-out cert.
- **226 — Warehouse Manager View.** Dock-door heatmap, inbound/outbound split.
- **227 — Sales-Rep View.** Customer pipeline of pending ship-outs.
- **228 — Customer Portal Settings.** Branded sub-portal config for downstream customers.
- **229 — Scorecard — My Performance.** How shipper's carriers see them (facility wait times, appointment honor rate).

---

## 4. Backend architecture

Anchored by four principal modules:

**`shippers.ts`** (28 KB) — core shipper entity router. Onboarding, KYB (know-your-business) via `businessVerification.ts`, credit checks, default vertical detection, routing-guide management, carrier preference lists, shipper profile serialization. Exposes REST + tRPC for every 2xx screen.

**`shipperContracts.ts`.** Persistent contract-rate storage. Shipper-carrier contract is structured document: lane(s), commitment volume, rate ($/mile or flat), fuel-surcharge schedule, accessorial matrix, effective dates, MCI (minimum commitment incentive), renewal terms. Contract engine enforces rate-lookups at tender time — if contracted lane exists, auto-applies contract rate rather than soliciting spot bids.

**`shipperScorecard.ts`.** Bi-directional. Shipper scores carriers on OTIF, tender acceptance, claims ratio, communication responsiveness, detention behavior. Carrier scores shipper on facility wait time, appointment discipline, dock courtesy, payment speed. Scorecards surface on 215 + 229, feed matching engine's carrier ranking.

**`customerPortal.ts`** (54 KB) — largest module in Shipper stack. Implements shipper's *own* customer-facing portal — a shipper can invite *their* customers (consignees) into branded sub-experience to track inbound freight. Handles sub-account provisioning, white-label theming, permissions scoping, read-only views of shipment status. 54 KB footprint reflects complexity of multi-tenant isolation, theme compilation, event filtering.

Supporting: `loadTemplates.ts, bulkImport.ts, appointments.ts (29 KB), freightClaims.ts, claims.ts, tracking.ts, container_timeline.ts, geofencing.ts, assetTracking.ts`.

---

## 5. Shipper wallet — A/P instrument

Unlike Carrier wallet (A/R), Shipper wallet is accounts-payable:

- **Load-Pay Records.** Every invoice paid: to whom, for which load, on which date, via which rail.
- **PO Matching.** Each load tied to PO. Wallet maintains PO-to-invoice link, flags over-billing.
- **Invoicing.** Received carrier invoices with status (received, matched, approved, disputed, paid).
- **Payment Terms.** Default Net 30; negotiable to Net 60 for enterprise; QuickPay (Net 2 at 1.5% discount, Net 7 at 1%, Net 10 at 0.5%) for carriers opting in.

Wallet reconciles daily against shipper's linked bank account (Plaid or direct ACH gateway), generates Form 1099-NEC feed for carriers earning > $600/year when operating as sole proprietors.

---

## 6. Vertical-specific Shipper needs

Vertical modules plug into Shipper workflow at tender creation — compliance artifacts gathered BEFORE load dispatches:

**Reefer Temp Logs (FSMA).** Food processors: load creation screen requires temperature setpoint, pre-cooling duration, continuous-log device designation. At pickup, driver prompted for reefer display photo. In-transit, app logs temp at shipper-defined cadence (typically every 15 min). At delivery, temp log bundled into POD packet. Any reading breaching tolerance raises FSMA exception; shipment cannot be accepted without shipper override.

**Hazmat Manifests (HM-232).** Oil & gas + chemical shippers: system generates security plan-compliant manifest — proper shipping name, UN/NA number, hazard class, packing group, quantity, emergency response info, 24-hour response contact (ChemTel, CHEMTREC). HM-232 requires driver identity verification; app captures live selfie matched against CDL photo before hazmat tender releases.

**Flatbed Load Securement Photos.** Manufacturers + construction-materials: four-corner photo protocol + tarp/chain documentation. Computer vision validates N tie-downs visible (N computed from cargo weight per 49 CFR 393.130) before driver can mark pickup complete.

**Livestock CVI Docs.** Ag co-ops: every interstate livestock load requires Certificate of Veterinary Inspection. App accepts CVI upload at tender, validates expiration (CVIs typically 30 days), captures head count at pickup via manual tally or drone-feed integration, carries CVI through to delivery.

**Food-Grade Chain-of-Custody.** Seal number at origin, seal number at destination, wash-out certification (tank trailers) with photo of wash ticket, commodity-compatibility verification (no prior haul of non-food grade within wash-cycle window).

---

## 7. Load templates + bulk upload

High-volume shippers do not create loads one-at-a-time.

`loadTemplates.ts` — saves any load as reusable template (lane, commodity, equipment, instructions, routing-guide carrier list). Spawns new loads in two taps. Templates support tokens (`{pickup_date}, {po_number}`) filled at spawn.

`bulkImport.ts` — ingests CSV, XLSX, EDI 204 batch tenders. Import engine validates each row (address resolution via geocoding, equipment-code normalization, commodity-code mapping), surfaces errors in preview grid, commits only after shipper acknowledgment. Typical CPG shipper bulk-uploads morning batch of 60–120 loads in under 90 seconds.

---

## 8. Track & trace — four pillars

- **`tracking.ts`** — GPS ping ingestion from driver app, ELD, or third-party telematics.
- **`container_timeline.ts`** — event-sourced timeline (tender, dispatch, arrived-origin, loaded, departed, in-transit checkpoints, arrived-destination, unloaded, delivered, POD-captured).
- **`geofencing.ts`** — polygon-based geofences around shipper facilities, consignee facilities, weigh stations, hazmat-restricted zones. Auto-generates arrival/departure events.
- **`assetTracking.ts`** — trailer and container tracking independent of tractor, for drop-trailer pool shippers.

---

## 9. Appointment scheduling — `appointments.ts` (29 KB)

Appointments are the single largest source of friction in shipper-carrier relationships. 29 KB module encodes dock-door-level scheduling with:

- Door-specific resource calendars (some doors reefer-only, some oversize-capable).
- Appointment types (live load, drop, preload, cross-dock).
- Strict vs flex windows (see §11).
- Automatic rescheduling proposals when ETA drift exceeds threshold.
- Carrier self-service booking within shipper-defined availability.
- Integration with `yardManagement.ts` for gate-in / dock-assignment handoff.

---

## 10. Claims — Shipper side

`freightClaims.ts` + `claims.ts` handle shipper's side of loss, damage, shortage claims. Shipper files under Carmack Amendment (49 U.S.C. § 14706) within nine-month statutory window. App captures claim type (shortage, damage, loss, concealed damage), supporting evidence (photos, weight tickets, salvage estimates), claim amount, transmits to carrier via platform. Carrier has 30 days to acknowledge, 120 days to disposition. EusoTrip tracks statutory clocks, automates demand-letter generation if carrier misses deadlines.

---

## 11. Pickup + delivery windows

**Strict windows** are hard appointment times ("Tuesday 08:00 sharp"). Miss-by-30-minutes triggers chargebacks.

**Flex windows** are ranges ("Tuesday 06:00–14:00"). Arrival anywhere in range is on-time.

EusoTrip distinguishes at load creation. Detention accrual begins at window boundary. Strict → detention starts at appointment + grace (typically 2 hours free). Flex → detention starts at window close + grace. App auto-computes accrued detention, surfaces to carrier (billing) + shipper (accrual reserves). Prevents perennial industry dispute over "when did the clock start?"

---

## 12. Document hub

Every shipper has unified hub (219):

- **BOL** — uploaded by shipper or auto-generated from load data; signed by driver at pickup, consignee at delivery.
- **PO Sync** — bi-directional sync with shipper ERP (SAP, Oracle, NetSuite, Dynamics, QuickBooks).
- **ASN Generation** — EDI 856 Advance Ship Notice to consignees, with GS1 SSCC pallet label generation for retail-compliant shipments.

All documents stored with SHA-256 content hashes, immutable audit trails, retention matching 49 CFR 379 (three years minimum).

---

## 13. Mobile-first Shipper sub-views

**Warehouse Manager View (226).** Designed for person running dock. Live heatmap of door utilization, inbound trucks in yard, outbound loads ready to depart, lumper requests, shift-handoff notes. Optimized for tablet mounted at shipping office.

**Sales-Rep View (227).** Designed for account manager or inside-sales rep needing to see what's shipping to each customer today, tomorrow, this week. Pipeline-style Kanban — "planned," "tendered," "in-transit," "delivered" — grouped by customer. Enables rep to proactively call customers about incoming freight.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
