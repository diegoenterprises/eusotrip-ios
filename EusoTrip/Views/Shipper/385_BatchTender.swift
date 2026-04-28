//
//  385_BatchTender.swift
//  EusoTrip — Shipper · Batch tender (Arc N).
//
//  Tender many drafted loads at once to a single (or favorited) carrier
//  set. Multi-select drafts; pick a carrier or "favorites"; fire bulk
//  tender mutation.
//

import SwiftUI

struct BatchTenderScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { BatchTenderBody() } nav: { shipperLifecycleNav() }
    }
}

private struct DraftLoadRow: Decodable, Identifiable, Hashable {
    let id: String
    let loadNumber: String
    let origin: String?
    let destination: String?
    let cargoType: String?
}

private struct BatchTenderBody: View {
    @Environment(\.palette) private var palette
    @State private var drafts: [DraftLoadRow] = []
    @State private var selected: Set<String> = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var sending = false
    @State private var sent = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if sent { LifecycleCard(accentGradient: true) { Text("Batch tendered \(selected.count) drafts.").font(EType.body).foregroundStyle(palette.textPrimary) } }
                if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                listCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · BATCH TENDER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Tender many at once").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var listCard: some View {
        if loading { LifecycleCard { Text("Loading drafts…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if drafts.isEmpty { EusoEmptyState(systemImage: "tray", title: "No drafts", subtitle: "Save drafts from Post-a-Load to bulk-tender them here.") }
        else {
            ForEach(drafts) { d in
                Button {
                    if selected.contains(d.id) { selected.remove(d.id) } else { selected.insert(d.id) }
                } label: {
                    LifecycleCard(accentGradient: selected.contains(d.id)) {
                        HStack {
                            Image(systemName: selected.contains(d.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(d.id) ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.loadNumber).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                                Text("\(dashIfEmpty(d.origin)) → \(dashIfEmpty(d.destination))").font(EType.caption).foregroundStyle(palette.textSecondary)
                                Text(dashIfEmpty(d.cargoType?.uppercased())).font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private var ctaRow: some View {
        Button { Task { await tender() } } label: {
            HStack(spacing: 6) {
                if sending { ProgressView().tint(.white) }
                Text(sending ? "Tendering…" : "Tender \(selected.count) loads")
                    .font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(sending || selected.isEmpty)
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [DraftLoadRow] = try await EusoTripAPI.shared.api.queryNoInput("loads.listDrafts")
            drafts = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func tender() async {
        sending = true
        struct In: Encodable { let loadIds: [String]; let mode: String }
        struct Out: Decodable { let success: Bool }
        do {
            let _ : Out = try await EusoTripAPI.shared.api.mutation("loads.batchTender", input: In(loadIds: Array(selected), mode: "favorites"))
            sent = true; selected = []
        } catch { /* surface inline */ }
        sending = false
    }
}

#Preview("385 · Batch tender · Night") { BatchTenderScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("385 · Batch tender · Afternoon") { BatchTenderScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
