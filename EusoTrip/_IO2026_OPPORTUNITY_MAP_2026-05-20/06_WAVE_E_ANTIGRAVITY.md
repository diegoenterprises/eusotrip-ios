# Wave E — Antigravity 2.0 + CLI + Managed Agents
**Agent #5 deliverable** | 6 opportunities + 48-week porting sequence

## Opportunity A — Migrate Zenith Cortex 52-Agent System to Managed Agents API

**What it replaces:** Custom orchestrators (ConvoyCommander, DispatchBroker, ComplianceGuardian, FinanceOracle, StrategicPlanner + 47 others, currently hand-wired via tRPC + Redis pub/sub). Replaces manual agent lifecycle, context window routing, token budgeting.

**Files:** New `/agents/layer1_sensory/` (8 agents — geofencing, NI ranging, ELD/HOS) → `/agents/layer2_dispatch/` (12 agents) → `/agents/layer3_compliance/` (14 agents) → `/agents/layer4_financial/` (6 agents) → `/agents/layer5_strategic/` (8 agents) → `/agents/layer6_guardian/` (4 agents)

**Migration plan (4 phases):**
- Phase 1 (Wk 1-4): Sensory layer — port geofence to Managed Agents, test against live NI event stream. Baseline 120ms → target 85ms. Feature flag `USE_MANAGED_AGENTS=false` for rollback.
- Phase 2 (Wk 5-8): Dispatch — convoy load assignment, ConvoyRollingMesh with NI multi-peer formation snapshot. Risk: 15s deadline on 6-8 simultaneous NISessions.
- Phase 3 (Wk 9-12): Compliance + Financial — hazmat hose-valve real-time checking (Pod 7), settlement atomic processing. Risk: concurrent writes; use idempotent keys + Postgres advisory locks.
- Phase 4 (Wk 13-16): Strategic + Guardian — rate optimization, fraud detection (manual override queue for FPs), AV emergency takeover.

**Cost impact:**
| Metric | Before | After | Savings |
|--------|--------|-------|---------|
| API calls/day | 14M | 8.4M | 40% |
| Gemini cost/month | $18,500 | $6,200 | **67%** |
| Ops debugging | 320 hrs/mo | 80 hrs/mo | 75% |
| Latency p95 | 320ms | 120ms | 62% faster |

**Annual savings:** ~$147,600 + ops time.

**Effort:** L (16 wk, 4 FTE — 2 senior backend, 2 mid-level)

## Opportunity B — Antigravity CLI for Plugin/Skill Generation

**What it replaces:** `/skills/*/SKILL.md` (markdown definitions) + `/deploy/skill-deploy.sh` (error-prone bash with credential handling).

**After Antigravity CLI:**
```bash
antigravity skill init --name hazmat-connect --description "NI-guided hose connection"
antigravity skill add-tool --tool=ni-distance-poll --scope=local
antigravity skill test --mode=offline --seed-data=mock_hose_tags.json
antigravity skill publish --channel=staging --audit=true
```

**Phases:**
- Wk 1-2: Install CLI everywhere (developer machines + CI/CD). Wrap existing 12 core skills in CLI skeleton (no logic changes). Dual-deploy old + new pipelines for parity validation.
- Wk 3-4: Migrate hazmat-connect first (highest stakes, NI-dependent). CLI provides SandboxEnv isolation, vault credential injection, signed commits + branch protection + 2-approval requirement.
- Wk 5-12: Migrate fuel-loading, dry-bulk, reefer, escort, compliance, dispatch, finance, driver-coaching, messaging, billing, analytics, terminal-ops skills.

**Cost impact:**
| Metric | Before | After |
|--------|--------|-------|
| Skill deploy time | 45 min (manual) | 8 min (auto) — 82% faster |
| Security incidents (leaked creds) | 2-3/qtr | 0 — 100% |
| Dev onboarding (new skill) | 4 hrs | 20 min — 88% faster |

**Effort:** M (4 wk, 2 FTE — 1 principal CLI/DevOps, 1 senior migration)

## Opportunity C — Subagent Orchestration

**What it replaces:** Monolithic 8000-token agents reading full context. Replaced by parent agent spawning specialized subagents in parallel.

**Example — Load Assignment Flow:**
```
DispatchBroker (parent)
├── LoadMatcher (subagent) — parses load, extracts requirements
├── CarrierValidator (subagent) — insurance, compliance, hazmat cert
├── RateOptimizer (subagent) — market rates, surge pricing
├── FormationCheck (subagent) — driver in active convoy?
└── Synthesizer (subagent) — merges results, outputs assignment
```

