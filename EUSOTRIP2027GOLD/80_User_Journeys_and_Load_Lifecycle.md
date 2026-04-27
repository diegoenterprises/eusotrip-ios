# 80 · User Journeys + Load Lifecycle

**What this covers.** End-to-end journeys for every mode (trucking FTL dry-van reference, rail intermodal, ocean + inland vessel, cross-border US→MX, hazmat overlay, dispatch-board hour-by-hour, settlement/pay Friday cycle, factoring instant pay, tax January 31 1099, new-hire training, ongoing compliance, incident crash-to-back-in-service, long-haul sleeper-berth, team driver swaps). Each journey is a state machine with roles, screens, backend procedures, notification fan-out, watch surfaces, offline fallbacks, failure modes, latency budgets. Source: wave-1 shard `team_JOURNEYS_lifecycle`.

**When you need this.** When scoping a feature that crosses many surfaces. When a PM asks what "the canonical day" looks like. When debugging cross-cutting behavior ("why did the wallet update before the POD synced?").

**Cross-links.** State machine: [04_Database_and_Schema.md §6](./04_Database_and_Schema.md). Role-specific flows: [10_Mode_TRUCK/01_Driver.md](./10_Mode_TRUCK/01_Driver.md), [10_Mode_TRUCK/02_Dispatch.md](./10_Mode_TRUCK/02_Dispatch.md), [20_Mode_RAIL/00_Overview.md](./20_Mode_RAIL/00_Overview.md), [30_Mode_VESSEL/00_Overview.md](./30_Mode_VESSEL/00_Overview.md). Cross-border: [40_Intermodal_and_Cross_Border.md](./40_Intermodal_and_Cross_Border.md).

This section is the operational bible for how a unit of work moves through the EusoTrip platform — from moment a shipper picks up a phone to moment a 1099 is mailed eleven months later. Every mode is treated as state machine with explicit transitions, role-scoped screens, backend procedures, notification fanout, watch surfaces, offline fallbacks, failure modes, latency budgets. **If a step is not described here, it does not exist in the product.**

---

## 7.1 TRUCKING — Single-load journey (FTL dry van reference case)

Canonical trucking journey: 53-foot dry van moving dry goods from shipper DC in Memphis to receiver DC in Dallas. Reference implementation against which every other mode is compared. Twenty-three discrete states, ~18–30 hours wall-clock, four primary roles: shipper, broker, dispatcher, driver. Carrier admin and settlement clerk are secondary roles touching the tail.

### Step 1 — Shipper creates load (web)
- **Role**: Shipper ops clerk.
- **Surface**: Web `/shipper/loads/new` (no iOS — shippers are web-first in v1).
- **Backend**: `loads.create` tRPC → writes `loads` row status `draft` → `loads.publish` flips to `tender_ready`, emits `load.created` to broker inbox.
- **Notifications**: Push + email to broker of record ("New tender: Memphis → Dallas, 42,000 lb, pickup tomorrow 0800"); in-app toast on broker dashboard.
- **Offline fallback**: Web form caches to IndexedDB; retries on reconnect with idempotency key.
- **Failure modes**: Validation errors (missing weight, invalid ZIP) inline in red; rate cards missing → modal prompt spot vs contract; broker offline → load parks in `tender_ready` until broker reconnects.
- **Latency budget**: p95 350ms for form submit, p99 800ms.

### Step 2 — Broker receives tender
- **Role**: Broker.
- **Surface**: iOS 42 (Broker Tender Inbox), web `/broker/tenders`.
- **Backend**: `tenders.list` (paginated, cursor-based) + `tenders.get(id)` on row tap; subscribes to WS channel `broker:{id}:tenders`.
- **Notifications**: Push "New tender from Acme Foods — $2,800 target — accept within 15 min"; if no ack in 5 min, escalates to manager.
- **Watch**: Complication shows pending tender count; tap opens quick-accept glance.
- **Offline**: Tender cached in CoreData; broker can mark "claiming" offline, syncs on reconnect (optimistic, server-side last-write-wins on conflict).
- **Failure modes**: Tender rescinded mid-review → banner "Tender withdrawn" + soft-dismiss; duplicate tender (same PO) → dedupe UI with "merge or keep separate?"
- **Latency**: p95 200ms list, 180ms detail.

