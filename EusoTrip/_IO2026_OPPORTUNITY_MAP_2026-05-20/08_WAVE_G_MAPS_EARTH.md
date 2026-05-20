# Wave G — Maps + Earth × Routing
**Agent #7 deliverable** | 6 opportunities + HERE vendor strategy

**Premise:** Augment, don't replace. HERE Maps stays as the canonical routing layer; Google Earth + Maps + Gemini fill specific gaps HERE can't.

## Opportunity A — Heavy-Haul OS/OW Route Survey (P1)
- **Use case:** Real-time route validation for OS/OW loads using 1-meter contour intervals. Construction crews + escort coordinators preview bridge clearances, grade percentages, and overhead obstacles before departure.
- **Data:** Google Earth API (elevation) + Maps Elevation Service + HERE route polyline + USGS bathymetry for water crossings
- **Files:** `LocationTrackingMap.tsx` (add Earth elevation alongside HERE basemap), `RoleBasedMap.tsx` (add escort role conditional UI for contour visualization), backend route-planning service — call `elevation.getElevationAlongPath()` every 0.1 mi, new component `OverweightRouteSurveyOverlay.tsx`
- **HERE/Google trade-off:** Keep HERE as routing/turn-by-turn default; overlay Google Earth elevation as secondary layer. HERE lacks 1m contour granularity; Earth fills the gap.
- **Effort:** M (2-3 wk including mobile parity)
- **ROI:** OS/OW incident reduction 15-20%

## Opportunity B — Vessel Berth + Port Draught Assignment (P2)
- **Use case:** Automate dock assignment for container vessels by cross-referencing ship LOA/beam/draught against Earth bathymetry data. Prevents costly groundings.
- **Data:** Google Earth Pro bathymetry tiles (1m resolution near coast) + IHO S-57 ENC charts + vessel registry APIs + HERE port terminal polygons
- **Files:** New `bathymetryService.ts` (query Earth bathymetry + ENC), new `VesselBerthSelector.tsx`, backend intermodal schema → add `recommended_berth` field
- **HERE/Google trade-off:** Separate concern. HERE doesn't expose bathymetry; Earth is purpose-built. Zero overlap.
- **Effort:** L (4-6 wk) — Requires ENC chart licensing, bathymetric tile ingestion pipeline, vessel draught DB integration
- **ROI:** SOLAS Annex I compliance + grounding avoidance

## Opportunity C — Rail Yard 3D + Gemini Convoy Staging (P2)
- **Use case:** Visual planning for drayage yard operations. Rail yard managers stage trailers in convoy sequence using Earth 3D building/terrain overlay (exact yard layout, overhead cables, clearances). Gemini reasons about optimal blocking sequence given equipment constraints.
- **Data:** Earth 3D models + Maps satellite imagery (high resolution) + Gemini API for yard analysis ("Is this sequence safe given 53' trailers + 14' dock doors?")
- **Files:** New `RailYardVisualizationCanvas.tsx` (embeds Earth WebGL), new `geminiYardPlanningService.ts` (LLM-based sequence validation), backend rail_shipment schema → add `staging_plan` JSON field
- **HERE/Google trade-off:** 3D Earth transformative here; HERE is 2D vector-focused. Gemini reasoning Google-exclusive. **Highest-leverage opportunity** for replacing manual yard management.
- **Effort:** L (5-6 wk) — Earth WebGL SDK, Gemini API setup, rail yard polygon library (every major NA yard), mobile rendering
- **ROI:** 20-30% faster yard turnover

## Opportunity D — Cross-Border Crossing Wait-Time Forecast (P0)
- **Use case:** Drivers get real-time border queue predictions. Fuse Maps Traffic API (historical wait patterns) + Earth geofencing (detect driver approaching crossing) to forecast 15-min and 1-hr delays. Route to less-congested POE if beneficial.
- **Data:** Maps Directions API w/ traffic_model=best_guess + custom wait-time scraping from CBP/BGTOC APIs + HERE route recalculation for alternates
- **Files:** New `borderWaitForecastService.ts` (call Maps traffic at 5-min intervals), backend load schema → add `crossing_preference` enum (primary/alternative/fastest), `Shipment.tsx` + `InTransit.tsx` → new AlertCard "Heavy queue at El Paso; Laredo ETA -45min"
- **HERE/Google trade-off:** Maps has superior traffic layer (real-time congestion). HERE has better routing. Use HERE for base route; call Maps traffic for crossing-specific ETAs. Clear boundary.
- **Effort:** S (1-2 wk)
- **ROI:** 2-3 hr ETA improvement per cross-modal load

