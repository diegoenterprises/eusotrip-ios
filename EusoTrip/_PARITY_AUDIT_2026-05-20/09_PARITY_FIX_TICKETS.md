# Parity Fix Tickets — file-level, ordered for safe rollout
**Date:** 2026-05-20
**Foundation:** 02–08 Swift files in this directory
**Rule:** every ticket lands one of the foundation files into a production file. Land tickets in order — later tickets depend on earlier ones.

---

## P0 — Foundation drop (LAND FIRST, no behavior change)

### T-001 · Drop canonical Swift foundation into Models/
**Move** these files from `_PARITY_AUDIT_2026-05-20/` into `EusoTrip/Models/`:
- `02_Vertical.swift`           → `Models/Vertical.swift`
- `03_TrailerCode.swift`        → `Models/TrailerCode.swift`
- `04_LoadStateFSM.swift`       → `Models/LoadStateFSM.swift`
- `05_EquipmentEquivalency.swift` → `Models/EquipmentEquivalency.swift`
- `06_DocumentRequirements.swift` → `Models/DocumentRequirements.swift`

And these into `EusoTrip/Services/`:
- `07_FeeMultiplierEngine.swift` → `Services/FeeMultiplierEngine.swift`
- `08_AnimationBindingMap.swift` → `Services/AnimationBindingMap.swift`

Add to `EusoTrip.xcodeproj` and `EusoTrip.xcconfig`. Compile-only — no behavior wired yet.

---

## P1 — Wizard Step 1 / 2 / 3 / 4 lock-in

### T-002 · Step 1 Lane — add Mode picker
**File:** `Views/Shipper/250_PostLoadStep1Lane.swift`
**Insert before line 65:**
```swift
Picker("Mode", selection: $draft.mode) {
    ForEach(TransportMode.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
}
.pickerStyle(.segmented)
```
**Bind:** `draft.mode` to `TransportMode` from `LoadStateFSM.swift`.
**Side effect:** Step 2 equipment list switches between truck/rail/vessel.

### T-003 · Step 1 Lane — add Origin/Destination country picker
**Same file**, after mode picker. Two `Picker` views for `originCountry` and `destinationCountry` of type `Country` (from `FeeMultiplierEngine.swift`). Compute `draft.isCrossBorder = origin != destination`. Surface USMCA badge if true.

### T-004 · Step 1 Lane — fix multi-stop button
**Same file, line 122:** change `screenId: "256"` → `screenId: "255"`.

### T-005 · Step 2 Equipment — replace display strings with `TrailerCode`
**File:** `Views/Shipper/251_PostLoadStep2Equipment.swift`
**Replace `equipmentChoices` (lines 23–44)** with:
```swift
private var equipmentChoices: [TrailerCode] {
    if let v = draft.vertical {
        return TrailerCode.filtered(by: v)
    }
    return TrailerCode.allCases
}
```
**Selection writes** `draft.trailer: TrailerCode` (NOT a String). Server payload sends `trailer.rawValue`.

### T-006 · Step 2 Equipment — add Vertical row
**Same file**, before the trailer grid:
```swift
ForEach(Vertical.allCases) { v in
    VerticalChip(vertical: v, isSelected: draft.vertical == v) { draft.vertical = v }
}
```

### T-007 · Step 2 Equipment — equipment-based hazmat/reefer subform triggers
**Same file**, lines 53–54:
```swift
if draft.trailer?.isHazmatEligible == true || draft.vertical == .hazmat {
    NavigationLink("Hazmat details") { PostLoadHazmatSubform(draft: $draft) }
}
if draft.trailer?.requiresReeferSubform == true || draft.vertical == .refrigerated {
    NavigationLink("Refrigeration details") { PostLoadReeferSubform(draft: $draft) }
}
```

### T-008 · Step 3 Pricing — wire `FeeMultiplierEngine`
**File:** `Views/Shipper/252_PostLoadStep3Pricing.swift`
**Insert** above the rate field:
```swift
let fee = FeeMultiplierEngine.compute(FeeComputationInput(
    baseRate: draft.baseRate,
    originCountry: draft.originCountry, destinationCountry: draft.destinationCountry,
    vertical: draft.vertical ?? .generalFreight, trailer: draft.trailer ?? .dryVan,
    mode: draft.mode, isHazmat: draft.isHazmat,
    distanceMiles: draft.distanceMiles, shipperPostingCycleDays: draft.cycleDays,
    isCrossBorder: draft.isCrossBorder,
))
RateSheetCard(breakdown: fee)
```
Replace the freeform FSC field with `Picker` bound to server `fscSchedules.list`.

### T-009 · Step 4 Review — render `DocumentRequirements`
**File:** `Views/Shipper/253_PostLoadStep4Review.swift`
**Insert** after the equipment card:
```swift
let required = DocumentRequirements.forShipment(
    vertical: draft.vertical ?? .generalFreight,
    isCrossBorder: draft.isCrossBorder
)
DocumentsRequiredCard(requirements: required, attached: draft.attachedDocuments)
```
Block `submit()` if any `blocking == true` document is not in `draft.attachedDocuments`.

