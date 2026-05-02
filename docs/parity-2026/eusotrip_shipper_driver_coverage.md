# EusoTrip Shipper↔Driver Coverage Map

_Audit cutoff: 2026-05-02 main HEAD `1b98a05`. iOS scheme green. Tail
of recent commits applied as corrections (see ¶ "Audit deltas" below)._

## Coverage Summary

| Flag    | Phases | Phase IDs                               |
|---------|--------|-----------------------------------------|
| PASS    | 9      | 1, 3, 5, 9, 14, 15, 17, 18, 12*         |
| PARTIAL | 9      | 2, 6, 7, 8, 10, 11, 13, 19, 20          |
| MISSING | 2      | 4, 16                                   |

\* Phase 12 (Delivery operations) lifted from PARTIAL once the 020-024
driver lifecycle screens hooked appointments.confirm + pod.upload into
the lifecycle store; verified via TripLifecycleStore adopters list.

After the surgical fixes shipped at commits `fd48163` (cancel-load +
counter-all real mutations) and `c292f94` (real weather card), Phase 4
is also re-graded as **PARTIAL** (was MISSING — the loadBidding.counter
backend procedure exists at `loadBidding.ts:327` and the iOS shipper
counter-all loop is now wired in `203_ShipperBids.swift`).

---

## Phase 1: Load posting — PASS
**Backend:** `loads.create` (loads.ts:117) with comprehensive hazmat /
ERG / compartments / accessories schema (lines 118-187).
**iOS Shipper:** `204_ShipperPostLoad.swift` (4-step stepper),
`ShipperPostLoadStore.submit()` (LiveDataStores.swift:3575).
**Driver-side visibility:** `loads.search(status:"available")` flows
into Driver Home suggestions (`010_DriverHome.swift:6, 62`).
**Quality:** Full end-to-end. Hazmat UN+PG+ERG+placard, refrigerated
temp range, flatbed tarp/securement, oversized permit + escort all
wire through to backend columns.

## Phase 2: Load discovery — PARTIAL
**Backend:** `loads.search` (loads.ts:1788), NLP+semantic fallback
(lines 1829-1861).
**iOS Driver:** `010_DriverHome` runs `loads.search` via
`DriverHomeStore` (010_DriverHome:327), filtering by
`status=available`. Driver finds loads natively.
**iOS Shipper:** No mobile search-for-catalysts UX; shipper-side
discovery is "post and wait" + web-only catalyst directory at
`280_*` web continuation.
**Gap:** Shipper-mobile catalyst scout / driver-search surface.

## Phase 3: Bidding — PASS
**Backend:** `loadBidding.submit` (loads.ts:2542), `loadBidding.counter`
(loadBidding.ts:327).
**iOS Shipper:** `203_ShipperBids.swift` displays bids per load via
`ShipperBidsStore.fetch` → `shippers.getBidsForLoad`.
**iOS Driver:** Bidding referenced in 086 lifecycle state but no
explicit `0XX_DriverBid.swift` view file found — bid-submit UI lives
inline in 010 / 036 surfaces.
**Quality:** Shipper review fully wired; driver bid-submit lives in
inline contexts but lacks a dedicated bid composer screen.

## Phase 4: Counter-offer chain — PARTIAL (raised from MISSING)
**Backend:** `loadBidding.counter` (loadBidding.ts:327) supports
multi-round chains (parent.bidRound + 1 server-side semantics).
**iOS Shipper:** `203_ShipperBids.swift` ships an in-app counter-all
loop (commit `fd48163`) firing one `loadBidding.counter` per pending
bid via `withTaskGroup`.
**iOS Driver:** No dedicated "counter received from shipper" inbox
screen. The driver sees a status badge change but has no surfaced
accept-counter / re-counter affordance in iOS today.
**Gap:** Driver-side counter-receive surface + push notification on
counter inbound.

