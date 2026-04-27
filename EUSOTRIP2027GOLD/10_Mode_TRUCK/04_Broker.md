# 10 · Mode TRUCK — Broker

**What this covers.** The TRUCK::Broker doctrine — licensed principal persona, 8-state lifecycle (Shipper contract → RFP → Carrier selection → Rate-con → Dispatch → Invoice → Payout carrier → Reconcile), screens 400–499 (intentionally sparse, web-heavy by design), backend (`brokers.ts` 65KB, `brokerManagement.ts` 63KB, `bids.ts`, `loadBidding.ts`, `loadBoard.ts` 133KB, `rfpManager.ts`, `bidReview.ts`, `quotes.ts`), four-ledger wallet (gross revenue, net margin, carrier payable, customer receivable), three load-creation modalities (`nlLoadCreator`, `aiRateConReader`, `bulkUpload` 86KB), carrier qualification (`carrierCapacity`, `carrierTier`, `carrierScorecard`, `clearinghouse`), pricebook + rates (`rateSheet` 73KB, `laneContracts`, `laneRates`, `pricebook`, `marketPricing` 68KB), fuel surcharge landmine, shipper + consignee portals, freight claims, mobile vs web asymmetry, KYC/SOC2. Source: wave-1 shard `team_TRUCK_catalyst_broker` Part II.

**When you need this.** When building 400-series screens. When wiring broker-side backend. When working with rate-cons, FSC, claims, carrier qualification. When a broker PM asks about mobile parity (answer: intentional asymmetry — see §12).

**Cross-links.** Catalyst counterpart (cross-role doctrine at bottom of Catalyst file): [03_Catalyst.md](./03_Catalyst.md). Journeys: [80_User_Journeys_and_Load_Lifecycle.md](./../80_User_Journeys_and_Load_Lifecycle.md). Backend: [03_Backend_API_Contract.md](./../03_Backend_API_Contract.md).

---

## 1. Persona

The Broker is the licensed principal. Holds broker authority (MC with FF designation), registered with FMCSA as property broker, meets BMC-84 or BMC-85 bond requirement, holds process agent (BOC-3), typically carries contingent cargo and errors & omissions coverage. Many also hold NMFTA membership for LTL classification work and may operate as 3PL with warehousing on the side.

Inside EusoTrip the Broker is the **principal counterparty** on every load they handle — invoices the shipper, pays the carrier, owns the margin, owns the risk. Aggregates load-board sources (DAT, Truckstop, internal board), negotiates with carriers, issues rate confirmations under own paper, carries claims exposure when freight goes wrong.

Unlike the Catalyst — relational, throughput-driven — the Broker is **portfolio-driven**. Managing many lanes, many customers, many carriers against margin targets, service targets, compliance obligations simultaneously. Product must respect that. Broker tooling is *data-first* and *desk-first* (web-heavy), with mobile reserved for specific intercepts.

---

## 2. Lifecycle — eight canonical states

Written directly into load state machine:

1. **Shipper contract.** MSA, spot agreement, or dedicated lane contract. Commercial framing set here: credit terms, payment terms, accessorials, fuel surcharge schedule, claims procedure.
2. **RFP.** Request-for-pricing from shipper — one-off or recurring-lane. Managed in `rfpManager.ts`.
3. **Carrier selection.** Broker chooses carrier from qualified pool, usually via internal carrier ranking + spot-market cross-check.
4. **Rate-con.** Rate confirmation issued; binding artefact for carrier side.
5. **Dispatch.** Pickup, in-transit tracking, delivery.
6. **Invoice.** Shipper invoice generated on delivery + POD, per contracted payment terms.
7. **Payout carrier.** Carrier paid per contracted terms (standard net-30, quickpay opt-in, factoring assignment).
8. **Reconcile.** Margin posted to GL, accessorials/deductions trued up, claims opened if required.

Each state has owning backend module + gating check. Broker's daily work is moving loads across these states against the clock.

---

## 3. iOS screens — 400s range

Broker screens live in **400–499**. Because Broker is primarily-web persona (§12), iOS footprint is intentionally narrow — alerts, approvals, quick actions, not full workflow.

Reserved allocations (canonical):

- **400 BrokerHome** — today's loads at risk, margin-at-risk strip, pending carrier acceptances, pending customer approvals.
- **410 BrokerLoadDetail** — single load, all context, read-mostly. The workhorse.
- **420 BrokerCarrierQuickTender** — fast re-tender when carrier falls through; deliberately the only tender composer on mobile.
- **430 BrokerQuoteApprove** — approve quote desk team drafted on web.
- **440 BrokerClaimAck** — first-touch acknowledgement of freight claim; full handling on web.
- **450 BrokerSettlementAlerts** — margin anomalies, carrier overpay risk, DSO deterioration.
- **460 BrokerPricebookLookup** — lane-rate spot check, read-only.
- **470 BrokerCarrierProfile** — carrier one-pager: scorecard, clearinghouse status, insurance expiry.
- **480 BrokerMessaging** — shipper and carrier threads.
- **490 BrokerApprovals** — credit line increases, rate overrides, claim payouts above threshold.

