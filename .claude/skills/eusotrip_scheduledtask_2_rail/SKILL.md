---
name: eusotrip_scheduledtask_2_rail
description: rail reconstruct of my app (purpose-built cadence, SKILL-led)
---

**BEFORE YOU DRAW OR CODE A SINGLE SCREEN — STUDY THE HOUSE, THEN MATCH IT EXACTLY.**
The EusoTrip design pipeline has a hard quality line at **2026-05-22 08:27 AM**: every SVG
designed on or before that moment is GOLDEN — full studio cadence, deliberate in every button,
gradient, menu shape, corner radius, spacing and density — and everything after it came from a
rushed batch that degraded the work. Your bar is the golden era. **05 Rail is 100% post-line —
the entire mode is debt.** Go to school on the TRUCK flagship anchors first — `02 Shipper/200
Shipper Home`, `205 Load Detail`, `227 Settlement Detail`, `03 Catalyst/300 Catalyst Home` —
RENDER them, study them, earn your honors in this exact cadence, THEN reconstruct rail to that
bar 1000%, the WHOLE screen. Forbidden on sight: giant gradient stat-card heroes, 3×N MetricTile
grids, chip-less rows, long pills that collide with the money, missing CTA pair, a glyph where
the flagship uses an initials disc. Build Light first, make Dark by exact Theme.dark palette-
swap, then port the **Swift as a FAITHFUL 1:1 mirror of the SVG.** Code ships **0 STUBS · 0 MOCK
DATA · 0 PLACEHOLDERS — FULLY DYNAMIC, PRODUCTION-READY**. A screen is DONE only when you've
RENDERED Light + Dark, eyeballed them against the golden flagship, they read as the same
designer's work, AND the Swift matches the SVG. Precedence: real code/disk > SKILL.md (+ Design
Authority + Foundation Contract) > rendered golden flagship > task context.

═══════════════════════════════════════════════════════════════════════
EusoTrip 2027 — AUTONOMOUS BUILD · eusotrip-killers · MODE = RAIL
(rev 2026-05-24 · PURPOSE-BUILT-CADENCE · FULL RECONSTRUCT · FLAT · SINGLE-COUNTRY-PER-SCREEN
 · OATH-ALIGNED · SKILL-led)
═══════════════════════════════════════════════════════════════════════

You are the RAIL lane. The rail catalog already has ~141 numbered screens — and that is exactly
the problem: they were batch-stamped from one detail skeleton and read VERBATIM IDENTICAL one
after another, with no intention tied to each screen's function. Your job is NOT to add more
numbers. It is to RECONSTRUCT the existing rail screens, one coherent batch at a time, until a
rail user looking at the catalog beside the Shipper/Catalyst/Dispatch screens says "the same
studio designed this" — full 1000% parity with the house, every screen purpose-built for its
job. Rail and Truck are siblings, not cousins: a rail user must feel the identical product.

THE SINGLE SOURCE OF TRUTH IS THE CANONICAL SKILL.md + DESIGN AUTHORITY, NOT THIS BLOCK.
Read in full FIRST every fire:
  • `~/Desktop/EusoTrip 2027 UI Wireframes/SKILL.md`
  • `~/Desktop/EusoTrip 2027 UI Wireframes/_DESIGN_AUTHORITY_2026-05-24b_CADENCE_LINE.md`
    (RUBRIC A–K is binding and exact — obey it, do not paraphrase it)
  • `~/Desktop/EusoTrip 2027 UI Wireframes/_DESIGN_FOUNDATION_CONTRACT.md` (the 14-kit)
PRECEDENCE: real iOS/web code > SKILL.md + Design Authority + Foundation Contract > rendered
golden flagship > this context. No swarm, no `<CC>` suffix, no subfolders, no `_LIFECYCLE_CLOCK`.
Flat trees only: `05 Rail / {Light-SVG, Dark-SVG, Code}`.

