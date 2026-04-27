# 92 · Launch Runbook + Rollback + Crisis Playbook

**What this covers.** The thirty-day launch arc (T-14 through T+30), pre-launch checklist gates, soft freeze, App Review submission, launch-day phased-release protocol, monitoring stack, latency + crash-free SLOs, key business-health metrics, rollback triggers, three-layer rollback procedure (remote config kill switches, backend swap, App Store hotfix), feature flag system, incident response, Sev definitions, comms templates, status page, support channels, post-launch regressions to watch in first 30 days, 30-day retro, release cadence, hotfix cadence, on-call schedule, exact commands for health checks. Source: wave-1 shard `team_LAUNCH_runbook`.

**When you need this.** Before every launch. Before every Sev-1. Before every rollback. Before every hotfix. During every incident. Reviewed verbatim by release captain before every release. Reviewed verbatim by on-call during every Sev-1.

**Cross-links.** Engineering principles (TDD + E2E as pre-launch discipline): [02_Engineering_Principles.md](./02_Engineering_Principles.md). Web parity (cross-platform test must pass before ship): [91_Web_Mobile_Parity.md §10](./91_Web_Mobile_Parity.md). Phased release doctrine: [90_App_Store_Strategy.md §14](./90_App_Store_Strategy.md).

---

## 0. Preamble — launch is a discipline, not an event

Launch is not a day. Launch is a **thirty-day arc** beginning fourteen days before binary hits App Review and ending thirty days after first user downloads.

Failure mode we are defending against: not a bad build, but a good build shipped into unmonitored environment, at wrong percentage, with no rollback plan, and a team that does not know who holds the pager.

EusoTrip ships a safety-critical app. Drivers depend on HOS changes being accurate. Carriers depend on wallet balances rendering correctly. Dispatchers depend on load accepts propagating to back-office. **A bug we would consider cosmetic in a consumer social app becomes a regulatory incident in trucking.** This runbook treats every launch as if human safety event is one silent crash away, because it is.

Opinionated. Follow it. If you deviate, document why in release notes and get sign-off from on-call lead.

---

## 1. Pre-launch checklist (T-14 days)

Fourteen days before submission, all gates must be green. Red → launch slips. No exceptions, no heroics.

### Code gates
- All driver 010–099 bricks shipped, tagged, merged to `release/1.0`.
- Every procedure in registry mapped to owning brick, green smoke test in last 48 hours.
- **No `TODO`, no `FIXME`, no `HACK`, no `console.log`** in code paths touched in last 30 days.
- Swift warnings count is zero. Deprecation warnings resolved or explicitly suppressed with justification.

### Backend gates
- Deploy success rate >99.9% over trailing 7 days (Azure App Service slots, measured in deploy telemetry dashboard).
- Zero Sev-1 or Sev-2 backend incidents in trailing 14 days.
- Database migrations idempotent, reversible, dry-run against staging copy of production.

### Mobile gates
- Zero critical crashes in TestFlight for trailing 3 days across ≥50 external testers on iOS 17 and iOS 18.
- Cold launch p95 on real devices (iPhone 12+) under 2.5 seconds.
- Watch pairing success rate measured internally above 98%.

### Store gates
- Listing drafts ready: title, subtitle, 30-char keywords, 170-char promo text, long description, category, age rating.
- Screenshots captured for every required device class (6.7", 6.5", 5.5", 12.9" iPad if applicable).
- App Preview video cut + under 30 seconds.
- Support URL, marketing URL, privacy policy URL all return 200 + render legible content.

### Legal gates
- Legal review signed off by counsel on ToS, Privacy Policy, driver-specific disclosures, factoring disclosures.
- Terms + privacy URLs live on production (`eusotrip.com/terms, /privacy`) + match in-app copy exactly.
- DPA on file for every subprocessor touching driver PII.

T-14 passes → cleared to enter soft-freeze at T-7.

---

## 2. T-7 days — soft freeze

Seven days before submission, codebase enters soft freeze. Rules:

