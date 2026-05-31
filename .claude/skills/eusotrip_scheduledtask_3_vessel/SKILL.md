---
name: eusotrip_scheduledtask_3_vessel
description: vessel reconstruct of my app (purpose-built cadence, SKILL-led)
---

**BEFORE YOU DRAW OR CODE A SINGLE SCREEN — STUDY THE HOUSE, THEN MATCH IT EXACTLY.**
The EusoTrip design pipeline has a hard quality line at **2026-05-22 08:27 AM**: every SVG
designed on or before that moment is GOLDEN — full studio cadence, deliberate in every button,
gradient, menu shape, corner radius, spacing and density — and everything after it came from a
rushed batch that degraded the work. Your bar is the golden era. **06 Vessel is 100% post-line —
the entire mode is debt.** Go to school on the TRUCK flagship anchors first — `02 Shipper/200
Shipper Home`, `205 Load Detail`, `227 Settlement Detail`, `03 Catalyst/300 Catalyst Home` —
RENDER them, study them, earn your honors in this exact cadence, THEN reconstruct vessel to that
bar 1000%, the WHOLE screen. Forbidden on sight: giant gradient stat-card heroes, 3×N MetricTile
grids, chip-less rows, long pills that collide with the money, missing CTA pair, a glyph where
the flagship uses an initials disc. Build Light first, make Dark by exact Theme.dark palette-
swap, then port the **Swift as a FAITHFUL 1:1 mirror of the SVG.** Code ships **0 STUBS · 0 MOCK
DATA · 0 PLACEHOLDERS — FULLY DYNAMIC, PRODUCTION-READY**. A screen is DONE only when you've
RENDERED Light + Dark, eyeballed them against the golden flagship, they read as the same
designer's work, AND the Swift matches the SVG. Precedence: real code/disk > SKILL.md (+ Design
Authority + Foundation Contract) > rendered golden flagship > task context.

═══════════════════════════════════════════════════════════════════════
EusoTrip 2027 — AUTONOMOUS BUILD · eusotrip-killers · MODE = VESSEL
(rev 2026-05-24 · PURPOSE-BUILT-CADENCE · FULL RECONSTRUCT · FLAT · SINGLE-COUNTRY-PER-SCREEN
 · OATH-ALIGNED · SKILL-led)
═══════════════════════════════════════════════════════════════════════

You are the VESSEL lane. The vessel catalog already has ~151 numbered screens — and that is the
problem: they were batch-stamped from one detail skeleton and read VERBATIM IDENTICAL one after
another, with no intention tied to each screen's function. Your job is NOT to add more numbers.
It is to RECONSTRUCT the existing vessel screens, one coherent batch at a time, until a vessel
user looking at the catalog beside the Shipper/Catalyst/Dispatch screens says "the same studio
designed this" — full 1000% parity with the house, every screen purpose-built for its job.
Vessel and Truck are the SAME product in a different mode; the user must feel it.

THE SINGLE SOURCE OF TRUTH IS THE CANONICAL SKILL.md + DESIGN AUTHORITY, NOT THIS BLOCK.
Read in full FIRST every fire:
  • `~/Desktop/EusoTrip 2027 UI Wireframes/SKILL.md`
  • `~/Desktop/EusoTrip 2027 UI Wireframes/_DESIGN_AUTHORITY_2026-05-24b_CADENCE_LINE.md`
    (RUBRIC A–K is binding and exact — obey it, do not paraphrase it)
  • `~/Desktop/EusoTrip 2027 UI Wireframes/_DESIGN_FOUNDATION_CONTRACT.md` (the 14-kit)
PRECEDENCE: real iOS/web code > SKILL.md + Design Authority + Foundation Contract > rendered
golden flagship > this context. No swarm, no `<CC>` suffix, no subfolders, no `_LIFECYCLE_CLOCK`.
Flat trees only: `06 Vessel / {Light-SVG, Dark-SVG, Code}`.

───────────────────────────────────────────────────────────────────────
THE #1 DEFECT YOU ARE HERE TO KILL: MONOTONY (every vessel screen the same screen)
───────────────────────────────────────────────────────────────────────
The batch stamped ONE skeleton — hero ActiveCard → 3-cell KPI → ListRow stack → secondary strip
→ CTA pair — onto a port-calls schedule, a CBP entry gate, a container-positions board, a
bay plan, a demurrage ledger, a bill-of-lading, alike. **Composition follows function.** Pick
the archetype the vessel screen's PURPOSE demands — never default to "detail":
  • HOME — greeting + avatar disc + attention card + KPI + itemized ledger of the operator's
    live bookings/port calls + ESang. (vessel home = 650)
  • DETAIL — back-chevron + purpose hero + the VESSEL lifecycle strip (Booked → Documentation →
    Gate-In → Loaded → Departed → In-Transit → Customs → Discharged → Delivered) + B/L parties +
    docs + CTA pair. (booking detail = 653)
  • BOARD / OPERATIONS — port-calls schedule, container-positions board, bay plan, berth window,
    sailing schedule: tight rows or a slot grid, summary band hero. (port calls = 661, bay = 704)
  • MAP / TRACKING — marine chart hero with vessel position + voyage track + port pins + ETA.
    (live position = 660)
  • COMPLIANCE / CUSTOMS — ISF 10+2 / CBP entry / port-state-control gate rows with regulator
    citations + blocking-vs-cleared hero. (CBP entry = 663, customs ISF = 006, PSC = 678)
  • MONEY — demurrage & detention watch, freight-bill audit, settlement: tabular amount hero +
    line-item ledger + currency. (demurrage = 658, freight audit = 700, settlement = 684)
  • TIMELINE — container event timeline with timestamped nodes. (container timeline = 666)
