# 50 · Verticals Reference — 9 Verticals × 3 Countries

**What this covers.** Deep reference on the nine operational freight verticals served by EusoTrip — Hazmat, Reefer, Flatbed, Livestock, Auto-Hauler, LTL, Tanker, Intermodal, General — across the three North American jurisdictions (USA / Canada / Mexico), including tri-country cross-border flows. Each vertical has dedicated iOS screens, backend routers, compliance gates, pricebook rate multipliers, insurance tiers, and driver endorsement requirements. Source: wave-1 shard `team_VERTICALS_COUNTRIES`.

**When you need this.** When a load picks up a vertical flag (`hazmat`, `reefer`, `flatbed`, etc.) and you need to know what screens + gates activate. When wiring the `dispatchResolver.ts`. When scoping insurance requirements.

**Cross-links.** Cross-border mechanics: [40_Intermodal_and_Cross_Border.md](./40_Intermodal_and_Cross_Border.md). Driver vertical add-ons: [10_Mode_TRUCK/01_Driver.md §12](./10_Mode_TRUCK/01_Driver.md). Schema enumeration: [04_Database_and_Schema.md §4](./04_Database_and_Schema.md).

---

## Part I — The nine verticals

EusoTrip's mobile app is not a generic dispatch surface. It morphs per vertical. A reefer driver running a produce lane out of Salinas sees fundamentally different screens than a hazmat Class 3 tanker operator hauling gasoline on the NJ Turnpike, who in turn sees fundamentally different screens than an auto-hauler operator picking up from a Manheim auction. The doctrine enforces that the iOS app's root navigator reads active load's `verticalType` field and swaps the tab bar, quick-actions, required-evidence checklist accordingly. **One binary and nine personalities.**

### 1. HAZMAT

Highest-liability vertical. A single missed placard or incorrectly completed shipping paper can trigger PHMSA penalties up to **$89,678 per violation** (2024 inflation-adjusted) and void carrier insurance entirely.

**9 Hazard Classes:**
- Class 1: Explosives (1.1–1.6 division)
- Class 2: Gases (2.1 Flammable, 2.2 Non-flammable, 2.3 Toxic)
- Class 3: Flammable liquids
- Class 4: Flammable solids / Spontaneously combustible / Dangerous when wet
- Class 5: Oxidizers / Organic peroxides
- Class 6: Toxic / Infectious substances
- Class 7: Radioactive
- Class 8: Corrosives
- Class 9: Miscellaneous (lithium batteries, elevated-temperature materials)

**iOS screens:**
- `HazmatPlacardingScreen.swift` — driver photographs all four sides of trailer before load marked loaded. CV model (`placard_detection_v4.mlmodel`, ~11MB Core ML) runs on-device verifying correct placards affixed + legible. Manual override requires dispatcher approval PIN.
- `ShippingPaperScreen.swift` — UN number, proper shipping name, hazard class, packing group, emergency response phone in federally-mandated order. Driver confirms vs BOL.
- `ERGLookupScreen.swift` — Emergency Response Guidebook 2024 bundled as searchable offline database (~24MB). Lookup by UN number or material name → orange-page isolation/evacuation distances.
- `RouteComplianceScreen.swift` — NHS hazmat-designated routes, tunnel restrictions (Baltimore Harbor, Lincoln, Ted Williams), urban-area variances. Integrates with `hazmat.ts` (91KB) for real-time route blackouts.
- `HM-232SecurityPlanScreen.swift` — driver attests truck locked when unattended, security plan reviewed, logs every stop > 30 minutes.

**Backend router**: `hazmat.ts` (91KB — largest regulatory router). Endpoints: `validateShippingPaper, checkRouteRestrictions(originZip, destZip, unNumber), generateEmergencyContactCard, getPlacardRequirements(unNumber, quantity, packingGroup), logSecurityStop`. Holds DOT routing-exclusion tables keyed by UN number + state.

