//
//  669_RailOverchargeRecovery.swift
//  EusoTrip - Rail Engineer - Overcharge Recovery.
//
//  Mode-scoped freight-audit recovery truth. Rail currently has no modeled
//  recovery source, so the API returns null values with explicit provenance.
//

import SwiftUI

private struct OverchargeInput669: Encodable {
    let transportMode: String
    let limit: Int
    let offset: Int
}

private struct RecoveryRow669: Decodable, Identifiable {
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

private struct RecoverySummary669: Decodable {
    let totalIdentified: Double?
    let totalRecovered: Double?
    let pendingRecovery: Double?
    let recoveryRate: Double?
    let avgRecoveryDays: Double?
    let totalCurrency: String?
    let unvaluedCount: Int?
}

private struct RecoveryTracking669: Decodable {
    let tracked: Bool
    let state: String
    let modeledModes: [String]
    let reason: String?
}

private struct RecoveryMetricStates669: Decodable {
    let total: FreightClaimsAPI.MetricTruth
    let totalIdentified: FreightClaimsAPI.MetricTruth
    let totalRecovered: FreightClaimsAPI.MetricTruth
    let pendingRecovery: FreightClaimsAPI.MetricTruth
    let recoveryRate: FreightClaimsAPI.MetricTruth
    let avgRecoveryDays: FreightClaimsAPI.MetricTruth
}

private struct RecoveryPageScope669: Decodable {
    let kind: String
    let offset: Int
    let limit: Int
    let returnedCount: Int
    let totalMatching: Int?
    let status: String?
    let transportMode: String?
}

private struct RecoveryProvenance669: Decodable {
    let source: String?
    let scope: String
    let transportMode: String?
    let observedAt: String?
    let computedAt: String
}

private struct OverchargeResp669: Decodable {
    let recoveries: [RecoveryRow669]
    let transportMode: String?
    let total: Int?
    let summary: RecoverySummary669
    let tracking: RecoveryTracking669
    let metricStates: RecoveryMetricStates669
    let pageScope: RecoveryPageScope669
    let provenance: RecoveryProvenance669
}

struct RailOverchargeRecoveryScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { RailOverchargeRecoveryBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct RailOverchargeRecoveryBody: View {
    @Environment(\.palette) private var palette
    @State private var response: OverchargeResp669?
    @State private var loading = true
    @State private var loadError: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header
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
                    recoveryRows(response)
                    Button { Task { await load() } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(palette.bgCard)
                            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
                    }
                    .buttonStyle(.plain)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                EusoTripEyebrow(verbatim: "RAIL ENGINEER · FREIGHT AUDIT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("RECOVERY").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            Text("Overcharge recovery").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
            IridescentHairline()
        }
    }

    private func sourceContract(_ value: OverchargeResp669) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: 7) {
                Text(value.tracking.tracked ? "TRACKED SOURCE" : "NOT MODELED FOR RAIL")
                    .font(EType.micro)
                    .foregroundStyle(value.tracking.tracked ? Brand.success : Brand.warning)
                Text(value.tracking.tracked ? "Recovery evidence" : "Recovery metrics unavailable")
                    .font(.system(size: 21, weight: .bold)).foregroundStyle(palette.textPrimary)
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
            Text(value).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func recoveryRows(_ value: OverchargeResp669) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECOVERY RECORDS · CURRENT PAGE").font(EType.micro).foregroundStyle(palette.textTertiary)
            if value.recoveries.isEmpty {
                EusoEmptyState(
                    systemImage: "doc.text.magnifyingglass",
                    title: value.tracking.tracked ? "No matching recovery observations" : "Rail recovery tracking is not modeled",
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
    }

    private func recoveryRow(_ row: RecoveryRow669) -> some View {
        let tone = statusColor(row.status)
        return HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(tone.opacity(0.14)).frame(width: 40, height: 40)
                .overlay(Image(systemName: "doc.text").foregroundStyle(tone))
            VStack(alignment: .leading, spacing: 4) {
                Text(row.carrier).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("\(row.invoiceNumber) · \(row.type.replacingOccurrences(of: "_", with: " "))")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textSecondary).lineLimit(1)
                Text("Identified \(money(row.overchargeAmount, currency: row.currency))")
                    .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                Text("Recovered \(money(row.recoveredAmount, currency: row.currency))")
                    .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(row.status.replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(EType.micro).foregroundStyle(tone)
                Text(row.currency ?? "currency unavailable").font(.system(size: 9))
                    .foregroundStyle(row.currency == nil ? Brand.warning : palette.textTertiary)
            }
        }
        .padding(.vertical, 10)
    }

    private func money(_ value: Double?, currency: String?) -> String {
        guard let value, let currency else { return "Unavailable" }
        return value.formatted(.currency(code: currency))
    }

    private func provenanceLabel(_ value: RecoveryProvenance669) -> String {
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
                input: OverchargeInput669(transportMode: "RAIL", limit: 20, offset: 0)
            )
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }
}

#Preview("669 · Overcharge recovery · Light") {
    RailOverchargeRecoveryScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
#Preview("669 · Overcharge recovery · Night") {
    RailOverchargeRecoveryScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