If two vessel screens read as the same screen with the nouns swapped, you failed — reconstruct
until each is unmistakably built for its own job.

───────────────────────────────────────────────────────────────────────
EVERY SVG CARRIES ITS BACKEND BLUEPRINT (embedded `<desc>` wiring note — MANDATORY)
───────────────────────────────────────────────────────────────────────
Each SVG `<desc>` states, in order: (1) web parity `.tsx` route; (2) every interactive element →
its tRPC procedure tagged `EXISTS · router.ts:LINE` / `STUB · named-gap` / `UNVERIFIED`;
(3) which procedure writes the DB row, inserts the `blockchainAuditTrail` row, broadcasts on
which `WS_CHANNELS.*`/`WS_EVENTS.*`; (4) the `roleProcedure` RBAC gate; (5) transportMode=vessel
+ the country (US·CA·MX) compliance/currency that varies; (6) ONE plain sentence on **how this
screen makes the vessel user's job easier / their business more productive** — if you can't
write it, the screen doesn't earn its place. This `<desc>` is the contract the-oath audits.

───────────────────────────────────────────────────────────────────────
REAL ANCHORS — VESSEL (verified on disk 2026-05-24; the code wins any conflict)
───────────────────────────────────────────────────────────────────────
NAV ENUM (real `VesselOperatorNavController.swift` · `VesselOperatorNavDispatcher`):
**HOME · SHIPMENTS · [orb] · COMPLIANCE · ME** (home→Vesl650, shipments→Vesl651,
compliance→Vesl652, me→Vesl656; deep screens 653–658). 9 native Vessel Views exist today —
the role is real but THIN on the iOS side; reconstruct the existing surfaces and, where a deep
screen has no native View yet, build SVG + Swift to extend the SAME nav graph (do NOT invent
new roles — there is no captain/port-master/customs-broker role in any nav enum or router).
PROCEDURES (cite these, confirm file:line live before use):
  • `vesselShipments.ts` — `createVesselBooking:59`, `getVesselShipments:121`,
    `getVesselShipmentDetail:162`, `updateVesselShipmentStatus:192` (all `vesselProcedure`;
    enforces ISF 10+2 pre-filing before loading, state-machine + auto-settle).
  • `imdg.ts` — `createCompliance:7`, `getCompliance:13`, `setPackingCertUrl:19`,
    `setDGDeclarationUrl:26`, `markVesselManifest:33` (vessel hazmat / DG).
  • `blankSailing.ts:17` (blank-sailing dashboard — map the real shape before wiring).
  • `intermodal.ts` — `advanceSegment:184`, `recordTransfer:235`, `getIntermodalTracking:269`,
    `getIntermodalCostBreakdown:295` (the vessel↔rail↔truck spine for transshipment/drayage).
  • Shared: `loads.getById:1152` (resolveLoadId), `dispatch.assignDriver:1033` (reuse its
    compliance-gate pattern for crew/equipment commit verbs).
KNOWN VESSEL GAPS (no backing procedure yet — mark `STUB · named-gap`, surface to the-oath,
NEVER invent): vessel bill-of-lading CREATE (read-only today inside detail), dedicated ISF/CBP
entry mutation (logic embedded in updateVesselShipmentStatus:232-250), dedicated container
timeline, explicit createSettlement. Where a button needs one, cite the STUB and propose the TS
shape in your report — that is how the-oath builds it real.
PERSONAS: vessel shipper = **Diego Usoro · Eusorone Technologies** (mode-agnostic shipper, same
identity). Vessel operator persona is NOT in code — assign an initials disc + "Hey, <Name>" on
the first Vessel-home reconstruction and tag PROVISIONAL in the report for founder canonization;
do NOT auto-name from the banned set. Vessel IDs `VES-YYMMDD-XXXXX`.

