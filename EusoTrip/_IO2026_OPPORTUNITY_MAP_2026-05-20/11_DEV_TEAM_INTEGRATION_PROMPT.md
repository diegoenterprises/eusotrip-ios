# EusoTrip × Google I/O 2026 — Dev Team Integration Brief
**Date:** 2026-05-20
**Founder:** Diego Usoro
**Scope:** Lock in iOS app + web platform e2e integration of the 52 I/O 2026 opportunities. iOS is the primary surface; web mirrors. Every ticket lists Swift files AND TypeScript files. Round-trip wire contract guaranteed by the canonical foundation shipped 2026-05-20.

---

## 1. Read these four sources of truth FIRST

Before touching any code, open in order:

1. **`EusoTrip/_PARITY_AUDIT_2026-05-20/00_CANONICAL_WIZARD_INVENTORY.md`** — the locked source-of-truth for verticals, trailer codes, FSM, documents. Every new feature must bind to canonical enums.

2. **`EusoTrip/_IO2026_OPPORTUNITY_MAP_2026-05-20/00_EXECUTIVE_SUMMARY.md`** — 52 opportunities, 3-window rollout (Q3 / Q4 / Q1), top-10 P0 list.

3. **`EusoTrip/_IO2026_OPPORTUNITY_MAP_2026-05-20/01_OPPORTUNITY_MATRIX.md`** — the sortable master table; this is the ticket source.

4. **`EusoTrip/_IO2026_OPPORTUNITY_MAP_2026-05-20/10_DEV_TEAM_PROMPT.md`** — the per-engineer Sprint 1-6 plan; this assigns work.

The eight wave files (`02–09`) are the deep-dive references. Read them when working a ticket.

---

## 2. iOS is primary — every ticket lands Swift first, then web

The platform's center of gravity is the iOS Swift app at `EusoTrip/`. Web (`eusoronetechnologiesinc/frontend/`) mirrors after iOS is green. **No web-first tickets in this brief.** When a feature requires server endpoints, the iOS PR ships the endpoint; the web PR consumes it later.

Exception: tickets B (XR — Android-only hardware ship Fall 2026) and E5 (native Android app generation) are non-iOS by definition. Everything else: iOS first.

---

## 3. The 17 P0 tickets — iOS + web file map

Each ticket below lists:
- **iOS file(s)** — Swift surfaces to touch
- **Web file(s)** — TypeScript mirror to touch (if applicable in Q3)
- **Server file(s)** — shared backend
- **Foundation dependency** — which canonical enum (from `_PARITY_AUDIT_2026-05-20/`) it must bind to
- **Effort** — S (1-2d) / M (3-5d / week) / L (>1 week)
- **Acceptance** — single bullet that proves done

### P0-1 · Gemini 3.5 Flash drop-in swap (voice dispatcher)
- **iOS:** `EusoTrip/Services/ESangVoiceClient.swift` (model ID), `EusoTrip/ViewModels/ESangVoiceViewModel.swift` (response decoder), `EusoTrip Pulse Watch App/Sources/ESangWatchClient.swift`
- **Web:** `eusoronetechnologiesinc/frontend/client/src/lib/esangClient.ts`
- **Server:** `wiring_stubs/server/esangVoiceServer.ts` lines 88-94, `voiceLocaleAdapter.ts` lines 42-46
- **Foundation:** none (model swap is opaque to the canonical layer)
- **Effort:** M
- **Acceptance:** voice latency p50 drops from ~500ms to <180ms on iPhone + Pulse Watch; web parity within 10%

### P0-2 · thinking_level parameter (intent-aware reasoning)
- **iOS:** `EusoTrip/Services/ESangVoiceClient.swift` (intent → thinking_level mapping), `EusoTrip/Models/ESangIntent.swift` (new file — 12 intents + thinking_level annotation per intent)
- **Web:** `eusoronetechnologiesinc/frontend/client/src/lib/esangClient.ts` mirror enum
- **Server:** `wiring_stubs/server/esangVoiceServer.ts`, new `esangThinkingConfig.ts`
- **Foundation:** `TrailerCode` + `Vertical` (some intents are vertical-aware: hazmat queries → thinking_level=high)
- **Effort:** M
- **Acceptance:** 30%+ Gemini API cost reduction on simple intents while complex intents (HOS conflict, customs reroute) retain accuracy

