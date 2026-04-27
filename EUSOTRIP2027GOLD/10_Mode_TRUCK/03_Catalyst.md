# 10 · Mode TRUCK — Catalyst

**What this covers.** The TRUCK::Catalyst doctrine — persona (commission-earning independent matcher, not broker-of-record), 5-state lifecycle (Discover lane → Match carrier → Broker relationship → Co-broker OR direct match → Commission settlement), screens 500–599, backend (`catalysts.ts`, `catalystPackets.ts`, `commissionEngine.ts`), commission-only wallet, three load-sourcing modes (post truck, browse freight, relationship matching — the dominant mode), the Catalyst tender process contrasted with Broker tender, verification (credit check / MC verification / FMCSA lookup), disputes landmine, tax (1099-NEC, self-employed posture, EIN vs SSN). Source: wave-1 shard `team_TRUCK_catalyst_broker` Part I.

**When you need this.** When building 500-series screens. When wiring commission math. When working with co-broker packet lifecycle. When making a feature work across Catalyst AND Broker.

**Cross-links.** Broker counterpart: [04_Broker.md](./04_Broker.md). Messaging: [70_Messaging_and_ESANG_AI.md](./../70_Messaging_and_ESANG_AI.md). Backend procedures: [03_Backend_API_Contract.md](./../03_Backend_API_Contract.md). Cross-role doctrine (Catalyst + Broker together): see bottom of this file.

---

## 1. Persona

The Catalyst is the platform's answer to the independent freight matcher — the person who, in the legacy industry, lives on the phone and survives on relationships. They do not own trucks. They do not hold a broker bond in their own name (that is the Broker's jurisdiction). They do not carry a BOC-3. What they have is a rolodex, a feel for a lane, and the judgment to know when a carrier's "I've got capacity Thursday out of Laredo" is worth a shipper's "I need a dry van on Thursday out of Laredo."

Inside EusoTrip the Catalyst is modelled as a **commission-earning independent contractor** who operates *under* a Broker umbrella (co-brokered) or, in the more mature flow, directly between a shipper and a carrier on paper issued by EusoTrip's own broker-of-record entity. In both cases the Catalyst is the *matcher*, not the *principal*. Their income is commission; their asset is reputation; their liability posture is narrow by design — the bond, the contingent cargo policy, and the surety all sit one layer up.

Where a traditional brokerage hires W-2 agents and pays a desk rate, EusoTrip unbundles the agent function into a self-serve role. The Catalyst onboards themself, runs their book inside the app, and gets paid on the settlement rail that the rest of the platform already uses. They are referral-driven — a large fraction of their loads come from inbound relationships rather than the load board — and the product must respect that. Catalyst tooling is *contact-first*, not *load-first*.

The Catalyst's day reads very differently from a Broker's day. A Broker is optimizing margin across a portfolio of contracts. A Catalyst is optimizing *throughput* against a personal relationship graph. Doctrine follows: Catalyst UI prioritizes speed of match, Broker UI prioritizes depth of data.

---

## 2. Lifecycle — five canonical states

A Catalyst engagement runs through five canonical states, which are the axes of the `catalyst_engagement` ledger table and the governance model of `catalystPackets.ts`:

1. **Discover lane.** The Catalyst identifies a repeating freight flow. Sources: inbound shipper referral, outbound cold outreach, load-board posting they choose to work, or re-power opportunity surfaced by `laneInsights`.
2. **Match carrier.** Matches lane to carrier. Almost never impersonal ranking query — the Catalyst selecting from their *known carriers* list, augmented by FMCSA/clearinghouse signals surfaced inline.
3. **Broker relationship.** Because the Catalyst is not broker-of-record, the load must be *carried* by either EusoTrip's house broker entity or external licensed Broker the Catalyst has co-brokerage agreement with. Packet-writing phase: `catalystPackets.ts` issues co-brokerage packet, pins commission-split terms.
4. **Co-broker OR direct match.** Two terminal shapes:
   - **Co-broker**: external Broker is carrier's counterparty. Catalyst earns split on top of Broker's margin. Broker invoices shipper; Catalyst's share flows through co-broker packet.
   - **Direct match**: EusoTrip's house broker is counterparty. Catalyst earns commission against gross margin. No external Broker.
