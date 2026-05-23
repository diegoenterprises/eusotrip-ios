//
//  421_LoadConsolidation.swift
//  EusoTrip — Shipper · Load consolidation.
//
//  Reshaped 2026-05-23 with a single EXECUTE CONSOLIDATION drop-
//  zone tile above the suggestions list. Drag a suggestion card
//  onto it to fire shippers.executeConsolidation in one gesture
//  (the legacy per-card Consolidate button stays as tap fallback).
//

import SwiftUI

struct LoadConsolidationScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { LoadConsolBody() } nav: { shipperLifecycleNav() }
    }
}

private struct ConsolGroup: Decodable, Identifiable, Hashable {
    let id: String
    let lane: String
    let loadIds: [String]
    let combinedRate: Double?
    let savingsUsd: Double?
    let mode: String?     // "stop_chain" | "lane_split"
}

private struct LoadConsolBody: View {
    @Environment(\.palette) private var palette
    @State private var groups: [ConsolGroup] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var executing: String? = nil
    @State private var actionError: String? = nil
    @State private var lastExecuted: String? = nil
    @State private var dropHover: Bool = false
    @State private var draggingGroupId: String? = nil

    private var totalSavings: Double {
        groups.compactMap { $0.savingsUsd }.reduce(0, +)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let m = lastExecuted {
                    LifecycleCard(accentGradient: true) {
                        Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
                    }
                }
                if let e = actionError {
                    LifecycleCard(accentDanger: true) {
                        Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                }
                if !groups.isEmpty { executeDropZone }
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
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · LOAD CONSOLIDATION · LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text("Consolidation suggestions")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("ESANG groups loads on overlapping lanes for stop-chain or lane-split consolidation. Drag a suggestion onto EXECUTE to commit.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var executeDropZone: some View {
        let hoveringGroup = draggingGroupId.flatMap { id in groups.first(where: { $0.id == id }) }
        return HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 38, height: 38)
                .background(palette.bgCardSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("EXECUTE CONSOLIDATION")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
                if dropHover, let g = hoveringGroup {
                    let savings = g.savingsUsd.map { usd($0) } ?? "—"
                    Text("Release to consolidate \(g.loadIds.count) loads · save \(savings)")
                        .font(EType.caption)
                        .foregroundStyle(LinearGradient.diagonal)
                        .lineLimit(2)
                } else if totalSavings > 0 {
                    Text("Drop a suggestion here · total possible savings \(usd(totalSavings))")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                } else {
                    Text("Drop a suggestion card here to consolidate the loads.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            if executing != nil {
                ProgressView().scaleEffect(0.8)
            } else {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(dropHover ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    dropHover ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint),
                    lineWidth: dropHover ? 2 : 1
                )
                .animation(.easeOut(duration: 0.12), value: dropHover)
        )
        .dropDestination(for: String.self) { droppedIds, _ in
            guard let gid = droppedIds.first else { return false }
            guard groups.contains(where: { $0.id == gid }) else { return false }
            Task { await execute(gid) }
            return true
        } isTargeted: { hovering in
            dropHover = hovering
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading suggestions…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if groups.isEmpty { EusoEmptyState(systemImage: "arrow.triangle.merge", title: "No consolidations available", subtitle: "ESANG suggests grouping when 2+ loads share lane segments.") }
        else {
            ForEach(groups) { g in
                consolCard(g)
                    .draggable(g.id) {
                        consolCard(g)
                            .frame(maxWidth: 320)
                            .opacity(0.92)
                            .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                    }
                    .onDrag {
                        draggingGroupId = g.id
                        return NSItemProvider(object: g.id as NSString)
                    }
            }
        }
    }

    private func consolCard(_ g: ConsolGroup) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: dashIfEmpty(g.mode?.uppercased()), icon: "arrow.triangle.merge")
            LifecycleRow(label: "Lane",          value: g.lane)
            LifecycleRow(label: "Loads",         value: "\(g.loadIds.count)")
            LifecycleRow(label: "Combined rate",  value: usd(g.combinedRate))
            LifecycleRow(label: "Savings",        value: usd(g.savingsUsd))
            Button { Task { await execute(g.id) } } label: {
                HStack(spacing: 6) {
                    if executing == g.id { ProgressView().tint(.white) }
                    Text(executing == g.id ? "Consolidating…" : "Consolidate")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain).disabled(executing != nil)
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [ConsolGroup] = try await EusoTripAPI.shared.queryNoInput("shippers.getConsolidationSuggestions")
            groups = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func execute(_ id: String) async {
        await MainActor.run { executing = id; actionError = nil }
        let label = groups.first(where: { $0.id == id }).map { "\($0.loadIds.count) loads on \($0.lane)" } ?? "group \(id)"
        struct In: Encodable { let groupId: String }
        struct Out: Decodable { let success: Bool?; let consolidatedLoadId: String? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "shippers.executeConsolidation",
                input: In(groupId: id)
            )
            await MainActor.run {
                lastExecuted = "\(label) → CONSOLIDATED"
                draggingGroupId = nil
            }
            await load()
        } catch {
            await MainActor.run {
                actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
        }
        await MainActor.run { executing = nil }
    }
}

#Preview("421 · Consolidation · Night") { LoadConsolidationScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("421 · Consolidation · Afternoon") { LoadConsolidationScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