## Opportunity E — Driver Pre-Trip Route Preview (Earth Flyover) (P1)
- **Use case:** New drivers unfamiliar with route see 3D Earth flyover video before departure. 30-second geospatial narrative: highlights hazards (low bridges, sharp curves), toll plazas, fuel stops, rest areas. Reduce navigation errors + improve safety onboarding.
- **Data:** Earth API (elevation, 3D buildings, road curvature) — generate POV video along route with annotations
- **Files:** New `earthFlyoverGenerator.ts` (stream Earth tiles along HERE polyline, render 45° camera), new `RouteFlyoverPreview.tsx` (video player with pause/rewind), driver workflow `LoadDetail` → new "Preview Route" button
- **HERE/Google trade-off:** Completely complementary. HERE provides route; Earth provides immersive preview. Zero conflict.
- **Effort:** M (2-3 wk for v1; refinement ongoing) — Earth WebGL streaming, video rendering pipeline (may offload to Earth Timelapse API)
- **ROI:** Driver navigation errors -30%

## Opportunity F — Receiver Dock Door + Yard Layout Geocoding (P1)
- **Use case:** Shippers upload a PDF facility site plan or photo; Earth recognizes building footprint + dock locations. Gemini API auto-extracts dock door coordinates (precise to meter). Driver gets turn-by-turn directions to "Bay 3, North Side" instead of just "1234 Industrial Ave."
- **Data:** Earth satellite imagery (match against submitted PDFs) + Gemini vision + layout reasoning + custom dock door geocoder
- **Files:** New `geminiDockGeocoder.ts` (analyze facility image + infer dock coords), facility schema → add `dock_locations[]` with `{door_id, lat, lng, door_name}`, driver detail route endpoint → snap to dock door not building center
- **HERE/Google trade-off:** Earth + Gemini is CV/reasoning advantage. HERE doesn't provide this. One-way augmentation.
- **Effort:** M (2-3 wk) — Gemini vision API integration, dock label training, PDF parsing
- **ROI:** Last-mile accuracy + driver satisfaction

---

## Vendor Strategy Recommendation

### HERE-DEFAULT + GOOGLE AUGMENTATION (not migration)

**Rationale:**

1. **HERE as canonical base** — stable routing layer; already in `LocationTrackingMap`, `RoleBasedMap`; no breaking changes; turn-by-turn remains HERE-native

2. **Google APIs as specialized overlays**
   - Earth: elevation, 3D visualization, imagery, geofencing, flyovers
   - Maps: traffic, alternatives, ETA refinement, accessibility
   - Gemini: reasoning about complex spatial problems (yard staging, dock detection)

3. **Financial rationale** — no rip-and-replace cost (months of reengineering); incremental rollout minimizes risk; can A/B test each new capability; vendor flexibility preserved (if Earth pricing becomes unfavorable, revert specific features)

4. **Regulatory + safety win**
   - Heavy-haul contours (A) reduce bridge strikes
   - Vessel draught (B) prevents SOLAS violations
   - Yard staging AI (C) improves yard safety
   - Cross-border forecast (D) reduces driver fatigue + compliance risk

5. **Implementation phasing:**
   - Q3 2026: D (wait-time) + E (flyover) — fast wins, driver-facing
   - Q4 2026: A (heavy-haul contours) — regulatory alignment
   - Q1 2027: C (rail yard AI) — operational multiplier
   - Q2 2027: B (vessel draught) + F (dock geocoding) — cross-modal differentiation

### Expected outcomes
- OS/OW incident reduction: 15-20% (Opp A)
- Driver navigation errors: -30% (Opps E, F)
- Border crossing optimization: 2-3 hours ETA improve per cross-modal load (Opp D)
- Yard throughput lift: 20-30% with AI staging (Opp C)
- Platform switching cost increase: +3-4 points on NPS via geospatial sophistication
