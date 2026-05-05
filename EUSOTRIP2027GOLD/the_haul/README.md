# The Haul — Engineering Doctrine

This folder contains the canonical doctrine for THE HAUL — EusoTrip's professional driver community + progression spine inside Eusoboards.

## Primary deliverables

- **THE_HAUL_ENCYCLOPEDIA.md** — the master synthesis (26,800 words, 55 chapters + 6 appendices). Read this top-to-bottom on Sprint 0.
- **THE_HAUL_ENCYCLOPEDIA.pdf** — the same content, dark-themed, paginated for reference. Generated via pandoc + xelatex.
- **THE_HAUL_ENCYCLOPEDIA.html** — standalone styled HTML matching the EusoTrip Pulse / Offline Mode Encyclopedia aesthetic. Open in Safari/Chrome and use Print → Save as PDF for an alternative pagination.
- **THE_TRILLION_DOLLAR_DOCTRINE.md** — the conversion playbook. Five plays (Driver Demo, Fleet Treaty, Lane Take-Over, Cross-Mode Halo, Founder's Witness) and the 90-day belief plan. Read alongside Part XI of the encyclopedia.
- **HERE_Call_Script_Frackowiak.md** — vendor-side call script for the HERE Technologies SDR follow-up (Alexandra Frackowiak, 2026-04-20 outreach). Threads The Haul's data feedback loop into HERE's Workspace Marketplace monetization. Reference this anywhere the HERE relationship surfaces in product or partnership conversations.
- **HERE_Email_Frackowiak_Missed_Call.md** — written-form recovery memo for the missed call. Substance over volume; reschedule + four asks (mapping activation, custom maps, marketplace partnership, enterprise launch support).
- **ZENITH_CORTEX_AGENTS_DOCTRINE.md** — the 50-agent research op synthesized into one engineering trunk. 10 pods of 5 chapters each (~46,000 words) covering OpenAI Agents Python SDK primitives, multi-agent patterns, memory/state/tracing, voice/realtime/MCP, production hardening, full migration of all 50 cortex agents, 24-role mapping, cross-platform parity (web tRPC + iOS Swift), ESANG voice on Realtime API, MCP server for iOS consumption, The Haul × Cortex emergent layer, and a 6-phase 90-day migration ladder. Closes with a Master Synthesis written for Mike "Diego" Usoro and an executive memo for the eusotrip-killers scheduled task team. Read this alongside Part XI of THE_HAUL_ENCYCLOPEDIA.md and the THE_TRILLION_DOLLAR_DOCTRINE.md for the complete agent-tier strategic picture.
- **ZENITH_NEARBY_INTERACTION_DOCTRINE.md** — the second 50-agent research op, this one tearing apart Apple's NearbyInteraction (UWB) framework and mapping every primitive onto the iOS app, the Pulse watchOS companion, the iPhone↔Watch sync layer, the 50-agent Cortex backend, and The Haul recognition system across all 24 user roles. 11 pods, ~24,000 words. Pod 11 (Diego's flagship enhancement) covers Pulse Watch-side NI sessions, sync hardening via PhonePresenceService (retires the stuck-orb bug class), watch-to-watch convoy, AirTag hazmat seal verification, and three new watch complications. Introduces the Cyan light (ninth color in The Haul recognition spectrum) and the data partnership leverage with HERE Workspace Marketplace. Same 6-phase 90-day ladder format with kill-switches, observability metrics, and rollback paths. Read alongside the Cortex doctrine — they share the role-manifest architecture and the SkillTier governance model.

## Source shards (10 doctrine teams, 50 agents)

The 10 source doctrine markdown files (`team_01_HERE_LBS_to_missions.md` through `team_10_launch_governance.md`) are the raw research output that the encyclopedia synthesizes. They live at the canonical Desktop path:

`/Users/diegousoro/Desktop/the_haul_doctrine/`

Engineering should treat the encyclopedia as authoritative. The shards are reference material for any chapter where the engineering team wants the underlying analysis (PSO design retrospectives, HERE LBS mapping, regulatory deep-dive, full mission grammar, etc.).

## Reading order for engineering

1. **Foreword + Chapter 00 + Chapter 03** — the framing, the "how to read this book," and the professional language doctrine. Non-negotiable; defines what driver-facing copy looks like.
2. **Part I (Origins & Philosophy)** — Chapters 01–04. The PSO lineage and the Eusoboards integration model.
3. **Part II (Mission Grammar)** — Chapters 05–09. Mission archetypes, tier ladder, state machine, Mission Board UI, load → Mission integration.
4. **Part X (Engineering Specs)** — Chapters 46–50. The procedure-by-procedure wiring map against the existing `gamification.ts` and `advancedGamification.ts` routers, the schema additions, the iOS implementation primitives.
5. **Part XI (Launch & Governance)** — Chapters 51–55. The phased launch ladder, the regulatory shield, the wellness floor, the SLO board.
6. **Appendix F** — Open questions and Sprint-by-Sprint API list. This is the implementation backlog.

## Reading order for the steering committee

1. **Foreword.**
2. **Chapter 03** (professional language doctrine — the brand-voice constraint).
3. **Part XI** (launch ladder, kill criteria, the Single Veto).
4. **Appendix B** (forbidden words guard rail).

## Cross-references

- Existing routers: `frontend/server/routers/gamification.ts` (1,871 lines, 36 procedures) and `frontend/server/routers/advancedGamification.ts` (31 procedures).
- Existing tables: `gamification_profiles`, `missions`, `mission_progress`, `badges`, `user_badges`, `loot_crates`, `reward_crates`, `rewards`, `haul_lobby_messages`, `haul_lobby_moderation_log`, `haul_lobby_user_strikes`, `esang_memories`.
- Existing services: `gamificationDispatcher`, `missionGenerator`, `hosEngine`, `lobbyModeration`.
- See Chapter 47 for the canonical schema additions list.

— *The Haul Synthesis Group, 2026-04-27.*