### Step 3 — Broker posts to load board
- **Backend**: `loadboard.post` fans out to DAT, Truckstop, internal EusoTrip board, private networks; writes `board_postings` rows per destination.
- **Notifications**: Carriers subscribed to matching searches get push ("New load matches your lane").
- **Offline**: Post queued locally; on reconnect posts in order with 3× retry + exponential backoff.
- **Failure modes**: DAT API 500 → partial post with yellow banner "Posted to 3 of 4 boards — DAT retrying"; rate below floor → confirm modal; duplicate → 409.
- **Latency**: p95 900ms (includes third-party fanout), p99 2.5s.

### Step 4 — Carrier/driver accepts load
- **Surface**: iOS 18 (Load Details), 19 (Accept Modal).
- **Backend**: `loads.accept` with idempotency token → atomic CAS from `available` to `assigned`; writes `assignments` row; emits `load.assigned`.
- **Notifications**: Broker gets push "Smith Trucking accepted — ETA to pickup 14:22"; shipper email; dispatcher (if separate from driver) push with driver assignment.
- **Watch**: New active load; complication flips "No load" → "Load #18472 — Memphis."
- **Offline**: Accept optimistic — if server rejects (another beat them), roll back "Sorry, load was taken 3 seconds ago."
- **Failure modes**: Race condition → first write wins; credit hold on carrier → block with "Contact broker — credit review needed"; MC number inactive → hard block.
- **Latency**: p95 250ms, p99 600ms — race-critical path, cannot be slow.

### Step 5 — Driver pre-trip DVIR
- **Surface**: iOS 87 (DVIR Pre-Trip), 32-item checklist + defect photo.
- **Backend**: `dvir.start` returns DVIR id; per-item `dvir.setItem(id, itemCode, status, photoUrl?)` with debounced writes; `dvir.submit` seals record.
- **Notifications**: If any defect marked "critical," push to dispatcher + carrier safety officer; HOS-adjacent event written to eLogs.
- **Watch**: Progress ring (e.g., 18/32 items) with haptic on completion.
- **Offline**: Full DVIR works offline — photos stored locally, uploaded via background URLSession on reconnect; DVIR marked `pending_upload` until all photos confirm.
- **Failure modes**: Critical defect + start trip attempt → hard block "Vehicle out of service — contact dispatcher"; photo upload failure → retry indicator per item.
- **Latency**: Each item save p95 120ms (local-first); full submit p95 400ms (network).

### Step 6 — En-route to pickup
- **Surface**: iOS 21.
- **Backend**: `location.ping` every 30s (2min when stationary), writes to timeseries table partitioned by load id; `loads.updateStatus('en_route_pickup')`; ETA recalculation every 5min.
- **Notifications**: Broker + shipper get ETA update on 20%/10%/arriving; geofence entry at pickup triggers "Driver arrived at shipper."
- **Watch**: Turn-by-turn micro-instructions, next maneuver, ETA, HOS remaining.
- **Offline**: Location pings queued locally (up to 24h ring buffer); replayed on reconnect with original timestamps.
- **Failure modes**: GPS signal lost → cell-tower triangulation with reduced accuracy badge; battery saver → reduce ping frequency with banner.
- **Latency**: Ping ingestion p95 80ms; ETA recalc async, user-facing fetch p95 300ms.

### Step 7 — Pickup DVIR + trailer inspection
- **Surface**: iOS 88.
- **Backend**: `dvir.trailer.create` with trailer VIN, seal number, tire/light/door checks; photo attachment to seal number mandatory.
- **Failure modes**: Seal mismatch → critical alert to dispatcher + broker + shipper; driver must photograph alternate seal with override reason.

### Step 8 — BOL sign
- **Surface**: iOS 91 (BOL Signing Canvas).
- **Backend**: `bol.create` with line items (from shipper load record), `bol.sign` captures signature PNG + geostamp + device attestation; generates PDF server-side.
- **Offline**: Signatures captured locally; PDF generated on reconnect; signed-but-unsynced badge on load.

