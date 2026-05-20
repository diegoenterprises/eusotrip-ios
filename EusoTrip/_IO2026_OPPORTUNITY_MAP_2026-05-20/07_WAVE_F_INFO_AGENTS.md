# Wave F — AI Search × Information Agents
**Agent #6 deliverable** | 7 multi-turn agents + chrome strategy

## Agent 1 — Hazmat Compliance Agent (P0)
**Role:** Shipper, hazmat certifier, driver
**Replaces:** ERG search modal (`ergSearchRouter.ts` dropdown picker)

**Sources:** 49 CFR 172.101 table, segregation matrix (49 CFR 177.848), PHMSA ERG guides 115-171, tank spec/stencil requirements

**4-turn flow:**
1. "What's the ERG guide for UN1830?" → UN1830 sulfuric acid → Guide 137, class 8, packing II, DOT 412 tank spec
2. "What PPE do I need?" → PPE matrix for guide 137 corrosives, level A/B
3. "Can I haul this with class 3 flammables?" → segregationCheck → incompatible, cites 49 CFR 177.848
4. "Show me a sample manifest." → manifest template with UN1830 placard/stencil pre-filled

**Files:** `ergSearchRouter.ts` + multi-turn context, `49_cfr_172_101_seed.json` + PPE matrix + manifest refs, new `getFollowUpContext()` tRPC procedure, `CustomsBrokerSurface.tsx` agent panel
**Effort:** M (data exists; serialize follow-up state)

## Agent 2 — Shipment Status Agent (P0)
**Role:** Shipper, broker, dispatch
**Replaces:** Search-by-load-ID page + status detail drill-down

**Sources:** Shipment API + GPS/ELD telemetry (real-time) + driver profile + hazmat/commodity (linked to 49 CFR) + load event log

**5-turn flow:**
1. "Where is shipment LD-2026-04812?" → current location (map pin), ETA, driver name, vehicle
2. "Are we on time?" → compares actual vs. scheduled, returns yes/no + delta
3. "Who's the driver?" → driver card (name, photo, safety score, miles, hazmat endorsement)
4. "What am I shipping exactly?" → commodity, UN if hazmat, weight, value, linked 49 CFR entry
5. "Show me the placard requirements." → ERG guide entry (hazard class, erg_guide, stencil) + visual placard render

**Files:** `shipments.ts` + `getShipmentAgent()` endpoint with context persistence, `ergSearchRouter.ts` link commodity → placard, `TrackShipments.tsx` agent interface, `ShipmentCard.tsx` rendering
**Effort:** M (APIs exist; agent layer is orchestration)

## Agent 3 — Compliance Segregation Agent (P0)
**Role:** Shipper, logistics manager, customs broker
**Replaces:** 49 CFR rules lookup page (static reference)

**Sources:** 49 CFR 172.101 + segregation matrix, DOT placard/label spec, marine pollutant flag, packing group constraints

**3-4 turn flow:**
1. "Can I ship UN1203 gasoline and UN2031 nitric acid together?" → segregationCheck → incompatible (class 3 vs. 8), 49 CFR 177.848
2. "What if I use separate compartments?" → compartment spec (DOT 406 with divider or dual-tank), safety distance rule
3. "What's the marine pollutant rule for UN2031?" → UN2031 NOT marine pollutant; UN2014 (H2O2) IS; shows handling difference

**Files:** Extend `ergSearchRouter.ts` segregationCheck with follow-up sub-queries, `49_cfr_172_101_seed.json` + compartment spec links, new `compliance.ts` tRPC router, `CustomsBrokerSurface.tsx` agent panel
**Effort:** S-M (logic + data already in router; extend with compartment + marine rules)

## Agent 4 — Lane Intelligence + Pricing Agent (P1)
**Role:** Shipper, dispatch, analyst
**Replaces:** Pricebook lookup + lane analysis page

**Sources:** Internal lane history (truck, rail, vessel), carrier availability by lane, seasonal multipliers (peak/off-peak), hazmat surcharge matrix, reefer premium

**4-turn flow:**
1. "What's the going rate Dallas → Houston?" → truck $/mi (7d avg), rail $/ton, vessel $/TEU
2. "For hazmat?" → hazmat surcharge (+15-25%), shows delta
3. "For reefer loads?" → reefer premium (+8-12% vs. dry van)
4. "Peak season impact?" → Q4 holiday multiplier (+20-35%), Nov 1 – Dec 31 date range

**Files:** `pricebook.ts` + new `getLaneIntelligence()` endpoint with context, `fsc.ts` link FSC schedule to lane query, new `/lanes-intelligence` page or extend Marketplace.tsx, `PricingCard.tsx` rendering
**Effort:** M (historical data aggregation; seasonality rules exist in dispatch)

## Agent 5 — Partner/Carrier Vetting Agent (P1)
**Role:** Shipper, procurement, dispatch
**Replaces:** Carrier search page + FMCSA lookup modal

**Sources:** FMCSA carrier safety DB (DOT lookup), EusoTrip internal scorecard (on-time%, damage rate, accept%), CSA scores + OOS violations, insurance verification, ELD/compliance status

**4-turn flow:**
1. "Is MC-567890 safe to use?" → FMCSA + EusoTrip scorecard → safety rating (A-F), on-time, damage rate
2. "What's their CSA score?" → CSA BASICS breakdown (unsafe speed, critical violations, hazmat, etc.)
3. "Any recent OOS violations?" → last 12 months OOS events by category (brake, light, hazmat cert, HOS, etc.)
4. "Can they haul hazmat?" → checks hazmat endorsement in ELD, returns yes/no + cert expiry

