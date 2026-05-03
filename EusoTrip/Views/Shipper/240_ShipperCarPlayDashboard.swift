//
//  240_ShipperCarPlayDashboard.swift
//  EusoTrip iOS — Shipper CarPlay Dashboard authoring (§35.3 Arc L)
//
//  iOS twin of:
//    /Users/diegousoro/Desktop/EusoTrip 2027 UI Wireframes/02 Shipper/Code/
//    240_ShipperCarPlayDashboard.swift
//
//  Surface: per-tile CarPlay Dashboard scene-widget authoring. Tenth and
//  final Arc L brick — closes the cohort at ten consecutive iOS-platform-
//  surface bricks (231 push receiver · 232 lock screen Live Activity ·
//  233 Watch complication · 234 haptic escalation · 235 Focus Mode ·
//  236 widget gallery · 237 App Intents · 238 Continuity · 239 Apple Pay
//  Wallet · 240 CarPlay Dashboard).
//
//  Hero is the active CarPlay tile for §11.2 row 1
//  (LD-260427-A38FB12C7E · Houston→Dallas · MC-306 Gasoline UN1203 ·
//  $1,900). Six tiles in the gallery (Active Load + Hot Zones +
//  Control Tower + Wallet Pass enabled, Catalyst Ticker + Quick Call
//  Driver disabled). Three zone slots: Driver Cluster active wash,
//  Dashboard Widget enabled, Passenger Map disabled per Eusorone fleet
//  policy.
//
//  §11 Diego canon · §11.2/§11.4 MATRIX-50 anchors verbatim.
//  Doctrine: §2 nav, §3 numbers-first, §4.3 single hairline, §7 breathe
//  density, §13 Catalyst tier system, §17.2 width-locked status grammar,
//  §19.2 file-scoped helpers (GradientPassHeader, GradientCapsuleCTA,
//  CarPlayMapPreview, TierLetterBadge, WidgetGlyphTile, EnabledPill,
//  WidgetRow, ZoneRow), §20.4 no dead buttons, §22.2 counter eyebrow
//  color encodes screen-status, §35.3 Arc L iOS-platform integration
//  surfaces.
//
//  Backend (server) endpoints owed (EUSO-2161):
//    carplay.getDashboardWidgets    -> [CarPlayWidget]
//    carplay.setWidgetEnabled(widgetId, enabled)
//    carplay.getZoneAssignments     -> [CarPlayZone]
//    carplay.setZoneEnabled(zoneId, enabled)
//    carplay.recordCarPlayHandoff(loadId, zone, scene)
//
//  iOS API surface (consumed by LiveDataStore):
//    ShipperCarPlayAPI.currentWidgets()     -> [CarPlayWidget]
//    ShipperCarPlayAPI.setWidget(_:enabled:)
//    ShipperCarPlayAPI.currentZones()       -> [CarPlayZone]
//    ShipperCarPlayAPI.setZone(_:enabled:)
//    ShipperCarPlayAPI.recordHandoff(loadId:)
//
//  iOS framework binding:
//    CarPlay (CPTemplateApplicationSceneDelegate / CPDashboardController
//    / CPNowPlayingTemplate manage the head-unit scene lifecycle;
//    CPMapTemplate + CPListTemplate render the active-load + hot-zones
//    + control-tower scenes; CPInformationTemplate renders the wallet-
//    pass quick-action scene). Each CarPlay scene is bound to a parent
//    NSUserActivity carrying the LD-id so a handoff back to iPhone via
//    238's NSUserActivity-Continuity recipe deep-links straight to 205
//    ShipperLoadDetail.
//
//  Both #Preview blocks (Dark + Light) ship per §11.4 doctrine.
//

import SwiftUI

// MARK: - Screen

struct ShipperCarPlayDashboard: View {
    @Environment(\.palette) var palette
    @Environment(\.openURL) private var openURL

    private let counterEyebrow = "6 TILES · 4 ENABLED"