### P0-3 · Thought Signatures for multi-turn voice
- **iOS:** `EusoTrip/Services/ESangVoiceClient.swift` (signature cache + replay), `EusoTrip/ViewModels/ESangConversationViewModel.swift` (new file — manages turn-by-turn state)
- **Web:** `eusoronetechnologiesinc/frontend/client/src/hooks/useEsangConversation.ts`
- **Server:** `wiring_stubs/server/esangVoiceServer.ts` followUp flow (lines 251-258), new `esangThoughtSignatureCache.ts`
- **Foundation:** `LoadStateFSM` (signatures often gate FSM transitions — confirm "I'm at the dock" → AT_PICKUP)
- **Effort:** S
- **Acceptance:** multi-step voice intent (e.g. "reroute to Houston" → "confirm" → "send to driver") completes 40% faster end-to-end

### P0-4 · Regional dialect voice (es-MX, fr-CA, en-AU, etc.)
- **iOS:** `EusoTrip/Services/ESangTTSPlayer.swift` (new file), `EusoTrip/Models/UserVoicePreference.swift` (new field), `EusoTrip/Views/Settings/VoiceDialectPicker.swift`
- **Web:** `eusoronetechnologiesinc/frontend/client/src/components/settings/VoiceDialectPicker.tsx`
- **Server:** `wiring_stubs/server/voiceLocaleAdapter.ts` LocalePatternBundle.dialectVariant field
- **Foundation:** none
- **Effort:** S
- **Acceptance:** drivers in Mexico hear voice in Mexican Spanish (Guadalajara dialect), QC drivers in Quebec French; verifiable via user pref in Settings

### P0-5 · Daily Brief + Universal Cart deep link
- **iOS:** `EusoTrip/Services/GeminiBriefAdapter.swift` (new file), `EusoTrip/Views/Home/DailyBriefWidget.swift` (new file), Universal Cart link → `EusoTrip/Views/Wallet/CartView.swift`
- **Web:** `eusoronetechnologiesinc/frontend/client/src/components/home/DailyBriefWidget.tsx`, `CartWidget.tsx`
- **Server:** new `wiring_stubs/server/esangGeminiBriefAdapter.ts` (POST `/api/integrations/gemini-brief`)
- **Foundation:** `Vertical` (brief content varies by role × verticals shipper operates)
- **Effort:** M
- **Acceptance:** OAuth to Gemini app succeeds; Daily Brief widget renders 6:00 AM local with role-tailored cards (shipper sees loads + AR, broker sees rate sheets, dispatcher sees HOS-aware schedule)

### P0-6 · Astra Pre-Trip DVIR (iOS-native vision)
- **iOS:** `EusoTrip/Views/Driver/011_PretripDVIR.swift`, `EusoTrip/ViewModels/PretripDVIRViewModel.swift` (extend with Astra), `EusoTrip/Services/AstraVisionService.swift` (new file — wraps Gemini Vision API)
- **Web:** N/A (driver-only)
- **Server:** new `wiring_stubs/server/astraDvirEndpoint.ts` (POST `/api/astra/dvir/analyze`)
- **Foundation:** `TrailerCode` (DVIR checklist is trailer-specific — see ticket T-018 in parity audit), `LoadStateFSM` (DVIR result enters hash chain)
- **Effort:** M
- **Acceptance:** driver points camera at tire → Astra auto-fills tread depth + brake pad wear + cracks; output cryptographically signed; entry appears in `dualLayerHashChain` as `vehicle.dvir.astra_observed`

### P0-7 · Astra Hazmat Placard + ERG hands-free
- **iOS:** `EusoTrip/Views/Driver/HazmatPlacardScanView.swift` (new file), `EusoTrip/Services/AstraVisionService.swift` (placard OCR), `EusoTrip/Services/ERGLookupService.swift` (extend with multi-turn)
- **Web:** N/A (driver-only)
- **Server:** `wiring_stubs/server/ergSearchRouter.ts` (extend with multi-turn `getFollowUpContext()`), `wiring_stubs/server/astraDvirEndpoint.ts` (new `/placard-detect` route)
- **Foundation:** `Vertical.hazmat` + `TrailerCode.isHazmatEligible` + `DocumentRequirements` (hazmat manifest, ERG info, segregation verification)
- **Effort:** M
- **Acceptance:** driver wearing audio-only XR (or holding iPhone) says "scan placard" → Astra OCRs UN number → ESang reads ERG guide in driver's preferred dialect; `HazmatOverlay.placardsAffixed` written to hash chain