**Compliance gates blocking dispatch:**
- Driver CDL with H endorsement (or X if tanker-hazmat combined) — `driverEndorsements.hazmatExpiry` not expired.
- TSA HME (Hazardous Materials Endorsement) fingerprint clearance non-expired.
- Shipping paper signed digitally by both shipper + driver.
- Placards affixed + photo-verified.
- Route approved through PHMSA-compliant lane check.
- Insurance certificate on file with MCS-90 endorsement visible.

**Rate multipliers**: Base × 1.35 for Class 3/8/9 common haz, × 1.65 for Class 1 explosives, × 1.75 for Class 7 radioactive, × 1.50 for Class 6.1 toxics. Stacked for hazmat + tanker combinations (× 1.95 ceiling).

**Insurance**: Minimum $5M liability for bulk haz, $1M MCS-90 for non-bulk, $5M pollution liability for Class 3 + Class 8. Radioactive requires NRC certificate + $10M nuclear-specific rider.

**Endorsements**: CDL-A with H (hazmat) or X (tanker-hazmat). TSA HME. Some shippers (military, nuclear) additionally require TWIC.

---

### 2. REEFER

Refrigerated freight sits under FSMA Sanitary Transportation Rule at **21 CFR 1.908** — carrier must maintain + provide temperature logs for duration of haul + 12 months. Non-compliance is FDA matter; a single excursion can cause $400,000 pharma load to be rejected outright.

**iOS screens:**
- `ReeferTempLogScreen.swift` — live display of set-point, actual return-air, actual supply-air, ambient, deviation history. Auto-syncs every 5 minutes with telematics provider (Thermo King TracKing, Carrier Lynx Fleet, Orbcomm) via `reeferTemp.ts`.
- `ReeferSetPointScreen.swift` — requires shipper-supplied set-point at tender acceptance. Driver can adjust only within shipper's allowed tolerance band (typically ±2°F). Any deviation triggers alert to dispatch + shipper.
- `MultiTempZoneScreen.swift` — for dual/tri-temp trailers (Great Dane Everest Reefer with bulkheads). Each zone independently tracked.
- `PreTripReeferScreen.swift` — 20-point pre-cool + pre-trip inspection. Reefer fuel level (separate from tractor), belt condition, defrost cycle completion, probe calibration.
- `ReeferFuelScreen.swift` — reefer fuel is distinct line item. Driver logs gallons, receipts OCR'd via `receiptOCR.ts`, reconciled nightly.
- `DeviationAlertScreen.swift` — any excursion >30 minutes outside tolerance triggers modal. Driver responds: (a) acknowledged + corrected, (b) mechanical failure, (c) door opened for inspection. Each path logged immutably.

**Backend router**: `reeferTemp.ts` — ingests continuous temperature stream, runs FSMA 1.908 checks, produces exportable PDF "Temperature Log Report" signed with SHA-256 integrity hash.

**Compliance gates:**
- Trailer has calibrated reefer with valid calibration cert (annual).
- Driver completed FSMA Food Transporter training (refreshed every 3 years).
- Pre-cool completed + logged (set-point achieved for 30+ minutes before loading).
- Food-grade wash if last load non-food (tanker-style wash ticket).
- Pharmaceutical loads (Class II cold chain 2–8°C) require validated reefer per 21 CFR 205 + shipper SOP attestation.

**Rate multipliers**: Base × 1.20 standard produce, × 1.35 frozen (below 0°F), × 1.45 multi-temp, × 1.75 pharmaceutical GDP validated equipment.

**Insurance**: Cargo coverage minimum $100,000, scaling to $250,000 for pharma. Contamination/spoilage rider required for all food-grade moves.

**Endorsements**: Standard CDL-A. No special federal endorsement, but FSMA training attestation is gate-blocking.

---

### 3. FLATBED

Physical skill vertical. Load securement is the regulation line (FMCSA **49 CFR 392.9** + Subpart I of Part 393). Improper tie-downs kill people; roadside inspector puts truck OOS for single missing strap.