    private let activeTile = ActiveCarPlayTile(
        id:                 "carplay_LD-260427-A38FB12C7E",
        sceneLine:          "CARPLAY · ACTIVE LOAD",
        title:              "Houston \u{2192} Dallas",
        loadId:             "LD-260427-A38FB12C7E",
        eta:                "Apr 30 · in 4h 12m",
        equipment:          "MC-306 · UN1203 · Gas",
        driver:             "Michael Eusorone",
        carrier:            "Bulk Logistics MC-1485",
        carrierTier:        "A",
        tierCarrierLine:    "Tier A · Eusotrans LLC",
        pairingLine:        "CarPlay paired · in 4h 12m",
        distanceLine:       "240 mi · 4h 12m",
        ctaLabel:           "Add to CarPlay"
    )

    private let widgets: [CarPlayWidget] = [
        CarPlayWidget(
            id:       "tile_active_load",
            name:     "Active Load",
            binding:  "LD-260427-A38FB12C7E · Driver Cluster",
            glyph:    .truck,
            enabled:  true,
            isActive: true
        ),
        CarPlayWidget(
            id:       "tile_hot_zones",
            name:     "Hot Zones",
            binding:  "Gulf · LA basin · Midwest · Dashboard Widget",
            glyph:    .flame,
            enabled:  true,
            isActive: false
        ),
        CarPlayWidget(
            id:       "tile_control_tower",
            name:     "Control Tower",
            binding:  "2 EXCEPTIONS · 4 IN TRANSIT · Dashboard Widget",
            glyph:    .tower,
            enabled:  true,
            isActive: false
        ),
        CarPlayWidget(
            id:       "tile_wallet_pass",
            name:     "Wallet Pass",
            binding:  "Add-to-Wallet quick action · Driver Cluster",
            glyph:    .wallet,
            enabled:  true,
            isActive: false
        ),
        CarPlayWidget(
            id:       "tile_catalyst_ticker",
            name:     "Catalyst Ticker",
            binding:  "5-carrier grade trend · Passenger Map",
            glyph:    .tierLetterA,
            enabled:  false,
            isActive: false
        ),
        CarPlayWidget(
            id:       "tile_quick_call",
            name:     "Quick Call Driver",
            binding:  "Eusotrans LLC · Driver Cluster",
            glyph:    .phone,
            enabled:  false,
            isActive: false
        )
    ]

    private let zones: [CarPlayZone] = [
        CarPlayZone(
            id:       "zone_driver_cluster",
            name:     "Driver Cluster",
            binding:  "2 widgets · Active Load · Wallet Pass",
            enabled:  true,
            isActive: true
        ),
        CarPlayZone(
            id:       "zone_dashboard_widget",
            name:     "Dashboard Widget",
            binding:  "2 widgets · Hot Zones · Control Tower",
            enabled:  true,
            isActive: false
        ),
        CarPlayZone(
            id:       "zone_passenger_map",
            name:     "Passenger Map",
            binding:  "0 widgets · disabled in Eusorone fleet policy",
            enabled:  false,
            isActive: false
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, Space.s5)
            titleBlock
                .padding(.top, Space.s3)

            IridescentHairline()
                .padding(.top, Space.s3)

            sectionLabel("ACTIVE TILE · MATRIX-50 ROW 1")
                .padding(.top, Space.s5)
            heroTileCard
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s2)