- No new features. Any new feature PR auto-closed with label `post-launch`.
- Bug fixes only — and only bug fixes resolving crashes, data loss, or regressions introduced in release window.
- Every merge to `release/1.0` requires two reviewer approvals, one of whom must be release captain.
- Regression sweep runs every 12 hours via CI against full integration suite.

**Final QA matrix**: Every role × every country × every mode.
- Roles: driver, carrier, dispatcher, factor, broker, shipper, admin.
- Countries: US, Canada, Mexico (cross-border loads must exercise customs filing paths).
- Modes: online, offline, degraded network (3G simulation), airplane mode recovery, low-power mode, Dynamic Island active, background audio active, CarPlay active.

**Matrix**: 7 × 3 × 8 = 168 test passes. Automate what's automatable. Manually execute rest on physical device. Sign off with checklist stored in `qa/release-1.0-matrix.md`.

---

## 3. T-3 days — submit to App Review

Three days before target launch, submit to Apple. Expected turnaround 24–48 hours; plan for 72.

- Submit with phased release enabled but staged rollout OFF until post-approval.
- Include reviewer-facing demo account with credentials for every role. Document demo flow in submission notes.
- Pre-declare sensitive capabilities: Location Always, Background Modes, HealthKit (if used for HOS), Network Extensions.
- If rejected, have rejection triage doc ready. Most rejections are metadata, not code; respond within 4 hours with clarification or resubmission.

---

## 4. Launch day protocol — phased release

Apple's phased release ships binary to increasing % over 7 days. We enforce more conservative ramp on top using feature flags gated on build version.

- Hour 0: release to 1% of users. All eyes on dashboards.
- Hour 4 (if green): 10%.
- Hour 24 (if green): 50%.
- Hour 72 (if green): 100%.

"Green" = crash-free-users above 99.5%, no Sev-1 incidents, no rollback triggers fired, manual spot-checks of wallet + HOS + load accept flows pass.

If any metric yellow (degrading but not breaching), **hold at current %** and investigate. Do not advance to "catch up." **Time is cheap. Data integrity is not.**

---

## 5. Monitoring stack during launch

Launch dashboard is single source of truth during ramp. Aggregates:

- **App Store Connect crash reports**: refresh every 15 min for first 72 hours. Apple lags real-time by ~6–12 hours; trailing indicator.
- **MetricKit payloads posted to telemetry router**: leading indicator. Every device posts daily MetricKit diagnostics to `telemetry.eusotrip.com/mk`. During launch drop cadence to hourly for first week via remote config.
- **Sentry or Crashlytics**: real-time crash grouping, session tracking, release health. Alert rules for any new crash group with >5 users in 10 minutes.
- **Custom OrbTelemetry events on critical surfaces**: orb tap, wallet render, load accept, HOS change, SOS activation, watch pair. Each emits structured event with build version, user role, country, success/failure. Aggregated in Grafana.
- **Backend observability**: Azure App Service logs (Application Insights), MySQL slow-query log (threshold 200ms), APNs delivery rate tracked via `apns_receipts` table joined against `notifications_sent`.

War room during launch has all five dashboards on screen. One engineer owns each pane.

---

## 6. Latency SLOs

Service Level Objectives. Breaches fire pages.

- **Cold launch**: <2.5s at p95, via MetricKit `applicationLaunchTime`.
- **Screen transition**: <100ms at p95, via custom OrbTelemetry `nav.transition.ms`.
- **API call**: p50 <400ms, p95 <1.2s, p99 <3s. Backend access logs + cross-verified with client-side `api.roundtrip.ms`.
- **Push delivery**: <5s at p95 from APNs send to client receive ack.
- **Watch orb tap to listening state**: <250ms at p95. Tightest SLO + most sensitive to regressions.

Any p95 breach sustained >30 min is Sev-2. Sustained p99 breaches are Sev-3 unless correlated with user-facing failures.

---

## 7. Crash-free-users SLO

**Crash-free-users above 99.5% rolling 24-hour window.** Single most important health metric during launch. Drop below 99% is rollback trigger (§9).

Measured per Sentry/Crashlytics: user is "crash-free" in window if no session ended in unhandled crash. Background crashes count. Watch extension crashes count against paired iPhone user.

