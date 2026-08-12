//
//  780_VesselTerminalMoveQueue.swift
//  EusoTrip — Vessel Operator · Terminal Move Queue.
//
//  Faithful port of "780 Vessel Terminal Move Queue.svg" (Light + Dark), adapted onto the canonical
//  DesignSystem (Shell · BottomNav · Theme.Palette · StatusPill · CTAButton · IridescentHairline).
//  Role VESSEL_OPERATOR (carrier-side). Nav anchored to VesselOperatorNavController
//  (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME) — a move queue is an operations board, so
//  the SHIPMENTS slot is inked.
//
//  ARCHETYPE: BOARD — the duty officer is not reading one record, they are deciding which of N boxes
//  moves next and who takes it. A board is the only shape that lets depth, fleet and order be read
//  against each other in one glance.
//
//  LIVE FUSION: the queue-depth histogram, the UTR allocation strip, the ranked move rows and the
//  ESang sequence line are FOUR FACES OF ONE STATE. All four re-reason together off load(): the
//  histogram is moves[] bucketed by requestedAt, the strip is hostlers[], the rows are moves[]
//  re-ranked, the ESang line is the clearance arithmetic over the same array. Degraded provider
//  state surfaces an explicit error card, never a frozen number.
//
//  OFFLINE POLICY: READ_CACHED(60s) — the board reads from a 60 second cache and the assign commit is
//  REFUSED while the read is stale. Made visibly distinct three ways, all drawn and not merely
//  claimed: (1) the header subline stamps the read clock beside the cache ceiling and turns amber
//  past it; (2) the hero carries a live dot + READ stamp that flips to an amber CACHED stamp; (3)
//  once stale every GO chip drops to the outline state and the assign path refuses with an explicit
//  "refresh before assigning" notice rather than firing off a stale board.
//
//  Data / wiring (line numbers opened and read first-hand 2026-08-11; the legacy citations carried by
//  the retired wireframe had drifted by roughly 200 lines and are discarded):
//    yardManagement.getYardMoveQueue (EXISTS frontend/server/routers/yardManagement.ts:1940 ·
//      protectedProcedure · input {locationId?: string, status?: yardMoveStatusSchema} with the WHOLE
//      object optional · returns {moves:[{id,status,trailerNumber,fromSpot,toSpot,priority,
//      requestedAt,assignedTo,hostlerId,reason,estimatedMinutes,startedAt,completedAt}],
//      summary:{total,pending,assigned,inProgress,completed,avgCompletionMinutes},
//      hostlers:[{id,name,status,currentMove,movesCompleted}]}. Mounted routers.ts:1843.
//      READ TENANCY CORRECT — eq(yardMoves.companyId, companyId) at yardManagement.ts:1952, companyId
//      resolved at :1947. Named honestly: :1947 is `ctx.user!.companyId || 0`, so a user with no
//      company reads company 0 rather than being refused — not a cross-tenant leak, not a refusal.)
//    yardManagement.assignYardMove (EXISTS yardManagement.ts:2026 · protectedProcedure MUTATION at
//      :2033 · input {moveId: String, hostlerId: String, hostlerName?, notes?} -> {success, moveId,
//      hostlerId, assignedAt}. WRITE TENANCY IS THE HOUSE STANDARD, cited as such: :2038 resolves
//      ctx.isolation?.companyId ?? ctx.user?.companyId; :2039 computes isAdmin; :2042-2043 throws
//      FORBIDDEN when a non-admin has no company; :2049 scopes the UPDATE where with
//      and(eq(yardMoves.id, numericMoveId), eq(yardMoves.companyId, callerCompany)); :2066-2067
//      throws NOT_FOUND on affected === 0. Wired to the GO chip and to the primary CTA.)
//    STUB · named-gap yard-move-hold — no hold mutation exists in the router. Proposed shape:
//      yardManagement.holdYardMove({moveId: string, reason: string, untilAt?: string}) ->
//      {success, moveId, status:"pending", heldUntil}, company-scoped with the :2049 where clause.
//    STUB · named-gap yard-move-repriority — no re-priority mutation exists. Proposed shape:
//      yardManagement.reprioritizeYardMove({moveId: string, priority: "low"/"normal"/"high"/"urgent"})
//      -> {success, moveId, priority}, company-scoped with the same where clause.
//    CHAIN-OPEN: assign move — yardManagement.ts:2026 commits a REAL DB row but does not broadcast and
//      does not audit. yardManagement.ts carries ZERO blockchainAuditTrail writes and ZERO
//      wsService/getIO/broadcast calls across all 2542 lines. WS_EVENTS.TERMINAL_QUEUE_UPDATE
//      (shared/websocket-events.ts:225) and TERMINAL_DOCK_ASSIGNED (:223) exist with zero emitters and
//      WS_CHANNELS.TERMINAL_QUEUE (:598, wire terminal:<id>:queue) has zero emitters — while the
//      RECEIVER IS ALREADY BUILT at client/src/hooks/useRealtimeEvents.ts:786. The hostler you just
//      assigned never learns. This screen fires the write and says so on the face of the success
//      banner; it never claims the counter-party was notified.
//    RBAC: both procedures are protectedProcedure — AUTH ONLY, no mode gate and no role gate.
//      vesselProcedure (server/_core/trpc.ts:268) is NOT applied here, so an authenticated TRUCK-only
//      DRIVER can read this marine move queue and can assign a hostler. Filed as P0-RBAC-MODE. The
//      only role-gated procedure in the whole router is moveTrailer (yardManagement.ts:440) on
//      yardOpsProcedure (defined yardManagement.ts:19 — TERMINAL_MANAGER, DISPATCH, ADMIN,
//      SUPER_ADMIN) — the gate assignYardMove should also carry.
//
//  ZERO-FALLBACK: state starts EMPTY, the loader overwrites UNCONDITIONALLY, an honest empty response
//  renders the bespoke empty state and never fabricated rows. Every number on this screen is derived
//  from the loaded payload — depth from requestedAt/status, served rate from avgCompletionMinutes and
//  the active hostler count, ETA-to-serve from estimatedMinutes, chip fill from movesCompleted. There
//  is no forecast field on the wire and the card says DERIVED on its face. File-scoped types are
//  suffixed 780 to avoid cross-file private collisions.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI
import Combine