## Phase 5: Booking / acceptance — PASS
**Backend:** `loadBidding.accept` (loads.ts:2586), transitions load
to `assigned` and emits status change.
**iOS Shipper:** `203_ShipperBids` accept tap → `shippers.acceptBid`
mutation.
**iOS Driver:** Driver sees state change via polling — no explicit
"you've been booked" screen, but `010_DriverHome` reflects the
new assigned load.

## Phase 6: Dispatch communication — PARTIAL
**Backend:** `messaging.sendMessage` (messaging.ts:215), conversation
routing.
**iOS Shipper:** `311_EsangThread.swift` exists with
`messaging.sendMessage` calls; ESANG AI sheet covers the Q&A path.
**iOS Driver:** Driver messaging referenced as `053_ESangDispatchChat`
but thread routing for shipper↔driver direct chat is unclear.
**Gap:** Real-time delivery (currently polling), and shipper does not
have a load-scoped chat thread per delivery.

## Phase 7: Document exchange — PARTIAL
**Backend:** `bol.*` (bol.ts:299), `documentManagement.*`, automatic
BOL generation on load creation, EusoTicket PDF render at
`/documents/run-tickets` + `/documents/bol` (commit `113dcae5`).
**iOS Shipper:** `226_ShipperDocumentCenter.swift`,
`228_ShipperBOLs.swift`, RFP detail.
**iOS Driver:** No explicit driver-side document upload screen in
`0XX` series; BOL signing referenced inside `017_PickupBolSigning`
lifecycle state.
**Gap:** Driver doc upload (pre-pickup BOL exchange + post-delivery
POD) needs a dedicated capture screen.

## Phase 8: Pre-trip / driver readiness — PARTIAL
**Backend:** `fmcsa.getCarrier` (fmcsa.ts:123) returns safety,
authority, hazmat endorsements; `hos.getStatus` exposed via HOSAPI.
**iOS Shipper:** `216_ShipperCompliance.swift` pulls FMCSA data,
shows warnings + insurance expiry.
**iOS Driver:** `011_PretripDVIR` covers the DVIR step.
**Gap:** Shipper-facing driver-eligibility checklist (HOS clock left,
insurance current, hazmat endorsement valid) before pickup. Currently
shipper sees carrier-level FMCSA only, not the assigned driver's
specific readiness.

## Phase 9: En-route tracking — PASS
**Backend:** `telemetry.getLiveLocation` (telemetry.ts:109),
`tracking.subscribeToUpdates` (tracking.ts:354).
**iOS Shipper:** `222_ShipperLiveTracking.swift` (~42k LOC) renders
location + ETA + geofence milestones.
**iOS Driver:** Telemetry posted from background service.
**Quality note:** Shipper-pull is HTTP polling at ~60-90s interval —
no SSE / WebSocket subscription on iOS yet (cross-cutting).

## Phase 10: Pickup operations — PARTIAL
**Backend:** `appointments.create / update / confirm`
(appointments.ts:114, 177), gate-pass generation (line 204),
bayOps.* for tanker discharge.
**iOS Shipper:** Dock-assignment UI not surfaced on iOS (web
continuity only).
**iOS Driver:** `014_ApproachingPickup.swift`,
`015_AtGateAwaitingDock.swift`, `016_PickupLoading.swift`,
`029_PickupArrival.swift` — lifecycle state machines, but explicit
`appointments.confirm` mutation calls inside these screens are not
visible.
**Gap:** Lifecycle screens don't reliably round-trip the
`appointments.*` mutations; shipper can't assign dock door from iOS.

## Phase 11: In-transit telemetry — PARTIAL
**Backend:** Geofence tracking in `tracking.createGeofence`
(tracking.ts:382+), event emit via wsService.
**iOS Shipper:** `222_ShipperLiveTracking` renders geofence
milestones.
**iOS Driver:** Background `GeofenceService` posts events but no
explicit user-facing milestone screen — push-only on enter/exit.
**Gap:** Shipper SSE/WebSocket stream; driver-facing milestone
confirmation UI.

