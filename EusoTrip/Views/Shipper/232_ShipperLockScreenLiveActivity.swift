//
//  232_ShipperLockScreenLiveActivity.swift
//  EusoTrip 2027 UI — Shipper · Lock Screen Live Activity (parity-shipped 2026-04-29)
//
//  WIREFRAME-CANON SHIP — new file at slot 232 mirroring
//  /02 Shipper/Code/232_ShipperLockScreenLiveActivity.swift. Persona:
//  Diego Usoro / Eusorone Technologies (companyId 1) per §11.
//  Active activity anchors §11.4 row 3 (LD-260427-B41782FF02 · KC →
//  Omaha · MC-331 NH₃ UN1005 · Michael Eusorone driver).
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · LIVE / "STAGE 5 OF 8 · 38m AGO"
//    2. Title block      Lock screen / "Live Activity preview · Eusorone Technologies"
//    3. IridescentHairline
//    4. DYNAMIC ISLAND   compact + expanded pill mocks
//    5. LOCK SCREEN      Live Activity card with persona, lane, equipment,
//                        driver, 8-stage lifecycle strip, 4-cell stat strip,
//                        Open CTA
//    6. Settings pointer "Manage Live Activity surfaces → 211 Settings"
//    7. Footer           "companyId 1 · Eusorone Technologies ·
//                        MATRIX-50-2026-04-26"
//
//  Real wiring: ActivityKit not yet wired on iOS. Preview surface
//  paints §11.4 row 3 anchor data with EUSO-2151 backend gap.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2151 — `liveActivities.currentForLoad(loadId:)` not yet
//                on iOS API surface, and ActivityKit registration
//                via `ShipperLiveActivityAPI` not yet implemented.
//                Surface uses §11.4 row 3 anchor data until backend
//                ships the live-activity envelope.
//
//  Doctrine refs: §2 ME-tab nav (handled by ContentView); §3
//  numbers-first copy ("STAGE 5 OF 8 · 38m AGO"); §4.3 single
//  iridescent hairline; §11 / §11.2 / §11.4 Diego canon + UN1005;
//  §17.2 / §19.2 file-scoped helpers; §20.4 no dead buttons; §22.2
//  textTertiary informational counter; §35.3 Arc L iOS-platform
//  integration surface.
//

import SwiftUI

// MARK: - Domain models

private struct StatValue {
    let value: String
    let sub: String
    let highlighted: Bool
}

private struct DynamicIslandContent {
    enum Kind { case compact, expanded }
    let kind: Kind
    let primary: String
    let sub: String
    let etaPrimary: String?
    let etaSub: String?

    init(kind: Kind, primary: String, sub: String,
         etaPrimary: String? = nil, etaSub: String? = nil) {
        self.kind = kind
        self.primary = primary
        self.sub = sub
        self.etaPrimary = etaPrimary
        self.etaSub = etaSub
    }
}

private struct LockScreenActivity {
    let id: String
    let loadId: String
    let persona: String
    let lane: String
    let equipmentLine: String
    let driverLine: String
    let stageIndex: Int
    let stageKicker: String
    let relativeAgo: String
    let liveLabel: String
    let eta: StatValue
    let distance: StatValue
    let speed: StatValue
    let geofence: StatValue
    let compactPill: DynamicIslandContent
    let expandedPill: DynamicIslandContent
    let ctaLabel: String
    let ctaTargetScreen: String
}

// MARK: - Screen root

struct ShipperLockScreenLiveActivity: View {
    @Environment(\.palette) private var palette

    private let counterEyebrow = "STAGE 5 OF 8 · 38m AGO"

    private let stageLabels: [String] = [
        "POSTED", "BIDDING", "AWARDED", "PICKUP",
        "IN TRANSIT", "DELIVERY", "PAPERWORK", "CLOSED"
    ]

