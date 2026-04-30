//
//  384_BulkRetender.swift
//  EusoTrip — Shipper · Bulk re-tender (Arc N).
//

import SwiftUI

struct BulkRetenderScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { BulkRetenderBody() } nav: { shipperLifecycleNav() }
    }
}

private struct BulkRetenderBody: View {
    @Environment(\.palette) private var palette
    @StateObject private var loads = ShipperMyLoadsStore()
    @State private var selected: Set<String> = []
    @State private var sending: Bool = false
    @State private var sent: Bool = false
    @State private var actionError: String? = nil

    private var rows: [ShipperAPI.MyLoad] {
        (loads.state.value ?? []).filter { ["posted", "bidding"].contains($0.status.lowercased()) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if sent { LifecycleCard(accentGradient: true) { Text("Re-tendered \(selected.count) loads.").font(EType.body).foregroundStyle(palette.textPrimary) } }
                if let err = actionError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
                listCard
                ctaRow
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loads.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · BULK RE-TENDER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Re-tender selected loads").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Multi-select posted/bidding loads. Bulk action broadcasts to all favorited carriers.").font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var listCard: some View {
        if rows.isEmpty {
            EusoEmptyState(systemImage: "shippingbox", title: "Nothing to re-tender", subtitle: "No posted/bidding loads in the active set.")
        } else {
            ForEach(rows) { ld in
                Button {
                    if selected.contains(ld.id) { selected.remove(ld.id) } else { selected.insert(ld.id) }
                } label: {
                    LifecycleCard(accentGradient: selected.contains(ld.id)) {
                        HStack {
                            Image(systemName: selected.contains(ld.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(ld.id) ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ld.loadNumber).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                                Text("\(dashIfEmpty(ld.origin)) → \(dashIfEmpty(ld.destination))").font(EType.caption).foregroundStyle(palette.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Text(ld.status.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                        }
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private var ctaRow: some View {
        Button { Task { await retender() } } label: {
            HStack(spacing: 6) {
                if sending { ProgressView().tint(.white) }
                Text(sending ? "Re-tendering…" : "Re-tender \(selected.count)")
                    .font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain).disabled(sending || selected.isEmpty)
    }

    private func retender() async {
        sending = true; actionError = nil
        struct In: Encodable { let loadIds: [String] }
        struct Out: Decodable { let success: Bool; let count: Int? }
        do {
            let _ : Out = try await EusoTripAPI.shared.mutation("loads.bulkRetender", input: In(loadIds: Array(selected)))
            sent = true; selected = []
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sending = false
    }
}

#Preview("384 · Bulk re-tender · Night") { BulkRetenderScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("384 · Bulk re-tender · Afternoon") { BulkRetenderScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
