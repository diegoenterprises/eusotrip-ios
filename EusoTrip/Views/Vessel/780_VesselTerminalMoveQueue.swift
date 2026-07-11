//
//  780_VesselTerminalMoveQueue.swift
//  EusoTrip — Vessel Operator · Terminal Move Queue.
//
//  Verbatim port of wireframe 780 (06 Vessel · Dark) — a purpose-built
//  NOW-SERVING priority lane: the active move pulled out as a live ring-
//  progress node feeding a NEXT-UP ribbon, over an HRRN-ordered move-ticket
//  list. Distinct from 781 Drop Yard (occupancy grid).
//
//  Endpoints (server/routers/yardManagement.ts):
//    getYardMoveQueue (:1915 · {locationId?} → {moves:[{id,status,trailerNumber,
//      fromSpot,toSpot,priority,requestedAt,assignedTo,estimatedMinutes,
//      startedAt}], summary:{pending,inProgress,...}, hostlers:[{id,name,status,
//      currentMove}]}) — drives the hero, KPI strip, and list.
//    assignYardMove (:2001 · {moveId, hostlerId} mutation) — "Assign move".
//  Honest note: yardManagement is yard-scoped; the marine terminal maps ISO
//  6346 container moves onto the trailer-move queue — no invented procedure.
//

import SwiftUI

struct VesselTerminalMoveQueueScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselTerminalMoveQueueBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct MoveQueue780: Decodable {
    let moves: [YardMove780]
    let summary: MoveSummary780
    let hostlers: [Hostler780]
    private enum CodingKeys: String, CodingKey { case moves, summary, hostlers }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        moves    = (try? c.decode([YardMove780].self, forKey: .moves)) ?? []
        summary  = (try? c.decode(MoveSummary780.self, forKey: .summary)) ?? MoveSummary780()
        hostlers = (try? c.decode([Hostler780].self, forKey: .hostlers)) ?? []
    }
}

private struct MoveSummary780: Decodable {
    var pending = 0, assigned = 0, inProgress = 0, completed = 0, avgCompletionMinutes = 0
    init() {}
    private enum CodingKeys: String, CodingKey { case pending, assigned, inProgress, completed, avgCompletionMinutes }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        pending = (try? c.decode(Int.self, forKey: .pending)) ?? 0
        assigned = (try? c.decode(Int.self, forKey: .assigned)) ?? 0
        inProgress = (try? c.decode(Int.self, forKey: .inProgress)) ?? 0
        completed = (try? c.decode(Int.self, forKey: .completed)) ?? 0
        avgCompletionMinutes = (try? c.decode(Int.self, forKey: .avgCompletionMinutes)) ?? 0
    }
}

private struct YardMove780: Decodable, Identifiable {
    let id: String
    let status: String
    let trailerNumber: String?
    let fromSpot: String?
    let toSpot: String?
    let priority: String
    let requestedAt: String?
    let assignedTo: String?
    let reason: String?
    let estimatedMinutes: Int
    let startedAt: String?
    private enum CodingKeys: String, CodingKey {
        case id, status, trailerNumber, fromSpot, toSpot, priority, requestedAt, assignedTo, reason, estimatedMinutes, startedAt
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        status = (try? c.decode(String.self, forKey: .status)) ?? "pending"
        trailerNumber = try? c.decode(String.self, forKey: .trailerNumber)
        fromSpot = try? c.decode(String.self, forKey: .fromSpot)
        toSpot = try? c.decode(String.self, forKey: .toSpot)
        priority = (try? c.decode(String.self, forKey: .priority)) ?? "normal"
        requestedAt = try? c.decode(String.self, forKey: .requestedAt)
        assignedTo = try? c.decode(String.self, forKey: .assignedTo)
        reason = try? c.decode(String.self, forKey: .reason)
        estimatedMinutes = (try? c.decode(Int.self, forKey: .estimatedMinutes)) ?? 10
        startedAt = try? c.decode(String.self, forKey: .startedAt)
    }

    var route: String {
        let f = fromSpot ?? "—", t = toSpot ?? "—"
        let box = trailerNumber ?? "Container"
        return "\(box) · \(f) → \(t)"
    }
    var waitMinutes: Int {
        guard let r = requestedAt, let d = ISO780.date(r) else { return 0 }
        return max(0, Int(Date().timeIntervalSince(d) / 60))
    }
    /// HRRN-style rank: (wait + service) / service — higher served first.
    var responseRatio: Double {
        let s = Double(max(estimatedMinutes, 1))
        return (Double(waitMinutes) + s) / s + priorityBoost
    }
    private var priorityBoost: Double {
        switch priority.lowercased() { case "urgent": return 4; case "high": return 2; case "low": return -1; default: return 0 }
    }
    /// Live progress for an in-progress move (elapsed / estimate).
    var progress: Double? {
        guard status.lowercased() == "in_progress", let s = startedAt, let d = ISO780.date(s) else { return nil }
        let elapsed = Date().timeIntervalSince(d) / 60
        return max(0.02, min(0.98, elapsed / Double(max(estimatedMinutes, 1))))
    }
}

