//
//  412_DraftsList.swift
//  EusoTrip — Shipper · Drafts list (Arc C deepening).
//

import SwiftUI

struct DraftsListScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { DraftsListBody() } nav: { shipperLifecycleNav() }
    }
}

private struct DraftRow: Decodable, Identifiable, Hashable {
    let id: String
    let loadNumber: String?
    let origin: String?
    let destination: String?
    let cargoType: String?
    let createdAt: String?
}

private struct DraftsListBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [DraftRow] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var deleting: String? = nil

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
                Image(systemName: "tray").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · DRAFTS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Saved drafts").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading drafts…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rows.isEmpty { EusoEmptyState(systemImage: "tray", title: "No drafts", subtitle: "Save unfinished post-a-load attempts to resume later.") }
        else {
            ForEach(rows) { row in
                LifecycleCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dashIfEmpty(row.loadNumber)).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                            Text("\(dashIfEmpty(row.origin)) → \(dashIfEmpty(row.destination))").font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                            Text("\(dashIfEmpty(row.cargoType?.uppercased())) · \(humanISO(row.createdAt))").font(EType.mono(.micro)).tracking(0.4).foregroundStyle(palette.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Button {
                            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "250", "draftId": row.id])
                        } label: {
                            Text("Resume").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(LinearGradient.diagonal).clipShape(Capsule())
                        }.buttonStyle(.plain)
                        Button { Task { await delete(row.id) } } label: {
                            if deleting == row.id { ProgressView().tint(Brand.danger).frame(width: 22, height: 22) }
                            else { Image(systemName: "trash").foregroundStyle(Brand.danger) }
                        }.buttonStyle(.plain).disabled(deleting != nil)
                    }
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [DraftRow] = try await EusoTripAPI.shared.queryNoInput("loads.listDrafts")
            rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func delete(_ id: String) async {
        deleting = id
        struct In: Encodable { let id: String }
        struct Out: Decodable { let success: Bool }
        let _ : Out = (try? await EusoTripAPI.shared.mutation("loads.deleteDraft", input: In(id: id))) ?? Out(success: false)
        await load()
        deleting = nil
    }
}

#Preview("412 · Drafts · Night") { DraftsListScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("412 · Drafts · Afternoon") { DraftsListScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