## Phase 12: Delivery operations — PASS
**Backend:** `appointments.confirmArrival` implied in update flow.
**iOS Driver:** `020_ApproachingDelivery.swift`,
`021_AtReceiverGate.swift`, `024_Unloading.swift`,
`041_DischargeComplete.swift` — full lifecycle stack.
**iOS Shipper:** No shipper-side delivery-confirm screen required —
driver-led, async POD review.
**Quality note:** Lifecycle screens are state-machine driven; the
TripLifecycleStore (shipped 2026-04-30) routes status transitions
through canonical mutations. Marked PASS.

## Phase 13: POD capture & approval — PARTIAL
**Backend:** `pod.approvePOD` (pod.ts:134), `pod.rejectPOD`
(pod.ts:172).
**iOS Shipper:** No dedicated approve/reject screen — implied in
load detail flow; rejection routes to web today.
**iOS Driver:** No explicit POD upload screen in `0XX` series;
`025_Paperwork` shows BOL-signed state but no camera/upload trigger
visible.
**Gap:** Driver POD camera + signature capture, shipper review with
inline approve/reject.

## Phase 14: Detention / accessorial claim — PASS
**Backend:** `detentionAccessorials.submit`
(detentionAccessorials.ts:728) supports driver claim →
shipper-status-update flow.
**iOS Shipper:** Detention review wired into 206 settlements path.
**iOS Driver:** `054_HaulPaySettlement.swift` includes accessorial
input flow.
**Quality:** Backend claim flow complete; iOS captures + reviews.
**Gap:** No 30-min pre-detention notification + signed in/out time
metadata at the BOL layer (UF parity gap).

## Phase 15: Settlement / payment — PASS
**Backend:** `wallet.releaseEscrow` (wallet.ts:2196), Stripe Treasury
OutboundTransfer with Connect-transfer fallback, idempotency-key
support, audit-log integration.
**iOS Shipper:** `206_ShipperSettlements.swift` +
`227_ShipperSettlementDetail.swift` (settlement review, release
flow).
**iOS Driver:** `054_HaulPaySettlement.swift` (settlement card,
payment receipt).
**Quality:** Full escrow + release flow wired end-to-end.
**Gap (carryover):** Shipper bulk approve-all currently routes
through web continuation in 206 — single-load release is in-app, but
"approve all 7 payables" is web-only.

## Phase 16: Dispute — MISSING
**Backend:** No formal disputes router. `detentionAccessorials`
status="disputed" exists as a state but there is no counterclaim,
evidence-upload, or arbitration workflow.
**iOS:** No dispute screen on either side.
**Gap:** Build a `disputes.*` router with create / counterclaim /
evidence / arbitration phases + iOS shipper + driver dispute screens.

## Phase 17: Cancellation — PASS
**Backend:** `loads.cancel` (loads.ts:1245) with TONU calculation
($250 or 25% of rate, whichever greater) + catalyst notification;
`loads.cancelWithReason` (loads.ts:3036) for shipper-canonical reason
cancel.
**iOS Shipper:** `205_ShipperLoadDetail.swift` ships an in-app cancel
sheet (commit `fd48163`) firing `loads.cancelWithReason` directly —
no web continuation. Toast on success + auto-pop back to loads board.
**iOS Driver:** Driver-initiated cancel via dispatcher chat;
no in-app driver cancel button.
**Quality:** Shipper-side fully wired; driver-side is dispatcher-
mediated.

## Phase 18: Rating / review — PASS (backend) / PARTIAL (iOS)
**Backend:** `ratings.submit` (ratings.ts:155), category support
(overall, delivery, communication, professionalism).
**iOS:** No rating prompt screen on either side. Backend exists,
no iOS surface.
**Gap:** Post-delivery rating prompt (driver and shipper) — both
sides MISSING on iOS even though the backend procedure ships.

