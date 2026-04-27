# 95 · Codebase Continuity + Claude Code Initialization

**What this covers.** The source inventory of every folder that could contain EusoTrip source, doctrine, or operational artifact; the recommended symlink-hub workspace; the canonical `CLAUDE.md` boot file; per-repo `.claude/settings.json`; git hooks (no-mock-data, tests-exist, ledger-touch); the `eusorone-web-apps` MCP server configuration; alternate editors (VS Code, Cursor, Windsurf); ten-step new-engineer onboarding; escape hatches; and **the FINAL `claude` init command** for starting a fresh session with every source root visible. Synthesized from wave-1 shard `team_CLAUDE_init` + RLM principles + filesystem audit of 2026-04-23.

**When you need this.** On day one of hiring a new engineer. When your Claude session keeps editing the wrong repo. When setting up Claude Code on a new Mac. When preparing for a multi-repo story.

**Cross-links.** RLM integration (which makes the doctrine self-improve via scheduled task firings): [98_Recursive_Language_Model_Integration.md](./98_Recursive_Language_Model_Integration.md). Engineering principles enforced by git hooks: [02_Engineering_Principles.md](./02_Engineering_Principles.md).

---

## 0. TL;DR — the FINAL command

For the daily driver (pasteable):

```bash
cd "$HOME/Desktop/eusotrip-workspace" && claude
```

For a strict backend-only session:

```bash
cd "$HOME/Desktop/eusoronetechnologiesinc" && claude
```

For a one-off session spanning multiple repos (no symlink hub):

```bash
claude \
  --add-dir "$HOME/Desktop/EUSOTRIP" \
  --add-dir "$HOME/Desktop/AI/eusoronetechnologiesinc" \
  --add-dir "$HOME/Desktop/EusoTrip 2006 for iPhone" \
  --add-dir "$HOME/Desktop/eusoronetechnologiesinc_backup" \
  --add-dir "$HOME/Desktop/EusoTrip Mobile App Doctrine 2027" \
  --add-dir "$HOME/Desktop/doctrine_wave1" \
  --add-dir "$HOME/Documents/Claude/Scheduled/eusotrip-killers"
```

The first one is what you want 95% of the time, once the symlink hub is built per §3.

---

## 1. EusoTrip source inventory (audited 2026-04-23)

A fresh filesystem audit of `~/Desktop` and `~/Documents` on this machine turned up the following categories. The inventory below reflects what **actually exists on disk** at the time of writing; older doctrine references to `~/Desktop/eusoronetechnologiesinc/` and `~/Desktop/EusoTrip by Eusorone Technologies, Inc/` do not currently resolve on this machine and need to be re-pulled before the workspace is fully functional.

### 1.1 Primary sources (pull these before running the hub setup)
- `~/Desktop/eusoronetechnologiesinc/` — active backend + web monorepo. Node + Drizzle + React/Vite. Deploys to `eusotrip-app.azurewebsites.net`. **Not present on this machine as of 2026-04-23 — pull from git before running §3.**
- `~/Desktop/EusoTrip by Eusorone Technologies, Inc/` — active native iOS SwiftUI app. Xcode project, ViewModels, HereMaps services, `_WAVE3_AUDIT/` + `_WAVE4_BUILD/` staging folders. **Not present on this machine as of 2026-04-23 — pull from git before running §3.**

### 1.2 Secondary sources
- `~/Desktop/EusoTrip 2027 UI/` — the 2027 wireframe canon: `00_doctrine/DOCTRINE.md`, `01_design_system/tokens.css` + `DesignSystem.swift`, `02_html/dark + 02_html/light` pairs (010–022), `03_swiftui/` screens, `04_waves/WAVE_PLAN.md`. Designers + front-end devs live here. **Not present on this machine as of 2026-04-23 — pull before running §3.**
- `~/Desktop/doctrine_wave1/` — the wave-1 doctrine shards this document synthesizes. **Present.** 25 files.
- `~/Desktop/EusoTrip Mobile App Doctrine 2027/` — this doctrine set. **Present.** Produced by this deliverable.