### Step 9 — Loaded / en-route to delivery
- **Surface**: iOS 22.
- **Backend**: `loads.updateStatus('loaded')` → `loads.updateStatus('en_route_delivery')`; ETA engine switches to destination.
- **Watch**: ETA, distance remaining, HOS clock, next mandatory break.
- **Failure modes**: HOS violation imminent → force-break UI at 30min out; weather-driven reroute → push "Storm ahead, suggested reroute +45min."

### Step 10 — Detention at receiver
- **Surface**: iOS 23 (Detention Timer).
- **Backend**: Geofence entry starts detention clock; `detention.start` at entry + 2 hours (grace); accrual calculated per contract rate.
- **Notifications**: At 2h push to broker + dispatcher "Detention starting at $75/hr"; at 4h escalation to shipper.
- **Watch**: Big timer + accrual counter ("$125.50 accrued").
- **Failure modes**: Receiver disputes → flagged record, goes to broker arbitration queue.

### Step 11 — Unload + POD sign
- **Surface**: iOS 92 (POD Capture).
- **Backend**: `pod.create` with signature, damage-free flag, piece count verification, optional photo evidence; `loads.updateStatus('delivered')`.
- **Offline**: Full offline capture; photos + signature synced on reconnect; POD timestamp local-truthful.
- **Failure modes**: Damage noted → mandatory photo + claim intake; short count → reconciliation modal with shipper BOL numbers.

### Step 12 — Settlement batched
- **Surface**: iOS 71 (Settlements), web `/carrier/settlements`.
- **Backend**: Nightly cron `settlements.batch` groups delivered loads by driver; applies per-load deductions (fuel advance, escrow, tolls); generates settlement sheet PDF.
- **Notifications**: Driver push "Settlement ready — $1,847.50 net"; carrier admin approval queue.
- **Watch**: Weekly total accrual, updates daily.
- **Failure modes**: Missing lumper receipt → holds line item in "pending"; dispute flag → settlement review queue.

### Step 13 — Wallet credited + 1099 year-end
- **Surface**: iOS 73 (Wallet), 74 (Tax Docs).
- **Backend**: `payouts.execute` via Stripe/Modern Treasury; writes `ledger_entries`; Jan 31 cron `tax.generate1099` materializes per-payee 1099-NEC.
- **Notifications**: Push "Deposit sent — $1,847.50 to Chase ****4521"; Jan 15 "1099 draft available for review"; Jan 31 "1099 final, download or mail copy requested."
- **Watch**: Deposit confirmation haptic + amount.
- **Failure modes**: ACH return (NSF on carrier account) → retry + carrier notification; W-9 missing → 1099 blocked with urgent flag.

---

## 7.2 RAIL — Intermodal rail journey

Longer (7–14 days), touches more parties, far more "handoff" states than trucking. Hallmark: container spends most of its life in someone else's custody — railroad — and app's job is visibility, not control.

**Key states** (see [20_Mode_RAIL/00_Overview.md §3](./20_Mode_RAIL/00_Overview.md) for full 19-state detail):

1. **Booked** (shipper + NVOCC): `rail.bookings.create` → booking number, equipment type, origin ramp, destination ramp.
2. **Container discharged at port**: EDI 315 inbound from steamship line → `rail.statusUpdate('discharged')`.
3. **Drayage to rail ramp**: mini-trucking (see 7.1 truncated — pickup + delivery to ramp only, no BOL since intra-company).
4. **Car ordered**: `rail.carOrder.create` → submits to Class I API (BNSF, UP, NS, CSX, CN, CP, KCSM).
5. **Spotted**: Car positioned for loading — EDI 404 received.
6. **Loaded**: Container on car, lift confirmation.
7. **In transit (multi-leg)**: EDI 322 every interchange; can involve 2–3 railroads on single move.
8. **At interchange**: Physical handoff between Class Is (e.g., Chicago between BNSF and NS).
9. **In yard**: Arrived destination yard but not yet available for pickup.
10. **Delivered to destination ramp**: Available for drayage.
11. **Drayage to final consignee**: mini-trucking journey closes out.