### P0-8 · Hazmat ERG multi-turn agent
- **iOS:** `EusoTrip/Views/Shipper/257_PostLoadHazmatSubform.swift`, `EusoTrip/Services/ERGLookupService.swift` (multi-turn context)
- **Web:** `eusoronetechnologiesinc/frontend/client/src/pages/LoadCreationWizard.tsx` (Step 2 hazmat subform, opened in surgical pass)
- **Server:** `wiring_stubs/server/ergSearchRouter.ts` + new `compliance.ts` router
- **Foundation:** `Vertical.hazmat`, `DocumentRequirements.forVertical(.hazmat)`, `49_cfr_172_101_seed.json`
- **Effort:** M
- **Acceptance:** shipper asks "What's the ERG guide for UN1830?" → "Sulfuric acid, Guide 137" → "Can I haul with class 3 flammables?" → `segregationCheck()` returns incompatible with citation; conversation preserved via thought signatures

### P0-9 · Shipment status multi-turn agent
- **iOS:** `EusoTrip/Views/Shipper/TrackShipments.swift` (new agent panel), `EusoTrip/Services/ShipmentAgentService.swift` (new file)
- **Web:** `eusoronetechnologiesinc/frontend/client/src/pages/TrackShipments.tsx` (replace search-by-load-ID box)
- **Server:** new `wiring_stubs/server/shipmentAgentRouter.ts` (POST `/api/agent/shipment-status`)
- **Foundation:** `LoadStateFSM` + `Vertical` (status answer surfaces compliance for vertical) + `TrailerCode` (placard/equipment context)
- **Effort:** M
- **Acceptance:** shipper asks "Where is LD-2026-04812?" → location, ETA, driver name, on-time/late; follow-up "Show me the placard" → renders hazmat placard card

### P0-10 · Compliance segregation agent
- **iOS:** `EusoTrip/Views/Compliance/ComplianceAgentView.swift` (new file)
- **Web:** `eusoronetechnologiesinc/frontend/client/src/components/customs/SegregationAgent.tsx`
- **Server:** extend `wiring_stubs/server/ergSearchRouter.ts` segregationCheck with multi-turn, new `compliance.ts` router
- **Foundation:** `Vertical.hazmat`, `DocumentRequirements.crossBorder`, segregation matrix from `49_cfr_172_101_seed.json`
- **Effort:** S
- **Acceptance:** customs broker asks "Can I co-load UN1203 and UN2031?" → "No, class 3 vs class 8 prohibited per 49 CFR 177.848"

### P0-11 · Border wait-time forecast
- **iOS:** `EusoTrip/Views/Driver/427_CrossBorderShipping.swift` (new wait-time card)
- **Web:** `eusoronetechnologiesinc/frontend/client/src/components/crossborder/BorderWaitCard.tsx`
- **Server:** new `wiring_stubs/server/borderWaitForecastService.ts` (calls Google Maps Traffic API)
- **Foundation:** `CrossBorderOverlay`, `Country` (from `FeeMultiplierEngine.swift`)
- **Effort:** S
- **Acceptance:** driver approaching Laredo sees "Heavy queue at WB Convent St; Colombia Solidarity ETA -45min"; alternate route accepted via voice → reroutes through HERE

### P0-12 · AI Ultra SaaS upsell tier
- **iOS:** `EusoTrip/Views/Wallet/PremiumTierView.swift` (new file), `EusoTrip/Services/EusoWalletManager.swift` (extend with tier field)
- **Web:** `eusoronetechnologiesinc/frontend/client/src/pages/Wallet.tsx` (Fee Insights card behind paywall)
- **Server:** `wiring_stubs/server/eusoWalletFeeMultiVehicle.ts` (expose `breakdown` object); new `eusoWalletPremium/geminiOptimizer.ts`
- **Foundation:** `FeeMultiplierEngine.FeeBreakdown` (7 multipliers) — premium tier renders Gemini-generated explanation per multiplier
- **Effort:** M
- **Acceptance:** shipper subscribes to Premium ($100/mo) → fee breakdown card explains "Your hazmat multiplier is 1.40 because UN1830 has class 8 corrosive + tank wash required"; Stripe Connect splits $100 → platform, Gemini API budget allocated per seat