### T-010 · Step 4 Review — confirmation gate
**Same file**, wrap `draft.submit()` in `.confirmationDialog("Post \(draft.id)?", ...) { Button("Post") { draft.submit() } }`.

### T-011 · Step 4 Review — ePOD lock initialization
**Same file**. When `draft.requiresEpodLock` (computed: `isCrossBorder || isHazmat || rateUsd > 5000 || vertical == .heavyHaulSpecialized`), set `draft.ePodLockEnabled = true` before submit. Pass to server.

---

## P2 — Agreement Wizard 223A lock-in

### T-012 · Agreement Wizard — accept Vertical + TrailerCode parameters
**File:** `Views/Shipper/223A_AgreementWizard.swift`
**Change** the `agreements.generate` mutation input (line 654) to include `vertical: Vertical.RawValue` and `trailer: TrailerCode.RawValue`. Pass them through.

### T-013 · Agreement Wizard — render `DocumentRequirements` per vertical
**Same file**, in Step 1 / Step 5 (Review):
```swift
let docs = DocumentRequirements.forShipment(vertical: vertical, isCrossBorder: isCrossBorder)
ForEach(docs, id: \.document) { DocRow(req: $0) }
```

### T-014 · Agreement Wizard — Ed25519 signing
**Same file**, replace the base64-PNG-only signature flow with:
1. Capture signature PNG (existing UX).
2. Compute SHA-256 of agreement-body + signaturePng + timestamp.
3. Sign with `Vehicle.identityChain`'s Ed25519 key (or platform key for shipper).
4. Send signature + signature-bytes + publicKey to server.
5. Server appends to `Shipment.hashChainAnchor`.

---

## P3 — Load-cycle FSM overlay states

### T-015 · Persist overlay states in Vehicle / Shipment models
**File:** `Models/Shipment.swift`
**Add** `overlayStates: CompositeLoadState` (from `LoadStateFSM.swift`) to `Vehicle`. Server schema must accept it. Decoding falls back to empty sets for legacy rows.

### T-016 · Driver lifecycle — gate transitions on overlays
**Files in `Views/Driver/`** that fire transitions (014, 016, 017, 020, 025, 030, …).
**For each call site of `loadLifecycle.executeTransition(...)`:** before the call, check `CompositeLoadState.requiredOverlays(vertical:, mode:, isCrossBorder:, isAvDispatch:)`. If any required overlay set is empty for a blocking transition, present the missing-overlay sheet to the driver and short-circuit.

### T-017 · Dispatch FSM badges — show overlay state in UI
**File:** `Views/Dispatch/708_DispatchKanbanBoard.swift`
**Replace** `multiVehicleCount` badge with a row of overlay chips:
```swift
ForEach(overlayChips(for: vehicle.compositeState)) { ChipView($0) }
```

---

## P4 — Driver / Catalyst / Broker parity

### T-018 · Pre-trip DVIR — accept TrailerCode
**File:** `ViewModels/PretripDVIRViewModel.swift`
**Change** `getTemplate(type:)` to `getTemplate(type:, trailer: TrailerCode)`. Server returns trailer-keyed checklist categories.

### T-019 · POD capture — equipment-specific fields
**File:** `Views/Driver/DeliveryPODCaptureView.swift`
**Conditionally render:**
- Reefer temp log download (`if trailer.requiresReeferSubform`)
- Livestock 28-hr attestation (`if vertical == .livestock`)
- Hazmat placard verification photo (`if trailer.isHazmatEligible`)
- Flatbed securement log (`if vertical == .flatbedOpenDeck`)

### T-020 · Loading animation — equipment-keyed views
**File:** `Views/Driver/030_LoadingInProgress.swift`
**Refactor** so the metric stack picks from a `LoadingMetricsViewBuilder.for(trailer:)` map. Add views for dry-van (weight gauge), flatbed (stack height), reefer (set/actual temp), livestock (animal count, 28-hr timer), auto-carrier (per-vehicle inspection).

### T-021 · Catalyst — endorsement filter
**File:** `Views/Catalyst/304_CatalystFleetDrivers.swift`
**Replace** display-only endorsement badges with a query filter:
```swift
let required = load.trailer.requiredEndorsements
let candidates = drivers.filter { required.isSubset(of: $0.endorsements) }
```

### T-022 · Dispatch HoS — livestock 28-hr law overlay
**File:** `Views/Dispatch/704_DispatchHOSAlerts.swift`
**Branch on `load.vertical == .livestock`:** render 28-hour rule instead of 14-hour. Pull from `LivestockOverlay.timer28hArmed`.

### T-023 · Multi-vehicle convoy composer
**New file:** `Views/Dispatch/710A_DispatchConvoyComposer.swift`
**Activate** when `load.vertical.typicallyMultiVehicle == true`. Composes parent shipment + N child vehicles + escort agreements.

