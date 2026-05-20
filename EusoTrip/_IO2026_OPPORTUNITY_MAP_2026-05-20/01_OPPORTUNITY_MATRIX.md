# 52-Opportunity Matrix — sortable, filterable
**Date:** 2026-05-20
**Legend:** Effort = S (1-2d) / M (3-5d / weeks) / L (>1w / months). P0 = ship Q3 2026. P1 = ship Q4. P2 = ship Q1 2027.

| # | Wave | Opportunity | Role(s) served | Effort | Priority | Files (canonical) |
|---|------|-------------|----------------|:------:|:--------:|-------------------|
| 1 | A | **Gemini 3.5 Flash swap** in ESang voice dispatcher | All 12 | M | **P0** | `wiring_stubs/server/esangVoiceServer.ts`, `voiceActionDispatcher.ts` |
| 2 | A | **thinking_level parameter** (intent-aware cost/latency tuning) | All | M | **P0** | `esangVoiceServer.ts`, new `esangThinkingConfig.ts` |
| 3 | A | **Thought Signatures** for multi-turn voice context preservation | Driver, dispatcher | S | **P0** | `esangVoiceServer.ts` followUp flow + new cache |
| 4 | A | **Managed Agents document generator** (POD, CF3461, hazmat PDFs in <60s) | Shipper, broker, compliance | L | P1 | New `esangAgentDocumentGenerator.ts` |
| 5 | A | **Regional dialect voice models** (Mexican Spanish, Quebec French, Appalachian English) | Driver | S | **P0** | `EsangVoiceWatch.swift`, `voiceLocaleAdapter.ts` |
| 6 | A | **Gemini Omni explainer videos** (auto-generated trip explanations) | Shipper, broker | L | P2 | New endpoint + Gemini Omni client |
| 7 | A | **Gemini Intelligence async customs filing** (voice → background filing) | Shipper, broker, compliance | L | P1 | New `esangIntelligenceOrchestrator.ts` + task queue |
| 8 | A | **Daily Brief integration** + Universal Cart deep link | Shipper, broker | M | **P0** | New `esangGeminiBriefAdapter.ts` |
| 9 | B | **XR Hazmat Pre-Haul Checklist** (in-lens, placard OCR, ERG card) | Driver (hazmat-certified) | M | **P0** | `Views/Driver/014_ApproachingPickup.swift` + XR overlay layer |
| 10 | B | **XR Dock Worker POD Capture** (audio + in-lens, gloved-hand-friendly) | Receiver | M | P1 | `ReceiverDockSurface.swift` + XR extension |
| 11 | B | **XR Cross-Border USMCA Filing Assistant** (live SAT/CBP/CBSA status) | Driver, dispatcher | M | P1 | `427_CrossBorderShipping.swift` + XR overlay |
| 12 | B | **XR Reefer Temp Monitoring HUD** (live telemetry overlay) | Driver | S | P1 | POD capture view + reefer telemetry binding |
| 13 | B | **XR Hazmat Incident Emergency Response** (CHEMTREC + ERG live, video stream) | Driver, dispatcher | L | P2 | New emergency-mode XR variant |
| 14 | B | **XR Intermodal Multi-Leg Task Queue** (4-task pipeline visible in-lens) | Driver | M | P2 | `016_PickupLoading.swift` + task queue model |
| 15 | C | **Astra Pre-Trip DVIR** (tire wear, brake pad detection, auto-form fill) | Driver | M | **P0** | `PretripDVIRViewModel.swift` + vision pipeline |
| 16 | C | **Astra Hazmat Placard + ERG hands-free lookup** | Driver, hazmat-certifier | M | **P0** | `ergSearchRouter.ts` + driver Hazmat surface |
| 17 | C | **Astra POD Photo with auto-seal/placard/damage detection** | Receiver, driver | M | P1 | `DeliveryPODCaptureView.swift` + OCR service |
| 18 | C | **Astra Reefer Temp-Log Reading** (OCR reefer unit display) | Driver | S | P1 | Reefer telemetry service + OCR |
| 19 | C | **Astra OS&D Detection from cargo visual diff** | Receiver | M | P1 | `ReceiverDockSurface.swift` + manifest diff |
| 20 | C | **Astra Livestock 28-hr Law Arming** (thermal animal detection + countdown) | Driver, catalyst | L | P2 | `LivestockComplianceRouter.swift` + thermal vision |
| 21 | D | **Shipper Spark** (overnight rate confirmation drafting + ERP reconciliation) | Shipper | M | P1 | New `sparkAutoMonitor.ts` + workspace adapter |
| 22 | D | **Broker Spark** (overnight rate-sheet updates + tender triage + lane intel) | Broker | L | P1 | New `sparkRateEngine.ts` + `tenderTriagulator.ts` |
| 23 | D | **Dispatcher Spark** (HoS-aware schedule planning + driver scoring) | Dispatcher | M | P1 | New `sparkScheduler.ts` + ELD integration |
| 24 | D | **Catalyst Spark** (settlement reconciliation + factoring decisions + scorecards) | Catalyst, fleet manager | M | P1 | New `sparkReconciler.ts` + factoring scorer |
| 25 | D | **Customs Broker Spark** (filing monitoring + hold response + USMCA cert gen) | Customs broker | M | P1 | New `sparkFilingMonitor.ts` + `CustomsBrokerSurface.tsx` |
| 26 | D | **Shipper Daily Brief** (06:00 local: loads, exceptions, AR, fuel rates) | All shippers | S | **P0** | New `sparkDailyBriefEngine.ts` + Workspace integration |
| 27 | D | **Universal Cart in EusoWallet** (fuel / permits / tolls / insurance one-flow) | All roles | S | **P0** | `CartWidget.tsx` + new Spark recommendation feeds |
| 28 | E | **Migrate 52 Zenith Cortex agents → Managed Agents API** (4 phases) | All | L | P1 | New `/agents/layer1_sensory/` through `/layer6_guardian/` |
| 29 | E | **Antigravity CLI** as dev pipeline for plugin/skill generation | Engineering | M | **P0** | Replace `/skills/*/SKILL.md` workflow |
| 30 | E | **Subagent orchestration** for 7-layer Cortex (parent + parallel children) | All | M | P1 | Refactor existing agent prompts |
| 31 | E | **Antigravity cron workflows** for nightly retrain + daily rate card + weekly compliance audit | Engineering | S | P1 | Replace Lambda + CloudWatch with native cron |
| 32 | E | **Native Android app generation** (Antigravity prompt → MX/CA/LATAM variant in 6 wk) | Driver (LATAM markets) | M | P2 | New Android Studio project; Carta Porte + TDG variants |
| 33 | E | **Hardened Git policies** (Antigravity CLI credential masking + signed commits) | Engineering | M | P1 | Both monorepos: credential vault + signed-commit enforcement |
| 34 | F | **Information agent for hazmat ERG + segregation** (multi-turn) | Shipper, hazmat certifier, driver | M | **P0** | `ergSearchRouter.ts` + multi-turn context store |
| 35 | F | **Information agent for shipment status** (multi-turn "where is X?", "are we on time?") | Shipper, broker, dispatch | M | **P0** | Replace search-by-load page with agent panel |
| 36 | F | **Information agent for compliance segregation** (49 CFR rules, marine pollutants) | Shipper, customs broker | S | **P0** | Extend `ergSearchRouter.ts` segregation check |
| 37 | F | **Information agent for lane intelligence + pricing** (multi-turn rate + surcharge) | Shipper, dispatch | M | P1 | New `pricebook.ts` agent endpoint |
| 38 | F | **Information agent for carrier vetting** (FMCSA + EusoTrip scorecard + CSA) | Shipper, procurement | M | P1 | New `fmcsa.ts` agent endpoint |
| 39 | F | **Information agent for USMCA cert generation** (HS code wizard + origin determination) | Shipper, customs broker | L | P2 | Replace `FileEntryForm` static form |
| 40 | F | **Information agent for equipment selection** (commodity → trailer + docs + fleet availability) | Shipper, dispatch | M | P1 | Replace equipment picker dropdown |
| 41 | G | **Earth 1m contours for heavy-haul OS/OW route survey** | Driver (heavy haul), dispatcher | M | P1 | `LocationTrackingMap.tsx` + new contour overlay |
| 42 | G | **Earth bathymetry for vessel berth + draught assignment** | Catalyst, terminal manager | L | P2 | New `VesselBerthOptimizer.tsx` |
| 43 | G | **Earth 3D + Gemini for rail yard convoy staging** | Terminal manager, dispatcher | L | P2 | New `RailYardConvoyPlanner.tsx` |
| 44 | G | **Maps traffic API for cross-border crossing wait-time forecast** | Driver, dispatch | S | **P0** | New `borderWaitForecastService.ts` |
| 45 | G | **Earth flyover for driver pre-trip route preview** | Driver | M | P1 | New `RouteFlyoverPreview.tsx` |
| 46 | G | **Earth + Gemini vision for dock door geocoding** | Shipper, driver | M | P1 | New `geminiDockGeocoder.ts` |
| 47 | H | **TPU 8i for sync-window ML inference** (87% compute cost cut) | Engineering | M | P1 | `syncWindowInference.ts` execution provider swap |
| 48 | H | **TPU 8t for nightly retrain** (69% cycle-time cut) | Engineering | L | P2 | `train_sync_window.py` distributed training |
| 49 | H | **AI Ultra ($100/mo) SaaS upsell tier in EusoWallet** | All shippers, brokers | M | **P0** | `eusoWalletFeeMultiVehicle.ts` + new premium tier |
| 50 | H | **Enterprise AI Services co-sell with Google Cloud** (custom-tuned Gemini for shippers 500+/mo) | Enterprise shippers | L | P2 | Vertex AI pipeline + sales/delivery org |
| 51 | H | **"Built on Gemini" brand badge + co-marketing** | All | S | **P0** | UI badge + landing-page update + press release |
| 52 | H | **Universal Cart × EusoWallet checkout integration** (covered in #27, listed here for cost tracking) | All | M | **P0** | (Same as #27) |

---

## P0 sprint (Q3 2026) — 10 items to ship

| # | Opportunity | Effort |
|---|-------------|:------:|
| 1 | Gemini 3.5 Flash swap | M |
| 2 | thinking_level parameter | M |
| 3 | Thought Signatures | S |
| 5 | Regional dialect voice | S |
| 8 | Daily Brief integration | M |
| 9 | XR Hazmat Pre-Haul (audio-only tier first) | M |
| 15 | Astra Pre-Trip DVIR | M |
| 16 | Astra Hazmat Placard + ERG | M |
| 26 | Shipper Daily Brief | S |
| 27 | Universal Cart in EusoWallet | S |
| 29 | Antigravity CLI dev pipeline | M |
| 34 | Hazmat ERG agent (multi-turn) | M |
| 35 | Shipment status agent | M |
| 36 | Compliance segregation agent | S |
| 44 | Border wait-time forecast | S |
| 49 | AI Ultra SaaS tier | M |
| 51 | "Built on Gemini" badge | S |

That's 17 P0 items, ~24 engineer-weeks combined. With 4 engineers parallel, ships in 6 weeks.