### 1.3 Tertiary / stale / reference (present on this machine)
- `~/Desktop/EUSOTRIP/` — the "ideas dump" folder. Roadmaps, docs, swift drafts, HTML mockups, gamification PSO scripts, wallet + commission docs. Includes legacy `eusotrip-frontend 2/` with its own `mobile-app/` + `frontend/` subtrees. **Present.** Archaeology goldmine, not build target.
- `~/Desktop/EusoTrip 2006 for iPhone/` — the 2006-generation iOS prototype. **Present.** Kept for reference; **do not edit**.
- `~/Desktop/eusoronetechnologiesinc_backup/` + `~/Desktop/eusoronetechnologiesinc-broken/` — last-known-good + last-known-bad snapshots of the backend. **Present.** Useful for git-diff archaeology; never build targets.
- `~/Desktop/AI/eusoronetechnologiesinc/` — older AI-scaffolded variant of the backend. **Present.** Reference only.
- `~/Desktop/EUSOTRIP/eusotrip-frontend 2/` — older iOS + frontend checkout inside the ideas dump.

### 1.4 Operational artifacts
- `~/Desktop/EUSOTRIP_TRAJECTORY.json` — master ledger tracking every autorun, brick-port, hygiene pass. **Present.** Source of truth for "what firing are we on?"
- `~/Desktop/EUSOTRIP_AUTORUN_*_REPORT.md` — 60+ dated autorun reports (2026-04-19 through 2026-04-23). Paper trail of scheduled killer runs.
- `~/Documents/Claude/Scheduled/eusotrip-killers/SKILL.md` — the scheduled task skill that drives the killer firings. **Present.** If missing, new engineer has not set up `claude schedule` yet + should before running any doctrine task.
- `~/Documents/Claude/Scheduled/eusotrip-2027-ui-build-loop/SKILL.md` — parallel scheduled task for UI build loop. **Present.**

### 1.5 Supporting assets (present)
- `~/Desktop/brand/` — brand guidelines, logos.
- `~/Desktop/EUSOSECURITY/` — security architecture docs.
- `~/Desktop/EUSOTERMINAL/` — terminal / facility database docs (if present).
- `~/Desktop/EusoMap/, TELEMETRY/, ZEUN/, TEST/, JOURNEY/, EUSOCONNECT/, heatmap/, GAPS 2026/, FIX/, Eusotrip Features/, Eusotrip Action/, COWORK TEAMS/` — topic-specific design + spec folders. Attach as needed per story.

### 1.6 Source repos referenced in earlier doctrine but not present on this machine
These paths were referenced by prior shards but **do NOT exist on this machine's filesystem as of 2026-04-23**. They need to be pulled from their canonical git remotes before a full workspace can function:
- `~/Desktop/eusoronetechnologiesinc/` (active backend — highest priority to pull).
- `~/Desktop/EusoTrip by Eusorone Technologies, Inc/` (active iOS — highest priority to pull).
- `~/Desktop/EusoTrip 2027 UI/` (wireframe canon).

See §11 "Deferred" for the implication.

---

## 2. The problem with `cd ... && claude`

`cd ~/Desktop/eusoronetechnologiesinc && claude` gives Claude Code exactly one directory. Any file outside is invisible — Claude cannot read iOS SwiftUI files, cannot cross-reference 2027 wireframes, cannot check trajectory ledger, cannot look at `_WAVE4_BUILD`. Fine for backend-only story. Terrible for anything end-to-end.

Solve two ways. **Option A** (recommended for most): symlink hub. **Option B** (recommended for one-off): `--add-dir`.

---

## 3. Option A — the `eusotrip-workspace` symlink hub (recommended)

Create single folder on Desktop whose only job is to hold named symlinks to every EusoTrip source. Open Claude Code against that folder; Claude sees everything through one clean tree.

### 3.1 One-time setup

Idempotent — running twice does no harm.

