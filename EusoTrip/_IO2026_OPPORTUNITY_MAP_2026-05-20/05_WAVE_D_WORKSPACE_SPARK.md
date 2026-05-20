# Wave D — Workspace Intelligence + Gemini Spark
**Agent #4 deliverable** | 7 opportunities + Spark × ESang convergence model

## Opportunity 1 — Shipper Spark (P1)
**Spark does overnight:** Monitors new posted loads, tracks rate quotes, compares against ERP vendor/rate bands, auto-drafts rate confirmation emails (with confidence thresholds), reconciles spot freight vs. contracted take-or-pay, flags outliers.

**Daily Brief:** "17 new loads posted (vs. 14h avg) • 8 rate confirmations auto-drafted • 3 quotes exceed band threshold • 1 carrier flagged (payment terms changed) • $127K posted spend • Avg rate $2.14/mi (vs. $2.09 contract floor)"

**Files:** `sparkAutoMonitor.ts`, `sparkBriefs.ts`, `ShipperDashboard.tsx`, `googleWorkspaceAdapter.ts` (Gmail draft creation)

**Endpoint:** `POST /api/spark/shipper/monitor-overnight` with `{shipperId, orgId, erp_vendor_bands}`. Reads `loadPostings`, `quoteEngines.acceptedQuotes`, `erp_sync`. Writes `sparkDrafts` + Gmail API.

**Audit:** Settings toggle "Auto-monitor rates" with rate band approval + "Draft confirmations" with confidence slider. Drafts move to pending-review folder; no live send. Every draft timestamped + linked to rate comparison basis.

**Effort:** M (8-12 wk) — Gmail OAuth 3 wk, rate band logic 2 wk, daily brief aggregation 2 wk, UX 3 wk.

## Opportunity 2 — Broker Spark (P1)
**Spark does overnight:** Pulls SONAR/DAT/Truckstop lane rates + fuel indices, aggregates carrier acceptance patterns by lane/vertical/equipment, auto-generates next-day rate sheets, triages tenders by exception likelihood, drafts intent-to-tender summaries, rolls up lane intelligence.

**Daily Brief:** "Rate sheets: 12 new lanes • Lane intel: LAX→PHX top carrier changed (5% rate drop) • Tender triage: 47 new tenders → 6 require immediate action • Exception risk: 3 loads predicted to breach sync window"

**Files:** `sparkRateEngine.ts`, `tenderTriagulator.ts`, `BrokerDashboard.tsx`, `googleSheetsAdapter.ts` (rate sheet auto-populate)

**Endpoint:** `POST /api/spark/broker/update-rates-overnight` with `{brokerId, orgId, lanes?}`. Reads external APIs (DAT, SONAR, Truckstop), `carrierAcceptanceHistory`, `syncWindowEvents`. Writes `rateSheets`, `sparkBriefs`, Google Sheets API.

**Audit:** Toggles for auto-update frequency, auto-triage confidence threshold. All rate sheets versioned (Sheets revision history + sparkVersionLog). Triage audit shows logic inline ("exception risk 87%: sync window breach predicted, 3 carriers below 90% accept").

**Effort:** L (12-16 wk) — External APIs 4 wk, ML triage 4 wk, lane rollups 2 wk, Sheets sync 2 wk, testing 4 wk.

## Opportunity 3 — Dispatcher Spark (P1)
**Spark does overnight:** Ingests driver HoS state from ELD (Motive/Samsara/KeepTruckin), predicts who cycles out of "on-duty" in next 6/12/24h, generates next-day availability calendar, scores unassigned loads by exception likelihood + HoS coverage, drafts dispatch recommendations, flags pre-trip DVIR issues + maintenance windows, reconciles roster churn.

**Daily Brief:** "47 drivers available • 12 cycling into 10-hr break in 2h (pre-plan unloads) • 5 HoS-constrained for PM (4-hr max) • 8 unassigned loads (3 high exception risk) need coverage by 6am • Load LD-...0847 → Driver D-521 (HoS-compliant, 2-trip day)"

**Files:** `sparkScheduler.ts`, `hosAuditLog.ts`, `DispatcherBoard.tsx`, `eldIntegration.ts`

**Endpoint:** `POST /api/spark/dispatch/generate-schedule-overnight` with `{dispatcherId, orgId, planningHorizon: '6h'|'12h'|'24h'}`. Reads `hos_audit_logs`, ELD webhooks, `vehicles.maintenance_window`, `drivers.status`. Writes `sparkBriefs`, `dispatchRecommendations` (audit table).

**Audit:** Spark never auto-assigns; only generates ranked recommendations. Reasoning logged: "HoS-compliant via [6h cycle restart] + [200mi = 4h drive]". Spark goes to "advisory only" if revoked.

**Effort:** M (10-14 wk) — ELD webhooks 3 wk, HoS state machine 3 wk, exception scoring 2 wk, ranking 2 wk, HoS audit compliance 4 wk.

