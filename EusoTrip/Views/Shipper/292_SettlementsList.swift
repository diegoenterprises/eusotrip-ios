//
//  292_SettlementsList.swift
//  EusoTrip — Shipper · Settlements list (Arc G).
//  Backed by `earnings.getSettlementHistory`.
//

import SwiftUI

struct SettlementsListScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { SettlementsListBody() } nav: { shipperLifecycleNav() }
    }
}

private struct SettlementRow: Decodable, Identifiable, Hashable {
    let id: String
    let status: String?
    let amount: Double?
    let payableDate: String?
    let paidAt: String?
    let loadId: String?
    let loadNumber: String?
}

private struct SettlementsListBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [SettlementRow] = []
    @State private var statusFilter: String? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private let filters: [(String?, String)] = [
        (nil, "All"), ("pending", "Pending"), ("approved", "Approved"), ("paid", "Paid"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                filterStrip
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "creditcard.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · SETTLEMENTS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Settlements").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(filters, id: \.1) { f in
                    Button { Task { statusFilter = f.0; await load() } } label: {
                        Text(f.1).font(.system(size: 11, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(statusFilter == f.0 ? .white : palette.textPrimary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(statusFilter == f.0 ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.tintNeutral))
                            .clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            LifecycleCard { Text("Loading settlements…").font(EType.caption).foregroundStyle(palette.textSecondary) }
        } else if let err = loadError {
            LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
        } else if rows.isEmpty {
            EusoEmptyState(systemImage: "tray", title: "No settlements", subtitle: statusFilter.map { "Nothing matches the \($0) filter." } ?? "No settlements have been built yet.")
        } else {
            ForEach(rows) { row in
                Button {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "293", "settlementId": row.id])
                } label: {
                    LifecycleCard {
                        LifecycleSection(label: dashIfEmpty(row.loadNumber).uppercased(), icon: "doc.text")
                        LifecycleRow(label: "Status",   value: dashIfEmpty(row.status?.uppercased()))
                        LifecycleRow(label: "Amount",   value: usd(row.amount))
                        LifecycleRow(label: "Payable",  value: humanISO(row.payableDate))
                        LifecycleRow(label: "Paid",     value: humanISO(row.paidAt))
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let status: String? }
        do {
            let r: [SettlementRow] = try await EusoTripAPI.shared.api.query(
                "earnings.getSettlementHistory",
                input: In(status: statusFilter)
            )
            rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("292 · Settlements list · Night") {
    SettlementsListScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("292 · Settlements list · Afternoon") {
    SettlementsListScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