5. **Commission settlement.** On delivery + POD, `commissionEngine.ts` fires. Commission computed, held, released per settlement schedule Catalyst is enrolled in (weekly default, optional quickpay).

These five are the only states appearing in Catalyst wallet transaction stream. If a backend event does not map to one, it does not post.

---

## 3. iOS screens — 500s range

Catalyst screens live in **500–599 range**. Numbering is not cosmetic — it's how `mobileRouteRegistry` knows a route belongs to the Catalyst surface, dictates analytics tagging, feature-flag gating, badge used in global nav.

Reserved allocations (canonical):

- **500 CatalystHome** — today's matches, open tenders awaiting carrier acceptance, commission accrual strip.
- **510 CatalystContacts** — carrier and shipper rolodex; screen Catalysts spend most time on. Search-first, tag-driven.
- **520 CatalystLaneDiscover** — browse freight / post truck / lane alerts. Surfaces `laneInsights` rankings.
- **530 CatalystMatchComposer** — build match: pick shipper, pick carrier, pick rate, pick broker-of-record.
- **540 CatalystTender** — outbound tender to carrier with relationship-aware flow (see §7).
- **550 CatalystPackets** — co-brokerage packets, rate confirmations issued under packet, signed artefacts.
- **560 CatalystWallet** — commission accrual, settlement schedule, quickpay, Stripe Connect linkage.
- **570 CatalystCreditCheck** — shipper credit check entry point (see §8).
- **580 CatalystVerification** — MC verification workspace (see §8).
- **590 CatalystDisputes** — dispute management. Talk to §9 for landmine.

501-509, 511-519 etc. reserved for sub-flows (modals, multi-step wizards). A new top-level Catalyst destination should occupy next free decade, not squat inside existing one.

---

## 4. Backend — three primary modules

Sizes canonical at time of writing. Unexpected growth beyond → refactor trigger, not feature request.

- **`catalysts.ts`** (84 KB) — main router. Owns CRUD for catalyst identity, relationship graph, match records, packet lifecycle, commission read-models. One of largest single-role routers — intentionally monolithic: Catalyst workflow crosses too many entities (contact → lane → match → packet → commission) to decompose cleanly without cross-module transaction overhead. When it crosses 100 KB, split **by lifecycle phase**, not by entity.
- **`catalystPackets.ts`** — packet issuance: co-brokerage agreement, rate confirmation, carrier packet. Notarization layer. Anything signed on Catalyst side passes through here, gets packet hash pinned to load.
- **`commissionEngine.ts`** — computes commission at settlement. Reads match record, co-broker split table, overrides, platform take. Writes commission ledger entries. Stripe Connect transfer triggered from here on schedule, not inline.

Three rules:

1. `catalysts.ts` writes *identity and relationship*. Does not compute money.
2. `catalystPackets.ts` writes *artefacts*. Does not compute money.
3. `commissionEngine.ts` is the *only* module writing to commission ledger. Commission ledger insert outside `commissionEngine.ts` is a bug.

---

## 5. Catalyst wallet — commission-only

Strictly a **commission earnings wallet**. Not an operating account. Not a broker escrow. Does not hold carrier payables or shipper receivables — that's Broker wallet's job.

What it holds:
- **Accrued commission** — earned on delivered + POD'd load, not yet settled.
- **Held commission** — under dispute or pending chargeback review.
- **Available for payout** — released by settlement scheduler.
- **In flight** — Stripe Connect transfer initiated, awaiting confirmation.
- **Paid** — terminal.

