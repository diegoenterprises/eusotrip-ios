# Parity Audit Findings — Synthesis
**Date:** 2026-05-20  
**Scope:** Full iOS Swift codebase (370+ files across Views/Shipper, Driver, Catalyst, Broker, Dispatch, Models, ViewModels, Services)  
**Methodology:** 6 specialized audit agents, each scoped to a parity surface, all reading directly against the canonical inventory at `00_CANONICAL_WIZARD_INVENTORY.md`

---

## Overall parity score: **~32%** against the canonical inventory

The iOS app has a strong **foundation** (53 vehicle child states, parent shipment state machine, multi-modal models, equipment animation framework) but is **missing the lock-in layer** — there is no place in the Swift type system where "this is the list of 12 verticals" or "this is the list of 23 trailer codes" is declared. As a result, the wizard accepts arbitrary equipment strings, agreements are not keyed by vertical, FSM overlay states for hazmat/reefer/livestock/heavy-haul/cross-border are not modeled, and the fee multiplier engine only implements 1 of the 7 canonical multipliers.

---

## Findings by parity surface

### 1. Step 2 (Equipment) wizard — 30%
**Files:** `251_PostLoadStep2Equipment.swift`, `257_PostLoadHazmatSubform.swift`, `258_PostLoadReeferSubform.swift`

- ✗ Zero of 12 verticals modeled in Swift — no `Vertical` enum
- ⚠ 31 equipment display strings but no canonical trailer codes
- ⚠ Equipment list hardcoded per mode, not filtered by vertical
- ⚠ Hazmat / reefer subforms triggered only by `cargoType`, not by equipment type
- ✗ No hero animation file binding referenced
- **Critical**: server round-trip relies on canonical codes; iOS sends display strings — breaks server parity

### 2. Step 1 / 3 / 4 wizard — 50%
**Files:** `250_PostLoadStep1Lane.swift`, `252_PostLoadStep3Pricing.swift`, `253_PostLoadStep4Review.swift`, `255_PostLoadMultiStop.swift`