// MARK: - Screen wrapper (Shell + vessel nav · SHIPMENTS inked)

struct VesselTerminalMoveQueueScreen: View {
    let theme: Theme.Palette
    /// Optional yard/terminal scope. Empty (registry / zero-arg use) omits `locationId`
    /// on the wire, which the procedure accepts — the whole input object is optional.
    var locationId: String = ""

    init(theme: Theme.Palette, locationId: String = "") {
        self.theme = theme; self.locationId = locationId
    }

    var body: some View {
        Shell(theme: theme) {
            VesselTerminalMoveQueueBody780(locationId: locationId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",         systemImage: "person",                isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Wire shapes (mirror getYardMoveQueue's return EXACTLY)

/// Integer-ish column that may arrive as Int, Double or String off a SQL driver.
private struct FlexNum780: Decodable {
    let value: Double
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d; return }
        if let i = try? c.decode(Int.self) { value = Double(i); return }
        if let s = try? c.decode(String.self), let d = Double(s) { value = d; return }
        value = 0
    }
    var int: Int { Int(value.rounded()) }
}

/// `moves[]` row.
private struct YardMove780: Decodable, Identifiable {
    let id: String
    let status: String?
    let trailerNumber: String?
    let fromSpot: String?
    let toSpot: String?
    let priority: String?
    let requestedAt: String?
    let assignedTo: String?
    let hostlerId: String?
    let reason: String?
    let estimatedMinutes: FlexNum780?
    let startedAt: String?
    let completedAt: String?
}

/// `summary` block.
private struct QueueSummary780: Decodable {
    let total: FlexNum780?
    let pending: FlexNum780?
    let assigned: FlexNum780?
    let inProgress: FlexNum780?
    let completed: FlexNum780?
    let avgCompletionMinutes: FlexNum780?
}

/// `hostlers[]` row — the UTR allocation strip reads this directly.
private struct QueueHostler780: Decodable, Identifiable {
    let id: String
    let name: String?
    let status: String?
    let currentMove: String?
    let movesCompleted: FlexNum780?
}

private struct QueuePayload780: Decodable {
    let moves: [YardMove780]?
    let summary: QueueSummary780?
    let hostlers: [QueueHostler780]?
}

// MARK: - Derived shapes (nothing here is a seed; every field comes off the payload)

/// One half-hour bucket of the hero histogram.
private struct DepthBucket780: Identifiable {
    let id: Int
    let clock: String
    let depth: Int
    let served: Int
}

/// The three trigger states. Only `.go` has a mutation behind it.
private enum Trigger780 { case go, hold, bump
    var label: String { switch self { case .go: return "GO"; case .hold: return "HOLD"; case .bump: return "BUMP" } }
}

/// A ranked, derived view of one move row.
private struct RankedMove780: Identifiable {
    let id: String
    let rank: Int
    let box: String
    let reason: String
    let route: String
    let priority: String
    let etaMinutes: Int
    let trigger: Trigger780
    let status: String
}

// MARK: - Body

private struct VesselTerminalMoveQueueBody780: View {
    @Environment(\.palette) private var palette
    let locationId: String

    // Live state only — no seeds anywhere.
    @State private var moves: [YardMove780] = []
    @State private var hostlers: [QueueHostler780] = []
    @State private var summary: QueueSummary780? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // READ_CACHED(60s) clock
    @State private var lastRead: Date? = nil
    @State private var now = Date()
    private let cacheCeiling: TimeInterval = 60
    /// Static so the publisher is created once for the process rather than on every body eval.
    private static let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    // Write state
    @State private var assigning = false
    @State private var assignResult: String? = nil
    @State private var assignError: String? = nil
    @State private var gapNotice: String? = nil
    @State private var showRoster = false

    private let horizon = 8            // 8 half-hours = the next 4 hours

    // MARK: Derived — every organ reads THIS state -------------------------

    private var isStale: Bool {
        guard let r = lastRead else { return false }
        return now.timeIntervalSince(r) > cacheCeiling
    }
    private var readClock: String {
        guard let r = lastRead else { return "—" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: r)
    }

    /// Moves still waiting to be worked: pending or assigned, and not yet started.
    private var backlogMoves: [YardMove780] {
        moves.filter { m in
            let s = (m.status ?? "pending").lowercased()
            return (s == "pending" || s == "assigned") && (m.startedAt == nil || m.startedAt!.isEmpty)
        }
    }
    private var pendingMoves: [YardMove780] {
        moves.filter { ($0.status ?? "pending").lowercased() == "pending" }
    }
    private var inProgressCount: Int {
        moves.filter { ($0.status ?? "").lowercased() == "in_progress" }.count
    }
    private var activeHostlers: Int {
        max(hostlers.filter { ($0.status ?? "").lowercased() == "busy" || $0.currentMove != nil }.count, 0)
    }
    private var openHostlers: [QueueHostler780] {
        hostlers.filter { ($0.status ?? "").lowercased() != "busy" && $0.currentMove == nil }
    }
    private var shiftLeader: Int {
        max(hostlers.compactMap { $0.movesCompleted?.int }.max() ?? 0, 1)
    }

    /// Mean minutes a move takes. Prefers the server's measured average; falls back to the mean of
    /// the queue's own estimatedMinutes. Returns nil when neither is knowable — in which case the
    /// histogram refuses to project rather than inventing a rate.
    private var minutesPerMove: Double? {
        if let avg = summary?.avgCompletionMinutes?.value, avg > 0 { return avg }
        let ests = backlogMoves.compactMap { $0.estimatedMinutes?.value }.filter { $0 > 0 }
        guard !ests.isEmpty else { return nil }
        return ests.reduce(0, +) / Double(ests.count)
    }

    /// Moves the fleet can complete per half-hour. Derived from the measured minutes-per-move and the
    /// number of units actually working. nil when the rate is not knowable.
    private var servedPerHalfHour: Double? {
        guard let mpm = minutesPerMove, mpm > 0 else { return nil }
        let fleet = Double(max(activeHostlers, 1))
        return (30.0 / mpm) * fleet
    }

    /// Observed arrival run-rate: requests landed in the last two hours, expressed per half-hour.
    /// This is a measured run-rate off `requestedAt`, NOT a forecast, and the card says so.
    private var arrivalsPerHalfHour: Double {
        let cutoff = now.addingTimeInterval(-2 * 3600)
        let recent = moves.compactMap { Self.parse($0.requestedAt) }.filter { $0 >= cutoff }
        guard !recent.isEmpty else { return 0 }
        return Double(recent.count) / 4.0
    }

    /// The hero histogram. depth(k) walks the backlog forward at the observed arrival run-rate less
    /// the derived served rate; served(k) is capped at what is actually there to serve.
    private var buckets: [DepthBucket780] {
        guard let served = servedPerHalfHour else { return [] }
        var out: [DepthBucket780] = []
        var depth = Double(backlogMoves.count)
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        var cursor = Self.nextHalfHour(after: now)
        for k in 0..<horizon {
            let servedHere = min(served, max(depth + arrivalsPerHalfHour, 0))
            depth = max(0, depth + arrivalsPerHalfHour - served)
            out.append(DepthBucket780(id: k,
                                      clock: f.string(from: cursor),
                                      depth: Int(depth.rounded()),
                                      served: Int(servedHere.rounded())))
            cursor = cursor.addingTimeInterval(1800)
        }
        return out
    }

    /// Index of the bucket where the served rate first overtakes the depth — the clearance crossing.
    private var crossingIndex: Int? { buckets.firstIndex { $0.served > $0.depth } }

    /// Wall-clock moment the backlog reaches zero, interpolated inside the crossing bucket.
    /// nil when the fleet never catches the arrival rate — which the card states plainly.
    private var clearsAt: String? {
        guard let served = servedPerHalfHour, served > arrivalsPerHalfHour else { return nil }
        let net = served - arrivalsPerHalfHour
        guard net > 0 else { return nil }
        let halfHours = Double(backlogMoves.count) / net
        guard halfHours.isFinite, halfHours >= 0, halfHours <= Double(horizon) else { return nil }
        let start = Self.nextHalfHour(after: now)
        let when = start.addingTimeInterval(halfHours * 1800)
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: when)
    }

    /// The highest depth in the projection after the first clearance — the second wave, if any.
    private var rebuild: DepthBucket780? {
        guard let c = crossingIndex, c + 1 < buckets.count else { return nil }
        let tail = buckets[(c + 1)...]
        guard let peak = tail.max(by: { $0.depth < $1.depth }), peak.depth > 0 else { return nil }
        return peak
    }

    /// The move rows, re-ranked client-side: priority band, then oldest request first. The server
    /// ships ORDER BY requestedAt DESC, so this ranking is ours and is labelled as such on screen.
    private var ranked: [RankedMove780] {
        let ordered = backlogMoves.sorted { a, b in
            let pa = Self.priorityWeight(a.priority), pb = Self.priorityWeight(b.priority)
            if pa != pb { return pa > pb }
            let ta = Self.parse(a.requestedAt) ?? .distantFuture
            let tb = Self.parse(b.requestedAt) ?? .distantFuture
            return ta < tb
        }
        let fleet = Double(max(activeHostlers, 1))
        var cumulative = 0.0
        var out: [RankedMove780] = []
        for (i, m) in ordered.enumerated() {
            let est = m.estimatedMinutes?.value ?? 0
            let eta = Int((cumulative / fleet).rounded())
            cumulative += est
            let status = (m.status ?? "pending").lowercased()
            let trigger: Trigger780
            if status == "pending" { trigger = i == 0 ? .go : .bump } else { trigger = .hold }
            let from = (m.fromSpot ?? "").isEmpty ? "—" : m.fromSpot!
            let to   = (m.toSpot ?? "").isEmpty ? "—" : m.toSpot!
            out.append(RankedMove780(
                id: m.id,
                rank: i + 1,
                box: (m.trailerNumber ?? m.id),
                reason: (m.reason ?? "reposition").replacingOccurrences(of: "_", with: " "),
                route: "\(from) → \(to)",
                priority: (m.priority ?? "normal"),
                etaMinutes: eta,
                trigger: trigger,
                status: status))
        }
        return out
    }

    private var topPending: RankedMove780? { ranked.first { $0.trigger == .go } }

    // MARK: Body ------------------------------------------------------------

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleRow
                IridescentHairline()
                if loading {
                    loadingState
                } else if let err = loadError {
                    errorState(err)
                } else if moves.isEmpty && hostlers.isEmpty {
                    emptyState
                } else {
                    heroHistogram
                    derivationNote
                    utrAllocationStrip
                    moveBoard
                    if let notice = gapNotice { gapCard(notice) }
                    if let ok = assignResult { assignBanner(ok) }
                    if let bad = assignError { assignErrorCard(bad) }
                    esangRead
                    countryFooter
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
        .onReceive(Self.tick) { now = $0 }
        .sheet(isPresented: $showRoster) {
            HostlerRosterSheet780(hostlers: hostlers, shiftLeader: shiftLeader)
                .environment(\.palette, palette)
        }
    }

    // MARK: Header

    private var eyebrow: some View {
        HStack {
            HStack(spacing: 5) {
                Text("\u{2726}").font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.primary)
                Text("VESSEL · MOVE QUEUE · UTR DISPATCH")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
            }
            Spacer(minLength: 8)
            Text(locationId.isEmpty ? "ALL TERMINALS" : locationId.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundColor(palette.textTertiary)
        }
    }

    private var titleRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Move queue")
                .font(EType.h1).kerning(-0.4)
                .foregroundColor(palette.textPrimary)
            // OFFLINE POLICY affordance #1 — drawn staleness, never claimed.
            Text(sublineText)
                .font(EType.caption)
                .foregroundColor(isStale ? Brand.warning : palette.textSecondary)
        }
    }

    private var sublineText: String {
        let p = pendingMoves.count
        let ip = inProgressCount
        if lastRead == nil { return "\(p) pending · \(ip) in progress · cache ceiling 60s" }
        return isStale
            ? "\(p) pending · \(ip) in progress · CACHED \(readClock) · past the 60s ceiling · pull to refresh"
            : "\(p) pending · \(ip) in progress · read \(readClock) · cache ceiling 60s"
    }

    // MARK: HERO ORGAN — queue-depth histogram + served-rate step + clearance stem

    private var heroHistogram: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 6) {
                Text("QUEUE DEPTH · NEXT 8 HALF-HOURS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundColor(palette.textTertiary)
                Spacer(minLength: 8)
                // OFFLINE POLICY affordance #2 — the live dot flips amber and the stamp says CACHED.
                Circle().fill(isStale ? Brand.warning : Brand.success).frame(width: 6, height: 6)
                Text("\(isStale ? "CACHED" : "READ") \(readClock)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).monospacedDigit()
                    .foregroundColor(isStale ? Brand.warning : palette.textTertiary)
            }

            if buckets.isEmpty {
                // The rate is not knowable from this payload — refuse to project.
                Text("No completed move on this board yet, so the drain rate is not measurable. The projection stays blank until the first move completes rather than showing a fabricated curve.")
                    .font(EType.caption)
                    .foregroundColor(palette.textSecondary)
                    .padding(.vertical, Space.s3)
            } else {
                plot.frame(height: 132)
                Rectangle().fill(palette.borderFaint).frame(height: 1)
                HStack(spacing: 6) {
                    ForEach(buckets) { b in
                        Text(b.clock)
                            .font(.system(size: 8, weight: .bold)).tracking(0.4)
                            .foregroundColor(rebuild?.id == b.id ? Brand.warning : palette.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.xl)
    }

    private var plot: some View {
        GeometryReader { geo in
            let n = max(buckets.count, 1)
            let pitch = geo.size.width / CGFloat(n)
            let colW = max(pitch - 8, 6)
            let scaleMax = max(buckets.map(\.depth).max() ?? 1,
                               buckets.map(\.served).max() ?? 1, 1)
            let usable = geo.size.height - 16          // headroom for the depth numerals
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(buckets) { b in
                        VStack(spacing: 3) {
                            Text("\(b.depth)")
                                .font(.system(size: 9, weight: .bold)).monospacedDigit()
                                .foregroundColor(rebuild?.id == b.id ? Brand.warning
                                                 : (isBacklog(b) ? palette.textPrimary : palette.textSecondary))
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(columnStyle(b))
                                .frame(width: colW,
                                       height: max(3, usable * CGFloat(b.depth) / CGFloat(scaleMax)))
                        }
                        .frame(width: pitch)
                    }
                }
                ServedStep780(values: buckets.map { CGFloat($0.served) / CGFloat(scaleMax) },
                              pitch: pitch, plotHeight: usable)
                    .stroke(LinearGradient.diagonal,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                Text("SERVED RATE")
                    .font(.system(size: 8, weight: .bold)).tracking(0.4)
                    .foregroundColor(Brand.blue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                if let c = crossingIndex, let when = clearsAt {
                    clearanceStem(when: when)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .offset(x: CGFloat(c) * pitch + pitch * 0.55)
                }
            }
        }
    }

    private func isBacklog(_ b: DepthBucket780) -> Bool {
        guard let c = crossingIndex else { return true }
        return b.id <= c
    }

    private func columnStyle(_ b: DepthBucket780) -> AnyShapeStyle {
        if rebuild?.id == b.id { return AnyShapeStyle(Brand.warning.opacity(0.34)) }
        if isBacklog(b) { return AnyShapeStyle(LinearGradient.diagonal.opacity(0.90)) }
        return AnyShapeStyle(Brand.blue.opacity(0.18))
    }

    /// The 2 x 96 clearance stem of the wireframe, annotated in 11/700 tabular.
    private func clearanceStem(when: String) -> some View {
        ZStack(alignment: .top) {
            Rectangle().fill(LinearGradient.primary).frame(width: 2, height: 96)
            Circle().fill(LinearGradient.diagonal).frame(width: 6, height: 6).offset(y: -3)
            Text("clears \(when)")
                .font(.system(size: 11, weight: .bold)).monospacedDigit()
                .foregroundColor(palette.textPrimary)
                .fixedSize()
                .offset(x: 44, y: -14)
        }
        .frame(width: 2, height: 96, alignment: .top)
    }

    private var derivationNote: some View {
        Text(clearsAt == nil
             ? "depth = pending + assigned · rate = completed / 30 min · on the current rate this backlog does not clear inside 4 hours"
             : "depth = pending + assigned · rate = completed / 30 min · derived, not forecast")
            .font(.system(size: 9, weight: .regular))
            .foregroundColor(palette.textTertiary)
    }

    // MARK: MID-BAND ORGAN — UTR (hostler) allocation strip

    private var utrAllocationStrip: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("UTR ALLOCATION · \(hostlers.count) ON SHIFT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundColor(palette.textTertiary)
                Spacer(minLength: 8)
                Text("\(activeHostlers) ASSIGNED · \(openHostlers.count) OPEN")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundColor(palette.textTertiary)
            }

            if hostlers.isEmpty {
                Text("No hostler is attached to any move in this window. hostlers[] is assembled from rows that carry a hostlerId, so an empty strip means nothing has been assigned yet — not that the yard has no units.")
                    .font(EType.caption)
                    .foregroundColor(palette.textSecondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(hostlers) { u in hostlerChip(u) }
                    }
                    .padding(.vertical, 2)
                }
                Text("fill = moves done vs shift leader · tail = current move · outline = idle")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundColor(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private func hostlerChip(_ u: QueueHostler780) -> some View {
        let done = u.movesCompleted?.int ?? 0
        let busy = (u.status ?? "").lowercased() == "busy" || u.currentMove != nil
        let fill = CGFloat(done) / CGFloat(shiftLeader)
        return VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                if busy {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(palette.tintNeutral)
                    Rectangle().fill(Brand.blue.opacity(0.20))
                        .frame(height: max(0, 40 * min(fill, 1)))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Brand.blue.opacity(0.40), lineWidth: 1)
                } else {
                    // idle units are OUTLINE-ONLY
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(palette.textTertiary.opacity(0.55),
                                      style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                VStack(spacing: 1) {
                    Text(u.id)
                        .font(.system(size: 10, weight: .heavy)).tracking(0.3)
                        .foregroundColor(busy ? palette.textPrimary : palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("\(done) mv")
                        .font(.system(size: 9, weight: .bold)).monospacedDigit()
                        .foregroundColor(busy ? Brand.blue : palette.textTertiary)
                }
                .padding(.horizontal, 3)
            }
            .frame(width: 56, height: 40)

            if busy, let move = u.currentMove {
                // 2px assignment tail dropping onto the move this unit is on
                Rectangle().fill(Brand.blue.opacity(0.45)).frame(width: 2, height: 18)
                Rectangle().fill(Brand.blue.opacity(0.45)).frame(width: 12, height: 2)
                Text(move)
                    .font(EType.mono(.micro))
                    .foregroundColor(palette.textSecondary)
                    .padding(.top, 6)
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Color.clear.frame(width: 2, height: 20)
                Text("open")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(palette.textTertiary)
                    .padding(.top, 6)
            }
        }
        .frame(width: 56)
    }

    // MARK: ROWS — rank numeral square · yard coordinates · ETA · trigger chip

    private var moveBoard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("MOVE ORDER · RANKED")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundColor(palette.textTertiary)
                Spacer(minLength: 8)
                Text("\(ranked.count) waiting · LIVE YARD QUEUE")
                    .font(EType.mono(.caption))
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }

            if ranked.isEmpty {
                Text("Nothing is waiting. Every move on this board is in progress or complete.")
                    .font(EType.caption)
                    .foregroundColor(palette.textSecondary)
                    .padding(Space.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .eusoCard(radius: Radius.lg)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(ranked.enumerated()), id: \.element.id) { idx, m in
                        moveRow(m)
                        if idx < ranked.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                    Text("rank = priority band then oldest request · GO assigns the first open UTR")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(palette.textTertiary)
                        .padding(.horizontal, Space.s4).padding(.top, Space.s3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, Space.s3)
                .eusoCard(radius: Radius.lg)
            }
        }
    }

    private func moveRow(_ m: RankedMove780) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            // 26x26 rx6 priority-rank numeral square — NOT a 40x40 icon chip
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(rankFill(m.priority))
                Text("\(m.rank)")
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(rankInk(m.priority))
            }
            .frame(width: 26, height: 26)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(m.box) · \(m.reason)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text("\(m.route) · \(m.priority)")
                    .font(EType.mono(.caption))
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                Text(m.etaMinutes == 0 ? "next" : "\(m.etaMinutes) min")
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundColor(palette.textPrimary)
                triggerButton(m)
            }
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s2)
    }

    private func rankFill(_ p: String) -> AnyShapeStyle {
        switch p.lowercased() {
        case "urgent": return AnyShapeStyle(LinearGradient.diagonal)
        case "high":   return AnyShapeStyle(palette.tintWarning)
        default:       return AnyShapeStyle(palette.tintNeutral)
        }
    }
    private func rankInk(_ p: String) -> AnyShapeStyle {
        switch p.lowercased() {
        case "urgent": return AnyShapeStyle(Color.white)
        case "high":   return AnyShapeStyle(Brand.warning)
        default:       return AnyShapeStyle(palette.textSecondary)
        }
    }

    /// 58x22 rx11 trigger. Every state is a REAL Button: GO fires the real mutation, HOLD and BUMP
    /// surface the honest named gap with its proposed shape. None of them fakes a state change.
    private func triggerButton(_ m: RankedMove780) -> some View {
        Button {
            switch m.trigger {
            case .go:
                Task { await assign(moveId: m.id) }
            case .hold:
                gapNotice = "HOLD is not available yet. Nothing was changed and the queue is unaffected — the hold you just tapped was not recorded anywhere. Hold the unit over the radio instead."
                assignResult = nil; assignError = nil
            case .bump:
                gapNotice = "BUMP is not available yet. The rank you see was worked out on this device and was NOT saved — the queue everyone else works from is unchanged. Re-order with the yard over the radio."
                assignResult = nil; assignError = nil
            }
        } label: {
            ZStack {
                triggerBackground(m.trigger)
                Text(m.trigger.label)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(triggerInk(m.trigger))
            }
            .frame(width: 58, height: 22)
        }
        .buttonStyle(.plain)
        .disabled(assigning)
        .opacity(assigning ? 0.6 : 1.0)
    }

    @ViewBuilder
    private func triggerBackground(_ t: Trigger780) -> some View {
        switch t {
        case .go:
            // Stale board => GO drops to the outline state and the commit refuses.
            if isStale {
                Capsule().strokeBorder(Brand.warning.opacity(0.75), lineWidth: 1)
            } else {
                Capsule().fill(LinearGradient.primary)
            }
        case .hold:
            Capsule().fill(palette.tintWarning)
        case .bump:
            Capsule().strokeBorder(palette.textTertiary.opacity(0.55), lineWidth: 1)
        }
    }
    private func triggerInk(_ t: Trigger780) -> AnyShapeStyle {
        switch t {
        case .go:   return isStale ? AnyShapeStyle(Brand.warning) : AnyShapeStyle(Color.white)
        case .hold: return AnyShapeStyle(Brand.warning)
        case .bump: return AnyShapeStyle(palette.textSecondary)
        }
    }

    // MARK: Notices

    private func gapCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                StatusPill(text: "Named gap", kind: .warning)
                Spacer()
                Button("Dismiss") { gapNotice = nil }
                    .font(EType.micro).foregroundColor(palette.textSecondary)
            }
            Text(text).font(EType.caption).foregroundColor(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private func assignBanner(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                StatusPill(text: "Assigned", kind: .success)
                Spacer()
                Button("Dismiss") { assignResult = nil }
                    .font(EType.micro).foregroundColor(palette.textSecondary)
            }
            Text(text).font(EType.caption).foregroundColor(palette.textSecondary)
            // CHAIN-OPEN, stated on the face of the success banner. Never claim a notification.
            Text("Move saved. The hostler is NOT notified — this yard has no live dispatch link yet, nothing was broadcast and no audit entry was written. Tell the unit over the radio.")
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(palette.textTertiary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private func assignErrorCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                StatusPill(text: "Not assigned", kind: .danger)
                Spacer()
                Button("Dismiss") { assignError = nil }
                    .font(EType.micro).foregroundColor(palette.textSecondary)
            }
            Text(text).font(EType.caption).foregroundColor(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: ESang sequence read (derived off the same array; off the stamped tail rhythm)

    private var esangRead: some View {
        HStack(alignment: .top, spacing: 11) {
            RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.diagonal)
                .frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("ESANG · SEQUENCE READ")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundColor(palette.textTertiary)
                    Spacer(minLength: 8)
                    Text("DERIVED · ADVISORY")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundColor(palette.textTertiary)
                }
                Text(esangLine)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoRow(radius: Radius.md)
    }

    private var esangLine: String {
        guard let when = clearsAt else {
            if servedPerHalfHour == nil {
                return "No completed move yet, so no clearance can be computed from this board."
            }
            return "On the current rate the backlog does not clear inside the next 4 hours."
        }
        if let r = rebuild {
            return "Clears \(when), then re-builds to \(r.depth) by \(r.clock)."
        }
        return "Clears \(when) and stays clear across the projection."
    }

    // MARK: Tri-country authority footer (small; content, never a feature organ)

    private var countryFooter: some View {
        HStack(spacing: 0) {
            countryCell("US · FMC MTO · USD")
            Rectangle().fill(palette.borderSoft).frame(width: 1, height: 16)
            countryCell("CA · CBSA · CAD")
            Rectangle().fill(palette.borderSoft).frame(width: 1, height: 16)
            countryCell("MX · API SAT · MXN")
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity)
        .eusoRow(radius: Radius.sm)
    }
    private func countryCell(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(palette.textSecondary)
            .lineLimit(1).minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
    }

    // MARK: CTA pair (228 + 164 in the wireframe; proportional here)

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Assign to hostler",
                      action: { Task { await assign(moveId: topPending?.id) } },
                      isLoading: assigning)
                .frame(maxWidth: .infinity)
                .layoutPriority(2)
            Button { showRoster = true } label: {
                Text("Hostler roster")
                    .font(EType.title)
                    .foregroundColor(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft))
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
        }
    }

    // MARK: States

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ProgressView()
            Text("Reading the move queue…")
                .font(EType.caption).foregroundColor(palette.textSecondary)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private func errorState(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            StatusPill(text: "Queue unavailable", kind: .danger)
            Text(err).font(EType.caption).foregroundColor(palette.textSecondary)
            Text("The yard move queue did not answer. Nothing below is coming from a cache and no count has been carried over from the last read — treat the board as unknown until it loads.")
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(palette.textTertiary)
            Button("Retry") { Task { await load() } }
                .font(EType.bodyStrong).foregroundColor(Brand.blue)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            StatusPill(text: "Queue clear", kind: .success)
            Text("No move is queued for this company")
                .font(EType.title).foregroundColor(palette.textPrimary)
            Text("The move queue came back empty. Every box is where it should be, or no move has been raised against \(locationId.isEmpty ? "any terminal" : locationId) yet. Nothing here is being shown from a cache.")
                .font(EType.caption).foregroundColor(palette.textSecondary)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Loader — real client call; on failure set loadError, never fabricate

    private func load() async {
        loading = true; loadError = nil
        struct QueueIn780: Encodable { let locationId: String? }
        do {
            let payload: QueuePayload780 = try await EusoTripAPI.shared.query(
                "yardManagement.getYardMoveQueue",
                input: QueueIn780(locationId: locationId.isEmpty ? nil : locationId))
            // UNCONDITIONAL overwrite — an honest empty board clears every organ.
            moves = payload.moves ?? []
            hostlers = payload.hostlers ?? []
            summary = payload.summary
            lastRead = Date()
            now = Date()
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    // MARK: Write — the real assignYardMove mutation

    private func assign(moveId: String?) async {
        assignResult = nil; assignError = nil; gapNotice = nil
        // OFFLINE POLICY affordance #3 — never commit off a stale board.
        guard !isStale else {
            assignError = "This board was read at \(readClock), past the 60 second cache ceiling. Pull to refresh before assigning so you are not handing a box to a unit that has already moved on."
            return
        }
        guard let moveId, !moveId.isEmpty else {
            assignError = "Nothing pending to assign. Every move on this board is already assigned or in progress."
            return
        }
        guard let unit = openHostlers.first else {
            assignError = "No UTR is open. Every unit on shift already carries a move, so the assignment was not sent."
            return
        }
        assigning = true
        struct AssignIn780: Encodable { let moveId: String; let hostlerId: String; let hostlerName: String? }
        struct AssignOut780: Decodable { let success: Bool?; let moveId: String?; let hostlerId: String?; let assignedAt: String? }
        do {
            let out: AssignOut780 = try await EusoTripAPI.shared.mutation(
                "yardManagement.assignYardMove",
                input: AssignIn780(moveId: moveId, hostlerId: unit.id, hostlerName: unit.name))
            assignResult = "\(out.moveId ?? moveId) assigned to \(unit.name ?? unit.id)."
            await load()
        } catch {
            assignError = error.eusoUserCopy
        }
        assigning = false
    }

    // MARK: Small helpers

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return isoFractional.date(from: s) ?? isoPlain.date(from: s)
    }

    static func nextHalfHour(after d: Date) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        let m = comps.minute ?? 0
        if m < 30 {
            comps.minute = 30
        } else {
            comps.minute = 0
            comps.hour = (comps.hour ?? 0) + 1
        }
        comps.second = 0
        return cal.date(from: comps) ?? d.addingTimeInterval(1800)
    }

    static func priorityWeight(_ p: String?) -> Int {
        switch (p ?? "normal").lowercased() {
        case "urgent": return 3
        case "high":   return 2
        case "normal": return 1
        default:       return 0
        }
    }
}