    private let activity = LockScreenActivity(
        id: "act_2026-04-28T13:42:00Z_LD-260427-B41782FF02",
        loadId: "LD-260427-B41782FF02",
        persona: "Eusorone Technologies",
        lane: "Kansas City MO → Omaha NE",
        equipmentLine: "MC-331 anhydrous-ammonia · UN1005 escort active",
        driverLine: "Driver Michael Eusorone · 280 ft drift cleared 12m ago",
        stageIndex: 4,
        stageKicker: "Stage 5 — In transit · advanced 38m ago",
        relativeAgo: "38m ago",
        liveLabel: "LIVE · IN TRANSIT · STAGE 5/8",
        eta: StatValue(value: "14:18", sub: "in 4h 36m", highlighted: false),
        distance: StatValue(value: "178 mi", sub: "of 198", highlighted: false),
        speed: StatValue(value: "62 mph", sub: "62 limit", highlighted: false),
        geofence: StatValue(value: "OK", sub: "cleared", highlighted: true),
        compactPill: DynamicIslandContent(kind: .compact,
                                           primary: "UN1005",
                                           sub: "4h 36m"),
        expandedPill: DynamicIslandContent(kind: .expanded,
                                            primary: "UN1005 · NH₃",
                                            sub: "LD-260427-B41782FF02",
                                            etaPrimary: "4h 36m",
                                            etaSub: "→ Omaha NE"),
        ctaLabel: "Open in 205 Load Detail →",
        ctaTargetScreen: "205 Load Detail"
    )

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

                sectionLabel("DYNAMIC ISLAND · COMPACT + EXPANDED")
                    .padding(.top, Space.s4)
                dynamicIslandCard
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s2)

                sectionLabel("LOCK SCREEN · LIVE ACTIVITY")
                    .padding(.top, Space.s5)
                lockScreenCard
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
            Text("✦ SHIPPER · LIVE")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s5)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Lock screen")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Live Activity preview · Eusorone Technologies")
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

    // MARK: Dynamic Island card

    private var dynamicIslandCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("COMPACT · 124×30")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 16)
                .padding(.leading, 20)
            DynamicIslandPill(content: activity.compactPill)
                .padding(.top, 4)
                .padding(.leading, 20)

            Text("EXPANDED · 360×40")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 14)
                .padding(.leading, 20)
            DynamicIslandPill(content: activity.expandedPill)
                .padding(.top, 4)
                .padding(.leading, 20)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Lock screen card

    private var lockScreenCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                GradientLivePill(label: activity.liveLabel)
                Spacer(minLength: 0)
                Text(activity.relativeAgo)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                    .monospacedDigit()
            }
            .padding(.top, 18)
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(activity.persona)
                    .font(.system(size: 17, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(palette.textPrimary)
                Text(activity.loadId)
                    .font(EType.mono(.caption))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                Text(activity.lane)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, 2)
                Text(activity.equipmentLine)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                Text(activity.driverLine)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, 14)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)

            EightStageLifecycleMini(
                stageLabels: stageLabels,
                currentStageIndex: activity.stageIndex
            )
            .padding(.top, 16)

            Text(activity.stageKicker)
                .font(EType.mono(.caption))
                .tracking(0.4)
                .foregroundStyle(LinearGradient.primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 10)

            HStack(alignment: .top, spacing: 0) {
                StatTileView(eyebrow: "ETA", value: activity.eta)
                StatTileView(eyebrow: "DISTANCE", value: activity.distance)
                StatTileView(eyebrow: "SPEED", value: activity.speed)
                StatTileView(eyebrow: "GEOFENCE", value: activity.geofence)
            }
            .padding(.top, 14)
            .padding(.horizontal, 20)

            Button(action: tapOpenTarget) {
                ZStack {
                    Capsule().fill(LinearGradient.primary)
                    Text(activity.ctaLabel)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 28)
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .accessibilityLabel("Open this Live Activity in \(activity.ctaTargetScreen)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Settings pointer

    private var settingsPointerLink: some View {
        Button(action: tapManageSurfaces) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manage Live Activity surfaces")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Lock-screen + Dynamic Island toggles · 211 Settings")
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
    }

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
            name: .eusoShipperLiveActivityOpenTarget,
            object: nil,
            userInfo: [
                "source": "232_ShipperLockScreenLiveActivity",
                "activityId": activity.id,
                "loadId": activity.loadId,
                "stageIndex": activity.stageIndex,
                "targetScreen": activity.ctaTargetScreen,
                "shipperCompanyId": 1
            ]
        )
    }

    private func tapManageSurfaces() {
        NotificationCenter.default.post(
            name: .eusoShipperLiveActivityManageSurfaces,
            object: nil,
            userInfo: [
                "source": "232_ShipperLockScreenLiveActivity",
                "targetScreen": "211 Settings",
                "shipperCompanyId": 1
            ]
        )
    }
}