### P0-13 · Universal Cart in EusoWallet
- **iOS:** `EusoTrip/Views/Wallet/CartView.swift` (new file), `EusoTrip/Services/CartRecommendationFeed.swift` (new file)
- **Web:** `eusoronetechnologiesinc/frontend/client/src/components/wallet/CartWidget.tsx`
- **Server:** new `wiring_stubs/server/cartRecommendationFeed.ts`, extends `stripeConnectMultiLeg.ts` with cart-line settlement
- **Foundation:** `FeeMultiplierEngine` (cart items include surcharges), `LoadStateFSM.crossBorder` (permit recommendations trigger on cross-border posts)
- **Effort:** S
- **Acceptance:** driver low on fuel → Cart suggests "$200 Pilot card, $45 IFTA permit renewal"; one-tap checkout → Stripe split → fleet manager sees roll-up

### P0-14 · "Built on Gemini" brand badge + co-marketing
- **iOS:** `EusoTrip/Views/Branding/GeminiAttributionBadge.swift` (new file — header pill), `EusoTrip/Resources/Assets.xcassets/GeminiBadge.imageset`
- **Web:** `eusoronetechnologiesinc/frontend/client/src/components/branding/GeminiAttributionBadge.tsx`, landing page hero update
- **Server:** every Gemini-backed API response includes `meta.aiPoweredBy: "Gemini Ultra"` (audit trail)
- **Foundation:** none
- **Effort:** S
- **Acceptance:** badge renders in iOS app header + web nav; appears in dev-docs landing; legal review of trademark use complete

### P0-15 · Antigravity CLI dev pipeline
- **iOS:** N/A (build pipeline ticket)
- **Web:** N/A (build pipeline ticket)
- **Server:** `eusoronetechnologiesinc/.github/workflows/*.yml` — replace shell scripts with `antigravity skill publish` invocations
- **Foundation:** none
- **Effort:** M
- **Acceptance:** all 12 core ESang skills publishable via `antigravity skill publish --channel=staging`; dual-deploy with old pipeline shows byte-identical output for 7 days; cut over

### P0-16 · XR Hazmat Pre-Haul checklist (audio-only tier first)
- **iOS:** `EusoTrip/Views/Driver/014_ApproachingPickup.swift` (add XR overlay handoff), `EusoTrip/Services/XRSessionBridge.swift` (new file — WatchConnectivity-style bridge to Android XR via cloud relay)
- **Web:** N/A (driver-only)
- **Server:** new `wiring_stubs/server/xrChecklistFeed.ts` (returns role-aware checklist items to XR glasses)
- **Foundation:** `Vertical.hazmat`, `TrailerCode.isHazmatEligible`, `HazmatOverlay.ergVerified` / `.placardsAffixed`
- **Effort:** M
- **Acceptance:** driver pairs Warby Parker audio-only XR → approaching hazmat pickup → checklist read aloud → driver says "placard verified" → `HazmatOverlay.placardsAffixed` set → audit chain entry written

### P0-17 · Astra POD photo with auto-detection
- **iOS:** `EusoTrip/Views/Driver/DeliveryPODCaptureView.swift` (extend with Astra), `EusoTrip/Services/AstraVisionService.swift` (POD analysis method)
- **Web:** `eusoronetechnologiesinc/frontend/client/src/components/receiver/PodCaptureCard.tsx` (mirror for warehouse worker)
- **Server:** new `wiring_stubs/server/astraPodEndpoint.ts` (POST `/api/astra/pod/analyze`)
- **Foundation:** `DocumentRequirements.proofOfDelivery`, `LoadStateFSM.podSigned`, `TrailerCode` (trailer-specific POD fields)
- **Effort:** M
- **Acceptance:** receiver photos pallet stack → Astra auto-detects seal #, damage, missing pieces; OS&D card pre-fills; pod_signed FSM transition gated by `attached docs >= required docs`

---

## 4. Round-trip wire contract — iOS Swift ↔ web TypeScript ↔ server

Same contract as the parity audit, extended for I/O 2026 fields:

| Field | iOS Swift | Web TypeScript | Server | Origin |
|-------|-----------|----------------|--------|--------|
| `vertical` | `Vertical.rawValue` | `Vertical` enum | validator | `_PARITY_AUDIT/02_Vertical.swift` |
| `trailer` | `TrailerCode.rawValue` | `TrailerCode` enum | validator | `_PARITY_AUDIT/03_TrailerCode.swift` |
| `mode` | `TransportMode.rawValue` | `TransportModeId` union | validator | `_PARITY_AUDIT/04_LoadStateFSM.swift` |
| `overlayStates` | `CompositeLoadState` | `CompositeLoadState` interface | persisted | `_PARITY_AUDIT/04_LoadStateFSM.swift` |
| `feeBreakdown` | `FeeBreakdown` | `FeeBreakdown` interface | persisted | `_PARITY_AUDIT/07_FeeMultiplierEngine.swift` |
| `aiPoweredBy` | `String` ("Gemini Ultra") | `string` | response meta | I/O 2026 — branding |
| `thinkingLevel` | `ESangThinkingLevel` enum | `"low" \| "medium" \| "high"` | per-request | I/O 2026 — Gemini 3 |
| `thoughtSignature` | `Data` (base64) | `string` | round-trip cache | I/O 2026 — Gemini 3 |
| `astraObservation` | `AstraObservation` struct | `AstraObservation` interface | persisted + hash-chained | I/O 2026 — Project Astra |
| `dialectVariant` | `VoiceDialectVariant` enum | `string` | TTS provider | I/O 2026 — voice models |

**All Astra observations MUST be cryptographically signed (Ed25519 via `EusoTrip.identityChain`) and committed to `dualLayerHashChain` before being treated as ground truth.** No silent AI decisions; every Astra output is auditable.

---

## 5. 6-week P0 sprint — 4-engineer parallel plan

Identical to `10_DEV_TEAM_PROMPT.md` but iOS-first verification at each step:

| Wk | Engineer 1 (Voice) | Engineer 2 (Astra + Agents) | Engineer 3 (Spark + Cart) | Engineer 4 (XR + Cloud) |
|----|--------------------|-----------------------------|---------------------------|-------------------------|
| 1 | Flash swap iOS → web | Astra DVIR scaffold iOS | Workspace OAuth iOS → web | Border wait API + iOS card |
| 2 | thinking_level iOS + web mirror | Astra hazmat placard + DVIR vision iOS | Daily Brief aggregation server | XR Hazmat skeleton iOS bridge |
| 3 | Thought Signatures iOS + dialect picker iOS + web | Astra hazmat wired iOS + ERG multi-turn server | Cart recommendation feed iOS + web | AI Ultra tier iOS + web paywall |
| 4 | Daily Brief deep link iOS | Shipment status agent iOS + web | Cart UI iOS + Spark hook | Antigravity CLI on CI |
| 5 | E2E voice stack test (iPhone + Pulse Watch) | Segregation agent iOS + Astra POD iOS | Daily Brief delivery (iOS push + web) | "Built on Gemini" badge iOS + web |
| 6 | Voice stack rollout + monitoring | Stabilization + bug bash | Stabilization | XR + Cloud stabilization |

**End of Wk 6:** all 17 P0 items behind feature flags, with iOS verified first, web verified within 24h of iOS sign-off.

---

## 6. Rollout strategy — iOS-first feature flags

iOS-native flag store: `EusoTrip/Services/FeatureFlagService.swift` (existing). Flags map 1:1 to the 17 P0 tickets.

| Flag | iOS default | Web default | 100% rollout date |
|------|-------------|-------------|-------------------|
| `gemini_3_5_flash_voice` | off | off → mirror iOS | Wk 7 |
| `thinking_level_routing` | off | off | Wk 7 |
| `thought_signature_cache` | off | off | Wk 8 |
| `dialect_voice` | off | off | Wk 8 |
| `daily_brief_widget` | off | off | Wk 9 |
| `astra_dvir` | off | N/A | Wk 9 |
| `astra_hazmat_placard` | off | N/A | Wk 10 |
| `erg_multi_turn` | off | off | Wk 8 |
| `shipment_status_agent` | off | off | Wk 9 |
| `compliance_segregation_agent` | off | off | Wk 9 |
| `border_wait_forecast` | off | off | Wk 7 |
| `ai_ultra_tier` | off | off | Wk 12 |
| `universal_cart` | off | off | Wk 10 |
| `gemini_badge` | on | on | Wk 6 |
| `antigravity_cli` | N/A | N/A | Wk 8 |
| `xr_hazmat_checklist` | off | N/A | Wk 12 (XR ships Fall 2026) |
| `astra_pod_auto_detect` | off | off | Wk 11 |