// MARK: - The served-rate stepped polyline

private struct ServedStep780: Shape {
    /// Served value per bucket, already normalised to 0…1 of the plot height.
    let values: [CGFloat]
    let pitch: CGFloat
    let plotHeight: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard !values.isEmpty else { return p }
        func y(_ v: CGFloat) -> CGFloat { rect.maxY - plotHeight * min(max(v, 0), 1) }
        var x: CGFloat = 0
        p.move(to: CGPoint(x: x, y: y(values[0])))
        for i in values.indices {
            let nextX = min(rect.maxX, x + pitch)
            p.addLine(to: CGPoint(x: nextX, y: y(values[i])))
            if i + 1 < values.count, values[i + 1] != values[i] {
                p.addLine(to: CGPoint(x: nextX, y: y(values[i + 1])))
            }
            x = nextX
        }
        return p
    }
}

// MARK: - Hostler roster sheet (reads hostlers[] off the SAME payload — no second procedure)

private struct HostlerRosterSheet780: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let hostlers: [QueueHostler780]
    let shiftLeader: Int

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Text("This roster is built from the units already attached to moves on the queue. EusoTrip has no separate yard roster, so a unit that has never taken a move will not appear here.")
                        .font(EType.caption).foregroundColor(palette.textTertiary)

                    if hostlers.isEmpty {
                        Text("No unit is attached to a move on this board.")
                            .font(EType.body).foregroundColor(palette.textSecondary)
                            .padding(Space.s4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .eusoCard(radius: Radius.lg)
                    } else {
                        ForEach(hostlers) { u in
                            HStack(spacing: Space.s3) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(u.name ?? u.id)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(palette.textPrimary)
                                    Text("\(u.id) · \(u.currentMove ?? "no current move")")
                                        .font(EType.mono(.caption))
                                        .foregroundColor(palette.textSecondary)
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("\(u.movesCompleted?.int ?? 0) mv")
                                        .font(.system(size: 14, weight: .bold)).monospacedDigit()
                                        .foregroundColor(palette.textPrimary)
                                    StatusPill(text: (u.status ?? "unknown"),
                                               kind: (u.status ?? "").lowercased() == "busy" ? .info : .success)
                                }
                            }
                            .padding(Space.s4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .eusoRow(radius: Radius.md)
                        }
                    }
                }
                .padding(Space.s5)
            }
            .background(palette.bgPage.ignoresSafeArea())
            .navigationTitle("Hostler roster")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview("780 Move queue · Light") {
    VesselTerminalMoveQueueScreen(theme: Theme.light).environment(\.palette, Theme.light)
}
#Preview("780 Move queue · Dark") {
    VesselTerminalMoveQueueScreen(theme: Theme.dark).environment(\.palette, Theme.dark)
}
