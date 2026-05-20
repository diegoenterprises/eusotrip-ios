# Canonical Post-Load Wizard Inventory — locked 2026-05-20

This document is the **single source of truth** for what the Post-Load Wizard
must support end-to-end. It is locked from the production wizard screenshots
provided 2026-05-20. Every iOS / web / server file referencing equipment,
vertical, FSM, or agreements must satisfy parity against this list.

---

## Industry Verticals (12 — all must be selectable + drive Step 2 filtering)

| # | Vertical | Code | Default trailer hint | Compliance overlay |
|---|----------|------|----------------------|--------------------|
| 1 | General Freight | `general_freight` | Dry Van | none |
| 2 | Refrigerated / Temperature-Controlled | `refrigerated` | Reefer / Food-Grade Liquid | FSMA, FDA, USDA cold-chain |
| 3 | Hazardous Materials | `hazmat` | Hazmat Box / Tank / Cryogenic | 49 CFR 172 + ERG, placards, segregation |
| 4 | Tanker / Liquid Bulk | `tanker_liquid_bulk` | Liquid Tank (DOT-406/407) | 49 CFR 178, vapor recovery |
| 5 | Flatbed / Open Deck | `flatbed_open_deck` | Standard Flatbed / Step Deck | 49 CFR 393 securement |
| 6 | Auto Transport | `auto_transport` | Auto Carrier / Car Hauler | 49 CFR 393.130, height/weight |
| 7 | Intermodal / Container | `intermodal_container` | Intermodal Chassis | AAR, ISO 1496, port drayage |
| 8 | LTL / Partial Load | `ltl_partial` | Dry Van / Curtain Side | NMFC class, freight class |
| 9 | Heavy Haul / Specialized | `heavy_haul_specialized` | Lowboy / RGN / Double Drop | OS/OW permits, escorts |
| 10 | Livestock / Live Animals | `livestock` | Livestock / Cattle Pot | USDA, FMCSA livestock HoS, 28-hr law |
| 11 | Dry Bulk / Pneumatic | `dry_bulk_pneumatic` | Dry Bulk Hopper / Pneumatic Tank | bonded sites, dust suppression |
| 12 | Household Goods / Moving | `household_goods` | Dry Van / Moving Van | 49 CFR 375, HHG bill of lading |

## Trailer Types (23 — all must render in Step 2, with vertical filter)

| # | Trailer | Code | Hazmat-eligible | Spec | Hero animation file |
|---|---------|------|:----------------:|------|---------------------|
| 1 | Liquid Tank Trailer | `liquid_tank` | ✓ | MC-306 / DOT-406 / DOT-407 | truck_07_tanker_hazmat, truck_09_tanker_liquid |
| 2 | Pressurized Gas Tank | `pressurized_gas_tank` | ✓ | MC-331 | truck_10_tanker_gas |
| 3 | Cryogenic Tank | `cryogenic_tank` | ✓ | LNG / LIN / LOX / LH2 | truck_10 variant or vessel_31_LNG |
| 4 | Hazmat Box / Van | `hazmat_box` | ✓ | packaged hazmat | truck_01 + hazmat placard binding |
| 5 | Dry Van | `dry_van` | — | enclosed 53' | truck_01_dryvan |
| 6 | Refrigerated (Reefer) | `reefer` | — | nose-mount refrigeration | truck_02_reefer |
| 7 | Standard Flatbed | `standard_flatbed` | — | 48-53' open deck | truck_03_flatbed |
| 8 | Step Deck / Drop Deck | `step_deck` | — | tall machinery clearance | truck_04 (step deck variant) |
| 9 | Lowboy / RGN | `lowboy_rgn` | — | detachable gooseneck | truck_05 (lowboy variant) |
| 10 | Double Drop / Stretch | `double_drop` | — | extra-tall well | truck_06 (double-drop variant) |
| 11 | Conestoga (Rolling-Tarp) | `conestoga` | — | weather-protected flatbed | truck_11 (conestoga variant) |
| 12 | Auto Carrier / Car Hauler | `auto_carrier` | — | 7-10 car capacity | truck_12 (auto-carrier variant) |
| 13 | Livestock / Cattle Pot | `livestock_cattle_pot` | — | USDA-regulated | truck_21 (livestock variant) |
| 14 | Log Trailer | `log_trailer` | — | 49 CFR 393.116 | truck_22 (log variant) |
| 15 | Dry Bulk / Hopper | `dry_bulk_hopper` | — | pneumatic discharge | truck_(bulk variant) or rail_24_hopper |
| 16 | Gravity Hopper | `gravity_hopper` | — | gravity discharge | rail_24_hopper variant |
| 17 | Grain Hopper | `grain_hopper` | — | USDA-grade | rail_24_hopper grain variant |
| 18 | Pneumatic Tank | `pneumatic_tank` | — | pressure-unload cement/flour | truck_(pneumatic variant) |
| 19 | End Dump Trailer | `end_dump` | — | hydraulic end-dump | truck_(end-dump variant) |
| 20 | Food-Grade Liquid Tank | `food_grade_liquid_tank` | — | milk/juice/wine | truck_09 food-grade variant |
| 21 | Water Tank | `water_tank` | — | potable/non-potable | truck_(water variant) |
| 22 | Intermodal Chassis | `intermodal_chassis` | ✓ (if cargo hazmat) | ISO container chassis | rail_29_flatcar / vessel_16_container |
| 23 | Curtain Side / Tautliner | `curtain_side` | — | side-access loading | truck_11 (curtain variant) |

