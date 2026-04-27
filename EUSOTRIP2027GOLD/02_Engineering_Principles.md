# 02 · Engineering Principles

**What this covers.** The non-negotiable engineering doctrine for EusoTrip — TDD red-green-refactor on every feature, E2E testing built into every plan, no fancy plugins, no runtime MCPs, foundational principles of software engineering applied to an app whose failures hurt real drivers. Includes `dj_teknal`'s principles applied verbatim to EusoTrip and a new section applying the Recursive Language Model paper to our code review, doctrine maintenance, and incident response workflows.

**When you need this.** Before every commit. Before every PR review. Before every incident postmortem. Before every argument about shipping something "quickly." Read sections 1, 2, 3, 17, 18 once a quarter minimum.

---

## 1. Why TDD + E2E Is THE Engineering Principle for EusoTrip

Every engineering doctrine has a center of gravity — the one principle everything else orbits. For EusoTrip, that center is not architectural taste, not language preference, not tooling fashion. It is a single, non-negotiable commitment: **nothing can break in the hands of a driver, a dispatcher, or a carrier owner.**

EusoTrip is not a social app. It is not a content platform. It is not a novelty. EusoTrip is the operational spine for freight movement — and the surfaces it touches are surfaces where failure has material, human, legal, and financial consequences.

Consider what the app is actually responsible for:

- **Money.** Factoring advances, settlement math, fuel surcharges, accessorial charges, per-mile rates, detention billing. A rounding error is not an inconvenience — it is a theft or a loss, and either way it is a breach of trust that takes years to rebuild.
- **Hours of Service (HOS) compliance.** An HOS log that drops a duty-status change or miscalculates the 14-hour clock is not a bug — it is a federal violation under 49 CFR Part 395. A single bad log can trigger a DOT audit, fines, and out-of-service orders.
- **Hazmat safety.** When the app is handling a hazmat placard scan, a BOL with UN numbers, or a driver signoff for a Class 3 flammable, a crash or a silent failure can contribute to a real-world incident — spills, fires, injuries, environmental damage.
- **Driver livelihoods.** A driver who loses a load because the accept-flow crashed, or who misses a pickup window because the notification never fired, loses income. That income pays rent. That rent feeds a family. We are not shipping pixels; we are shipping the thin layer between a professional driver and their paycheck.

Given those stakes, "move fast and break things" is disqualified. The correct philosophy is the one `dj_teknal` articulated (see §3): **red-green-refactor TDD on every feature, end-to-end tests baked into every plan, no fancy tooling, no MCP runtime dependencies, just foundational principles of software engineering executed with discipline.**

This section is the operationalization of that commitment. It is not aspirational. Every PR, every release candidate, and every incident postmortem will be measured against it.

---

## 2. TDD — Red / Green / Refactor for every feature

### 2.1 RED — Write the failing test first

Before a single line of production code, the engineer writes a test that fails for the right reason — not because of a typo, not because of a missing import, but because the behavior it asserts does not yet exist.

On iOS:
- **XCTest** (or Swift Testing where migrated) for view-models, stores, reducers, pure-function business rules, API response decoders.
- Mirror-style test targets — `Features/Loads/LoadAcceptViewModel.swift` has a sibling `Features/Loads/LoadAcceptViewModelTests.swift`.
- Every new public method on a view-model begins life as a failing test.

On TypeScript backend:
- **Vitest** (preferred) or **Jest**.
- Every new tRPC procedure, every new Zod schema, every new service function begins with a failing test.

**RED is the step most engineers skip under pressure. The doctrine forbids skipping it.** Retrofitted testing is a weaker artifact and produces weaker code.

### 2.2 GREEN — Minimum code to pass

Simplest possible code. Not prettiest. Not most extensible. Not most clever. Simplest.

This is deliberately uncomfortable. Premature abstraction is the most expensive abstraction. Simple code that passes the test is honest code. GREEN proves the test harness works, the production path wires up, and the expected output is producible.

### 2.3 REFACTOR — Clean up while staying GREEN

Extract a function, rename a variable, collapse a duplicated branch, pull a protocol out of a concrete type. **The test suite runs continuously.** Any red light is a stop-the-line — revert and retry.

REFACTOR is where engineering craft lives. Skipping it leaves the codebase naive and accumulates debt per commit.

### 2.4 Where TDD applies