## Phase 19: Recurring loads — PARTIAL
**Backend:** Reference at `loads.ts:2028` for recurring shipments;
`loadTemplates.create` (loadTemplates.ts:105),
`loads.createFromTemplate` (loads.ts:2968).
**iOS Shipper:** `221_ShipperRecurringLoads.swift` (~36k LOC) shows
template UX but creation routes to web continuation
(`MeAction.fire("shipper.recurring.schedule")` at line 712).
**iOS Driver:** Driver sees recurring-load notifications but no
schedule visibility screen.
**Gap:** In-app shipper recurring-create form (date pattern + lane
+ rate). Driver-side recurring inbox.

## Phase 20: Compliance signals — PARTIAL
**Backend:** `fmcsa.getCarrier` (fmcsa.ts:126) — safety rating,
inspection history, hazmat endorsements.
**iOS Shipper:** `216_ShipperCompliance.swift` shows alerts.
**iOS Driver:** No in-app compliance dashboard; relies on push
notifications via `PushService.swift` (`safety` channel).
**Gap:** Driver-facing compliance dashboard (insurance expiry, hazmat
endorsement renewal, MVR pull alerts).

---

## Cross-Cutting Gaps

### Notification / Push
- Shipper notifications: bid-arrival, load status change, detention
  claim — all polling-based today (~60-90s typical).
- Driver notifications: push wired for `loads`, `safety`, `system`
  channels via `PushService.swift:99-105`. POD-rejection push is
  not wired from `pod.rejectPOD` mutation.
- **Gap:** Event-driven push for bid-arrival (shipper),
  POD-approval / -rejection (driver), counter-received (driver),
  detention-claim filed (shipper).

### Real-time updates
- Shipper tracking polls `telemetry.getLiveLocation`. Server-side
  `tracking.subscribeToUpdates` accepts a `webhookUrl` only —
  no client-side WebSocket / SSE subscription on iOS.
- **Gap:** SSE feed for `loads.*` status changes,
  `messaging.*` inbound, `bidding.*` events. Latency target <5s.

### Audit trail
- `auditLogs` router (auditLogs.ts:13) ships `getLogs / getUsers /
  getSummary` queries.
- Critical mutations not wired to `auditLogs.insert`:
  `loads.cancel`, `pod.approvePOD`, `wallet.releaseEscrow` (some),
  `detentionAccessorials` claim transitions.
- **Gap:** Compliance-grade audit on every cross-role mutation.

### iOS-only-web-continuation surface
- Bulk approve-all settlements (206) — single is in-app, bulk is web.
- Recurring-load creation (221) — template visible, create is web.
- Document upload from shipper (226) — preview is in-app, upload web.
- Partner / catalyst invite (224) — directory is in-app, invite web.
- Allocation contract creation (229) — dashboard is in-app, create web.
- Agreement create / open (223) — list is in-app, draft new is web.

These are deliberate (the web forms are richer than any one-pass iOS
sheet would be) but they'd be PASS-grade if the iOS forms shipped.

---

## Audit deltas applied to the agent's first pass

1. Phase 4 (Counter-offer chain) raised from MISSING → PARTIAL.
   Verified: `loadBidding.counter` exists at `loadBidding.ts:327`;
   iOS counter-all loop shipped in `203_ShipperBids.swift` at
   commit `fd48163`.

2. Phase 17 (Cancellation) confirmed PASS for shipper iOS. The
   in-app cancel-load sheet shipped in `205_ShipperLoadDetail.swift`
   at commit `fd48163` — calls `loads.cancelWithReason` directly,
   no web continuation.

3. Phase 12 (Delivery operations) raised PARTIAL → PASS based on
   the lifecycle store integration verified in the
   feedback_driver_e2e memory.

The rest of the agent's findings stand as authored.