## Cross-track equivalents (parity requirement)

Every vertical × trailer combo above must have an equivalent **rail** and
**vessel** equipment binding so the Post-Load Wizard supports intermodal
routing without parity gaps:

| Truck trailer | Rail equivalent | Vessel equivalent |
|---------------|-----------------|-------------------|
| Dry Van | Boxcar (rail_23) | Container Ship (vessel_16) |
| Reefer | Reefer Boxcar (rail_28) | Reefer Container Ship (vessel_32) |
| Flatbed | Flatcar (rail_29) / Centerbeam (rail_25) | RoRo (vessel_30) |
| Auto Carrier | Auto Rack (rail_27) | RoRo (vessel_30) |
| Liquid Tank | Tank Liquid (rail_20 DOT-117) | Tanker (vessel_18) |
| Cryogenic Tank | — | LNG (vessel_31) |
| Dry Bulk Hopper | Hopper (rail_24) | Bulk Carrier (vessel_17) |
| Intermodal Chassis | Flatcar (rail_29) | Container Ship (vessel_16) |
| Heavy Haul | Schnabel / Flatcar (rail_29) | Project cargo on RoRo (vessel_30) |
| Pneumatic Tank | — | ISO Tank (vessel_33) |
| Gondola payload | Gondola (rail_26) | Bulk Carrier (vessel_17) |

## Load-cycle FSM — required states per trailer type

Base states (all trailers):
`DRAFT → POSTED → TENDERED_PARTIAL/FULL → BOOKED → EN_ROUTE_TO_PICKUP →
AT_PICKUP → LOADED → EN_ROUTE_TO_DELIVERY → AT_DELIVERY → UNLOADED →
DELIVERED → POD_SIGNED → SETTLED`

Hazmat overlay (all 4 hazmat-eligible + intermodal-with-hazmat):
- `HAZMAT_LOADED` between LOADED and EN_ROUTE_TO_DELIVERY
- `ERG_VERIFIED` at DRAFT
- `PLACARDS_AFFIXED` at LOADED
- `SEGREGATION_VERIFIED` at LOADED (49 CFR 177.848)

Reefer / Food-Grade overlay:
- `TEMP_SETPOINT_CONFIRMED` at AT_PICKUP
- `COLD_CHAIN_VERIFIED` at AT_DELIVERY
- `TEMP_LOG_SEALED` at POD_SIGNED

Livestock overlay:
- `28HR_TIMER_ARMED` at LOADED
- `REST_REQUIRED` if 28hr breaches
- `USDA_INSPECTION_PASSED` at AT_PICKUP