**Tracking** all EDI-driven (204, 214, 315, 322, 404). App polls railroad API every 15 min, normalizes into internal state. iOS 61 (Rail Tracking) shows map with car location, current leg, next interchange, ETA. Watch: complication shows days to delivery + current status ("In transit — NS"). Offline: cached last-known, stale indicator after 1h. Failure: EDI feed down → yellow banner "Tracking delayed, last update 2h ago."

**Interchange events** — critical pain points (24–72h). Push on every event ("Arrived Chicago interchange, next leg NS, est. handoff 8h"). For high-value loads, SMS fallback.

**At-yard / available for pickup** — notification to dray carrier + consignee; iOS 62 (Rail Available Notification) shows pickup window, fees if exceeded (per-diem), one-tap dispatch dray.

---

## 7.3 VESSEL — Ocean + inland journey

2–6 weeks wall-clock, most documentation, strictest regulatory touchpoints.

**States** (see [30_Mode_VESSEL/00_Overview.md §3](./30_Mode_VESSEL/00_Overview.md) for full 19-state detail):

1. **Booked with NVOCC**: `ocean.bookings.create` → MBL number.
2. **ISF 10+2 filed**: Mandatory 24h before lading; `customs.isf.file` calls CBP AES.
3. **Gate-in at origin port**: Container arrives terminal; AIS + terminal operator feed.
4. **Loaded onto vessel**: Vessel manifest update.
5. **Departed**: Sailed from origin — AIS feed.
6. **In transit**: Daily AIS pings, weather overlays.
7. **Arrived destination port**: AIS + terminal feed.
8. **Customs hold (if selected)**: CBP exam; X-ray, tailgate, or intensive.
9. **Customs cleared**: Release to terminal for pickup.
10. **Discharged**: Lifted off vessel.
11. **Gate-out**: Container leaves terminal with drayage tractor.
12. **Drayage + delivered**: Standard trucking leg.

iOS 63 (Ocean Tracking): map with vessel AIS, ETA, weather, piracy zones if applicable. Watch: "At sea, 6 days to arrival" with voyage progress ring. Offline: last-known + map tiles pre-downloaded for zoomed-out route. Failure: AIS blackout (common some regions) → estimation from last known + course/speed with "estimated" badge.

**ISF 10+2 specifically** — role: NVOCC ops clerk; screen: web `/nvocc/isf/{booking}` (no mobile). Backend: `customs.isf.submit` serializes 10 importer + 2 carrier data points to CBP AES. Notifications: ISF accepted/rejected with field-level errors. Failure: Missing data blocks submission; late filing → automatic $5k penalty flag.

---

## 7.4 CROSS-BORDER — US → MX journey

Chain of custody with **mandatory tractor swap at border**. US carriers cannot legally deliver in MX; MX carriers cannot legally pick up in US. App models explicitly.

**States:**
1. **Shipper creates (US)**: Standard creation with destination in MX → routing engine flags cross-border.
2. **Broker routes**: Two-segment load auto-generated — US to border crossing (e.g., Laredo), MX from border to final.
3. **US carrier drops at border**: POD at border yard; trailer stays, tractor returns.
4. **MX carrier picks up (tractor swap)**: MX tractor attaches; new DVIR, new assignment record.
5. **Carta Porte generated**: CFDI 4.0 Carta Porte XML via SAT.
6. **VUCEM filed**: Electronic manifest to MX customs.
7. **Crosses border**: Geofence event at international boundary.
8. **Delivered in MX**: Standard POD.
9. **SAT invoicing**: Post-delivery CFDI issuance.

**Role matrix:**
- US shipper: creates load, sees unified tracking.
- US broker: manages both segments, coordinates tractor swap timing.
- US driver: journey ends at border drop — iOS 27 (Border Drop).
- MX driver: journey starts at border pickup — iOS 28 (Border Pickup, Spanish default).
- Customs agent: iOS 29 (Customs Review) — specialized role.

**Carta Porte**: Backend `sat.cartaPorte.generate` calls SAT PAC partner, returns CFDI with QR code. iOS 94 (Carta Porte Viewer) shows QR + UUID; driver must show on phone at any MX checkpoint. Offline: XML + QR cached on-device from moment of generation. Failure: SAT API down → retry queue, manual paper fallback with audit flag. Latency: p95 4s (SAT is slow), p99 10s.