400s are intentionally sparse. New Broker mobile feature must justify against "does this need to happen on a phone, or is it desk work?" If honest answer is desk work, feature ships on web and does not get 400s number.

---

## 4. Backend — largest footprint in TRUCK vertical

- **`brokers.ts`** (65 KB) — primary router for broker identity, carrier relationships, shipper relationships, core load CRUD.
- **`brokerManagement.ts`** (63 KB) — multi-broker, multi-desk, multi-branch management; roles, permissions, commission split tables for W-2 agents.
- **`bids.ts`** and **`loadBidding.ts`** — carrier bidding on posted loads. `bids.ts` transactional (submit, counter, accept); `loadBidding.ts` orchestration (rounds, cutoffs, auto-selection rules).
- **`loadBoard.ts`** (133 KB) — the load board. Single largest module in vertical. Owns posting, searching, filtering, ranking, external-board syndication, subscription model for carriers. When crosses 150 KB, split by **read path vs write path** — never by feature.
- **`rfpManager.ts`** — RFP lifecycle for contract + mini-bid work.
- **`bidReview.ts`** — scoring + selection of received bids, both RFPs and spot loads.
- **`quotes.ts`** — shipper-facing quote generation, multi-leg + multi-mode.

Rule of thumb:
- If workflow starts with *carrier* action (bidding, accepting) → `bids.ts` / `loadBidding.ts`.
- If starts with *shipper* action (RFP, quote) → `rfpManager.ts` / `quotes.ts`.
- Everything else → `brokers.ts` or `loadBoard.ts` by default; `brokerManagement.ts` strictly multi-entity administration.

---

## 5. Broker wallet — four-ledger

Unlike Catalyst wallet (commission-only), Broker wallet reflects principal status:

- **Gross revenue.** Shipper invoices issued, by status (billed, aged, collected, written off).
- **Net margin.** Gross revenue minus carrier cost, FSC pass-through, accessorials, claim reserves, per load and aggregated by lane, customer, period.
- **Carrier payable.** Owed to carriers, by status (scheduled, quickpay-offered, in-flight, paid, held-for-dispute).
- **Customer receivable.** Owed by shippers, by aging bucket (0-30, 31-60, 61-90, 90+). DSO tracked natively.

Wallet is financial dashboard, not transactional surface. Payments move through settlement engines, not through wallet UI actions directly. Wallet shows *state* + small set of gated actions (approve quickpay, release hold, write off) calling into settlement layer.

---

## 6. Load creation — three input modalities

Each exists because different volume segment demands it:

- **`nlLoadCreator`** — natural-language. Dispatcher pastes shipper email into text box; parser extracts origin, destination, pickup window, delivery window, commodity, weight, equipment, special requirements. Extracted draft shown for confirmation before persist. Fastest happy-path for one-off loads.
- **`aiRateConReader`** — inbound rate confirmations (from external shippers or other brokers on co-brokered) read by LLM-backed extraction. Pulls same fields as nlLoadCreator plus rate + accessorials specified on rate-con. Output always lands in draft state for human confirmation.
- **`bulkUpload`** (86 KB) — CSV/XLSX path for large shippers tendering hundreds of loads per day. Handles long tail of edge cases (malformed rows, missing required fields, multi-leg expressed on one row). Size reflects those edge cases. Do not let it grow without decomposing validation layer.

All three converge on same `load` entity. No "load created via bulk" type — provenance is a field, not a branch.

---

## 7. Carrier qualification — gated pool

Four modules managing qualification:

- **`carrierCapacity`** — real-time view of what each carrier can haul where, when. Fed by carrier self-posting (post-truck), deliveries-in-progress, historical lane coverage.
- **`carrierTier`** — tiering model (platinum / gold / silver / unrated) driving rate-con issuance order, quickpay eligibility, board visibility. Computed, not manually assigned.
- **`carrierScorecard`** — scorecard: on-time pickup, on-time delivery, tracking compliance, claim rate, dispute rate, invoice-accuracy rate. Drives tier; tier drives commercial treatment.
- **`clearinghouse`** — FMCSA Clearinghouse integration for drug & alcohol program compliance. Carrier in prohibited status cannot receive rate-con. Periodic re-pull automated; stale clearinghouse record triggers tender block.

Broker cannot issue rate-con to carrier that has not passed qualification gate. Non-negotiable at platform level, only softened by explicit tenant-level override, itself audit-logged.

---

## 8. Pricebook + rates — multi-layered

- **`rateSheet`** (73 KB) — Broker's own negotiated rate sheet, per customer, per lane, per equipment type, seasonal adjustments.
- **`laneContracts`** — contracted rates on dedicated lanes, volume commitments, rate-escalation clauses.
- **`laneRates`** — live operational rate for a lane; resolves from `laneContracts` first, then `rateSheet`, then spot market signal.
- **`pricebook`** — aggregated view used by sales desk to quote. Sits on top of three above.
- **`marketPricing`** (68 KB) — market-rate intelligence: DAT-style signals, internal historical medians, lane health (tight/loose), projected spot direction. *Input* to pricing decisions, not a rule.

