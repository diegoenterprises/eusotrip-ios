//
//  231_ShipperPushNotificationLanding.swift
//  EusoTrip 2027 UI — Shipper · Push Notification Landing (parity-shipped 2026-04-29)
//
//  WIREFRAME-CANON SHIP — new file at slot 231 mirroring
//  /02 Shipper/Code/231_ShipperPushNotificationLanding.swift verbatim.
//  Persona: Diego Usoro / Eusorone Technologies (companyId 1) per §11.
//  Active push anchors §11.4 row 3 (LD-260427-B41782FF02 · KC → Omaha
//  · MC-331 NH₃ UN1005 · Michael Eusorone driver).
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · PUSH / "1 OF 7 · 09:42 EDT"
//    2. Title block      Notification / "Routed from your iOS lock-screen
//                        tap · Eusorone Technologies"
//    3. IridescentHairline
//    4. ACTIVE PUSH      hero card — gradient category pill + headline +
//                        load id + lane + driver sub + timestamp eyebrow
//                        + Open-CTA gradient capsule
//    5. ROUTING          7-category card with active row gradient wash
//    6. Settings pointer "Manage push categories → 211 Settings · 3 prefs"
//    7. Footer           "companyId 1 · Eusorone Technologies ·
//                        MATRIX-50-2026-04-26"
//
//  Real wiring: iOS doesn't yet have a `ShipperPushAPI.currentPush()`
//  endpoint; the surface paints §11.4 row 3 anchor data with
//  EUSO-2150 backend gap.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2150 — `notifications.listRecent` + `getRecentPushes` not
//                yet on iOS API surface. Hero card uses canonical
//                §11.4 anchor data (KC → Omaha NH₃ hazmat exception).
//                When backend ships the push envelope, the active
//                push hydrates from the latest unread row and the
//                routing card lights the matching category.
//
//  Doctrine refs: §2 ME-tab nav (handled by ContentView); §3
//  numbers-first copy ("1 OF 7 · 09:42 EDT" / "38s ago" / "280 ft");
//  §4.3 single iridescent hairline; §11 / §11.2 / §11.4 Diego canon
//  + UN1005 + Michael Eusorone driver canon; §17.2 / §19.2 file-
//  scoped CategoryPill / RoutingRow / GradientCapsuleCTA helpers;
//  §20.4 no dead buttons; §22.2 textTertiary informational counter;
//  §35.3 Arc L iOS-platform integration surface.
//

import SwiftUI

// MARK: - Domain models

private struct ActivePush {
    let id:               String
    let categoryId:       String
    let categoryLabel:    String
    let headline:         String
    let loadId:           String
    let lane:             String
    let driverSub:        String
    let timestampEyebrow: String
    let ctaLabel:         String
    let targetScreen:     String
}

private struct PushCategory: Identifiable {
    let id:           String
    let title:        String
    let targetScreen: String
}

// MARK: - Screen root

struct ShipperPushNotificationLanding: View {
    @Environment(\.palette) private var palette

    // §11 Diego canon — push position + timestamp identification eyebrow.
    private let counterEyebrow = "1 OF 7 · 09:42 EDT"

    private let activeCategoryId = "hazmat_exception"

    private let activePush = ActivePush(
        id:               "push_2026-04-28T09:42:14Z_LD-260427-B41782FF02",
        categoryId:       "hazmat_exception",
        categoryLabel:    "HAZMAT EXCEPTION · UN1005",
        headline:         "GPS escort divergence",
        loadId:           "LD-260427-B41782FF02",
        lane:             "Kansas City MO → Omaha NE · MC-331 NH₃",
        driverSub:        "Driver Michael Eusorone · 280 ft drift from approved route",
        timestampEyebrow: "Pushed 09:42:14 EDT · 38s ago · routes to 212 Control Tower",
        ctaLabel:         "Open in Control Tower →",
        targetScreen:     "212 Control Tower"
    )

    private let categories: [PushCategory] = [
        PushCategory(id: "bid_received",
                     title: "Bid received",
                     targetScreen: "→ 205 Load Detail"),
        PushCategory(id: "lifecycle_stage_advance",
                     title: "Lifecycle stage advance",
                     targetScreen: "→ 205 Load Detail"),
        PushCategory(id: "hazmat_exception",
                     title: "Hazmat exception alert",
                     targetScreen: "→ 212 Control Tower · ACTIVE"),
        PushCategory(id: "detention_exception",
                     title: "Detention exception",
                     targetScreen: "→ 212 Control Tower"),
        PushCategory(id: "late_pickup",
                     title: "Late pickup risk",
                     targetScreen: "→ 205 Load Detail"),
        PushCategory(id: "late_delivery",
                     title: "Late delivery risk",
                     targetScreen: "→ 205 Load Detail"),
        PushCategory(id: "late_paperwork",
                     title: "Late paperwork",
                     targetScreen: "→ 229 BOL Upload")
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                titleBlock
                    .padding(.top, Space.s2)
                IridescentHairline()
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s5)

