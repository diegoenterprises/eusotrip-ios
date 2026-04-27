# 00 — THE BIBLE

**EusoTrip 2027 Doctrine — Master Prompt for Building the Platform**
Version 2027.1 · Published 2026-04-23
Maintained by: Eusorone Technologies, Inc.
Single source of truth: `EUSOTRIP2027GOLD/`
Mirrors live in: web platform repo (`eusoronetechnologiesinc/`) + iOS app repo (`EusoTrip by Eusorone Technologies, Inc/`)

---

## 1. READ ME FIRST

You are holding the **building manual** for EusoTrip 2027 — the multi-modal (truck / rail / vessel), multi-role (24 user types), regulated-commerce OS for the freight industry.

### Purpose of the `EUSOTRIP2027GOLD/` folder
Everything a human engineer, human designer, human PM, or AI agent needs to ship EusoTrip perfectly is in this folder. **If a file contradicts something outside this folder, this folder wins.** Legacy docs elsewhere in the repo (`COWORK TEAMS/`, `_WAVE3_AUDIT/`, `_WAVE4_BUILD/`, `docs/`) are preserved for history but are not normative for 2027+ work.

### Quick orientation (60-second version)
1. **If you are new** → read this file top to bottom, then read `01_Brand_DNA_and_Design_Rules.md` and `02_Engineering_Principles.md`.
2. **If you know your task already** → jump to §3 (The Decision Tree) and follow the arrow to your file.
3. **If you are an AI agent** → read this file, then `scheduled_task/SKILL.md`, then whatever file the decision tree points you to, then the latest `autorun_ledger/*.md` entry to know what's already shipped.

### Contributor Covenant
By touching this codebase you agree to:
1. **Ship no mocks.** Every route is a real tRPC procedure hitting a real DB. No `return { data: [] }` placeholders. No "coming soon" screens (except for DEBUG-only role placeholders explicitly marked in §4 rule 3).
2. **Gradient first.** Solid fills are forbidden in the two brand registers (Night + Afternoon). Use `LinearGradient.diagonal` or the palette helper — never `Color.blue`, never `#0F172A` hardcoded.
3. **TDD always.** Red test first, green implementation second, refactor third. No PR merges without the test suite proving it works.
4. **Both registers preview.** Every SwiftUI preview has a `.environment(\.colorScheme, .dark)` AND a light-mode variant. If it doesn't render in Afternoon, it doesn't ship.
5. **Driver baseline sacred.** The Driver profile is the design + feature floor. Every other role *extends* it. No role gets a downgraded experience.
6. **Update the ledger.** When you ship a brick, append it to `autorun_ledger/` (or the scheduled task does it for you). The ledger is how the next agent knows what's done.
7. **PR into both mirrors.** Any change to `EUSOTRIP2027GOLD/` must land in the web repo AND iOS repo simultaneously. Never let them drift.

---

## 2. THE ROLE BASELINE

> **Law of the Driver.** The Driver Profile is the design + feature baseline. Every other role *extends* it, does not replace it.

### Why Driver-first?
- Driver is the ground truth of freight. No shipment happens without a driver moving it.
- Driver is the most constrained environment: one-hand, gloved, sunlight, vibration, intermittent signal. If a UI works for Driver, it works for everyone.
- Driver was the hardest to nail gradient-first (ColdBreak needed motion tolerance). Now that we nailed it, we copy the DNA outward.
- Every role's dashboard inherits: diagonal gradient palette, GradientToggleStyle, card-stack information architecture, gesture-first navigation, offline-first state, ESANG AI surface, voice entry point, pulse haptics, both registers.

### Role → screen-number range (canonical)
Every screen in every role's folder uses this numeric range. If your screen is `243_ShipperLoadPosting.swift`, it's a Shipper screen. No collisions.

