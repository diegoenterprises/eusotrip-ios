# Wave B — Android XR Intelligent Eyewear
**Agent #2 deliverable** | 6 killer use cases

## Hardware reality (announced May 19, 2026)
- **Frames:** Warby Parker + Gentle Monster
- **Silicon:** Samsung + Qualcomm
- **Two tiers:** audio-only (camera + mic + speaker) AND in-lens display
- **AI stack:** Gemini + Project Astra
- **Ship date:** Fall 2026 (consumer)
- **DOT-compliant:** ANSI Z87.1 impact-resistant lens option

## Use case #1 — Hazmat Pre-Haul Checklist (P0)
- **Tier:** In-lens display
- **What it shows:** 6-item pre-gate checklist overlaid on facility view (placard verification photo + ERG card summary + equipment pressure baseline + commodity match + tunnel restrictions per 49 CFR 397 + dispatch signature 15-min notify)
- **Voice contract:** "Is the placard visible?" → Gemini + Astra OCR reads placard → confirms UN match → "Placard verified. ERG card next."
- **Files:** `Views/Driver/014_ApproachingPickup.swift`, `_REGULATORY_RULE_PACKS_2026-05-10.md`, `EsangVoiceWatch.swift`
- **Branding:** Warby Parker "Hazmat Edition" (ANSI Z87.1 + Eusorone red accent). Gentle Monster premium variant.
- **Effort:** M (8 wk)
- **Regulatory:** 49 CFR 172.504 (placard audit chain), DVSA/FMCSA 391.63 (vision req), 49 USC §5103 (security plan)

## Use case #2 — Dock Worker Voice POD (P1)
- **Tier:** Audio-only → upgrade to in-lens
- **What it shows:** Shipment card on dock arrival, OS&D picker, "Start unload" action highlighted on voice trigger
- **Voice:** "Trailer 4892 docked, door six, load LD-260427, 48 pallets, clean" → Gemini parses → state transitions
- **Files:** `ios/ReceiverDockSurface.swift`, `DeliveryPODCaptureView.swift`, `EsangVoiceWatch.swift`
- **Branding:** Gentle Monster "Dock Pro" rugged (anti-fog, gloved-hand temple buttons). Carrier/3PL logos embossed.
- **Effort:** M (6 wk). ReceiverVoiceController already exists; extend to in-lens binding.
- **Regulatory:** OSHA 1910.95 (hearing protection dual-feed), POD timestamp = regulatory-grade

## Use case #3 — Cross-Border USMCA Filing Assistant (P1)
- **Tier:** In-lens display
- **What it shows:** Cargo declaration form, required docs checklist (RFC, Agente Aduanal, Carta Porte CFDI 4.0), live filing status grid (ACE ✓ / SAT ✓ / CBSA pending), port-of-entry queue time
- **Voice:** "Is my Carta Porte ready?" → Astra checks SAT filing → "Carta Porte CFDI 123456 certified. Ready to cross."
- **Files:** `Views/Shipper/427_CrossBorderShipping.swift`, `EsangVoiceWatch.swift`
- **Branding:** Warby Parker "BorderPro" (CA/US/MX SKUs, Spanish/English language toggle, white-label firmware option)
- **Effort:** M (10 wk). Cross-border filing state exists; wire in-lens display + real-time SAT/CBP/CBSA status API.
- **Regulatory:** 19 CFR §4.7 (CBP 24-hr manifest), RMF 2.7.1.9 (SAT Carta Porte validation)

## Use case #4 — Reefer Temp Monitoring HUD (P1)
- **Tier:** In-lens display (audio-only fallback)
- **What it shows:** Live reefer unit telemetry (target 34°F / actual 33.8°F ✓), 24-hr temp sparkline, unit health (fuel %, compressor RPM, alarm), FSMA compliance badge
- **Voice:** "Check my reefer" → "Setpoint 34, actual 34.2, fuel 67%. Good for 380 miles at current burn rate."
- **Alert:** Temp excursion → red border + voice alarm
- **Files:** `DeliveryPODCaptureView.swift` lines 137-161 + reefer telemetry binding, `EsangVoiceWatch.swift`
- **Branding:** Gentle Monster premium with integrated IoT antenna (Qualcomm → vehicle CAN bus). Co-branded with reefer OEM (Carrier, Thermo King).
- **Effort:** S. Telemetry binding exists.
- **Regulatory:** FSMA 21 CFR 1.908 (immutable temp logs), insurance: "certified monitoring device" rate discount