- ✗ Step 1: no mode picker (truck/rail/vessel) — locked to `.truck`
- ✗ Step 1: no country picker — locked to `.US` (cross-border can't post)
- ✗ Step 1: multi-stop button links to address picker, not multi-stop builder
- ✗ Step 3: no vertical-aware surcharges (hazmat, reefer, livestock 28hr, heavy haul permits)
- ✗ Step 3: no cross-border surcharge
- ⚠ Step 3: FSC is freeform %, not bound to FSC schedules
- ✗ Step 4: no per-vertical documents card
- ✗ Step 4: no ePOD lock initialization
- ✗ Step 4: no multi-vehicle review card for convoy/heavy-haul
- ⚠ Step 4: no confirmation gate before POSTED state

### 3. Agreement Wizard 223A — 5%
**File:** `223A_AgreementWizard.swift`

- ✗ Generates contract text via ESANG AI but receives no `vertical` parameter
- ✗ Zero per-vertical document mapping — all 13 document suites missing
- ✗ No trailer-code keying
- ⚠ Signature is base64 PNG only — no Ed25519 cryptographic signing
- ✗ No hash chaining (parent `hashChainAnchor` exists but not wired to agreement)
- ✗ No ePOD lock binding

### 4. Load-cycle FSM — 65%
**Files:** `Shipment.swift` (lines 339–418), `EusoTripAPI.swift` (LoadLifecycleAPI, lines 11151–11301)

- ✓ Strong server-driven FSM with role-gated transitions
- ✓ 13/13 base states present (with UNLOADED + SETTLED gaps in derivation)
- ✓ Identity verification model (Vehicle.identityChain)
- ✓ Hash chain anchor on parent
- ✗ **Zero overlay state enums** — all hazmat / reefer / livestock / heavy-haul / cross-border / AV-handoff overlays deferred to server-side strings
- ✗ No `Vertical` enum
- ✗ Hash validation not performed on iOS (server-side only)
- ⚠ Customs filing model present but no driver UI

### 5. Animation binding — 60%
**Files:** `EquipmentAnimation.swift`, `BindableEquipmentAnimation.swift`, `LoadAnimationContext.swift`, `ConvoyAnimationStrip.swift`

- ✓ 34 hero animation SVGs bundled (single-state)
- ✗ Zero Loading + Unloading state-variant SVGs bundled (68 missing)
- ✗ 6 of 23 trailer codes unmapped in `EquipmentKind`: livestock, log_trailer, pneumatic, end_dump, water_tank, curtain_side
- ⚠ Runtime binding: 10/14 canonical fields present; region decals + vertical badges missing
- ✗ No `AnimationService.swift` — binding decentralized across 4 files

### 6. Driver / Catalyst / Broker equipment-awareness — 25%
**Files:** `LifecycleProductContext.swift`, `PretripDVIRViewModel.swift`, `DeliveryPODCaptureView.swift`, `304_CatalystFleetDrivers.swift`, `704_DispatchHOSAlerts.swift`, `402_BrokerTenderDetail.swift`

- ✓ Pre-haul checklist: 6/12 verticals (hazmat, reefer, flatbed, container, railIntermodal, vesselContainer)
- ✗ Pre-trip DVIR: generic FMCSA only — 0/12 equipment-keyed
- ✗ POD capture: generic — no reefer temp log, livestock 28hr, hazmat segregation photos
- ✗ Loading animation: tanker-specific only (1/12)
- ✗ Unloading animation: generic (0/12)
- ✗ Catalyst driver-availability filter: endorsements display-only, no upstream query
- ✗ ELD HoS overlay: generic 14hr only — no livestock 28hr law override
- ✗ Multi-vehicle convoy composer: missing entirely
- ✗ Broker rate sheet: no equipment-keyed multipliers

### 7. Settlement + compliance routing — 12%
**Files:** `EusoWalletManager.swift`, `CommissionEngine.swift`, `HazmatDataUIIntegration.swift`

- ⚠ Fee engine: BASE only present (5/8/10/12% by load type); missing COUNTRY × VERTICAL × PRODUCT × DISTANCE × CYCLE × HAZMAT (parametric)
- ✗ ePOD lock engine: not present
- ✗ AP/AR vertical routing: single flat distribution
- ✗ Per-vertical compliance: 1 of 12 (hazmat only) — 11 missing
- ✗ Cross-border customs (ACE/CARM/SAT): not present in iOS
- ✗ OS/OW permit lookup: not present
- ✗ FSMA / USDA / FDA / 28hr compliance: not present

### 8. Cross-track parity (truck/rail/vessel) — 50%
**Files:** `MultiModalCore.swift`, `RailLane.swift`, `204_ShipperPostLoad.swift`

- ✓ TransportMode enum + Port directory (50 ports) + VesselClass (30+ types)
- ✓ Rail atlas: ClassIRailroad + 37 metros + 30 lanes + interchange registry
- ✓ Equipment enum: 35 choices (12 truck, 12 rail, 7 vessel)
- ✗ No `EquipmentEquivalency` map (truck trailer → rail car → vessel class)
- ✗ Rail yard lookup service missing (port equivalent for rail)
- ✗ Rail-specific FSM states missing (yard placement, interchange transfer, customs release, waybill filed)
- ✗ Vessel-specific FSM states missing (gate-in, load-plan, stow-plan, departure, in-transit, arrival, discharge, customs-clearance)
- ✗ Mode-aware services: rail/vessel routing missing
- ✗ Identifier UI: reporting marks, BIC, ISO, IMO, MMSI all defined in model but no input forms

---

## Recurring root-cause pattern

Every gap traces back to **one missing layer**: a Swift type system that **declares the canonical inventory once** and **forces every downstream feature to conform to it**. Today the inventory exists only as the markdown doc and the production wizard screenshots — iOS code has no compile-time check that says "if you reference a vertical, it must be one of these 12."

**Fix:** ship `02_Vertical.swift`, `03_TrailerCode.swift`, `04_LoadStateFSM.swift`, `05_EquipmentEquivalency.swift`, `06_DocumentRequirements.swift`, `07_FeeMultiplierEngine.swift`, `08_AnimationBindingMap.swift` as the canonical foundation. Refactor every audit-finding file to consume these enums/tables. Once shipped, **drift becomes impossible** — a typo in a vertical code is a compile error, a missing document requirement is a missing case in the switch.

This is the lock-in layer. The fix tickets in `09_PARITY_FIX_TICKETS.md` reference these foundation files for every gap.