### T-024 · Broker rate sheet — wire `FeeBreakdown`
**File:** `Views/Broker/402_BrokerTenderDetail.swift`
**Render** `FeeBreakdown.humanRateSheet` inline. Show each multiplier as a chip.

---

## P5 — Settlement + compliance routing

### T-025 · Refactor `CommissionEngine.swift` to delegate to `FeeMultiplierEngine`
**File:** `CommissionEngine.swift`
**Replace** the 4-rate switch with a single call to `FeeMultiplierEngine.compute(...)`. Keep the existing public surface for backwards-compatibility.

### T-026 · Wire ePOD lock engine
**New file:** `Services/EpodLockEngine.swift` (port the TypeScript impl from wiring stubs).
**Block** `eusoWallet.disburse(...)` if `epodLock.isLocked(shipmentId)`.

### T-027 · Per-vertical compliance routers
**New files in `Services/Compliance/`:**
- `HazmatComplianceRouter.swift` (ERG, placards, segregation)
- `ReeferComplianceRouter.swift` (FSMA, FDA, temp logs)
- `LivestockComplianceRouter.swift` (USDA, 28-hr law)
- `HeavyHaulComplianceRouter.swift` (OS/OW, escorts, route survey)
- `CrossBorderComplianceRouter.swift` (ACE / CARM / SAT)
Each router subscribes to FSM transitions and emits compliance prompts/warnings.

---

## P6 — Animation bundling

### T-028 · Bundle the 66 Loading + Unloading SVGs
**Action:** copy from `/EusoTrip Animation Design System/_DesignSystem/v3_perfected_animations/04_LoadingUnloading/` into `EusoTrip/Resources/Animations/Equipment/` (preserving 01_Truck / 02_Rail / 03_Vessel subdirs).

### T-029 · Wire `AnimationBindingMap`
**File:** `Services/EquipmentAnimation.swift`
**Replace** the existing hardcoded `svgFilename` mapping with:
```swift
public func file(for state: AnimationState) -> String? {
    let pair = AnimationBindingMap.files(for: equipment)
    switch state {
    case .loading:    return pair?.loading
    case .unloading:  return pair?.unloading
    case .hero:       return pair?.hero
    }
}
```

### T-030 · Add 6 missing trailer types to `EquipmentKind`
**File:** `Services/EquipmentAnimation.swift`
**Add cases** for livestock_cattle_pot, log_trailer, pneumatic_tank, end_dump, water_tank, curtain_side, then map each to its `AnimationBindingMap.truck` row.

---

## P7 — Cross-track parity

### T-031 · Wire `EquipmentEquivalency` to wizard mode switch
**File:** `Views/Shipper/250_PostLoadStep1Lane.swift`
**When `draft.mode` changes**, call `EquipmentEquivalency.equivalent(of: draft.equipment, in: draft.mode)` and auto-snap.

### T-032 · Rail yard lookup service
**New file:** `Services/RailYardLookup.swift`
Mirror `PortDirectory`: yards keyed by `Metro` from `RailLane.swift`.

### T-033 · Vessel class recommender
**New file:** `Services/VesselClassRecommender.swift`
Picks a `VesselClassKind` from cargo volume + commodity.

### T-034 · Rail + vessel identifier UI
**File:** `Views/Shipper/251_PostLoadStep2Equipment.swift`
**Conditionally render:**
- Rail mode → reporting marks + AAR class fields
- Vessel mode → BIC + ISO + IMO + MMSI fields

---

## P8 — Driver-side mode UI

### T-035 · Mode-specific lifecycle labels
**Files in `Views/Driver/`**
Replace "AT PICKUP DOCK" with `vehicle.mode.atPickupLabel`:
- truck → "AT PICKUP DOCK"
- rail  → "AT RAIL RAMP / YARD"
- vessel → "AT VESSEL GATE"

### T-036 · Mode-specific POD
- truck: existing POD
- rail: rail waybill signature + reporting marks photo
- vessel: BL signature + container seal verification

---

## Rollout sequence

1. **Day 1:** T-001 (drop foundation files, compile-only).
2. **Day 2-3:** T-002…T-007 (wizard Step 1/2 lock-in).
3. **Day 4:** T-008…T-011 (wizard Step 3/4 + ePOD).
4. **Day 5-6:** T-012…T-014 (agreement wizard + Ed25519).
5. **Day 7-9:** T-015…T-024 (FSM overlays + driver/dispatch/broker).
6. **Day 10-11:** T-025…T-027 (settlement + compliance routers).
7. **Day 12-13:** T-028…T-030 (animation bundle + binding map).
8. **Day 14-15:** T-031…T-034 (cross-track parity).
9. **Day 16-17:** T-035…T-036 (driver mode UI).

After T-036 the iOS app physically cannot drift from the canonical wizard inventory at the type system level.
