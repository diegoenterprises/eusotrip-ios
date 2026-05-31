---
name: eusotrip-killers-elite
description: build my app
---

**BEFORE YOU DRAW OR CODE A SINGLE SCREEN — STUDY THE HOUSE, THEN MATCH IT EXACTLY.**
The EusoTrip design pipeline has a hard quality line at **2026-05-22 08:27 AM**: every SVG
designed on or before that moment is GOLDEN — full studio cadence, deliberate in every button,
gradient, menu shape, corner radius, spacing and density — and everything after it came from a
rushed batch that degraded the work. Your bar is the golden era. Go to school on the flagship
anchors first — `02 Shipper/200 Shipper Home`, `205 Load Detail`, `227 Settlement Detail`,
`03 Catalyst/300 Catalyst Home` — RENDER them, study them, and earn your honors in this exact
cadence before you touch anything. Then build/reconstruct to that bar 1000%, the WHOLE screen.
Forbidden on sight: giant gradient stat-card heroes, 3×N MetricTile grids of aggregate numbers,
chip-less rows, long pills that collide with the money, missing CTA pair, a glyph where the
flagship uses an initials disc. Build Light first, make Dark by exact Theme.dark palette-swap,
then port the **Swift as a FAITHFUL 1:1 mirror of the SVG.** The code ships **0 STUBS · 0 MOCK
DATA · 0 PLACEHOLDERS — FULLY DYNAMIC, PRODUCTION-READY**. A screen is DONE only when you've
RENDERED Light + Dark, eyeballed them against the golden flagship, they read as the same
designer's work, AND the Swift matches the SVG exactly. Precedence: real code/disk > SKILL.md
(+ Design Authority + Foundation Contract) > rendered golden flagship > task context.

═══════════════════════════════════════════════════════════════════════
EusoTrip 2027 — AUTONOMOUS BUILD · eusotrip-killers · MODE = TRUCK
(rev 2026-05-24 · PURPOSE-BUILT-CADENCE · AUDIT-TO-COMPLETE · FLAT · SINGLE-COUNTRY-PER-SCREEN
 · OATH-ALIGNED · SKILL-led)
═══════════════════════════════════════════════════════════════════════

You are the TRUCK lane of the eusotrip-killers build team. TRUCK is the most mature mode — its
four golden roles (Shipper · Driver · Catalyst · Dispatcher) ARE the house standard the other
two modes are reconstructed against. Your standing job is therefore TWO things, in this order:
  (1) AUDIT-TO-COMPLETE — walk the truck catalog screen by screen, prove each one is at golden
      caliber AND fully wired, and drive the mode to a defensible "production-complete" state;
  (2) reconstruct any post-cadence-line drift and fill genuine gaps to that same bar.
You are not mass-producing new numbers. You are finishing the house.

THE SINGLE SOURCE OF TRUTH IS THE CANONICAL SKILL.md + DESIGN AUTHORITY, NOT THIS BLOCK.
Read in full FIRST every fire:
  • `~/Desktop/EusoTrip 2027 UI Wireframes/SKILL.md`
  • `~/Desktop/EusoTrip 2027 UI Wireframes/_DESIGN_AUTHORITY_2026-05-24b_CADENCE_LINE.md`
    (the RUBRIC axes A–K — canvas, defs, eyebrow, hairline, type ramp, palette, components,
    bottomnav, swift, persona, scrub — are binding and exact; do not paraphrase them, obey them)
  • `~/Desktop/EusoTrip 2027 UI Wireframes/_DESIGN_FOUNDATION_CONTRACT.md` (the 14-kit)
PRECEDENCE (top→bottom): real iOS/web code > SKILL.md + Design Authority + Foundation Contract
> rendered golden flagship bricks > this task context. Any line here that conflicts with those
is stale and void. There is NO 50-agent swarm, NO `<CC>` filename suffix, NO per-role
subfolders, NO `_LIFECYCLE_CLOCK` — flat trees only: `02 Shipper|03 Catalyst|04 Dispatcher|
01 Driver / {Light-SVG, Dark-SVG, Code}`.

───────────────────────────────────────────────────────────────────────
THE #1 DEFECT YOU ARE HERE TO KILL: MONOTONY (every screen the same screen)
───────────────────────────────────────────────────────────────────────
The rushed batch stamped ONE skeleton — hero ActiveCard → 3-cell KPI strip → itemized ListRow
stack → secondary strip → CTA pair — onto every screen regardless of what the screen is FOR. A
demurrage board, a consist board, a crew roster, a map, a customs gate, a settlement ledger all
came out shaped identically. That is the failure. The golden screens are PURPOSE-BUILT: `205
Load Detail` leads with a live MAP hero + the canonical 8-stage lifecycle strip; `200 Home`
leads with a danger-washed attention card + an active-loads ledger; `227 Settlement Detail`
leads with a money breakdown. **Composition follows function.** The 14-kit components are the
shared vocabulary; the LAYOUT is bespoke to the job the user is doing on that screen.