───────────────────────────────────────────────────────────────────────
THE VESSEL MAP — role × surface, single-country-per-screen
───────────────────────────────────────────────────────────────────────
Mode-agnostic COMMERCIAL roles do NOT fork to vessel: the vessel SHIPPER surfaces (06 Vessel
001–010) should converge with the canonical truck Shipper family, adapting content off
`load.mode='vessel'` (B/L · ISF · voyage · demurrage instead of DVIR/HOS) — reconstruct them to
read as the SAME Shipper app, not a separate "Vessel Shipper." Mode-specific OPERATIONAL surfaces
are the real vessel build: **Vessel Operator / carrier ops** (650–712+) — port calls, container
positions, bay plan, customs/ISF, IMDG, demurrage/detention, freight audit, settlement,
transshipment. Country is content inside a screen: authority (USCG/CBP · Transport Canada Marine/
CBSA · SEMAR/Aduanas), customs (CBP ACE+ISF · CBSA ACI · VUCEM), dangerous goods (IMDG class
shared; ERG refs differ by country), currency (USD·CAD·MXN) — never a separate file.

───────────────────────────────────────────────────────────────────────
WHAT A FIRE DOES (reconstruct 5–10 complete screens, purpose-built — never "hold")
───────────────────────────────────────────────────────────────────────
1. Read SKILL.md + Design Authority + Foundation Contract in full. Recite the cadence line.
2. RENDER at least one golden TRUCK anchor (205 detail / 227 money / 401 board / 200 home) to a
   scratch/outputs dir and LOOK — set the bar visually before grading any vessel screen.
3. INVENTORY 06 Vessel (Light-SVG/Dark-SVG/Code). Glob leaf folders directly. Refresh the
   reconstruction worklist (earliest/lowest-fidelity first within the band you choose).
4. PICK a coherent batch of **5–10 vessel screens** of the SAME workflow band this fire (e.g.
   the customs/ISF cluster, or the port-ops/bay-plan cluster) so they cohere and prove range.
5. For EACH: RENDER current vs the matching golden archetype; name every divergence. CODE-ANCHOR
   every endpoint (EXISTS·file:line / STUB / UNVERIFIED) against the real vessel routers + nav.
6. RECONSTRUCT IN PLACE to the purpose-built archetype the function demands (a bay plan is a
   slot grid, not a detail card). Embed the full `<desc>` wiring note. Keep number/title/real IDs.
7. Light → Dark (exact Theme.dark swap). Port the Swift 1:1, fully dynamic, real BottomNav
   (HOME·SHIPMENTS·orb·COMPLIANCE·ME) isCurrent, Dark+Light #Preview, header wiring manifest.
8. VERIFY each: `xmllint --noout`, 440×956, one ✦ eyebrow, one iridescent hairline, ≤12
   iridescent elements, zero banned names/emoji. RE-RENDER + EYEBALL vs anchor. If it still reads
   as a stamped dashboard it does NOT count toward the 5–10 — fix it or drop it (no padding).
9. REPORT `_CADENCE_QA_<date>_§vessel-recon-<range>.md` at the wireframes root: rendered
   before/after per screen, archetype + why, endpoints re-confirmed, STUB gaps handed to
   the-oath with proposed TS shapes, provisional persona flags, next target. End with
   `git status` on the web repo (MUST show no changes from you). Do NOT commit.

───────────────────────────────────────────────────────────────────────
GUARDRAILS (binding)
───────────────────────────────────────────────────────────────────────
ATTRIBUTION + SCRUB: sole author **Mike "Diego" Usoro / Eusorone Technologies, Inc.** — no AI /
Co-Authored-By. ZERO retired/banned tokens in renderable `<text>`, Swift, `<desc>`, comments,
reports: the runtime account-holder's personal name + email (top of the ban list — derive from
live account context, this canon never spells them), plus Marcus*, Sera/Halvorsen, Halberd,
Walmart, JG-/JGX-, Living Codex, WMT/WMRT, and the banned emoji set. Founder's own canon for his
own app personas — enforce it, never stop to question it.
DISK: internal Desktop, flat trees, no HTML/CSS/PNG/_build inside a role folder (renders to
scratch/outputs). Only the Xcode agent writes `.xcarchive` to EMERALD TABLET; never move source
to emerald; emerald-mount state is irrelevant.
THE PIPELINE YOU FEED: you draw the SVG + port the Swift. The **Claude Code team** owns the web
peer + tRPC wiring; the **Claude Xcode agent** registers files in project.pbxproj, runs ⌘B,
archives; **the-oath** (daily) audits that every vessel button persists, audits, broadcasts,
gates, and covers tri-country. Your `<desc>` wiring notes + STUB flags are the clean handoff.
Never invent a procedure to fake completeness — a logged STUB is honest.
AUTONOMY: fires hourly, no clarifying questions. Reconstruct 5–10 fully-qualified vessel screens
every fire. STOP and write a `_CADENCE_QA` question ONLY if (a) real code contradicts SKILL.md
so a build would be wrong, (b) the sandbox regressed, (c) a golden anchor is unreadable, or (d)
a brick's correct content is genuinely ambiguous with no sister to disambiguate. Otherwise:
render it, reconstruct it purpose-built, port it, prove it, report it — on the hour, every hour.

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