```bash
mkdir -p ~/Desktop/eusotrip-workspace
cd ~/Desktop/eusotrip-workspace

# Active sources (if they exist — pull from git first if not)
[ -d "$HOME/Desktop/EusoTrip by Eusorone Technologies, Inc" ] && \
  ln -sf "$HOME/Desktop/EusoTrip by Eusorone Technologies, Inc" ios
[ -d "$HOME/Desktop/eusoronetechnologiesinc" ] && \
  ln -sf "$HOME/Desktop/eusoronetechnologiesinc" backend
[ -d "$HOME/Desktop/EusoTrip 2027 UI" ] && \
  ln -sf "$HOME/Desktop/EusoTrip 2027 UI" wireframes
[ -d "$HOME/Desktop/EusoTrip by Eusorone Technologies, Inc/_WAVE3_AUDIT" ] && \
  ln -sf "$HOME/Desktop/EusoTrip by Eusorone Technologies, Inc/_WAVE3_AUDIT" wave3_audit
[ -d "$HOME/Desktop/EusoTrip by Eusorone Technologies, Inc/_WAVE4_BUILD" ] && \
  ln -sf "$HOME/Desktop/EusoTrip by Eusorone Technologies, Inc/_WAVE4_BUILD" wave4_build

# Doctrine + operational
ln -sf "$HOME/Desktop/doctrine_wave1" doctrine_source_shards
ln -sf "$HOME/Desktop/EusoTrip Mobile App Doctrine 2027" doctrine
ln -sf "$HOME/Documents/Claude/Scheduled/eusotrip-killers" killers
ln -sf "$HOME/Documents/Claude/Scheduled/eusotrip-2027-ui-build-loop" ui_build_loop
ln -sf "$HOME/Desktop/EUSOTRIP_TRAJECTORY.json" ledger.json

# Reference / archaeology
ln -sf "$HOME/Desktop/EUSOTRIP" reference_archive
ln -sf "$HOME/Desktop/EusoTrip 2006 for iPhone" legacy_ios
[ -d "$HOME/Desktop/eusoronetechnologiesinc_backup" ] && \
  ln -sf "$HOME/Desktop/eusoronetechnologiesinc_backup" backend_backup
[ -d "$HOME/Desktop/eusoronetechnologiesinc-broken" ] && \
  ln -sf "$HOME/Desktop/eusoronetechnologiesinc-broken" backend_broken
[ -d "$HOME/Desktop/AI/eusoronetechnologiesinc" ] && \
  ln -sf "$HOME/Desktop/AI/eusoronetechnologiesinc" backend_ai_variant

# Supporting assets
ln -sf "$HOME/Desktop/brand" brand
[ -d "$HOME/Desktop/EUSOSECURITY" ] && ln -sf "$HOME/Desktop/EUSOSECURITY" security_docs
```

The `[ -d "..." ] && ln -sf` pattern skips missing sources silently; run the script again after pulling the missing repos to complete the hub.

### 3.2 Daily use

```bash
cd ~/Desktop/eusotrip-workspace && claude
```

That's it. Claude opens with one root, named aliases below it, every relevant source visible. Engineers stop saying "oh but that file is on the Desktop" because *everything* is on the workspace tree now.

### 3.3 Why symlinks, not copies

Copies drift. Symlinks are live — edit `ios/ViewModels/LoginViewModel.swift` from inside the workspace and you've edited the real file. No sync step, no divergence.

---

## 4. Option B — `claude --add-dir` for one-off sessions

If you don't want persistent workspace, or debugging across two specific repos for one afternoon:

```bash
claude \
  --add-dir "$HOME/Desktop/EusoTrip by Eusorone Technologies, Inc" \
  --add-dir "$HOME/Desktop/eusoronetechnologiesinc" \
  --add-dir "$HOME/Documents/Claude/Scheduled/eusotrip-killers" \
  --add-dir "$HOME/Desktop/EusoTrip 2027 UI" \
  --add-dir "$HOME/Desktop/doctrine_wave1" \
  --add-dir "$HOME/Desktop/EusoTrip Mobile App Doctrine 2027"
```

Use absolute paths inside `--add-dir` (not `~`) to avoid tilde-expansion edge cases. Quote any path containing spaces.

---

## 5. `CLAUDE.md` — the orientation file Claude reads on boot

Claude Code automatically reads `CLAUDE.md` at session root. Put every new Claude instance on the same page before engineer types first word.

Create `~/Desktop/eusotrip-workspace/CLAUDE.md` with:

