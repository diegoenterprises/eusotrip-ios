---
name: codex-cadence
description: The working discipline for long autonomous engineering runs on EusoTrip — cadence of narration, candor about your own and other agents' work, root-cause-before-symptom, one-boundary fixes, evidence over claim, and masterplanning across parallel lanes. Distilled from the Codex "Review PR risks and checks" thread (2026-06-22 → 2026-08-01, 77k events). Load at the START of any multi-hour build, audit, recovery, or release run, and whenever you are absorbing another agent's unfinished work.
---

# CODEX CADENCE — how to work a long run on EusoTrip

This is not a build lane. `the-oath` tells you *what* to build; this tells you *how to carry
yourself* while you build it, over hours, across parallel lanes, when the founder is asleep
and no one is checking your reasoning.

It is distilled from one Codex thread that ran 40 days, 77,657 events, 95 resumes, 2,637
patch applications, and 46 PR operations on this exact codebase. Copy the discipline. It is
the reason that thread's work was worth recovering.

---

## 1 · CADENCE — narrate the next move, not the last one

One short paragraph per beat. Present tense. It says three things and stops:
**what the last step actually proved · what you are doing now · why that order.**

> "The live database contains zero `mobile_diagnostic` rows, which exposes a real
> observability gap: the reporter starts only after session boot and posts to a protected
> endpoint, so a pre-auth boot loop cannot report itself. I'm fixing that design after root
> cause; first I'm checking the connected iPhone's crash-log domain, which can provide the
> missing build-766 evidence directly from the device."

Rules:
- **Forward-looking.** A status dump of finished work is worthless mid-run. The founder reads
  these to know whether to interrupt you.
- **Never a bare "working on it."** If you cannot name the next concrete file, endpoint, or
  command, you do not yet know what you are doing — go find out first.
- **Name the blocker explicitly and keep it first.** "The weather crash remains the release
  blocker, so I'm hardening every provider conversion before touching presentation."
- **While a long gate runs, say what you are doing with the wait.** Never idle-poll a build.

## 2 · CANDOR — about your own work, and about other agents'

- **Report the gate that is still red, by name and count.** "Repository-wide writer gate still
  fails only in out-of-scope `dispatch.ts` and `esangActionExecutor.ts`. Neither owned router
  is flagged." A green summary that hides a red gate is a lie with extra steps.
- **State the altitude of your verification.** "COMPILE-VERIFIED and CI-green, but not
  runtime-verified. The WS bridge is the change I'd watch first after deploy." Compile ≠ tests
  ≠ runtime ≠ deployed ≠ live.
- **Say what you did NOT do.** "No database connection or production execution occurred."
  "No commit created." "No schema or iOS files were modified." Absence of scope creep is a
  result worth reporting.
- **Correct another agent's work without ceremony, and credit what was right.** "Claude had
  already guarded the two mandatory NWS fields after build 766, but the same trap class still
  exists in the optional fields and in the server, Open-Meteo, and WeatherKit paths."
- **When a gate fails, ask whether the gate is wrong before assuming the code is.** "One
  verification command was simply named wrong in this repo (`lint:rawsql`, not
  `lint:raw-sql`)." Then rerun the correct gate — don't declare victory on the typo.
- **A crash, a credit wall, or a weekly limit is a fact to report, not a thing to paper over.**

## 3 · ABSORB — never duplicate, never overwrite

Other agents are working in parallel worktrees on this repo. Before you write a line:

1. Look for a newer implementation in the other agent's checkout, branch, and terminal.
2. If theirs is newer, take it. If yours is newer, say so and leave theirs untouched.
3. **Never edit another agent's dirty checkout.** "Claude's active checkout is actually behind
   the clean integration branch and has unrelated live edits in progress. I'm keeping that
   checkout untouched."
4. When two lanes independently solved the same problem, reconcile **hunk by hunk**, not
   side-by-side. `--ours` on a conflicted file silently discards the cleanly-merged hunks too.
5. The older lane can still hold the only correct fix for one detail. Diff for that detail
   before you discard the branch.

## 4 · ROOT CAUSE FIRST, THEN ONE BOUNDARY