## Use case #5 — Hazmat Incident Emergency Response (P2)
- **Tier:** In-lens display with emergency variant + video stream
- **What it shows:** RED HAZMAT INCIDENT banner, CHEMTREC auto-dial button (tap temple), live front-camera streaming to dispatcher, overlaid ERG 125 card + 49 CFR 171.15 procedures
- **Voice:** "What do I do?" → "Step 1: Move upwind. Step 2: CHEMTREC dialing now."
- **Files:** `PER_ROLE_SURFACE_MAP.md` D-11 hazmat incident + DP-06 hazmat command center, `EsangVoiceWatch.swift`
- **Branding:** Warby Parker "Safety Edition" (impact-resistant, high-contrast OLED, Eusorone red, co-branded with CHEMTREC + DOT ERG)
- **Effort:** L. Video streaming + real-time ERG overlay + CHEMTREC SIP bridging.
- **Regulatory:** 49 CFR 171.15 (in-lens ERG card satisfies documentation), 49 USC §5103 (audit-grade incident report)

## Use case #6 — Multi-Modal Intermodal Task Queue (P2)
- **Tier:** In-lens display
- **What it shows:** 4-task pipeline (drop tractor at BNSF ramp → wait for rail car gate-in 14:23 → pick up loaded container from rail spur B4 → return to origin shipper by 18:00). Geofence triggers task highlight.
- **Voice:** "What's next?" → "Next: drop tractor. Rail ramp 3.2 miles ahead. Gate opens 14:15."
- **Files:** `Views/Driver/016_PickupLoading.swift`, `MULTI_VEHICLE_LOAD_ARCHITECTURE.md`, `EsangVoiceWatch.swift`
- **Branding:** Gentle Monster "Intermodal Edition" (multi-color OLED: red=truck, blue=rail, green=vessel). Warby Parker "Dispatch Pro" wider FOV for catalysts.
- **Effort:** M. Task queue model exists.
- **Regulatory:** 49 CFR §177 (rail hazmat segregation auto-flag), ELD integration = hands-free HOS logging

---

## Top 3 killer use cases (ranked by impact + market size)

### #1 Hazmat Pre-Haul Checklist
40,000+ hazmat shipments/day in US. ERG card + placard OCR eliminates pre-gate holds (15–30 min/load saved). Revenue: carrier safety premiums + shipper compliance audit SLAs. Timeline: 8 wk.

### #2 Dock Worker Voice POD
Dock labor shortage (15–25% unfilled). Audio-only frames reduce onboarding friction + accessibility. Hands-free POD capture (photo + signature auto-triggered) = gloved-hand-friendly. Revenue: 3PL partnerships + warehouse automation tier. Timeline: 6 wk.

### #3 Cross-Border USMCA Filing
$2.2T US-Mexico trade; USMCA saves $500–$2000/shipment. 60% of drivers still unclear on requirements. Real-time SAT/CBP/CBSA filing status + voice Q&A (Spanish/English) = 20–40 min border dwell savings. Revenue: premium carrier SLAs + tariff optimization affiliate. Timeline: 10 wk.

---

## Technical integration notes
- **Voice intent engine:** All 6 use cases ride on `EsangVoiceWatch.swift` + `EsangVoiceBridge.swift` patterns. Gemini + Astra add OCR (placard, document) + multi-step task reasoning.
- **In-lens data binding:** Live load state → `/api/esang/voice` returns `EsangVoiceActionReply.visual` (card template). Template renderer in frame (Samsung Qualcomm SoC handles SVG → OLED bitmap). Timezone/locale via `EusoTripSession` context.
- **Regulatory audit chain:** Frame camera timestamp + voice transcript + location = immutable POD. Blockchain audit trail (already in platform) extended to XR events. FMCSA/DOT compliance: each session = signed audit event.
- **Co-branding:** Frame templates (anti-glare, ANSI Z87.1, temple-tap button custom Android XR firmware). Co-branded unboxing kits. Carrier subscription bundles ($200/frame; 3-pack fleet starter $500).