**iOS screens:**
- `FlatbedSecurementScreen.swift` — driver selects commodity type (coil, lumber, pipe, machinery, steel plate); app computes minimum strap count + working load limit (WLL) math per 393.106. Photo-capture for each strap / chain / corner protector.
- `TarpingScreen.swift` — weather-sensitive freight. Tarp condition inspection, number of tarps (steel tarp, lumber tarp, smoke tarp), bungees/straps count.
- `PermitScreen.swift` — over-dimensional moves. State-by-state permit PDFs, validity windows, pilot-car requirements, curfew hours (no-travel windows — no movement in NY after 3pm Friday), bridge-law routings. Integrates with `trailerRegulatory.ts` (61KB).
- `HeavyHaulScreen.swift` — 80,001+ lb configurations. Axle weight distribution calculator, superload approvals, route surveyor contact log.
- `CornerProtectorScreen.swift` — photo proof all edge/corner protectors in place before strap tensioning.

**Backend router**: `trailerRegulatory.ts` (61KB) handles permit aggregation across state DOTs, bridge-law computations, over-dimensional escort requirements. Integrates with ProMiles for routing.

**Compliance gates:**
- Minimum strap/chain count per commodity computed + acknowledged.
- All securement photographed.
- Permits on file for every state if any dimension exceeds 8'6"W × 13'6"H × 53'L or 80,000 lb gross.
- Pilot-car contracted if required (>12' wide, >14'6" high, >100' long in most states).
- Tarps in place if commodity marked "tarpable."

**Rate multipliers**: Base × 1.15 standard flat, × 1.45 over-dimensional, × 1.85 superload (>160,000 lb or >16' wide), × 1.25 tarped. Heavy-haul specialists × 2.00+ on bespoke freight.

**Insurance**: $100,000 cargo standard, $250,000 heavy-machinery, $1M+ for transformers / wind blades.

**Endorsements**: Standard CDL-A. No federal endorsement, but many heavy-haul shippers require internal 6-month flatbed tenure before dispatch.

---

### 4. LIVESTOCK

Animal-welfare vertical. The **28-hour law** (49 USC 80502) mandates unloading for feed, water, rest after 28 consecutive hours of transit. Cross it → USDA civil penalties + activist attention.

**iOS screens:**
- `CVIScreen.swift` — Certificate of Veterinary Inspection. Driver captures from USDA-accredited vet: issuance date, destination state, species, head count, individual animal IDs (or lot ID for feeder cattle). Expires 30 days typically.
- `BrandInspectionScreen.swift` — required for cattle moves in 14 brand-inspection states (CO, MT, WY, NV, ID, NM, OR, SD, ND, UT, WA, CA, AZ, AR parts). Inspector's brand certificate photographed.
- `LoadingDensityScreen.swift` — based on species, weight class, weather. Computes recommended head-per-compartment. 53' pot-belly (double-decker) has different density rules than straight trailer.
- `WaterRestStopScreen.swift` — runs 28-hour-law countdown. At 24h alerts driver to plan 5-hour minimum rest stop with water + feed. At 27h escalates to dispatch.
- `WeatherScreen.swift` — heat index / cold stress warnings. High-humidity + >85°F forces compartment-fan check, may deny dispatch until temps fall.
- `BeddingScreen.swift` — photo of bedding (shavings, sand, sawdust) appropriate to species. Pigs get deep sawdust in winter, cattle get light shavings year-round.

**Backend router**: `livestock.ts` — holds 28-hour-law timer, brand-inspection state matrix, USDA-accredited vet directory for nine western states.

**Compliance gates:**
- CVI on file, unexpired, matching species + destination.
- Brand inspection cert if required.
- 28-hour-law timer armed + compliant.
- Bedding photographed.
- Weather within safe envelope or mitigations acknowledged.

**Rate multipliers**: Base × 1.30 cattle, × 1.40 swine (biosecurity), × 1.60 poultry (high mortality), × 1.80 exotics / show animals.

**Insurance**: Cargo scales to animal market value. Mortality coverage separate rider — $500/head standard feeder, $5,000/head breeder, bespoke for racehorses ($500k+).

**Endorsements**: CDL-A. Some states require livestock-hauler registration. USDA APHIS Animal Handler certification recommended.

---

### 5. AUTO-HAULER

Moving $90,000 F-350 Platinum → driver-induced scratch during unload is claim carrier eats. VIN scanning + condition reports are the defense.

**iOS screens:**
- `VINScannerScreen.swift` — camera OCRs 17-character VIN from door jamb or windshield, validates check digit, cross-references dispatch manifest. Scanned at pickup + delivery.
- `DamageReportScreen.swift` — 3D car model driver rotates + taps to mark scratches, dents, missing parts. Timestamped photos attached per marker. Generates signed condition report.
- `LoadingPositionScreen.swift` — 9-car open carrier has slotted positions (head rack, over-cab, ramps). App computes optimal loading order for weight distribution + unloading sequence.
- `AuctionPickupScreen.swift` — Manheim, ADESA, IAA, Copart integrations. Auction gate pass, buyer number, release documents captured.
- `EnclosedLoadScreen.swift` — high-value enclosed transport. Cover-soft check, tie-down strap check (no chains on exotics), climate-control logging for classics.
- `RollOnRollOffScreen.swift` — non-running vehicles requiring winch operations.

**Backend router**: `autoHauler.ts` — VIN decoding via NHTSA API, auction-house integrations, damage-claim generation.

**Compliance gates:**
- VIN scanned + confirmed matching manifest both ends.
- Condition report signed by shipper AND driver at pickup.
- Weight distribution within per-axle limits (especially car carriers where front overhang is common).
- Tie-down count per NHTSA recommended practices (4 straps per vehicle minimum).

**Rate multipliers**: Base × 1.25 open carrier, × 1.65 enclosed, × 1.90 enclosed with climate control, × 2.10 exotic/classic (white-glove).

**Insurance**: Cargo $250,000 open standard, $500,000 enclosed, $1M+ for exotic. Inoperable/winch rider for non-runners.

**Endorsements**: CDL-A. Car hauler experience typically required by insurers for 1 year minimum before underwriting.

---

### 6. LTL (Less-Than-Truckload)

Multi-stop, pallet-counting, terminal-network vertical. Freight class (NMFC) determines rate; density + handling + stowability + liability drive the class.

**iOS screens:**
- `NMFCClassScreen.swift` — driver/dock worker enters dimensions + weight; app computes density, suggests NMFC class (50-500 range). Integrates with NMFTA's ClassIT API.
- `PalletCountScreen.swift` — dock scan of every pallet at pickup, intermediate terminal, delivery. Pallet-jack and forklift availability flags.
- `TerminalScheduleScreen.swift` — terminal operating hours, appointment windows, dock door assignment, live gate queue length.
- `MultiStopScreen.swift` — ordered stop list with geofenced arrival/departure. Each stop has own BOL, pallet count, POD.
- `HazmatDenseCargoScreen.swift` — hazmat in LTL is combined vertical. Triggers segregation-table checks (Class 3 + Class 5.1 cannot co-load in same compartment).

**Backend router**: `ltl.ts` + `nmfc.ts` — rating engine, terminal network routing, BOL generation.

**Compliance gates:**
- NMFC class confirmed per bill.
- Terminal appointments confirmed.
- Segregation rules enforced if mixed haz in trailer.
- Tri-axle pallet jack / lift-gate confirmed if delivery is residential or no-dock.

**Rate multipliers**: Complex — class-driven, not multiplier. Surcharges: residential pickup/delivery (flat $95), lift-gate ($75), inside delivery ($85), limited access (mine, job site, military base: $120).

**Insurance**: Cargo per NMFC released value rules. Most LTL carriers cap at $25/lb released unless declared value.

**Endorsements**: CDL-A. Forklift certification for dock work.

---

### 7. TANKER

Tankers haul product. Previous three loads matter because residue contamination is #1 cause of rejected loads.

**iOS screens:**
- `TankerWashTicketScreen.swift` — every wash bay visit captured: wash facility ID (Kag, Quala, Groendyke), wash type (detergent, caustic, kosher, food-grade heel-out), last-3-commodity declaration, seal numbers post-wash. Wash ticket PDF attached.
- `LastThreeLoadsScreen.swift` — shipper pulls to determine product compatibility. Chemical compatibility matrix runs server-side.
- `CompartmentScreen.swift` — multi-compartment tankers (5-compartment gasoline) track each compartment's product, volume, seal number independently.
- `PSMPHAScreen.swift` — high-hazard chemicals (HCl, anhydrous ammonia, chlorine). Process Safety Management / Process Hazard Analysis documentation surfaced pre-dispatch.
- `LoadingSealScreen.swift` — every dome lid and outlet valve gets tamper-evident seal. Seals logged by number.
- `OffloadScreen.swift` — petroleum: bottom-loading vapor-recovery confirmation. Food-grade: sanitary hose inspection.

**Backend router**: `tanker.ts` + `chemCompat.ts` — product compatibility matrix, wash facility directory, seal log.

**Compliance gates:**
- Last-3-loads wash compatibility check passed.
- Wash ticket on file if required by shipper.
- Appropriate seals affixed + logged.
- Driver holds N endorsement (or X if hazmat-tanker).
- PSM/PHA documentation on file for high-hazard.

**Rate multipliers**: Base × 1.25 food-grade, × 1.45 petroleum, × 1.55 chemical non-haz, × 1.85 hazmat chemical, × 2.10 cryogenic (LNG, liquid O2).

**Insurance**: $1M liability floor, $5M for petroleum, $10M for toxic-by-inhalation (Class 2.3). Pollution rider $5M minimum.

**Endorsements**: CDL-A with N (tank vehicle). X if hazmat. TWIC for refinery / port access.

---

### 8. INTERMODAL (Chassis Drayage)

Port/rail-to-door vertical. Chassis separate asset from container; per-diem accumulates fast.

**iOS screens:**
- `ChassisInspectionScreen.swift` — UIIC (Uniform Intermodal Interchange and Facilities Access Agreement) pre-trip inspection. Tire condition, lights, ABS, landing gear, twist-locks. Standard J1 criteria.
- `PerDiemScreen.swift` — running clock on container per-diem (shipping line) and chassis per-diem (pool provider). Alerts when approaching free-time expiry.
- `StreetTurnScreen.swift` — when empty container can be reused for new export booking without returning to port, saving per-diem + port trip. App confirms steamship-line approval before street turn.
- `ChassisProviderScreen.swift` — pool selection (TRAC Intermodal, DCLI, FlexiVan, SACP) + interchange receipts.
- `ContainerSizeScreen.swift` — 20' / 40' / 45' / 53' container codes, gross weight verification (VGM requirement for export per SOLAS).
- `UIICScreen.swift` — master intermodal interchange agreement. Violations logged here.

**Backend router**: `intermodal.ts` — per-diem clocks, chassis-pool integrations, steamship-line API calls.

**Compliance gates:**
- Chassis UIIC inspection completed + logged.
- Container seal number confirmed on gate-out.
- VGM provided for exports (SOLAS compliance).
- Driver holds TWIC for port access.

**Rate multipliers**: Base × 1.05 local drayage (<50mi), × 1.20 regional drayage (50–250mi), × 1.15 street turn (savings passed through).

**Insurance**: Standard motor carrier liability + UIIC per-incident chassis damage coverage ($100k minimum).

**Endorsements**: CDL-A. TWIC. Port-specific RFID credentials (LA/LB PortCheck).

---

### 9. GENERAL / DRY VAN

Default vertical. 53' dry van, palletized or floor-loaded, non-regulated freight. Everything the other verticals aren't.

**iOS screens:**
- `DryVanPreTripScreen.swift` — standard CVSA Level 1 inspection items.
- `LoadSecurementScreen.swift` — light-duty securement: load bars, straps, airbags.
- `PODScreen.swift` — proof-of-delivery signature + photo.
- `SealScreen.swift` — seal number logged at pickup + delivery.
- `DockScreen.swift` — dock-door assignment, appointment window, detention timer.

**Backend router**: `dryVan.ts` (minimal — most functionality in shared dispatch core).

**Compliance gates:**
- Pre-trip inspection completed.
- Seal integrity maintained.
- POD captured at delivery.

**Rate multipliers**: Base × 1.00 (baseline). Surcharges: appointment delivery ($25), driver-assist ($75), team driver requirement (× 1.30).

**Insurance**: $100,000 cargo standard, $1M auto liability (FMCSA minimum).

**Endorsements**: CDL-A. That's it.

---

## Part II — The three countries

### 1. USA

Most regulated freight market on earth. EusoTrip's US stack anchored by FMCSA + specialty regulators.

**Regulatory bodies + mobile integration:**
- **FMCSA** — governs HOS, CDL, CSA, DOT/MC authority. Pulls carrier's SAFER snapshot nightly, surfaces CSA deterioration alerts.
- **ELD mandate** (49 CFR Part 395) — EusoTrip is registered ELD provider (FMCSA Registration No. EUSO). ELD module is sub-app inside main binary, showing duty-status, remaining-drive clocks (11/14/70), personal conveyance flags.
- **HOS cycles** — 11 hours driving, 14 on-duty, 70/8 (or 60/7). 30-min break after 8 cumulative driving. Split-sleeper provisions.
- **IFTA** — every fuel receipt geocoded, mileage per jurisdiction computed for quarterly filing.
- **UCR** — Unified Carrier Registration. Annual by fleet size.
- **PHMSA** — hazmat (see Vertical 1).
- **FDA** — food (see Vertical 2 — FSMA 1.908).
- **USDA / APHIS** — livestock + ag (see Vertical 4).
- **DOT/MC authority** — operating authority. MC number on all BOL + inspection reports.
- **BOC-3** — designation of process agents for every state. Surfaced + expiration-flagged.

**US-specific compliance gates (mobile):**
- ELD status current + duty-cycle not exceeded.
- IFTA fuel receipts geocoded correctly.
- DOT medical card unexpired.
- CDL unexpired.
- Drug/alcohol clearinghouse query within 12 months for new hires, annual for tenure.

**US pricebook modifier**: Base rates USD. EusoTrip multiplier applied atop DAT/Truckstop load board benchmark pricing.

---

### 2. CANADA

**Regulatory bodies + mobile integration:**
- **Transport Canada** — federal. Administers Motor Vehicle Transport Act.
- **NSC** (National Safety Code) — Canadian equivalent of FMCSA safety rules, administered province-by-province.
- **ELD mandate** — effective 2023, distinct cycle from US: 13 hours driving, 14 on-duty, 70/7 or 120/14 cycles. App auto-swaps cycle logic based on side of border (geofence trigger).
- **TDG** (Transportation of Dangerous Goods) — Canadian hazmat framework. Class structure mirrors UN but placarding + shipping-paper rules differ. Distinct TDG training cert required.
- **CFIA** (Canadian Food Inspection Agency) — food + livestock imports/exports. CFIA permits + conditional releases drive `livestock.ts` and `reeferTemp.ts` router paths when Canadian.
- **Provincial weight/dimension regs** — Ontario tridem limits differ from Quebec. BC has unique mountain-pass chain requirements. Routing engine holds province-specific axle-weight tables.

**Canada-specific mobile screens:**
- `CanadaHOSScreen.swift` — alternate cycle math.
- `TDGShippingPaperScreen.swift` — French/English bilingual shipping paper.
- `ProvincialPermitScreen.swift` — per-province overweight/oversize permits.
- `NSCSafetyScoreScreen.swift` — carrier's NSC rating visible to driver.

**Canadian compliance gates:**
- NSC safety rating "Satisfactory" minimum.
- TDG certificate on file (3-year renewal) for hazmat.
- Driver's provincial commercial license unexpired.
- Bilingual shipping papers for hazmat crossing Quebec.

---

### 3. MEXICO

**Regulatory bodies + mobile integration:**
- **SCT → SICT** (Secretaría de Infraestructura, Comunicaciones y Transportes) — federal transportation authority. Issues federal motor carrier permit (permiso federal).
- **NOM-087** — Mexican hazmat transportation standard, equivalent to PHMSA in spirit but with distinct placard specs, shipping paper format, driver training.
- **Carta Porte** (Complemento Carta Porte) — digital waybill/CFDI supplement required since 2023 for all motor carriage inside Mexico. Contains origin/destination, commodity, weight, hazmat declaration, distances. Must be signed digitally via SAT. App generates via `cartaPorte.ts`, validates XML against SAT schema, attaches UUID to load record.
- **VUCEM** — Mexico's single-window customs portal. All cross-border documentation flows through.
- **CFDI** — Mexican tax invoice standard. Every freight invoice must be CFDI with proper use-code. Carta Porte supplement attaches to CFDI.
- **SAT** — tax authority. Issues RFC (tax ID) for carriers, validates CFDI.

**Mexico-specific mobile screens:**
- `CartaPorteScreen.swift` — generate, validate, attach Carta Porte XML + PDF. SAT UUID on face.
- `NOM087Screen.swift` — Mexican hazmat shipping paper in Spanish with NOM-087 required fields.
- `CFDIScreen.swift` — freight CFDI generation + SAT stamping.
- `MexicanCDLScreen.swift` — Federal Licencia Federal de Conductor (Tipo A / B / C / D / E) verification.

**Mexican compliance gates:**
- Carta Porte generated, XML-valid, SAT-stamped.
- CFDI issued with correct use-code.
- Federal SICT permit on file.
- Driver holds Licencia Federal appropriate for vehicle.
- NOM-087 hazmat training for hazmat lanes.

---

## Part III — Cross-border flows

See [40_Intermodal_and_Cross_Border.md](./40_Intermodal_and_Cross_Border.md) for the full cross-border playbook (USMCA, VUCEM, Carta Porte, ACE/ACI, NOM, TDG, chassis pools, tri-country flows).

---

## Part IV — The vertical × country matrix

App's routing engine at dispatch time resolves:

`dispatchResolve(verticalType, countryOfOperation, crossBorderFlag) → requiredScreens[], requiredGates[], rateMultiplier, insuranceTier, endorsementSet`

Resolution in `dispatchResolver.ts`, which imports every vertical router (hazmat.ts, reeferTemp.ts, trailerRegulatory.ts, livestock.ts, autoHauler.ts, ltl.ts, tanker.ts, intermodal.ts, dryVan.ts) and every country router (usa.ts, canada.ts, mexico.ts, usmca.ts, cartaPorte.ts, aci.ts, ace.ts). Output hydrates iOS app's navigator state at load acceptance.

**Maximum-complexity case.** Hazmat reefer tanker carrying Class 6.1 pharmaceuticals on Laredo → Monterrey → Calgary tri-country lane: 42 required screens, 31 compliance gates, rate multiplier 2.85, insurance tier "PLATINUM+" ($15M pollution + $10M cargo + $5M liability), endorsement set `{H, N, X, TWIC, FAST, TDG, Licencia-Federal-E, C-TPAT}`.

**Minimum-complexity case.** One-way dry van Atlanta → Dallas: 8 screens, 4 gates, 1.00× multiplier, standard FMCSA minimums.

Doctrine enforces: both cases ship the **same iOS binary**, with **identical code paths**, and only the data-driven resolver distinguishes them. One binary, nine personalities, three countries, unbounded combinations.

---

Last updated: 2026-04-23
Synchronized with: eusotrip-killers scheduled task