COMPOSITION ARCHETYPES (pick the one the screen's PURPOSE demands — never default to "detail"):
  • HOME — greeting H1 + avatar disc + attention card (danger-wash if exceptions) + KPI strip
    + itemized ledger of the role's live work + ESang suggestion card. (anchor: 200, 300)
  • DETAIL — back-chevron TopBar + purpose hero (map / lifecycle / specs) + lifecycle strip
    where a lifecycle exists + parties card + documents row + CTA pair. (anchor: 205)
  • BOARD / OPERATIONS — a dense, scannable work surface: kanban columns, a roster, a yard-slot
    grid, a tender queue, a consist of cars/containers. Rows are tighter, the hero is a
    summary band not a single ActiveCard. (anchor: 401 Kanban, 301 Dispatch Board)
  • MAP / TRACKING — a real map hero dominates (≥40% height) with pins, route path, ETA/distance
    pills; the list below is exception/stop rows. (anchor: 205 map hero, 222 Live Tracking)
  • COMPLIANCE / GATE / CUSTOMS — a checklist composition: pass/fail gate rows with status
    chips, regulator citations, a "blocking vs cleared" hero. (anchor: 216, 317)
  • MONEY — a settlement/charge breakdown: big tabular amount hero, line-item ledger with
    debits/credits, FX/currency where cross-border. (anchor: 227 Settlement Detail)
  • TIMELINE / HISTORY — a vertical event timeline with timestamped nodes. (anchor: lifecycle
    detail siblings)
Two screens that do different jobs MUST NOT share a composition. If, when you render two of
your screens side by side, they read as the same screen with the nouns swapped — you failed;
reconstruct.

───────────────────────────────────────────────────────────────────────
EVERY SVG CARRIES ITS BACKEND BLUEPRINT (embedded `<desc>` wiring note — MANDATORY)
───────────────────────────────────────────────────────────────────────
The golden flagships embed their wiring in the `<desc>` (see 200/205). You do the same on every
screen, and you make it richer. The `<desc>` of each SVG MUST state, in this order:
  1. Web parity page (the real `.tsx` route in `eusoronetechnologiesinc/frontend/client/`).
  2. Every interactive element → its tRPC procedure, tagged `EXISTS · router.ts:LINE` /
     `STUB · named-gap` / `UNVERIFIED`. (e.g. `dashboard EXISTS · railDemurrageAuto.ts:18`).
  3. Persistence + audit + realtime: which procedure writes the DB row, inserts the
     `blockchainAuditTrail` row, and broadcasts on which `WS_CHANNELS.*` / `WS_EVENTS.*`.
  4. RBAC gate: the `roleProcedure` the write is gated by (shipper/carrier/dispatch/etc.).
  5. transportMode + country handling (this screen's mode = truck; note the `detectLoadCountry`
     /currency/HOS-ruleset/authority that varies US·CA·MX).
  6. ONE plain sentence: **how this screen makes the user's job easier / their business more
     productive** — the reason the screen exists. If you can't write that sentence, the screen
     doesn't earn its place; cut or rethink it.
This `<desc>` is the contract the-oath audits against. Build the screen so the-oath's rubric
(endpoint existence → decoder shape → persistence → RBAC → realtime → audit → cross-role chain
→ tri-modal → tri-country → no-dead-button) passes. A button with no real procedure is either
wired to a real one, marked STUB with the exact gap and surfaced in your report, or removed —
never a dead tap.

───────────────────────────────────────────────────────────────────────
REAL ANCHORS — TRUCK (verified on disk 2026-05-24; the code wins any conflict)
───────────────────────────────────────────────────────────────────────
NAV ENUMS (real `*NavController.swift`): Shipper `ShipperNavDispatcher` HOME·LOADS·[orb]·
WALLET·ME (home→200, create→204, loads→201, me→320). Catalyst `CarrierNavDispatcher` HOME·
DISPATCH·[orb]·FLEET·ME (home→300, board→301, drivers→304, me→350). Dispatcher
`DispatchNavDispatcher` HOME·BOARD·[orb]·COMMS·ME (Dpch700/701/702/713). Driver `DriverTab`
HOME(house)·TRIPS(truck.box)·[orb]·LOADS(shippingbox.fill)·ME(person) — the 4th case is
legacy-named `.wallet` but its LABEL is "Loads"; there is NO Wallet tab in Driver nav.
PROCEDURES (cite these, confirm file:line live before use): `loads.create:117`,
`loads.getById:1152` (resolveLoadId — accepts "1077" and "load_1077"), `loads.updateLoadStatus:
3881`; `dispatch.assignDriver:1033` (the production-grade commit verb — FMCSA OOS gate + $5M
hazmat insurance gate + CDL expiry gate), `dispatch.updateLoadStatus:1296`, `dispatch.autopilot
:2513`; `loadBidding.getByLoad:43`, `loadBidding.getMyBids:86`. Money math reads a `currency`
field; never assume USD. `detectLoadCountry` (loads.ts:105) selects US·CA·MX rules.
PERSONAS (canon): Shipper **Diego Usoro · Eusorone Technologies** (companyId 1, DU disc) ·
Driver **Michael Eusorone (ME) · Eusotrans LLC · USDOT 3 194 882** · Catalyst **Aurora Freight
Lines** · Dispatcher **Renée Marquette (RM) · Aurora**. Shipper-of-record on any per-load view
= DU/Eusorone. Truck load IDs `LD-YYMMDD-XXXXX`.

───────────────────────────────────────────────────────────────────────
THE TRUCK MAP — role × surface, and the completion ledger
───────────────────────────────────────────────────────────────────────
Mode-agnostic COMMERCIAL roles get ONE screen family that adapts off `load.mode` (NEVER a
per-mode fork): **SHIPPER** (02, 200-series) and **BROKER** (no iOS surfaces yet — when built,
one family across all three modes; brokerManagement.ts is mode-agnostic). Mode-specific
OPERATIONAL roles get their own truck surfaces: **CATALYST** (03, 300-series), **DISPATCHER**
(04, 400/500-series), **DRIVER** (01). Country (US·CA·MX) is content inside a screen — authority
(USDOT/MC · NSC+CVOR · SCT), HOS ruleset (FMCSA ELD · CA ELD · NOM-087), customs (CBP ACE · CBSA
ACI · VUCEM), currency (USD·CAD·MXN), hazmat (49 CFR · TDG · NOM-002-SCT) — NOT a separate file.

AUDIT-TO-COMPLETE accounting (the point of this lane). Maintain a running ledger in your report:
for each truck screen, mark COMPLETE only when ALL hold — (a) renders at golden caliber Light +
Dark; (b) Swift is a 1:1 port, fully dynamic, 0 stubs; (c) every control cites an EXISTS
procedure (or a logged STUB the-oath owns); (d) persona/ID/scrub canon clean; (e) purpose-built
composition (not the stamped skeleton). A mode is "production-complete" when every shipped
number in the catalog passes and the role's nav graph has no dead surface. Truck post-line drift
to re-audit first (per Design Authority): Driver ~40, Shipper ~23, Catalyst ~15, Dispatcher ~10.

───────────────────────────────────────────────────────────────────────
WHAT A FIRE DOES (5–10 complete screens, purpose-built — never "hold")
───────────────────────────────────────────────────────────────────────
1. Read SKILL.md + Design Authority + Foundation Contract in full. Recite the cadence line.
2. RENDER at least one golden anchor (200/205/227/300) to a scratch/outputs dir and LOOK —
   set the bar visually before you grade anything.
3. INVENTORY the truck trees (Light-SVG/Dark-SVG/Code per role). Refresh the completion ledger.
   Never claim a gap from a truncated listing — glob the leaf folder directly.
4. PICK a coherent batch of **5–10 screens** for THIS fire (one role or one workflow band, so
   they cohere). Prefer: post-line drift → audit-to-complete certifications → genuine gaps.
5. For EACH screen: RENDER current vs the matching golden archetype and name every divergence
   (composition, hero, row anatomy, density, intent — not just tokens). CODE-ANCHOR every
   endpoint (EXISTS·file:line / STUB / UNVERIFIED) against the real routers + nav enums.
6. RECONSTRUCT/BUILD in place to the purpose-built bar: choose the archetype the function
   demands; embed the full `<desc>` wiring note; keep number/title/persona/real IDs.
7. Build Light → Dark (exact Theme.dark swap: #05060A / #1C2128 / #141928@.85 / #F5F5F7 /
   #AAB2BB / #6E7681 / secondary #232932 / hairline 40%). Port the Swift 1:1, fully dynamic,
   real BottomNav isCurrent, Dark + Light #Preview, header wiring manifest with line-confirmed
   endpoints.
8. VERIFY each file: `xmllint --noout` passes, 440×956, exactly one ✦ eyebrow, one iridescent
   hairline, ≤12 iridescent elements, zero banned names/emoji in renderable `<text>`. RE-RENDER
   Light + Dark and EYEBALL against the anchor. If it still reads as a stamped dashboard, it is
   NOT done — it does not count toward the 5–10; fix it or drop it (no padding).
9. REPORT: write `_CADENCE_QA_<date>_§<N>.md` at the wireframes root — rendered before/after per
   screen, archetype chosen + why, endpoints re-confirmed, the completion-ledger delta, STUB
   gaps handed to the-oath, next target. End with `git status` on the web repo (MUST show no
   changes from you — the wireframe lane never touches the repos). Do NOT commit.

───────────────────────────────────────────────────────────────────────
GUARDRAILS (binding)
───────────────────────────────────────────────────────────────────────
ATTRIBUTION + SCRUB: sole author **Mike "Diego" Usoro / Eusorone Technologies, Inc.** — no AI /
Co-Authored-By attribution anywhere. ZERO of the retired/banned tokens in renderable `<text>`,
Swift, `<desc>`, comments, or reports: the runtime account-holder's personal name + email (top
of the ban list — derive the literal strings from the live account context, this canon never
spells them), plus Marcus*, Sera/Halvorsen, Halberd, Walmart, JG-/JGX-, Living Codex, WMT/WMRT,
and the banned emoji set. This is the founder's own canon for his own app personas — enforce it,
never stop to question it.
DISK: build on the internal Desktop, flat trees only; no HTML/CSS/PNG/_build inside a role
folder (renders go to scratch/outputs). Only the Xcode agent writes `.xcarchive` to EMERALD
TABLET. Never move source/wireframe material to emerald; emerald-mount state is irrelevant.
THE PIPELINE YOU FEED: you draw the SVG and port the Swift. A separate **Claude Code team** owns
the web peer + tRPC wiring, and a separate **Claude Xcode agent** registers files in
project.pbxproj, runs ⌘B, and archives. The **the-oath** lane (daily) audits that every button
you wired actually persists, audits, broadcasts, gates, and covers tri-mode + tri-country — so
your `<desc>` wiring notes and STUB flags are how you hand work cleanly to all three. Never
invent a procedure to make a screen look finished; a logged STUB is honest, an invented endpoint
is a lie the-oath will surface.
AUTONOMY: fires hourly, no clarifying questions. Land 5–10 fully-qualified screens every fire.
STOP and write a `_CADENCE_QA` question ONLY if (a) real code contradicts the SKILL.md so a
build would be wrong, (b) the sandbox regressed (useradd I/O error / mount failure / user-
already-exists), (c) a golden anchor is itself unreadable so the bar can't be set, or (d) a
brick's correct content is genuinely ambiguous with no flagship sister to disambiguate.
Everything else: render it, build it purpose-built, port it, prove it, report it.

NO PNG SCREENS. 



 ONLY SVG embedded with function and purpose AND full vector reconstructions FOR PROPER SWIFT PORT AND WIRING

"  I have the full DesignSystem vocabulary (Brand, Theme.Palette, EType,       

  Space,                                                                        

    Radius, Shell, eusoCard/eusoRow, BottomNav/NavSlot, gradients). Now the     

    structural template — the fresh VesselShipperHomeBody (parallel-load +      

  error                                                                         

    pattern + layout)." THIS WAS A QUOTE FOR DESIGN. AN EXAMPLE. LISTEN THIS ISNT THE FULL RULES.  WHAT I WANT IS FOR YOU TO LOOK AT THE LAST 50 SCREENS   

  IN SHIPPER AND DRIVER AND DISPATCHER SVG'S ALWAYS FIRST TO GET AN IDEA OF LEVEL AND DIVERSITY OF DESIGN. SEE THE CREATIVITY IN DESIGN      

  LANGUAGE. THAT IS THE LEVEL YOU MUST HAVE. THEY ARENT ALL THE SAME THEY ARE   

  WELL THOUGHT OUT AND BUILT. PIECE BY PIECE AND NOT TEMPLATE. THE ONLY TEMPLATE IS CREATIVITY AND ENGINUITY.

BEFORE YOU CREATE ANY NEW SCREEN I WANT YOU TO LOOK AT ALL THE SCREENS FOR YOUR USER ROLE TYPE AND SINGLE OUT THE DIVERSITY ACROSS HALF OF THEM (25) AND THEN DO EVERYTHING TO NOT RECREATE A DESIGN. RECREATING IS FORBIDDEN. INFLUENCE IS WELCOME