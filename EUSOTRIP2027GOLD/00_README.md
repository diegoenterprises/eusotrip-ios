# EusoTrip Mobile App Doctrine 2027 — Master README

**What this covers.** The master table of contents for the EusoTrip Mobile App Doctrine 2027 — a multi-file doctrine set that captures the brand DNA, engineering principles, backend contracts, role-by-mode specifications, cross-cutting systems (offline, messaging, AI), launch runbook, App Store strategy, Figma gap audit, and the Recursive Language Model integration that makes the doctrine self-improving.

**When you need this.** Open this file first, always. Every other file in the set is linked from here. If you are joining the team, if you are returning after a sprint away, if you are picking up a new story, start here.

---

## The doctrine set

This doctrine is deliberately multi-file. Each file is scoped, cross-linked, and preserves the source shards verbatim wherever quality would be lost by paraphrase. Every file opens with a "What this covers" + "When you need this" header and ends with a `Last updated` + `Synchronized with` footer.

### Foundations (read in order)

- [00_README.md](./00_README.md) — this file.
- [01_Brand_DNA_and_Design_Rules.md](./01_Brand_DNA_and_Design_Rules.md) — gradient, palette, typography, forbidden design, canonical primitives, screen anatomy, microcopy + voice, accessibility.
- [02_Engineering_Principles.md](./02_Engineering_Principles.md) — TDD red-green-refactor, E2E built into every plan, `dj_teknal`'s principles applied to EusoTrip, Recursive Refinement Loops from the RLM paper.
- [03_Backend_API_Contract.md](./03_Backend_API_Contract.md) — tRPC procedure catalog, transport, auth cookie contract, error envelope, rate limits, WebSocket + realtime.
- [04_Database_and_Schema.md](./04_Database_and_Schema.md) — 380+ table inventory, tenancy model, 3-country data model, 9 verticals, 3 modes, 37+56 state machines, Drizzle policy.
- [05_Auth_Security_Compliance.md](./05_Auth_Security_Compliance.md) — JWT lifecycle, MFA, 24-role RBAC, isolation middleware, SOC 2, GDPR/CCPA, PCI, known vulnerabilities.
- [06_Third_Party_Integrations.md](./06_Third_Party_Integrations.md) — HERE Maps, Stripe, Plaid, Apple frameworks, ELD providers, FMCSA, CBP/CBSA/SAT/PHMSA, SendGrid/Twilio, AI routing, Azure, observability.

### Mode × Role specifications

- [10_Mode_TRUCK/00_Overview.md](./10_Mode_TRUCK/00_Overview.md)
  - [01_Driver.md](./10_Mode_TRUCK/01_Driver.md)
  - [02_Dispatch.md](./10_Mode_TRUCK/02_Dispatch.md)
  - [03_Catalyst.md](./10_Mode_TRUCK/03_Catalyst.md)
  - [04_Broker.md](./10_Mode_TRUCK/04_Broker.md)
  - [05_Shipper.md](./10_Mode_TRUCK/05_Shipper.md)
  - [06_Escort.md](./10_Mode_TRUCK/06_Escort.md)
  - [07_Carrier_Terminal_Admin.md](./10_Mode_TRUCK/07_Carrier_Terminal_Admin.md)
- [20_Mode_RAIL/00_Overview.md](./20_Mode_RAIL/00_Overview.md)
  - [01_Rail_Operator.md](./20_Mode_RAIL/01_Rail_Operator.md)
  - [02_Rail_Dispatcher.md](./20_Mode_RAIL/02_Rail_Dispatcher.md)
  - [03_Rail_Yard_Master.md](./20_Mode_RAIL/03_Rail_Yard_Master.md)
  - [04_Rail_Shipper.md](./20_Mode_RAIL/04_Rail_Shipper.md)
  - [05_Rail_Broker.md](./20_Mode_RAIL/05_Rail_Broker.md)
  - [06_Rail_Conductor.md](./20_Mode_RAIL/06_Rail_Conductor.md)
