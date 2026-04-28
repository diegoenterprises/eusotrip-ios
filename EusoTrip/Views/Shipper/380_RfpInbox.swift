//
//  380_RfpInbox.swift
//  EusoTrip — Shipper · RFP inbox (Arc N §1.3 expansion).
//

import SwiftUI

struct RfpInboxScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RfpInboxBody() } nav: { shipperLifecycleNav() }
    }
}

private struct RfpRow: Decodable, Identifiable, Hashable {
    let id: String
    let title: String?
    let status: String?
    let dueDate: String?
    let lanes: Int?
    let bidsReceived: Int?
}

private struct RfpInboxBody: View {
    @Environment(\.palette) private var palette
    @State private var rfps: [RfpRow] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
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
                Image(systemName: "doc.text.image").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · RFP MANAGER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Active RFPs").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Multi-lane procurement bids. View detail to award lanes inline; full composer remains on web.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading RFPs…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rfps.isEmpty { EusoEmptyState(systemImage: "doc.on.doc", title: "No active RFPs", subtitle: "Create RFPs on the web shipper page; they'll show up here for review and awarding.") }
        else {
            ForEach(rfps) { r in
                Button {
                    NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "381", "rfpId": r.id])
                } label: {
                    LifecycleCard {
                        LifecycleSection(label: dashIfEmpty(r.title?.uppercased()), icon: "doc.text")
                        LifecycleRow(label: "Status",   value: dashIfEmpty(r.status?.uppercased()))
                        LifecycleRow(label: "Due",      value: humanISO(r.dueDate))
                        LifecycleRow(label: "Lanes",    value: r.lanes.map { "\($0)" } ?? "—")
                        LifecycleRow(label: "Bids in",  value: r.bidsReceived.map { "\($0)" } ?? "—")
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [RfpRow] = try await EusoTripAPI.shared.api.queryNoInput("rfpManager.getRFPs")
            rfps = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("380 · RFP inbox · Night") { RfpInboxScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("380 · RFP inbox · Afternoon") { RfpInboxScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
