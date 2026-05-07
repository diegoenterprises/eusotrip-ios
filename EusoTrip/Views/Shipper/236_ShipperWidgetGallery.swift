//
//  236_ShipperWidgetGallery.swift
//  EusoTrip iOS — Shipper Widget Gallery (§35.3 Arc L)
//
//  iOS twin of:
//    /Users/diegousoro/Desktop/EusoTrip 2027 UI Wireframes/02 Shipper/Code/
//    236_ShipperWidgetGallery.swift
//
//  Surface: per-Home-Screen-widget-size authoring. Three WidgetKit
//  size variants (Small 158×158 / Medium 338×158 / Large 338×354) each
//  carry a 7-bool payload vector mapped to the size-payload taxonomy.
//  Sixth Arc L brick after 231 push → 232 lock screen → 233 watch
//  complication → 234 haptic → 235 Focus Mode. Active size is Medium —
//  added 4 days ago, lane + 8-stage strip + ETA visible at glance.
//
//  §11.4 row 3 anchor (every widget thumbnail):
//    LD-260427-B41782FF02 · Eusorone Technologies (companyId 1) · Kansas
//    City MO → Omaha NE NH₃ UN1005 escort · MC-331 · Driver Michael
//    Eusorone (Eusotrans LLC USDOT 3 194 882) · stage 5 In transit ·
//    178/198 mi · ETA 4h 36m. NEXT BID $2,200 cites §11.2 row 2.
//
//  Doctrine: §2 nav, §3 numbers-first, §4.3 single hairline, §7 breathe
//  density, §11/§11.2/§11.4 Diego canon + MATRIX-50, §17.2 width-locked
//  status grammar, §19.2 file-scoped helpers (PillToggle,
//  GradientLivePill, GradientCapsuleCTA, CategoryDotStrip,
//  SmallWidgetThumbnail, MediumWidgetThumbnail, LargeWidgetThumbnail,
//  MicroStrip, WidgetThumbnailView, SizeRow), §20.4 no dead buttons,
//  §22.2 counter eyebrow color encodes screen-status, §35.3 Arc L
//  iOS-platform integration surfaces.
//
//  Backend (server) endpoints owed (EUSO-2156):
//    widgetKit.getInstalledWidgets         -> [WidgetSize]
//    widgetKit.setActiveWidgetSize(sizeId)  -> Void
//    widgetKit.getWidgetPreview(sizeId)     -> WidgetEntry
//    widgetKit.recordWidgetTimelineRefresh(sizeId, refreshedAt)
//
//  iOS API surface (consumed by LiveDataStore):
//    ShipperWidgetGalleryAPI.currentSizes()        -> [WidgetSize]
//    ShipperWidgetGalleryAPI.setEnabled(size:enabled:)
//    ShipperWidgetGalleryAPI.setActiveSize(_:)
//    ShipperWidgetGalleryAPI.reinstallActive()      -> reload timeline
//
//  iOS framework binding:
//    WidgetKit Home Screen widget extension exposing three
//    TimelineEntry kinds — SmallWidgetEntry · MediumWidgetEntry ·
//    LargeWidgetEntry — driven by widgetKit.getWidgetPreview and
//    refreshed via WidgetCenter.shared.reloadTimelines on lifecycle
//    stage advances.
//
//  Both #Preview blocks (Dark + Light) ship per §11.4 doctrine.
//

import SwiftUI

// MARK: - Screen

struct ShipperWidgetGallery: View {
    @Environment(\.palette) var palette
    @Environment(\.openURL) private var openURL

    private let counterEyebrow = "3 SIZES · MEDIUM INSTALLED"

    private let activeWidget = ActiveWidget(
        id:                "wgt_2026-04-25T13:18:00Z_medium",
        installedLabel:    "INSTALLED · MEDIUM · 1 OF 3 SIZES",
        headline:          "Lane + 8-stage strip + ETA",
        entryIdAndDims:    "MediumWidgetEntry · WidgetKit · 338×158",
        payloadEyebrow:    "PAYLOAD · 7 ELEMENTS",
        payloadCaption:    "MATRIX-50 row 3 · NH₃",
        relativeAgo:       "added 4d ago",
        ctaLabel:          "Reinstall widget",
        // 0 lane, 1 equipment, 2 8-stage strip, 3 ETA, 4 status pill,
        // 5 driver headline (Large only), 6 stat strip (Large only)
        payload: [true, true, true, true, true, false, false]
    )