Each subagent: 1500-2000 tokens, isolated context, deterministic tool calls. Parent spawns all 5 in parallel; waits 4s; merges with Synthesizer. **200ms total vs. 800ms sequential.**

**Phases:**
- Wk 1: Design subagent topology — map each of 7 layers' workflows to subagent call graphs, identify parallelization (CarrierValidator + RateOptimizer can run simultaneously)
- Wk 2-3: Build dispatch layer (12 agents → 3 parent + 9 subagents). Validate latency, error handling, timeout, deterministic merging.
- Wk 4+: Expand to compliance (HazmatValidator + InsuranceChecker + FMCSAChecker in parallel; currently sequential), guardian (FraudDetector + SOS Router + AV Takeover in parallel).

**Cost impact:**
| Metric | Before | After |
|--------|--------|-------|
| Avg cost per dispatch | $0.032 | $0.018 — smaller contexts |
| Latency p99 | 1.2s | 0.4s — parallel subagents |

**Effort:** M (4 wk, 3 FTE)

## Opportunity D — Cron Workflows for Nightly Retrain

**What it replaces:** `automatedRetrain.ts` on Lambda + CloudWatch Events. Replaced with Antigravity native cron via Managed Agents background task.

**After:**
```yaml
# agents/batch/retrainSyncWindowModel/SKILL.md
cronExpression: "0 2 * * *"  # Every day 02:00 UTC
timeout: 3600s
tools:
  - db_query (read shipments)
  - gcs_read (ML training data)
  - s3_write (save retrained model)
```

**Phases:**
- Wk 1-2: Implement `retrainSyncWindowModel`. Validate scheduler fires reliably; model artifact written to correct S3 location. At-most-once semantics.
- Wk 3-4: Add `computeRateCardDaily` + `complianceAuditWeekly`. Shared Managed Agents executor pool.
- Wk 5-8: Migrate all background workers — `scoreCarrierPerformance` (hourly), `archiveOldSessions` (weekly), `generateMonthlyFinancials` (monthly).

**Cost impact:**
| Metric | Before (Lambda) | After (Antigravity) |
|--------|-----------------|---------------------|
| Cost per nightly retrain | $0.87 | $0.22 — **75% savings** |
| Ops overhead | CloudWatch rule + alarms | Native cron UI — simpler |

**Effort:** S (2 wk, 1 FTE)

## Opportunity E — Native Android App Generation

**What it replaces:** Hand-written Kotlin Android app (4GB, currently 6 months behind iOS in features).

**Prompt:**
> "Generate Android app with parity to iOS EusoTrip. Features: driver lifecycle (dock backing with NI precision, hazmat hose verification), convoy formation, HOS tracking, Canopy insurance integration, FMCSA compliance. Target Android 12+. Use Jetpack Compose. Languages: Spanish, Portuguese, French. Permissions: location, camera, microphone."

**CLI:** `antigravity app generate --platform=android --prompt=...` outputs production-ready Android Studio project. **4-6 weeks to production vs. 16 weeks hand-written.**

**Phases:**
- Wk 1: Write canonical multi-modal app prompt (feature list, UX guidelines, compliance constraints). Test prompt against iOS Antigravity generation (validate structurally identical Swift output).
- Wk 2-3: Generate Android from same prompt. Manually integrate MX/CA region features (TDG instead of Hazmat, Carta Porte compliance). Internal test with 50 Mexican drivers (fleet partner).
- Wk 4-6: Push to Google Play (internal track). Measure feature parity vs. iOS; fix gaps. GA in Mexico market.
- Wk 7-12: Generate variants for Canada (French + English, TDG), Brazil (Portuguese), Colombia (Spanish). Each market: 2 wk (prompt tuning + local compliance).

**Cost impact:**
| Metric | Before (Hand-written) | After (Generated) |
|--------|----------------------|-------------------|
| Time to Android release | 16 wk | 6 wk — 63% faster |
| Android dev headcount | 2 FTE | 0.5 FTE (mostly testing) |
| Feature parity lag (iOS → Android) | 6 months | 1-2 wk |

**Effort:** M (6 wk, 2 FTE — 1 senior, 1 QA)

## Opportunity F — Hardened Git Policies

**What it replaces:** Manual GitHub branch protection + occasional leaked keys in commit history.