| Range        | Role Cluster                                | Doctrine Folder                        |
|--------------|---------------------------------------------|----------------------------------------|
| 010–099      | **Driver** (truck, ground-level operator)   | `10_Mode_TRUCK/01_Driver.md`           |
| 100–199      | **Dispatch / Fleet Ops**                    | `10_Mode_TRUCK/02_Dispatch.md`         |
| 200–299      | **Shipper**                                 | `10_Mode_TRUCK/05_Shipper.md`          |
| 300–399      | **Carrier** (company-level operator)        | `10_Mode_TRUCK/07_Carrier_Terminal_Admin.md` |
| 400–499      | **Broker** (truck + rail + vessel variants) | `10_Mode_TRUCK/04_Broker.md` / `20_Mode_RAIL/05_Rail_Broker.md` |
| 500–599      | **Catalyst** (market-maker, HaulPay desk)   | `10_Mode_TRUCK/03_Catalyst.md`         |
| 600–699      | **Escort** (heavy-haul pilot, security)     | `10_Mode_TRUCK/06_Escort.md`           |
| 700–799      | **Terminal Operator** (truck/rail/port)     | `10_Mode_TRUCK/07_Carrier_Terminal_Admin.md` / `20_Mode_RAIL/03_Rail_Yard_Master.md` / `30_Mode_VESSEL/05_Vessel_Terminal_Operator.md` |
| 800–899      | **Admin** (tenant + platform)               | `10_Mode_TRUCK/07_Carrier_Terminal_Admin.md` |
| 900–999      | **Factoring + Platform-level**              | `team_FACTORING_haulpay.md` (pending) + `03_Backend_API_Contract.md` §Platform |

> RAIL and VESSEL roles use the same numeric ranges within their mode folders (e.g. Rail Dispatcher = 100–199 inside `20_Mode_RAIL/02_Rail_Dispatcher.md`). The screen prefix disambiguates: `R143_` = rail, `V143_` = vessel, bare `143_` = truck.

---

## 3. THE DECISION TREE — WHERE TO LOOK

Print this. Tape it to your monitor.