## Opportunity 4 — Catalyst Spark (P1)
**Spark does overnight:** Ingests daily load completion events (POD, DVIR, ETA variance, customer sign-off), reconciles invoice totals vs. freight rates + fuel surcharges + accessorials, flags invoice discrepancies, scores loads for factoring eligibility (funding risk, customer creditworthiness, lien conflicts), auto-generates driver scorecards, reconciles settlement with carrier payment schedules, detects chargeback patterns.

**Daily Brief:** "143 loads completed → invoiced • 7 invoice discrepancies flagged (avg $340 delta) • 4 loads pending customer sign-off (24h+ overdue) • Settlement payout $487K processed (11 carriers) • Factoring: 18 eligible loads, $156K available • Driver scorecards: D-0521 100% on-time, D-0847 87% (↓ 6%) coaching, D-1220 94% 1 harsh brake → monitor"

**Files:** `sparkReconciler.ts`, `sparkFacroringScorer.ts`, `driverScorecardEngine.ts`, `CatalystDashboard.tsx`

**Endpoint:** `POST /api/spark/catalyst/reconcile-settlement-overnight`. Reads `shipmentInvoiceLifecycle`, `shipper_disputes`, `driverPerformance`, `factoring_applications`, `paymentSchedules`. Writes `sparkBriefs`, `invoiceDiscrepancies`, `factoringEligibility`, `driverScorecards`.

**Audit:** Dry-run mode by default (flagged discrepancies only, no auto-correction). Factoring scores include reasoning: "Eligible $156K, fee 1.8% | Credit 720 ✓ | No liens ✓ | 12 prior on-time ✓". Corrections require explicit approval click.

**Effort:** M (10-13 wk)

## Opportunity 5 — Customs Broker Spark (P1)
**Spark does overnight:** Monitors in-flight filings (US-ACE, CA-CARM, MX-SAT) for status changes, detects "hold" or "under_review", pulls hold reason, summarizes hold documents via vision + summarization, auto-generates hold-response drafts with compliance-safe language, generates USMCA certificate PDFs, flags filings at risk of rejection, collates nightly summary report.

**Daily Brief:** "Filings in flight: 34 (US-ACE 12, CA-CARM 8, MX-SAT 14) • Released today: 7 ✓ • On hold: 2 (action required: Hold #1 MX pedimento incomplete, draft response ready / Hold #2 US HS code mismatch, draft ready) • USMCA certificates ready: 5 (await signature) • At-risk: 2 missing entry bill, 1 classification in gray zone"

**Files:** `sparkFilingMonitor.ts`, `sparkResponseDrafter.ts`, `usmcaCertGenerator.ts`, `CustomsBrokerSurface.tsx` (hold response panel already scaffolded), `googleDocsAdapter.ts`

**Endpoints:** `POST /api/spark/customs/monitor-filings-overnight` + `POST /api/spark/customs/draft-hold-response`. Reads ACE/CARM/SAT adapters (polling), `customsFilings`, OCR results. Writes `sparkBriefs`, `customsResponses` (drafts).

**Audit:** All drafts watermarked "AUTO-GENERATED DRAFT — BROKER REVIEW REQUIRED". Each draft linked to hold reason + source docs (OCR confidence, full text available). No auto-send.

**Effort:** M (9-12 wk)

## Opportunity 6 — Shipper Daily Brief (P0)
**Every morning 06:00 user-local time:**
- Load status: "12 active loads, 3 exceptions, 1 USMCA pending, $48K AR aging"
- Exceptions: "LD-0441 ETA missed by 4h • LD-0512 hazmat incident MX, container sealed/rerouted • LD-0778 customs hold pending USMCA doc"
- AR: "$48K aging (0-30d: $22K | 30-60d: $18K | 60d+: $8K). 2 invoices 60+ days flagged for collections"
- Upcoming: "2 loads ready to tender in 2h • 1 rate confirmation awaiting approval"
- Fuel + rates: "Diesel $3.07/gal (↑ 2¢) • Avg freight rate $2.11/mi (↑ 1%) • Spot capacity tight"

**Delivery:**
- Primary: Workspace (Gmail + linked Google Sheet "Your Loads Today" + Google Doc "AR Reconciliation Checklist")
- Secondary: EusoTrip in-app notification + dashboard widget
- Tertiary: SMS for critical exceptions only

**Files:** `sparkDailyBriefEngine.ts`, `sparkBriefs.ts` (GET endpoint), `googleWorkspaceAdapter.ts`, `BriefWidget.tsx`, `sparkBriefScheduler.ts` (daily 06:00 local trigger)

**Endpoints:** `GET /api/spark/shipper/{id}/daily-brief` + scheduled `POST /api/spark/briefs/send-daily` (runs 06:00 UTC + timezone offset).

**Audit:** Settings → Notifications → Spark Daily Brief. Toggle enable/disable, time, content checkboxes, delivery channels (email/in-app/SMS), frequency. All emails archived in EusoTrip "Brief" folder; Sheets/Docs versioned.

**Effort:** S (6-8 wk)

## Opportunity 7 — Universal Cart in EusoWallet (P0)
**Spark monitors needs:** Driver D-0521 low on fuel (150 mi remaining), Vehicle V-847 maintenance opening, Permit renewal within 30d, Insurance quarterly refresh.