Settlement schedules configured per Catalyst:
- **Weekly standard** (Friday for prior Mon-Sun, 1-day POD cure window).
- **Biweekly** (for Catalysts who prefer larger cadence + fewer Stripe fees).
- **Quickpay** (per-load, factoring-style discount taken by platform; opt-in, disclosed).

Payout rail: **Stripe Connect Express**. Catalyst completes Stripe onboarding during signup; 1099-relevant tax attributes captured by Stripe, mirrored into Catalyst profile for platform's own 1099 run (§10). No other rail. If Stripe Connect not onboarded, commission accrues but does not release.

---

## 6. Load sourcing — three shapes

Catalyst sources work in three shapes; UI in 520/530 is built around the distinction:

1. **Post truck.** Publishes carrier's capacity ("dry van, Laredo → Dallas, Thursday, $/mi indicated") and waits for shippers (or other Catalysts/Brokers) to bite.
2. **Browse freight.** Scans internal load board for loads Broker side has opened to co-brokers, or shipper-posted. Where `loadBoard.ts` intersects Catalyst surface — reads from same board Broker writes to, with different filters and different conversion button.
3. **Relationship-based matching.** The dominant mode. Catalyst composes match from rolodex: "I know this shipper has this, I know this carrier wants that, let me draw the line." Product must make this path the shortest path. Screen 530 (MatchComposer) opens by default to *your contacts*, not to load board.

Ordering — relationship first, browse second, post truck third — reflects how successful Catalysts actually work and is enforced by default sort on 500.

---

## 7. The Catalyst tender process vs Broker tender

A Broker tender is **transactional**: Broker has a load, pushes to ranked list of carriers, accepts first qualifying response. Scoped by rate, equipment, service level. Implied "take it or leave it" cadence — Broker working portfolio, cannot hand-hold.

A Catalyst tender is **relational**: Catalyst is usually tendering to *one known carrier* whose capacity they already have a read on. Tender is formalization of conversation that often already happened off-platform.

Product implications enforced in 540 CatalystTender:

- **Single-recipient default.** Defaults to one carrier, not broadcast. Broadcast available but intentional choice.
- **Pre-wired rate.** Rate typically agreed by phone beforehand; tender screen prefills rather than asks.
- **Chat thread attachment.** In-app messaging thread with that carrier attached to tender — tender is not cold artefact but next message in ongoing conversation.
- **Longer response window.** Broker tenders time-box aggressively (often 30 min). Catalyst tenders default longer (multiple hours) — relationship is the asset.
- **Packet issued on accept.** On carrier acceptance, `catalystPackets.ts` immediately cuts rate confirmation under broker-of-record's paper. Catalyst does not sign rate-con themselves; packet is signed under broker entity with Catalyst named as agent.

This distinction matters because if Catalyst tenders are built as copy-paste of Broker tenders, adoption craters. Catalysts experience broadcast-style tender flows as *hostile to their book of business* — they read it as platform trying to disintermediate them.

---

## 8. Verification and trust

Catalyst does not carry broker bond, but carries reputational risk on both sides. EusoTrip surfaces three verifications plus regulatory baseline:

- **Credit check on shipper** — before match is paper-issued, platform runs credit check (Ansonia / RMIS / Compunetix tier, whichever configured). Shipper must pass tenant-level threshold, or Catalyst must explicitly override with elevated-risk acknowledgement that writes to audit log. Screen 570 CatalystCreditCheck is the surface.
- **MC verification on carrier** — Motor Carrier number, authority active, operating status, insurance on file, broker-of-record listed as additional insured on cargo certificate. Precondition for any tender, not post-tender check. Screen 580 CatalystVerification.
- **FMCSA lookup** — platform pulls SAFER/SMS signals (BASIC percentiles, inspection history, crash indicator), displays plain-English safety summary inline in MatchComposer. Clearinghouse (drug & alcohol) is separate pull at packet time. If carrier in prohibited status on Clearinghouse, packet blocked — Catalyst cannot proceed.

None presented as *optional*. Presented as *already run*, with clear pass/fail badges. Catalyst allowed to override only where platform policy permits; overrides audit-logged.