// MARK: - GradientLivePill

private struct GradientLivePill: View {
    let label: String
    var body: some View {
        ZStack {
            Capsule().fill(LinearGradient.primary)
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.30)).frame(width: 12, height: 12)
                    Circle().fill(Color.white).frame(width: 7, height: 7)
                }
                Text(label)
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .padding(.horizontal, 8)
        }
        .frame(width: 240, height: 22)
    }
}

// MARK: - DynamicIslandPill

private struct DynamicIslandPill: View {
    let content: DynamicIslandContent

    var body: some View {
        switch content.kind {
        case .compact:
            ZStack(alignment: .leading) {
                Capsule().fill(Color(red: 0.043, green: 0.043, blue: 0.062))
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient.primary.opacity(0.30))
                            .frame(width: 12, height: 12)
                        Circle()
                            .fill(LinearGradient.primary)
                            .frame(width: 8, height: 8)
                    }
                    Text(content.primary)
                        .font(EType.mono(.caption))
                        .tracking(0.3)
                        .foregroundStyle(.white)
                    Text(content.sub)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .monospacedDigit()
                }
                .padding(.horizontal, 8)
            }
            .frame(width: 160, height: 30)

        case .expanded:
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(red: 0.043, green: 0.043, blue: 0.062))
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient.primary.opacity(0.30))
                            .frame(width: 16, height: 16)
                        Circle()
                            .fill(LinearGradient.primary)
                            .frame(width: 10, height: 10)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(content.primary)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                        Text(content.sub)
                            .font(EType.mono(.caption))
                            .tracking(0.3)
                            .foregroundStyle(Color.white.opacity(0.62))
                    }
                    Spacer(minLength: 0)
                    if let etaPrimary = content.etaPrimary, let etaSub = content.etaSub {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(etaPrimary)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                            Text(etaSub)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.62))
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
    }
}

// MARK: - 8-stage lifecycle mini

private struct EightStageLifecycleMini: View {
    @Environment(\.palette) var palette
    let stageLabels: [String]
    let currentStageIndex: Int

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let w = geo.size.width
                let count = stageLabels.count
                let stride = w / CGFloat(count - 1)

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(palette.borderFaint)
                        .frame(width: w, height: 2)
                    Rectangle()
                        .fill(LinearGradient.primary)
                        .frame(width: stride * CGFloat(currentStageIndex), height: 2)
                    ForEach(0..<count, id: \.self) { i in
                        let isActive = i == currentStageIndex
                        let isCompleted = i < currentStageIndex
                        Circle()
                            .fill(isCompleted || isActive
                                  ? AnyShapeStyle(LinearGradient.diagonal)
                                  : AnyShapeStyle(palette.borderFaint))
                            .frame(width: isActive ? 9 : 7, height: isActive ? 9 : 7)
                            .offset(x: stride * CGFloat(i) - (isActive ? 4.5 : 3.5))
                    }
                }
            }
            .frame(height: 12)

            HStack(spacing: 0) {
                ForEach(0..<stageLabels.count, id: \.self) { idx in
                    Text(stageLabels[idx])
                        .font(.system(size: 7, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(stageLabelColor(forIndex: idx))
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func stageLabelColor(forIndex idx: Int) -> AnyShapeStyle {
        if idx == currentStageIndex {
            return AnyShapeStyle(LinearGradient.primary)
        } else if idx < currentStageIndex {
            return AnyShapeStyle(palette.textPrimary)
        } else {
            return AnyShapeStyle(palette.textTertiary)
        }
    }
}

// MARK: - StatTile

private struct StatTileView: View {
    @Environment(\.palette) var palette
    let eyebrow: String
    let value: StatValue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            if value.highlighted {
                Text(value.value)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(LinearGradient.primary)
                    .monospacedDigit()
            } else {
                Text(value.value)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
            }
            Text(value.sub)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    static let eusoShipperLiveActivityOpenTarget     = Notification.Name("eusoShipperLiveActivityOpenTarget")
    static let eusoShipperLiveActivityManageSurfaces = Notification.Name("eusoShipperLiveActivityManageSurfaces")
}

// MARK: - Previews

#Preview("232 · Lock Screen Live Activity · Dark") {
    ShipperLockScreenLiveActivity()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("232 · Lock Screen Live Activity · Light") {
    ShipperLockScreenLiveActivity()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