**Drafts requests:** Fuel card loaded $200 @ Pilot/FJ LAX region, permit renewal pack at 10% bundle discount, insurance quote based on vehicle/driver/claims.

**One-flow checkout:** EusoWallet → "Cart" widget shows 1-3 pending items → user reviews + approves → Stripe Connect → fleet manager sees spending roll-up → Workspace confirmation email + in-app notification.

**Integration points:**
- EusoWallet Cart widget (extend with Spark recommendations row)
- Spark Fuel Optimizer (ELD + geolocation → predicts refueling stops + prices)
- Permit Renewal Alert (DOT, TWIC, medical card, hazmat endorsement expiration)
- Insurance Quote Engine (real-time, vehicle age/driver record/claims history)
- Toll Predictor (estimated toll cost pre-trip; added to cart)

**Files:** `CartWidget.tsx`, `fuelOptimizer.ts`, `permitRenewalAlert.ts`, `cartRecommendationFeed.ts`, `googleFormsAdapter.ts`

**Endpoints:** `POST /api/spark/cart/get-recommendations` + `POST /api/eusoWallet/cart/add-spark-recommendation`.

**Audit:** Recommendations only never auto-add. Logged with reasoning: "Recommend fuel @ $3.12/gal, 45 gallons = $140.40 [based on ELD consumption rate]".

**Effort:** S (6-8 wk)

---

## Workspace × ESang Convergence

### Shared read-only surfaces
- **Google Sheets as source-of-truth** for rate sheets, driver rosters, load assignments
- Spark *reads* live Sheets; *writes* only to versioned drafts (e.g., "RateSheet_2026-05-19_v1")
- Broker reviews, then moves draft → production (explicit action)
- ESang (voice) *reads* live Sheets + production rate sheets only (no draft contamination)

### Separate write paths
- **Spark writes to `sparkDrafts`, `sparkBriefs`, `sparkRecommendations`** (new tables; versioned, audited, with confidence + reasoning)
- **ESang writes to `messageThreads`, `shipmentEvents`, `fsmStateMachine`** (direct state mutations)
- Spark monitors ESang outcomes to refine overnight recommendations

### Conflict prevention
1. **Temporal separation:** Spark 21:00-06:00 UTC; ESang + humans 06:00-21:00 UTC
2. **Drafts not live:** Gmail drafts created by Spark are read-only previews; human sends or edits-then-sends
3. **Settlement lock:** Once a load enters `settlement.reconciled`, Spark can only flag, not auto-correct
4. **Data staleness OK for queries:** ESang voice queries read cached state (5min old = acceptable for HoS queries)

### Daily reconciliation event (06:00 UTC)
- Spark publishes overnight findings to `sparkBriefs` + Workspace (Docs link, Sheets snapshot)
- Human reviews
- Conflicts (manual change vs. Spark draft): human wins; Spark sheet marked "superseded"
- ESang queries read approved states only

### Workspace API footprint
```
New adapters (frontend/server/workspace/):
  googleWorkspaceAdapter.ts (OAuth, token refresh, base patterns)
  googleGmailAdapter.ts (drafts, archive, label threads)
  googleSheetsAdapter.ts (create, share, populate, version control)
  googleDocsAdapter.ts (templates, tables, PDFs)
  googleCalendarAdapter.ts (events, compliance reminders)

OAuth scopes:
  gmail.compose (drafts only; never auto-send)
  drive.file (create + manage Spark-owned artifacts)
  calendar.events (read-only: permit expiry, sync window breaches)
  docs (create + edit: daily briefs, compliance reports)
```

### Unified audit trail
**`sparkAuditLog` table:**
`{timestamp, agentId: 'spark_shipper', action: 'drafted_rate_confirmation', resourceId: 'DRAFT-001', workspace_artifact_id: 'email_msg_xyz', user_approval_at?, user_rejection_reason?}`

Links Spark action → Workspace artifact (Gmail message ID, Sheets revision, Docs version). Satisfies: "Show me every automated action and its human disposition."

---

## Phasing

**Phase 1 (Weeks 1-12):** Workspace adapter infrastructure + Spark audit tables + Daily Brief engine + Shipper Spark MVP

**Phase 2 (Weeks 13-24):** Broker Spark + Dispatcher Spark + Cart Spark MVP (fuel + permits)

**Phase 3 (Weeks 25-36):** Catalyst Spark + Customs Broker Spark + USMCA cert generator

**Total effort:** 61-78 weeks (1.4-1.9 FTE across backend + frontend + integrations)

## Risk mitigations
1. **Workspace API rate limits** → Batch ops, exponential backoff, quota monitoring
2. **Timezone complexity** → IANA timezone per user; ISO-8601 UTC storage
3. **Audit + compliance** → Every action logged with reasoning; no auto-send; explicit approval gates
4. **State collision** → Temporal separation, lock patterns, versioning
5. **User privacy** → OAuth scope minimization; no reading non-EusoTrip emails; 30d draft auto-delete if unsent
