# EusoTrip Post-Load Wizard — Dev Team Integration Brief
**Date:** 2026-05-20
**Founder:** Diego Usoro
**Scope:** Lock in 100% parity between iOS Post-Load Wizard + web LoadCreationWizard.tsx + canonical inventory. Zero gaps. App-version simplicity preserved.

---

## 1. Read these three sources of truth FIRST

Before touching any code, open:

1. **`EusoTrip/_PARITY_AUDIT_2026-05-20/00_CANONICAL_WIZARD_INVENTORY.md`**
   — the locked source-of-truth. 12 industry verticals, 23 trailer types (truck-side), cross-track equivalents, FSM overlay states, document requirements per vertical. **If your code references a vertical or trailer code that isn't in this doc, you're wrong and the doc is right.**

2. **`EusoTrip/_PARITY_AUDIT_2026-05-20/01_AUDIT_FINDINGS_SYNTHESIS.md`**
   — what 6 specialized audit agents found. Overall iOS parity vs canonical: **~32%**. Per-surface scores: Step 2 30%, Steps 1/3/4 50%, Agreement Wizard 5%, FSM 65%, Animation 60%, Driver/Catalyst/Broker 25%, Settlement+Compliance 12%, Cross-track 50%.

3. **`EusoTrip/_PARITY_AUDIT_2026-05-20/09_PARITY_FIX_TICKETS.md`**
   — 36 ordered tickets (T-001 → T-036), every one with file path, line number, code block, and acceptance criteria.

The canonical Swift foundation lives in the same folder (files 02–08). Land it first. Everything else depends on it.

---

## 2. What the parallel Claude session has already done (do not redo)

A separate engineering session has been making surgical edits to the **web** wizard. Status snapshot:

### ✅ DONE — iOS deprecation fixes
- `EusoTrip/Views/Shipper/313_EsangVoiceListening.swift`
  - `AVAudioSession.sharedInstance().requestRecordPermission` → `AVAudioApplication.requestRecordPermission` (iOS 17+)
  - `.allowBluetooth` → `.allowBluetoothHFP`

### ✅ DONE — Web wizard surgical pass 1 (LoadCreationWizard.tsx)
- Eliminated Step 1 / Step 2 redundancy (My Products merged into Industry & Trailer as a quick-pick header)
- Deleted dead standalone SPECTRA-MATCH step (`rs === 3`)
- Opened inline SPECTRA-MATCH collapsible to **all** hazmat tankers (not just ERG-verified)
- Step count: 9 → 7 active steps; file: 3,436 → 3,356 lines
- `activeStepIndices` filters now exclude indices 0 and 3
- TypeScript compiles clean (0 errors on that file)

### 🟡 IN-FLIGHT — Web wizard surgical pass 2 (LoadCreationWizard.tsx)
- Adding `TransportModeId` + `TRANSPORT_MODES` (truck / rail / vessel / barge) to `loadConstants.ts`
- Adding `mode` field to every `TRAILER_TYPES` row
- Expanding `TRAILER_TYPES` from ~24 truck-only rows to **45 rows** total (24 truck + 12 rail + 7 vessel + 3 barge)
- Adding 4-mode picker UI to Step 1 (Lane)
- Filtering the trailer grid by selected mode
- Extending `getClassesForTrailer()` and `TRAILER_COMMODITY_MAP` to cover new equipment

**Verify** `loadConstants.ts` looks like this when you pull:
- New exports: `TransportModeId`, `TRANSPORT_MODES` (4 entries with rateUnit)
- 45 entries in `TRAILER_TYPES`, each with a `mode` field
- `TRAILER_COMMODITY_MAP` covers all 45 ids
- `getClassesForTrailer` handles rail_tank_liquid, vessel_tanker, vessel_iso_tank, barge_tanker (liquid hazmat family) and rail_tank_gas, vessel_lng (gas hazmat family)

If any of those are missing, the in-flight pass didn't finish — pick it up before moving on.

---

## 3. Your assignment — finish the integration

The four-week rollout in `09_PARITY_FIX_TICKETS.md` is the source of truth. Work it in order. Highlights:

### Week 1 — Foundation drop (T-001 → T-011)

**T-001 · Drop canonical foundation into the iOS project**