            sectionLabel("WIDGETS · 6 IN GALLERY")
                .padding(.top, Space.s5)
            widgetsCard
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s2)

            sectionLabel("ZONES · 3 SLOTS")
                .padding(.top, Space.s5)
            zonesCard
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
            Text("\u{2726} SHIPPER · CARPLAY · LIVE")
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
                .accessibilityLabel("Six CarPlay widgets installed in the gallery. Four are currently enabled.")
        }
        .padding(.horizontal, Space.s5)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CarPlay")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Dashboard widgets · Eusorone Technologies")
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

    // MARK: - HERO TILE CARD (active CarPlay tile preview)

    private var heroTileCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )

            VStack(alignment: .leading, spacing: 0) {
                GradientPassHeader(
                    sceneLine: activeTile.sceneLine,
                    title:     activeTile.title
                )

                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("LOAD ID")
                            .font(.system(size: 8, weight: .heavy))
                            .tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                            .padding(.top, 12)

                        Text(activeTile.loadId)
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .tracking(0.4)
                            .foregroundStyle(LinearGradient.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .padding(.top, 4)

                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ETA")
                                    .font(.system(size: 8, weight: .heavy))
                                    .tracking(0.6)
                                    .foregroundStyle(palette.textTertiary)
                                Text(activeTile.eta)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(palette.textPrimary)
                                    .monospacedDigit()
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("EQUIPMENT")
                                    .font(.system(size: 8, weight: .heavy))
                                    .tracking(0.6)
                                    .foregroundStyle(palette.textTertiary)
                                Text(activeTile.equipment)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)
                            }
                        }
                        .padding(.top, 12)

                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("DRIVER")
                                    .font(.system(size: 8, weight: .heavy))
                                    .tracking(0.6)
                                    .foregroundStyle(palette.textTertiary)
                                Text(activeTile.driver)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("CARRIER")
                                    .font(.system(size: 8, weight: .heavy))
                                    .tracking(0.6)
                                    .foregroundStyle(palette.textTertiary)
                                Text(activeTile.carrier)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(palette.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)
                            }
                        }
                        .padding(.top, 8)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack {
                        Spacer()
                        CarPlayMapPreview(distanceLabel: activeTile.distanceLine)
                            .padding(.top, 12)
                            .padding(.trailing, 20)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                HStack(alignment: .center, spacing: 12) {
                    TierLetterBadge(letter: activeTile.carrierTier)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeTile.tierCarrierLine)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Text(activeTile.pairingLine)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(LinearGradient.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }

                    Spacer(minLength: 0)

                    Button(action: tapAddToCarPlay) {
                        GradientCapsuleCTA(label: activeTile.ctaLabel, width: 140)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add the active load tile to CarPlay — pins the Houston to Dallas active-load widget to the Driver Cluster zone of the head unit's Dashboard scene.")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var widgetsCard: some View {
        VStack(spacing: 0) {
            ForEach(widgets.indices, id: \.self) { idx in
                WidgetRow(
                    widget:    widgets[idx],
                    onRowTap:  { tapWidgetRow(widgets[idx]) }
                )
                if idx < widgets.count - 1 {
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

    private var zonesCard: some View {
        VStack(spacing: 0) {
            ForEach(zones.indices, id: \.self) { idx in
                ZoneRow(
                    zone:      zones[idx],
                    onRowTap:  { tapZoneRow(zones[idx]) }
                )
                if idx < zones.count - 1 {
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
        Button(action: tapManageCarPlay) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Manage CarPlay integration")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Per-tile · per-zone · pairing · 211 Settings")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("\u{2192}")
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
        .accessibilityLabel("Manage CarPlay integration. Per-tile, per-zone, and pairing settings live in 211 Settings.")
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("Powered by CarPlay · MapKit · CPNowPlayingTemplate")
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

    private func tapAddToCarPlay() {
        NotificationCenter.default.post(
            name: .eusoShipperCarPlayAddTile,
            object: nil,
            userInfo: [
                "source":           "240_ShipperCarPlayDashboard",
                "tileId":           activeTile.id,
                "loadId":           activeTile.loadId,
                "carrierMC":        "MC-1485",
                "driver":           activeTile.driver,
                "shipperCompanyId": 1,
                "zone":             "driver_cluster"
            ]
        )
        if let url = URL(string: "https://app.eusotrip.com/shipper/carplay/tile/\(activeTile.id)/add") {
            openURL(url)
        }
    }

    private func tapWidgetRow(_ widget: CarPlayWidget) {
        NotificationCenter.default.post(
            name: .eusoShipperCarPlayWidgetRow,
            object: nil,
            userInfo: [
                "source":           "240_ShipperCarPlayDashboard",
                "widgetId":         widget.id,
                "widgetName":       widget.name,
                "isEnabled":        widget.enabled,
                "isActive":         widget.isActive,
                "shipperCompanyId": 1
            ]
        )
        if let url = URL(string: "https://app.eusotrip.com/shipper/carplay/widget/\(widget.id)") {
            openURL(url)
        }
    }

    private func tapZoneRow(_ zone: CarPlayZone) {
        NotificationCenter.default.post(
            name: .eusoShipperCarPlayZoneRow,
            object: nil,
            userInfo: [
                "source":           "240_ShipperCarPlayDashboard",
                "zoneId":           zone.id,
                "zoneName":         zone.name,
                "isEnabled":        zone.enabled,
                "isActive":         zone.isActive,
                "shipperCompanyId": 1
            ]
        )
        if let url = URL(string: "https://app.eusotrip.com/shipper/carplay/zone/\(zone.id)") {
            openURL(url)
        }
    }

    private func tapManageCarPlay() {
        NotificationCenter.default.post(
            name: .eusoShipperCarPlayManage,
            object: nil,
            userInfo: [
                "source":           "240_ShipperCarPlayDashboard",
                "targetScreen":     "211 Settings",
                "shipperCompanyId": 1
            ]
        )
        if let url = URL(string: "https://app.eusotrip.com/shipper/settings/carplay") {
            openURL(url)
        }
    }
}

// MARK: - Domain models (file-scoped — wired by LiveDataStore from
//          ShipperCarPlayAPI.currentWidgets() + carplay.getDashboardWidgets
//          + carplay.getZoneAssignments)

private struct ActiveCarPlayTile {
    let id:               String
    let sceneLine:        String
    let title:            String
    let loadId:           String
    let eta:              String
    let equipment:        String
    let driver:           String
    let carrier:          String
    let carrierTier:      String
    let tierCarrierLine:  String
    let pairingLine:      String
    let distanceLine:     String
    let ctaLabel:         String
}

private enum CarPlayWidgetGlyph {
    case truck
    case flame
    case tower
    case wallet
    case tierLetterA
    case phone
}

private struct CarPlayWidget: Identifiable {
    let id:        String
    let name:      String
    let binding:   String
    let glyph:     CarPlayWidgetGlyph
    let enabled:   Bool
    let isActive:  Bool
}

private struct CarPlayZone: Identifiable {
    let id:        String
    let name:      String
    let binding:   String
    let enabled:   Bool
    let isActive:  Bool
}

// MARK: - GradientPassHeader (40pt CarPlay scene-lead strip — gradient
//          fill, white scene-line + title + Apple "Play" capsule on the
//          right; lifted from 239 with `issuerLine` -> `sceneLine` pivot)

private struct GradientPassHeader: View {
    let sceneLine: String
    let title:     String

    var body: some View {
        ZStack(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius:     Radius.lg,
                bottomLeadingRadius:  0,
                bottomTrailingRadius: 0,
                topTrailingRadius:    Radius.lg,
                style: .continuous
            )
            .fill(LinearGradient.diagonal)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sceneLine)
                        .font(.system(size: 8, weight: .heavy))
                        .tracking(1.0)
                        .foregroundStyle(Color.white.opacity(0.85))
                    Text(title)
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(0.3)
                        .foregroundStyle(.white)
                }
                Spacer()
                ZStack {
                    Capsule().fill(Color.white.opacity(0.18))
                    Text("Play")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.4)
                        .foregroundStyle(.white)
                }
                .frame(width: 50, height: 18)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, minHeight: 40, maxHeight: 40)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(sceneLine) — \(title) — Apple Play")
    }
}

// MARK: - GradientCapsuleCTA (140×22 hero CTA — 234-239 recipe)

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

// MARK: - CarPlayMapPreview (100×100 stylized MapKit scene — grid +
//          curved gradient route + origin/dest pins + truck puck +
//          compass label. Decorative — production renders a real
//          MKMapView via UIViewRepresentable from CPMapTemplate's
//          underlying MKMapView.)

private struct CarPlayMapPreview: View {
    @Environment(\.palette) var palette
    let distanceLabel: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(palette.textPrimary.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )

            ForEach([22, 44, 66, 88], id: \.self) { y in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: CGFloat(y)))
                    path.addLine(to: CGPoint(x: 100, y: CGFloat(y)))
                }
                .stroke(palette.textPrimary.opacity(0.06), lineWidth: 1)
            }
            ForEach([22, 44, 66, 88], id: \.self) { x in
                Path { path in
                    path.move(to: CGPoint(x: CGFloat(x), y: 0))
                    path.addLine(to: CGPoint(x: CGFloat(x), y: 100))
                }
                .stroke(palette.textPrimary.opacity(0.06), lineWidth: 1)
            }

            Path { path in
                path.move(to: CGPoint(x: 14, y: 82))
                path.addQuadCurve(to: CGPoint(x: 50, y: 50), control: CGPoint(x: 34, y: 62))
                path.addQuadCurve(to: CGPoint(x: 86, y: 18), control: CGPoint(x: 70, y: 36))
            }
            .stroke(LinearGradient.diagonal,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round))

            ZStack {
                Circle().fill(Color(red: 0.078, green: 0.451, blue: 1.0))
                    .frame(width: 12, height: 12)
                Circle().fill(Color.white)
                    .frame(width: 4, height: 4)
            }
            .offset(x: 8, y: 76)

            ZStack {
                Circle().fill(Color(red: 0.745, green: 0.004, blue: 1.0))
                    .frame(width: 12, height: 12)
                Circle().fill(Color.white)
                    .frame(width: 4, height: 4)
            }
            .offset(x: 80, y: 12)

            ZStack {
                Circle()
                    .fill(palette.bgCard)
                    .overlay(
                        Circle().strokeBorder(LinearGradient.primary, lineWidth: 2)
                    )
                    .frame(width: 14, height: 14)
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(LinearGradient.primary)
                    .frame(width: 6, height: 4)
            }
            .offset(x: 43, y: 43)

            VStack {
                Spacer()
                Text(distanceLabel)
                    .font(.system(size: 7, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.bottom, 3)
            }
            .frame(width: 100, height: 100)
        }
        .frame(width: 100, height: 100)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("CarPlay map preview · Houston to Dallas · \(distanceLabel)")
    }
}