    private let sizes: [WidgetSize] = [
        WidgetSize(
            id:           "small",
            title:        "Small",
            sub:          "158 × 158 · iPhone Home Screen",
            kind:         .small,
            payload:      [false, false, true, true, false, false, false],
            countCaption: "3 OF 7 · STAGE DOT + ETA + LANE ABBR",
            enabled:      false
        ),
        WidgetSize(
            id:           "medium",
            title:        "Medium",
            sub:          "338 × 158 · iPhone Home Screen",
            kind:         .medium,
            payload:      [true, true, true, true, true, false, false],
            countCaption: "5 OF 7 · LANE + 8-STAGE STRIP + ETA",
            enabled:      true
        ),
        WidgetSize(
            id:           "large",
            title:        "Large",
            sub:          "338 × 354 · iPhone Home Screen",
            kind:         .large,
            payload:      [true, true, true, true, true, true, true],
            countCaption: "7 OF 7 · FULL 232 LOCK-SCREEN-CARD PAYLOAD",
            enabled:      false
        )
    ]

    private let activeWidgetId: String = "medium"

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, Space.s5)
            titleBlock
                .padding(.top, Space.s3)

            IridescentHairline()
                .padding(.top, Space.s3)

            sectionLabel("ACTIVE WIDGET · MEDIUM INSTALLED")
                .padding(.top, Space.s5)
            heroCard
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s2)

            sectionLabel("WIDGETS · 3 SIZES")
                .padding(.top, Space.s5)
            sizesCard
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s2)

            settingsPointerLink
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)

            footer
                .padding(.top, Space.s4)
                .padding(.bottom, Space.s5)
        }
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · WIDGETS")
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
                .accessibilityLabel("Three Home Screen widget sizes total. Medium currently installed.")
        }
        .padding(.horizontal, Space.s5)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Widget gallery")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Home Screen widgets · Eusorone Technologies")
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

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                GradientLivePill(label: activeWidget.installedLabel)
                Spacer(minLength: 0)
                Text(activeWidget.relativeAgo)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
                    .monospacedDigit()
            }
            .padding(.top, 18)
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(activeWidget.headline)
                    .font(.system(size: 17, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(palette.textPrimary)

                Text(activeWidget.entryIdAndDims)
                    .font(EType.mono(.caption))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .padding(.top, 14)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .bottom, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(activeWidget.payloadEyebrow)
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(palette.textTertiary)

                    HStack(alignment: .center, spacing: 0) {
                        CategoryDotStrip(payload: activeWidget.payload,
                                         emphasis: .hero)
                        Spacer().frame(width: 8)
                        Text(activeWidget.payloadCaption)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                }

                Spacer(minLength: 0)

                Button(action: tapReinstallWidget) {
                    GradientCapsuleCTA(label: activeWidget.ctaLabel, width: 140)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reinstall the active Home Screen widget — refreshes the WidgetKit timeline immediately.")
            }
            .padding(.top, 14)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var sizesCard: some View {
        VStack(spacing: 0) {
            ForEach(sizes.indices, id: \.self) { idx in
                SizeRow(
                    size:        sizes[idx],
                    isActive:    sizes[idx].id == activeWidgetId,
                    onToggleTap: { tapSizeToggle(sizes[idx]) },
                    onRowTap:    { tapSizeRow(sizes[idx]) }
                )
                if idx < sizes.count - 1 {
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

    private var settingsPointerLink: some View {
        Button(action: tapManageWidgets) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manage installed widgets")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Per-widget opt-in matrix · 211 Settings")
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
        }
        .buttonStyle(.plain)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Manage installed widgets. Per-widget opt-in matrix lives in 211 Settings.")
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Powered by WidgetKit · Apple Home Screen widgets")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
            Text("companyId 1 · Eusorone Technologies · MATRIX-50-2026-04-26")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, Space.s5)
    }

    // MARK: - Tap handlers (§20.4 no dead buttons)

    private func tapReinstallWidget() {
        NotificationCenter.default.post(
            name: .eusoShipperWidgetReinstall,
            object: nil,
            userInfo: [
                "source": "236_ShipperWidgetGallery",
                "sizeId": activeWidget.id,
                "activeSizeId": activeWidgetId,
                "shipperCompanyId": 1
            ]
        )
        if let url = URL(string: "https://app.eusotrip.com/shipper/widgets/reinstall/\(activeWidget.id)") {
            openURL(url)
        }
    }

    private func tapSizeToggle(_ size: WidgetSize) {
        NotificationCenter.default.post(
            name: .eusoShipperWidgetSizeToggle,
            object: nil,
            userInfo: [
                "source": "236_ShipperWidgetGallery",
                "sizeId": size.id,
                "priorEnabled": size.enabled,
                "shipperCompanyId": 1
            ]
        )
        if let url = URL(string: "https://app.eusotrip.com/shipper/widgets/size/\(size.id)/toggle") {
            openURL(url)
        }
    }

    private func tapSizeRow(_ size: WidgetSize) {
        NotificationCenter.default.post(
            name: .eusoShipperWidgetSizeRow,
            object: nil,
            userInfo: [
                "source": "236_ShipperWidgetGallery",
                "sizeId": size.id,
                "payloadCount": size.payload.filter { $0 }.count,
                "isActiveSize": size.id == activeWidgetId,
                "shipperCompanyId": 1
            ]
        )
        if let url = URL(string: "https://app.eusotrip.com/shipper/widgets/size/\(size.id)") {
            openURL(url)
        }
    }

    private func tapManageWidgets() {
        NotificationCenter.default.post(
            name: .eusoShipperWidgetManage,
            object: nil,
            userInfo: [
                "source": "236_ShipperWidgetGallery",
                "targetScreen": "211 Settings",
                "shipperCompanyId": 1
            ]
        )
        if let url = URL(string: "https://app.eusotrip.com/shipper/settings/widgets") {
            openURL(url)
        }
    }
}

// MARK: - Domain models (file-scoped — wired by LiveDataStore from
//          ShipperWidgetGalleryAPI.currentSizes() + widgetKit.getInstalledWidgets)

private struct ActiveWidget {
    let id:              String
    let installedLabel:  String
    let headline:        String
    let entryIdAndDims:  String
    let payloadEyebrow:  String
    let payloadCaption:  String
    let relativeAgo:     String
    let ctaLabel:        String
    let payload:         [Bool]
}

private enum WidgetKind {
    case small
    case medium
    case large
}

private struct WidgetSize: Identifiable {
    let id:           String
    let title:        String
    let sub:          String
    let kind:         WidgetKind
    let payload:      [Bool]
    let countCaption: String
    let enabled:      Bool
}

// MARK: - Widget thumbnail body color (matches SVG #0B0B0F)
private let widgetBodyColor = Color(hex: 0x0B0B0F)

// MARK: - GradientLivePill (240×22 INSTALLED pill — same recipe as 234/235)

private struct GradientLivePill: View {
    let label: String

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(LinearGradient.primary)
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.30))
                        .frame(width: 12, height: 12)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 7, height: 7)
                }
                .padding(.leading, 8)
                Text(label)
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.trailing, 10)
        }
        .frame(maxWidth: 240, minHeight: 22, maxHeight: 22)
        .accessibilityLabel(label)
    }
}

