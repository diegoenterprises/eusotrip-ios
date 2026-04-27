# 70 · Messaging + Chat + ESANG AI

**What this covers.** The complete messaging + ESANG AI doctrine for EusoTrip — two parallel messaging routers (SKILL §16 landmine), conversation model (5 shapes), message types, delivery guarantees (dual-path), read receipts + typing, push flow, Haul Lobby (raw-SQL cross-company driver chat), dispatcher → driver quick actions, Unsend + Swipe-to-Delete, ESANG AI (model routing Gemini/Claude/GPT, context injection, offline VoiceDispatch fallback, voice output, transcript UI, tip strips), ESANG V2 protocol, voice dispatcher orchestrator, mandatory disclaimers, prompt engineering, error handling, cost controls, regulatory boundaries, translations, learning/feedback, memory, safety classifier, rate limits, watch delivery, operational runbook. Source: wave-1 shard `team_MESSAGING_AI`.

**When you need this.** When building any messaging screen. When wiring ESANG. When scoping AI cost controls. When adding a new intent or language. When reviewing what ESANG is allowed to say.

**Cross-links.** Messaging backend: [03_Backend_API_Contract.md §4](./03_Backend_API_Contract.md). Offline voice grammar (what ESANG falls back to): [60_Offline_First_and_Pulse_Watch.md §3](./60_Offline_First_and_Pulse_Watch.md). Microcopy rules (what ESANG can/can't say): [01_Brand_DNA_and_Design_Rules.md Part D](./01_Brand_DNA_and_Design_Rules.md).

---

## 1. Purpose and scope

Governs every pixel of conversation, every token of AI, every ping of notification. Single source of truth for how drivers, dispatchers, shippers, brokers communicate with each other and with ESANG AI — our first-party orchestration intelligence. Messaging is the second-most-used screen after Dispatch Board; ESANG is the single most-common entry point for new-user engagement. Together carry ~41% of all p95 session time on mobile. Treat this section like a pilot's preflight checklist: skip a line and something goes wrong in the field.

---

## 2. Two parallel messaging routers (SKILL §16 landmine)

EusoTrip has **two messaging routers** — historical artifact from 2024 Communication Hub rewrite, known landmine documented in SKILL §16.

- **Canonical: `messages.ts`** — all new features, endpoints, client calls route here. Backs CommunicationHub v2 schema, supports conversation model in §3, emits events compatible with Team B Agent 2 WebSocket stack.
- **Legacy: `messaging.ts`** — kept alive because three tenants on grandfathered 2023 contract still use endpoints never migrated. **Do not add procedures.** Do not fix bugs here unless SEV-1 and equivalent fix cannot ship to `messages.ts` with client migration. If you find yourself reading `messaging.ts`, stop, re-read this paragraph, go to `messages.ts`.

**Rule of thumb**: **`messages.*` for all new work**. Every PR touching `messaging.ts` requires VP-level exception + attached deprecation ticket. Goal: zero traffic on `messaging.ts` by Q3 2027.

---

## 3. Conversation model — five shapes

CommunicationHub schema exposes five conversation shapes. Every message belongs to exactly one; every conversation has exactly one of:

1. **1:1** — driver-to-dispatcher, dispatcher-to-shipper, driver-to-driver (Haul Lobby DMs).
2. **Group** — named multi-party rooms, up to 64 members. Team dispatch rooms, regional ops, EusoTrip internal ops.
3. **Role-based** — derived membership, resolved at send time. Example: `dispatcher-to-all-drivers` fans out to every driver currently clocked in under that dispatcher's tenant. Membership dynamic; driver who clocks out mid-conversation stops receiving new messages but retains history access.
4. **Broadcast (Announcement)** — one-to-many, read-only for receivers. Safety bulletins, weather closures, rate changes. Replies go to sidecar thread, not broadcast.
5. **Thread (per-load)** — anchored to single `loadId`. Every load automatically gets a thread on creation; dispatcher, assigned driver, optionally shipper contact are auto-members. Thread dies 30 days after load final settlement.

All five share same `messages` table, differ only by `conversation_kind` discriminator. Never fork the table.

---

## 4. Message types

Every `messages` row has `message_type`. Allowed:

- **text** — UTF-8, up to 4,000 characters, emoji-capable.
- **image** — JPEG, PNG, HEIC; auto-compressed to 1600px longest edge; S3-backed with signed URLs.
- **doc** — BOL, POD, rate confirmation, permits. PDF or image; routed through Documents pipeline for OCR extraction + compliance hooks.
- **voice note** — M4A, up to 3 minutes, auto-transcribed by ESANG Voice for accessibility + search.
- **system** — load status change, geofence entry/exit, HOS violation warning. Rendered with neutral chip style, never replied to.
- **ESANG reply** — inline AI response inside conversation. Always tagged with "Powered by ESANG AI" strip (§15).
- **ephemeral** — auto-destruct after 24 hours. Only for Haul Lobby sensitive content. Audit trail preserved server-side; only UI disappears.

Clients must never invent a new `message_type`. Additions require migration, schema version bump, backward-compatible rendering fallback.

---

## 5. Delivery guarantees

Dual-path delivery:

- **Best-effort real-time** via WebSocket (primary) or HTTP long-poll (fallback). Team B Agent 2 owns socket layer. WebSocket available → p50 delivery <180ms; polling fallback interval 6 seconds. Clients must not assume socket connected; every send is idempotent + acknowledged.
- **Durable** via OfflineQueue Lane 4 (messaging). Any message composed while offline queued locally, persisted to encrypted SQLite, replayed on reconnect with exact client timestamp. Lane 4 dedicated retry: exponential backoff up to 5 attempts, then surfacing "failed to send" banner with manual retry.

**Delivery contract**: **a message composed on-device will reach the server or surface an error. It will never silently vanish.** If you write code that can silently drop a message, you are writing a bug.

---

## 6. Read receipts + typing indicators

**Read receipts** on by default in 1:1 + thread conversations, off by default in role-based + broadcast (fan-out at scale would DoS the read-receipt table). Users can disable per conversation; other party sees "Read receipts off" in header. Receipts are best-effort + eventually consistent — guarantee delivery of receipt within 30 seconds of app foregrounding, not instantly.

**Typing indicators** are ephemeral and **never stored server-side**. Sent over dedicated socket channel with 4-second TTL — if client stops typing for 4 seconds, indicator clears automatically. No persistence of "last typing at" anywhere. Privacy decision, load-bearing: do not add persistence.

---

## 7. Push notification flow

Messages arriving when app backgrounded or terminated delivered via push:

1. New message persisted by `messages.ts`.
2. Pub/sub event fires to push dispatcher.
3. `push.ts` router formats platform-specific payload (APNs iOS + watchOS, FCM Android) with conversation ID, preview text (redacted for ephemeral), deep link.
4. APNs delivers to registered device tokens.
5. iOS displays; tap opens app via deep link directly into conversation thread.

For watchOS, parallel APNs push targets paired watch, delivers short form. See §25 for truncation.

Push not guaranteed — APNs can drop, tokens expire, users disable. Reconcile on app foreground by refetching unread counts.

---

## 8. The Haul Lobby

Cross-company driver-only chat. Unique in two ways: spans tenant boundaries (drivers from different carriers meet here) AND stored in raw-SQL tables rather than CommunicationHub schema. Table prefix `haul_lobby_*` (see SKILL §16 landmine — **this is the only place in the app where raw-SQL tables are sanctioned; treating them as ORM-backed will fail**).

Rules:
- **Driver-only** — no dispatchers, shippers, brokers, admins.
- **Topics region-based**: Pacific NW, Mountain West, Great Lakes, Southeast, Northeast, Texas Triangle, West Coast I-5, Rockies, Cross-Border. Moderated by elected driver-moderators (one per region) + Team Trust & Safety.
- **Three-strike system**: offensive content, doxxing, recruitment spam → strike 1 (24h ban), strike 2 (7-day), strike 3 (permanent, DOT-flagged for review).
- **No load-brokering in Lobby** — drivers caught tendering or claiming loads outside official board get instant strike.
- **Ephemeral messages allowed** and commonly used.

Community benefit, not revenue surface. Not monetized, no ads, no ESANG training on content.

---

## 9. Dispatcher → Driver Quick Actions

Inside any dispatcher-to-driver thread, composer exposes five quick-action chips. Structured messages (not free text) producing both system message + side-effect:

- **Accept load** — triggers load acceptance, advances state, fires settlement pre-authorization.
- **Decline** — requires reason code (ELDT, safety, HOS, other); logged to dispatcher scorecard.
- **Arrived at pickup** — stamps load with geofenced arrival time, starts detention clock.
- **Delivered** — captures POD requirement, opens signature/photo capture flow.
- **Request extension** — asks for 15/30/60/120-minute delivery extension; dispatcher must approve or reject within 10 minutes.

Each renders as rich card in thread with visible audit trail: who tapped, when, from what geolocation (nearest 1km for privacy). Taps failing precondition (e.g., "Delivered" with no POD attached) show inline error rather than silently completing.

---

## 10. Unsend (Task #33)

Shipped in Wave 0. Users can delete a sent message within **15-minute window** from both sender's and recipient's rendered view. Row not physically deleted — soft-flagged `unsent_at = NOW()`, rendered body replaced with "Message unsent" on both sides.

**Audit trail preserved.** Original content retained server-side for 7 years (compliance + subpoena response) but **never surfaced in client APIs**. Only path to original is legal-hold export pipeline requiring signed warrant + two-party internal approval. Do not build any client endpoint returning unsent content.

---

## 11. Swipe to Delete (Task #30)

On inbox list, swipe left on conversation reveals Delete action. Deletes conversation from user's inbox only — other participant still sees it. **Client-side thread dismissal, not server-side deletion.** Underlying messages retained. User can restore by receiving new message in conversation (pops back into inbox).

Bugs here high-visibility — misconfigured swipe that nukes conversation on both sides is SEV-2 incident. Test idempotent-swipe case: swiping twice in rapid succession must not produce two DELETEs.

---

## 12. ESANG AI conversation

ESANG AI is in-app orchestration intelligence. **NOT a generic chatbot.** Domain-specialized assistant with access to user's load, HOS, wallet, weather, compliance context. How drivers ask "what's my next load?", "can I take a 30-minute break here?", "what's my current week gross?", "is the weigh station on I-40 open?" without navigating menus.

### 12.1 Model routing

ESANG routes queries to different backing models based on query shape:

- **Gemini 2.5 Flash** — default. 80%+ of traffic. Short factual queries; load lookups; HOS arithmetic; wallet balance questions. Cost + latency optimized (sub-second typical).
- **Claude (Sonnet 4.x family)** — long-context reasoning, document summarization (BOL/POD/rate-con), compliance interpretation, multi-step planning. Trip planning routes here.
- **GPT (5.x family)** — voice-first scenarios and when best natural-sounding Spanish/French output needed. A/B testing against Gemini on quality-sensitive paths.

Routing decided server-side by `esangAIv2.ts` dispatch layer. **Clients never specify a model** — asking for specific vendor is anti-pattern, stripped from request.

### 12.2 Context injection

Every ESANG call injects user-specific context bundle before prompt reaches model:

- Active load (origin, destination, current stage, shipper, commodity).
- HOS state (hours remaining in drive clock, duty clock, 70-hour window).
- Wallet snapshot (pending settlement, today's earnings, fuel card balance).
- Weather along active route (next 6 hours, 24-hour outlook).
- Compliance status (CDL expiration, medical card, permits, upcoming inspections).

Injection in `esangAIv2.ts`, cached per-user 60 seconds to avoid hammering backend services. If backend context service degraded, inject `[context unavailable]` sentinel, let model know — model trained to respond with partial answer + suggest retry rather than confabulate.

### 12.3 Offline fallback — VoiceDispatch local grammar

When device offline or AI unreachable, ESANG falls back to **VoiceDispatch** — local grammar-based intent parser in app binary. Handles 50 most common intents without network call. Responses deterministic template strings. Not smart, but always available.

Switchover automatic: if AI router returns 5xx twice in 10 seconds, flip to VoiceDispatch for next 60 seconds, then retry. Users see subtle "offline assistant" badge on ESANG avatar.

### 12.4 Voice output

- **iOS** — `AVSpeechSynthesizer` with user-selectable voice (default: system voice, en-US female). Respects system silent switch + Do Not Disturb.
- **watchOS** — `WKInterfaceDevice` text-to-speech. Shorter outputs (max 120 chars spoken) because watch speaker is thin.

Voice output **off by default**; users enable in Settings > ESANG > Voice replies. Once on, stays across sessions.

### 12.5 Transcript UI

While ESANG listening, transcript UI updates live (interim). On submit, final transcript replaces interim and query dispatched. If user corrects interim before submit, correction wins. Interim never sent to model — only final user-confirmed text.

### 12.6 Tip Strips

Short actionable insights (under 80 characters) ESANG generates + places inline in surfaces:
- Wallet §6 factoring ("Factor now: $2,340 available, $42 fee").
- Earnings header ("You're $180 above last week at this hour").
- HOS widget ("Break in 42 min avoids violation").
- Load card ("Detention likely — arrived 25 min early").

Pre-computed in batch for common scenarios, cached aggressively. **Never display if ESANG confidence <0.7.**

---

## 13. ESANG V2 Protocol

V2 protocol in `esangAIv2.ts` is wire format for AI conversations:

- **Request envelope** — user ID, conversation ID, query text, context hash, model routing hint, locale.
- **Streaming response** — SSE with token-level chunks for visible streaming + final structured block containing tool calls, citations, confidence score.
- **Tool calls** — ESANG can request structured data from backend (e.g., "get load detail for LD-9821") via tool calls; V2 formalizes tool-call JSON schema.
- **Cacheable responses** — include cache-control block; identical (query, context hash) pairs skip model entirely on next call within TTL.

V1 (inside `esangAI.ts`) deprecated for new client code but retained for watchOS until Wave 2. **All new mobile code uses V2.**

---

## 14. Voice dispatcher orchestrator

`esangVoiceOrchestrator.ts` wraps ESANG Voice with higher-level orchestrator providing AI-dispatched load suggestions.

Flow: driver says "find me a load home" → orchestrator pulls current location, HOS budget, equipment, home-base preference → queries load board with ranked shortlist → speaks top three options with one-sentence summaries. Driver can accept by voice ("take the second one") without ever opening app.

Safety feature as much as convenience — we want drivers to interact hands-free while driving. Orchestrator refuses to take actions requiring visual review (POD capture, rate confirmation review), tells driver to pull over.

---

## 15. Mandatory disclaimers

Every ESANG reply in UI carries phrase **"Powered by ESANG AI™"** in 10pt muted footer. **Non-optional.** Do not ship a screen rendering ESANG response without the strip.

For hazmat + safety-critical questions, ESANG appends: **"This is not a substitute for your dispatcher's judgment. For hazmat or safety decisions, call dispatch."** Model prompt-engineered to emit verbatim; client renders as distinct block.

---

## 16. Prompt engineering

EusoTrip system prompt is company-confidential, lives in `esangAIv2.ts` as versioned constant. Key principles:

- ESANG is "an AI dispatch copilot for EusoTrip drivers."
- **Never reveal backend internals** (table names, service names, vendor names, model vendor).
- **Never make up data.** If data field missing from context, say "I don't have that right now" — do not confabulate a load number, earnings figure, HOS remaining time.
- Default to **U.S. units** (miles, gallons, pounds). Switch to metric if user locale `fr-CA` or `es-MX`.
- Default tone: concise, warm, respectful. No slang. **No emojis in ESANG output.**
- Never recommend illegal action (HOS bypass, log falsification, weigh-station avoidance).

Prompt A/B tested weekly. Changes require sign-off from Product + Safety.

---

## 17. Error handling

If ESANG unavailable (router 5xx, timeout, explicit degraded flag from orchestration), client surfaces: **"Esang is unavailable right now"** with Retry button + subtitle indicating degradation ("Voice transcription down — typed queries still work" when subsystem known).

**No stack trace.** **No "model X returned error Y"** — vendor names + internal error codes stay server-side. If user retries three times in rapid succession, auto-suggest VoiceDispatch fallback if query matches known intent.

---

## 18. Cost controls

AI tokens cost real money; a chatty user can spend us into the ground:

- **Per-user per-day token budget** — 40,000 input tokens + 8,000 output tokens per driver per day. Heavy-use enterprise tenants get custom cap. At 80% of budget, ESANG surfaces "You're near your daily AI limit — I'll be briefer." At 100% → VoiceDispatch local grammar until midnight user-local.
- **Aggressive caching on common queries** — "What's my HOS?" asked twice within 60 seconds returns cached response without hitting model. Cache key includes user ID + context hash.
- **Debounce repeated asks** — client debounces identical queries within 3 seconds to prevent fat-finger double sends.
- **Prompt compression** — context bundle compressed to minimum viable shape per query type (don't send wallet context for weather question).

Token metering reported nightly to Finance. Alerts fire if cost-per-active-user breaches $0.12/day.

---

## 19. Regulatory boundaries

ESANG **cannot** provide legal, medical, or final compliance advice without human review. **Hard line.**

- **Legal**: "Can I refuse this load?" → ESANG summarizes rights but defers to driver's contract + suggests contacting HR or legal.
- **Medical**: "My back hurts, can I drive?" → ESANG responds "I can't give medical advice. Please consult a medical professional" + surfaces one-tap route to employer's nurse hotline (if configured) or 911.
- **Compliance**: "Is my trailer DOT-compliant?" → ESANG can surface most recent inspection record but refuses to stamp anything as "compliant." Defers to human inspector.

**Safety protocol always wins.** If driver says "I'm in a crash" — ESANG immediately says "Call 911" and surfaces dialer.

---

## 20. Translations

ESANG responds in user's preferred language, one of **English, Spanish, French**. Preference stored on user profile; client includes in every request; system prompt is bilingual-aware. **Do not translate user queries** — model handles native-language input directly.

Three caveats:
- Legal disclaimers + mandatory safety phrases always shown in English AND user's preferred language (side by side).
- Spanish includes both Mexican + US Latino variants; bias to US Latino unless locale explicitly `es-MX`.
- French is Québécois for Canadian routes, continental French elsewhere.

---

## 21. Learning + feedback

Every ESANG reply renders thumbs up / thumbs down pair in footer. Thumbs-down opens short form with three radio buttons (wrong info, unhelpful, offensive) + optional text field. Feedback fed into reinforcement signal pipeline informing weekly prompt tuning + nightly retraining of routing classifier (which decides Gemini vs Claude vs GPT).

Feedback PII-scrubbed before leaving user's tenant. **We do not train external vendor models on user data** — feedback used only for routing + prompt improvements internally.

---

## 22. Memory

ESANG has per-user conversation memory with **30-day TTL**. Stores:

- Recent query patterns (personalization — driver always asks about Spanish-language tip strips gets them by default).
- User-expressed preferences ("call me Al, not Alfred").
- Frequently referenced loads + routes.

Does NOT store:
- Driver medical mentions. If user says "my knee is bothering me," sentence filtered out of memory before persistence.
- Driver complaints about co-workers or employers (reduces legal risk).
- Anything flagged as ephemeral by safety classifier.

Memory encrypted at rest with per-tenant key, user-viewable + user-deletable via Settings > ESANG > My memory.

---

## 23. Safety classifier

Every ESANG query passes through safety classifier before reaching model. Flags:

- **Dangerous medical DIY** — "how do I stop bleeding while driving" → refuse + surface 911.
- **HOS bypass / log falsification** — "how do I edit my log to show more rest" → refuse + escalate to compliance officer via email notification.
- **Violence or self-harm** — refuse + route to mental health resources + (if severe) trigger silent alert to employer-configured contacts.
- **Illegal activity** — refuse + log for T&S review.

Flagged queries **NOT stored in user memory, NEVER used for training, logged server-side only in restricted audit table** accessible to T&S + legal.

---

## 24. Rate limits + latency budgets

- **p95 latency <2.5 seconds** for short queries (HOS status, wallet balance, simple load lookups).
- **p95 latency <8 seconds** for complex diagnose queries (multi-step compliance explanation, trip planning, long-context doc summarization).
- **Rate limit** — 60 queries per user per minute ("I'll be briefer" threshold kicks in at 20/min).

Budgets measured weekly. Sustained breach triggers model-routing review + potential vendor swap in `esangAIv2.ts`.

---

## 25. Watch message delivery

Messages on watchOS:

- **Truncation at 80 characters** for both inbound messages + ESANG replies. Longer cut with ellipsis.
- **Expand on tap** — tap notification opens full-bleed view with complete message + scroll.
- **Voice replies only for ESANG** — users can dictate reply to dispatcher message via watch mic; peer-to-peer message composition from watch limited to canned responses ("Copy that", "Running late", "ETA 30 min").
- **Quiet hours** — watch respects iOS Do Not Disturb + adds "quiet on wrist" mode between 10pm–6am local unless user overrides.

---

## 26. Operational runbook quick reference

| Situation | Response |
|---|---|
| WebSocket down, socket storm | Fall back to polling at 6s; alert Team B Agent 2 |
| ESANG 5xx sustained | Flip client to VoiceDispatch; page on-call ML |
| Push tokens expiring en masse | Refresh on next foreground; notify iOS team |
| Haul Lobby strike storm | Pause moderation auto-execute; escalate to T&S lead |
| Token budget cost alert | Page Finance + ML on-call; review caching |
| Unsend audit-leak report | SEV-1; page Legal + Security immediately |
| Voice transcription degraded | Surface "typed queries still work" banner |
| Cross-locale rendering broken | Freeze i18n release; notify Localization |

---

## Closing principle

The messaging and AI surface is where EusoTrip most directly touches a driver's day. A broken message means a late load; a confabulated ESANG answer means a driver makes a wrong turn or misses an HOS break; a missed push means a shipper thinks we ghosted them. Every engineer who touches this section owes the app the same care a dispatcher owes a driver: **precision, honesty, and the willingness to say "I don't know" when you don't.** Build accordingly.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