Move files from `_PARITY_AUDIT_2026-05-20/` into the production Models/Services directories:

```
02_Vertical.swift            → EusoTrip/Models/Vertical.swift
03_TrailerCode.swift         → EusoTrip/Models/TrailerCode.swift
04_LoadStateFSM.swift        → EusoTrip/Models/LoadStateFSM.swift
05_EquipmentEquivalency.swift → EusoTrip/Models/EquipmentEquivalency.swift
06_DocumentRequirements.swift → EusoTrip/Models/DocumentRequirements.swift
07_FeeMultiplierEngine.swift → EusoTrip/Services/FeeMultiplierEngine.swift
08_AnimationBindingMap.swift → EusoTrip/Services/AnimationBindingMap.swift
```

Add to `EusoTrip.xcodeproj` (drag into Project Navigator → check EusoTrip target). Compile. Zero behavior change. **This must compile before any other ticket lands.**

**T-002 → T-011 · iOS wizard lock-in**

Per ticket. Wires Vertical enum, TrailerCode enum, FeeMultiplierEngine, DocumentRequirements, ePOD lock initialization into the four PostLoad Step views (250, 251, 252, 253). After these land, the iOS wizard physically cannot post a load that violates the canonical inventory.

### Week 2 — Agreement wizard + FSM overlays + driver/dispatch/broker (T-012 → T-024)

Highlights:
- T-014: Replace base64-PNG-only signature in `223A_AgreementWizard.swift` with Ed25519 cryptographic signing + hash chain entry.
- T-015 → T-017: Persist overlay states (Hazmat/Reefer/Livestock/HeavyHaul/CrossBorder/AvHandoff/Rail/Vessel) on Vehicle, gate driver transitions on them, render overlay chips in dispatch.
- T-018 → T-022: Equipment-keyed DVIR templates, equipment-specific POD capture (reefer temp log, livestock 28-hr attestation, hazmat placard photos, flatbed securement docs), driver-availability filter by endorsement, livestock 28-hr law HoS overlay.
- T-024: Wire `FeeBreakdown.humanRateSheet` into the broker tender detail.

### Week 3 — Settlement, compliance routers, animation, cross-track (T-025 → T-036)

- T-025: Refactor `CommissionEngine.swift` to delegate to `FeeMultiplierEngine`. Keep old public surface for backwards compatibility.
- T-026: Port `EpodLockEngine.ts` (from `_DesignSystem/wiring_stubs/server/`) into Swift. Block `eusoWallet.disburse(...)` when locked.
- T-027: Five new files under `Services/Compliance/` — HazmatComplianceRouter, ReeferComplianceRouter, LivestockComplianceRouter, HeavyHaulComplianceRouter, CrossBorderComplianceRouter. Each subscribes to FSM transitions and emits compliance prompts.
- T-028 → T-030: Bundle the 66 Loading + Unloading SVGs into `Resources/Animations/Equipment/`, wire `AnimationBindingMap` into `EquipmentAnimation.swift`, add 6 missing trailer types to `EquipmentKind`.
- T-031 → T-036: Cross-track parity (mode-switch auto-snap via `EquipmentEquivalency`, rail yard lookup, vessel class recommender, rail/vessel identifier UI on Step 2, driver-side mode-specific lifecycle labels and POD flows).

---

## 4. Web ↔ iOS round-trip contract (do not break)

Both clients submit to `loads.create` tRPC mutation. The server expects raw enum values from the canonical inventory:

| Field              | Type                            | Source                       |
|--------------------|---------------------------------|------------------------------|
| `vertical`         | `Vertical.rawValue`             | `Vertical.swift` / web enum  |
| `trailer`          | `TrailerCode.rawValue`          | `TrailerCode.swift` / web    |
| `mode`             | `TransportMode.rawValue`        | `LoadStateFSM.swift` / web   |
| `originCountry`    | `Country.rawValue`              | `FeeMultiplierEngine.swift`  |
| `destinationCountry`| `Country.rawValue`              | `FeeMultiplierEngine.swift`  |
| `isCrossBorder`    | `Bool` (origin != destination)  | computed                     |
| `isHazmat`         | `Bool`                          | from TrailerCode or vertical |
| `feeBreakdown`     | `FeeBreakdown` (7 multipliers)  | `FeeMultiplierEngine.swift`  |
| `attachedDocuments`| `[DocumentType.rawValue]`       | `DocumentRequirements.swift` |
| `ePodLockEnabled`  | `Bool`                          | computed                     |