---

## 8. Key metrics to watch

Business-health metrics. Latency + crash rate tell us if app runs. These tell us if app works.

- DAU / WAU / MAU segmented per role (driver, carrier, dispatcher, factor, broker, shipper).
- **Load accept rate**: offered-to-accepted ratio within expected window. Baseline before launch, alert on 20% deviation.
- **Wallet balance render success rate**: % of wallet opens rendering numeric balance within 2 seconds. Target above 99.8%.
- **HOS change success rate**: % of HOS duty status changes committing to ELD backend + returning confirmation within 10 seconds. Target above 99.9%. **Regulatory; failures serious.**
- **SOS button activations**: we hope zero. Every activation logged with full context + human follow-up within 15 minutes.
- **Watch pairing success rate**: % of pair attempts completing within 60 seconds. Target above 97%.

---

## 9. Rollback triggers

**Any one firing initiates rollback procedure (§10).** Not debatable in the moment. Trigger fires, rollback begins, debate afterward.

- Crash-free-users drops below 99% in rolling 1-hour window.
- Wallet or payment procedure error rate >0.5%.
- HOS change failure rate >1%.
- SOS or emergency flow broken (any end-to-end test failure or user report).
- Hazmat placarding missing for hazmat loads (compliance test suite red).
- Cross-border compliance gate fails (customs filing rejected or missing fields).

**Any trigger is a Sev-1 by definition.**

---

## 10. Rollback procedure

iOS rollback is not instantaneous. Cannot pull a version off App Store in under minutes. Plan operates at **three layers**:

### Layer 1 — Remote config kill switches (seconds)
- Force-show older tested flows via `profile.flags.use_legacy_wallet, use_legacy_hos`, etc.
- Disable risky new features via `feature.disabled.<brickId>`.
- All OrbTelemetry surfaces check these flags on launch + per-screen render.
- **First line of defense.** Every risky new surface must ship with a flag.

### Layer 2 — Backend rollback (3–7 minutes)
- Azure App Service slot swap: previous production slot kept warm. Swap back via Azure CLI:
  ```
  az webapp deployment slot swap --resource-group eusotrip-prod --name eusotrip-api --slot staging --target-slot production
  ```
  (reversing direction swapped at deploy).
- Git revert release commit on `main`, push, tag as `rollback-<date>`.
- Re-run database migrations only if reversible + rollback requires it; otherwise leave schema forward-compatible.
- Expected total: 3–7 minutes from decision to traffic on old code.

### Layer 3 — Mobile binary (hours to days)
- If App Store binary itself is problem + cannot be remediated by flags, submit hotfix with expedited review request. Expedited review typically 4–12 hours but not guaranteed.
- Apple's Expedited Review form: cite user impact in specific terms (number of users affected, nature of break). **Do not cry wolf**; we get maybe 2–3 expedited approvals a year before Apple starts declining.

### Watch rollback
- iOS companion ships watch binary as bundled resource. Watch rollback follows iOS rollback automatically; no independent watch ship vehicle.
- If watch-specific code is problem, disable watch pairing via remote config `watch.pairing.enabled = false` until hotfix lands.

---

## 11. Feature flag system recommendation

If team has no feature flag system, adopt one before launch. Priority order:

- **LaunchDarkly**: industry standard, expensive, rock-solid SDK. Recommended if budget allows.
- **Flagsmith**: open-source, self-hostable, good enough for our scale.
- **Rolling own**: simple `profile.flags` key per user, served by backend on session start, cached for session. Acceptable for launch, replaceable later. Ship with rules: flags are strings mapping to booleans or small strings, default to off, flag fetch failure means off, flags logged to OrbTelemetry on every consumption.

Whichever picked, **every risky brick ships with kill switch. No exceptions.** A brick that cannot be disabled remotely is not launch-ready.

---

## 12. Incident response

Severity definitions + response:

### Sev-1: app down for >5% of users, or any §9 rollback trigger fires
- Page on-call primary + secondary immediately.
- Open war room (Zoom + dedicated Slack channel `#incident-YYYYMMDD-HHMM`).
- Customer ETA update every 30 min via status page + in-app banner + email to affected users.
- Postmortem draft within 48 hours, blameless, published internally.
- Executive summary to CEO within 24 hours.

### Sev-2: one role broken, or non-critical feature unusable for >10% of its users
- Same-day fix committed.
- Customer comms within 2 hours via in-app banner + status page.
- Postmortem optional but encouraged for pattern recognition.

### Sev-3: minor UI bugs, cosmetic issues, small performance regressions not breaching SLOs
- Queue for next release.
- No customer comms required unless bug visible enough to generate support tickets.

---

## 13. Comms templates

Pre-written, approved by legal + CEO, stored in `/runbooks/comms-templates/`.

### Customer email (Sev-1)
```
Subject: EusoTrip service disruption - we're on it

Hi [Name], we're aware of an issue affecting [describe]. Our team is
actively working on it. Current ETA to resolution: [time]. We'll update
you every 30 minutes at status.eusotrip.com. If your situation is
safety-critical, please call [phone]. We're sorry for the disruption.
- EusoTrip Team
```

### In-app banner (Sev-1)
```
We're experiencing issues with [feature]. Working on it. Updates at
status.eusotrip.com.
```

### Twitter/X update
```
We're aware of an issue affecting [feature] and working on a fix.
Updates at status.eusotrip.com. Thanks for your patience.
```

All three ship with release. During incident you fill in blanks, you do not rewrite from scratch.

---

## 14. Status page

Recommended: `status.eusotrip.com` hosted on Statuspage.io (Atlassian) or AtlasStatus. Must be:
- Hosted on infrastructure independent of primary stack (stays up when we go down).
- Updated in real time during incidents, not after.
- Componentized: Mobile App, Backend API, Push Delivery, Wallet, HOS, Watch — each independent status.
- Subscribable via email + SMS.

**Status page not updated during incidents is worse than no status page.** Assign on-call "comms lead" whose only job during Sev-1 is updating status page every 30 minutes.

---

## 15. Support channels

- **In-app help router**: contextual help based on current screen, routing to knowledge base article or human agent.
- **Email**: support@eusotrip.com, staffed during business hours, SLA 4 hours first response.
- **Phone line for drivers**: staffed 24/7. Drivers on road cannot wait for email. Number printed on driver onboarding material + accessible from Profile tab + SOS flow.

During launch week, add "We just launched - thanks for your patience" autoresponder that does not extend SLA but sets expectations.

---

## 16. Post-launch regressions to watch (first 30 days)

Based on structural risk map, surfaces most likely to regress:

- **Auth persistence**: users getting logged out unexpectedly. Root cause usually keychain access group misconfiguration or token refresh race conditions.
- **Watch pairing**: handoff between iPhone + Watch is fragile; iOS updates can break.
- **Push delivery**: APNs token rotation on fresh installs, silent push for background sync.
- **Factoring payout**: wallet balance race conditions when payout lands mid-session.
- **HOS edge cases**: 8/2 split berth rule is most commonly mis-implemented. Also watch for DST transitions + timezone changes while driving.
- **Cross-border customs filings**: ACE/ACI field changes happen quarterly; ensure our field map is current.

---

## 17. 30-day retro template

At day 30, convene full team. Template:

1. **What shipped**: every brick live, with dates + authors.
2. **What broke**: every incident, Sev-1 through Sev-3, with root cause + resolution time.
3. **What we learned**: three to five bullets of institutional knowledge. Add to doctrine.
4. **What's next**: top three priorities for next 30 days, owned by named engineers.

Retro doc in `/retros/1.0-launch-day30.md`, reviewed by every future release captain before their release.

---

## 18. Release cadence post-launch

**Every 2 weeks (bi-weekly).** Cadence discipline is more important than feature velocity. Predictable bi-weekly release:
- Forces team to cut scope rather than slip dates.
- Builds user trust: drivers learn when to expect updates.
- Limits blast radius: smaller releases, smaller incidents.

