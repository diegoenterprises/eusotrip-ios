# EusoTrip — iOS

The native iOS surface of **Eusorone Technologies'** AI-driven multi-modal freight platform.

Built by Mike "Diego" Usoro / Eusorone Technologies, Inc.

## What this is

A SwiftUI app for iPhone, iPad, Apple Watch, and CarPlay that runs the full load lifecycle across **truck, rail, vessel, and barge** for **24 user roles**.

## Roles

**Truck (12)** — Shipper · Catalyst · Broker · Driver · Dispatch · Escort · Terminal Manager · Compliance Officer · Safety Manager · Factoring · Admin · Super Admin

**Rail (6)** — Rail Shipper · Rail Catalyst · Rail Dispatcher · Rail Engineer · Rail Conductor · Rail Broker

**Vessel (6)** — Vessel Shipper · Vessel Operator · Port Master · Ship Captain · Vessel Broker · Customs Broker

## Branded systems

- **ESANG AI** — voice + decision orchestration across every role surface
- **EusoTicket** — branded BOL / waybill / mate's-receipt documents per mode
- **EusoWallet** — payments, settlements, escrow, factoring
- **Zeun** — fleet maintenance, fuel, breakdown, mechanic network
- **The Haul** — gamification, missions, leaderboard, rewards

## Key flows

- **Post-a-Load wizard** (`204_ShipperPostLoad`) — Step-1 multi-modal picker, Step-2 industry-accurate gating (49 CFR 173 hazmat compatibility, state-overweight per federal 80k + 5 state overrides, reefer band validation, 49 CFR 177.848 segregation), Step-3 mode-native rate units (`$/mile`, `$/ton-mile`, Worldscale, `$/FEU`, `$/MT`)
- **Driver Ring-3 lifecycle** — 22 screens from Home (010) → Pretrip DVIR → Approaching Pickup → Loading → BOL Sign → En-route → Approaching Receiver → Discharge → Disconnect → Departing
- **EusoTicket renderer** — single canonical document shape with mode-aware variants
- **HERE Dynamic Map Content** — 8 HERE DMC products wired across truck routing, traffic, low-clearance, hazmat-routed corridors
- **NearbyInteraction (UWB)** — yardmap pairing, dock alignment, escort proximity, EusoTicket hand-off

## Web platform

This app pairs with the **[eusoronetechnologiesinc](https://github.com/diegoenterprises/eusoronetechnologiesinc)** web repo (React + TypeScript + Vite frontend, Express + tRPC backend, MySQL on Azure). Every endpoint the iOS app consumes is defined there.

## Build

Open `EusoTrip.xcodeproj` in Xcode 16+. Targets:
- `EusoTrip` (iOS 17+)
- `EusoTripWidget` (WidgetKit)
- `EusoTrip Watch App` (watchOS 10+)
- `EusoTripCarPlay` (CarPlay scene delegate inside main target)

Auto-bump script (`scripts/`) keeps CFBundleVersion in sync across all targets including embedded `*.appex` and `Watch/*.app` Info.plists.

---

© 2026 Eusorone Technologies, Inc. — all rights reserved.