- Every new view-model — RemoteState transitions, input-event handling, error paths.
- Every store — initial state, mutations, cache invalidation, subscription behavior.
- Every API wrapper — stubbed URLProtocol or mocked transport, request shape, response decoding, error mapping.
- Every business rule — HOS clock math, settlement calculations, accessorial logic, eligibility predicates, routing guards. Densest test coverage.

Not rigidly applied to pure layout/SwiftUI view composition — covered by snapshot + E2E instead. When in doubt, write the test first.

---

## 3. dj_teknal's Principles Applied to EusoTrip

From the Threads post that triggered this doctrine revision:

> **Question:** "VIBE CODERS, what did you do to your tech stack that upgraded you 100%? Please list it point by point."
>
> **Response (dj_teknal, 3h):** "Not exactly a vibe coder since I've been coding for 13 years and I check/review/manually test all my changes, but: enforcing TDD with red-green-refactor. E2E testing built into all planning for every feature. No fancy skills, plugins, or MCPs. Just solid, foundational principles of software engineering to ensure nothing breaks."

Quoted verbatim. Load-bearing. The EusoTrip application of each clause:

### 3.1 "I've been coding for 13 years and I check/review/manually test all my changes"

Thirteen years of production software experience beats thirteen AI rewrites. Every change to the EusoTrip codebase is **deliberately reviewed, tested, and manually verified.** AI assistants are accelerators — autocomplete, scaffolding, rubber-ducking, refactoring suggestions — but we do not ship code the author cannot explain, cannot test, and cannot defend in review. Vibe coding is disqualified.

### 3.2 "Enforcing TDD with red-green-refactor"

See §2. No exceptions. Every PR carries a RED test alongside the GREEN code. Reviewers reject PRs missing the failing-then-passing pair.

### 3.3 "E2E testing built into all planning for every feature"

See §4. Every feature plan, before implementation starts, includes its E2E test plan. No feature plan without an E2E plan.

### 3.4 "No fancy skills, plugins, or MCPs"

See §5 and §6. SwiftLint minimal. Dependencies justified in PR body. Standard library first. No vendor lock-in. No MCPs in the app runtime.

### 3.5 "Just solid, foundational principles of software engineering to ensure nothing breaks"

See §7. SOLID for Swift types. SRP on view-models. Dependency inversion. Fail-fast error handling. Pure functions. Immutable by default. These aren't fashionable; they work.

### 3.6 Concrete EusoTrip rules derived from dj_teknal

1. **RED test attached to every PR that changes behavior.** CI checks for a new failing test in the diff and then a passing test in the same diff. Missing either fails the build.
2. **E2E plan in every design doc.** A design doc without an "E2E scenarios" section is returned to the author.
3. **No `try?` in production code.** Errors surface to the view-model. Silent swallows are reviewed out.
4. **No god-objects.** `EusoTripAPI.shared` is the one documented exception (§7.4). New singletons require doctrine-level review.
5. **No new dependency without a written rationale.** "It saves me 400 lines of code that would be ours to maintain" is acceptable. "It's popular" is not.
6. **No MCPs at runtime.** MCPs are dev-time and build-time. If removing the MCP would break a production user flow, the MCP is in the wrong place.
7. **Every PR carries a screenshot diff for UI changes.** Light + dark, Dynamic Type above default, on at least one device size.
8. **Every incident produces a test.** The test is the contract that the incident does not silently recur.

---

## 4. E2E testing built into every plan

### 4.1 iOS E2E via XCUITest

Critical flows with E2E coverage (must retain):

- **Login** — credential entry, MFA challenge, session establishment, token refresh, logout.
- **Accept load** — inbox receipt, load detail review, accept tap, backend confirmation, state transition to booked.
- **Log HOS change** — On-Duty → Driving → Off-Duty → Sleeper transitions, clock validation, persistence across app relaunch.
- **Sign BOL** — pickup + delivery signature capture, image persistence, upload retry on network failure.
- **Submit DVIR** — pre-trip inspection, defect reporting, signature, submission confirmation.
- **Pair watch** — Apple Watch pairing, complication installation, WatchConnectivity handshake, HOS mirror.
- **Voice-command offline** — offline voice capture, local queueing, background sync on reconnect.

### 4.2 Backend E2E via supertest + real DB fixtures

- Real Postgres (test schema, transactional rollback per test).
- Known fixtures: carrier, driver, shipper, load in known state.
- Procedure executed with realistic inputs.
- Assertions: response shape, DB side-effects, emitted telemetry events.

