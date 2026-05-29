//
//  650_VesselOperatorHome.swift
//  EusoTrip — Vessel Operator · Home (KPI hero + booking overview).
//

import SwiftUI

struct VesselOperatorHomeScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselOperatorHomeBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: true),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct VesselDash: Decodable {
    let activeBookings: Int?
    let containersInTransit: Int?
    let revenue: Double?
    let avgTransitDays: Double?
}

private struct VesselCompliance650: Decodable {
    let status: String?
    let inspections: Int?
    let failedCount: Int?
    let hazmatPermits: Int?
}

private struct VesselCrewRow650: Decodable, Identifiable {
    let id: String
    let name: String?
    let role: String?
    let status: String?
}

// MARK: - Body

private struct VesselOperatorHomeBody: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    @State private var dash: VesselDash? = nil
    @State private var compliance: VesselCompliance650? = nil
    @State private var crew: [VesselCrewRow650] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    private let widgetLayoutKey = "vessel.operator.home.widgetOrder"
    private let canonicalOrder: [String] = ["bookings_overview", "compliance_status", "crew_roster", "news"]

    private func widgetRender(_ id: String) -> AnyView {
        switch id {
        case "bookings_overview":  AnyView(bookingsWidget)
        case "compliance_status":  AnyView(complianceWidget)
        case "crew_roster":        AnyView(crewWidget)
        case "news":               AnyView(NewsCarouselWidget())
        default:                   AnyView(EmptyView())
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
                            Text("Loading vessel dashboard…").font(EType.caption).foregroundStyle(palette.textSecondary)
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
                            role: "VESSEL_OPERATOR",
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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "ferry.fill")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("✦  VESSEL OPERATOR · DASHBOARD")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                if let n = dash?.activeBookings {
                    Text("\(n) active")
                        .font(EType.micro).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(headline)
                    .font(EType.display)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.65)
                Spacer(minLength: 8)
            }
            .padding(.top, Space.s2)
            Text("Vessel operations · fleet bookings + crew watch")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 2)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
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

    private func hero(_ d: VesselDash) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "ferry.fill")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("ACTIVE BOOKINGS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text("\(d.activeBookings ?? 0)")
                    .font(.system(size: 42, weight: .heavy))
                    .foregroundStyle(.white).monospacedDigit()
                HStack(spacing: 8) {
                    Text("CONTAINERS \(d.containersInTransit ?? 0)")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.white.opacity(0.18)).clipShape(Capsule())
                    if let avg = d.avgTransitDays {
                        Text(String(format: "AVG %.0fd", avg))
                            .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(.white.opacity(0.18)).clipShape(Capsule())
                    }
                    if let c = compliance, (c.failedCount ?? 0) > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8, weight: .heavy))
                            Text("\(c.failedCount ?? 0) PSC")
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

            if let c = compliance {
                let isGood = (c.failedCount ?? 0) == 0
                Image(systemName: isGood ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.30))
                    .padding(Space.s4)
            }
        }
    }

    // MARK: - Stat strip

    private func statStrip(_ d: VesselDash) -> some View {
        let rev = d.revenue ?? 0
        let revStr = rev >= 1_000_000
            ? String(format: "$%.1fM", rev / 1_000_000)
            : String(format: "$%.0fK", rev / 1_000)
        return HStack(spacing: Space.s2) {
            MetricTile(label: "BOOKINGS",   value: "\(d.activeBookings ?? 0)",      gradientNumeral: true)
            MetricTile(label: "CONTAINERS", value: "\(d.containersInTransit ?? 0)")
            MetricTile(label: "REVENUE",    value: revStr)
        }
    }

    // MARK: - Bookings widget

    @ViewBuilder
    private var bookingsWidget: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            widgetHeader(icon: "calendar.badge.checkmark", label: "BOOKINGS OVERVIEW", count: dash?.activeBookings)
            if loading {
                LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else if let d = dash {
                HStack(spacing: Space.s2) {
                    LifecycleStatTile(label: "ACTIVE",     value: "\(d.activeBookings ?? 0)",      icon: "calendar.badge.checkmark")
                    LifecycleStatTile(label: "CONTAINERS", value: "\(d.containersInTransit ?? 0)", icon: "shippingbox.fill")
                }
            } else {
                EusoEmptyState(systemImage: "calendar.badge.checkmark", title: "No booking data",
                               subtitle: "Active vessel bookings will appear here.")
            }
        }
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
                    LifecycleStatTile(label: "INSPECTIONS", value: "\(c.inspections ?? 0)",   icon: "doc.text.magnifyingglass")
                    LifecycleStatTile(label: "HAZMAT",      value: "\(c.hazmatPermits ?? 0)", icon: "exclamationmark.triangle")
                    LifecycleStatTile(label: "FAILED",      value: "\(c.failedCount ?? 0)",   icon: "xmark.circle",
                                      danger: (c.failedCount ?? 0) > 0)
                }
            } else {
                EusoEmptyState(systemImage: "checkmark.shield.fill", title: "No compliance data",
                               subtitle: "Vessel compliance status will appear here.")
            }
        }
    }

    // MARK: - Crew widget

    @ViewBuilder
    private var crewWidget: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            widgetHeader(icon: "person.3.fill", label: "CREW ROSTER", count: crew.isEmpty ? nil : crew.count)
            if loading {
                VStack(spacing: Space.s2) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCardSoft).frame(height: 52)
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                        .strokeBorder(palette.borderFaint))
                    }
                }
            } else if crew.isEmpty {
                EusoEmptyState(systemImage: "person.3", title: "No crew data",
                               subtitle: "Vessel crew roster will appear here.")
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(crew.prefix(5)) { member in crewRow(member) }
                }
            }
        }
    }

    private func crewRow(_ member: VesselCrewRow650) -> some View {
        let statusColor: Color = {
            switch (member.status ?? "").lowercased() {
            case "on_duty", "active": return Brand.success
            case "off_duty":          return palette.textTertiary
            case "rest":              return Brand.warning
            default:                  return palette.textTertiary
            }
        }()
        return HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(statusColor.opacity(0.14)).frame(width: 32, height: 32)
                Text(String(member.name?.prefix(2).uppercased() ?? "—"))
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(statusColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(member.name ?? "—").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(member.role ?? "—").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text((member.status ?? "—").replacingOccurrences(of: "_", with: " ").uppercased())
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .overlay(Capsule().strokeBorder(statusColor.opacity(0.5), lineWidth: 1))
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
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
            async let d: VesselDash = EusoTripAPI.shared.queryNoInput("vesselShipments.getVesselDashboard")
            async let c: VesselCompliance650 = EusoTripAPI.shared.queryNoInput("vesselShipments.getVesselCompliance")
            async let r: [VesselCrewRow650] = EusoTripAPI.shared.queryNoInput("vesselShipments.getVesselCrew")
            let (dsh, comp, roster) = try await (d, c, r)
            self.dash = dsh
            self.compliance = comp
            self.crew = roster
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("650 · Vessel Operator Home · Night")  { VesselOperatorHomeScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("650 · Vessel Operator Home · Light")  { VesselOperatorHomeScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