───────────────────────────────────────────────────────────────────────
THE #1 DEFECT YOU ARE HERE TO KILL: MONOTONY (every rail screen the same screen)
───────────────────────────────────────────────────────────────────────
The batch stamped ONE skeleton — hero ActiveCard → 3-cell KPI → ListRow stack → secondary strip
→ CTA pair — onto a demurrage board, a consist board, a crew HOS roster, a yard console, a
container timeline, a customs gate, a settlement ledger, alike. **Composition follows function.**
The golden screens prove it: `205` leads with a live MAP + 8-stage lifecycle strip; `227` leads
with a money breakdown; `401` is a kanban board. Pick the archetype the rail screen's PURPOSE
demands — never default to "detail":
  • HOME — greeting + avatar disc + attention card + KPI + itemized ledger of the engineer's
    live shipments/consists + ESang. (rail home = 550)
  • DETAIL — back-chevron + purpose hero + the RAIL lifecycle strip (Ordered → Tendered →
    Placed → Loaded → In-Train → Interchange → Ramp → Delivered) + waybill/consist parties +
    docs + CTA pair. (rail shipment detail = 553)
  • BOARD / OPERATIONS — a consist board (list of railcars in a cut), a yard-slot grid, a tender
    queue, a ramp schedule: tight rows, summary band hero, scannable. (consist = 555, yard = 559)
  • MAP / TRACKING — rail network map hero with car position pins + interchange points + ETA.
  • COMPLIANCE / CUSTOMS — FRA safety gate rows / cross-border interchange clearance checklist
    with regulator citations, blocking-vs-cleared hero. (border clearance = 564, FRA = 587)
  • MONEY — demurrage burndown, freight-bill audit, settlement batch: tabular amount hero +
    line-item ledger + currency. (demurrage = 608, freight audit = 599, settlement = 581)
  • TIMELINE — container/car event timeline with timestamped nodes. (container timeline = 565)
If two of your rail screens read as the same screen with the nouns swapped, you failed —
reconstruct until each is unmistakably built for its own job.

───────────────────────────────────────────────────────────────────────
EVERY SVG CARRIES ITS BACKEND BLUEPRINT (embedded `<desc>` wiring note — MANDATORY)
───────────────────────────────────────────────────────────────────────
Each SVG `<desc>` states, in order: (1) web parity `.tsx` route; (2) every interactive element →
its tRPC procedure tagged `EXISTS · router.ts:LINE` / `STUB · named-gap` / `UNVERIFIED`;
(3) which procedure writes the DB row, inserts the `blockchainAuditTrail` row, broadcasts on
which `WS_CHANNELS.*`/`WS_EVENTS.*`; (4) the `roleProcedure` RBAC gate; (5) transportMode=rail +
the country (US·CA·MX) compliance/currency that varies; (6) ONE plain sentence on **how this
screen makes the rail user's job easier / their business more productive** — if you can't write
it, the screen doesn't earn its place. This `<desc>` is the contract the-oath audits.

───────────────────────────────────────────────────────────────────────
REAL ANCHORS — RAIL (verified on disk 2026-05-24; the code wins any conflict)
───────────────────────────────────────────────────────────────────────
NAV ENUM (real `RailEngineerNavController.swift` · `RailEngineerNavDispatcher`):
**HOME · SHIPMENTS · [orb] · COMPLIANCE · ME** (home→Rail550, shipments→Rail551,
compliance→Rail552, me→Rail556; deep screens Rail560–Rail590+). 43 native Rail Views exist —
this is NOT greenfield iOS; you are reconstructing real surfaces, not inventing roles.
PROCEDURES (cite these, confirm file:line live before use):
  • `railShipments.ts` — `createRailShipment:47`, `getRailShipments:99`, `getRailShipmentDetail
    :140`, `updateRailShipmentStatus:168` (all `railProcedure`; state-machine + auto-settle).
  • `railDemurrageAuto.ts` — `dashboard:18`, `calculateAccrual:36` (free time US 48h/CA 48h/MX
    24h), `runBulkAccrual:66`, `createDispute:78`, `reportByDwellReason:93` (protectedProcedure).
  • `railFreightAudit.ts` — `auditInvoice:27`, `recentAudits:103`.
  • `railTenderWorkflow.ts` — `submitTender:16` (EDI 404), `receiveTenderResponse:57` (EDI 990),
    `tenderHistory:80`.
  • `intermodal.ts` — `createIntermodalShipment:30`, `getIntermodalShipmentDetail:161`,
    `advanceSegment:184`, `recordTransfer:235`, `getIntermodalTracking:269`,
    `getIntermodalCostBreakdown:295`, `getIntermodalDashboard:341` (the rail↔truck↔vessel spine).
  • Shared: `loads.getById:1152` (resolveLoadId), `dispatch.assignDriver:1033` (the compliance-
    gated commit verb — reuse its gate pattern for rail crew assignment).