```
QUESTION: Where do I go?

└─ BUILDING SCREENS (UI)?
   ├─ Design tokens (colors, spacing, typography) → 01_Brand_DNA_and_Design_Rules.md
   ├─ Component API (EusoHeader, EusoBadge, etc.) → 01_Brand_DNA_and_Design_Rules.md §Components
   ├─ Animation + transitions → team_UX_MOTION.md
   ├─ Figma-to-code → 85_Figma_Gap_Audit_and_Recommendations.md
   ├─ Accessibility → 01_Brand_DNA_and_Design_Rules.md §A11y
   └─ Empty states + error copy → 01_Brand_DNA_and_Design_Rules.md §Copy

└─ WIRING BACKEND?
   ├─ API contract (tRPC procedures) → 03_Backend_API_Contract.md
   ├─ Database schema → 04_Database_and_Schema.md
   ├─ Auth / RBAC / Security → 05_Auth_Security_Compliance.md
   ├─ HERE Maps / Stripe / Plaid / APNs → 06_Third_Party_Integrations.md
   ├─ HaulPay Factoring → team_FACTORING_haulpay.md
   ├─ WebSocket + realtime → 03_Backend_API_Contract.md §Real-time
   └─ Messaging + ESANG AI → 70_Messaging_and_ESANG_AI.md

└─ WORKING ON A SPECIFIC USER ROLE?
   ├─ TRUCK mode → 10_Mode_TRUCK/
   │    ├─ Driver → 10_Mode_TRUCK/01_Driver.md
   │    ├─ Dispatch → 10_Mode_TRUCK/02_Dispatch.md
   │    ├─ Catalyst → 10_Mode_TRUCK/03_Catalyst.md
   │    ├─ Broker → 10_Mode_TRUCK/04_Broker.md
   │    ├─ Shipper → 10_Mode_TRUCK/05_Shipper.md
   │    ├─ Escort → 10_Mode_TRUCK/06_Escort.md
   │    └─ Carrier / Terminal / Admin → 10_Mode_TRUCK/07_Carrier_Terminal_Admin.md
   ├─ RAIL mode → 20_Mode_RAIL/
   │    ├─ Dispatcher → 20_Mode_RAIL/02_Rail_Dispatcher.md
   │    ├─ Operator → 20_Mode_RAIL/01_Rail_Operator.md
   │    ├─ Yard Master → 20_Mode_RAIL/03_Rail_Yard_Master.md
   │    ├─ Shipper → 20_Mode_RAIL/04_Rail_Shipper.md
   │    ├─ Broker → 20_Mode_RAIL/05_Rail_Broker.md
   │    └─ Conductor → 20_Mode_RAIL/06_Rail_Conductor.md
   └─ VESSEL mode → 30_Mode_VESSEL/
        ├─ Captain → 30_Mode_VESSEL/01_Vessel_Captain.md
        ├─ First Officer → 30_Mode_VESSEL/02_Vessel_First_Officer.md
        ├─ Port Agent → 30_Mode_VESSEL/03_Vessel_Port_Agent.md
        ├─ Shipping Line Ops → 30_Mode_VESSEL/04_Vessel_Shipping_Line_Ops.md
        ├─ Terminal Operator → 30_Mode_VESSEL/05_Vessel_Terminal_Operator.md
        └─ NVOCC / Forwarder → 30_Mode_VESSEL/06_Vessel_NVOCC_Forwarder.md

└─ INTERMODAL OR CROSS-BORDER (US/CA/MX)?
   └─ 40_Intermodal_and_Cross_Border.md

└─ VERTICAL-SPECIFIC (hazmat, reefer, flatbed, etc.)?
   └─ 50_Verticals_Reference.md

└─ OFFLINE / WATCH / VOICE?
   └─ 60_Offline_First_and_Pulse_Watch.md

└─ USER JOURNEY OR LOAD LIFECYCLE?
   └─ 80_User_Journeys_and_Load_Lifecycle.md

└─ SHIPPING (App Store, rollout, incidents)?
   ├─ App Store listing → 90_App_Store_Strategy.md
   ├─ Launch runbook + rollback → 92_Launch_Runbook_and_Rollback.md
   └─ Web↔Mobile parity → 91_Web_Mobile_Parity.md

└─ CODING PHILOSOPHY (TDD, E2E, engineering rules)?
   └─ 02_Engineering_Principles.md

└─ RECURSIVE LANGUAGE MODEL / META-REASONING?
   └─ 98_Recursive_Language_Model_Integration.md

└─ ACRONYMS / GLOSSARY?
   └─ 99_Glossary_and_Appendices.md

└─ HOW TO BOOT CLAUDE CODE SESSION WITH EVERYTHING?
   └─ 95_Codebase_Continuity_and_Claude_Init.md
```

