//
//  313_CarrierSettlementsList.swift
//  EusoTrip — Carrier · Settlements list (incoming).
//

import SwiftUI

struct CarrierSettlementsListScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { CSettlementsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Bids", systemImage: "hand.raised.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

private struct CarrierSettlement: Decodable, Identifiable, Hashable {
    let id: String
    let loadNumber: String?
    let amount: Double?
    let payableDate: String?
    let paidAt: String?
    let status: String
}

private struct CSettlementsBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [CarrierSettlement] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var filter: String = "all"

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
                Text("CARRIER · SETTLEMENTS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Settlements").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var filterStrip: some View {
        HStack(spacing: 6) {
            ForEach([("all", "All"), ("pending", "Pending"), ("approved", "Approved"), ("paid", "Paid")], id: \.0) { f in
                Button { Task { filter = f.0; await load() } } label: {
                    Text(f.1).font(.system(size: 11, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(filter == f.0 ? .white : palette.textPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(filter == f.0 ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.tintNeutral))
                        .clipShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rows.isEmpty { EusoEmptyState(systemImage: "tray", title: "No settlements", subtitle: "Once loads close, settlements land here.") }
        else {
            ForEach(rows) { r in
                Button {
                    NotificationCenter.default.post(name: .eusoCarrierNavSwap, object: nil, userInfo: ["screenId": "321", "settlementId": r.id])
                } label: {
                    LifecycleCard(accentGradient: r.status == "paid") {
                        LifecycleSection(label: dashIfEmpty(r.loadNumber).uppercased(), icon: "doc.text")
                        LifecycleRow(label: "Amount",   value: usd(r.amount))
                        LifecycleRow(label: "Status",   value: r.status.uppercased())
                        LifecycleRow(label: "Payable",  value: humanISO(r.payableDate))
                        LifecycleRow(label: "Paid",     value: humanISO(r.paidAt))
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let status: String? }
        do {
            let r: [CarrierSettlement] = try await EusoTripAPI.shared.query("catalysts.getSettlements", input: In(status: filter == "all" ? nil : filter))
            rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("313 · Settlements · Night") { CarrierSettlementsListScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("313 · Settlements · Afternoon") { CarrierSettlementsListScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
