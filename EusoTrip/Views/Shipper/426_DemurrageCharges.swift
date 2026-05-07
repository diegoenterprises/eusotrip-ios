//
//  426_DemurrageCharges.swift
//  EusoTrip — Shipper · Demurrage charges (auto-gen + approve).
//
//  Cross-role chain: shipper-side approval here triggers
//  catalysts.acceptDemurrage on the carrier's accessorial queue +
//  emits ACCESSORIAL_APPROVED so the carrier's settlement page
//  refreshes via realtime.
//

import SwiftUI

struct DemurrageChargesScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { DemurrageBody() } nav: { shipperLifecycleNav() }
    }
}

private struct DemurrageRow: Decodable, Identifiable, Hashable {
    let id: String
    let loadId: String
    let loadNumber: String?
    let amount: Double
    let hoursDetained: Double?
    let rate: Double?
    let evidenceUrl: String?
    let status: String?
    let createdAt: String?
}

private struct DemurrageBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [DemurrageRow] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var processing: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · DEMURRAGE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Demurrage charges").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Auto-generated from ELD detention events. Approve / dispute each row; carrier sees outcome via realtime.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading demurrage queue…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rows.isEmpty { EusoEmptyState(systemImage: "clock", title: "No demurrage", subtitle: "Detention events generate rows here automatically.") }
        else {
            ForEach(rows) { r in
                LifecycleCard {
                    LifecycleSection(label: dashIfEmpty(r.loadNumber).uppercased(), icon: "doc.text")
                    LifecycleRow(label: "Hours",   value: r.hoursDetained.map { String(format: "%.1f", $0) } ?? "—")
                    LifecycleRow(label: "Rate",    value: usd(r.rate))
                    LifecycleRow(label: "Amount",  value: usd(r.amount))
                    LifecycleRow(label: "Status",  value: dashIfEmpty(r.status?.uppercased()))
                    if r.status == "pending_approval" {
                        HStack(spacing: 8) {
                            Button { Task { await respond(r.id, approve: true) } } label: {
                                HStack { if processing == r.id+":a" { ProgressView().tint(.white) }
                                    Text(processing == r.id+":a" ? "Approving…" : "Approve").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white) }
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(LinearGradient.diagonal).clipShape(Capsule())
                            }.buttonStyle(.plain).disabled(processing != nil)
                            Button { Task { await respond(r.id, approve: false) } } label: {
                                Text(processing == r.id+":d" ? "Disputing…" : "Dispute").font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 6)
                                    .background(Brand.danger).clipShape(Capsule())
                            }.buttonStyle(.plain).disabled(processing != nil)
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [DemurrageRow] = try await EusoTripAPI.shared.queryNoInput("demurrage.listForShipper")
            rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func respond(_ id: String, approve: Bool) async {
        processing = id + (approve ? ":a" : ":d")
        struct In: Encodable { let id: String; let approve: Bool }
        struct Out: Decodable { let success: Bool }
        let _ : Out = (try? await EusoTripAPI.shared.mutation("demurrage.respond", input: In(id: id, approve: approve))) ?? Out(success: false)
        await load()
        processing = nil
    }
}

#Preview("426 · Demurrage · Night") { DemurrageChargesScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("426 · Demurrage · Afternoon") { DemurrageChargesScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