**Border geofence**: entry on MX side triggers notification to MX broker + shipper + consignee. If tractor swap hasn't happened by border geofence, page dispatcher.

---

## 7.5 HAZMAT specific journey

Overlays trucking journey (7.1) with additional states + gates. No step skipped — only added.

**Additional states:**
- **Hazmat classification at booking**: UN number (e.g., UN1203 gasoline), packing group (I/II/III), emergency response doc reference.
- **Carrier hazmat verification**: HM-232 certification validated against carrier record.
- **Driver hazmat endorsement validated**: HME on CDL checked against FMCSA API.
- **Placard loading verification**: Photo of placards on all four sides of trailer.
- **Route restrictions loaded**: Tunnel restrictions (Lincoln, Baltimore Harbor), time-of-day restrictions in certain cities.
- **Emergency response plan active**: CHEMTREC number, ERG lookup in-app.
- **Special handling POD**: Hazmat-specific POD with additional damage/leak checkboxes.

iOS 96 (Hazmat Briefing): Pre-trip, mandatory read-and-acknowledge on UN number details, ERG reference, emergency contacts. iOS 97 (ERG Lookup): Offline copy of Emergency Response Guidebook; lookup by UN number or material name. Backend: `hazmat.validate` at load accept — if driver lacks HME or carrier lacks HM-232, hard block. Watch: ERG ID + response code pinned during hazmat active load. Offline: everything hazmat-critical cached on-device. Failure: Incident / spill → SOS flow (7.12) with hazmat overlay — CHEMTREC auto-dialed.

---

## 7.6 Dispatch board journey (hour-by-hour)

Dispatcher is the orchestrator — sees all drivers, all loads, all trucks.

- **0500**: iOS 51 or web `/dispatch/board`; initial paint p95 600ms.
- **0505–0600**: Review overnight ETAs, adjust morning assignments; `assignments.update` batch.
- **0600–0900**: Heavy new-tender window; iOS 42 badge active.
- **0900–1200**: Check-ins with drivers; iOS 54 (Fleet Map).
- **1200–1400**: Afternoon bookings; settlement clerk handoff for yesterday's PODs.
- **1400–1700**: Outbound dispatches for overnight runs; pre-check HOS, weather, fuel.
- **1700–2000**: Handoff to after-hours dispatcher; iOS 55 (Shift Handoff) with note dump.
- **2000–0500**: On-call; push for critical events only (breakdowns, late ETAs >2h, crashes).

Watch: Dispatcher complication shows active load count, loads needing attention, drivers at HOS limit. Offline: Full read on cached state; writes queue with conflict resolution on reconnect.

---

## 7.7 Settlement / pay journey (Friday cycle)

- **Monday**: Settlement clerk reviews Friday-Sunday deliveries.
- **Tuesday**: Fuel card data imported, detention claims validated.
- **Wednesday**: Driver disputes window opens; iOS 76 (Dispute Settlement Line).
- **Thursday 1700**: Settlement sheets finalized; carrier admin approves; iOS 77 (Approve Batch).
- **Friday 0600**: ACH file submitted to bank.
- **Friday 1200–1400**: Deposits land in driver accounts; push "Deposit sent."

Watch: driver sees accrued earnings live; Friday deposit haptic is distinct chime. Offline: read-only statements cached; disputes drafted offline, submitted on reconnect. Failures: ACH return → retry Monday; bank holiday shifts cycle; W-4/W-9 mismatch holds payment with urgent banner.

---

## 7.8 Factoring journey — instant pay via HaulPay

Within hours of POD instead of 15–45 day AR cycle.

- **Post-POD (within 10 min)**: Driver sees iOS 78 (Instant Pay Offer) — "Advance $1,847 now for $37 fee, or wait for settlement Friday."
- **Driver taps Accept**: `factoring.advance.create` submits invoice + POD to HaulPay API.
- **HaulPay verifies (usually <60s)**: Returns approval with exact fee.
- **Advance lands in wallet**: Push "Instant pay sent — $1,810 to your card."
- **HaulPay collects from broker** at standard cycle (no driver involvement).

