//
//  340_LoadBoardTrio.swift
//  EusoTrip — Load board trio (Matched / Find / Assigned).
//
//  iOS port of three flagship load-board web pages:
//    • MatchedLoads.tsx   → MatchedLoadsScreen
//    • FindLoads.tsx      → FindLoadsScreen
//    • AssignedLoads.tsx  → AssignedLoadsScreen
//
//  All reads off REAL server endpoints — no stubs:
//    dispatchRole.getMatchedLoads     (Matched)
//    dispatchRole.getMatchStats       (Matched)
//    dispatchRole.acceptLoad          (Matched — upgraded from stub
//                                       to real DB write in the paired
//                                       platform commit)
//    dispatch.unifiedLoads            (Find — marketplace mode)
//    loadBoard.getStats               (Find)
//    loadBoard.getMyPostedLoads       (Assigned)
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: ─────────────────────────────────────────────────────────
// MARK: MatchedLoads (340)
// MARK: ─────────────────────────────────────────────────────────

struct MatchedLoadsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { MatchedLoadsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Match", systemImage: "arrow.triangle.merge", isCurrent: true)],
                trailing: [NavSlot(label: "Drivers", systemImage: "person.3.fill", isCurrent: false),
                           NavSlot(label: "Me",      systemImage: "person",        isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct MatchedLoadRow: Decodable, Hashable, Identifiable {
    let id: String
    let loadNumber: String?
    let status: String?
    let pickupCity: String?
    let pickupState: String?
    let destCity: String?
    let destState: String?
    let rate: String?
    let distance: Double?
    let cargoType: String?
    let matchScore: Double?
}

private struct MatchStats: Decodable, Hashable {
    let pending: Int?
    let accepted: Int?
    let total: Int?
    let avgRate: Double?
}

private struct MatchedLoadsBody: View {
    @Environment(\.palette) private var palette
    @State private var loads: [MatchedLoadRow] = []
    @State private var stats: MatchStats?
    @State private var search: String = ""
    @State private var loading: Bool = true
    @State private var error: String?
    @State private var acceptingId: String?
    @State private var acceptAck: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let s = stats { statsRow(s) }
                searchField
                if let ack = acceptAck {
                    LifecycleCard(accentGradient: true) {
                        Text(ack).font(EType.caption).foregroundStyle(palette.textPrimary)
                    }
                }
                if let err = error {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                }
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
                Image(systemName: "arrow.triangle.merge").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · MATCHED LOADS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Matched loads").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func statsRow(_ s: MatchStats) -> some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "PENDING",  value: "\(s.pending ?? 0)",  icon: "hourglass")
            LifecycleStatTile(label: "ACCEPTED", value: "\(s.accepted ?? 0)", icon: "checkmark.seal.fill")
            LifecycleStatTile(label: "AVG RATE", value: "$\(Int(s.avgRate ?? 0))", icon: "dollarsign.circle")
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(palette.textTertiary)
            TextField("Search by lane / commodity", text: $search)
                .onSubmit { Task { await loadList() } }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            LifecycleCard { Text("Loading matched loads…").font(EType.caption).foregroundStyle(palette.textSecondary) }
        } else if loads.isEmpty {
            EusoEmptyState(systemImage: "tray", title: "No matches", subtitle: "When ESANG finds matches for your lanes they'll land here.")
        } else {
            ForEach(loads) { l in
                LifecycleCard(accentGradient: (l.matchScore ?? 0) > 0.85) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(l.loadNumber ?? l.id).font(EType.body.weight(.bold))
                            Spacer()
                            if let s = l.matchScore {
                                Text("\(Int(s * 100))% MATCH").font(.caption2.weight(.heavy)).tracking(0.6).foregroundStyle(LinearGradient.diagonal)
                            }
                        }
                        Text("\(l.pickupCity ?? "—"), \(l.pickupState ?? "—") → \(l.destCity ?? "—"), \(l.destState ?? "—")").font(.caption).foregroundStyle(palette.textSecondary)
                        HStack {
                            if let c = l.cargoType { Text(c.uppercased()).font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(palette.textTertiary) }
                            Spacer()
                            if let r = l.rate { Text("$\(r)").font(.body.monospacedDigit().weight(.semibold)) }
                        }
                        Button { Task { await accept(l.id) } } label: {
                            HStack(spacing: 6) {
                                if acceptingId == l.id { ProgressView().tint(.white).controlSize(.mini) }
                                Text(acceptingId == l.id ? "Accepting…" : "Accept Load")
                                    .font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(LinearGradient.diagonal)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(acceptingId != nil)
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    private func loadAll() async {
        loading = true; error = nil
        async let l: Void = loadList()
        async let s: Void = loadStats()
        _ = await (l, s)
        loading = false
    }

    private func loadList() async {
        struct In: Encodable { let search: String? }
        do {
            let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
            loads = try await EusoTripAPI.shared.query(
                "dispatchRole.getMatchedLoads",
                input: In(search: q.isEmpty ? nil : q)
            )
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func loadStats() async {
        do { stats = try await EusoTripAPI.shared.queryNoInput("dispatchRole.getMatchStats") } catch { /* */ }
    }

    private func accept(_ id: String) async {
        acceptingId = id
        struct In: Encodable { let loadId: String }
        struct Out: Decodable { let success: Bool?; let acceptedAt: String? }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation("dispatchRole.acceptLoad", input: In(loadId: id))
            acceptAck = "Accepted load \(id) — status flipped to ACCEPTED."
            await loadAll()
        } catch {
            error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        acceptingId = nil
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: FindLoads (341)
// MARK: ─────────────────────────────────────────────────────────

struct FindLoadsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { FindLoadsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",   systemImage: "house",             isCurrent: false),
                          NavSlot(label: "Find",   systemImage: "magnifyingglass",   isCurrent: true)],
                trailing: [NavSlot(label: "Match", systemImage: "arrow.triangle.merge", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",            isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct LoadBoardStats: Decodable, Hashable {
    let totalAvailable: Int?
    let avgRate: Double?
    let avgDistance: Double?
}

private struct FindLoadsBody: View {
    @Environment(\.palette) private var palette
    @State private var loads: [MatchedLoadRow] = []
    @State private var stats: LoadBoardStats?
    @State private var loading: Bool = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if let s = stats { statsRow(s) }
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
                Image(systemName: "magnifyingglass.circle.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · FIND LOADS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Open marketplace").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    private func statsRow(_ s: LoadBoardStats) -> some View {
        HStack(spacing: Space.s2) {
            LifecycleStatTile(label: "AVAILABLE", value: "\(s.totalAvailable ?? 0)", icon: "shippingbox.fill")
            LifecycleStatTile(label: "AVG RATE",  value: "$\(Int(s.avgRate ?? 0))",  icon: "dollarsign.circle")
            LifecycleStatTile(label: "AVG MI",    value: "\(Int(s.avgDistance ?? 0))", icon: "ruler")
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            LifecycleCard { Text("Loading marketplace…").font(EType.caption).foregroundStyle(palette.textSecondary) }
        } else if loads.isEmpty {
            EusoEmptyState(systemImage: "tray", title: "Marketplace is quiet", subtitle: "Check back — new loads post throughout the day.")
        } else {
            ForEach(loads) { l in
                LifecycleCard {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(l.loadNumber ?? l.id).font(EType.body.weight(.bold))
                            Spacer()
                            if let r = l.rate { Text("$\(r)").font(.body.monospacedDigit().weight(.semibold)) }
                        }
                        Text("\(l.pickupCity ?? "—"), \(l.pickupState ?? "—") → \(l.destCity ?? "—"), \(l.destState ?? "—")").font(.caption).foregroundStyle(palette.textSecondary)
                        if let c = l.cargoType { Text(c.uppercased()).font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(palette.textTertiary) }
                    }
                }
            }
        }
    }

    private func loadAll() async {
        loading = true
        async let l: Void = loadList()
        async let s: Void = loadStats()
        _ = await (l, s)
        loading = false
    }

    private func loadList() async {
        struct In: Encodable { let mode: String; let limit: Int }
        struct Out: Decodable { let loads: [MatchedLoadRow]?; let items: [MatchedLoadRow]? }
        do {
            let r: Out = try await EusoTripAPI.shared.query("dispatch.unifiedLoads", input: In(mode: "marketplace", limit: 100))
            loads = r.loads ?? r.items ?? []
        } catch { /* */ }
    }

    private func loadStats() async {
        do { stats = try await EusoTripAPI.shared.queryNoInput("loadBoard.getStats") } catch { /* */ }
    }
}

// MARK: ─────────────────────────────────────────────────────────
// MARK: AssignedLoads (342)
// MARK: ─────────────────────────────────────────────────────────

struct AssignedLoadsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { AssignedLoadsBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",             isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill",  isCurrent: true)],
                trailing: [NavSlot(label: "Match", systemImage: "arrow.triangle.merge", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct AssignedLoadsBody: View {
    @Environment(\.palette) private var palette
    @State private var loads: [MatchedLoadRow] = []
    @State private var loading: Bool = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadList() }
        .refreshable { await loadList() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.clipboard.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · ASSIGNED LOADS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("My posted loads").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            LifecycleCard { Text("Loading your posted loads…").font(EType.caption).foregroundStyle(palette.textSecondary) }
        } else if loads.isEmpty {
            EusoEmptyState(systemImage: "tray", title: "Nothing posted", subtitle: "Loads you post on the marketplace appear here.")
        } else {
            ForEach(loads) { l in
                LifecycleCard {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(l.loadNumber ?? l.id).font(EType.body.weight(.bold))
                            Spacer()
                            Text((l.status ?? "—").uppercased()).font(.caption2.weight(.bold)).tracking(0.6).foregroundStyle(palette.textTertiary)
                        }
                        Text("\(l.pickupCity ?? "—"), \(l.pickupState ?? "—") → \(l.destCity ?? "—"), \(l.destState ?? "—")").font(.caption).foregroundStyle(palette.textSecondary)
                        if let r = l.rate { Text("$\(r)").font(.body.monospacedDigit().weight(.semibold)) }
                    }
                }
            }
        }
    }

    private func loadList() async {
        loading = true
        struct In: Encodable { let limit: Int }
        struct Out: Decodable { let loads: [MatchedLoadRow]?; let items: [MatchedLoadRow]? }
        do {
            let r: Out = try await EusoTripAPI.shared.query("loadBoard.getMyPostedLoads", input: In(limit: 100))
            loads = r.loads ?? r.items ?? []
        } catch { /* */ }
        loading = false
    }
}

// MARK: - Previews

#Preview("340 Matched · Dark")  { MatchedLoadsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("340 Matched · Light") { MatchedLoadsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("341 Find · Dark")     { FindLoadsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("341 Find · Light")    { FindLoadsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("342 Assigned · Dark")  { AssignedLoadsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("342 Assigned · Light") { AssignedLoadsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