**Files:** New `fmcsa.ts` tRPC endpoint wrapping FMCSA API + EusoTrip scorecard, extend `carrier.ts` with `getCarrierAgent()`, `Carriers.tsx` agent interface, `CarrierCard.tsx` rendering
**Effort:** M (FMCSA API integration + scorecard data aggregation)

## Agent 6 — USMCA Certificate Generator Agent (P2)
**Role:** Shipper, customs broker
**Replaces:** `FileEntryForm` static form (`CustomsBrokerSurface.tsx` lines 258-299)

**Sources:** HS code database (tariff classification), USMCA rules of origin (yarn forward, RVC %), blanket period templates, importer/exporter/producer registry

**5-turn flow:**
1. "I'm shipping electronics to Mexico. Do I need USMCA cert?" → yes + suggests HS code 8471 (automatic data processing machines)
2. "What's the HS code exactly?" → offers narrowed codes (8471.30 vs 8471.41), asks form factor (laptop? desktop?)
3. "It's laptops from Vietnam." → flags non-USMCA origin; suggests alternative (laptop assembled in Mexico qualifies) or offers duty-only path
4. "Use blanket cert?" → explains blanket vs. transaction, suggests 6-month blanket (Q2-Q3), auto-fills dates
5. "Generate the cert." → USMCA form pre-filled with HS, origin criterion (RVC %), importer/exporter, ready to sign

**Files:** Replace `CustomsBrokerSurface.tsx` lines 258-299 `FileEntryForm` with agent panel, new `usmca.ts` endpoint with HS code lookup + origin rules, extend `customs.ts` file-crossing endpoint to accept agent context, new `UsmcaAgent.tsx` component
**Effort:** L (HS code taxonomy large; origin rules need USMCA rules engine; form filling is sequential)

## Agent 7 — Equipment Selection Agent (P1)
**Role:** Shipper, dispatch, logistics manager
**Replaces:** Equipment picker (trailer type, refrigeration, cross-border docs)

**Sources:** Trailer type specs (dry van, reefer, flatbed, tanker), weight/dimension constraints by border (MX 38k-lb, CA DOT weight), document requirements by commodity + crossing, equipment availability by lane (internal fleet)

**4-turn flow:**
1. "I have 22 pallets of palletized consumer goods going to Mexico." → recommends 53-ft dry van (max ~25 pallets), asks weight
2. "They're 950 kg each. Is that within limit?" → 22 × 950 kg = 20.9 tonnes (46k lbs) → within 38k-lb MX GVW limit; also OK for CA
3. "What documents do I need?" → USMCA cert (if applicable), commercial invoice, packing list, shipper affidavit; links to customs broker agent
4. "What's available on my preferred lane?" → fleet availability on Dallas → Mexico City (trailer types, reefer units, hazmat-certified)

**Files:** New `equipment.ts` tRPC endpoint for rig recommendation, extend `shipments.ts` with equipment validation, replace equipment picker dropdown in `LoadCreate.tsx` with agent panel, `EquipmentSelector.tsx` rendering
**Effort:** M (specs + constraints known; asset availability API call)

---

## AGENT vs. APP CHROME — Surfacing Strategy

To avoid "chat bot everywhere" bloat, deploy agents in **conversational pockets**, not as a universal chat overlay:

### Surfaces (NO global chat)
1. **Customs Broker Surface** — Agent panel (right sidebar) ONLY for filing detail, not every action
2. **Shipper Load Creation** — Agent activates on "Pick equipment" step; returns to form when complete
3. **Tracking Page** — Agent search box replaces text input; results appear inline
4. **Hazmat Compliance Panel** — Agent only in shipper post-load wizard, accessed via "Check regulations" button
5. **Carrier Vetting** — Agent search sidebar in shipper marketplace; not in every load card

### When NOT to use agents
- No chat in header/nav (avoid omnipresent search bar)
- No agent for single-answer queries (e.g., "What's your phone number?")
- No agent for data-entry (e.g., "Fill in recipient name") — use forms
- No agent for settings, account management, or password resets

### Interaction triggers
- **Buttons only:** "Check regulations", "Get carrier intel", "Quote this lane", "Generate USMCA", "Pick equipment" — all route to agent sidebar
- **Search boxes** (tracking, carrier, lane lookup) become agent entry points
- **Follow-ups** stay within agent context; exiting agent returns to calling page with result

### UX affordance
- Agent panels show `<` or "X" close button (don't auto-hide on follow-up)
- Results export to form fields or clipboard (no copy-paste friction)
- Visual separation from main content (sidebar, modal, or dedicated sub-page)

---

## Implementation priority

| Wave | Quarter | Agents |
|------|---------|--------|
| 1 | Q3 2026 | Agent 2 (Shipment Status) — highest ROI, data-rich, motivates adoption • Agent 3 (Compliance Segregation) — regulatory urgency, small data footprint |
| 2 | Q4 2026 | Agent 1 (ERG Guide) — incremental to Compliance • Agent 4 (Lane Intelligence) — revenue optimization, network effects • Agent 5 (Carrier Vetting) — risk reduction |
| 3 | Q1 2027 | Agent 6 (USMCA Generator) — high complexity, lower volume • Agent 7 (Equipment Selection) — dependency on fleet API maturity |