Heavy Haul overlay:
- `PERMITS_VERIFIED` at DRAFT
- `ESCORTS_ASSIGNED` at BOOKED
- `ROUTE_SURVEY_COMPLETE` at DRAFT
- `BRIDGE_CLEARANCE_VERIFIED` at LOADED

Cross-border overlay (any direction US/MX/CA):
- `EN_ROUTE_TO_CROSSING` between EN_ROUTE_TO_DELIVERY
- `AT_BORDER` at crossing
- `CUSTOMS_FILED` (US-ACE / CA-CARM / MX-SAT)
- `CUSTOMS_CLEARED` post-release
- `CLEARED_BORDER`

AV-handoff overlay (autonomous-eligible trailers):
- `AV_HANDOFF_PENDING`
- `AV_DISPATCHED`
- `AV_HANDOFF_COMPLETE` or `AV_FAULT_RECOVERY`

## Agreements / Documents — required per vertical

| Vertical | Required documents at LOADED |
|----------|------------------------------|
| General Freight | BOL, rate confirmation |
| Refrigerated | BOL, temp setpoint, FSMA certificate |
| Hazmat | BOL, hazmat manifest (49 CFR 172.201), shipping papers, emergency response info, driver hazmat training cert |
| Tanker Liquid Bulk | BOL, tank wash certificate, last 3 commodities (food-grade) |
| Flatbed Open Deck | BOL, securement log (49 CFR 393), tarp/strap inventory |
| Auto Transport | BOL, individual vehicle condition reports (VCR) per car |
| Intermodal | BOL, container interchange (UIIA), EIR (equipment interchange receipt) |
| LTL | BOL, NMFC freight class declaration |
| Heavy Haul | BOL, OS/OW permits per state, escort agreement, route survey |
| Livestock | BOL, USDA health certificate, animal welfare cert, 28-hr law log |
| Dry Bulk | BOL, kosher/halal cert (if applicable), prior commodity wash |
| Household Goods | HHG BOL (49 CFR 375), inventory list, valuation, customer release |
| Cross-border | USMCA Certificate of Origin (if claiming preferential treatment), commercial invoice, packing list, pedimento/manifest |

## Driver-side parity

Every trailer type must drive these driver surfaces:
- Equipment-specific pre-trip inspection checklist
- Equipment-specific load animation (Loading / Unloading)
- Equipment-specific PODs (e.g., reefer download, livestock 28-hr log)
- Equipment-specific compliance prompts (placards, securement, temp)

## Catalyst / Dispatch parity

Every trailer type must support:
- Equipment-aware driver-availability filter
- Equipment-specific qualification (endorsements: H, X, N, T, etc.)
- Equipment-aware ELD HoS overlay
- Multi-vehicle composition (for heavy haul / oversize / convoy)

## Broker parity

Every trailer type must support:
- Equipment-specific rate sheet
- Hazmat surcharge multiplier
- Cross-border surcharge
- Detention/demurrage tariffs per equipment

## Settlement parity (HaulPay / EusoWallet / Stripe)

Every trailer type must support:
- Equipment-specific fee multiplier (BASE × COUNTRY × VERTICAL × PRODUCT × HAZMAT × DISTANCE × CYCLE)
- Partial vs full disbursement triggers per trailer
- AP/AR routing per vertical
- ePOD lock for international + hazmat + high-value

---

## Audit checklist (run against this inventory)

- [ ] Step 2 wizard renders all 12 verticals
- [ ] Step 2 wizard renders all 23 trailer types
- [ ] Trailer selection cascades to Step 2 subforms (hazmat, reefer, etc.)
- [ ] Cross-track equivalents wired in mode-switch flow
- [ ] All FSM overlay states implemented per trailer
- [ ] All agreements wired per vertical
- [ ] Driver-side equipment awareness present
- [ ] Catalyst/dispatch equipment filter present
- [ ] Broker rate sheet keyed by trailer code
- [ ] Settlement fee engine keyed by trailer code
- [ ] Animation binding present for every trailer × state
- [ ] Hazmat placard binding wired for all 4 hazmat-eligible trailers
- [ ] Region decal binding wired for US / MX / CA