Watch: Instant pay offer shows as actionable notification; accept from wrist. Offline: offer cached; accept must be online. Failure: HaulPay declines (broker not on whitelist) → falls back to standard settlement; driver notified. Latency: offer fetch p95 400ms; accept→deposit p95 90s.

---

## 7.9 Tax journey — January 31 1099 generation

- **Jan 1–14**: Background W-9 completeness check; drivers with missing W-9 get daily push.
- **Jan 15**: Draft 1099s generated; iOS 79 (Tax Documents) shows DRAFT status.
- **Jan 16–30**: Correction window; drivers flag discrepancies, carrier fixes via web.
- **Jan 31 0001**: Final 1099-NEC e-filed to IRS via IRIS; driver gets copy as PDF in-app + email.
- **Jan 31 follow-up**: Physical mail copies printed for opted-in drivers.

Notifications: Jan 15, Jan 25 reminder, Jan 31 final. Watch: Badge on Wallet complication "Tax docs ready." Offline: PDFs cached after download. Failure: IRS IRIS rejection → carrier admin queue; TIN mismatch → B-notice workflow.

---

## 7.10 Training journey — new hire to first load

- **Day 1**: HR adds driver; invite SMS + email.
- **Day 1–2**: Driver downloads, completes iOS 01–05 (Signup, Identity, CDL Upload, W-9, Direct Deposit).
- **Day 2–3**: Assigned training modules — iOS 80 (Training Hub) — DOT refresher, company policies, ELD tutorial, hazmat if applicable.
- **Day 3**: Road test with carrier safety officer logged via iOS 81 (Skills Assessment).
- **Day 4**: Truck assigned, pre-trip walkthrough with trainer, first DVIR together.
- **Day 5**: First load — dispatcher assigns "training load" flagged in system; dispatcher + safety officer get extra notifications.
- **Post-Day 5**: Probationary 30-day flag on driver record; elevated monitoring.

iOS 80–85 is Training module. Backend: `training.modules.list, training.progress.update, training.complete`. Watch: progress ring during onboarding week. Offline: video content pre-downloaded; quiz answers cached + synced. Failure: Failed quiz (<80%) → retake; expired doc during onboarding → hold.

---

## 7.11 Compliance journey — CDL, medical, drug test, CSA

Ongoing, runs in parallel to every load.

- **CDL Renewal**: 90/60/30 day pre-expiry pushes; iOS 82 (Compliance Docs) shows countdown; upload new CDL before expiry or load assignment blocked day-of-expiry.
- **DOT Medical (2-year cycle)**: Same countdown; National Registry of Medical Examiners integration verifies validity.
- **Drug Testing**: Random selection quarterly per DOT rules; `compliance.drugTest.schedule` selects drivers using seedable RNG auditable post-hoc; iOS 83 (Drug Test Notice) with 24–48h window.
- **CSA Score**: Monthly FMCSA data refresh; iOS 84 (Safety Score) shows BASIC scores; alerts if any crosses threshold.

Notifications: compliance events high-priority — push + email + in-app persistent banner. Watch: complication "All clear" or "1 action needed" with tap-to-view. Failure: Expired doc + assignment attempt → hard block.

---

## 7.12 Incident journey — crash to back-in-service

- **T+0s — Incident**: Driver triggers SOS on iOS 99 or accelerometer detects crash-level impact.
- **T+5s — Auto-escalation**: Location + last 30s telemetry + driver info auto-sent to dispatcher + carrier safety + insurance; 911 auto-dial prompted.
- **T+1 min — Scene**: Driver uses iOS 100 (Incident Capture) — photos, police report number, other party info, witness statements.
- **T+10 min — Triage**: Safety officer calls driver; dispatcher reassigns load if possible.
- **T+1 hour — Claim opened**: Insurance claim auto-opened with prefilled data; claim number in-app.
- **T+1-7 days — Repair**: iOS 101 (Vehicle Status — OOS); repair shop assignment, estimate approval, progress tracking.
- **T+repair complete — Return to service**: Post-repair DVIR, safety officer sign-off, back in service.

