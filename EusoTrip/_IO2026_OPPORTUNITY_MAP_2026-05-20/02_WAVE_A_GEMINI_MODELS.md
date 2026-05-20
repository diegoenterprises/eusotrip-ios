# Wave A — Gemini Models × ESang Dispatcher
**Agent #1 deliverable** | 8 opportunities

## Announcements covered
1. Gemini 3.5 Flash — 4× faster than Gemini 3.1 Pro
2. Gemini Omni — multimodal video generation
3. Gemini Intelligence — multi-step background orchestration
4. thinking_level parameter — control reasoning depth
5. Thought Signatures — encrypted reasoning state across turns
6. Managed Agents in Gemini API — single-call agent spawn
7. Regional dialect voice models
8. Daily Brief in Gemini app + Universal Cart

## Opportunity #1 — Gemini 3.5 Flash drop-in swap (P0)
- **Files:** `esangVoiceServer.ts` lines 88-94, `voiceLocaleAdapter.ts` lines 42-46, `EsangVoiceWatch.swift` line 329 (`dispatchToServer`)
- **Approach:** Drop Gemini 3.5 Flash as primary classifier; keep pattern-engine fallback for offline; swap model ID in single config
- **Impact:** 500ms → 150ms voice latency across all 12 roles. Perceivable UX speedup on truck radio + watch.
- **Effort:** M (3-5d). No infra; ships solo. Sprint 1.

## Opportunity #2 — thinking_level cost/latency tuning (P0)
- **Files:** `esangVoiceServer.ts`, new `esangThinkingConfig.ts` (intent → thinking_level lookup table)
- **Approach:** Lightweight thinking (L) for high-confidence queries (ETA, location); deep thinking (M/H) for ambiguous requests (re-route, HOS conflict). Cache thinking results per (shipmentId, intent) for 5 min.
- **Impact:** 30–40% Gemini API cost savings. "Instant" replies on simple intents; "considered" replies on complex ones.
- **Effort:** M. Parametric only.

## Opportunity #3 — Thought Signatures for multi-turn (P0)
- **Files:** `esangVoiceServer.ts` followUp flow lines 251-258, `EsangVoiceWatch.swift` line 214, new `esangThoughtSignatureCache.ts`
- **Approach:** When action requires confirmation, return signature with prompt. On re-entry, decrypt + replay to speed reconsideration. Audit log signature digest for compliance.
- **Impact:** Multi-turn voice (HOS override → reroute → customs filing) feels like a conversation. 40% faster multi-step workflows.
- **Effort:** S (1-2d). Ships solo. Sprint 1.

## Opportunity #4 — Managed Agents for document generation (P1)
- **Files:** New `esangAgentDocumentGenerator.ts`, `esangVoiceServer.ts` (new 'action.generate_documents' case), `esangMultiVehicleContext.ts` (customs_docs_needed trigger)
- **Approach:** POST /api/esang/agents/document-gen with {shipmentId, docTypes: ['POD','CF3461','hazmat']}. Gemini API spawns isolated agent (Antigravity sandbox). Agent pulls shipment data, renders to PDF (puppeteer/wkhtmltopdf), uploads to S3.
- **Impact:** "Manual POD + 5-min customs filing" → "voice request → auto-PDF in <60s". Audit trail via agent logs.
- **Effort:** L (>1w). Dependency: Antigravity sandbox security review + PDF template library.

## Opportunity #5 — Regional dialect voice (P0)
- **Files:** `EsangVoiceWatch.swift` (new voiceOutput.locale field), `esangVoiceServer.ts` (new VoiceActionReply.voiceDialect field), `voiceLocaleAdapter.ts` (LocalePatternBundle.dialectVariant: 'border'/'local'/'south')
- **Approach:** User profile field: preferred_voice_dialect. Gemini 3.5 Flash TTS output: voice_name e.g., "Spanish (Mexican, Guadalajara)". Watch speaker uses OS native TTS or fallback to Gemini TTS API.
- **Impact:** Voice replies in home dialect = retention +5–10% in target regions. Enables Southwest/Southeast/Quebec ops.
- **Effort:** S. Dependency: regional voice model availability in Gemini TTS API.

## Opportunity #6 — Gemini Omni explainer videos (P2)
- **Files:** `EsangVoiceWatch.swift` (new video reply handler), `esangVoiceServer.ts` (new endpoint POST /api/esang/voice/video-explain), `esangMultiVehicleContext.ts` (ProactiveAlert video trigger)
- **Approach:** Gemini Omni input: {shipmentId, vehicleIds, syncWindowState, context}. Output: MP4 URL + captions. Reply includes `visual.kind: 'explainer_video'`.
- **Impact:** Shippers/brokers: explainer videos reduce support tickets 20–30% (HOS, customs, reroute complexity). Drivers: visual warnings safer.
- **Effort:** L. Dependency: video hosting + CDN integration.

## Opportunity #7 — Gemini Intelligence async customs filing (P1)
- **Files:** `esangVoiceServer.ts` (intelligence queue middleware), new `esangIntelligenceOrchestrator.ts`
- **Approach:** Voice reply: "I'll file your customs docs. Check messages in 2 min." Task backbone: Bull/Temporal/Cloud Tasks. Callback bridge to ESang threads.
- **Impact:** 30 min customs filing → 2 min voice request → async execution = 15–30 min time savings per cross-border load.
- **Effort:** L. Dependency: task queue infrastructure + customs filing API client.

## Opportunity #8 — Daily Brief + Universal Cart deep link (P0)
- **Files:** New `esangGeminiBriefAdapter.ts` (POST /api/integrations/gemini-brief), new `esangUniversalCartView.ts`, `EsangVoiceWatch.swift` (deep link)
- **Approach:** OAuth 2.0 bridge to Gemini app (user consent). Daily Brief API: POST /api/gemini/brief with {userRole, regionFilter, activeLoads}. Universal Cart treats each leg (pickup → delivery → customs) as cart item with progress bar + ETA.
- **Impact:** Daily Brief = faster status scanning (5 sec vs. 30 sec per app launch). Cart UI makes multi-leg handoff visual + intuitive.
- **Effort:** M. Dependency: Gemini app OAuth setup.

---

## Top 3 lock-in priorities (in order)

### 1. Gemini 3.5 Flash + thinking_level (Opps #1 + #2)
Ship in 5–7d as pure API swap. No infra. **Perceivable UX win for all 12 roles** (500ms → 150ms latency). Cost savings (thinking_level routing) = immediate COGS leverage. First-mover advantage in voice latency in freight TMS space (competitors at 500ms+).

### 2. Managed Agents for document generation (Opp #4)
Solves compliance nightmare (customs forms, hazmat labels, PODs). Single-call agent spawning = **new service tier**. Antigravity sandbox = security moat. **Only freight TMS with managed-agent doc gen.**

### 3. Thought Signatures for multi-turn (Opp #3)
1–2d to integrate. Multi-step voice intents feel like a conversation, not a form. Drivers/dispatchers: 40% faster multi-step workflows. Unique voice UX in freight.