// MARK: - TierLetterBadge (24×24 — 233/239 recipe)

private struct TierLetterBadge: View {
    let letter: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient.primary)
            Text(letter)
                .font(.system(size: 14, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white)
        }
        .frame(width: 24, height: 24)
        .accessibilityLabel("Catalyst tier \(letter)")
    }
}

// MARK: - WidgetGlyphTile (24×24 widget glyph — gradient when enabled,
//          neutral when disabled; pivots 237/238/239 InitialsTile/LDTile
//          semantic to "tile enabled / disabled")

private struct WidgetGlyphTile: View {
    @Environment(\.palette) var palette
    let glyph:   CarPlayWidgetGlyph
    let enabled: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(enabled
                      ? AnyShapeStyle(LinearGradient.primary)
                      : AnyShapeStyle(palette.textPrimary.opacity(0.06)))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(enabled
                                      ? Color.clear
                                      : palette.borderFaint)
                )

            glyphShape
                .foregroundStyle(enabled
                                 ? AnyShapeStyle(Color.white)
                                 : AnyShapeStyle(palette.textTertiary))
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyphShape: some View {
        switch glyph {
        case .truck:
            Path { p in
                p.move(to: CGPoint(x: 5, y: 14))
                p.addLine(to: CGPoint(x: 14, y: 14))
                p.addLine(to: CGPoint(x: 14, y: 8))
                p.addLine(to: CGPoint(x: 17, y: 8))
                p.addLine(to: CGPoint(x: 19, y: 11))
                p.addLine(to: CGPoint(x: 19, y: 14))
                p.addLine(to: CGPoint(x: 20, y: 14))
                p.addLine(to: CGPoint(x: 20, y: 17))
                p.addLine(to: CGPoint(x: 17, y: 17))
                p.addCurve(to: CGPoint(x: 13, y: 17),
                           control1: CGPoint(x: 17, y: 19),
                           control2: CGPoint(x: 13, y: 19))
                p.addLine(to: CGPoint(x: 10, y: 17))
                p.addCurve(to: CGPoint(x: 6, y: 17),
                           control1: CGPoint(x: 10, y: 19),
                           control2: CGPoint(x: 6, y: 19))
                p.addLine(to: CGPoint(x: 5, y: 17))
                p.closeSubpath()
            }
            .fill(.foreground)
            .frame(width: 24, height: 24)
        case .flame:
            Path { p in
                p.move(to: CGPoint(x: 8, y: 18))
                p.addLine(to: CGPoint(x: 8, y: 12))
                p.addLine(to: CGPoint(x: 12, y: 6))
                p.addLine(to: CGPoint(x: 16, y: 12))
                p.addLine(to: CGPoint(x: 16, y: 18))
                p.closeSubpath()
            }
            .fill(.foreground)
            .frame(width: 24, height: 24)
        case .tower:
            ZStack {
                Rectangle().fill(.foreground)
                    .frame(width: 2, height: 14)
                    .offset(x: 0, y: -2)
                Rectangle().fill(.foreground)
                    .frame(width: 10, height: 2)
                    .offset(x: 0, y: -2)
                Rectangle().fill(.foreground)
                    .frame(width: 6, height: 4)
                    .offset(x: 0, y: 6)
            }
            .frame(width: 24, height: 24)
        case .wallet:
            ZStack {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .strokeBorder(.foreground, lineWidth: 1.5)
                    .frame(width: 14, height: 10)
                Rectangle().fill(.foreground)
                    .frame(width: 14, height: 2)
                    .offset(x: 0, y: -2)
                Rectangle().fill(.foreground)
                    .frame(width: 3, height: 1.5)
                    .offset(x: 4.5, y: 1.5)
            }
            .frame(width: 24, height: 24)
            .offset(x: 0, y: 1)
        case .tierLetterA:
            Text("A")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(.foreground)
        case .phone:
            Path { p in
                p.move(to: CGPoint(x: 7, y: 7))
                p.addLine(to: CGPoint(x: 9, y: 7))
                p.addLine(to: CGPoint(x: 11, y: 11))
                p.addLine(to: CGPoint(x: 9, y: 13))
                p.addQuadCurve(to: CGPoint(x: 14, y: 17),
                               control: CGPoint(x: 11, y: 16))
                p.addLine(to: CGPoint(x: 16, y: 15))
                p.addLine(to: CGPoint(x: 20, y: 17))
                p.addLine(to: CGPoint(x: 20, y: 19))
                p.addQuadCurve(to: CGPoint(x: 9, y: 16),
                               control: CGPoint(x: 14, y: 21))
                p.addQuadCurve(to: CGPoint(x: 7, y: 7),
                               control: CGPoint(x: 5, y: 11))
                p.closeSubpath()
            }
            .fill(.foreground)
            .frame(width: 24, height: 24)
        }
    }
}

