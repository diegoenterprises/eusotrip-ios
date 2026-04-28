//
//  303_EusoTicketBol.swift
//  EusoTrip — Shipper · EusoTicket BOL (Arc H).
//  Backed by `eusoTicket.generateBOL` (existing).
//

import SwiftUI

struct EusoTicketBolScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) { EusoTicketBolBody(loadId: loadId) } nav: { shipperLifecycleNav() }
    }
}

private struct BolDetail: Decodable, Hashable {
    let id: Int
    let pdfUrl: String?
    let status: String?
    let qrCode: String?
}

private struct EusoTicketBolBody: View {
    @Environment(\.palette) private var palette
    let loadId: String
    @State private var bol: BolDetail? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let b = bol { heroCard(b); ctaRow(b) }
                else if loading { LifecycleCard { Text("Generating BOL…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
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
                Image(systemName: "ticket.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("EUSOTICKET · BOL").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Bill of lading").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func heroCard(_ b: BolDetail) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "STATUS", icon: "checkmark.shield.fill")
            LifecycleRow(label: "BOL ID",  value: "BOL-\(b.id)")
            LifecycleRow(label: "Status",  value: dashIfEmpty(b.status?.uppercased()))
        }
    }

    private func ctaRow(_ b: BolDetail) -> some View {
        HStack(spacing: 10) {
            if let pdf = b.pdfUrl, !pdf.isEmpty {
                Button {
                    if let url = URL(string: pdf) { UIApplication.shared.open(url) }
                } label: {
                    Text("Open PDF").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(LinearGradient.diagonal)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }.buttonStyle(.plain)
            }
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "306", "loadId": loadId])
            } label: {
                Image(systemName: "signature").font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    .frame(width: 44, height: 44).background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let loadId: Int }
        let n = Int(loadId.replacingOccurrences(of: "load_", with: "")) ?? 0
        do {
            let b: BolDetail = try await EusoTripAPI.shared.api.mutation("eusoTicket.generateBOL", input: In(loadId: n))
            bol = b
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("303 · EusoTicket BOL · Night") {
    EusoTicketBolScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("303 · EusoTicket BOL · Afternoon") {
    EusoTicketBolScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
