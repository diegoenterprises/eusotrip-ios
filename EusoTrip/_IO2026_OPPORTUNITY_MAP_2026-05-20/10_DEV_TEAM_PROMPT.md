# Google I/O 2026 Integration — Dev Team Hand-off

## Read these three first
1. `00_EXECUTIVE_SUMMARY.md` — top-line, 52 opportunities, prioritization
2. `01_OPPORTUNITY_MATRIX.md` — sortable table of all 52
3. The 8 per-wave files (`02–09`) — detailed agent findings

## P0 sprint (Q3 2026) — ship in 6 weeks with 4 engineers

These 17 items are the highest-leverage / lowest-effort opportunities. Land them first; they unlock everything else.

### Engineer 1 — Voice + Locale (Sprint 1-2)
| Ticket | Files | Effort |
|--------|-------|:------:|
| Swap to Gemini 3.5 Flash | `wiring_stubs/server/esangVoiceServer.ts` lines 88-94, `voiceLocaleAdapter.ts` lines 42-46, iOS `EsangVoiceWatch.swift` line 329 | M |
| Add thinking_level parameter | `esangVoiceServer.ts`, new `esangThinkingConfig.ts` | M |
| Add Thought Signatures | `esangVoiceServer.ts` followUp flow + new `esangThoughtSignatureCache.ts` | S |
| Regional dialect voice | `EsangVoiceWatch.swift`, `voiceLocaleAdapter.ts` LocalePatternBundle.dialectVariant | S |
| Daily Brief deep link | New `esangGeminiBriefAdapter.ts` + `esangUniversalCartView.ts` | M |

### Engineer 2 — Astra + Information Agents (Sprint 1-3)
| Ticket | Files | Effort |
|--------|-------|:------:|
| Astra Pre-Trip DVIR | `Views/Driver/DVIRCaptureController.swift`, `Services/VehicleInspectionService.swift`, `PhotoCaptureService.swift` | M |
| Astra Hazmat Placard + ERG | `Services/HazmatMetadataService.swift`, `Views/Driver/HazmatPlaycardScanController.swift`, `EmergencyResponseGuideClient.ts` | M |
| Hazmat ERG multi-turn agent | `ergSearchRouter.ts` + new `getFollowUpContext()` procedure | M |
| Shipment status agent | `shipments.ts` + new `getShipmentAgent()` endpoint, `TrackShipments.tsx` | M |
| Compliance segregation agent | Extend `ergSearchRouter.ts` segregationCheck with follow-ups, new `compliance.ts` router | S |

### Engineer 3 — Spark + Universal Cart (Sprint 1-3)
| Ticket | Files | Effort |
|--------|-------|:------:|
| Workspace adapter base | New `googleWorkspaceAdapter.ts` + `googleGmailAdapter.ts` + `googleSheetsAdapter.ts` + `googleDocsAdapter.ts` | M |
| Shipper Daily Brief engine | New `sparkDailyBriefEngine.ts` + `sparkBriefs.ts` GET endpoint + `sparkBriefScheduler.ts` | S |
| Universal Cart in EusoWallet | `Wallet.tsx` cart widget + new `cartRecommendationFeed.ts` | S |

### Engineer 4 — XR + Cloud + Branding (Sprint 1-3)
| Ticket | Files | Effort |
|--------|-------|:------:|
| Border wait-time forecast | New `borderWaitForecastService.ts` (Maps Traffic API) | S |
| XR Hazmat Pre-Haul (audio-only first) | `Views/Driver/014_ApproachingPickup.swift` + XR overlay layer | M |
| AI Ultra SaaS tier in EusoWallet | `eusoWalletFeeMultiVehicle.ts` (expose breakdown) + new `eusoWalletPremium/geminiOptimizer.ts` + Wallet.tsx Fee Insights card | M |
| "Built on Gemini" badge | New `/branding/geminiAttribution.tsx` + landing page + API response field | S |
| Antigravity CLI dev pipeline | Wrap 12 core skills in CLI skeleton; dual-deploy old + new | M |

## Sprint plan

| Wk | Engineer 1 | Engineer 2 | Engineer 3 | Engineer 4 |
|----|------------|------------|------------|------------|
| 1 | Flash swap | DVIR scaffold | Workspace OAuth | Border wait API |
| 2 | thinking_level | DVIR vision + hazmat placard scaffold | Daily Brief aggregation | XR Hazmat skeleton |
| 3 | Thought Signatures + dialects | Astra hazmat placard wired | Cart recommendation feed | AI Ultra tier |
| 4 | Daily Brief deep link | ERG multi-turn agent | Cart UI + Spark hook | Antigravity CLI setup |
| 5 | E2E test + ship voice stack | Shipment status agent | Daily Brief delivery | "Built on Gemini" badge |
| 6 | Stabilization + bug bash | Segregation agent + stabilization | Stabilization | Stabilization |

End of Wk 6: all 17 P0 items in production behind feature flags. Wk 7: gradual rollout. Wk 8: 100%.

## Wire contract — what every PR must show

1. **Ticket ID from `01_OPPORTUNITY_MATRIX.md`** in PR title
2. **Files touched** match the wave doc's file list
3. **Round-trip test** — sample request via iOS or web → server → response, screenshotted
4. **Feature flag config** — flag name + default state + planned rollout
5. **Audit log entry** for any agentic action (every Spark / Astra / Managed Agent call must log to `sparkAuditLog` or `astraObservationLog`)
6. **Cost telemetry** — Gemini API call count + thinking_level distribution per endpoint

## Rollout gates

| Gate | Criterion |
|------|-----------|
| **Wk 4 review** | All P0 scaffolding in place; integration tests green |
| **Wk 6 ship** | All 17 P0 items behind feature flags |
| **Wk 8 rollout** | Cost telemetry baseline established; latency improvement confirmed |
| **Wk 12 P1 kickoff** | P0 stabilized; begin Managed Agents Phase 1 (Sensory layer) + Broker Spark + XR Dock POD |

## Risks + escalation

| Risk | Mitigation | Escalate when |
|------|------------|---------------|
| Gemini API rate limits | Backoff + quota monitoring | Quota usage >80% sustained |
| Workspace OAuth scope rejection by users | Minimize scopes; transparent consent | <40% opt-in rate |
| Astra observation false positives | Dual-signature audit; operator override path | FP rate >5% in any vertical |
| TPU availability in target region | Stay on CPU as fallback | TPU 8i unavailable >7 days |
| XR hardware delays beyond Fall 2026 | Audio-only tier ships first; in-lens display later | Ship date slips >30 days |

## TL;DR

> Q3 2026 ship: voice 4× faster, Astra observational compliance, Daily Brief, Universal Cart, AI Ultra upsell tier, "Built on Gemini" co-marketing badge. Q4 2026: Spark x 5 roles + 52-agent Cortex Phase 1-2 + XR fall launch. Q1 2027: USMCA cert agent + native Android variant + Enterprise AI Services co-sell.
>
> Total addressable lift: **$1M+ annual revenue + $300K+ cost savings in year 1.** 6-9 month first-mover window before competitors catch up.