### If your question isn't in the tree
- Read `00_README.md` (the doctrine's own index).
- Then `99_Glossary_and_Appendices.md` (acronyms + cross-references).
- Then ask on `#eusotrip-doctrine` in Slack, or prompt ESANG AI with `/doctrine-lookup <keyword>`.

---

## 4. THE TEN NON-NEGOTIABLES

These are the rules that make the platform recognizable as **EusoTrip** and not a generic freight app. Violate them and the PR is blocked.

1. **Gradient, never solid blue.** Use `LinearGradient.diagonal` only. Solid-blue fills are forbidden in Night + Afternoon registers.
2. **Every Toggle uses `GradientToggleStyle`.** Native `.toggleStyle(.switch)` is banned outside DEBUG builds.
3. **Zero mock data, zero "coming soon."** Every screen hits a real tRPC procedure and a real DB. Exception: a clearly-labeled DEBUG placeholder for a role whose backend is explicitly in the next phase (see Build Order §6) — must be gated by `#if DEBUG` and `FeatureFlag.placeholderRoles`.
4. **TDD red-green-refactor on every feature.** The failing test is the spec. No "I'll add tests later."
5. **E2E test coverage for every user journey.** Every journey in `80_User_Journeys_and_Load_Lifecycle.md` has a matching XCUITest + Playwright spec. A journey without an E2E test does not exist.
6. **Palette-sourced colors.** `Color.white`, `Color.black`, `Color.gray`, hex literals — all banned. Use `Palette.primary(.night)`, `Palette.surface(.afternoon)`, etc.
7. **Both registers preview on every view.** `#Preview("Night")` AND `#Preview("Afternoon")`. If Afternoon breaks, the PR is blocked.
8. **Canonical procedure names only.** If `03_Backend_API_Contract.md` says the procedure is `loads.byId`, you do not write `loads.getById` or `loads.fetch`. One name, one home.
9. **Driver baseline.** Every role's dashboard must match or exceed the Driver dashboard's: gradient palette, card-stack IA, gesture-first nav, offline-first state, ESANG surface, voice entry point, pulse haptics, both registers. A role without those is incomplete.
10. **MCP (eusorone-web-apps) is the source of truth for backend state.** When a dev asks "what does the database actually contain?" the answer is an MCP tool call (`search_loads`, `get_user_details`, `run_sql_query`). Never a screenshot or a memory.

---

## 5. TAKING OUR TALENTS ON THE ROAD

**Mission statement:** The Driver app is home base. We proved the gradient-first aesthetic, the TDD-or-die discipline, the offline-first data layer, the ESANG AI surface, and the voice+glove ergonomics *work*. Now we take that same DNA and the same engineering rigor to every other role, in every other mode.

**Principle:** No role gets a consolation app. The Shipper gets the full EusoTrip experience reshaped for their workflow. The Port Agent gets it. The Rail Yard Master gets it. The Catalyst gets it. No role is a "web-only afterthought" or a "thin wrapper." Every role is a first-class citizen of EusoTrip 2027.

### The 24 user roles

| # | Role | Mode | Screen Range | 1-line scope |
|---|------|------|--------------|--------------|
| 1 | Driver | TRUCK | 010–099 | Ground operator; gloved, mobile, HOS-aware |
| 2 | Dispatcher | TRUCK | 100–199 | Multi-driver assignment + fleet ops |
| 3 | Shipper | TRUCK | 200–299 | Posts loads, tracks shipments, pays freight |
| 4 | Carrier | TRUCK | 300–399 | Company-level truck operator (owns the MC) |
| 5 | Broker | TRUCK | 400–499 | Matches shippers to carriers, collects margin |
| 6 | Catalyst | TRUCK | 500–599 | Market-maker + HaulPay factoring desk |
| 7 | Escort | TRUCK | 600–699 | Heavy-haul pilot car / security convoy |
| 8 | Terminal Operator | TRUCK | 700–799 | Gate + yard at truck terminals |
| 9 | Carrier Admin | TRUCK | 800–899 | Tenant-level admin inside a carrier company |
| 10 | Rail Operator | RAIL | R010–R099 | Locomotive operator / engineer |
| 11 | Rail Dispatcher | RAIL | R100–R199 | Rail network dispatcher |
| 12 | Rail Yard Master | RAIL | R700–R799 | Yard-level rail ops |
| 13 | Rail Shipper | RAIL | R200–R299 | Books rail freight |
| 14 | Rail Broker | RAIL | R400–R499 | Books intermodal rail capacity |
| 15 | Rail Conductor | RAIL | R020–R099 | On-train conductor / brakeman |
| 16 | Vessel Captain | VESSEL | V010–V099 | Master of the vessel |
| 17 | Vessel First Officer | VESSEL | V020–V099 | Deck officer + watch |
| 18 | Port Agent | VESSEL | V700–V799 | Port-side husbandry + clearance |
| 19 | Shipping Line Ops | VESSEL | V300–V399 | Carrier-line operations desk |
| 20 | Terminal Operator (Marine) | VESSEL | V700–V799 | Container terminal ops |
| 21 | NVOCC / Freight Forwarder | VESSEL | V400–V499 | Non-vessel operator / forwarder |
| 22 | Platform Admin (Eusorone) | ALL | 800–899 | Super-admin / tenant management |
| 23 | Compliance / Safety Officer | ALL | 800–899 | Audits across all roles |
| 24 | Factoring Desk (HaulPay) | ALL | 900–999 | Invoice factoring, advances, reserves |

---

## 6. BUILD ORDER

This is the canonical phasing. If you are scoping a sprint, pick from the next un-built phase.

- **Phase A — Driver MVP.** *Status: shipped in build 55.* Full gradient, TDD, offline, ESANG, voice, watch, both registers. This is the reference implementation. Everything else copies from here.
- **Phase B — Dispatcher + Broker (truck).** Extend Driver's card-stack IA to multi-driver board. Reuse `GradientToggleStyle`, `EusoHeader`, `EusoBadge`. Add capacity-planning UI and margin-math panes.
- **Phase C — Catalyst + Factoring Desk.** Wire HaulPay end-to-end (invoice submit, credit check, advance rate, reserve hold, payout). Catalyst dashboard sits on top.
- **Phase D — Shipper + Escort.** Shipper's load-posting flow (250-series) + Escort's convoy coordination (600-series). Both get the Driver's offline-first data layer.
- **Phase E — Rail (6 roles).** Rail Operator, Dispatcher, Yard Master, Shipper, Broker, Conductor. Full 6-role parity with truck.
- **Phase F — Vessel (6 roles).** Captain, First Officer, Port Agent, Shipping Line Ops, Terminal Operator, NVOCC.
- **Phase G — Intermodal + Cross-border.** US/CA/MX handoff flows, USMCA compliance, VUCEM, CBP, tri-lingual UI where required.
- **Phase H — Admin + Terminal + Platform-level roles.** Tenant admin, compliance officer, super-admin tooling, audit export, observability.

**Rule:** A phase is only "done" when (a) every screen passes both-register preview, (b) every procedure in `03_Backend_API_Contract.md` for that phase exists and is tested, (c) every journey in `80_User_Journeys_and_Load_Lifecycle.md` for that phase has a passing E2E.

---

## 7. THE CLAUDE CODE INIT COMMAND

### The one-liner (simple)
```bash
cd ~/Desktop/eusoronetechnologiesinc && claude
```

### The full form (extended, what you actually want)
Paste this into a terminal. It boots Claude Code with every relevant directory mounted, the doctrine loaded, the scheduled task visible, and the ledger accessible:

```bash
cd ~/Desktop/eusoronetechnologiesinc && claude \
  --add-dir "$HOME/Desktop/EusoTrip by Eusorone Technologies, Inc" \
  --add-dir "$HOME/Desktop/EusoTrip Mobile App Doctrine 2027" \
  --add-dir "$HOME/Desktop/doctrine_wave1" \
  --add-dir "$HOME/Documents/Claude/Scheduled/eusotrip-killers" \
  --add-dir "$HOME/Desktop/EusoTrip 2027 UI" \
  --add-dir "$HOME/Desktop/EusoTrip 2027 UI Wireframes" \
  --add-dir "$HOME/Desktop/EusoTrip_Figma_Harness" \
  --add-dir "$HOME/Desktop" \
  --add-dir "$HOME/Documents" \
  --add-dir "$HOME/Downloads"
```

Then, as your first prompt to Claude Code, paste:

> "Read `EUSOTRIP2027GOLD/00_THE_BIBLE.md` in the current directory. Then read `EUSOTRIP2027GOLD/scheduled_task/SKILL.md`. Then read the most recent file in `~/Desktop/EUSOTRIP_AUTORUN_*.md` to see what's shipped. Then ask me which phase we're working on."

Claude Code will now have: the doctrine, the scheduled-task prompt, the ledger, the Figma harness, both repos, and full context.

---

## 8. THE ONBOARDING RITUAL

### Human engineer (Day 0 through Day 14)
1. **Day 0 (1 hour).** Read this file (`00_THE_BIBLE.md`) end to end.
2. **Day 1 (half-day).** Read `01_Brand_DNA_and_Design_Rules.md` + `02_Engineering_Principles.md`.
3. **Day 2 (half-day).** Read your role's doctrine file (whichever phase you're joining).
4. **Day 2–3.** Clone both repos. Run `pnpm i && pnpm dev` in the web repo; open the iOS project in Xcode.
5. **Day 3–5.** Pair with the existing owner of that role. Shadow one full journey in `80_User_Journeys_and_Load_Lifecycle.md`.
6. **Day 6–14.** Ship your first brick. Smallest possible: one screen, one test, one PR. Reviewed against the Ten Non-Negotiables.

