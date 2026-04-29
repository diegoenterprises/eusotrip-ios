//
//  710_DispatchRunTicketCapture.swift
//  EusoTrip — Dispatch · Electronic run-ticket capture (EusoTicket mobile).
//
//  Mirrors Dispatch Commodity's electronic ticketing app — Android/iPad
//  ticket capture without proprietary hardware. Wired to runTickets.create
//  (issues RT-YYYY-XXXXXX numbers) and runTickets.list / getStats. Origin
//  and destination resolve automatically from loads.loadNumber so a
//  dispatcher can punch the load number, hand the phone to the driver,
//  and the ticket is on the wire before the truck leaves the gate.
//

import SwiftUI

struct DispatchRunTicketCaptureScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { TicketBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct RunTicketRow: Decodable, Identifiable, Hashable {
    let id: Int
    let ticketNumber: String
    let loadId: Int?
    let loadNumber: String?
    let status: String
    let origin: String?
    let destination: String?
    let totalMiles: Double?
    let totalFuel: Double?
    let totalTolls: Double?
    let totalExpenses: Double?
    let createdAt: String?
    let completedAt: String?
}

private struct RunTicketStats: Decodable, Hashable {
    let total: Int?
    let active: Int?
    let completed: Int?
    let pendingReview: Int?
    let totalFuel: Double?
    let totalTolls: Double?
    let totalExpenses: Double?
}

private struct TicketBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [RunTicketRow] = []
    @State private var stats: RunTicketStats? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var loadNumber: String = ""
    @State private var creating: Bool = false
    @State private var actionError: String? = nil
    @State private var lastCreated: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let s = stats { statsGrid(s) }
                composeCard
                if let m = lastCreated { LifecycleCard(accentGradient: true) { Text(m).font(EType.caption).foregroundStyle(palette.textPrimary) } }
                if let e = actionError { LifecycleCard(accentDanger: true) { Text(e).font(EType.caption).foregroundStyle(Brand.danger) } }
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "ticket.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCH · EUSOTICKET").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Run-ticket capture").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Electronic ticketing — origin/destination auto-resolve from load number.").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private func statsGrid(_ s: RunTicketStats) -> some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "ACTIVE", value: "\(s.active ?? 0)", icon: "ticket")
            LifecycleStatTile(label: "REVIEW", value: "\(s.pendingReview ?? 0)", icon: "magnifyingglass", danger: (s.pendingReview ?? 0) > 0)
            LifecycleStatTile(label: "DONE",   value: "\(s.completed ?? 0)", icon: "checkmark.seal")
        }
    }

    private var composeCard: some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "OPEN A TICKET", icon: "plus.app.fill")
            HStack(spacing: 8) {
                TextField("Load number (e.g. LD-260427-A38FB)", text: $loadNumber)
                    .textFieldStyle(.plain)
                    .font(EType.body)
                    .padding(10)
                    .background(palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                Button { Task { await create() } } label: {
                    HStack(spacing: 4) {
                        if creating { ProgressView().tint(.white) }
                        Text(creating ? "Opening…" : "Open").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }.buttonStyle(.plain).disabled(creating || loadNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading tickets…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rows.isEmpty {
            EusoEmptyState(systemImage: "ticket", title: "No tickets yet", subtitle: "Punch a load number above to open the first one.")
        } else {
            ForEach(rows) { t in
                LifecycleCard(accentGradient: t.status == "active") {
                    LifecycleSection(label: t.ticketNumber, icon: "ticket.fill")
                    LifecycleRow(label: "Load",        value: dashIfEmpty(t.loadNumber))
                    LifecycleRow(label: "Origin",      value: dashIfEmpty(t.origin))
                    LifecycleRow(label: "Destination", value: dashIfEmpty(t.destination))
                    LifecycleRow(label: "Status",      value: t.status.uppercased())
                    LifecycleRow(label: "Miles",       value: t.totalMiles.map { String(format: "%.0f mi", $0) } ?? "—")
                    LifecycleRow(label: "Fuel",        value: usd(t.totalFuel))
                    LifecycleRow(label: "Tolls",       value: usd(t.totalTolls))
                    LifecycleRow(label: "Expenses",    value: usd(t.totalExpenses))
                    LifecycleRow(label: "Opened",      value: humanISO(t.createdAt))
                }
            }
        }
    }

    private func loadAll() async {
        loading = true; loadError = nil
        struct In: Encodable { let limit: Int }
        do {
            async let r: [RunTicketRow] = EusoTripAPI.shared.api.query("runTickets.list", input: In(limit: 100))
            async let s: RunTicketStats = EusoTripAPI.shared.api.queryNoInput("runTickets.getStats")
            let (rrows, sstats) = try await (r, s)
            rows = rrows
            stats = sstats
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func create() async {
        creating = true; actionError = nil
        struct In: Encodable { let loadNumber: String }
        struct Out: Decodable { let ticketNumber: String?; let id: Int? }
        do {
            let r: Out = try await EusoTripAPI.shared.api.mutation("runTickets.create", input: In(loadNumber: loadNumber))
            lastCreated = "Opened ticket \(r.ticketNumber ?? "—") for \(loadNumber)."
            loadNumber = ""
            await loadAll()
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        creating = false
    }
}

#Preview("710 · Run-ticket capture · Night") { DispatchRunTicketCaptureScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("710 · Run-ticket capture · Afternoon") { DispatchRunTicketCaptureScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
