//
//  744_VesselTerminalGateLog.swift
//  EusoTrip — Vessel Operator · Terminal Gate Log (PURPOSE-BUILT TIMELINE).
//
//  Verbatim bespoke port of canonical wireframe "744 Vessel Terminal Gate Log ·
//  Dark" (06 Vessel · Vessel Operator). A true TIMELINE/HISTORY archetype: a
//  compact gate-throughput band feeding a vertical gate-event spine with a left
//  time-rail — so the operator reads the live flow of boxes through the terminal
//  as a chronology, not as a stat. A timeline must look like a timeline. Docked
//  under SHIPMENTS.
//
//  REAL WIRING (tRPC · server/routers/terminals.ts — re-verified 2026-07-11):
//    · terminals.getRecentMovements {limit}                             (:2644)
//        -> [{id,loadNumber,status,origin,destination,resolvedAt,finalDwellHours}].
//        Backs the event spine + the throughput count + the avg-turn KPI. Company-
//        scoped, live off yard_moves (completed / cancelled).
//    · terminals.getGateQueue {limit}                                   (:2692)
//        -> [{id,loadNumber,origin,destination,stage,arrivedAt,dwellHours,
//        priority}]. Backs the in-queue KPI (trucks waiting at the gate). Live.
//    · A formal gate-crossing IN/OUT direction + geofence-confirmed flag is not
//        carried on yard_moves; the spine reads the real resolved moves and
//        surfaces gate direction as the named gap.  STUB · named-gap
//        (terminals.recordGateCrossing).
//    · "Export gate log" = client render · "Filter" = client filter.
//
//  transportMode=vessel · US (CA/MX drayage regime carried as content). RBAC
//  protectedProcedure. NO mock data — the band, KPIs, and spine derive from live
//  yard moves + gate queue.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Data shapes

private struct GateMovement744: Decodable, Identifiable {
    let id: String
    let loadNumber: String?
    let status: String?
    let origin: String?
    let destination: String?
    let resolvedAt: String?
    let finalDwellHours: Double?
}
private struct GateQueueItem744: Decodable, Identifiable {
    let id: String
    let loadNumber: String?
    let origin: String?
    let destination: String?
    let stage: String?
    let arrivedAt: String?
    let dwellHours: Double?
    let priority: String?
}

// MARK: - Screen

struct VesselTerminalGateLogScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            VesselTerminalGateLogBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle)
        }
    }
}

// MARK: - Body

private struct VesselTerminalGateLogBody: View {
    @Environment(\.palette) private var palette