Mocked databases are banned for procedure tests. The point of E2E is actually hitting the real dependency graph.

### 4.3 Cross-platform E2E — the one that must always pass

**web-create-load → iOS-driver-accept → iOS-driver-deliver → web-confirm**

If this test breaks, the release does not ship. Period.

---

## 5. No "fancy plugins" rule

- **SwiftLint / SwiftFormat minimal.** Force-unwraps in prod, trailing whitespace, brace style. A 400-rule configuration that produces >5:1 noise-to-signal ratios is banned.
- **Dependency tree stays slim.** Every Swift Package, npm dependency, or Pod needs a written rationale in the PR.
- **Prefer the standard library.** Foundation, Swift Concurrency, URLSession, Combine.
- **No vendor-lock frameworks.** Extraordinary scrutiny on anything that couples us to a vendor, runtime, or proprietary build.

Clean clone build under 2 minutes. Readable Package.swift. Boring upgrade paths.

---

## 6. No MCPs at app runtime

MCPs are development-time and build-time aids. **They are not shipped in the app.**

- The `eusorone-web-apps` MCP accelerates internal development workflows (dev-time).
- We do not link, embed, proxy, or runtime-invoke MCPs from the EusoTrip iOS binary or production backend paths.

If removing the MCP would break a production user flow, the MCP is in the wrong place. MCPs are scaffolding, not structure.

---

## 7. Foundational principles (explicit)

### 7.1 SOLID for Swift types

- **Single Responsibility** — every type has one reason to change.
- **Open/Closed** — types open for extension via protocols, closed for modification.
- **Liskov Substitution** — protocol conformances honor contract including semantics, not just signature.
- **Interface Segregation** — five small protocols over one fat one.
- **Dependency Inversion** — high-level modules depend on abstractions.

### 7.2 Single Responsibility per view-model

Each view-model owns one screen's state and one screen's intent-to-action mapping. Reaching into two unrelated stores + coordinating three network calls + formatting strings = too much. Split.

### 7.3 Dependency Inversion — pass in dependencies

View-models, services, business-rule modules take dependencies as constructor parameters or environment injection. They do not reach into `SomeSingleton.shared` from methods. That's what makes them testable, mockable, and keeps the dependency graph visible.

### 7.4 No god-objects — `EusoTripAPI.shared` is the documented exception

`EusoTripAPI.shared` is a singleton because there is exactly one backend. Surface-narrow (every method explicit), no dynamic dispatch catch-alls, the only singleton crossing feature boundaries. A second god-object requires doctrine-level review.

### 7.5 Fail-fast error handling

`try?` is a smell, flagged in review. Errors propagate to view-model, mapped into `RemoteState.error(UserFacingError)`, rendered with clear message + clear next step. Silent failure > crash for freight: crash gets investigated; silent failure has a driver standing at a dock wondering why nothing is happening.

### 7.6 Pure functions for business logic

HOS math, settlement math, eligibility rules, routing guards — expressed as `(inputs) -> output` with no side effects. Pure functions compose, reuse, and survive refactors.

### 7.7 Immutable where possible — `struct` > `class` unless identity matters

Value types are the default. Reference types when identity matters (live URLSession, actor mediating resource access, ObservableObject where reference semantics are framework-intrinsic).

---

## 8. Code-review ritual

Every PR includes:

- **(a) A failing test** demonstrating the bug or behavior.
- **(b) A passing test** proving the fix or implementation.
- **(c) A screenshot diff** for UI changes — before + after, both registers, Dynamic Type above default.
- **(d) An architecture note** for public API changes — motivation, compat implications, migration path.

Missing any → PR returned. Not pedantry — minimum evidence to responsibly merge into a codebase drivers depend on.

---

## 9. Regression fence — MockDataGuard

Runtime canary in DEBUG builds scans critical rendering paths for a forbidden-literal list: `PACCO`, `TRP-4492`, `Marcus Reyes`, etc. Any detection crashes the build with diagnostic stack trace pointing at the offender. Version-controlled, grows whenever a new regression-worthy literal is identified.

DEBUG-only by design: we don't want the canary crashing real users; we want it crashing engineers before the RC is cut.

---

## 10. Feature-flag policy

Every new feature touching money, HOS, hazmat, or driver-load-completion ships behind a runtime flag, default **OFF**.

