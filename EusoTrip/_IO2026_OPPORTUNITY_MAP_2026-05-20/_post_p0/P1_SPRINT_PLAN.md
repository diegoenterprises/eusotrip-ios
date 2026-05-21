# IO 2026 P1 sprint plan — post-P0 backlog
**Date:** 2026-05-21 (drafted at P0 sprint close)
**Source:** `01_OPPORTUNITY_MATRIX.md` rows tagged P1

P0 sprint shipped 17/17 in one day; the remaining backlog has **24 P1 + 11 P2 = 35 items**. This doc ranks the P1s by leverage × effort and proposes a Q4 sprint structure.

---

## Ranking framework

Each P1 ticket scored on three axes:

| Axis | Score 1-5 | Meaning |
|------|:--------:|---------|
| **Lev** (Leverage) | 1 = nice-to-have, 5 = unlocks a new revenue line / kills a recurring cost | |
| **Reach** | 1 = one role, 5 = all 12 truck roles + rail + vessel | |
| **Eff** (Effort) | S = 1-2d, M = 3-5d, L = >1wk | inverted in priority calc |

**Priority score = (Lev × Reach) / Eff_weight**, where S=1, M=2, L=4.

---

## Tier 1 — Land first (high-leverage S/M effort)

| Score | # | Opportunity | Lev | Reach | Eff | Why first |
|:---:|---|-------------|:---:|:---:|:---:|-----------|
| **15** | 36 (S) | Subagent orchestration for 7-layer Cortex | 5 | 3 | S | Single-day refactor; unlocks parallel agent fan-out across every existing surface. No new infra. |
| **12** | 31 (S) | Antigravity cron workflows | 4 | 3 | S | Replaces 3 CloudWatch / cron alternatives with GitHub-native scheduled runs; nightly retrain + daily rate card + weekly compliance audit. Zero Azure cost. |
| **12** | 18 (S) | Astra Reefer Temp-Log Reading (OCR reefer unit display) | 4 | 3 | S | Extends shipped Astra infra; driver photos the reefer panel, server OCRs setpoint + return-air + alarms. Anchors a FSMA cold-chain audit trail. |
| **12** | 12 (S) | XR Reefer Temp Monitoring HUD | 3 | 4 | S | Live reefer telemetry on the audio-only XR strip. Same xrChecklist wire we shipped. |
| **10** | 23 (M) | Dispatcher Spark — HoS-aware schedule planning + driver scoring | 5 | 4 | M | Overnight automation for the dispatcher role; biggest time-suck on the platform today. |
| **10** | 21 (M) | Shipper Spark — overnight rate-confirmation drafting + ERP reconciliation | 4 | 5 | M | Closes the loop the founder kept asking for — shipper wakes to drafts ready to fire. |
| **10** | 24 (M) | Catalyst Spark — settlement reconciliation + factoring decisions | 5 | 4 | M | Removes the manual reconciliation queue. Founder pain point per existing wallet flows. |

**Tier 1 estimate: 7 tickets — 4 S + 3 M ≈ 3-4 weeks for 1 engineer.**

---

## Tier 2 — Land second (high-reach M-effort agents)

| Score | # | Opportunity | Lev | Reach | Eff | Why next |
|:---:|---|-------------|:---:|:---:|:---:|----------|
| 10 | 35 (M) | Information agent for shipment status | 4 | 5 | M | ✅ Already shipped as P0-9 — verify, mark closed. |
| 10 | 40 (M) | Information agent for equipment selection | 4 | 5 | M | Replaces the equipment dropdown — commodity → trailer + docs + fleet availability. |
| 9 | 25 (M) | Customs Broker Spark — filing monitoring + USMCA cert gen | 5 | 3 | M | Specialised role but high-revenue per user. Stripe/Mexico customs broker partners already inbound. |
| 8 | 37 (M) | Information agent for lane intelligence + pricing | 4 | 4 | M | Multi-turn rate + surcharge agent. Adds market intel to every load post. |
| 8 | 38 (M) | Information agent for carrier vetting | 4 | 4 | M | FMCSA + EusoTrip scorecard + CSA in one query. |
| 8 | 33 (M) | Hardened Git policies (signed commits + credential vault) | 4 | 4 | M | Pre-IPO due diligence prep; CI hardening. |
| 7 | 30 (M) | Subagent orchestration for 7-layer Cortex | 5 | 3 | M | Listed in Tier 1 above as S — reclassify if scope grows. |
| 6 | 46 (M) | Earth + Gemini vision for dock door geocoding | 3 | 4 | M | Solves the "warehouse address geocodes to street, not to dock door" problem. |