private struct Hostler780: Decodable, Identifiable {
    let id: String
    let name: String?
    let status: String?
    let currentMove: String?
    private enum CodingKeys: String, CodingKey { case id, name, status, currentMove }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = try? c.decode(String.self, forKey: .name)
        status = try? c.decode(String.self, forKey: .status)
        currentMove = try? c.decode(String.self, forKey: .currentMove)
    }
    var isAvailable: Bool { (status ?? "").lowercased() == "available" }
}

private enum ISO780 {
    static let f: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    static let f2 = ISO8601DateFormatter()
    static func date(_ s: String) -> Date? { f.date(from: s) ?? f2.date(from: s) }
}

// MARK: - Body

private struct VesselTerminalMoveQueueBody: View {
    @Environment(\.palette) private var palette
    @State private var data: MoveQueue780? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var assigning = false
    @State private var toast: String? = nil

    private var hrrn: [YardMove780] {
        (data?.moves ?? []).sorted { $0.responseRatio > $1.responseRatio }
    }
    private var nowServing: YardMove780? {
        data?.moves.first(where: { $0.status.lowercased() == "in_progress" }) ?? hrrn.first
    }
    private var onShift: Int { data?.hostlers.count ?? 0 }
    private var available: Int { data?.hostlers.filter { $0.isAvailable }.count ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDetailHeader(
                eyebrow: "VESSEL OPERATOR · MOVE QUEUE",
                caption: "UTR DISPATCH",
                title: "Move queue",
                idText: "LBCT · live"
            )
            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    skeleton
                } else if let err = loadError {
                    VesselErrorCard(text: err)
                } else if let data {
                    if let ns = nowServing { nowServingHero(ns) }
                    if let t = toast { VesselToastRow(text: t) }
                    kpiStrip(data.summary)
                    movesSection
                    ctaPair
                }
                Color.clear.frame(height: Space.s6)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // NOW-SERVING priority lane (ring progress + next-up ribbon)
    private func nowServingHero(_ m: YardMove780) -> some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("NOW SERVING · \(m.assignedTo ?? m.id)")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(Brand.success).frame(width: 6, height: 6)
                        Text("LIVE").font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(Brand.success)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(palette.tintSuccess))
                }
                HStack(alignment: .center, spacing: Space.s4) {
                    ringNode(m)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(m.route).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                        Text(subLine(m)).font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(palette.textSecondary).lineLimit(1)
                        Text(m.status.lowercased() == "in_progress" ? "en route · terminal move" : "next up · ready to assign")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(Brand.info)
                    }
                    Spacer(minLength: 0)
                }
                Divider().overlay(palette.borderFaint)
                nextUpRibbon
            }
        }
    }

    private func ringNode(_ m: YardMove780) -> some View {
        let p = m.progress
        return ZStack {
            Circle().stroke(palette.borderFaint, lineWidth: 7).frame(width: 58, height: 58)
            if let p {
                Circle().trim(from: 0, to: p)
                    .stroke(LinearGradient.diagonal, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 58, height: 58)
                Text("\(Int(p * 100))%").font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
            } else {
                Image(systemName: "shippingbox.fill").font(.system(size: 18, weight: .semibold)).foregroundStyle(LinearGradient.diagonal)
            }
        }
    }

    private var nextUpRibbon: some View {
        let upcoming = hrrn.filter { $0.status.lowercased() != "in_progress" }.prefix(2)
        let remaining = max(0, hrrn.count - upcoming.count - 1)
        return HStack(spacing: Space.s2) {
            Text("NEXT").font(.system(size: 8.5, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            ForEach(Array(upcoming)) { m in
                Text("\(m.fromSpot ?? "—")→\(m.toSpot ?? "—") · \(m.waitMinutes)m")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(PriorityStyle780.color(m.priority))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(PriorityStyle780.color(m.priority).opacity(0.12)))
                    .lineLimit(1)
            }
            if remaining > 0 {
                Text("+\(remaining) queued").font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(palette.tintNeutral))
            }
            Spacer(minLength: 0)
        }
    }

    private func kpiStrip(_ s: MoveSummary780) -> some View {
        HStack(spacing: Space.s3) {
            kpi(label: "QUEUED", value: "\(s.pending + s.assigned)", caption: longestWaitCaption, gradient: true)
            kpi(label: "IN-PROG", value: "\(s.inProgress)", caption: s.avgCompletionMinutes > 0 ? "avg \(s.avgCompletionMinutes) min" : "in motion", accent: Brand.info)
            kpi(label: "UTRs ON", value: "\(onShift)", caption: "\(available) available", accent: Brand.success)
        }
    }

    private var longestWaitCaption: String {
        let w = hrrn.filter { $0.status.lowercased() != "in_progress" }.map { $0.waitMinutes }.max() ?? 0
        return w > 0 ? "longest \(w) min" : "no wait"
    }

    private func kpi(label: String, value: String, caption: String, gradient: Bool = false, accent: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary).padding(.bottom, 8)
            Group {
                if gradient { Text(value).foregroundStyle(LinearGradient.diagonal) }
                else if let accent { Text(value).foregroundStyle(accent) }
                else { Text(value).foregroundStyle(palette.textPrimary) }
            }
            .font(.system(size: 22, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5).padding(.bottom, 4)
            Text(caption).font(.system(size: 9)).foregroundStyle(palette.textSecondary).lineLimit(1)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(gradient ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.14)) : AnyShapeStyle(palette.bgCardSoft))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var movesSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("MOVES · HRRN ORDER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getYardMoveQueue").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            if hrrn.isEmpty {
                EusoEmptyState(systemImage: "arrow.left.arrow.right", title: "No moves queued", subtitle: "Container repositions and vessel-load moves will queue here in HRRN order.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(hrrn.prefix(6).enumerated()), id: \.element.id) { idx, m in
                        if idx > 0 { Divider().overlay(palette.borderFaint) }
                        moveRow(m)
                    }
                    if hrrn.count > 6 {
                        Text("+\(hrrn.count - 6) more · HRRN = highest-response-ratio-next")
                            .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, Space.s3)
                    }
                }
                .padding(Space.s4).background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func moveRow(_ m: YardMove780) -> some View {
        let color = PriorityStyle780.color(m.priority)
        return HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.14)).frame(width: 40, height: 40)
                Image(systemName: PriorityStyle780.icon(m.reason)).font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(m.route).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(subLine(m)).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                StatusPill(text: statusLabel(m), kind: statusKind(m))
                Text(m.status.lowercased() == "in_progress" ? "\(m.estimatedMinutes) min" : "\(m.waitMinutes) min")
                    .font(.system(size: 12, weight: .bold)).monospacedDigit().foregroundStyle(color)
            }
        }
        .padding(.vertical, Space.s3)
    }

    private func subLine(_ m: YardMove780) -> String {
        let r = (m.reason ?? "reposition").replacingOccurrences(of: "_", with: " ")
        return "\(r.uppercased()) · UTR \(m.assignedTo ?? "unassigned")"
    }
    private func statusLabel(_ m: YardMove780) -> String {
        switch m.status.lowercased() {
        case "in_progress": return "IN-PROG"
        case "assigned": return "ASSIGNED"
        case "completed": return "DONE"
        default: return m.priority.uppercased()
        }
    }
    private func statusKind(_ m: YardMove780) -> StatusPill.Kind {
        switch m.status.lowercased() {
        case "in_progress": return .info
        case "completed": return .success
        default:
            switch m.priority.lowercased() { case "urgent", "high": return .warning; default: return .neutral }
        }
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Assign move", action: { Task { await assignTop() } }, isLoading: assigning)
            Button {} label: {
                Text("View roster").font(EType.title).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 150, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
            }.buttonStyle(.plain)
        }
    }

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 154)
            HStack(spacing: Space.s3) { ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 78) } }
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 200)
        }
    }

    // MARK: - Networking

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let locationId: String? }
        do {
            let d: MoveQueue780 = try await EusoTripAPI.shared.query(
                "yardManagement.getYardMoveQueue", input: In(locationId: nil))
            self.data = d
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func assignTop() async {
        guard let move = hrrn.first(where: { $0.status.lowercased() != "in_progress" }) ?? hrrn.first,
              let hostler = data?.hostlers.first(where: { $0.isAvailable }) ?? data?.hostlers.first else {
            toast = "No available UTR to assign"; return
        }
        assigning = true
        struct In: Encodable { let moveId: String; let hostlerId: String }
        do {
            let _: AssignResult780 = try await EusoTripAPI.shared.mutation(
                "yardManagement.assignYardMove", input: In(moveId: move.id, hostlerId: hostler.id))
            toast = "Assigned \(move.id) → \(hostler.name ?? hostler.id)"
            await load()
        } catch {
            toast = (error as? EusoTripAPIError)?.errorDescription ?? "Could not assign move"
        }
        assigning = false
    }
}

private struct AssignResult780: Decodable {
    let success: Bool?
    private enum CodingKeys: String, CodingKey { case success }
    init(from d: Decoder) throws {
        let c = try? d.container(keyedBy: CodingKeys.self)
        success = try? c?.decode(Bool.self, forKey: .success)
    }
}

private enum PriorityStyle780 {
    static func color(_ p: String) -> Color {
        switch p.lowercased() { case "urgent": return Brand.danger; case "high": return Color(hex: 0xC2410C); case "low": return Brand.neutral; default: return Brand.info }
    }
    static func icon(_ reason: String?) -> String {
        switch (reason ?? "").lowercased() {
        case "dock_assignment", "outbound_staging", "gate_staging": return "arrow.up.forward.square"
        case "repair_move": return "wrench.and.screwdriver"
        default: return "arrow.left.arrow.right"
        }
    }
}

#Preview("780 · Move Queue · Night") { VesselTerminalMoveQueueScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("780 · Move Queue · Light") { VesselTerminalMoveQueueScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
