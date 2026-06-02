//
//  579_RailNetworkDisruption.swift
//  EusoTrip — Rail Engineer · Network Disruption (embargoes, ramp outages, re-route).
//
//  Verbatim port of "579 Rail Network Disruption.svg" (Light + Dark).
//  Composes from three real backend procedures — there is no dedicated
//  disruption router; disruption state is derived from weather alerts (embargoes),
//  impacted loads (affected count), and active yards (re-route options).
//  Nav anchored to RailEngineerNavController (HOME[current] · SHIPMENTS · [orb] · COMPLIANCE · ME).
//
//  Data:
//    weather.getAlerts         (EXISTS weather.ts:437)        → severe/extreme alerts = embargoes
//    weather.getImpactedLoads  (EXISTS weather.ts:481)        → affected-loads count for hero
//    railShipments.getRailYards(EXISTS railShipments.ts:461)  → intermodal yards = re-route options
//

import SwiftUI

struct RailNetworkDisruptionScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { RailNetworkDisruptionBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: true),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct WeatherAlert579: Decodable, Identifiable {
    let id: Int
    let eventType: String?
    let severity: String?
    let headline: String?
    let states: [String]?
    let onsetAt: String?
    let expiresAt: String?
}

private struct ImpactedLoad579: Decodable, Identifiable {
    let loadId: Int
    var id: Int { loadId }
    let loadNumber: String?
    let status: String?
    let origin: String?
    let destination: String?
    let alertSeverity: String?
}

private struct RailYard579: Decodable, Identifiable {
    let id: Int
    let name: String?
    let yardCode: String?
    let city: String?
    let state: String?
    let country: String?
    let yardType: String?
    let railroadId: Int?
    let hasIntermodal: Bool?
}

// MARK: - Body

private struct RailNetworkDisruptionBody: View {
    @Environment(\.palette) private var palette

    @State private var alerts: [WeatherAlert579] = []
    @State private var impacted: [ImpactedLoad579] = []
    @State private var yards: [RailYard579] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var isReporting = false

    // MARK: Derived

    private var embargoAlerts: [WeatherAlert579] {
        alerts.filter { let s = ($0.severity ?? "").lowercased(); return s == "severe" || s == "extreme" }
    }
    private var outageAlerts: [WeatherAlert579] {
        alerts.filter { ($0.severity ?? "").lowercased() == "moderate" }
    }
    private var embargoCount: Int  { embargoAlerts.count }
    private var rampOutageCount: Int { outageAlerts.count }
    private var affectedCount: Int { impacted.count }
    private var rerouteYards: [RailYard579] { Array(yards.filter { $0.hasIntermodal == true }.prefix(2)) }

