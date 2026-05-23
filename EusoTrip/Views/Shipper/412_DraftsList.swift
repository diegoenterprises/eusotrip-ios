//
//  412_DraftsList.swift
//  EusoTrip — Shipper · Drafts list (Arc C deepening).
//
//  Reshaped 2026-05-23 with a single TRASH drop-zone tile above
//  the drafts list. Drag a draft card onto it to fire
//  loads.deleteDraft in one gesture. Per-row trash button + Resume
//  CTA preserved as tap fallbacks.
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
    @State private var actionError: String? = nil
    @State private var lastDeleted: String? = nil
    @State private var dropHover: Bool = false
    @State private var draggingDraftId: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let m = lastDeleted {
                    LifecycleCard(accentGradient: true) {
                        Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
                    }
                }
                if let e = actionError {
                    LifecycleCard(accentDanger: true) {
                        Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                }
                if !rows.isEmpty { trashDropZone }
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "tray")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · DRAFTS · LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Saved drafts")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Drag a draft onto TRASH to delete. Tap Resume to pick up where you left off.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trashDropZone: some View {
        let hoveringDraft = draggingDraftId.flatMap { id in rows.first(where: { $0.id == id }) }
        return HStack(spacing: 10) {
            Image(systemName: "trash.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Brand.danger)
                .frame(width: 38, height: 38)
                .background(palette.bgCardSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("TRASH")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.danger)
                if dropHover, let d = hoveringDraft {
                    Text("Release to delete \(dashIfEmpty(d.loadNumber))")
                        .font(EType.caption)
                        .foregroundStyle(Brand.danger)
                        .lineLimit(2)
                } else {
                    Text("Drop a draft card here to delete it permanently.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if deleting != nil {
                ProgressView().scaleEffect(0.8)
            } else {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(dropHover ? Brand.danger : palette.textTertiary)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    dropHover ? AnyShapeStyle(Brand.danger) : AnyShapeStyle(Brand.danger.opacity(0.3)),
                    lineWidth: dropHover ? 2 : 1
                )
                .animation(.easeOut(duration: 0.12), value: dropHover)
        )
        .dropDestination(for: String.self) { droppedIds, _ in
            guard let did = droppedIds.first else { return false }
            guard rows.contains(where: { $0.id == did }) else { return false }
            Task { await delete(did) }
            return true
        } isTargeted: { hovering in
            dropHover = hovering
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            LifecycleCard { Text("Loading drafts…").font(EType.caption).foregroundStyle(palette.textSecondary) }
        } else if let err = loadError {
            LifecycleCard(accentDanger: true) {
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            }
        } else if rows.isEmpty {
            EusoEmptyState(systemImage: "tray", title: "No drafts", subtitle: "Save unfinished post-a-load attempts to resume later.")
        } else {
            ForEach(rows) { row in
                draftCard(row)
                    .draggable(row.id) {
                        draftCard(row)
                            .frame(maxWidth: 320)
                            .opacity(0.92)
                            .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                    }
                    .onDrag {
                        draggingDraftId = row.id
                        return NSItemProvider(object: row.id as NSString)
                    }
            }
        }
    }

    private func draftCard(_ row: DraftRow) -> some View {
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
        await MainActor.run { deleting = id; actionError = nil }
        let label = rows.first(where: { $0.id == id })?.loadNumber ?? "draft \(id)"
        struct In: Encodable { let id: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation("loads.deleteDraft", input: In(id: id))
            await MainActor.run {
                lastDeleted = "\(label) → DELETED"
                draggingDraftId = nil
            }
            await load()
        } catch {
            await MainActor.run {
                actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
        }
        await MainActor.run { deleting = nil }
    }
}

#Preview("412 · Drafts · Night") { DraftsListScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("412 · Drafts · Afternoon") { DraftsListScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