**The web `loadConstants.ts` `TransportModeId` union and the `mode` field on `TRAILER_TYPES` MUST stay in lockstep with the iOS `TransportMode` enum and `TrailerCode`'s `defaultVertical` / `isHazmatEligible` properties.** Use the canonical inventory doc as the bridge.

When the parity tickets land, the server should reject any `vertical` or `trailer` value that isn't in the canonical enum. **Add a server-side validator that imports the same enum.** That's the third leg of lock-in (after iOS type system + web TypeScript union).

---

## 5. Acceptance checklist — definition of done

Before claiming an integration complete, verify each line:

### Step 2 (Equipment) — wizard parity
- [ ] All 12 verticals selectable on iOS AND web
- [ ] All 23 truck trailer codes selectable on iOS AND web
- [ ] All 12 rail equipment codes selectable on web (iOS already has via `EquipmentChoice`)
- [ ] All 7 vessel equipment codes selectable on web
- [ ] All 3 barge equipment codes selectable on web
- [ ] Selecting a hazmat-eligible trailer triggers hazmat subform (iOS + web)
- [ ] Selecting reefer or food-grade triggers reefer subform (iOS + web)
- [ ] Changing mode auto-snaps equipment via `EquipmentEquivalency` (iOS + web)

### Step 3 (Pricing) — fee engine parity
- [ ] `FeeMultiplierEngine.compute(...)` runs on iOS AND mirrors web ML rate card output within 1¢
- [ ] All 7 multipliers visible in rate-sheet UI: BASE × COUNTRY × VERTICAL × PRODUCT × HAZMAT × DISTANCE × CYCLE
- [ ] Catalyst Requirements section (min safety score + endorsement requirements) present on iOS Step 3 (gap-fill from web)

### Step 4 (Review) — document checklist parity
- [ ] `DocumentRequirements.forShipment(...)` drives the documents card on iOS AND web
- [ ] Blocking documents missing → submit button disabled
- [ ] Cross-border shipments append USMCA / pedimento / carta porte / RPP / ACE manifest
- [ ] ePOD lock initialized when isCrossBorder OR isHazmat OR rateUsd > 5000 OR vertical == heavyHaulSpecialized

### FSM
- [ ] Vehicle.overlayStates persisted (iOS + server)
- [ ] Driver transitions blocked when required overlay set is empty (HAZMAT.PLACARDS_AFFIXED before HAZMAT.LOADED, etc.)
- [ ] Dispatch kanban shows overlay chips (iOS)
- [ ] Hash chain entries written on every transition (server)

### Agreements
- [ ] Agreement Wizard 223A receives `vertical` + `trailer` parameters
- [ ] Per-vertical document checklist renders
- [ ] Ed25519 cryptographic signing replaces base64-PNG-only signature
- [ ] Signature byte-string + public key appended to hash chain

### Driver
- [ ] DVIR template keyed by `TrailerCode`
- [ ] POD capture conditionally renders reefer/livestock/hazmat/flatbed fields
- [ ] Loading animation branches on `EquipmentKind` (every trailer has a Loading + Unloading SVG)

### Catalyst / Dispatch / Broker
- [ ] Driver-availability filter applies `TrailerCode.requiredEndorsements` to query
- [ ] HoS overlay shows 28-hr law when vertical == livestock
- [ ] Multi-vehicle convoy composer present when vertical.typicallyMultiVehicle
- [ ] Broker rate sheet renders `FeeBreakdown.humanRateSheet`

### Settlement
- [ ] `CommissionEngine` delegates to `FeeMultiplierEngine`
- [ ] EpodLockEngine blocks disbursement when locked
- [ ] All five compliance routers present and subscribed to FSM transitions

### Animation
- [ ] 66 Loading + Unloading SVGs bundled in app resources
- [ ] `AnimationBindingMap.isComplete == true` at runtime (every TrailerCode has a binding)
- [ ] 6 missing trailers added to `EquipmentKind`: livestock_cattle_pot, log_trailer, pneumatic_tank, end_dump, water_tank, curtain_side

