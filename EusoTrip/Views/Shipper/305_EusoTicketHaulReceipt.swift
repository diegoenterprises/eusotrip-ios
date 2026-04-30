//
//  305_EusoTicketHaulReceipt.swift
//  EusoTrip — Shipper · EusoTicket · Haul receipt (Arc H).
//

import SwiftUI

struct EusoTicketHaulReceiptScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) { HaulReceiptBody(loadId: loadId) } nav: { shipperLifecycleNav() }
    }
}

private struct HaulReceipt: Decodable, Hashable {
    let id: Int
    let pdfUrl: String?
    let lineHaul: Double?
    let accessorials: Double?
    let fuel: Double?
    let platformFee: Double?
    let total: Double?
}

private struct HaulReceiptBody: View {
    @Environment(\.palette) private var palette
    let loadId: String
    @State private var receipt: HaulReceipt? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let r = receipt { card(r); ctaRow(r) }
                else if loading { LifecycleCard { Text("Loading receipt…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
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
                Image(systemName: "receipt.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("EUSOTICKET · HAUL RECEIPT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Haul receipt").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func card(_ r: HaulReceipt) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "BREAKDOWN", icon: "list.bullet")
            LifecycleRow(label: "Line haul",     value: usd(r.lineHaul))
            LifecycleRow(label: "Accessorials",  value: usd(r.accessorials))
            LifecycleRow(label: "Fuel surcharge", value: usd(r.fuel))
            LifecycleRow(label: "Platform fee",  value: usd(r.platformFee))
            LifecycleRow(label: "Total",          value: usd(r.total))
        }
    }

    private func ctaRow(_ r: HaulReceipt) -> some View {
        if let pdf = r.pdfUrl, !pdf.isEmpty {
            return AnyView(Button {
                if let url = URL(string: pdf) { UIApplication.shared.open(url) }
            } label: {
                Text("Open PDF").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain))
        }
        return AnyView(EmptyView())
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let loadId: Int }
        let n = Int(loadId.replacingOccurrences(of: "load_", with: "")) ?? 0
        do {
            let r: HaulReceipt = try await EusoTripAPI.shared.query("eusoTicket.getHaulReceipt", input: In(loadId: n))
            receipt = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("305 · Haul receipt · Night") {
    EusoTicketHaulReceiptScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("305 · Haul receipt · Afternoon") {
    EusoTicketHaulReceiptScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
