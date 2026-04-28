//
//  413_ArchivedLoads.swift
//  EusoTrip — Shipper · Archived loads (Arc C deepening).
//

import SwiftUI

struct ArchivedLoadsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { ArchivedBody() } nav: { shipperLifecycleNav() }
    }
}

private struct ArchivedRow: Decodable, Identifiable, Hashable {
    let id: String
    let loadNumber: String
    let origin: String?
    let destination: String?
    let status: String
    let archivedAt: String?
}

private struct ArchivedBody: View {
    @Environment(\.palette) private var palette
    @State private var rows: [ArchivedRow] = []
    @State private var search: String = ""
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var restoring: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                searchBar
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
                Image(systemName: "archivebox").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · ARCHIVED").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Archived loads").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private var searchBar: some View {
        TextField("Search archive", text: $search)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onSubmit { Task { await load() } }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading archive…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if rows.isEmpty { EusoEmptyState(systemImage: "archivebox", title: "Nothing archived", subtitle: "Cancelled and old completed loads land here automatically.") }
        else {
            ForEach(rows) { r in
                LifecycleCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.loadNumber).font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                            Text("\(dashIfEmpty(r.origin)) → \(dashIfEmpty(r.destination))").font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                            Text("\(r.status.uppercased()) · archived \(humanISO(r.archivedAt))").font(EType.mono(.micro)).tracking(0.4).foregroundStyle(palette.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Button { Task { await restore(r.id) } } label: {
                            if restoring == r.id { ProgressView().tint(.white).frame(width: 70, height: 26).background(LinearGradient.diagonal).clipShape(Capsule()) }
                            else {
                                Text("Restore").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(LinearGradient.diagonal).clipShape(Capsule())
                            }
                        }.buttonStyle(.plain).disabled(restoring != nil)
                    }
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let q: String? }
        do {
            let r: [ArchivedRow] = try await EusoTripAPI.shared.api.query("loads.listArchive", input: In(q: search.isEmpty ? nil : search))
            rows = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func restore(_ id: String) async {
        restoring = id
        struct In: Encodable { let id: String }
        struct Out: Decodable { let success: Bool }
        let _ : Out = (try? await EusoTripAPI.shared.api.mutation("loads.restoreArchive", input: In(id: id))) ?? Out(success: false)
        await load()
        restoring = nil
    }
}

#Preview("413 · Archived · Night") { ArchivedLoadsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("413 · Archived · Afternoon") { ArchivedLoadsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