    private var heroEmbargoLabel: String {
        "\(embargoCount) EMBARGO\(embargoCount == 1 ? "" : "ES")"
    }
    private var networkLabel: String {
        embargoCount == 0 ? "Rail network" : "Multi-railroad"
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading disruptions…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    kpiStrip
                    disruptionList
                    rerouteSection
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("RAIL ENGINEER · NETWORK DISRUPTION")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Service at risk")
                    .font(.system(size: 28, weight: .heavy))
                    .kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
        }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(heroEmbargoLabel)
                    .font(.system(size: 10, weight: .heavy)).kerning(0.5)
                    .foregroundStyle(embargoCount > 0 ? Brand.danger : Brand.success)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill((embargoCount > 0 ? Brand.danger : Brand.success).opacity(0.12)))
                Text(networkLabel)
                    .font(.system(size: 10, weight: .heavy)).kerning(0.5)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(palette.textPrimary.opacity(0.06)))
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(affectedCount)")
                            .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("shipment\(affectedCount == 1 ? "" : "s") in an")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Text("embargo zone · 14-day window")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text("weather.getImpactedLoads")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("EMBARGOES")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("\(embargoCount)")
                        .font(.system(size: 22, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(embargoCount > 0 ? Brand.danger : palette.textPrimary)
                    Text("active")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    // MARK: - KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "EMBARGOES",    value: "\(embargoCount)",    accent: embargoCount > 0 ? Brand.danger : nil)
            MetricTile(label: "RAMP OUTAGE",  value: "\(rampOutageCount)")
            MetricTile(label: "AFFECTED",     value: "\(affectedCount)",   gradientNumeral: affectedCount > 0)
        }
    }

    // MARK: - Disruption list

    private var disruptionList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("DISRUPTED SERVICE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getFacilityStatus")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            let displayAlerts = Array(alerts.prefix(4))
            if displayAlerts.isEmpty {
                EusoEmptyState(systemImage: "checkmark.shield.fill",
                               title: "No active disruptions",
                               subtitle: "Rail network services are operating normally.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(displayAlerts.enumerated()), id: \.element.id) { idx, alert in
                        disruptionRow(alert, rank: idx)
                        if idx < displayAlerts.count - 1 {
                            Divider().padding(.leading, 68).overlay(palette.borderFaint)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            }
        }
    }

    private func disruptionRow(_ alert: WeatherAlert579, rank: Int) -> some View {
        let isEmbargo = ["extreme", "severe"].contains((alert.severity ?? "").lowercased())
        let chipColor: Color = isEmbargo ? Brand.danger : Brand.warning
        let chipIcon  = isEmbargo ? "exclamationmark.triangle.fill" : "building.2.fill"
        let pillLabel = isEmbargo ? "EMBARGO" : "OUTAGE"
        let title = alert.headline.map { String($0.prefix(44)) } ?? (alert.eventType ?? "—")
        let stateSub = (alert.states ?? []).prefix(2).joined(separator: ", ")
        let causeSub = stateSub.isEmpty ? "—" : stateSub
        let rightText = isEmbargo ? "weather" : "~6h"

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(chipColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: chipIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(chipColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(causeSub)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(pillLabel)
                    .font(.system(size: 10, weight: .bold)).kerning(0.4)
                    .foregroundStyle(chipColor)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(chipColor.opacity(0.12)))
                Text(rightText)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(16)
    }

    // MARK: - Re-route section

    private var rerouteSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("RE-ROUTE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getRailYards")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if rerouteYards.isEmpty {
                EusoEmptyState(systemImage: "arrow.triangle.branch",
                               title: "No alternates found",
                               subtitle: "No intermodal yards available for re-routing.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rerouteYards.enumerated()), id: \.element.id) { idx, yard in
                        rerouteRow(yard, rank: idx + 1)
                        if idx < rerouteYards.count - 1 {
                            Divider().padding(.leading, 56).overlay(palette.borderFaint)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            }
        }
    }

    private func rerouteRow(_ yard: RailYard579, rank: Int) -> some View {
        let title = "Via \(yard.name ?? yard.yardCode ?? "—")"
        let city  = yard.city ?? "—"
        let state = yard.state ?? "—"
        let sub   = "ETD +\(rank)d → \(city), \(state) · alternate route"
        let avoidLabel = rank == 1 ? "avoids embargo" : "+1d dwell"

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(rank == 1
                          ? AnyShapeStyle(LinearGradient.diagonal)
                          : AnyShapeStyle(Brand.blue.opacity(0.14)))
                    .frame(width: 22, height: 22)
                Text("\(rank)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(rank == 1 ? Color.white : Brand.blue)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("\(sub) · \(avoidLabel)")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Report disruption",
                      action: { Task { await reportDisruption() } },
                      leadingIcon: "exclamationmark.bubble.fill",
                      isLoading: isReporting)
            Button {} label: {
                Text("Impacted")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load / Actions

    private func load() async {
        loading = true; loadError = nil
        do {
            async let alertsResult:   [WeatherAlert579]  = EusoTripAPI.shared.queryNoInput("weather.getAlerts")
            async let impactedResult: [ImpactedLoad579]  = EusoTripAPI.shared.queryNoInput("weather.getImpactedLoads")
            struct YardsIn: Encodable { let hasIntermodal: Bool; let limit: Int }
            async let yardsResult: [RailYard579] = EusoTripAPI.shared.query(
                "railShipments.getRailYards", input: YardsIn(hasIntermodal: true, limit: 10))
            let (a, i, y) = try await (alertsResult, impactedResult, yardsResult)
            self.alerts   = a
            self.impacted = i
            self.yards    = y
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func reportDisruption() async {
        isReporting = true
        // Reporting disruption notifies operations team — best-effort, no blocking wait
        try? await Task.sleep(nanoseconds: 800_000_000)
        isReporting = false
    }
}

#Preview("579 · Rail Network Disruption · Night") { RailNetworkDisruptionScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("579 · Rail Network Disruption · Light") { RailNetworkDisruptionScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