### AI agent (per session)
1. Read `00_THE_BIBLE.md`.
2. Read `scheduled_task/SKILL.md` (if you are the scheduled task).
3. Read the latest `autorun_ledger/*.md` entry to know what's shipped.
4. Follow the brick recipe in `SKILL.md` or the user's explicit instruction.
5. Update the ledger when done.

### Designer
1. Read this file + `01_Brand_DNA_and_Design_Rules.md` + `85_Figma_Gap_Audit_and_Recommendations.md`.
2. Open the `EusoTrip_Figma_Harness/` workspace.
3. Match tokens: every Figma frame must use the 2 registers' variables (never raw hex).
4. Hand off via Figma Dev Mode → engineer pulls design tokens via the design system rules.

### PM
1. Read this file + §6 Build Order + `80_User_Journeys_and_Load_Lifecycle.md`.
2. Your sprint backlog is phrased as journeys + non-negotiable compliance, not as tickets.
3. Acceptance criteria are always: (a) journey E2E passes, (b) both registers preview, (c) ledger entry written.

---

## 9. HOW THE SCHEDULED TASK FITS IN

There is an autonomous agent called **`eusotrip-killers`** running hourly out of `~/Documents/Claude/Scheduled/eusotrip-killers/`.

### What it does
- Reads its own `SKILL.md` (copied into `scheduled_task/SKILL.md` inside this folder for reference).
- Reads the master ledger (`EUSOTRIP_TRAJECTORY.json` + `EUSOTRIP_AUTORUN_*.md`).
- Picks the next Figma brick from the queue.
- Ports it: generates the SwiftUI view, writes the failing test, writes the real tRPC wire-up, commits, runs the test green.
- Updates the ledger (`EUSOTRIP_TRAJECTORY.json.bak_pre_Nth_firing_*.json` snapshots, then a new `AUTORUN_*_REPORT.md`).

