//
//  804_VesselOverchargeRecovery.swift
//  EusoTrip - Vessel Operator - Overcharge Recovery.
//
//  Mode-scoped freight-audit recovery truth. Vessel currently has no modeled
//  recovery source, so the API returns null values with explicit provenance.
//

import SwiftUI

private struct OverchargeInput804: Encodable {
    let transportMode: String
    let limit: Int
    let offset: Int
}

private struct RecoveryRow804: Decodable, Identifiable {
    let id: String
    let invoiceNumber: String
    let carrier: String
    let overchargeAmount: Double?
    let recoveredAmount: Double?
    let currency: String?
    let transportMode: String
    let status: String
    let identifiedDate: String
    let recoveredDate: String?
    let type: String
}

private struct RecoverySummary804: Decodable {
    let totalIdentified: Double?
    let totalRecovered: Double?
    let pendingRecovery: Double?
    let recoveryRate: Double?
    let avgRecoveryDays: Double?
    let totalCurrency: String?
    let unvaluedCount: Int?
}

private struct RecoveryTracking804: Decodable {
    let tracked: Bool
    let state: String
    let modeledModes: [String]
    let reason: String?
}

private struct RecoveryMetricStates804: Decodable {
    let total: FreightClaimsAPI.MetricTruth
    let totalIdentified: FreightClaimsAPI.MetricTruth
    let totalRecovered: FreightClaimsAPI.MetricTruth
    let pendingRecovery: FreightClaimsAPI.MetricTruth
    let recoveryRate: FreightClaimsAPI.MetricTruth
    let avgRecoveryDays: FreightClaimsAPI.MetricTruth
}

private struct RecoveryPageScope804: Decodable {
    let kind: String
    let offset: Int
    let limit: Int
    let returnedCount: Int
    let totalMatching: Int?
    let status: String?
    let transportMode: String?
}

private struct RecoveryProvenance804: Decodable {
    let source: String?
    let scope: String
    let transportMode: String?
    let observedAt: String?
    let computedAt: String
}

private struct OverchargeResp804: Decodable {
    let recoveries: [RecoveryRow804]
    let transportMode: String?
    let total: Int?
    let summary: RecoverySummary804
    let tracking: RecoveryTracking804
    let metricStates: RecoveryMetricStates804
    let pageScope: RecoveryPageScope804
    let provenance: RecoveryProvenance804
}

struct VesselOverchargeRecoveryScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { VesselOverchargeRecoveryBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselOverchargeRecoveryBody: View {
    @Environment(\.palette) private var palette
    @State private var response: OverchargeResp804?
    @State private var loading = true
    @State private var loadError: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("Overcharge recovery").font(.system(size: 30, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("Mode-scoped recovery truth").font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()
                if loading {
                    LifecycleCard {
                        Text("Loading recovery evidence...").font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if let loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(loadError).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else if let response {
                    sourceContract(response)
                    Text("RECOVERY RECORDS · CURRENT PAGE").font(EType.micro).foregroundStyle(palette.textTertiary)
                    recoveryRows(response)
                    CTAButton(title: "Refresh", action: { Task { await load() } }, trailingIcon: "arrow.clockwise")
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            EusoTripBrandMark(size: 12).foregroundStyle(LinearGradient.diagonal)
            Text("VESSEL OPERATOR · OVERCHARGE RECOVERY").font(.system(size: 9, weight: .heavy))
                .tracking(1).foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text("RECOVERY").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
        }
    }

    private func sourceContract(_ value: OverchargeResp804) -> some View {
        RimCard804 {
            VStack(alignment: .leading, spacing: 7) {
                Text(value.tracking.tracked ? "TRACKED SOURCE" : "NOT MODELED FOR VESSEL")
                    .font(EType.micro)
                    .foregroundStyle(value.tracking.tracked ? Brand.success : Brand.warning)
                Text(value.tracking.tracked ? "Recovery evidence" : "Recovery metrics unavailable")
                    .font(.system(size: 20, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(value.tracking.reason ?? value.metricStates.total.reason ?? "No source is configured for this metric.")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                Divider().overlay(palette.borderFaint)
                HStack {
                    contractMetric("ROWS RETURNED", "\(value.pageScope.returnedCount)")
                    contractMetric("TOTAL MATCHING", value.total.map(String.init) ?? "Unavailable")
                    contractMetric("PAGE SCOPE", value.pageScope.kind.replacingOccurrences(of: "_", with: " ").capitalized)
                }
                Text(provenanceLabel(value.provenance))
                    .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
            }
        }
    }

    private func contractMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(EType.micro).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func recoveryRows(_ value: OverchargeResp804) -> some View {
        if value.recoveries.isEmpty {
            EusoEmptyState(
                systemImage: "tray",
                title: value.tracking.tracked ? "No matching recovery observations" : "Vessel recovery tracking is not modeled",
                subtitle: value.tracking.reason ?? value.metricStates.total.reason ?? "No source is configured for this metric."
            )
        } else {
            LifecycleCard {
                VStack(spacing: 0) {
                    ForEach(Array(value.recoveries.enumerated()), id: \.element.id) { index, row in
                        recoveryRow(row)
                        if index < value.recoveries.count - 1 { Divider().overlay(palette.borderFaint) }
                    }
                }
            }
        }
    }

    private func recoveryRow(_ row: RecoveryRow804) -> some View {
        let tone = statusColor(row.status)
        return HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(tone.opacity(0.14)).frame(width: 40, height: 40)
                .overlay(Text(String(row.carrier.uppercased().prefix(4)))
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(tone))
            VStack(alignment: .leading, spacing: 4) {
                Text("\(row.carrier) · \(row.type.replacingOccurrences(of: "_", with: " "))")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("\(row.invoiceNumber) · \(row.status)")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textSecondary).lineLimit(1)
                Text("Identified \(money(row.overchargeAmount, currency: row.currency))")
                    .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                Text("Recovered \(money(row.recoveredAmount, currency: row.currency))")
                    .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text(row.status.replacingOccurrences(of: "_", with: " ").uppercased())
                .font(EType.micro).foregroundStyle(tone)
        }
        .padding(.vertical, 10)
    }

    private func money(_ value: Double?, currency: String?) -> String {
        guard let value, let currency else { return "Unavailable" }
        return value.formatted(.currency(code: currency))
    }

    private func provenanceLabel(_ value: RecoveryProvenance804) -> String {
        guard let source = value.source else { return "No source · evaluated \(value.computedAt)" }
        return "\(source) · observed \(value.observedAt ?? "time unavailable") · calculated \(value.computedAt)"
    }

    private func statusColor(_ value: String) -> Color {
        switch value {
        case "recovered": return Brand.success
        case "disputed": return Brand.warning
        case "written_off": return Brand.danger
        default: return Brand.info
        }
    }

    private func load() async {
        loading = true
        loadError = nil
        do {
            response = try await EusoTripAPI.shared.query(
                "freightClaims.getOverchargeRecovery",
                input: OverchargeInput804(transportMode: "VESSEL", limit: 20, offset: 0)
            )
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }
}

private struct RimCard804<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content

    var body: some View {
        content().padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard).clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }
}

#Preview("804 · Overcharge Recovery · Night") {
    VesselOverchargeRecoveryScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("804 · Overcharge Recovery · Light") {
    VesselOverchargeRecoveryScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