### Cross-track parity
- [ ] Mode picker on iOS Step 1 AND web Step 1
- [ ] Rail yard lookup service present (mirror of PortDirectory)
- [ ] Vessel class recommender present
- [ ] Rail mode shows reporting marks + AAR class fields on Step 2
- [ ] Vessel mode shows BIC + ISO + IMO + MMSI fields on Step 2
- [ ] Driver lifecycle labels switch by mode (truck "AT PICKUP DOCK" / rail "AT RAIL RAMP" / vessel "AT VESSEL GATE")

### Round-trip
- [ ] Same payload posted from iOS and web produces identical server state
- [ ] Server validator rejects unknown vertical / trailer values
- [ ] Schema migrations for new persisted fields documented and applied

---

## 6. Rollout strategy — keep production safe

The current web wizard has live shippers. **Do not rewrite in place.** Instead:

1. Create `LoadCreationWizardV2.tsx` alongside the existing file.
2. Route `/loads/create?v=2` to V2; `/loads/create` keeps V1.
3. A/B test V2 with 10% of shippers for 7 days; monitor:
   - `loads.create` mutation success rate
   - Time-to-post (median + p95)
   - Step abandonment rate per step
4. If V2 metrics meet or beat V1, flip the default to V2 and route the legacy path to V2.
5. Delete `LoadCreationWizard.tsx` (V1) after 30 days at 100% V2 traffic with no regressions.

iOS doesn't need the V1/V2 split because the existing wizard files (250–253) are already small and surgical — land tickets directly with feature flags on the new Vertical/TrailerCode bindings.

---

## 7. Communication contract

Open a single PR per ticket in `09_PARITY_FIX_TICKETS.md`. PR title = ticket ID + subject (e.g. `T-005: Step 2 Equipment — replace display strings with TrailerCode`). PR body must include:

- Ticket ID + acceptance criteria from the doc
- Files touched + line ranges
- Screenshots before/after (iOS surfaces) or screenshot + Lighthouse delta (web)
- Round-trip test result (post a sample load → verify server payload)

PR reviewer assignment:
- Foundation files (T-001) — founder review required
- Wizard tickets (T-002 → T-011) — at least one mobile-platform engineer
- FSM / overlay tickets (T-015 → T-017) — at least one backend engineer
- Compliance router tickets (T-027) — domain SME review (whoever owns hazmat / reefer / livestock compliance)

---

## 8. What "lock-in" means in practice

After T-036 lands:

- A typo in a vertical code is a **compile error** (iOS Swift type system + web TypeScript discriminated union).
- A missing document requirement is a **non-exhaustive switch warning** the compiler flags.
- A new trailer type added in the wizard **must** be added to `TrailerCode.allCases`, which forces every consumer (driver UI, dispatch filter, broker rate sheet, animation map, document requirements) to handle it.
- A new compliance overlay added in `LoadStateFSM.swift` **must** be handled by every driver-side guard.
- Server-side validator rejects any client payload that violates the canonical inventory.

The 50-agent audit research output produced the gap inventory. The foundation files (02–08) make the lock-in unavoidable. The fix tickets (T-001 → T-036) land it into production. After three weeks, drift between web, iOS, and the canonical inventory becomes physically impossible.

---

## 9. Questions / blockers

Ping the founder directly with the following if you hit one:

- Server schema doesn't accept a new field → coordinate a migration ticket
- A canonical enum value seems wrong (e.g., a trailer code missing from the screenshots) → STOP, get founder sign-off before editing the canonical doc; the canonical inventory is the contract
- A ticket dependency isn't satisfied (e.g., T-009 needs T-006 first) → respect the ordering in section 3
- A regulatory requirement is unclear (28-hr law, FSMA, USMCA, etc.) → flag for SME review; don't guess

---

## TL;DR for the team meeting

> "Founder shipped a canonical inventory + Swift foundation that makes parity drift between iOS + web + server impossible at the type system level once landed. 36 tickets in `09_PARITY_FIX_TICKETS.md` close every gap the 50-agent audit found. Three-week rollout. Read `00_CANONICAL_WIZARD_INVENTORY.md` and `09_PARITY_FIX_TICKETS.md` before writing a single line of code. Land T-001 first; everything else depends on it."