```markdown
# EusoTrip Workspace

## Project
EusoTrip is a regulated-commerce OS for freight — shipper, carrier, driver, dispatch,
escort, terminal, compliance personas — built by Eusorone Technologies, Inc.

## Layout (everything here is a symlink to the real source on Desktop)
- ios/                     — iOS SwiftUI app. Xcode project at ios/EusoTrip.xcodeproj.
- backend/                 — Node + Drizzle + Vite monorepo. Deploys to Azure.
- wireframes/              — 2027 UI canon (HTML light + dark, SwiftUI, tokens, DOCTRINE.md).
- wave3_audit/             — Current iOS audit roadmap (_MASTER_ROADMAP.md + 10 agent buckets).
- wave4_build/             — Staged iOS additions not yet merged.
- doctrine/                — EusoTrip Mobile App Doctrine 2027 (this set).
- doctrine_source_shards/  — Wave-1 shards the doctrine is synthesized from.
- killers/                 — Scheduled-task killer skill (autorun firings).
- ui_build_loop/           — Parallel scheduled task for UI build loop.
- ledger.json              — EUSOTRIP_TRAJECTORY.json (firing/port ledger).
- reference_archive/       — Historical docs + drafts (read-only reference).
- legacy_ios/              — EusoTrip 2006 iPhone prototype (do not edit).
- backend_backup/, backend_broken/, backend_ai_variant/ — Archaeology.
- brand/                   — Brand guidelines and logos.
- security_docs/           — Security architecture references.

## Backend
- URL: https://eusotrip-app.azurewebsites.net
- Deploy: `cd backend/frontend && npm run deploy:azure`
- Migrations: Drizzle; SQL in backend/frontend/drizzle/

## iOS
- Build: open `ios/EusoTrip.xcodeproj` in Xcode 16+, scheme `EusoTrip`
- Maps: HERE Maps via ios/EusoTrip/Services/HereMaps/
- Assets: ios/EusoTrip/Assets.xcassets/

## Engineering rules
1. TDD or it didn't happen. No router lands without a `__tests__` sibling.
2. No MCP servers at runtime. MCPs are dev-time only.
3. No mock data shipped. Kill any `MOCK_`, stub, or placeholder before merge.
4. Every feature touches: doctrine/ (spec), wireframes/ (UI), backend/ (API + schema),
   ios/ (SwiftUI view + view model), and a test.
5. Update ledger.json on every merged brick-port.
6. Autorun killer firings tracked in killers/ and reported under
   ~/Desktop/EUSOTRIP_AUTORUN_*_REPORT.md.

## Doctrine entry point
Start with doctrine/00_README.md, then doctrine/02_Engineering_Principles.md.
```

Drop that file in workspace root. Every future `claude` session in that folder starts oriented.

---

## 6. Per-repo `.claude/settings.json`

Each real repo should have its own `.claude/settings.json`. Tiny, committed to git so every engineer's Claude behaves identically.

### 6.1 `~/Desktop/eusoronetechnologiesinc/.claude/settings.json`
```json
{
  "projectName": "eusotrip-backend",
  "defaultModel": "claude-opus-4-7",
  "permissions": {
    "allow": ["Read", "Grep", "Glob", "Edit", "Bash(npm:*)", "Bash(git:*)", "Bash(npx drizzle-kit:*)"],
    "deny": ["Bash(rm -rf:*)", "Bash(sudo:*)"]
  },
  "env": {
    "NODE_ENV": "development"
  }
}
```

### 6.2 `~/Desktop/EusoTrip by Eusorone Technologies, Inc/.claude/settings.json`
```json
{
  "projectName": "eusotrip-ios",
  "defaultModel": "claude-opus-4-7",
  "permissions": {
    "allow": ["Read", "Grep", "Glob", "Edit", "Bash(xcodebuild:*)", "Bash(git:*)", "Bash(swift:*)"],
    "deny": ["Bash(rm -rf:*)", "Bash(sudo:*)"]
  }
}
```

---

## 7. Git hooks + pre-commit

Both repos install same three-hook set (via Husky or plain `.git/hooks/pre-commit` symlinked from versioned `scripts/hooks/`):

1. **`no-mock-data`** — grep for `MOCK_, TODO:FAKE, placeholder` in staged files; fail if found. Enforces CLAUDE.md rule 3.
2. **`tests-exist`** — for every new `server/routers/*.ts`, require sibling `server/routers/__tests__/*.test.ts`. Enforces rule 1.
3. **`ledger-touch`** — if any file under `drizzle/` changed, require `EUSOTRIP_TRAJECTORY.json` to have been touched in same commit. Enforces rule 5.

Matching pre-push hook runs `npm run typecheck && npm test` on backend + `xcodebuild -scheme EusoTrip -destination 'generic/platform=iOS' build` on iOS.

---

## 8. MCP server — `eusorone-web-apps`

For Claude Code sessions needing live read access to backend (list_users, search_loads, wallet_overview, hos_status, etc. against deployed `eusotrip-app.azurewebsites.net`), add the `eusorone-web-apps` MCP.

**Server ID**: `6c5de60a-5b32-4f8d-b10b-9d1b20193d02`.

Exposes ~80 backend tools: `search_loads, search_drivers, search_companies, dispatch_board, hos_status, wallet_overview, fmcsa_carrier_safety, factoring_overview, rate_comparison`, full cross-border + rail + vessel + control-tower suite.