Watch: SOS is distinct watch gesture (hold-and-release); crash detection can fire from watch alone. Offline: SOS works with cached emergency contacts + offline map; incident capture fully offline. Failure: Network dead at SOS → queued with 10s retry; watch attempts via own cellular or paired phone fallback. Latency: SOS submit p95 400ms, p99 1.5s — but SOS never blocks UI on network; UI acks locally + syncs.

---

## 7.13 Long-haul journey — multi-day OTR with sleeper berth

- **Day 1 0500**: Pre-trip, pickup, start of HOS 14-hour clock, 11-hour drive clock.
- **Day 1 1500**: 30-min break (required at or before 8h drive).
- **Day 1 1900**: End of drive window; pull into rest area; iOS 31 (Sleeper Berth) flipped on.
- **Day 1 1900 — Day 2 0700**: 10-hour off-duty or 7+3 sleeper split.
- **Day 2–4**: Repeat with varying break strategies.
- **Day 5 AM**: Final delivery, POD, head home or reload.

Sleeper berth UX subtle but critical: driver flips to sleeper berth via single prominent button on iOS 31, HOS engine handles math. Split-sleeper rules (7/3, 8/2) auto-calculated + shown. Watch: at sleeper time, watch dims load complication + shows "rest" face; vibrates gently if HOS clock about to reset. Offline: HOS math fully local; ELD record append-only with server sync when online. Failure: ELD malfunction → automatic switch to paper log mode; push to dispatcher + flagged for repair within 24h per FMCSA.

---

## 7.14 Team driver journey — co-driver log sharing + cycle swaps

Two drivers, one truck, one continuous HOS ledger split per-driver. Critical UX affordance is the swap.

- **Swap event**: Driver A pulls over, both drivers authenticate on iOS 32 (Driver Swap) via biometric; HOS clocks swap atomically; driving driver's clock starts, resting driver flips to sleeper berth.
- **Backend**: `hos.swap` is single transactional call — both sides must succeed or both roll back.
- **Notifications**: Dispatcher sees swap event on iOS 54 (Fleet Map) timeline; no push unless swap fails.
- **Watch**: Both watches haptic-confirm swap.
- **Offline fallback**: Swap works offline with local atomic write; reconciled on reconnect; conflict window is microseconds (one device orchestrating).
- **Failure**: Biometric fails for Driver B → fallback to PIN; swap aborted cleanly, state unchanged.
- **Latency**: Swap user-perceived p95 200ms (local); server ack p95 500ms.

Team records also allow cycle-level "who slept when" visibility to carrier safety for fatigue management.

---

## 7.15 Cross-cutting principles for all journeys

Every journey above conforms to invariants enforced at framework layer:

1. **Every state transition is idempotent** with client-supplied idempotency key, enabling safe retries.
2. **Every notification has a de-duplication window** of 5 minutes per event-type per recipient, preventing push storms.
3. **Every screen has a defined offline mode** — either full-offline (DVIR, POD, BOL), read-only-offline (settlements, 1099), or explicitly-online (instant pay accept, tender accept race).
4. **Every backend procedure has a latency budget** tracked in SLO dashboards; p95 breaches trigger on-call within 5 minutes.
5. **Every failure mode has a UI surface** — no silent failures. If something can fail, user sees it, with a next-action.
6. **Every role boundary is enforced server-side** — app trusts nothing; client-side role gating is UX only, not security.
7. **Every long-running journey** (rail, ocean) has daily digest summary so users don't have to re-orient.
8. **Every document generated** (BOL, POD, Carta Porte, 1099, settlement sheet) is PDF with embedded metadata + hash for audit; originals immutable.
9. **Every geofence event** is logged with entry + exit timestamps + radius, supporting dispute resolution months later.
10. **Every journey terminates** with settlement or close-out — no orphaned states; overnight reconciliation job sweeps for dangling loads older than 72h and escalates.

Journeys above are the surface area of the product. Everything else — infrastructure, UI kit, auth model, eventing spine — exists to make these journeys run reliably, legibly, and at scale of tens of millions of loads per year.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