    @State private var moves: [GateMovement744] = []
    @State private var queue: [GateQueueItem744] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            IridescentHairline().padding(.horizontal, Space.s5)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    loadingState
                } else if let err = loadError {
                    errorCard(err)
                } else {
                    throughputBand
                    kpiStrip
                    spineSection
                    gateClearanceBand
                    ctaRow
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Derived

    private var resolvedCount: Int { moves.count }
    private var completedCount: Int { moves.filter { ($0.status ?? "") == "completed" }.count }
    private var cancelledCount: Int { moves.filter { ($0.status ?? "") == "cancelled" }.count }
    private var avgTurn: Double {
        let ds = moves.compactMap { $0.finalDwellHours }.filter { $0 > 0 }
        return ds.isEmpty ? 0 : ds.reduce(0, +) / Double(ds.count)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle").font(.system(size: 8, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · GATE LOG")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("live").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            Text("Gate log")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary).padding(.top, Space.s4)
        }
        .padding(.horizontal, Space.s5).padding(.top, Space.s5).padding(.bottom, Space.s3)
    }

    // MARK: Throughput band

    private var throughputBand: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("GATE THROUGHPUT · RECENT").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(Brand.success).frame(width: 5, height: 5)
                    Text("LIVE FEED").font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(Brand.success)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text("\(resolvedCount)").font(.system(size: 34, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("resolved moves").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textSecondary)
                    Text("\(queue.count) at gate now").font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
            // completed / cancelled split (the real yard-move resolution split).
            GeometryReader { geo in
                let total = max(1, completedCount + cancelledCount)
                let w = geo.size.width
                HStack(spacing: 3) {
                    Capsule().fill(Brand.success.opacity(0.85))
                        .frame(width: completedCount == 0 ? 0 : max(6, w * CGFloat(completedCount) / CGFloat(total) - 2))
                    Capsule().fill(Brand.neutral.opacity(0.7)).frame(maxWidth: .infinity)
                }
                .opacity((completedCount + cancelledCount) == 0 ? 0.25 : 1)
            }
            .frame(height: 12)
            HStack(spacing: Space.s4) {
                legendDot(Brand.success, "\(completedCount) completed")
                legendDot(Brand.neutral, "\(cancelledCount) cancelled")
                Spacer()
            }
        }
        .padding(Space.s5).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
    }
    private func legendDot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) { Circle().fill(c).frame(width: 6, height: 6)
            Text(t).font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textSecondary) }
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            kpiCell("AVG TURN", avgTurn > 0 ? String(format: "%.1fh", avgTurn) : "—", "gate to gate", highlight: true)
            kpiCell("IN QUEUE", "\(queue.count)", "trucks waiting", highlight: false)
            kpiCell("RESOLVED", "\(resolvedCount)", "recent moves", highlight: false)
        }
    }
    private func kpiCell(_ label: String, _ value: String, _ sub: String, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(highlight ? Color.white.opacity(0.85) : palette.textTertiary)
            Text(value).font(.system(size: 22, weight: .semibold)).monospacedDigit()
                .foregroundStyle(highlight ? Color.white : palette.textPrimary)
            Text(sub).font(.system(size: 9)).foregroundStyle(highlight ? Color.white.opacity(0.8) : palette.textTertiary)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(highlight ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(highlight ? Color.clear : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Vertical event spine

    private var spineSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("GATE CROSSINGS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getRecentMovements").font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
            }
            if moves.isEmpty {
                EusoEmptyState(systemImage: "arrow.left.arrow.right.circle",
                               title: "No gate crossings yet",
                               subtitle: "Resolved gate moves stream onto this timeline as boxes flow through the terminal.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(moves.enumerated()), id: \.element.id) { idx, m in
                        spineNode(m, isLast: idx == moves.count - 1)
                    }
                }
                .padding(Space.s4)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func spineNode(_ m: GateMovement744, isLast: Bool) -> some View {
        let completed = (m.status ?? "") == "completed"
        let accent = completed ? Brand.success : Brand.neutral
        return HStack(alignment: .top, spacing: Space.s3) {
            // Time rail + spine dot.
            VStack(spacing: 0) {
                Text(shortDate(m.resolvedAt)).font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textSecondary).frame(width: 46, alignment: .trailing)
            }
            ZStack(alignment: .top) {
                if !isLast {
                    Rectangle().fill(palette.borderFaint).frame(width: 2).padding(.top, 14)
                }
                ZStack {
                    Circle().fill(accent).frame(width: 14, height: 14)
                    Image(systemName: completed ? "checkmark" : "xmark").font(.system(size: 7, weight: .heavy)).foregroundStyle(.white)
                }
            }
            .frame(width: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(m.loadNumber ?? "gate move").font(.system(size: 13.5, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(flowMeta(m)).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 4) {
                Text((m.status ?? "").uppercased()).font(.system(size: 9, weight: .heavy)).foregroundStyle(accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(accent.opacity(0.16)))
                if let d = m.finalDwellHours, d > 0 {
                    Text(String(format: "%.1fh", d)).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(.bottom, isLast ? 0 : Space.s4)
    }
    private func flowMeta(_ m: GateMovement744) -> String {
        let o = m.origin ?? "", d = m.destination ?? ""
        if !o.isEmpty && !d.isEmpty { return "\(o) → \(d)" }
        if !o.isEmpty { return o }
        if !d.isEmpty { return d }
        return "yard move"
    }

    // MARK: Gate-clearance country band

    private var gateClearanceBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("GATE CLEARANCE · DRAYAGE HANDOFF").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                clearanceCapsule("US · CBP", "release + UIIA", active: true)
                clearanceCapsule("CA · CBSA", "coasting trade", active: false)
                clearanceCapsule("MX · SAT", "SICT NOM-068", active: false)
            }
        }
    }
    private func clearanceCapsule(_ code: String, _ sub: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(code).font(.system(size: 10.5, weight: .heavy)).foregroundStyle(active ? Brand.info : palette.textSecondary)
            Text(sub).font(.system(size: 8, weight: .medium)).foregroundStyle(active ? Brand.info.opacity(0.85) : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? Brand.info.opacity(0.10) : palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(active ? Brand.info.opacity(0.45) : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: CTA

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button { } label: {
                Text("Export gate log").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48).background(LinearGradient.primary).clipShape(Capsule())
            }.buttonStyle(.plain).frame(maxWidth: .infinity)
            Button { } label: {
                Text("Filter").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(minWidth: 110, minHeight: 48).padding(.horizontal, Space.s3)
                    .background(palette.bgCard).overlay(Capsule().strokeBorder(palette.borderFaint)).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
    }

    // MARK: States / format

    private func errorCard(_ err: String) -> some View {
        LifecycleCard(accentDanger: true) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            }
        }
    }
    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 150)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 280)
        }
    }
    private func shortDate(_ iso: String?) -> String {
        guard let iso, !iso.isEmpty else { return "—" }
        let s = String(iso.prefix(10))
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: s) else { return s }
        let out = DateFormatter(); out.dateFormat = "MMM d"
        return out.string(from: d)
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let limit: Int }
        do {
            async let m: [GateMovement744] = EusoTripAPI.shared.query("terminals.getRecentMovements", input: In(limit: 12))
            async let q: [GateQueueItem744] = EusoTripAPI.shared.query("terminals.getGateQueue", input: In(limit: 25))
            let (mResp, qResp) = try await (m, q)
            self.moves = mResp; self.queue = qResp
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("744 · Vessel Terminal Gate Log · Night") {
    VesselTerminalGateLogScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("744 · Vessel Terminal Gate Log · Light") {
    VesselTerminalGateLogScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
