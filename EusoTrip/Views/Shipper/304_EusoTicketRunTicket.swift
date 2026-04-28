//
//  304_EusoTicketRunTicket.swift
//  EusoTrip — Shipper · EusoTicket · Run ticket (Arc H).
//

import SwiftUI

struct EusoTicketRunTicketScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) { RunTicketBody(loadId: loadId) } nav: { shipperLifecycleNav() }
    }
}

private struct RunTicketDetail: Decodable, Hashable {
    let id: Int
    let pdfUrl: String?
    let status: String?
    let legCount: Int?
    let totalMiles: Double?
}

private struct RunTicketBody: View {
    @Environment(\.palette) private var palette
    let loadId: String
    @State private var ticket: RunTicketDetail? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let t = ticket { card(t); ctaRow(t) }
                else if loading { LifecycleCard { Text("Generating run ticket…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
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
                Image(systemName: "ticket").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("EUSOTICKET · RUN TICKET").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Run ticket").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func card(_ t: RunTicketDetail) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "DETAILS", icon: "doc.text")
            LifecycleRow(label: "Ticket ID",  value: "RT-\(t.id)")
            LifecycleRow(label: "Status",     value: dashIfEmpty(t.status?.uppercased()))
            LifecycleRow(label: "Legs",       value: t.legCount.map { "\($0)" } ?? "—")
            LifecycleRow(label: "Total miles", value: t.totalMiles.map { "\(Int($0)) mi" } ?? "—")
        }
    }

    private func ctaRow(_ t: RunTicketDetail) -> some View {
        if let pdf = t.pdfUrl, !pdf.isEmpty {
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
            let t: RunTicketDetail = try await EusoTripAPI.shared.api.mutation("eusoTicket.generateRunTicket", input: In(loadId: n))
            ticket = t
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("304 · Run ticket · Night") {
    EusoTicketRunTicketScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("304 · Run ticket · Afternoon") {
    EusoTicketRunTicketScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