Resolution order (contract → sheet → market) enforced by `laneRates` resolver. No code paths bypass. Quotes, rate-cons, invoices all flow from same resolution result — guarantees consistency between what was quoted, tendered, billed.

---

## 9. Fuel surcharge — and the landmine

Two modules:

- **`fscEngine`** — computation engine: given base rate, lane, date, carrier/shipper FSC schedule → compute FSC amount.
- **`fuelSurchargeIndex`** — weekly DOE EIA index ingestion + carrier-specific or shipper-specific schedules.

**Landmine, flagged canonical**: `fscEngine.calculateFSC` is **never invoked during settlement**. Function exists, is unit-tested, is referenced in quote generation + rate-con generation — but settlement pipeline reads FSC as line item from load record, NOT as fresh computation at settlement time. If fuel index moved between rate-con issuance and settlement, settlement uses rate-con's frozen FSC (usually correct commercially but NOT what the code appears to claim).

**Doctrinal statement**: FSC at settlement is read-through, not recomputed. Any future refactor wiring `fscEngine.calculateFSC` into settlement pipeline must first answer commercial question "do we want to recompute FSC at settlement?" — re-computing changes behaviour shippers and carriers built expectations around. Function being present but unwired is a *stable* state, not a bug to reflexively fix.

Exactly the class of latent mismatch the platform-wide code audit should surface early. Document before refactor.

---

## 10. Shipper portal

Two modules, two audiences:

- **`customerPortal.ts`** — shipper side. Self-service load tender, quote acceptance, invoice history, document retrieval (BOL, POD), claims filing, scorecard on Broker's performance.
- **`consigneePortal.ts`** — receiver side. Appointment scheduling, delivery status, POD upload, exception handling.

Splitting shipper + consignee reflects reality: paying party and receiving party often different organizations (3PL orchestrates for retailer; retailer's DC receives). Access models, permissions, notification channels differ enough that single portal would compromise both.

Both portals web-first. Mobile representation restricted to alert/approval intercepts + document capture (POD upload from phone camera).

---

## 11. Freight claims

- **`freightClaims.ts`** (42 KB) — full cargo claim lifecycle: intake, triage, documentation collection, carrier notification, insurer notification, reserve setting, settlement, subrogation, close-out.
- **`claims.ts`** — generic claim primitives (claim entity, status, parties, documents). `freightClaims.ts` is the cargo specialization; future specializations (auto-liability on fleet products) sit alongside, not inside.

Claims are *slow* in real-world time — cargo claim can run months. UI built for that cadence. Mobile screen (440) intentionally limited to first-touch acknowledgement; rest of workflow on web where documents + correspondence are easier to manage.

---

## 12. Mobile vs web — the deliberate asymmetry

The Broker surface is **web-heavy by design.** Workflows (RFP management, carrier qualification, pricebook maintenance, claims, bulk upload, multi-desk administration) are data-dense, done at a desk. A Broker staring at a phone for eight hours is a sign something is wrong with our product, not success.

iOS is reserved for three classes of intercept:

1. **Alerts** — things Broker needs to know *now*: load at risk, carrier falling through, credit line hit, claim escalation, margin anomaly.
2. **Quick actions** — narrowly-scoped approvals and re-tenders in under 60 seconds from phone. Longer belongs on desktop.
3. **Field capture** — photograph BOL, grab signature, upload POD when Broker is on-site at dock or with customer.

400s screen inventory reflects this scoping. New iOS Broker screen must fit one of those three classes. If it doesn't, ships on web. Doctrinally stable — do not let it drift.

---

## 13. KYC / SOC2 compliance

Brokers carry heavier compliance posture than Catalysts — they are principal of record:

- **KYC.** Business entity verification (Secretary of State filing, EIN, beneficial-ownership disclosure where applicable under FinCEN CTA), MC/FF authority active, bond on file + current, BOC-3 on file, E&O + contingent cargo on file with platform named as certificate holder. Re-verified annually + on any authority-status change event reported by FMCSA.
- **SOC2.** Platform operates under SOC2 Type II; Broker surface inherits: access reviews (quarterly), separation of duties in settlement (maker/checker above thresholds), audit logging on all privileged actions, encryption in transit + at rest, incident response plan with defined RTO/RPO, vendor due diligence on every integrated data source (DAT, EIA, FMCSA, Clearinghouse, Stripe, credit bureaus). Broker tenants receive SOC2 report under NDA on request.
- **PII minimization.** Carrier driver PII (CDL, medical card, clearinghouse identifiers) kept in segregated store with tighter access controls than operational data. Broker staff see summaries, not full documents, unless specific access reason logged.
- **Data retention.** Load records, rate-cons, invoices, PODs retained per transportation recordkeeping requirements (minimum three years on most, longer on claims records). Enforced by policy, not ad-hoc cron.

A Broker who cannot pass KYC cannot onboard. Broker whose authority lapses suspended from tender issuance within one business day of FMCSA signal, with grace window configurable per tenant for planned transitions.

---

## Cross-role doctrine — Catalyst + Broker together

See end of [03_Catalyst.md](./03_Catalyst.md) for the three cross-role principles that govern how these roles coexist.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