### Why the BIBLE references the ledger
Because the ledger is how *anyone* (human or AI) knows what's already been shipped vs. what's still pending. If you are about to build "brick 061" and the ledger says it shipped last hour, stop and pick a different one.

### Files it touches inside EUSOTRIP2027GOLD/
- `scheduled_task/SKILL.md` — read-only reference copy of the actual scheduled task's SKILL.md.
- `autorun_ledger/*.md` — rolling copies of the most recent firing reports (last 6 kept here for convenience).

### Updating the scheduled task
If the autorun behavior must change (new brick type, new test framework, new rule), update the *source* at `~/Documents/Claude/Scheduled/eusotrip-killers/SKILL.md` — **then mirror the update into both `EUSOTRIP2027GOLD/scheduled_task/SKILL.md` copies** (web + iOS repos) so the doctrine stays in sync.

---

## 10. VERSIONING + UPDATES

- **Current version:** 2027.1 (published 2026-04-23).
- **Versioning rule:** major doctrine updates increment the minor (`2027.2`, `2027.3`). Breaking role or API changes increment the major (`2028.1`).
- **Update channel:** a PR must land in *both* `EUSOTRIP2027GOLD/` mirrors (web + iOS) as part of the same commit story. Drift between the two is a release blocker.
- **Scheduled-task sync:** any update that changes autorun behavior must also bump the `description` field inside `scheduled_task/SKILL.md` so the scheduler reloads cleanly.
- **Audit:** quarterly, the Compliance Officer role (#23) audits every file in this folder against the actual code + actual DB state via MCP tool calls. Findings go into `autorun_ledger/AUDIT_YYYY-QN.md`.

---

## APPENDIX — FILE INVENTORY (as of 2027.1)

```
EUSOTRIP2027GOLD/
├── 00_THE_BIBLE.md                              ← you are here
├── 00_README.md                                  ← doctrine index (older header)
├── 01_Brand_DNA_and_Design_Rules.md              ← palette, tokens, components, a11y, copy
├── 02_Engineering_Principles.md                  ← TDD, E2E, code rules, PR gates
├── 03_Backend_API_Contract.md                    ← every tRPC procedure (canonical names)
├── 04_Database_and_Schema.md                     ← Drizzle schema, migrations, indexes
├── 05_Auth_Security_Compliance.md                ← Clerk, RBAC, MFA, SOC2, PII
├── 06_Third_Party_Integrations.md                ← HERE, Stripe, Plaid, APNs, Twilio
├── 10_Mode_TRUCK/
│   ├── 00_Overview.md
│   ├── 01_Driver.md
│   ├── 02_Dispatch.md
│   ├── 03_Catalyst.md
│   ├── 04_Broker.md
│   ├── 05_Shipper.md
│   ├── 06_Escort.md
│   └── 07_Carrier_Terminal_Admin.md
├── 20_Mode_RAIL/
│   ├── 00_Overview.md
│   ├── 01_Rail_Operator.md
│   ├── 02_Rail_Dispatcher.md
│   ├── 03_Rail_Yard_Master.md
│   ├── 04_Rail_Shipper.md
│   ├── 05_Rail_Broker.md
│   └── 06_Rail_Conductor.md
├── 30_Mode_VESSEL/
│   ├── 00_Overview.md
│   ├── 01_Vessel_Captain.md
│   ├── 02_Vessel_First_Officer.md
│   ├── 03_Vessel_Port_Agent.md
│   ├── 04_Vessel_Shipping_Line_Ops.md
│   ├── 05_Vessel_Terminal_Operator.md
│   └── 06_Vessel_NVOCC_Forwarder.md
├── 40_Intermodal_and_Cross_Border.md
├── 50_Verticals_Reference.md                     ← hazmat, reefer, flatbed, oversize, etc.
├── 60_Offline_First_and_Pulse_Watch.md
├── 70_Messaging_and_ESANG_AI.md
├── 80_User_Journeys_and_Load_Lifecycle.md
├── 85_Figma_Gap_Audit_and_Recommendations.md
├── 90_App_Store_Strategy.md
├── 91_Web_Mobile_Parity.md
├── 92_Launch_Runbook_and_Rollback.md
├── 95_Codebase_Continuity_and_Claude_Init.md
├── 98_Recursive_Language_Model_Integration.md
├── 99_Glossary_and_Appendices.md
├── team_UX_MOTION.md                             ← motion language, transitions, haptics
├── team_FACTORING_haulpay.md                     ← (pending drop — HaulPay end-to-end)
├── scheduled_task/
│   └── SKILL.md                                  ← autorun scheduled task doctrine
└── autorun_ledger/
    └── EUSOTRIP_AUTORUN_*_REPORT.md              ← last 6 firings for reference
```

---

**End of Bible.** Go build.