// MARK: - GradientCapsuleCTA (140×22 hero CTA — same width as 234/235)

private struct GradientCapsuleCTA: View {
    let label: String
    let width: CGFloat

    var body: some View {
        ZStack {
            Capsule().fill(LinearGradient.primary)
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 8)
        }
        .frame(width: width, height: 22)
    }
}

// MARK: - CategoryDotStrip (7-dot visualizer — gradient pair when payload
//          included, neutral pair when omitted; lifted from 235)

private enum DotEmphasis {
    case hero
    case row
}

private struct CategoryDotStrip: View {
    @Environment(\.palette) var palette
    let payload:  [Bool]
    let emphasis: DotEmphasis

    var body: some View {
        HStack(spacing: 12) {
            ForEach(payload.indices, id: \.self) { idx in
                ZStack {
                    if payload[idx] {
                        Circle()
                            .fill(LinearGradient.primary.opacity(0.30))
                            .frame(width: 10, height: 10)
                        Circle()
                            .fill(LinearGradient.primary)
                            .frame(width: 8, height: 8)
                    } else {
                        Circle()
                            .fill(palette.textPrimary.opacity(0.10))
                            .frame(width: 10, height: 10)
                        Circle()
                            .fill(palette.textTertiary)
                            .frame(width: 6, height: 6)
                    }
                }
                .frame(width: 10, height: 10)
            }
        }
    }
}

