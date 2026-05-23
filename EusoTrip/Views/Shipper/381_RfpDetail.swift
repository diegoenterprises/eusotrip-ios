//
//  381_RfpDetail.swift
//  EusoTrip — Shipper · RFP detail + lane awarding (Arc N).
//
//  Reshaped 2026-05-23 from a flat lane list (with per-card "Award
//  lane" button only on rows with no awardedCarrierName) into a
//  2-column Kanban by award state. Drag an UNAWARDED lane card
//  onto AWARDED fires the real rfpManager.awardLane mutation.
//  Per-card tap button preserved.
//

import SwiftUI

struct RfpDetailScreen: View {
    let theme: Theme.Palette
    let rfpId: String
    var body: some View {
        Shell(theme: theme) { RfpDetailBody(rfpId: rfpId) } nav: { shipperLifecycleNav() }
    }
}

private struct RfpDetail: Decodable, Hashable {
    let id: String
    let title: String?
    let status: String?
    let dueDate: String?
    let lanes: [Lane]
    struct Lane: Decodable, Hashable, Identifiable {
        let id: String
        let origin: String?
        let destination: String?
        let mode: String?
        let bestBid: Double?
        let awardedCarrierName: String?
    }
}

private struct LaneKanbanColumn: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String
}

private let laneKanbanColumns: [LaneKanbanColumn] = [
    .init(id: "unawarded", label: "UNAWARDED", icon: "hourglass"),
    .init(id: "awarded",   label: "AWARDED",   icon: "checkmark.seal.fill"),
]

private struct RfpDetailBody: View {
    @Environment(\.palette) private var palette
    let rfpId: String
    @State private var rfp: RfpDetail? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var awarding: String? = nil
    @State private var actionError: String? = nil
    @State private var lastAwarded: String? = nil
    @State private var selected: String = "unawarded"
    @State private var dragHoverColumn: String? = nil

    private func columnId(for lane: RfpDetail.Lane) -> String {
        (lane.awardedCarrierName?.isEmpty == false) ? "awarded" : "unawarded"
    }