Web rollout always follows iOS by 24h–7d. If iOS regression detected, web flag flips off automatically via shared `FeatureFlagConfig` table.

---

## 7. Acceptance checklist — definition of done (per ticket)

Before any P0 ticket is closed, all of these must be true:

### Code
- [ ] iOS Swift file compiles + passes XCTest target
- [ ] Web TypeScript file compiles + passes type-check (if applicable)
- [ ] Server endpoint passes contract test (Pact / OpenAPI snapshot)
- [ ] Feature flag wired with default `off`
- [ ] Audit log entry written for any AI action (Spark, Astra, Managed Agent, voice intent)
- [ ] Cost telemetry: Gemini API call count + thinking_level distribution emitted to `metrics.geminiUsage`

### Foundation binding
- [ ] If touching equipment → references `TrailerCode` (not raw strings)
- [ ] If touching vertical → references `Vertical` (not raw strings)
- [ ] If touching FSM → references `LoadState` + applicable overlay (`HazmatOverlay`, `ReeferOverlay`, etc.)
- [ ] If touching fees → uses `FeeMultiplierEngine.compute(...)` and renders `FeeBreakdown` (not custom math)
- [ ] If touching documents → references `DocumentRequirements.forShipment(...)`
- [ ] If touching animations → references `AnimationBindingMap.files(for:)`

### Round-trip
- [ ] Same payload posted from iOS and web produces identical server state
- [ ] Server validator rejects unknown vertical / trailer / overlay values
- [ ] Persisted records survive a round-trip through `loads.create` → `loads.get`

### Astra-specific (P0-6, P0-7, P0-17)
- [ ] Every observation includes operator Ed25519 signature
- [ ] Confidence score attached + persisted
- [ ] Hash committed to `dualLayerHashChain` BEFORE FSM transition fires
- [ ] Operator override path tested + audit entry shows both signatures

### Voice-specific (P0-1 to P0-5)
- [ ] iOS Pulse Watch app behavior matches iPhone app behavior
- [ ] Latency p50 measured + logged to `metrics.voiceLatency`
- [ ] Dialect-aware response (Mexican Spanish, Quebec French, etc.) tested per locale

### XR-specific (P0-16)
- [ ] Works on audio-only XR tier (camera + mic + speaker; no display)
- [ ] Falls back to iPhone voice + watch when XR not paired
- [ ] Voice action confirmation path tested (e.g., "placard verified" → no false positive)

---

## 8. PR contract

Same as parity audit:

- **Title:** `P0-{N}: {short description}` (e.g., `P0-1: Gemini 3.5 Flash swap`)
- **Body must include:**
  - Ticket ID from `01_OPPORTUNITY_MATRIX.md`
  - File paths touched
  - Foundation files referenced (proves type-safety)
  - Screenshots: iOS before/after, web before/after, Pulse Watch (if voice)
  - Round-trip test: paste request + response showing iOS and web produce identical server state
  - Feature flag config (name, default, planned rollout date)
  - Cost telemetry baseline (Gemini API calls / day before vs. projected after)

**Reviewers:**
- Foundation-touching tickets (P0-3, P0-8, P0-12) → founder review required
- Astra tickets (P0-6, P0-7, P0-17) → security + compliance SME review
- Voice tickets (P0-1 to P0-5) → at least one iOS engineer + one accessibility reviewer
- XR ticket (P0-16) → product partnership lead (Warby Parker / Gentle Monster integration)

---

## 9. Rollout gates

| Gate | Criterion |
|------|-----------|
| **Wk 4 review** | All P0 scaffolding compiles iOS + web; integration tests green; feature flags wired |
| **Wk 6 ship** | All 17 P0 items behind feature flags; iOS internal TestFlight green; web staging green |
| **Wk 8 rollout** | Cost telemetry baseline established; voice latency improvement confirmed (p50 < 200ms iOS, < 250ms web); Astra FP rate < 5% |
| **Wk 12 P1 kickoff** | P0 stabilized at 100% rollout; begin P1 work — Managed Agents Phase 1 (Sensory layer), Broker Spark, XR Dock POD |

---

## 10. P1 + P2 preview (after P0 ships)

Once the foundation is laid by P0, the remaining 35 opportunities unlock fast. Order of work:

**Q4 2026 (Wk 12-24):**
- P1-A: Managed Agents Phase 1 (8 Sensory agents) + Phase 2 (12 Dispatch agents) — see `06_WAVE_E_ANTIGRAVITY.md`
- P1-B: Broker Spark + Dispatcher Spark + Catalyst Spark + Customs Broker Spark — see `05_WAVE_D_WORKSPACE_SPARK.md`
- P1-C: XR Dock Worker POD + XR Reefer Temp HUD + XR USMCA Filing Assistant — see `03_WAVE_B_ANDROID_XR.md`
- P1-D: TPU 8i for inference (sync-window ML) — see `09_WAVE_H_CLOUD_COST.md`
- P1-E: Lane intelligence agent + Carrier vetting agent + Heavy-haul Earth contours — see `07_WAVE_F_INFO_AGENTS.md`, `08_WAVE_G_MAPS_EARTH.md`

**Q1 2027 (Wk 25-36):**
- P2-A: USMCA cert generator agent — see `07_WAVE_F_INFO_AGENTS.md`
- P2-B: Native Android app generation (Antigravity) for MX/CA/LATAM — see `06_WAVE_E_ANTIGRAVITY.md`
- P2-C: Enterprise AI Services co-sell with Google Cloud — see `09_WAVE_H_CLOUD_COST.md`
- P2-D: Astra livestock 28-hr law thermal detection — see `04_WAVE_C_PROJECT_ASTRA.md`
- P2-E: Earth bathymetry + Rail Yard 3D + Dock door geocoding — see `08_WAVE_G_MAPS_EARTH.md`

---

## 11. Communication

- **Daily standup:** 09:00 ET. Each engineer reports ticket status + iOS / web parity state.
- **Wk 2, 4, 6 demo:** show working iOS feature first, then web mirror; show round-trip payload screenshot.
- **Slack channels:** `#io2026-p0-voice`, `#io2026-p0-astra`, `#io2026-p0-spark`, `#io2026-p0-xr`. Each engineer owns one.
- **Escalation:**
  - Gemini API rate limits → founder + Google Cloud TAM
  - Astra FP rate > 5% in any vertical → engineering + compliance SME
  - XR hardware delays → product + partnership lead
  - Foundation enum mismatch (iOS vs. web vs. server) → STOP, fix the foundation file, re-run PR

---

## 12. Risks + mitigations

| Risk | Mitigation | Escalate when |
|------|------------|---------------|
| Gemini API rate limits | Backoff + quota monitoring per endpoint | Sustained >80% quota usage |
| Workspace OAuth scope rejection | Minimize scopes; transparent consent | <40% opt-in rate |
| Astra FP rate on critical paths (hazmat placard) | Dual-signature audit; operator override; manual review queue | FP rate > 5% in any vertical |
| TPU 8i unavailable in target region | Stay on CPU/ONNX as fallback | TPU 8i unavailable > 7 days |
| XR hardware delays beyond Fall 2026 | Audio-only tier ships first; in-lens display variant later | Ship date slips > 30 days |
| iOS App Store rejection on AI-powered features | Pre-submission with App Store guidelines team; clear AI disclosure in app description | Any reviewer feedback |
| Web/iOS state drift after parallel feature flag rollout | Shared `FeatureFlagConfig` table; iOS leads; web mirrors within 24h | Detected via E2E test failures |

---

## 13. TL;DR

> Founder shipped the canonical Vertical / TrailerCode / LoadStateFSM foundation on 2026-05-20 (yesterday). Google I/O 2026 keynote dropped the same day. The intersection is a 6–9 month first-mover window. 17 P0 tickets in this brief land iOS-first (Swift), web mirrors within 24h, server endpoints shared. Every ticket binds to a canonical foundation enum — drift becomes a compile error. 4 engineers, 6 weeks, all 17 P0 behind feature flags. Then P1 (Q4) and P2 (Q1 2027) unlock the remaining 35 opportunities.
>
> **Total addressable lift: $1M+ revenue + $300K+ cost savings in year 1.** Plus Google partnership posture + "Built on Gemini" co-marketing + Astra observational compliance no competitor has.
>
> Read `00_EXECUTIVE_SUMMARY.md` + `01_OPPORTUNITY_MATRIX.md` + this file before writing a line of code. Ship P0-1 (Gemini 3.5 Flash swap, iOS Swift first) by end of Wk 1. Everything else cascades from there.
