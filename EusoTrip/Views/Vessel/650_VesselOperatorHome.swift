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
}

private struct VesselCompliance: Decodable {
    let status: String?
    let inspections: Int?
    let failedCount: Int?
    let hazmatPermits: Int?
}

private struct VesselCrewRow: Decodable, Identifiable {
    let id: String
    let name: String?
    let role: String?
    let status: String?
}

// MARK: - Body

private struct VesselOperatorHomeBody: View {
    @Environment(\.palette) private var palette
    @State private var dash: VesselDash? = nil
    @State private var compliance: VesselCompliance? = nil
    @State private var crew: [VesselCrewRow] = []
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
            VStack(alignment: .leading, spacing: Space.s4) {
                header
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
                    statsGrid(d)
                    HomeWidgetGrid(
                        canonicalOrder: canonicalOrder,
                        role: "VESSEL_OPERATOR",
                        storageKey: widgetLayoutKey,
                        render: { id in widgetRender(id) }
                    )
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "ferry.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · HOME")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Vessel operations").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func hero(_ d: VesselDash) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACTIVE BOOKINGS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(.white.opacity(0.85))
            Text("\(d.activeBookings ?? 0)")
                .font(.system(size: 36, weight: .heavy))
                .foregroundStyle(.white).monospacedDigit()
            HStack(spacing: 8) {
                Text("CONTAINERS \(d.containersInTransit ?? 0)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white.opacity(0.18)).clipShape(Capsule())
                if let rev = d.revenue {
                    let revStr = rev >= 1_000_000
                        ? String(format: "$%.1fM", rev / 1_000_000)
                        : String(format: "$%.0fK", rev / 1_000)
                    Text(revStr)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(0.18)).clipShape(Capsule())
                }
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.diagonal)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func statsGrid(_ d: VesselDash) -> some View {
        let rev = d.revenue ?? 0
        let revStr = rev >= 1_000_000
            ? String(format: "$%.1fM", rev / 1_000_000)
            : String(format: "$%.0fK", rev / 1_000)
        return HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "BOOKINGS",   value: "\(d.activeBookings ?? 0)",      icon: "calendar.badge.checkmark")
            LifecycleStatTile(label: "CONTAINERS", value: "\(d.containersInTransit ?? 0)", icon: "shippingbox.fill")
            LifecycleStatTile(label: "REVENUE",    value: revStr,                           icon: "dollarsign.circle")
        }
    }

    // MARK: - Bookings widget

    @ViewBuilder
    private var bookingsWidget: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("BOOKINGS OVERVIEW")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if let n = dash?.activeBookings {
                    Text("\(n)").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                }
            }
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
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("COMPLIANCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if let status = compliance?.status {
                    Text(status.uppercased())
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(status.lowercased() == "compliant" ? Brand.success : Brand.warning)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .overlay(Capsule().strokeBorder(
                            (status.lowercased() == "compliant" ? Brand.success : Brand.warning).opacity(0.5), lineWidth: 1))
                }
            }
            if loading {
                LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else if let c = compliance {
                HStack(spacing: Space.s2) {
                    LifecycleStatTile(label: "INSPECTIONS",   value: "\(c.inspections ?? 0)",   icon: "doc.text.magnifyingglass")
                    LifecycleStatTile(label: "HAZMAT",        value: "\(c.hazmatPermits ?? 0)", icon: "exclamationmark.triangle")
                    LifecycleStatTile(label: "FAILED",        value: "\(c.failedCount ?? 0)",   icon: "xmark.circle",
                                      danger: (c.failedCount ?? 0) > 0)
                }
            } else {
                EusoEmptyState(systemImage: "checkmark.shield.fill", title: "No compliance data",
                               subtitle: "Vessel compliance status will appear here.")
            }
        }
    }

    // MARK: - Crew roster widget

    @ViewBuilder
    private var crewWidget: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CREW ROSTER")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if !crew.isEmpty {
                    Text("\(crew.count)").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                }
            }
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

    private func crewRow(_ member: VesselCrewRow) -> some View {
        let statusColor: Color = {
            switch (member.status ?? "").lowercased() {
            case "on_duty", "active": return Brand.success
            case "off_duty":          return palette.textTertiary
            case "rest":              return Brand.warning
            default:                  return palette.textTertiary
            }
        }()
        return HStack(spacing: Space.s3) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
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

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        do {
            async let d: VesselDash = EusoTripAPI.shared.queryNoInput("vesselShipments.getVesselDashboard")
            async let c: VesselCompliance = EusoTripAPI.shared.queryNoInput("vesselShipments.getVesselCompliance")
            async let r: [VesselCrewRow] = EusoTripAPI.shared.queryNoInput("vesselShipments.getVesselCrew")
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