Release train leaves on schedule. Features missing train wait for next one.

---

## 19. Hotfix cadence

- **Sev-1**: hotfix within 4 hours. Remote config first, backend deploy second, expedited App Review as last resort.
- **Sev-2**: hotfix within 24 hours. Normal release cadence unless user impact widespread.
- **Sev-3**: next scheduled release.

Hotfix is not license to skip CI or code review. **Two reviewers minimum, full test suite green, no exceptions.** "We're in a hurry" is how rollbacks become double rollbacks.

---

## 20. On-call schedule

First 30 days post-launch: **24/7 coverage with primary + secondary on-call**.

- Primary responds within 5 minutes to page, acknowledges incident, initiates war room if Sev-1.
- Secondary is backup: if primary doesn't ack within 10 minutes, page escalates.
- Rotation is one week at a time, handed off every Monday at 10am local.

After day 30: business hours coverage (7am–10pm local) with paging for Sev-1 outside hours. Primary still first responder but response SLA relaxes to 15 minutes.

**On-call compensation**: time-and-a-half for weekend coverage, full day off post-rotation. **Burning out on-call rotation is how good teams turn into angry ex-teams.**

---

## 21. Runbook — exact commands

Health checks executed by on-call during incidents. First thing run, before any theorizing.

**Backend health:**
```
curl -sS https://api.eusotrip.com/health | jq .
curl -sS https://api.eusotrip.com/health/deep | jq .
```
Expected: `{"status":"ok","db":"ok","redis":"ok","apns":"ok"}`.

**MySQL connections:**
```
mysql -h prod-db.eusotrip.internal -u ops -p -e "SHOW STATUS LIKE 'Threads_connected'; SHOW STATUS LIKE 'Max_used_connections'; SHOW PROCESSLIST;"
```
Watch for thread count approaching `max_connections`. Kill long-running queries with `KILL <id>`.

**MySQL slow queries:**
```
mysql -h prod-db.eusotrip.internal -u ops -p -e "SELECT * FROM mysql.slow_log ORDER BY start_time DESC LIMIT 20;"
```

**APNs queue depth:**
```
redis-cli -h prod-redis.eusotrip.internal LLEN apns:queue
redis-cli -h prod-redis.eusotrip.internal LLEN apns:queue:dlq
```
Queue depth above 10,000 or DLQ above 100 is red flag.

**Azure App Service CPU/memory:**
```
az monitor metrics list --resource /subscriptions/<sub>/resourceGroups/eusotrip-prod/providers/Microsoft.Web/sites/eusotrip-api --metric "CpuPercentage,MemoryPercentage" --interval PT1M
```

**Azure App Service recent logs:**
```
az webapp log tail --name eusotrip-api --resource-group eusotrip-prod
```

**Azure slot swap (rollback):**
```
az webapp deployment slot swap --resource-group eusotrip-prod --name eusotrip-api --slot staging --target-slot production
```

**Force remote config refresh on a user:**
```
curl -X POST https://api.eusotrip.com/internal/flags/refresh -H "Authorization: Bearer $OPS_TOKEN" -d '{"userId":"<id>"}'
```

**Pull crash group from Sentry:**
```
curl -sS -H "Authorization: Bearer $SENTRY_TOKEN" "https://sentry.io/api/0/projects/eusotrip/mobile/issues/?query=is:unresolved&statsPeriod=24h&sort=freq" | jq '.[0:10] | .[] | {title,count,userCount}'
```

Every on-call engineer memorizes first three. Rest live in `/runbooks/commands.md`, copy-pasted during incidents.

---

## Closing — the discipline

A launch runbook is not a document you read once. It is a discipline you rehearse. Before every release, release captain walks team through this runbook verbatim. Before every Sev-1, on-call reads §10 and §12 out loud. Before every retro, team re-reads §17.

Discipline compounds. A team that runs this runbook once a quarter becomes a team that does not have Sev-1s, because the muscles are built. **The goal is not to be ready for the crisis. The goal is to be the kind of team that does not have the crisis in the first place.**

Ship well. Ship on purpose. Ship with the rollback plan already written.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