    private var byColumn: [String: [RfpDetail.Lane]] {
        guard let r = rfp else { return [:] }
        return Dictionary(grouping: r.lanes) { columnId(for: $0) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let m = lastAwarded {
                    LifecycleCard(accentGradient: true) {
                        Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
                    }
                }
                if let e = actionError {
                    LifecycleCard(accentDanger: true) {
                        Text(e).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                }
                if loading {
                    LifecycleCard { Text("Loading RFP…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else if let r = rfp {
                    summaryCard(r)
                    scrubber
                    columnPager
                        .frame(minHeight: 460)
                }
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
                Image(systemName: "doc.text").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · RFP DETAIL · LIVE").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(rfp?.title ?? "—").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Drag an UNAWARDED lane onto AWARDED to commit. Best bid per lane is the auto-pick.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summaryCard(_ r: RfpDetail) -> some View {
        LifecycleCard(accentGradient: true) {
            LifecycleSection(label: "RFP", icon: "checkmark.seal")
            LifecycleRow(label: "Status",   value: dashIfEmpty(r.status?.uppercased()))
            LifecycleRow(label: "Due",      value: humanISO(r.dueDate))
            LifecycleRow(label: "Lanes",    value: "\(r.lanes.count)")
        }
    }

    private var scrubber: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(laneKanbanColumns) { col in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { selected = col.id }
                    } label: {
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: col.icon).font(.system(size: 9, weight: .heavy))
                                Text(col.label).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            }
                            Text("\(byColumn[col.id]?.count ?? 0)")
                                .font(.system(size: 13, weight: .heavy)).monospacedDigit()
                        }
                        .foregroundStyle(selected == col.id ? .white : palette.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(selected == col.id ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var columnPager: some View {
        TabView(selection: $selected) {
            ForEach(laneKanbanColumns) { col in
                column(col).tag(col.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func column(_ col: LaneKanbanColumn) -> some View {
        let cards = byColumn[col.id] ?? []
        let isHover = dragHoverColumn == col.id
        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text(col.label)
                        .font(.system(size: 13, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textPrimary)
                    Text("\(cards.count)")
                        .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                    Spacer(minLength: 0)
                    if col.id == "awarded" {
                        Text("DROP UNAWARDED TO COMMIT")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                if cards.isEmpty {
                    EusoEmptyState(
                        systemImage: col.icon,
                        title: col.id == "unawarded" ? "All lanes awarded" : "No awards yet",
                        subtitle: col.id == "unawarded"
                            ? "Every lane in this RFP has a carrier. Recall an award to revisit."
                            : "Drag a lane card from UNAWARDED here to commit to the best bid."
                    )
                } else {
                    ForEach(cards) { lane in
                        laneCard(lane, columnId: col.id)
                            .draggable(lane.id) {
                                laneCard(lane, columnId: col.id)
                                    .frame(maxWidth: 320)
                                    .opacity(0.92)
                                    .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
                            }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 6)
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(
                    isHover ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Color.clear),
                    lineWidth: isHover ? 2 : 0
                )
                .padding(.horizontal, 8)
                .animation(.easeOut(duration: 0.12), value: isHover)
        )
        .dropDestination(for: String.self) { droppedIds, _ in
            guard let laneId = droppedIds.first else { return false }
            guard let r = rfp, let lane = r.lanes.first(where: { $0.id == laneId }) else { return false }
            // Only one transition is user-driven: unawarded → awarded.
            guard col.id == "awarded", columnId(for: lane) == "unawarded" else {
                return false
            }
            Task { await awardLane(laneId) }
            return true
        } isTargeted: { hovering in
            dragHoverColumn = hovering ? col.id : (dragHoverColumn == col.id ? nil : dragHoverColumn)
        }
    }

    private func laneCard(_ lane: RfpDetail.Lane, columnId: String) -> some View {
        let isAwarding = awarding == lane.id
        return LifecycleCard(accentGradient: columnId == "awarded") {
            LifecycleSection(label: "\(dashIfEmpty(lane.origin)) → \(dashIfEmpty(lane.destination))", icon: "arrow.right")
            LifecycleRow(label: "Mode",     value: dashIfEmpty(lane.mode?.uppercased()))
            LifecycleRow(label: "Best bid", value: usd(lane.bestBid))
            LifecycleRow(label: "Awarded",  value: dashIfEmpty(lane.awardedCarrierName))
            if columnId == "unawarded" {
                Button { Task { await awardLane(lane.id) } } label: {
                    HStack(spacing: 6) {
                        if isAwarding { ProgressView().tint(.white) }
                        Text(isAwarding ? "Awarding…" : "Award lane")
                            .font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(LinearGradient.diagonal).clipShape(Capsule())
                }.buttonStyle(.plain).disabled(awarding != nil)
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let rfpId: String }
        do {
            let r: RfpDetail = try await EusoTripAPI.shared.query("rfpManager.getRFPDetail", input: In(rfpId: rfpId))
            rfp = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func awardLane(_ laneId: String) async {
        await MainActor.run { awarding = laneId; actionError = nil }
        let label = rfp?.lanes.first(where: { $0.id == laneId }).map { "\($0.origin ?? "—") → \($0.destination ?? "—")" } ?? "lane \(laneId)"
        struct In: Encodable { let rfpId: String; let laneId: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "rfpManager.awardLane",
                input: In(rfpId: rfpId, laneId: laneId)
            )
            await MainActor.run { lastAwarded = "\(label) → AWARDED" }
            await load()
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) { selected = "awarded" }
            }
        } catch {
            await MainActor.run {
                actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
        }
        await MainActor.run { awarding = nil }
    }
}

#Preview("381 · RFP detail · Night") { RfpDetailScreen(theme: Theme.dark, rfpId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("381 · RFP detail · Afternoon") { RfpDetailScreen(theme: Theme.light, rfpId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