                sectionLabel("ACTIVE PUSH · 38s AGO")
                    .padding(.top, Space.s4)
                heroCard
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s2)

                sectionLabel("ROUTING · 7 CATEGORIES")
                    .padding(.top, Space.s5)
                routingCard
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s2)

                settingsPointerLink
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s5)

                footer
                    .padding(.top, Space.s4)
                    .padding(.bottom, Space.s8)
            }
        }
    }

    // MARK: TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · PUSH")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .accessibilityLabel("Push 1 of 7, received at 9:42 a.m. Eastern.")
        }
        .padding(.horizontal, Space.s5)
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notification")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Routed from your iOS lock-screen tap · Eusorone Technologies")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(EType.micro)
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s5)
    }

    // MARK: Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            CategoryPill(label: activePush.categoryLabel)
                .padding(.top, 18)
                .padding(.leading, 20)

            Text(activePush.headline)
                .font(.system(size: 17, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 14)
                .padding(.leading, 20)

            Text(activePush.loadId)
                .font(EType.mono(.caption))
                .tracking(0.4)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 4)
                .padding(.leading, 20)

            Text(activePush.lane)
                .font(.system(size: 12))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 4)
                .padding(.leading, 20)

            Text(activePush.driverSub)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 4)
                .padding(.leading, 20)

            Text(activePush.timestampEyebrow)
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 4)
                .padding(.leading, 20)

            Button(action: tapOpenTarget) {
                GradientCapsuleCTA(label: activePush.ctaLabel)
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .accessibilityLabel("Open this push in \(activePush.targetScreen)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Routing card

    private var routingCard: some View {
        VStack(spacing: 0) {
            ForEach(categories.indices, id: \.self) { idx in
                RoutingRow(
                    category: categories[idx],
                    isActive: categories[idx].id == activeCategoryId,
                    onTap:    { tapRouteRow(categories[idx]) }
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                if idx < categories.count - 1 {
                    Rectangle()
                        .fill(palette.borderFaint)
                        .frame(height: 1)
                        .padding(.horizontal, 20)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Settings pointer

    private var settingsPointerLink: some View {
        Button(action: tapManagePrefs) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manage push categories")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Notification toggles live in 211 Settings · 3 prefs")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("→")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Manage push categories. Notification toggles live in 211 Settings.")
    }

    // MARK: Footer

    private var footer: some View {
        Text("companyId 1 · Eusorone Technologies · MATRIX-50-2026-04-26")
            .font(.system(size: 10))
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, Space.s5)
    }

    // MARK: Notification posts (§20.4)

    private func tapOpenTarget() {
        NotificationCenter.default.post(
            name: .eusoShipperPushOpenTarget,
            object: nil,
            userInfo: [
                "source": "231_ShipperPushNotificationLanding",
                "pushId": activePush.id,
                "loadId": activePush.loadId,
                "categoryId": activePush.categoryId,
                "targetScreen": activePush.targetScreen,
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapRouteRow(_ category: PushCategory) {
        NotificationCenter.default.post(
            name: .eusoShipperPushRouteRow,
            object: nil,
            userInfo: [
                "source": "231_ShipperPushNotificationLanding",
                "categoryId": category.id,
                "targetScreen": category.targetScreen,
                "isActiveCategory": category.id == activeCategoryId,
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapManagePrefs() {
        NotificationCenter.default.post(
            name: .eusoShipperPushManagePrefs,
            object: nil,
            userInfo: [
                "source": "231_ShipperPushNotificationLanding",
                "targetScreen": "211 Settings",
                "shipperCompanyId": 1
            ]
        )
    }
}

// MARK: - CategoryPill (180×20 gradient capsule)

private struct CategoryPill: View {
    let label: String
    var body: some View {
        ZStack {
            Capsule().fill(LinearGradient.primary)
            Text(label)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
        }
        .frame(width: 200, height: 22)
        .accessibilityLabel(label)
    }
}

// MARK: - GradientCapsuleCTA

private struct GradientCapsuleCTA: View {
    let label: String
    var body: some View {
        ZStack {
            Capsule().fill(LinearGradient.primary)
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
    }
}

// MARK: - RoutingRow

private struct RoutingRow: View {
    @Environment(\.palette) var palette
    let category: PushCategory
    let isActive: Bool
    let onTap:    () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .leading) {
                if isActive {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient.primary.opacity(0.12))
                        .padding(.horizontal, -12)
                        .padding(.vertical, -4)
                    Circle()
                        .fill(LinearGradient.primary)
                        .frame(width: 6, height: 6)
                        .offset(x: -16)
                }
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text(category.targetScreen)
                            .font(EType.mono(.caption))
                            .tracking(0.4)
                            .foregroundStyle(
                                isActive
                                    ? AnyShapeStyle(LinearGradient.primary)
                                    : AnyShapeStyle(palette.textSecondary)
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("→")
                        .font(.system(size: 11, weight: isActive ? .bold : .semibold))
                        .foregroundStyle(
                            isActive
                                ? AnyShapeStyle(LinearGradient.primary)
                                : AnyShapeStyle(palette.textSecondary)
                        )
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            isActive
                ? "\(category.title), \(category.targetScreen), active push category."
                : "\(category.title), routes \(category.targetScreen)."
        )
    }
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    static let eusoShipperPushOpenTarget   = Notification.Name("eusoShipperPushOpenTarget")
    static let eusoShipperPushRouteRow     = Notification.Name("eusoShipperPushRouteRow")
    static let eusoShipperPushManagePrefs  = Notification.Name("eusoShipperPushManagePrefs")
}

// MARK: - Previews

#Preview("231 · Push Landing · Dark") {
    ShipperPushNotificationLanding()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("231 · Push Landing · Light") {
    ShipperPushNotificationLanding()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