- [30_Mode_VESSEL/00_Overview.md](./30_Mode_VESSEL/00_Overview.md)
  - [01_Vessel_Captain.md](./30_Mode_VESSEL/01_Vessel_Captain.md)
  - [02_Vessel_First_Officer.md](./30_Mode_VESSEL/02_Vessel_First_Officer.md)
  - [03_Vessel_Port_Agent.md](./30_Mode_VESSEL/03_Vessel_Port_Agent.md)
  - [04_Vessel_Shipping_Line_Ops.md](./30_Mode_VESSEL/04_Vessel_Shipping_Line_Ops.md)
  - [05_Vessel_Terminal_Operator.md](./30_Mode_VESSEL/05_Vessel_Terminal_Operator.md)
  - [06_Vessel_NVOCC_Forwarder.md](./30_Mode_VESSEL/06_Vessel_NVOCC_Forwarder.md)

### Cross-cutting

- [40_Intermodal_and_Cross_Border.md](./40_Intermodal_and_Cross_Border.md) — USMCA, Carta Porte, ACE/ACI, VUCEM, SAT, NOM, TDG.
- [50_Verticals_Reference.md](./50_Verticals_Reference.md) — the 9 verticals in depth (hazmat, reefer, flatbed, livestock, auto-hauler, LTL, tanker, intermodal, general) × 3 countries.
- [60_Offline_First_and_Pulse_Watch.md](./60_Offline_First_and_Pulse_Watch.md) — F01–F16, unified outbox, voice dispatch grammar, dead-zone coast, satellite fallback, 9-state orb, watch doctrine.
- [70_Messaging_and_ESANG_AI.md](./70_Messaging_and_ESANG_AI.md) — conversation model, message types, push, Haul Lobby, ESANG model routing, prompt doctrine, memory, safety classifier.
- [80_User_Journeys_and_Load_Lifecycle.md](./80_User_Journeys_and_Load_Lifecycle.md) — canonical journeys (trucking FTL, rail intermodal, ocean, cross-border, hazmat, SOS, team, sleeper), state machines, latency budgets.
- [85_Figma_Gap_Audit_and_Recommendations.md](./85_Figma_Gap_Audit_and_Recommendations.md) — 77-item Figma queue, procedure mapping, alternates, P0/P1/P2 tiering, screens to add/delete.
- [90_App_Store_Strategy.md](./90_App_Store_Strategy.md) — single-binary doctrine, listing metadata, review gotchas, privacy manifest, subscriptions, phased release.
- [91_Web_Mobile_Parity.md](./91_Web_Mobile_Parity.md) — shared-everything principle, DTO contract, breaking-change policy, design tokens, feature flags, cross-platform user journeys.
- [92_Launch_Runbook_and_Rollback.md](./92_Launch_Runbook_and_Rollback.md) — T-14 to T+30 arc, SLOs, rollback triggers, remote config kill switches, Azure slot swap, incident response.

### Operational

- [95_Codebase_Continuity_and_Claude_Init.md](./95_Codebase_Continuity_and_Claude_Init.md) — the FINAL Claude Code init command, symlink hub, per-repo settings, git hooks, MCP server configuration.
- [98_Recursive_Language_Model_Integration.md](./98_Recursive_Language_Model_Integration.md) — RLM principles applied to EusoTrip, eusotrip-killers as a case study of recursive self-improvement.
- [99_Glossary_and_Appendices.md](./99_Glossary_and_Appendices.md) — terms, file paths, hex colors, contacts.

---

## Reader's guide

The shortest path from "I just got hired" to "productive" depends on your role. Follow these paths.