**After Antigravity CLI:**
- Both repos pull credential injection from CLI vault (Secrets Manager)
- Every commit signed by CLI-issued ephemeral key (rotated per developer per session)
- CI/CD validates signature before building
- Reproducible builds: commit SHA → deterministic build artifact
- Merkle-chain builds: each build signed, previous SHA referenced

**Phases:**
- Wk 1: Install CLI everywhere. Migrate credential handling: replace hardcoded API keys with CLI secret injection. Generate ephemeral dev-signing keys (1-week TTL).
- Wk 2-3: Enforce signed commits on `main` + `develop`. Dev commits locally, signs via CLI, GitHub checks signature before merge. CI verifies before tests.
- Wk 4-6: Audit history for leaked secrets (CLI scanning tool). Rotate exposed keys. Audit logging: every credential access to Cortex audit drawer (S3 WORM).
- Wk 7+: Reproducible builds. Merkle-chain builds.

**Cost impact:**
| Metric | Before | After |
|--------|--------|-------|
| Time to detect leaked credential | 2-4 wk (manual scan) | <1 min (auto) |
| Dev onboarding (cred setup) | 1 hr | 5 min (CLI wizard) |
| Compliance audit (cred rotation) | Manual spreadsheet | Automated Cortex log |

**Effort:** M (4 wk, 1.5 FTE — 1 security, 0.5 DevOps)

---

## Porting Sequence — 52-agent migration (48-week critical path)

| Phase | Agents | Layer | Weeks | Blocker clearance |
|-------|--------|-------|-------|-------------------|
| 1 | 8 | SENSORY (geofence, NI-ranging, ELD, voice, map, video, sensor, state) | 1-4 | Feature flag validation, NI device capability probe |
| 2 | 12 | DISPATCH (convoy, load-match, rate, carrier-select, escort, dock-assign, etc.) | 5-8 | Convoy multi-peer formation <4s |
| 3 | 14 | COMPLIANCE (hazmat, insurance, fmcsa, dot, tdg-ca, certification, hos-audit, etc.) | 9-12 | Hazmat hose-valve 30cm confidence >99% |
| 4 | 6 | FINANCIAL (commission, wallet, settle, factoring, currency, billing) | 13-16 | Settlement idempotency + advisory lock proof |
| 5 | 8 | STRATEGIC (market-intel, rate-card, shipper-profile, carrier-profile, lane-analytics, etc.) | 17-20 | Rate-card consistency across all vehicles |
| 6 | 4 | GUARDIAN (fraud-detect, sos-route, av-takeover, crash-predict) | 21-24 | Fraud FPR <0.5%, AV takeover <500ms |
| 7 | — | STABILIZE + OPTIMIZE | 25-48 | Remove feature flags; retire legacy; cost reductions |

## Parallel work streams (compress schedule)

| Stream | Opp | Weeks | Integration point |
|--------|-----|-------|-------------------|
| A | Opp A (Managed Agents — 6 phases) | 1-24 (critical path) | Primary path |
| B | Opp B (CLI dev pipeline) | 1-4 | Wk 5 (dispatch skill deploy) |
| C | Opp D (Cron workflows) | 5-7 | Wk 8 (rate-card model retraining) |
| D | Opp E (Android generation) | 16-22 | Wk 24 (MX market GA) |
| E | Opp F (Hardened Git) | 1-4 | Wk 5 (enforce on all repos) |

**Merged timeline:** 48 weeks end-to-end. Streams B–E complete by Wk 22 and run parallel with Stream A Phases 5-6.

---

## Summary

| # | Antigravity feature | EusoTrip system | Effort | Cost savings | Timeline |
|---|---------------------|-----------------|:------:|--------------|----------|
| A | Managed Agents | 52-agent Zenith Cortex | L | 67% API cost cut | 16 wk |
| B | CLI Dev Pipeline | Skill deployment | M | 82% deploy faster | 4 wk |
| C | Subagent Chains | Monolithic agents | M | 44% latency cut | 4 wk |
| D | Cron Workflows | Lambda + CloudWatch | S | 75% compute cost | 2 wk |
| E | Android Generation | Hand-written Kotlin | M | 63% dev time cut | 6 wk |
| F | Hardened Git | Manual credentials | M | Security + velocity | 4 wk |

**Total effort:** ~38 FTE-weeks (~12-16 engineers for 12 wk, or 6-8 engineers for 24 wk)
**Total annual savings:** ~$180K (API + dev velocity) + security gains
**Risk:** Medium (feature flag rollback for phases 1-6; subagent timeout tuning; Android testing matrix)
