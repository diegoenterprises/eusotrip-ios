# 98 · Recursive Language Model Integration

**What this covers.** The Recursive Language Model (RLM) principles applied to EusoTrip — an executive summary of the RLM approach, how recursive self-improvement + self-reflection loops + layered prompting + context-window management + iterative refinement + meta-reasoning map onto our doctrine maintenance, code review, Figma handoff, backend API evolution, and incident postmortems. Case study: the `eusotrip-killers` scheduled task as an instance of recursive self-improvement. Recommended future enhancements: a doctrine-auditor agent that reads this doctrine weekly and proposes diffs.

**When you need this.** When you need to understand *why* the doctrine is structured as multiple files. When designing a new feedback loop. When scoping the next generation of the scheduled-task skill. When considering how to apply the RLM technique to a new surface (e.g., design review, or incident response).

**Cross-links.** Engineering principles that reference RLM: [02_Engineering_Principles.md §18](./02_Engineering_Principles.md). Codebase continuity (the workspace the auditor reads against): [95_Codebase_Continuity_and_Claude_Init.md](./95_Codebase_Continuity_and_Claude_Init.md). The trajectory ledger (the auditor's input): `~/Desktop/EUSOTRIP_TRAJECTORY.json`.

---

## 1. Executive summary of the RLM paper

The Recursive Language Model (RLM) paper describes a family of techniques where the output of a language model is iteratively refined through multiple self-reflective passes rather than emitted from a single inference. Instead of asking one deep-thinking pass for a final answer, the model:

- **Generates** a candidate output.
- **Critiques** the candidate against explicit criteria.
- **Refines** the candidate in response to the critique.
- **Re-evaluates** whether the refined candidate now passes.
- Repeats until convergence or budget exhaustion.

The core claim: **multiple shallow passes catch more failure modes than one deep pass**, particularly when (a) the task has multiple dimensions of quality, (b) the model can self-critique with reasonable fidelity, and (c) the context window is managed so each pass has a well-scoped input.

The paper's key contributions — distilled:

1. **Recursive self-improvement.** An agent reads its own output, identifies weaknesses, revises. Applied to code, writing, planning, evaluation.
2. **Self-reflection loops.** The agent asks "what did I miss?" before committing, and iterates until the question's answer is "nothing."
3. **Layered prompting.** Different passes use different prompts — one pass checks correctness, another checks style, another checks completeness — rather than asking a single pass to hold all criteria in mind.
4. **Context-window management.** Each pass loads only what it needs. Outputs of earlier passes become inputs to later passes, rather than accumulating raw state.
5. **Iterative refinement.** Convergence on better answers is achieved through many small improvements, not one big leap.
6. **Meta-reasoning.** The agent reasons about how it reasons — watching for consistent failure modes, adjusting its own strategy, becoming more reliable over time.

The RLM paper is not about novel machine-learning architecture. It is about *discipline in the loop*. Much of what the paper articulates was already implicit in good software engineering practice — code review is a shallow pass, pair programming is a real-time critique loop, Kent Beck's TDD is iterative refinement, and postmortem rituals are meta-reasoning. The RLM contribution is making the pattern explicit and programmable so that non-human agents (including Claude) can participate.

---

## 2. Key RLM quotes and what they mean for EusoTrip

This section paraphrases the RLM paper's most load-bearing principles and translates each into an EusoTrip-specific posture.

### 2.1 "Recursion outperforms depth when errors are orthogonal."
If the errors your first pass makes are of one kind, a deep reflective pass on the same surface won't catch errors of another kind. Multiple passes, each scoped to one kind of error, catch the complement.

**For EusoTrip**: code review has three passes (correctness + tests, doctrine compliance, cross-platform parity), not one. Each pass has a narrow prompt and catches a different class of defect.

### 2.2 "The model should critique its own output before committing."
Rather than asking the model for its best answer and accepting it, ask the model for a candidate, then ask the same model to find the flaws in that candidate.

**For EusoTrip**: every doctrine update from the `eusotrip-killers` firing is produced, then re-read by the same skill, then refined before commit. The trajectory ledger records both the first draft and the revision.

### 2.3 "Context fits inside one pass, or it doesn't fit at all."
A pass with too much input drowns in its own material. Decompose by subsystem, by file, by concern.

**For EusoTrip**: the doctrine is multi-file deliberately. Each file is a context-window-sized unit. A pass over `01_Brand_DNA_and_Design_Rules.md` does not need to load the full state machine from `04_Database_and_Schema.md`. Cross-links replace duplication.

### 2.4 "State lives in artifacts, not in the model."
The model should write state to durable artifacts (files, logs, ledgers) and read state from those artifacts in subsequent passes. Don't rely on conversational memory.

**For EusoTrip**: `EUSOTRIP_TRAJECTORY.json` is the durable state. `SKILL.md` is the durable policy. Each firing reads both, acts, and writes back. Between firings, the agent has no memory — everything is reconstructed from the artifacts.

### 2.5 "Refinement is cheaper than re-generation."
Editing an existing artifact is often faster and more reliable than generating a new one from scratch.

**For EusoTrip**: doctrine updates are diffs, not rewrites. The scheduled task proposes edits to existing files and appends to the ledger; it rarely rewrites whole documents.

### 2.6 "Meta-reasoning watches for pattern drift."
The highest-leverage self-reflection is about one's own failure modes: "I keep forgetting X. Let me add X to my checklist."

**For EusoTrip**: the "doctrine auditor" pattern (§6) is meta-reasoning — it reads the doctrine for drift and proposes a checklist update, rather than fixing content directly.

---

## 3. Applying RLM to EusoTrip — five layers

### 3.1 Doctrine self-critique (this document's existence)

Each firing of `eusotrip-killers` reads the current doctrine set, compares it against the trajectory ledger, identifies drift, proposes diffs. The doctrine is not static; it self-improves.

**Mechanics:**
- Input: `SKILL.md` (policy), `EUSOTRIP_TRAJECTORY.json` (state), the doctrine files (subject).
- Pass 1: detect drift — which shards changed since last firing? which files reference stale paths? which Last-updated footers are older than 30 days?
- Pass 2: propose remediation — for each drift item, draft an edit.
- Pass 3: self-critique — read the proposed edit, check for tone consistency, cross-link correctness, no accidental duplication.
- Commit: write edits, append ledger row.

### 3.2 Code review passes

Rather than a single reviewer holding all criteria in mind, the PR template enforces three structured passes:

- **Pass 1 (correctness + tests):** RED test present, GREEN test passes, production code satisfies spec.
- **Pass 2 (doctrine compliance):** design tokens used correctly, forbidden patterns absent, architecture rules respected (see [01_Brand_DNA_and_Design_Rules.md](./01_Brand_DNA_and_Design_Rules.md) and [02_Engineering_Principles.md](./02_Engineering_Principles.md)).
- **Pass 3 (cross-platform parity):** does the shape match web? is the DTO still 1:1? is the icon registered in `icon-map.json`?

Three shallow passes catch what a single deep pass misses. Each pass has its own checklist and its own approver.

### 3.3 Figma handoff refinement

The Figma gap audit ([85_Figma_Gap_Audit_and_Recommendations.md](./85_Figma_Gap_Audit_and_Recommendations.md)) is a recursive pass over the screen queue. For each screen:

- **First pass:** does a canonical backend procedure exist?
- **Second pass (if gap):** produce Option A (reuse), Option B (compose), Option C (defer).
- **Third pass:** filter alternates against four invariants (mental model, provenance, offline fallback, a11y).
- **Fourth pass:** assign priority tier (P0/P1/P2).

The resulting recommendation survives review because each pass was narrow enough to be thorough.

### 3.4 Backend API evolution

tRPC procedure changes pass through a dual-response window (see [02_Engineering_Principles.md §13](./02_Engineering_Principles.md)) that is itself a recursive refinement — old shape and new shape coexist while clients migrate. The cutover is the final refinement pass.

At each stage:
- Old shape remains green; new shape also green.
- Telemetry tracks consumption of each.
- When new-shape consumption crosses 99%, old shape is removed (the final pass).

### 3.5 Incident postmortems

The postmortem ritual ([02_Engineering_Principles.md §17](./02_Engineering_Principles.md), [92_Launch_Runbook_and_Rollback.md §12](./92_Launch_Runbook_and_Rollback.md)) is a recursive pass over the incident:

1. Timeline — what happened, when.
2. Root cause — the honest one, not the convenient one.
3. Corrective action — the specific, dated, assigned change.
4. Test added — the contract that the incident does not silently recur.

Each element is refined by the next. The corrective action must actually address the root cause; the test must actually catch the failure mode. A postmortem that skips the test step is incomplete.

---

## 4. The closed feedback loop — `eusotrip-killers` as case study

The SKILL.md + TRAJECTORY.json + doctrine set + `EUSOTRIP_AUTORUN_*_REPORT.md` files form a **closed feedback loop** that is a concrete instance of recursive self-improvement applied to a real-world engineering workflow.

### 4.1 The loop in detail

1. **`SKILL.md`** encodes the current operational doctrine for the scheduled task. It carries the brick recipe, the screen queue, the file map, the backend codebase map, the known landmines, and the non-negotiable rules. It is the policy the firing follows.
2. **Each task firing** produces an `EUSOTRIP_AUTORUN_YYYY-MM-DD_REPORT.md` logging what was done, what was deferred, what broke, and what the firing learned.
3. **`EUSOTRIP_TRAJECTORY.json`** updates with the firing outcome — which bricks were ported, which were blocked, which ledger rows were added.
4. **The next firing** reads the trajectory, identifies drift (stale bricks, new Figma frames without tRPC mapping, newly-discovered landmines), and updates SKILL.md and the doctrine set.
5. **The loop continues**, firing after firing, doctrine sharpening, ledger growing, workflow converging on reliability.

This is recursive self-improvement in operation. The doctrine gets sharper every firing because each firing is both an actor and a critic.

### 4.2 Why this is not "just automation"

A naive automation runs the same steps every time. A recursive language-model-driven automation reads its own output, finds weaknesses, and improves the policy. When the tenth firing notices that the sixth firing missed a bug class that was caught in the eighth firing, it can add a check for that bug class to the skill — and every subsequent firing benefits.

### 4.3 The audit trail

Every firing is logged to `EUSOTRIP_AUTORUN_*_REPORT.md`. These reports are discoverable, reviewable, and form the provenance trail for the doctrine itself. If you want to know why a particular rule exists in the doctrine, the ledger + reports tell you which firing added it and why.

---

## 5. Context-window management — why the doctrine is multi-file

The RLM paper's most practical contribution is **context-window discipline**. A pass's input must fit in the pass's working memory.

This doctrine is deliberately multi-file. Each file is scoped so that a pass over it loads a coherent subsystem without dragging in irrelevant material.

**Examples of the discipline:**
- A pass reviewing typography loads `01_Brand_DNA_and_Design_Rules.md` only.
- A pass reviewing a migration loads `04_Database_and_Schema.md` only.
- A pass reviewing a new role loads the relevant `10_Mode_TRUCK/` or `20_Mode_RAIL/` or `30_Mode_VESSEL/` file plus the Overview.
- A pass reviewing a journey loads `80_User_Journeys_and_Load_Lifecycle.md`.

If the doctrine were one monolith, every pass would load every rule — and forget most of them. The multi-file structure is the RLM discipline materialized as file layout.

---

## 6. Recommended future enhancements

### 6.1 The doctrine-auditor agent

Add a new scheduled task, `eusotrip-doctrine-auditor`, that fires weekly and does NOT write content — it only reports drift. Questions the auditor asks:

- Is any file drifting from its source shard in `~/Desktop/doctrine_wave1/`?
- Are any cross-links broken?
- Are any verbatim quotes paraphrased?
- Are `Last updated` footers stale (>30 days)?
- Are new shards landing in `doctrine_wave1/` that aren't indexed in `00_README.md`?
- Are principles contradicting each other across files?
- Is any file >5,000 lines and should be split?
- Is any file <200 lines and should be merged?

Output: a PR-sized diff of suggested edits, posted to a `#doctrine-drift` Slack channel. Engineers review and apply. The auditor never commits directly — it reports, and humans curate.

### 6.2 The trajectory-informed firing

Extend `eusotrip-killers` to read the last N firings' reports before acting, identify patterns (e.g., "the last three firings all flagged the wallet router as partial"), and prioritize work accordingly. Today the firing treats each invocation as stateless-ish; future firings would be trajectory-aware.

### 6.3 The cross-doctrine consistency check

Add a pass that reads every doctrine file, builds a term graph (what each file defines, what each file references), and flags mismatches. Example: if `01_Brand_DNA_and_Design_Rules.md` says `Brand.magenta = 0xBE01FF` and `91_Web_Mobile_Parity.md` says `--brand-magenta: #E6008B`, the auditor flags the inconsistency.

### 6.4 The RLM-patterned design review

Apply the three-pass structure to design reviews: (1) does it match the brand rules, (2) does it serve the user journey, (3) does it have all six RemoteState variants. Today design review is usually one pass; a three-pass structure would catch more.

### 6.5 The incident classifier

Add a pass over historical postmortems that identifies recurring failure archetypes (auth race conditions, schema drift, mode mismatch) and proposes doctrine updates that prevent the next instance of each archetype. This is meta-reasoning applied to incidents.

---

## 7. Limits of RLM — what it does not fix

The RLM approach is not magic. It does not:

- **Replace domain expertise.** The agent can only critique against criteria it knows about. If the criteria are wrong, more passes won't help.
- **Catch novel failure modes.** The recursive pass catches known classes of error. New classes require new checklists.
- **Eliminate human judgment.** Final accept/reject of a doctrine edit or a code change is still a human call. The agent proposes; humans dispose.
- **Remove the need for testing.** Recursive refinement of code still needs runtime tests. Self-critique complements, does not replace, execution.
- **Solve coordination.** Two teams working on two files don't synchronize just because both teams use RLM-style passes. The shared-everything principle ([91_Web_Mobile_Parity.md](./91_Web_Mobile_Parity.md)) is still required.

The technique is a sharp tool with a known blade. Treat accordingly.

---

## 8. Closing — why this section is in the doctrine

This section exists because the doctrine itself is an artifact of the RLM approach. You are reading a doctrine that was produced by one pass, reviewed against the wave-1 shards in another pass, cross-linked against the other doctrine files in a third pass, and will be revised again in the next firing of `eusotrip-killers`.

The doctrine is not a static deliverable. It is a **checkpoint in a feedback loop**. The loop's purpose is to make the doctrine sharper every iteration. The loop's constraint is that every iteration must leave the doctrine strictly more useful than the prior iteration — otherwise we are thrashing, not improving.

If you are reading this during a firing, thank you. Leave the ledger better than you found it.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
