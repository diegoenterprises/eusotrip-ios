//
//  550_RailEngineerHome.swift
//  EusoTrip — Rail Engineer · Home (KPI hero + dashboard).
//

import SwiftUI

struct RailEngineerHomeScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailEngineerHomeBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: true),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct RailDash: Decodable {
    let activeShipments: Int?
    let carsInTransit: Int?
    let avgTransitDays: Double?
    let revenue: Double?
}

private struct RailCompliance550: Decodable {
    let inspections: Int?
    let hazmatPermits: Int?
    let status: String?
    let totalInspections: Int?
    let failedCount: Int?
}

private struct RailCrewHOS550: Decodable {
    let onDuty: Int?
    let offDuty: Int?
    let approaching: Int?
}

// MARK: - Body

private struct RailEngineerHomeBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    @State private var dash: RailDash? = nil
    @State private var compliance: RailCompliance550? = nil
    @State private var crewHOS: RailCrewHOS550? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private let widgetLayoutKey = "rail.engineer.home.widgetOrder"
    private let canonicalOrder: [String] = ["shipments_overview", "compliance_status", "crew_hos", "news"]

    private func widgetRender(_ id: String) -> AnyView {
        switch id {
        case "shipments_overview":  AnyView(shipmentsWidget)
        case "compliance_status":   AnyView(complianceWidget)
        case "crew_hos":            AnyView(crewWidget)
        case "news":                AnyView(NewsCarouselWidget())
        default:                    AnyView(EmptyView())
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.horizontal, Space.s5)
                VStack(alignment: .leading, spacing: Space.s4) {
                    RoleHomeIntro()
                    if loading {
                        LifecycleCard {
                            Text("Loading rail dashboard…").font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else if let d = dash {
                        hero(d)
                        statStrip(d)
                        HomeWidgetGrid(
                            canonicalOrder: canonicalOrder,
                            role: "RAIL_ENGINEER",
                            storageKey: widgetLayoutKey,
                            render: { id in widgetRender(id) }
                        )
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            // Bespoke eyebrow row — gradient role chip on the left, caps
            // live fleet stat on the right. Mirrors the 550 SVG header
            // motif ("✦ RAIL ENGINEER · HOME" + "8 ACTIVE · 23 CARS")
            // and the DriverHome idiom so every role home reads as one
            // family. The sparkle glyph is the surface's single §4.3
            // accent budget.
            HStack(spacing: Space.s3) {
                Text("✦ RAIL ENGINEER · DASHBOARD")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                Text(fleetEyebrowStat)
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(alignment: .firstTextBaseline) {
                // Brand-gradient greeting reads as EusoTrip-native in both
                // Night and Afternoon, matching DriverHome's hero name and
                // the SVG's display headline rhythm (tight tracking).
                Text(headline)
                    .font(EType.display)
                    .tracking(-0.6)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(2).minimumScaleFactor(0.65)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
            }
            Text("Rail operations · in-yard consist + crew HOS")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    /// Caps fleet stat shown at the top-right of the eyebrow row. Mirrors
    /// the SVG's "8 ACTIVE · 23 CARS" — derived from the live dashboard so
    /// it stays honest (no fabricated values). Falls through to just the
    /// active count, then a neutral label while loading.
    private var fleetEyebrowStat: String {
        guard let d = dash else { return "RAIL FLEET" }
        let active = d.activeShipments ?? 0
        if let cars = d.carsInTransit {
            return "\(active) ACTIVE · \(cars) CARS"
        }
        return "\(active) ACTIVE"
    }

    private var headline: String {
        let rawFirst = session.user?.firstName
        let first: String? = rawFirst.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        let hour = Calendar.current.component(.hour, from: Date())
        let sal: String
        switch hour {
        case 5..<12:  sal = "Good morning"
        case 12..<17: sal = "Good afternoon"
        case 17..<22: sal = "Good evening"
        default:      sal = "Welcome back"
        }
        if let first { return "\(sal), \(first)" }
        return sal
    }

    // MARK: - Hero

    private func hero(_ d: RailDash) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("CARS IN TRANSIT")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text("\(d.carsInTransit ?? 0)")
                    .font(.system(size: 42, weight: .heavy))
                    .foregroundStyle(.white).monospacedDigit()
                HStack(spacing: 8) {
                    Text("ACTIVE \(d.activeShipments ?? 0)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.white.opacity(0.18)).clipShape(Capsule())
                    if let avg = d.avgTransitDays {
                        Text(String(format: "AVG %.1fd", avg))
                            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(.white.opacity(0.18)).clipShape(Capsule())
                    }
                    if let c = compliance, (c.failedCount ?? 0) > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8, weight: .heavy))
                            Text("\(c.failedCount ?? 0) FAILED")
                                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Brand.danger.opacity(0.35)).clipShape(Capsule())
                    }
                }
            }
            .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            // Subtle compliance dot in top-right
            if let c = compliance {
                let isGood = (c.failedCount ?? 0) == 0
                Image(systemName: isGood ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.30))
                    .padding(Space.s4)
            }
        }
    }

    // MARK: - Stat strip (MetricTile row)

    private func statStrip(_ d: RailDash) -> some View {
        let rev = d.revenue ?? 0
        let revStr = rev >= 1_000_000
            ? String(format: "$%.1fM", rev / 1_000_000)
            : String(format: "$%.0fK", rev / 1_000)
        return HStack(spacing: Space.s2) {
            MetricTile(label: "SHIPMENTS", value: "\(d.activeShipments ?? 0)", gradientNumeral: true)
            MetricTile(label: "CARS",      value: "\(d.carsInTransit ?? 0)")
            MetricTile(label: "REVENUE",   value: revStr)
        }
    }

    // MARK: - Shipments widget

    @ViewBuilder
    private var shipmentsWidget: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            widgetHeader(icon: "shippingbox.fill", label: "ACTIVE SHIPMENTS", count: dash?.activeShipments)
            if loading {
                LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else if let d = dash {
                HStack(spacing: Space.s2) {
                    LifecycleStatTile(label: "ACTIVE",  value: "\(d.activeShipments ?? 0)", icon: "shippingbox")
                    LifecycleStatTile(label: "CARS",    value: "\(d.carsInTransit ?? 0)",   icon: "tram.fill")
                    if let avg = d.avgTransitDays {
                        LifecycleStatTile(label: "AVG DAYS", value: String(format: "%.1f", avg), icon: "clock")
                    }
                }
            } else {
                EusoEmptyState(systemImage: "shippingbox", title: "No shipment data",
                               subtitle: "Active rail shipments will appear here.")
            }
        }
        // Bespoke EusoCard surface — iridescent blue→magenta rim + glow,
        // matching the SVG card language and the DriverHome widget idiom
        // (replaces the flat, surface-less VStack).
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: - Compliance widget

    @ViewBuilder
    private var complianceWidget: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            widgetHeader(icon: "checkmark.shield.fill", label: "COMPLIANCE",
                         badge: compliance?.status)
            if loading {
                LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else if let c = compliance {
                HStack(spacing: Space.s2) {
                    LifecycleStatTile(label: "INSPECTIONS",    value: "\(c.totalInspections ?? c.inspections ?? 0)", icon: "doc.text.magnifyingglass")
                    LifecycleStatTile(label: "HAZMAT PERMITS", value: "\(c.hazmatPermits ?? 0)",                     icon: "exclamationmark.triangle")
                    LifecycleStatTile(label: "FAILED",         value: "\(c.failedCount ?? 0)",                       icon: "xmark.circle",
                                      danger: (c.failedCount ?? 0) > 0)
                }
            } else {
                EusoEmptyState(systemImage: "checkmark.shield", title: "No compliance data",
                               subtitle: "Rail compliance status will appear here.")
            }
        }
        // Bespoke EusoCard surface — matches the shipments widget so the
        // secondary-widget zone reads as a stack of iridescent-rimmed cards.
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: - Crew widget

    @ViewBuilder
    private var crewWidget: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            widgetHeader(icon: "person.2.fill", label: "CREW HOS", count: (crewHOS?.onDuty ?? 0) + (crewHOS?.offDuty ?? 0))
            if loading {
                LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else if let h = crewHOS {
                HStack(spacing: Space.s2) {
                    LifecycleStatTile(label: "ON DUTY",    value: "\(h.onDuty ?? 0)",     icon: "checkmark.circle")
                    LifecycleStatTile(label: "OFF DUTY",   value: "\(h.offDuty ?? 0)",    icon: "moon.fill")
                    LifecycleStatTile(label: "NEAR LIMIT", value: "\(h.approaching ?? 0)", icon: "exclamationmark.circle",
                                      danger: (h.approaching ?? 0) > 0)
                }
            } else {
                EusoEmptyState(systemImage: "person.2", title: "No crew data",
                               subtitle: "Crew hours of service will appear here.")
            }
        }
        // Bespoke EusoCard surface — keeps the crew HOS widget in the same
        // iridescent-rim card family as shipments + compliance.
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: - Widget header helper

    private func widgetHeader(icon: String, label: String, count: Int? = nil, badge: String? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            if let badge {
                let isGood = badge.lowercased() == "compliant"
                Text(badge.uppercased())
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(isGood ? Brand.success : Brand.warning)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder((isGood ? Brand.success : Brand.warning).opacity(0.5), lineWidth: 1))
            } else if let count {
                Text("\(count)").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
            }
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        do {
            async let d: RailDash = EusoTripAPI.shared.queryNoInput("railShipments.getRailDashboardStats")
            async let c: RailCompliance550 = EusoTripAPI.shared.queryNoInput("railShipments.getRailCompliance")
            async let h: RailCrewHOS550 = EusoTripAPI.shared.queryNoInput("railShipments.getCrewHOS")
            let (dash, comp, crew) = try await (d, c, h)
            self.dash = dash
            self.compliance = comp
            self.crewHOS = crew
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("550 · Rail Engineer Home · Night")  { RailEngineerHomeScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("550 · Rail Engineer Home · Light")  { RailEngineerHomeScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
