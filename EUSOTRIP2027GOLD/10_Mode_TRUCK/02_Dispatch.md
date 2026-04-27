# 10 · Mode TRUCK — Dispatch

**What this covers.** The TRUCK::Dispatch doctrine — four sub-personas (In-House, 3PL, Carrier, Broker), daily lifecycle (05:30 → 22:00), screens 300–316, backend architecture (`dispatch.ts`, `dispatchPlanner.ts`, `dispatchRole.ts`, `aiDispatchAssist.ts`, `controlTower.ts`), load-to-driver matching scoring model, five P1 exception types, Dispatch Board UI (web-primary, mobile mirror), messaging, rate negotiation, rate-con generation, planning subsystem, Autopilot Layer 7-agent cortex, analytics, regulatory (FMCSA CSA, BASIC, driver safety score), **mobile vs web split** (mobile is a companion, not a parity product), offline considerations, hazmat + cross-border dispatch, pitfalls, onboarding. Source: wave-1 shard `team_TRUCK_dispatch`.

**When you need this.** When building any 300-series screen. When scoping a dispatch-adjacent backend change. When a dispatcher asks "why can't I do X on mobile?" (answer: because it's desk work — see §15).

**Cross-links.** Driver ⇄ dispatcher messaging: [70_Messaging_and_ESANG_AI.md](./../70_Messaging_and_ESANG_AI.md). Backend procedures: [03_Backend_API_Contract.md](./../03_Backend_API_Contract.md). Load lifecycle: [80_User_Journeys_and_Load_Lifecycle.md](./../80_User_Journeys_and_Load_Lifecycle.md).

---

## 1. Persona taxonomy

The `TRUCK::Dispatch` role is the beating heart of any trucking operation. Primarily a web power-user during office hours, but critically dependent on mobile during commutes, after-hours escalations, weekends, overnight coverage.

**In-House Dispatcher.** Classic fleet dispatcher at asset-based carrier. Defined driver roster (typically 15-40 per dispatcher), owns driver relationship end-to-end, deep context on each driver's personality, home-time preferences, equipment quirks, performance history. Mobile prioritizes driver-centric views: who's running late, who's due home, who's out of hours. Single `carrierId` scope, full CRUD on assigned loads.

**3PL Dispatcher.** Third-party logistics provider, may/may not own assets. Mixed model: some dedicated capacity, some spot-market procurement, constant customer-facing communication. Mobile emphasizes customer satisfaction signals (shipper scorecards, tender acceptance rates, on-time delivery) alongside capacity. Across multiple `shipperId` relationships; quick context-switching UI needed.

**Carrier Dispatcher.** Similar to in-house but often at larger asset-based carrier with specialized lanes or equipment (reefer, flatbed, tanker). Authority may be lane-scoped or equipment-scoped rather than driver-scoped. Mobile needs equipment-type filtering, lane density heatmaps, backhaul optimization hints.

**Broker Dispatcher.** Non-asset, pure intermediary. Books loads from shippers, covers with outside carriers. Workflow is rate-negotiation-heavy: posting loads, fielding carrier inquiries, checking MC authority + insurance compliance, generating rate confirmations. Mobile leans on rate-negotiation tooling, carrier onboarding checks, tender-not-accepted timers. Typically do not see HOS data for covered carriers; see check-call compliance and carrier scorecards.

---

## 2. Daily lifecycle

**05:30 – 07:00: Load Board Review.** Dispatcher wakes, checks mobile on way to office. Home surface shows `top-5-alerts` digest: overnight check-call failures, tenders expiring before 09:00, loads unassigned for pickups inside 4 hours, any driver HOS violations from overnight Autopilot sweep, detention alarms crossing 2-hour threshold. Can triage from phone — ack, snooze, reassign, escalate — before coffee.

**07:00 – 09:00: Driver Assignment.** Primary work on web Dispatch Board. Unassigned loads from Kanban "Unassigned" lane. Dispatcher drags-and-drops onto driver tile or invokes `aiDispatchAssist` for ranked recommendation. Mobile reflects near-real-time via subscription.

**09:00 – 12:00: Dispatch Acceptance.** Tenders go out to drivers (in-house) or carriers (brokered). Mobile shows live tender-acceptance timer with visual countdown. If driver/carrier fails to accept within SLA (30 min in-house, 2 hours brokered), tender auto-escalates and dispatcher receives push.

**12:00 – 16:00: En-Route Monitoring.** Check-calls come in. Mobile shows live map bubble for every in-transit load; tapping reveals detail drawer. ELD integrations feed position + HOS; color-coded ring indicates HOS cushion (green 4+ hours, amber 1-4, red under 1).

**16:00 – 18:00: Exception Handling.** Bulk of real stress. Overdue check-calls, detention claims, breakdowns, customer reschedules. Mobile `exceptions` tab becomes primary workspace. Each exception is a card with predefined action buttons wired to backend mutations.

**18:00 – 22:00: POD Closeout.** As drivers deliver, PODs flow in from `TRUCK::Driver` mobile capture. Dispatcher reviews, approves, flags damaged goods, triggers billing handoff. Mobile POD review: image-centric with swipe-to-approve and pinch-to-zoom on signatures.

**22:00 – 05:30: After-Hours.** Dispatchers rotate on-call. Mobile push is sole surface. Compact "nightshift" mode presents only P0/P1 alerts with one-tap escalation to carrier's 24/7 duty phone.

---

## 3. Key iOS screens — 300s range

Dispatch screens live in 300s, reflecting secondary (web-primary) status.

- **300 — Dispatch Home.** Top-5 alerts digest, shift-context banner, quick-action row (Broadcast, Search Load, Search Driver, New Exception).
- **301 — Load Board Lite.** Read-optimized list, filterable by status/lane/driver. No drag-drop; assignment routes to 305.
- **302 — Driver Board Lite.** Roster view of dispatcher's drivers with HOS bubble, current location, current load, status chip.
- **303 — Exception Queue.** Card-stack UI, sorted by severity + age.
- **304 — Check-Call Inbox.** Inbound driver messages, categorized (on-time, late, ETA update, issue).
- **305 — Assign Load.** Driver picker with `aiDispatchAssist` recommendations surfaced at top.
- **306 — Tender Tracker.** Outstanding tenders with countdown timers, accept/reject status.
- **307 — Rate Negotiation (broker).** Active negotiation threads, counter-offer input, carrier MC lookup.
- **308 — POD Review.** Image-first queue.
- **309 — Rate-Con Generator.** Parameter form calling `documentManagement.generateRateConfirmation`, returns shareable PDF.
- **310 — Capacity Planner Snapshot.** Read-only view of upcoming 7-day plan; editing web-only.
- **311 — Control Tower Live Map.** Full-screen map with all active loads; pinch-to-filter by equipment type or customer.
- **312 — Broadcast Composer.** Message composer with audience selector (driver pool, lane, equipment-type, custom list).
- **313 — Dispatch Analytics Snapshot.** KPI tiles: loads/day, utilization %, on-time %, detention hours, idle time.
- **314 — Autopilot Review.** Queue of Autopilot-suggested actions awaiting approval.
- **315 — Hazmat Dispatch Panel.** Hazmat-specific filters, ERG lookup, route-restriction warnings.
- **316 — Cross-Border Panel.** Customs broker thread, BOL translation toggle, border-wait ETAs.

Admin surfaces (user management, role assignment, carrier config) live web-only, not duplicated in iOS.

---

## 4. Backend architecture

- **`dispatch.ts`** (~120KB). Main tRPC router for everything dispatch-related. Queries: `listLoads, getLoadDetail, listDrivers, listExceptions, getDispatchBoard, getTenderStatus`. Mutations: `assignLoad, unassignLoad, reassignLoad, sendTender, acceptTender, rejectTender, recordCheckCall, openException, resolveException, approvePOD, flagPOD`. Subscriptions for live board updates, tender state, check-call arrivals. Enforces `carrierId + roleScope` on every call.
- **`dispatchPlanner.ts`.** Forward-looking planning engine. Takes time horizon (default 7 days), current committed loads, forecasted capacity, driver home-time preferences → proposed assignment plan. Used by human planners (web-only) + Autopilot cortex.
- **`dispatchRole.ts`.** Role-specific authorization + feature-flag logic. Gates by sub-persona: broker dispatchers cannot access driver HOS; in-house cannot see broker rate-negotiation threads for carriers outside org; 3PL gets cross-`shipperId` visibility.
- **`aiDispatchAssist.ts`.** Load-to-driver matching engine wrapped as callable service. Given load → ranked driver candidates with explainability strings. Given driver → ranked candidate loads.
- **`controlTower.ts`.** Aggregation layer feeding live map + analytics. Denormalizes position pings, HOS clocks, check-call state, exception flags into single subscription-friendly document per load. What mobile Screen 311 subscribes to.

---

## 5. Load-to-driver matching logic

`aiDispatchAssist` scores each (load, driver) pair:

1. **Proximity.** Haversine from driver's current/projected-empty to load origin, adjusted for deadhead pay.
2. **HOS Feasibility.** Computed available drive + duty hours vs load's required drive time. Below 1.0× safety margin disqualifies.
3. **Equipment Match.** Binary filter: reefer, flatbed, dry van, tanker, hazmat-endorsed.
4. **Home-Time Fit.** Distance from driver's home at delivery, weighted by days-out-from-home.
5. **Customer Preference.** Shipper blacklist/whitelist based on historical scorecard.
6. **Performance.** Driver on-time %, claim rate, check-call compliance.
7. **Rate Attractiveness.** For owner-ops / leased, revenue per mile vs historical acceptance threshold.
8. **Hazmat Certification.** Hard filter.
9. **Cross-Border Endorsement.** FAST card, passport, visa if required.

Output: top-10 ranked list with short human-readable explanation per candidate (e.g., "270 mi deadhead, 8.5 hrs HOS cushion, 94% on-time, routes home by Friday").

---

## 6. Exception handling

Five P1 exception types that must be first-class in mobile UI:

**Check-Call Overdue.** Driver missed scheduled window by threshold (default 30 min). Card: last known position, ETA drift, quick actions: "Call Driver," "Send Ping," "Escalate." Backend: `dispatch.openException` type `check_call_overdue`.

**Detention.** Driver beyond free time (typically 2 hrs) at shipper/receiver. Card: arrival time, elapsed minutes, accessorial rate, auto-generated detention invoice preview. One-tap "Submit Detention Claim" writes to billing.

**Breakdown.** Driver reported mechanical. Card: breakdown location, severity (drivable vs non-drivable), estimated repair time, pickup/delivery appointment impact, workflow to dispatch roadside.

**No-Show.** Driver failed to arrive at pickup within window. Card: last-known position, HOS, contact attempts log, quick action "Find Replacement" invoking `aiDispatchAssist` in emergency mode.

**Refusal.** Driver refused tendered load post-acceptance. Card: refusal reason code, driver notes, "Reassign" surfacing `aiDispatchAssist` alternatives.

---

## 7. Dispatch Board UI — web primary, mobile mirror

Four-lane Kanban on web. Mobile: simplified single-column per lane with horizontal swipe between lanes.

**Lane 1: Unassigned.** Loads booked but no driver. Card: rate preview (dollar-per-mile chip), pickup appointment, delivery appointment, equipment requirement, hazmat flag. Web drag-to-driver-tile; mobile tap-to-assign.

**Lane 2: Assigned.** Driver assigned, tender accepted, not yet en route to pickup. Card: driver name + photo, HOS bubble (color-coded ring), expected pickup time.

**Lane 3: In-Transit.** Load moving. Card: live ETA, check-call compliance indicator, last ping timestamp. ETA drifting outside tolerance → amber; overdue check-call → red.

**Lane 4: Delivered.** POD pending or approved. Card: delivery timestamp, on-time vs late flag, POD status, invoice-ready flag.

**Driver HOS Bubbles.** Circular indicator with three segments: remaining drive hours (outer), remaining 14-hr duty (middle), remaining 70-hr cycle (inner dot). Mobile renders as compact 24px badge.

---

## 8. Messaging integration

Same thread infrastructure as rest of comm layer, with dispatch-specific affordances:

**Broadcast to Pool.** One-to-many outbound to filtered driver set (all reefer drivers, all in Texas, all off-duty). Used for load-availability calls, weather warnings, policy updates. Backend: `messaging.broadcast` with `audience` selector.

**Direct-to-Driver.** One-to-one thread. Load-specific coordination, personal check-ins, home-time negotiation.

**Thread (Load-Scoped).** Multi-party pinned to `loadId` — dispatcher, driver, shipper POC if enabled, customs broker if cross-border. Everyone sees load context automatically.

Mobile: Screen 312 Broadcast Composer + standard messaging (600-range) deep-linking into dispatch context.

---

## 9. Rate negotiation tools

`rateNegotiations.ts` is dedicated module for broker-persona rate conversations:
- `createNegotiation(loadId, carrierId, openingRate)` — opens thread.
- `counterOffer(negotiationId, amount, notes)` — records counter.
- `acceptRate(negotiationId)` — finalizes, auto-generates rate confirmation.
- `declineNegotiation(negotiationId, reason)`.

Mobile (307): thread-style timeline of offers/counters with persistent "Counter" input pinned to bottom + "Quick Accept" button when counter within dispatcher's pre-configured authority threshold.

---

## 10. Rate-con generation

`documentManagement.generateRateConfirmation(loadId, carrierId, terms)`:

1. Pulls load details (commodity, weight, pickup, delivery).
2. Pulls carrier MC/DOT, insurance cert references.
3. Applies broker template (letterhead, T&Cs, accessorial schedule).
4. Produces PDF, archives to document store, optionally emails/texts for e-signature.

Mobile (309): minimal form with template picker, variable inputs, "Generate & Send." PDF previewable in-app before send.

---

## 11. Planning subsystem

- **`dispatchPlanner.ts`** — assignment planning 1–14 day horizon, gantt-style proposed plan.
- **`capacityPlanning.ts`** — inventory-of-trucks forecasting. Given committed maintenance, driver PTO, expected home-time, projected new hires → daily available-trucks count per equipment type.
- **`allocationTracker.ts`** — actuals vs plan. How committed capacity performed against plan. Feeds continuous improvement loop.

Mobile: read-only snapshot (310); full editing web-only.

---

## 12. Autopilot Layer 7-agent cortex integration

Seven agents observe dispatch state and propose or execute actions subject to approval:

1. **Matcher Agent.** Continuously re-scores unassigned loads against available drivers; surfaces high-confidence recommendations.
2. **Check-Call Agent.** Auto-sends scheduled check-call prompts, parses replies for sentiment/issue flags.
3. **Tender Agent.** Manages tender lifecycle, auto-escalation on timeout.
4. **Detention Agent.** Watches facility dwell, auto-opens detention exceptions.
5. **Rate Agent.** For brokers, monitors spot-market indices, suggests counter-offers within authority bands.
6. **Exception Triage Agent.** Classifies incoming exceptions, routes to correct workflow.
7. **Capacity Agent.** Projects future capacity gaps, suggests preemptive driver recalls or broker-out decisions.

Mobile (314): Autopilot Review queue. Each action has "Approve," "Modify," or "Decline" + explainability text + one-tap review.

---

## 13. Analytics

KPI tile grid on Screen 313:
- **Loads/Day.** Daily count closed (assigned, in-transit, delivered).
- **Driver Utilization.** Revenue miles / total miles + idle time.
- **On-Time %.** Pickups + deliveries within window.
- **Detention Hours.** Total accrued, billed vs unbilled.
- **Idle Time.** Between-load hours, segmented by reason.
- **Tender Acceptance Rate.** Broker/3PL: % accepted first-round.
- **Check-Call Compliance.** % received on time.
- **Average Margin.** Broker: average load margin per period.

All tiles drill into full analytics view (web-primary); mobile shows headline + 7-day sparkline.

---

## 14. Regulatory layer

- **FMCSA CSA Scores.** Per carrier interacted with (direct or broker-covered), mobile surfaces current CSA overall + "alert" status from FMCSA SMS.
- **CSA BASIC Monitoring.** Per-BASIC breakdown (Unsafe Driving, HOS Compliance, Driver Fitness, Controlled Substances/Alcohol, Vehicle Maintenance, Hazmat, Crash Indicator). New hazmat load assignment → hazmat BASIC highlighted; cross-border → driver fitness.
- **Driver Safety Score.** Composite internal from CSA, telematics (hard braking, speeding, fatigue events), inspection history, on-time. Input to `aiDispatchAssist`.

Scores refreshed nightly by scheduled job, cached on driver + carrier records. Mobile reads cache; no live FMCSA API call from phone.

---

## 15. Mobile vs web split — the deliberate asymmetry

**Doctrinal position**: Dispatch is heavy-lifting on web. Dispatch Board, planning gantts, rate-con template editors, carrier onboarding flows, deep analytics all web-exclusive.

**Mobile's job**: surface top 5 alerts, support triage + ack, enable drill-in to read-only load/driver detail, enable time-critical mutations (accept tender, approve POD, open exception, broadcast message), fade cleanly into web for everything else.

This is not mobile-parity-by-default. It is mobile-companion intentionally. Dispatchers who try to run entire day from phone hit deliberate friction by design. Product steers them back to web for sustained work.

---

## 16. Offline considerations

Dispatcher is office-bound or home-office-bound majority of day. Unlike driver role, offline is not core.

One offline-adjacent scenario: **commute mobile.** Dispatcher on subway or plane needs inbox + ack. Minimum offline-capable:
- Last-synced state of exception queue (read-only).
- Last-synced state of check-call inbox (read-only).
- Ability to mark items "acknowledged" locally, syncs on reconnect.
- Draft messages offline, queued for send on reconnect.

Nothing else offline. Assigning, tendering, generating rate-cons all require connectivity.

---

## 17. Hazmat dispatch

Screen 315 Hazmat Dispatch Panel:

**ERG Lookup.** Emergency Response Guidebook by UN number, placard, or commodity name. Must pull correct response action within seconds of driver reporting incident.

**Route Restrictions.** State-by-state and municipality-by-municipality restrictions (tunnel/bridge prohibitions, residential bans, time-of-day). Backend cross-references load route with ingested ruleset.

**Hazmat-Certified Driver Filter.** When assigning hazmat, `aiDispatchAssist` hard-filters to drivers with current hazmat endorsement + TWIC (if port-based) + appropriate training. Expired certs suppress driver from candidate list.

---

## 18. Cross-border dispatch

For US-Mexico and US-Canada:

**Customs Broker Coordination.** Each cross-border load has assigned broker. Multi-party thread auto-created: dispatcher, driver, broker.

**BOL Spanish Translation.** For US-Mexico, BOLs auto-translated (or require approved Spanish template) and surfaced in both languages. Mobile toggles between source and translated.

**Border-Wait ETAs.** Live wait times at major crossings (Laredo, El Paso, Nogales, Otay Mesa) surfaced on load card to improve appointment setting.

**Driver Documentation Checks.** Passport, FAST card (expedited lanes), visa (if required) are hard-filter inputs to `aiDispatchAssist`.

---

## 19. Pitfalls

**Double-Booking.** Two loads to same driver with overlapping timelines. Backend validation on every assignment; mobile shows blocking error with conflicting load linked.

**Driver HOS Miscalculation.** Assigning a load driver cannot legally complete. Backend hard-filters infeasible; human override requires explicit reason-code entry.

**Tender Not-Accepted-In-Time.** Tender sits past SLA. Auto-escalation via Tender Agent, visible countdown on 306, push at T-minus-10-min.

**Silent Check-Call Failure.** System dropped check-call and dispatcher didn't notice. Auto-exception from Check-Call Agent surfaces as first-class alert.

**Orphaned Exceptions.** Exceptions opened but never resolved. Daily digest surfaces aged exceptions on 303.

---

## 20. Training and onboarding

Three-phase path:

**Phase 1: Shadow (Week 1).** Read-only access to senior dispatcher's board. Mobile flags user as "shadowing" and suppresses mutation UI. Daily in-app micro-lessons introduce one subsystem at a time.

**Phase 2: Assisted (Weeks 2–4).** Full mutation access but Autopilot set to "supervised" — every agent action requires approval, every dispatcher action mirror-reviewed by senior for first 30 days.

**Phase 3: Autonomous (Week 5+).** Standard access. Autopilot returns to normal thresholds. Ongoing training modules pushed to mobile inbox as new features ship.

In-app training is subset of EusoTrip Learning role, filtered to `TRUCK::Dispatch` curriculum.

---

## Closing

The dispatcher role is where logistics becomes tangible — where plans meet pavement, where rate-cons meet ratchet-straps, where HOS math meets human beings who need to get home by Friday. The EusoTrip mobile app does not replace the dispatcher's web workstation; it augments with triage-grade companion surfaces. Every design choice in 300s screen range reflects that discipline: show top five things that matter, make them one tap to act on, get out of the way.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