- Server-side evaluation when possible, client-side fallback.
- Default state for new flag is off.
- Rollouts: internal → opt-in carriers → percentage rollout → GA.
- Flags retired after GA + two full release cycles of stability. Dead flags are tech debt.

Ship risk without shipping incidents.

---

## 11. Observability

- **OSLog signposts** mark critical paths: accept-load, sign-BOL, HOS-transition, voice-command-capture, settlement-calc.
- **MetricKit** collects crashes, hangs, disk writes, CPU burns, launch times. Ingested into backend telemetry, triaged weekly.
- **Backend telemetry router** captures state transitions, API errors, retry exhaustion. Sliced by carrier, driver, app version, OS version.

---

## 12. Latency budgets

See [03_Backend_API_Contract.md §8](./03_Backend_API_Contract.md) and [92_Launch_Runbook_and_Rollback.md §6](./92_Launch_Runbook_and_Rollback.md). Enforced via CI performance tests on RC builds. Budget regressions fail the build. Performance is a feature.

---

## 13. Migration policy

Breaking backend contract changes never ship as single cutover:
- **Dual-response window** of N days (default 30, longer for offline-capable flows). Backend emits both shapes. Clients consume either.
- **Client adoption window** — all supported versions update.
- **Enforcement cutover** — old shape removed.

No big-bang. No "we'll update client and backend in the same release."

---

## 14. Branch hygiene

- `main` is always deployable. Fixing a broken main is highest-priority work.
- Feature branches short-lived (under 3 days, max 1 week).
- `release-candidate/*` branches cut for App Store submission. Only submission-blocker fixes land on RC.
- Force-push to `main` prohibited. To your own feature branch pre-review, fine.

---

## 15. Versioning discipline

- **Semver for backend contract.** Major = breaking, minor = additive, patch = internal. Surfaced in response envelope.
- **`CURRENT_PROJECT_VERSION`** monotonic. No skips. No resets. Burned versions stay burned.
- **`MARKETING_VERSION`** follows deliberate cadence. No silent bumps.

Version discipline is boring. That is the point.

---

## 16. Doctrine enforcement in review

Auto-reject conditions:

- New `Brand.info` fill where `Brand.primary` or semantic color is correct.
- Unclaimed `Toggle` (no binding, no action, no persistence path).
- AI-template header comment (`// Created by ... on ... for ...`).
- Hardcoded forbidden literal (MockDataGuard).
- Missing test for changed behavior.
- Missing architecture note for public API change.

Not personal. This is how the doctrine stays alive as code, not as a wiki page nobody reads.

---

## 17. Post-incident ritual

Every production incident — every one, no matter how small — produces a blameless postmortem within one business week:

- **Timeline.** What happened, when, as observed.
- **Root cause.** The honest answer, not the convenient one. If the root cause is "a test we should have had," that is written plainly.
- **Corrective action.** Specific, assigned, dated change preventing recurrence.
- **Test added.** Every postmortem ships with a test (unit, integration, or E2E) that would have caught the incident. Non-negotiable.

Blameless means we critique the system, not the engineer. Transparency is rewarded.

---

## 18. Recursive Refinement Loops (RLM-derived)

### 18.1 The principle

The Recursive Language Model paper describes a family of techniques where a language model's output is iteratively refined through multiple self-reflective passes. Rather than asking one deep-thinking pass for a final answer, the model generates, critiques, refines, and re-evaluates in layered loops. The practical wins:

- Multiple shallow passes catch more bugs than one deep pass.
- Self-reflection surfaces latent assumptions the original pass missed.
- Layered prompting manages context windows so the model doesn't drown in its own output.
- Iterative refinement converges on better answers than single-shot generation.
- Meta-reasoning (reasoning about the reasoning) improves reliability.

These aren't novel in software engineering — code review, pair programming, and the Kent Beck TDD loop are instances of the same pattern. The RLM contribution is making the pattern explicit and programmable.

### 18.2 Applied to EusoTrip

We apply RLM principles at five layers:

1. **Doctrine self-critique.** Each firing of the `eusotrip-killers` scheduled task reads the current doctrine set, compares it against the trajectory ledger (`EUSOTRIP_TRAJECTORY.json`), identifies drift, and proposes diffs. The doctrine is not static; it self-improves.
2. **Code-review passes.** A PR under review gets three passes, not one:
   - Pass 1: correctness + tests (RED/GREEN verification).
   - Pass 2: doctrine compliance (design tokens, forbidden patterns, architecture rules).
   - Pass 3: cross-platform parity (does the shape match web?).
   Three shallow passes catch what a single deep pass misses.