Add per MCP registry instructions once per machine. **Dev-time only; remember rule 2 — nothing from MCP ships in binary.**

---

## 9. Alternate editors (VS Code, Cursor, Windsurf)

Not every engineer lives in CLI. Same workspace folder, different front end.

- **VS Code**: `code ~/Desktop/eusotrip-workspace`. Install Claude extension from marketplace; reads same `CLAUDE.md` + `.claude/settings.json`. Symlinks resolve natively.
- **Cursor**: `cursor ~/Desktop/eusotrip-workspace`. Follows symlinks. Use built-in Claude model picker; point at `claude-opus-4-7`.
- **Windsurf**: `windsurf ~/Desktop/eusotrip-workspace`. Cascade agent respects same `CLAUDE.md`.

Shared `CLAUDE.md` means all four tools (CLI, VS Code, Cursor, Windsurf) give engineer same Claude with same context. Choice of editor becomes cosmetic.

---

## 10. New-engineer onboarding checklist (ten steps)

Print. Tape to monitor. Check each box.

1. Install Claude Code: `brew install claude-code` (or official installer).
2. Authenticate: `claude login` using `@eusorone.com` identity.
3. Pull two primary repos into `~/Desktop/eusoronetechnologiesinc/` and `~/Desktop/EusoTrip by Eusorone Technologies, Inc/`.
4. Pull `~/Desktop/EusoTrip 2027 UI/` + `~/Desktop/doctrine_wave1/`.
5. Run symlink-hub setup in §3.1.
6. Drop `CLAUDE.md` from §5 into `~/Desktop/eusotrip-workspace/`.
7. Add `eusorone-web-apps` MCP (§8).
8. Install git hooks in both repos (§7).
9. Open Claude Code: `cd ~/Desktop/eusotrip-workspace && claude`.
10. Ask Claude: *"Read doctrine/00_README.md and doctrine/02_Engineering_Principles.md and summarize my first story."* If Claude can read both, you are online.

---

## 11. Escape hatches — when Claude gets confused

Symptoms: Claude edits wrong repo, or insists file doesn't exist when it does, or mixes iOS and backend code in one patch.

Fixes:

- **`/cwd`** — ask Claude to confirm working directory. Wrong one → you opened from wrong shell. Exit, `cd` properly, re-open.
- **Explicit prefixing** — start every request with `In ios/...` or `In backend/...` to pin intent. Claude respects these anchors.
- **Fresh session** — symlink resolution + working-directory state are session-bound. When in doubt, `Ctrl-D` and `claude` again.
- **Drop `--add-dir`, switch to workspace** — `--add-dir` paths can get stale if underlying dir moves. Symlink hub is more robust.
- **Re-read CLAUDE.md** — paste *"Please re-read CLAUDE.md"* into chat. Claude refreshes mental map.
- **Switch repo mid-session** — paste *"From now on, work only in backend/. Ignore ios/ for this thread."* Claude holds to it.

---

## 12. The command, one more time

**For the daily driver** (once hub is set up per §3):

```bash
cd "$HOME/Desktop/eusotrip-workspace" && claude
```

**For strict backend-only session** this doctrine was also asked to bless:

```bash
cd "$HOME/Desktop/eusoronetechnologiesinc" && claude
```

**For the one-off multi-repo session** without building the hub:

```bash
claude \
  --add-dir "$HOME/Desktop/EUSOTRIP" \
  --add-dir "$HOME/Desktop/AI/eusoronetechnologiesinc" \
  --add-dir "$HOME/Desktop/EusoTrip 2006 for iPhone" \
  --add-dir "$HOME/Desktop/eusoronetechnologiesinc_backup" \
  --add-dir "$HOME/Desktop/EusoTrip Mobile App Doctrine 2027" \
  --add-dir "$HOME/Desktop/doctrine_wave1" \
  --add-dir "$HOME/Documents/Claude/Scheduled/eusotrip-killers"
```

Both of the first two are official. The first is what you want 95% of the time. The second is what you want when the story is a pure-backend migration, a Drizzle schema change, or an Azure deploy drill — and nothing else. The third is for when the primary `EusoTrip by Eusorone Technologies, Inc/` + `eusoronetechnologiesinc/` trees haven't been pulled yet on this machine and you need to work from what's currently available.

**That is the entirety of the Claude Code initialization doctrine. Every engineer, every machine, every session.**

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
