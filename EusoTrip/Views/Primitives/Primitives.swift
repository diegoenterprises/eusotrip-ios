//
//  Primitives.swift
//  EusoTrip — Primitive manifest (doctrine §6 Phase 1 #4).
//
//  This file is an INDEX, not an implementation. Primitives whose footprint
//  has been verified across 3+ shipped driver screens are documented here
//  with their canonical source-of-truth location and known call sites, so
//  future Phase 2-5 bricks reuse them instead of duplicating inline.
//
//  The primitives themselves live at their canonical locations listed
//  below — moving them would require an xcodebuild round-trip to verify
//  target membership, which the sandboxed audit pass cannot perform. When
//  the Phase-2 port wave starts, a primitive can be migrated into this
//  folder by: (a) cut its declaration, (b) paste it here in a new file,
//  (c) verify the file is included in the EusoTrip target, (d) delete the
//  old site. Until then, every primitive is module-internal and reachable
//  from any Views/ file without an import.
//
//  Call-site audit performed: 2026-04-23 (eusotrip-killers §6 Phase 1).
//

import SwiftUI

// MARK: - Primitive registry (documentation only)
//
// Each entry lists:
//   • Primitive name
//   • Canonical source file (where the struct is declared)
//   • Verified call sites (grep'd 2026-04-23)
//
// TODO(eusotrip-killers §6): when migrating a primitive into this folder,
// update its entry here with the new path so the manifest stays authoritative.
//
// ─────────────────────────────────────────────────────────────────────────
// ActiveCard<Content>
//   Canonical: EusoTrip/Theme/DesignSystem.swift (L1075)
//   Call sites:
//     010_DriverHome.swift, 012_DvirSubmitted.swift,
//     015_AtGateAwaitingDock.swift, 016_PickupLoading.swift,
//     017_PickupBolSigning.swift, 018_ActiveEnrouteLoaded.swift,
//     036_ESangSmartStop.swift,
//     DriverTabPanes.swift, MeDetailScreens.swift, MeNewsView.swift,
//     MeNotificationsView.swift, ProfileEditView.swift,
//     DriverConversationView.swift, ELDIntegrationView.swift,
//     HotZonesWidget.swift
//   Doctrine invariants:
//     • Diagonal gradient stroke (never flat Brand.blue)
//     • palette.bgCard fill — never Color.white / Color.black
//     • Brand blue + magenta dual-shadow at scheme-aware opacity
//
// ─────────────────────────────────────────────────────────────────────────
// MetricTile (with optional gradientNumeral)
//   Canonical: EusoTrip/Theme/DesignSystem.swift (L1104)
//   Call sites:
//     010_DriverHome.swift, 012_DvirSubmitted.swift,
//     036_ESangSmartStop.swift, 048_ArrivalGateTaskActive.swift (local var
//     shadow — uses its own inline struct; candidate for migration when
//     Phase 2 lands),
//     DriverTabPanes.swift, ELDIntegrationView.swift, HotZonesWidget.swift,
//     MeDetailScreens.swift, MeNotificationsView.swift
//   Doctrine invariants:
//     • `gradientNumeral: true` pipes the value through
//       `.foregroundStyle(LinearGradient.diagonal)` — never flat Brand.blue.
//     • Rail-aware: 20pt font w/ minimumScaleFactor(0.5) so 2-up/3-up/4-up
//       layouts all fit on narrow devices.
//
// ─────────────────────────────────────────────────────────────────────────
// StatusPill
//   Canonical: EusoTrip/Theme/DesignSystem.swift (L1143)
//   Call sites: 19+ screens — used anywhere a load/duty/compliance chip
//     needs a tint+color pair. Grep `StatusPill(` for the live list.
//   Doctrine invariants:
//     • Paints with Brand.* color + palette.tint* fill — ALWAYS paired
//       through the Kind enum so the semantic mapping stays one-to-one.
//     • For brand-accent pills (hot/primary CTA), use `EusoBadge(kind:.hot)`
//       instead — it carries the gradient fill variant.
//
// ─────────────────────────────────────────────────────────────────────────
// CTAButton
//   Canonical: EusoTrip/Theme/DesignSystem.swift (L1181)
//   Call sites: auth + many screens — the canonical full-width primary CTA.
//     For lifecycle-screen advance buttons that drive the trip state
//     machine, use `LifecycleCTAButton` (DriverNavController.swift L181)
//     instead — it reads `\.lifecycleAdvance` from the environment so
//     ContentView owns the advance closure.
//   Doctrine invariants:
//     • LinearGradient.primary fill with hueRotation press feedback.
//     • White title text (this is one of the sanctioned Color.white uses
//       — the text lives on top of a full-bleed gradient, so there's no
//       palette equivalent).
//     • Rounded rectangle (web-parity), never oval.
//
// ─────────────────────────────────────────────────────────────────────────
// WeatherCard
//   Canonical: EusoTrip/Views/Components/WeatherCard.swift
//   Call sites:
//     010_DriverHome.swift, DriverTabPanes.swift
//     (HERE-powered current-conditions surface; animated sky keyed to
//     time-of-day per Phase 2 brief).
//   Doctrine invariants:
//     • Pulls from `WeatherSnapshot` (services/WeatherStore when added).
//     • Time-of-day gradient — blue→orange→magenta sweep for golden hour,
//     blue→navy for night, etc. Never flat Brand.blue.
//
// ─────────────────────────────────────────────────────────────────────────
// LifecycleCTAButton
//   Canonical: EusoTrip/Views/Driver/DriverNavController.swift (L181)
//   Call sites: every lifecycle screen 010-053 that advances the trip.
//   Doctrine invariants:
//     • Reads `\.lifecycleAdvance` from the environment — never calls a
//       local `onTap` closure. ContentView owns the closure so the trip
//       state machine stays in a single place.
//     • Rendered with the CTAButton gradient treatment (same visual).
//
// ─────────────────────────────────────────────────────────────────────────
// EusoEmptyState
//   Canonical: EusoTrip/Theme/Components/EusoEmptyState.swift
//   Call sites: ~30 per mock_data_audit/patch_plan.md
//   Doctrine invariants:
//     • `comingSoon: true` shows the gradient orb + "Coming soon" treatment
//       for role tabs / unshipped surfaces.
//     • NEVER fake data — every MCP stub/gap renders this primitive.
//
// ─────────────────────────────────────────────────────────────────────────
//
// Primitives NOT yet promoted (flag for Phase 2 consolidation):
//   • 048_ArrivalGateTaskActive.swift defines a LOCAL `MetricTile` struct
//     (L141) that shadows the module MetricTile with a different API
//     (label/value/meta/isOk). Reconcile during Phase 2: rename to
//     `TaskMetricTile` or extend the canonical MetricTile with an
//     optional `meta` + `isOk` to absorb the shadow.
//
// ─────────────────────────────────────────────────────────────────────────
//
// Compilation guarantee:
// This file defines no types and adds no members — it is documentation
// with no runtime footprint. Safe to ship in every target configuration.