### New iOS engineer
1. [00_README.md](./00_README.md) (this file).
2. [01_Brand_DNA_and_Design_Rules.md](./01_Brand_DNA_and_Design_Rules.md) — learn the gradient, the forbidden patterns, the primitives.
3. [02_Engineering_Principles.md](./02_Engineering_Principles.md) — TDD is non-negotiable. Read it twice.
4. [10_Mode_TRUCK/01_Driver.md](./10_Mode_TRUCK/01_Driver.md) — the 010–099 Driver brick queue you will build.
5. [95_Codebase_Continuity_and_Claude_Init.md](./95_Codebase_Continuity_and_Claude_Init.md) — open Claude Code against the workspace.
6. Reference [60_Offline_First_and_Pulse_Watch.md](./60_Offline_First_and_Pulse_Watch.md) and [70_Messaging_and_ESANG_AI.md](./70_Messaging_and_ESANG_AI.md) for the big systems.

### New backend engineer
1. [00_README.md](./00_README.md).
2. [02_Engineering_Principles.md](./02_Engineering_Principles.md).
3. [03_Backend_API_Contract.md](./03_Backend_API_Contract.md) — 251 routers, 130+ procedures, the full map.
4. [04_Database_and_Schema.md](./04_Database_and_Schema.md) — 380+ tables, tenancy, migrations.
5. [05_Auth_Security_Compliance.md](./05_Auth_Security_Compliance.md) — JWT, RBAC, isolation.
6. [06_Third_Party_Integrations.md](./06_Third_Party_Integrations.md) — every external dependency.
7. [91_Web_Mobile_Parity.md](./91_Web_Mobile_Parity.md) — your DTOs feed two clients; never diverge.

### New designer
1. [00_README.md](./00_README.md).
2. [01_Brand_DNA_and_Design_Rules.md](./01_Brand_DNA_and_Design_Rules.md) — the full brand book lives there.
3. [80_User_Journeys_and_Load_Lifecycle.md](./80_User_Journeys_and_Load_Lifecycle.md) — design screens that serve real journeys.
4. [85_Figma_Gap_Audit_and_Recommendations.md](./85_Figma_Gap_Audit_and_Recommendations.md) — what we have, what we need, what we cut.

### New PM
1. [00_README.md](./00_README.md).
2. [10_Mode_TRUCK/00_Overview.md](./10_Mode_TRUCK/00_Overview.md), [20_Mode_RAIL/00_Overview.md](./20_Mode_RAIL/00_Overview.md), [30_Mode_VESSEL/00_Overview.md](./30_Mode_VESSEL/00_Overview.md) — the scope of the product.
3. [40_Intermodal_and_Cross_Border.md](./40_Intermodal_and_Cross_Border.md).
4. [50_Verticals_Reference.md](./50_Verticals_Reference.md).
5. [80_User_Journeys_and_Load_Lifecycle.md](./80_User_Journeys_and_Load_Lifecycle.md).
6. [90_App_Store_Strategy.md](./90_App_Store_Strategy.md).
7. [92_Launch_Runbook_and_Rollback.md](./92_Launch_Runbook_and_Rollback.md).

### Web platform engineer
1. [00_README.md](./00_README.md).
2. [91_Web_Mobile_Parity.md](./91_Web_Mobile_Parity.md) — read this in full.
3. [03_Backend_API_Contract.md](./03_Backend_API_Contract.md).
4. [04_Database_and_Schema.md](./04_Database_and_Schema.md).
5. [05_Auth_Security_Compliance.md](./05_Auth_Security_Compliance.md).

---

## How to read this doctrine

- **Shards are verbatim.** Wave-1 shard content was written by domain owners and is preserved unchanged wherever present. Do not paraphrase doctrine to fit a smaller page; if you cut, you lose the law.
- **Cross-links beat duplication.** Each file links out rather than duplicating content. If you find two files saying the same thing in different words, open a PR to collapse.
- **Every file ends with a footer.** The footer names the last-updated date and the scheduled task that is synchronized with it (`eusotrip-killers`). If the footer drifts from the latest firing, the doctrine is stale.
- **The doctrine self-improves.** See [98_Recursive_Language_Model_Integration.md](./98_Recursive_Language_Model_Integration.md). Each firing of the scheduled task runs a pass over this set and suggests diffs. You are looking at the current checkpoint of a living document.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task (see `/Users/diegousoro/Documents/Claude/Scheduled/eusotrip-killers/SKILL.md`)