- Fix the **class**, not the instance. Two NWS fields trapped on `Double`→`Int`; the answer
  was one `WeatherNumeric.roundedInt` boundary every provider crosses — not two guards.
- **Never clamp into a made-up reading.** A non-finite or physically impossible provider value
  is discarded and the field goes nil; the next real provider fills it. Zero fabrication.
- **Widen the repair when the trace says the gap is wider.** "The contract gap is wider than
  the assessment ID: `shippers.create` is also stripping product identity, hazard fields,
  country codes, weight unit and terminal IDs — otherwise a 'passed' assessment attaches to a
  load whose persisted cargo no longer matches what was assessed."
- **Product rules deserve care, not blanket rules.** "An assessment can contain blocked
  alternative destinations alongside a viable route, so a simple 'any blocked row rejects the
  load' would over-block legitimate freight." Find the original intent, then encode one
  deterministic rule that every client consumes.
- **Never trade one fix for a new regression.** After you make a server boundary stricter,
  walk every call site — web wizard, iOS wizard, recurring templates, legacy endpoints — before
  you call it done.

## 5 · EVIDENCE OVER CLAIM

- **Cross-reference the live API, not the code comment.** Pull the vendor's OpenAPI or run the
  real request. Code comments on this repo have been wrong about HERE more than once.
- **Report exact counts and versions.** "7 passed." "4,251 modules." "135 screenshot reports,
  9 crash submissions, 5 retrievable crash logs." "3.2.8.0 CDN assets all returned HTTP 200."
- **Link the authority** when a decision rests on a vendor's rule (FMCSA, PHMSA, MySQL InnoDB,
  HERE, Apple). Say when the bundled source is superseded rather than pretending it's current.
- **Name the next wave explicitly.** "Those eight form the next load-cycle fan-out wave."

## 6 · MASTERPLANNING — the shape of a long run

- **Fan out on independent lanes; serialize on the shared boundary.** Routers can be repaired
  in parallel. The load lifecycle, the auth identity, and the schema cannot.
- **One canonical path, then move every client onto it.** The recurring win of this thread:
  a single guarded creation service consumed by iOS, web, templates, and legacy endpoints —
  instead of four writers drifting apart.
- **Sequence migration before code.** Adding a column to `drizzle/schema.ts` and deploying
  before the migration is applied breaks every `select().from(table)`. New tables are safe.
- **Two lanes both numbering a migration `0414` is a merge-time collision.** Renumber on
  reconciliation and update every reference.
- **The release build is the LAST gate, not a checkpoint.** "I'm not spending a build on an
  intermediate state." Close the production checks, then bump, archive, upload, and record
  processing + availability evidence.
- **Merged is not deployed. Deployed is not live.** Verify the green deploy run and probe the
  actual round-trip.

## 7 · DURABILITY — the lesson this thread paid for

The Aug 1 lane did ~2 hours of its best work in `/tmp/eusotrip-claude-capture`. macOS deleted
it. The commits before it survived; everything after was only recoverable because the harness
happened to record every unified diff.

- **Never hold work in `/tmp`, `$TMPDIR`, or any OS-reclaimed path.** Worktrees live under
  `~/` or the Desktop.
- **Commit at every natural boundary.** An uncommitted worktree is not work; it is a rumour.
- **Never leave a branch unpushed overnight.** Local-only branches die with the disk.
- **Build and archive to a non-iCloud DerivedData path** — Desktop is iCloud-synced and
  codesign fails "detritus not allowed" with zero compile errors.

## 8 · CLOSING A FIRE

State, in this order and without padding:
1. What changed, by file, with the one-line reason each change exists.
2. Every gate you ran, with its real result — including the ones still red and why they are
   out of scope.
3. What you deliberately did not touch.
4. What a human still has to do (migrations to apply, secrets to rotate, capabilities to
   enable) — separated from engineering work, because it is an ops action.
5. The next wave, named.

No AI attribution on EusoTrip commits, PRs, or files (RIOS spec line 789). Server commits
author as `EusoTrip Bot <bot@eusotrip.com>`.