3. **Figma handoff refinement.** The Figma gap audit ([85_Figma_Gap_Audit_and_Recommendations.md](./85_Figma_Gap_Audit_and_Recommendations.md)) is a recursive pass over the screen queue — each screen gets Option A / Option B / Option C alternates evaluated against four invariants (mental model, provenance, offline fallback, a11y).
4. **Backend API evolution.** tRPC procedure changes pass through a dual-response window (§13) that is itself a recursive refinement — old shape + new shape coexist while clients migrate. The cutover is the final refinement pass.
5. **Incident postmortems.** The postmortem ritual (§17) is a recursive pass over the incident: timeline, root cause, corrective action, test. Each element is refined by the next — the corrective action must actually address the root cause; the test must actually catch the failure mode.

### 18.3 The closed feedback loop

The SKILL.md + TRAJECTORY.json + doctrine set form a closed feedback loop:

1. `SKILL.md` encodes the current operational doctrine for the scheduled task.
2. Each task firing produces an `EUSOTRIP_AUTORUN_*_REPORT.md` logging what was done.
3. `EUSOTRIP_TRAJECTORY.json` updates with the firing outcome.
4. Next firing reads the trajectory, identifies drift, and updates `SKILL.md` and the doctrine set.
5. Loop continues.

This is recursive self-improvement in operation. The doctrine gets sharper every firing.

### 18.4 Context-window management

Multiple shallow passes need disciplined context management. Our rules:

- Each pass has a narrow scope (e.g., "review only tests," "review only typography").
- Context loaded per pass should fit in a single focused read rather than the whole repo.
- Outputs of a pass become inputs to the next pass, not accumulated raw state.
- When context threatens to exceed the window, break the pass into sub-passes scoped by file or subsystem.

This is why the doctrine is multi-file: each file is a context-window-sized unit that a pass can load in isolation.

### 18.5 Meta-reasoning

The doctrine-auditor pattern (see [98_Recursive_Language_Model_Integration.md §6](./98_Recursive_Language_Model_Integration.md)) applies meta-reasoning: it reasons about how we maintain this doctrine, not just about the content.

Questions the auditor asks weekly:
- Is any file drifting from its source shard?
- Are cross-links broken?
- Are any verbatim quotes paraphrased?
- Are `Last updated` footers stale?
- Are new shards landing that aren't indexed in the README?
- Are principles contradicting each other?

The auditor doesn't rewrite; it reports drift. Engineers fix.

---

## 19. No "vibe coding" on EusoTrip

Every line is owned by a human engineer whose name is on the commit and whose reputation is on the release. "Vibe coding" — pasting AI output without understanding it, accepting because it compiles, shipping because it seems to work — is disqualified.

This is not anti-AI. It is pro-craftsmanship. The tool is excellent; the craftsman is still responsible.

---

## 20. Foundation-first before optimization

Kent Beck's ordering is our ordering:

1. **Make it work.** Correct behavior, covered by tests.
2. **Make it right.** Clean structure, honest abstractions, no duplicated logic.
3. **Make it fast.** Measure, find the real hotspot, optimize with evidence, re-measure.

Optimizing before it works produces fast wrong answers. Optimizing before it's right produces fast unmaintainable answers. We do all three. In order. We do not skip step two to get to step three faster.

---

## Closing

Red. Green. Refactor. Every feature. Every time.
E2E tests in every plan. No exceptions.
No fancy plugins. No runtime MCPs. No vibe coding.
SOLID types. Pure functions. Fail fast. Immutable by default.
Feature-flag the risky work. Measure the latency. Enforce the budgets.
Main is deployable. Versions are monotonic. Migrations have windows.
Every PR carries evidence. Every incident produces a test.
Foundation first, always.
Three shallow passes over one deep pass. Doctrine self-critiques. Context managed per pass.

That is how nothing breaks.

---

**Cross-links.**
- [00_README.md](./00_README.md) for the full doctrine set.
- [98_Recursive_Language_Model_Integration.md](./98_Recursive_Language_Model_Integration.md) for the RLM-derived operating model.
- [92_Launch_Runbook_and_Rollback.md](./92_Launch_Runbook_and_Rollback.md) for incident response ritual in practice.
- [03_Backend_API_Contract.md](./03_Backend_API_Contract.md) for the latency budgets these principles enforce.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
