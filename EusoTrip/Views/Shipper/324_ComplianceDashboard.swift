//
//  324_ComplianceDashboard.swift
//  EusoTrip — Shipper · Compliance dashboard (Arc J).
//

import SwiftUI

struct ComplianceDashboardScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ComplianceBody() } nav: { shipperLifecycleNav() }
    }
}

private struct ExpiringItem: Decodable, Identifiable, Hashable {
    let id: String
    let label: String
    let kind: String?
    let expiresAt: String?
    let daysRemaining: Int?
}

private struct ComplianceBody: View {
    @Environment(\.palette) private var palette
    @State private var expiring: [ExpiringItem] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                tilesRow
                expiringCard
                cellsCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · COMPLIANCE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Compliance").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var tilesRow: some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "EXPIRING", value: "\(expiring.count)", icon: "exclamationmark.triangle", danger: !expiring.isEmpty)
            LifecycleStatTile(label: "FMCSA",    value: "—", icon: "checkmark.shield")
            LifecycleStatTile(label: "INSURANCE", value: "—", icon: "umbrella")
        }
    }

    @ViewBuilder
    private var expiringCard: some View {
        if loading { LifecycleCard { Text("Loading expiring items…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if expiring.isEmpty { LifecycleCard(accentGradient: true) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill").foregroundStyle(LinearGradient.diagonal)
                Text("No expiring documents in the next 30 days.").font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        } }
        else {
            LifecycleCard(accentWarning: true) {
                LifecycleSection(label: "EXPIRING SOON", icon: "exclamationmark.triangle.fill")
                ForEach(expiring) { e in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.label).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                            Text("\(dashIfEmpty(e.kind?.uppercased())) · \(humanISO(e.expiresAt, format: "MMM d, yyyy"))").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Text("\(e.daysRemaining ?? 0) days").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(Brand.warning)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var cellsCard: some View {
        LifecycleCard {
            LifecycleSection(label: "DETAILS", icon: "list.bullet")
            link(icon: "umbrella", label: "Insurance",          screen: "325")
            link(icon: "checkmark.shield", label: "FMCSA SAFER", screen: "326")
            link(icon: "triangle.fill", label: "Hazmat audit",   screen: "327")
            link(icon: "doc",          label: "All documents",   screen: "300")
        }
    }

    private func link(icon: String, label: String, screen: String) -> some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": screen])
        } label: {
            HStack {
                Image(systemName: icon).foregroundStyle(LinearGradient.diagonal)
                Text(label).font(EType.body).foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(palette.textTertiary)
            }
            .padding(.vertical, 4)
        }.buttonStyle(.plain)
    }

    private func load() async {
        loading = true
        struct In: Encodable { let days: Int }
        do {
            let r: [ExpiringItem] = try await EusoTripAPI.shared.query("compliance.getExpiringItems", input: In(days: 30))
            expiring = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("324 · Compliance · Night") { ComplianceDashboardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("324 · Compliance · Afternoon") { ComplianceDashboardScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