// MARK: - SmallWidgetThumbnail (80×80 — stage pulse + stage tag + ETA + lane abbr)

private struct SmallWidgetThumbnail: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(widgetBodyColor)
                .frame(width: 80, height: 80)

            ZStack {
                Circle()
                    .fill(LinearGradient.primary.opacity(0.30))
                    .frame(width: 12, height: 12)
                Circle()
                    .fill(LinearGradient.primary)
                    .frame(width: 8, height: 8)
            }
            .position(x: 14, y: 14)

            Text("5/8")
                .font(.system(size: 7, weight: .heavy, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.62))
                .position(x: 68, y: 17)

            VStack(spacing: 0) {
                Text("4h")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("36m")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .monospacedDigit()
            }
            .position(x: 40, y: 52)

            Text("KC → OMA")
                .font(.system(size: 7, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(0.62))
                .position(x: 40, y: 72)
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("Small widget preview, stage 5 of 8, 4 hours 36 minutes, KC to OMA.")
    }
}

// MARK: - MediumWidgetThumbnail (200×96 — lane + 8-stage strip + ETA;
//          lifts 232's Live Activity card recipe at thumbnail scale)

private struct MediumWidgetThumbnail: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(widgetBodyColor)
                .frame(width: 200, height: 96)

            ZStack {
                Circle()
                    .fill(LinearGradient.primary.opacity(0.30))
                    .frame(width: 10, height: 10)
                Circle()
                    .fill(LinearGradient.primary)
                    .frame(width: 6, height: 6)
            }
            .padding(.leading, 9)
            .padding(.top, 9)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("UN1005 · NH₃")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.4)
                        .foregroundStyle(.white)
                    Text("KC MO → OMA NE")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .padding(.leading, 22)
                .padding(.top, 56)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("4h 36m")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                    Text("178/198 mi")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62))
                        .monospacedDigit()
                }
                .padding(.trailing, 12)
                .padding(.top, 56)
            }

            MicroStrip()
                .frame(width: 160, height: 8)
                .padding(.leading, 20)
                .padding(.top, 48)

            Text("stage 5 · in transit")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(LinearGradient.primary)
                .frame(width: 200, alignment: .center)
                .padding(.top, 70)
        }
        .frame(width: 200, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("Medium widget preview, UN1005 NH3, KC MO to OMA NE, 4 hours 36 minutes, stage 5 in transit.")
    }
}

// MARK: - LargeWidgetThumbnail (200×96 — top crop of full lock-screen-card
//          payload; lifts 232's expanded Dynamic Island recipe at scale)