// MARK: - EnabledPill (48×16 status pill — gradient ENABLED-active /
//          outlined-gradient ENABLED-archived / outlined-neutral OFF;
//          three-state lift from 230's allocation status pill)

private enum EnabledPillState {
    case enabledActive
    case enabledArchived
    case off

    var label: String {
        switch self {
        case .enabledActive, .enabledArchived: return "ENABLED"
        case .off:                             return "OFF"
        }
    }
}

private struct EnabledPill: View {
    @Environment(\.palette) var palette
    let state: EnabledPillState

    var body: some View {
        ZStack {
            switch state {
            case .enabledActive:
                Capsule().fill(LinearGradient.primary)
            case .enabledArchived:
                Capsule()
                    .strokeBorder(LinearGradient.primary, lineWidth: 1)
            case .off:
                Capsule()
                    .strokeBorder(palette.textPrimary.opacity(0.20),
                                  lineWidth: 1)
            }
            Text(state.label)
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(labelStyle)
        }
        .frame(width: 48, height: 16)
    }

    private var labelStyle: AnyShapeStyle {
        switch state {
        case .enabledActive:    return AnyShapeStyle(Color.white)
        case .enabledArchived:  return AnyShapeStyle(LinearGradient.primary)
        case .off:              return AnyShapeStyle(palette.textSecondary)
        }
    }
}