---

## Tier 3 — Astra + XR follow-ups (M-effort, narrower reach)

| Score | # | Opportunity | Lev | Reach | Eff |
|:---:|---|-------------|:---:|:---:|:---:|
| 6 | 19 (M) | Astra OS&D Detection from cargo visual diff | 4 | 3 | M |
| 6 | 17 (M) | Astra POD Photo with auto-detection | — | — | — | ✅ Shipped as P0-17 — close out. |
| 6 | 10 (M) | XR Dock Worker POD Capture | 3 | 4 | M |
| 6 | 11 (M) | XR Cross-Border USMCA Filing Assistant | 4 | 3 | M |
| 5 | 41 (M) | Earth 1m contours for heavy-haul OS/OW route survey | 4 | 2 | M |
| 5 | 45 (M) | Earth flyover for driver pre-trip route preview | 3 | 3 | M |

---

## Tier 4 — Heavy lifts (L-effort)

These are valuable but require either new infra, partner contracts, or significant business workflow:

| # | Opportunity | Why L | Suggested Q1 2027 |
|---|-------------|-------|--------------------|
| 4 | Managed Agents document generator | Needs PDF service + S3 storage | Pair with #28 Cortex migration |
| 7 | Gemini Intelligence async customs filing | Task queue infra (Bull/Temporal/Cloud Tasks) | After Cortex migration |
| 22 | Broker Spark | Rate engine + tender triage modules | Quartet with Catalyst/Dispatcher/Shipper Spark |
| 28 | Migrate 52 Zenith Cortex agents → Managed Agents API | 4-phase migration | The big Q1 2027 unlock |

---

## P2 backlog (Q1 2027) — out of scope for next sprint

| # | Opportunity |
|---|-------------|
| 6 | Gemini Omni explainer videos |
| 13 | XR Hazmat Incident Emergency Response |
| 14 | XR Intermodal Multi-Leg Task Queue |
| 20 | Astra Livestock 28-hr Law Arming (thermal vision) |
| 32 | Native Android app generation (Antigravity prompt → MX/CA/LATAM variant) |
| 39 | Information agent for USMCA cert generation |
| 42 | Earth bathymetry for vessel berth + draught assignment |
| 43 | Earth 3D + Gemini for rail yard convoy staging |
| 48 | TPU 8t for nightly retrain |
| 50 | Enterprise AI Services co-sell with Google Cloud |

---

## Recommended Q4 sprint shape

**Sprint 1 (1 week):** Tier 1 small lifts — #36 subagent orchestration + #31 Antigravity cron + #18 reefer temp OCR + #12 XR reefer HUD.

**Sprint 2-3 (2-3 weeks):** Spark trio — #23 Dispatcher Spark + #21 Shipper Spark + #24 Catalyst Spark.

**Sprint 4 (1 week):** Information agents — #40 equipment selection + #37 lane intelligence + #38 carrier vetting.

**Sprint 5 (1 week):** Hardening — #33 signed commits + credential vault + #46 dock door geocoding.

Total: ~6-8 weeks for 1 engineer; could parallelise Spark trio across 3 engineers and ship in 2 weeks.

---

## Cost guardrail check (every P1 item)

Per the founder's standing 2026-05-20 doctrine ("no Azure cost adds"):

- Tier 1 all-S items: ALL within guardrail. Reefer OCR extends existing Astra Vision; cron workflows run on GitHub Actions; subagent orchestration is a prompt refactor; XR reefer HUD adds one server endpoint + reuses xrChecklist.
- Spark trio (Tier 1 M): all within guardrail. Each Spark is a router + cron-triggered Gemini call. No new Azure resources; Gemini quota is founder-approved.
- Tier 2 information agents: all within guardrail. Gemini-backed query routers.
- Tier 3 Astra + XR: within guardrail.
- Tier 4 L-effort: re-evaluate at scoping. #28 Cortex migration to Managed Agents COULD touch Azure (background workers); needs separate cost review.

---

## What to do RIGHT NOW

1. Update memory with this plan + Tier 1 items as "next to ship."
2. When the founder kicks off Sprint 1, fire `#36 subagent orchestration` first — single-day, single-PR, validates the planning cadence.
3. After Sprint 1 lands, audit telemetry from `aiHealth.getGeminiTelemetry` to see real Gemini cost mix; that informs sprint 2-3 prioritisation.