private struct LargeWidgetThumbnail: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(widgetBodyColor)
                .frame(width: 200, height: 96)

            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    Capsule().fill(LinearGradient.primary)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 4, height: 4)
                            .padding(.leading, 6)
                        Text("LIVE · UN1005")
                            .font(.system(size: 7, weight: .heavy))
                            .tracking(0.6)
                            .foregroundStyle(.white)
                    }
                    .padding(.trailing, 8)
                }
                .frame(width: 100, height: 14)

                Spacer(minLength: 0)

                Text("4h 36m")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .padding(.trailing, 14)
            }
            .padding(.leading, 10)
            .padding(.top, 10)

            VStack(alignment: .leading, spacing: 2) {
                Text("Eusorone Technologies")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                Text("KC MO → OMA NE · MC-331 NH₃")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                Text("DRIVER · Michael Eusorone")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .padding(.leading, 10)
            .padding(.top, 30)

            MicroStrip()
                .frame(width: 180, height: 8)
                .padding(.leading, 10)
                .padding(.top, 68)

            HStack {
                Text("NEXT BID $2,200")
                    .font(.system(size: 7, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(.white.opacity(0.62))
                Spacer(minLength: 0)
                Text("EXC 1")
                    .font(.system(size: 7, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(LinearGradient.primary)
            }
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .padding(.top, 82)
        }
        .frame(width: 200, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("Large widget preview, Eusorone Technologies, KC MO to OMA NE MC-331 NH3, driver Michael Eusorone, 4 hours 36 minutes, next bid $2,200, 1 exception.")
    }
}

// MARK: - MicroStrip (8-dot lifecycle preview — same done/active/remaining
//          contract as 232/233's MicroStrip)

private struct MicroStrip: View {
    var body: some View {
        GeometryReader { geo in
            let count = 8
            let stride = geo.size.width / CGFloat(count - 1)
            let activeIdx = 4

            ZStack {
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(height: 1.5)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                Rectangle()
                    .fill(LinearGradient.primary)
                    .frame(width: stride * CGFloat(activeIdx), height: 1.5)
                    .position(x: stride * CGFloat(activeIdx) / 2, y: geo.size.height / 2)

                ForEach(0..<count, id: \.self) { idx in
                    let x = stride * CGFloat(idx)
                    if idx < activeIdx {
                        Circle()
                            .fill(LinearGradient.primary)
                            .frame(width: 4, height: 4)
                            .position(x: x, y: geo.size.height / 2)
                    } else if idx == activeIdx {
                        ZStack {
                            Circle()
                                .fill(LinearGradient.primary.opacity(0.25))
                                .frame(width: 12, height: 12)
                            Circle()
                                .fill(LinearGradient.primary)
                                .frame(width: 7, height: 7)
                        }
                        .position(x: x, y: geo.size.height / 2)
                    } else {
                        Circle()
                            .fill(.white.opacity(0.30))
                            .frame(width: 4, height: 4)
                            .position(x: x, y: geo.size.height / 2)
                    }
                }
            }
        }
    }
}

// MARK: - WidgetThumbnailView (kind-driven thumbnail dispatcher)

private struct WidgetThumbnailView: View {
    let kind: WidgetKind

    var body: some View {
        switch kind {
        case .small:
            SmallWidgetThumbnail()
        case .medium:
            MediumWidgetThumbnail()
        case .large:
            LargeWidgetThumbnail()
        }
    }
}

// MARK: - SizeRow (per-Home-Screen-widget-size row — thumbnail + name +
//          dim sub + 7-dot strip + count caption + PillToggle; active
//          row gets 12% gradient wash, leading marker dot, gradient
//          title/caption/chevron)

private struct SizeRow: View {
    @Environment(\.palette) var palette
    let size:        WidgetSize
    let isActive:    Bool
    let onToggleTap: () -> Void
    let onRowTap:    () -> Void

    var body: some View {
        Button(action: onRowTap) {
            ZStack(alignment: .leading) {
                if isActive {
                    LinearGradient.primary
                        .opacity(0.12)
                }

                HStack(alignment: .top, spacing: 14) {
                    if isActive {
                        Circle()
                            .fill(LinearGradient.primary)
                            .frame(width: 6, height: 6)
                            .padding(.top, 30)
                            .padding(.leading, 8)
                    }

                    HStack(alignment: .top, spacing: 14) {
                        WidgetThumbnailView(kind: size.kind)
                            .padding(.top, size.kind == .small ? 16 : 8)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(size.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(isActive
                                                 ? AnyShapeStyle(LinearGradient.primary)
                                                 : AnyShapeStyle(palette.textPrimary))
                                .lineLimit(1)

                            Text(size.sub)
                                .font(.system(size: 10))
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)

                            CategoryDotStrip(payload: size.payload,
                                             emphasis: .row)
                                .padding(.top, 56)

                            HStack(alignment: .center, spacing: 0) {
                                Text(size.countCaption)
                                    .font(.system(size: 9, weight: .heavy))
                                    .tracking(0.6)
                                    .foregroundStyle(isActive
                                                     ? AnyShapeStyle(LinearGradient.primary)
                                                     : AnyShapeStyle(palette.textTertiary))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                Spacer(minLength: 0)
                                if isActive {
                                    Text("→")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(LinearGradient.primary)
                                }
                            }
                            .padding(.top, 6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: onToggleTap) {
                        PillToggle(enabled: size.enabled)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(size.title), \(size.enabled ? "installed" : "not installed")")
                    .accessibilityHint("Toggles the \(size.title) Home Screen widget size.")
                    .padding(.top, 30)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .frame(minHeight: 130)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(size.title) Home Screen widget. \(size.countCaption). \(size.enabled ? "Installed" : "Not installed").\(isActive ? " Active." : "")")
    }
}

// MARK: - PillToggle (44×24 — 211/234/235 recipe)

private struct PillToggle: View {
    @Environment(\.palette) var palette
    let enabled: Bool

    var body: some View {
        ZStack(alignment: enabled ? .trailing : .leading) {
            Capsule()
                .fill(enabled
                      ? AnyShapeStyle(LinearGradient.primary)
                      : AnyShapeStyle(palette.textPrimary.opacity(0.10)))
            Circle()
                .fill(.white)
                .frame(width: 18, height: 18)
                .padding(.horizontal, 3)
        }
        .frame(width: 44, height: 24)
    }
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// "Reinstall widget" CTA — fires WidgetCenter.shared.reloadTimelines
    /// for the active size's WidgetKit timeline so the Home Screen widget
    /// refreshes immediately. Payload: sizeId + activeSizeId.
    static let eusoShipperWidgetReinstall   = Notification.Name("eusoShipperWidgetReinstall")

    /// Per-size PillToggle tap — flips per-size enabled state via
    /// widgetKit.setActiveWidgetSize. Carries priorEnabled for revert.
    static let eusoShipperWidgetSizeToggle  = Notification.Name("eusoShipperWidgetSizeToggle")

    /// Per-size row tap — opens the per-size payload-edit sheet (the
    /// 7-toggle matrix mapping size-payload taxonomy to size's payload
    /// vector). Tapping the active row re-fires the WidgetKit timeline reload.
    static let eusoShipperWidgetSizeRow     = Notification.Name("eusoShipperWidgetSizeRow")

    /// "Manage installed widgets" pointer link tap — routes into 211
    /// Settings's widget toggles card (source of truth for the per-size
    /// per-element opt-in matrix).
    static let eusoShipperWidgetManage      = Notification.Name("eusoShipperWidgetManage")
}

// MARK: - Shell wrapper + Shipper BottomNav (Me current)

private func shipperNavLeading() -> [NavSlot] {
    [
        NavSlot(label: "Home",  systemImage: "house.fill",   isCurrent: false),
        NavSlot(label: "Loads", systemImage: "shippingbox",  isCurrent: false),
    ]
}
private func shipperNavTrailing() -> [NavSlot] {
    [
        NavSlot(label: "My Loads", systemImage: "creditcard",   isCurrent: false),
        NavSlot(label: "Me",     systemImage: "person.fill",  isCurrent: true),
    ]
}

struct ShipperWidgetGalleryScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ShipperWidgetGallery()
        } nav: {
            BottomNav(leading: shipperNavLeading(),
                      trailing: shipperNavTrailing(),
                      orbState: .idle)
        }
    }
}

// MARK: - Previews (Dark + Light per §11.4 doctrine)

#Preview("Shipper Widget Gallery · Dark") {
    ShipperWidgetGalleryScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
        .padding(24)
        .background(Theme.dark.bgPage)
}

#Preview("Shipper Widget Gallery · Light") {
    ShipperWidgetGalleryScreen(theme: Theme.light)
        .preferredColorScheme(.light)
        .padding(24)
        .background(Theme.light.bgPage)
}