---

## 9. Disputes + resolution — the landmine

Five routers carry dispute-adjacent methods (`disputeOpen, disputeRespond, disputeEscalate, disputeResolve, disputeClose`) but **no shared `dispute` entity** backing them. SKILL.md §16 landmine, live today.

Practical shape:

- Each router models dispute inside own domain entity — commission dispute is a row on commission ledger, packet dispute is flag on packet, carrier dispute is state on load, etc.
- No single `disputes` table to query "how many open disputes does this tenant have." Ops team runs five queries and unions.
- State transitions inconsistent across routers. `disputeEscalate` in one advances status enum; in another writes event and leaves status unchanged.
- Notifications, SLAs, escalation timers implemented per-router, with drift.

Doctrinal position for 2027: **do not build a sixth dispute surface on top of this.** The Catalyst dispute screen (590) must be built against a *normalized* dispute entity that this section is the forcing function for. Scoped under backlog item `DISPUTES-UNIFY` and blocks any new dispute-flavoured feature across TRUCK vertical.

Until unification lands, Catalyst dispute screen reads from thin aggregation view joining the five routers' per-entity dispute shapes into common shape. View is intentionally read-only on client — writes still go to owning router, so data model debt is not compounded.

---

## 10. Tax — 1099, self-employed posture, EIN/SSN

Catalyst is independent contractor. Classification governs entire tax surface.

- **1099-NEC generation.** Platform generates 1099-NEC for every Catalyst crossing reporting threshold in calendar year. Runs in January for prior year. Data from commission ledger (source of truth) cross-checked against Stripe Connect payouts report (reconciliation).
- **Self-employed tax posture.** Catalyst is told, in onboarding + wallet copy, that platform does not withhold. They are responsible for quarterly estimated taxes. Link to IRS guidance + disclaimer permanent in 560.
- **EIN vs SSN.** On onboarding Catalyst chooses entity type: sole proprietor (SSN), single-member LLC (EIN or SSN per election), multi-member LLC or S-corp (EIN). Chosen identifier captured by Stripe (not stored in plaintext on our side), last four mirrored into Catalyst profile for display + 1099 reconciliation.
- **W-9 collection.** Stripe Connect handles W-9 as part of Express onboarding. No parallel W-9 flow. If Stripe's W-9 copy missing or stale, payouts halt until refreshed; Stripe's rule, we mirror it.
- **State backup withholding.** For states requiring backup withholding on 1099 income (CA especially), platform flags Catalyst's address in Stripe; Stripe handles withholding on payout rail. Platform UI surfaces as line item in wallet, not as surprise deduction.

Doctrinal rule: *the platform is not the Catalyst's accountant.* It is the Catalyst's payer and record-keeper. Every tax-adjacent piece of UI must reinforce that posture.

---

## Cross-role doctrine — Catalyst and Broker together

Three principles governing how these roles coexist on the platform:

1. **The Catalyst never *becomes* a Broker implicitly.** If Catalyst wants to hold own authority and operate as Broker, they go through full Broker onboarding — new entity, new KYC, new bond, new role. No in-app promotion path that skips those gates. Data model permits user to hold both roles (dual-hat) but roles are separate objects with separate ledgers.

2. **A load has exactly one Broker of record.** When Catalyst is in chain, co-brokerage packet names Broker of record explicitly, all downstream artefacts (rate-con, invoice, BOL reference) carry that Broker's MC. Non-negotiable for regulatory reasons, enforced at packet-issuance time.

3. **Disputes, claims, and settlement flow up the chain.** If carrier disputes rate-con issued under co-broker packet, dispute routes to Broker of record, not Catalyst. Catalyst is participant (notified, can contribute context) but not principal. Commission ledger holds back Catalyst's share until dispute resolves.

These three principles + landmines (disputes not unified, FSC not recomputed at settlement in Broker's §9) are load-bearing for any TRUCK feature touching both roles.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