KNOWN RAIL GAPS (no backing procedure yet — mark `STUB · named-gap` and surface to the-oath,
NEVER invent an endpoint): rail consist board, rail crew HOS roster, rail waybill create/track
(read-only today inside getRailShipmentDetail), rail FRA compliance query endpoint, dedicated
container timeline. Where a button needs one of these, cite the STUB and propose the TypeScript
shape in your report — that is how the-oath picks it up and builds it real.
PERSONAS: rail shipper = **Diego Usoro · Eusorone Technologies** (mode-agnostic shipper, same
identity). Rail carrier/engineer persona is NOT in code — Design Authority's PROVISIONAL is
**Owen Trask (OT) · Aurora Rail Division**; use it and tag PROVISIONAL in the report for founder
canonization; do NOT auto-name from the banned set. Rail IDs `RAIL-YYMMDD-XXXXX`.

───────────────────────────────────────────────────────────────────────
THE RAIL MAP — role × surface, single-country-per-screen
───────────────────────────────────────────────────────────────────────
Mode-agnostic COMMERCIAL roles do NOT fork to rail: the rail SHIPPER surfaces (05 Rail 001–010)
should converge with the canonical truck Shipper family, adapting content off `load.mode='rail'`
(waybill · ramp gate · demurrage instead of DVIR/HOS) — reconstruct them to read as the SAME
Shipper app, not a separate "Rail Shipper." Mode-specific OPERATIONAL surfaces are where the
real rail build lives: **Rail Engineer / carrier ops** (550–640+) — consist, crew HOS, yard,
ramp, FRA, interchange, demurrage, freight audit, settlement. Country is content inside a
screen: authority (STB/FRA · Transport Canada Rail · ARTF/SICT), dangerous goods (49 CFR · TDG ·
NOM), free-time/demurrage clocks (US/CA 48h · MX 24h per calculateAccrual), customs interchange
(CBP · CBSA · Aduanas/VUCEM), currency (USD·CAD·MXN) — never a separate file.

───────────────────────────────────────────────────────────────────────
WHAT A FIRE DOES (reconstruct 5–10 complete screens, purpose-built — never "hold")
───────────────────────────────────────────────────────────────────────
1. Read SKILL.md + Design Authority + Foundation Contract in full. Recite the cadence line.
2. RENDER at least one golden TRUCK anchor (205 detail / 227 money / 401 board / 200 home) to a
   scratch/outputs dir and LOOK — set the bar visually before grading any rail screen.
3. INVENTORY 05 Rail (Light-SVG/Dark-SVG/Code). Glob leaf folders directly. Refresh the
   reconstruction worklist (earliest/lowest-fidelity first within the band you choose).
4. PICK a coherent batch of **5–10 rail screens** of the SAME workflow band this fire (e.g. the
   demurrage cluster, or the consist/yard cluster) so they cohere and you can prove range.
5. For EACH: RENDER current vs the matching golden archetype; name every divergence. CODE-ANCHOR
   every endpoint (EXISTS·file:line / STUB / UNVERIFIED) against the real rail routers + nav enum.
6. RECONSTRUCT IN PLACE to the purpose-built archetype the function demands (a consist board is a
   board, not a detail card). Embed the full `<desc>` wiring note. Keep number/title/real IDs.
7. Light → Dark (exact Theme.dark swap). Port the Swift 1:1, fully dynamic, real BottomNav
   (HOME·SHIPMENTS·orb·COMPLIANCE·ME) isCurrent, Dark+Light #Preview, header wiring manifest.
8. VERIFY each: `xmllint --noout`, 440×956, one ✦ eyebrow, one iridescent hairline, ≤12
   iridescent elements, zero banned names/emoji. RE-RENDER + EYEBALL vs anchor. If it still reads
   as a stamped dashboard it does NOT count toward the 5–10 — fix it or drop it (no padding).
9. REPORT `_CADENCE_QA_<date>_§rail-recon-<range>.md` at the wireframes root: rendered
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
archives; **the-oath** (daily) audits that every rail button persists, audits, broadcasts, gates,
and covers tri-country. Your `<desc>` wiring notes + STUB flags are the clean handoff. Never
invent a procedure to fake completeness — a logged STUB is honest.
AUTONOMY: fires hourly, no clarifying questions. Reconstruct 5–10 fully-qualified rail screens
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