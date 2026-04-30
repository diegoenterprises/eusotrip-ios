//
//  293_SettlementDetail.swift
//  EusoTrip — Shipper · Settlement detail (Arc G).
//  Backed by `earnings.getSettlementById`.
//

import SwiftUI

struct SettlementDetailScreen: View {
    let theme: Theme.Palette
    let settlementId: String
    var body: some View {
        Shell(theme: theme) { SettlementDetailBody(settlementId: settlementId) } nav: { shipperLifecycleNav() }
    }
}

private struct SettlementDetail: Decodable, Hashable {
    let id: String
    let status: String?
    let amount: Double?
    let payableDate: String?
    let paidAt: String?
    let invoiceUrl: String?
    let loadId: String?
    let loadNumber: String?
    let breakdown: [String: Double]?
}

private struct SettlementDetailBody: View {
    @Environment(\.palette) private var palette
    let settlementId: String
    @State private var detail: SettlementDetail? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let d = detail { headerCard(d); breakdownCard(d); ctaRow(d) }
                else if loading { LifecycleCard { Text("Loading settlement…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
                else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.below.ecg").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · SETTLEMENT DETAIL").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(detail?.loadNumber ?? "—").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func headerCard(_ d: SettlementDetail) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "STATUS", icon: "creditcard")
            LifecycleRow(label: "Status",  value: dashIfEmpty(d.status?.uppercased()))
            LifecycleRow(label: "Amount",  value: usd(d.amount))
            LifecycleRow(label: "Payable", value: humanISO(d.payableDate))
            LifecycleRow(label: "Paid",    value: humanISO(d.paidAt))
        }
    }

    private func breakdownCard(_ d: SettlementDetail) -> some View {
        LifecycleCard {
            LifecycleSection(label: "BREAKDOWN", icon: "list.bullet")
            if let bk = d.breakdown, !bk.isEmpty {
                ForEach(bk.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                    LifecycleRow(label: k, value: usd(v))
                }
            } else {
                Text("Breakdown not yet available.").font(EType.caption).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func ctaRow(_ d: SettlementDetail) -> some View {
        HStack(spacing: 10) {
            if let u = d.invoiceUrl, !u.isEmpty {
                Button {
                    if let url = URL(string: u) { UIApplication.shared.open(url) }
                } label: {
                    Text("Open invoice")
                        .font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }.buttonStyle(.plain)
            }
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "294", "settlementId": d.id])
            } label: {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 13, weight: .heavy)).foregroundStyle(Brand.warning)
                    .frame(width: 44, height: 44).background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.warning.opacity(0.5), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let settlementId: String }
        do {
            let d: SettlementDetail = try await EusoTripAPI.shared.query("earnings.getSettlementById", input: In(settlementId: settlementId))
            detail = d
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("293 · Settlement detail · Night") {
    SettlementDetailScreen(theme: Theme.dark, settlementId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("293 · Settlement detail · Afternoon") {
    SettlementDetailScreen(theme: Theme.light, settlementId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
