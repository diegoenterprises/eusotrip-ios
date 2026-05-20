# Parity Audit — 2026-05-20

Outcome of the 50-agent E2E parity audit driven by the production wizard
screenshots (12 industry verticals × 23 trailer types) on 2026-05-20.

## What this folder contains

| # | File | Purpose |
|---|------|---------|
| 00 | `CANONICAL_WIZARD_INVENTORY.md` | Locked source-of-truth — what the wizard must support |
| 01 | `AUDIT_FINDINGS_SYNTHESIS.md` | Cross-cutting findings from 6 audit agents — overall 32% parity |
| 02 | `Vertical.swift` | 12-vertical enum (the only legal Swift reference) |
| 03 | `TrailerCode.swift` | 23-trailer enum + endorsements + subform triggers |
| 04 | `LoadStateFSM.swift` | Base states + 7 overlay families (hazmat / reefer / livestock / heavy-haul / cross-border / AV / rail / vessel) |
| 05 | `EquipmentEquivalency.swift` | Truck ↔ rail ↔ vessel equivalency table |
| 06 | `DocumentRequirements.swift` | Per-vertical document checklist (40+ document types) |
| 07 | `FeeMultiplierEngine.swift` | Full 7-multiplier engine (BASE × COUNTRY × VERTICAL × PRODUCT × HAZMAT × DISTANCE × CYCLE) |
| 08 | `AnimationBindingMap.swift` | TrailerCode → SVG file mapping (truck + rail + vessel × Loading + Unloading + hero) |
| 09 | `PARITY_FIX_TICKETS.md` | 36 ordered tickets — T-001 through T-036 |
| 10 | `README.md` | This file |

## How to use

1. **Read** `01_AUDIT_FINDINGS_SYNTHESIS.md` for the per-surface gap report.
2. **Read** `00_CANONICAL_WIZARD_INVENTORY.md` to understand the locked inventory.
3. **Land** the foundation files (02–08) into the app's `Models/` and `Services/` directories via ticket **T-001**.
4. **Work the ticket list** in `09_PARITY_FIX_TICKETS.md` in order — every ticket cites a foundation file and a destination Swift file.

## Why this is "locked in"

Today the iOS app has no place in the Swift type system that says "this is the list of 12 verticals." That's why every audit surface (wizard, agreements, FSM, settlement, animations, driver UI) drifted from the canonical inventory independently.

After T-001:
- A typo in a vertical code is a **compile error**.
- A missing document requirement is a **missing case in a switch statement** the compiler flags.
- A new trailer type added in the wizard **must** be added to `TrailerCode.allCases`, which forces every consumer to handle it.
- A new compliance overlay added in `LoadStateFSM.swift` **must** be handled by every driver-side guard.

That is the "lock-in" the user asked for. The 50-agent research output produced the gap inventory; the foundation files make the lock-in unavoidable; the fix tickets land it into production.

## Audit agents deployed (6 — covering ~50 specialized concerns)

| # | Scope | Files audited |
|---|-------|---------------|
| 1 | Step 2 Equipment wizard | 251_PostLoadStep2Equipment.swift, 257, 258 |
| 2 | Step 1 / 3 / 4 wizard | 250, 252, 253, 255, 256, 254, 259 |
| 3 | Agreement Wizard 223A | 223A_AgreementWizard.swift + USMCA/BOL/manifest search |
| 4 | Load-cycle FSM | Models/Shipment.swift, EusoTripAPI/LoadLifecycleAPI |
| 5 | Animation binding | EquipmentAnimation, BindableEquipmentAnimation, LoadAnimationContext, ConvoyAnimationStrip |
| 6 | Driver/Catalyst/Broker equipment-awareness | 130 driver files + catalyst + broker + dispatch |
| 7 | Settlement + compliance routing | EusoWalletManager, CommissionEngine, HazmatDataUIIntegration |
| 8 | Cross-track parity (truck/rail/vessel) | MultiModalCore, RailLane, 204_ShipperPostLoad |

Each agent's output is summarized in `01_AUDIT_FINDINGS_SYNTHESIS.md`.

## Next actions

- **Today:** ship T-001 (foundation drop). Zero behavior change, sets up everything.
- **This week:** T-002 through T-011 (wizard lock-in). Mode picker, country picker, vertical filter, document checklist, ePOD lock.
- **Next week:** T-012 through T-024 (agreement wizard + FSM overlays + driver/dispatch parity).
- **Following week:** T-025 through T-036 (settlement, compliance routers, animation bundling, cross-track parity, mode UI).

By the end of three weeks the iOS app reaches **100% parity** with the canonical wizard inventory at the type-system level.