// MARK: - WidgetRow (per-CarPlay-tile row — WidgetGlyphTile + name +
//          binding + EnabledPill; active variant gets gradient wash)

private struct WidgetRow: View {
    @Environment(\.palette) var palette
    let widget:   CarPlayWidget
    let onRowTap: () -> Void

    private var pillState: EnabledPillState {
        if !widget.enabled { return .off }
        return widget.isActive ? .enabledActive : .enabledArchived
    }

    var body: some View {
        Button(action: onRowTap) {
            ZStack(alignment: .leading) {
                if widget.isActive {
                    LinearGradient.primary
                        .opacity(0.12)
                }

                HStack(alignment: .center, spacing: 10) {
                    if widget.isActive {
                        Circle()
                            .fill(LinearGradient.primary)
                            .frame(width: 6, height: 6)
                            .padding(.leading, 4)
                    } else {
                        Color.clear.frame(width: 10, height: 6)
                    }

                    WidgetGlyphTile(glyph: widget.glyph, enabled: widget.enabled)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(widget.name)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(widget.isActive
                                             ? AnyShapeStyle(LinearGradient.primary)
                                             : AnyShapeStyle(palette.textPrimary))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Text(widget.binding)
                            .font(.system(size: 9))
                            .foregroundStyle(widget.isActive
                                             ? AnyShapeStyle(LinearGradient.primary)
                                             : AnyShapeStyle(palette.textSecondary))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    EnabledPill(state: pillState)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
            .frame(minHeight: 32)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(widget.name). \(widget.binding). \(widget.enabled ? "Enabled" : "Off").\(widget.isActive ? " Active CarPlay tile." : "")")
    }
}

// MARK: - ZoneRow (per-CarPlay-zone row — name + widget-list binding +
//          EnabledPill; compact variant of WidgetRow without the leading
//          24×24 glyph tile, since zones are abstract slots)

private struct ZoneRow: View {
    @Environment(\.palette) var palette
    let zone:     CarPlayZone
    let onRowTap: () -> Void

    private var pillState: EnabledPillState {
        if !zone.enabled { return .off }
        return zone.isActive ? .enabledActive : .enabledArchived
    }

    var body: some View {
        Button(action: onRowTap) {
            ZStack(alignment: .leading) {
                if zone.isActive {
                    LinearGradient.primary
                        .opacity(0.12)
                }

                HStack(alignment: .center, spacing: 10) {
                    if zone.isActive {
                        Circle()
                            .fill(LinearGradient.primary)
                            .frame(width: 6, height: 6)
                            .padding(.leading, 4)
                    } else {
                        Color.clear.frame(width: 10, height: 6)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(zone.name)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(zone.isActive
                                             ? AnyShapeStyle(LinearGradient.primary)
                                             : AnyShapeStyle(palette.textPrimary))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)

                        Text(zone.binding)
                            .font(.system(size: 9))
                            .foregroundStyle(zone.isActive
                                             ? AnyShapeStyle(LinearGradient.primary)
                                             : AnyShapeStyle(palette.textSecondary))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    EnabledPill(state: pillState)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
            .frame(minHeight: 32)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(zone.name) zone. \(zone.binding). \(zone.enabled ? "Enabled" : "Off").\(zone.isActive ? " Active CarPlay zone." : "")")
    }
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// "Add to CarPlay" CTA — fires CPDashboardController scene-add
    /// sequence with a CPListTemplate + CPMapTemplate composed from the
    /// active load's payload. Payload: tileId + loadId + carrierMC +
    /// driver + zone.
    static let eusoShipperCarPlayAddTile     = Notification.Name("eusoShipperCarPlayAddTile")

    /// Per-widget row tap — opens the per-tile edit sheet (enable/disable
    /// toggle, target zone selector, refresh interval, scene template).
    /// Tapping the active row re-opens the active tile in CarPlay's Now
    /// Playing scene via CPNowPlayingTemplate.
    static let eusoShipperCarPlayWidgetRow   = Notification.Name("eusoShipperCarPlayWidgetRow")

    /// Per-zone row tap — opens the per-zone edit sheet (enable/disable
    /// toggle, widget-list reordering, fleet-policy override). Routes
    /// through carplay.setZoneEnabled which writes the per-shipper zone
    /// vector + emits a CarPlay-scene reload event.
    static let eusoShipperCarPlayZoneRow     = Notification.Name("eusoShipperCarPlayZoneRow")

    /// "Manage CarPlay integration" pointer link tap — routes into 211
    /// Settings's CarPlay card (source of truth for the per-tile vector
    /// + per-zone vector + global head-unit pairing binding).
    static let eusoShipperCarPlayManage      = Notification.Name("eusoShipperCarPlayManage")
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
        NavSlot(label: "Wallet", systemImage: "creditcard",   isCurrent: false),
        NavSlot(label: "Me",     systemImage: "person.fill",  isCurrent: true),
    ]
}

struct ShipperCarPlayDashboardScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            ShipperCarPlayDashboard()
        } nav: {
            BottomNav(leading: shipperNavLeading(),
                      trailing: shipperNavTrailing(),
                      orbState: .idle)
        }
    }
}

// MARK: - Previews (Dark + Light per §11.4 doctrine)

#Preview("Shipper CarPlay Dashboard · Dark") {
    ShipperCarPlayDashboardScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
        .padding(24)
        .background(Theme.dark.bgPage)
}

#Preview("Shipper CarPlay Dashboard · Light") {
    ShipperCarPlayDashboardScreen(theme: Theme.light)
        .preferredColorScheme(.light)
        .padding(24)
        .background(Theme.light.bgPage)
}
