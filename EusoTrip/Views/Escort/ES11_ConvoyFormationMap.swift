//
//  ES11_ConvoyFormationMap.swift
//  EusoTrip — Escort · Convoy Formation Map (ES-11).
//
//  SUPERSEDES-BY-ADOPTION: `602_EscortCorridorMap.swift` (legacy escort corridor
//  surface). That file is NOT deleted and NOT edited by this brick — the escort
//  nav map still binds the corridor slot to "602" until the single-writer of
//  EscortNavController.swift rewires it. When it does, the "602" slot adopts
//  `EscortConvoyFormationMapScreen` and the legacy file retires. Nav entry needed
//  is listed in this brick's manifest; nothing here touches shared nav files.
//
//  Built from the ES-11 design-authority twins
//  ("07 Escort/{Light,Dark}-SVG/ES-11 Convoy Formation Map.svg").
//
//  ARCHETYPE MAP (formation-first). The hero is an ORDERED POSITION RAIL — the
//  convoy as a ranked front-to-back ladder, each rung carrying its own gap from the
//  load datum, its fix age, and a live-or-extrapolated state. The map canvas is a
//  110-pt subordinate corridor strip. Deliberately NOT ES-02 Height Pole (the escort
//  MAP-family sibling): ES-02 leads with a clearance ARC GAUGE answering a vertical
//  question about one structure; ES-11 has no gauge and answers a longitudinal
//  question about the whole string. Also NOT ES-01 (orbless, no channel strip).
//
//  WIRING TRUTH (code-traced this fire)
//    REAL  escorts.getActiveConvoys      escorts.ts:985   active convoy + lane context
//    REAL  convoy.getChannel             convoy.ts:928    envelope :948 (convoyId/loadId/status/members)
//    REAL  convoy.getMembers             convoy.ts:951    :958-966 role/online/lastSeenAt/lat/lng/heading/speedMph
//    REAL  convoy.getConvoyPositions     convoy.ts:213    latest locationHistory row per member :225,
//                                                         roles emitted lead|load|rear ONLY :227,
//                                                         gaps via haversine :1100 → METRES :248-251
//    REAL  convoy.getConvoy              convoy.ts:203-207 targets + speed cap (:61 800 m, :63 45 mph)
//    REAL  convoy.getConvoyAlerts        convoy.ts:641    warn :656 · critical target×1.5 :654 · stale >120 s :689
//    REAL  convoy.updateMemberLocation   convoy.ts:1071   own fix ping — ONLINE_ONLY
//    REAL  convoy.sendHazard             convoy.ts:1044   HAIL CHASE → ES-01 — ONLINE_ONLY
//
//  NAMED GAPS — honest, not shipped:
//    · No per-state spacing rule exists anywhere on the server. The 790-ft law line
//      (EVO-1032) is the client constant `Law.spacingFeet` below; convoys
//      .targetLeadDistanceMeters defaults to 800 METRES (2,625 ft), which is a
//      convoy-ops target, not the statutory band. Owed: an escort_spacing_rules
//      table (state → maxLeadFt/maxChaseFt/source) plus a proc.
//    · The 0.25-mi (1,320 ft) integrity line (EVO-1045) is absent server-side —
//      getConvoyAlerts knows only target × 1.5. Derived here.
//    · The server performs NO dead reckoning. getConvoyPositions returns a raw last
//      fix plus its timestamp; the extrapolated register is computed here from fix
//      age (> 30 s). Nothing on this screen claims a projected position is a fix.
//    · convoys carries three structural slots only (lead/load/rear :200-202), so
//      getConvoyPositions can never place STEER or HIGH-POLE. Those read
//      convoy_members lat/lng written by updateMemberLocation :1084-1095 (which
//      defaults an unknown joiner's role to the literal string "CHASE" :1094).
//      Two position stores that never converge — this screen reads BOTH and labels
//      each node with the store it came from.
//
//  OFFLINE (§W): READ_CACHED(30s) through `EscortOfflineCache`. A cached paint forces
//  every node into the extrapolated register (nothing on a snapshot is a live fix) and
//  renders the staleness line in place of the GPS chip. Mutations are ONLINE_ONLY —
//  the phone has no escort outbox (Driver-only mirror, PLANNED per Offline Mode
//  Encyclopedia v2). No queue badge is ever drawn.
//
//  CHAIN: A6 POSITION FAN-OUT is SILENT and poll-only. convoy.updateMemberLocation
//  convoy.ts:1071-1097 writes convoy_members and emits nothing (no broadcastConvoyEvent,
//  no audit row), and convoy.getConvoyPositions has no subscription bound to it, so a
//  formation change reaches other units only on their own poll. Missing half: a WS emit
//  on the position write (WS_CHANNELS.CONVOY carrying CONVOY_LOCATION) subscribed by the
//  positions read, over one store. This surface therefore prints "poll 30s", never "live".
//
//  RBAC: row-level convoy membership gate assertConvoyMember convoy.ts:19 on every proc
//  above; Shipper NO ACCESS; no rate or tender price on this surface.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Law constants (client-side — named as gaps in the header)

private enum Law {
    /// EVO-1032 · state escort spacing band, in feet. No server rule exists.
    static let spacingFeet: Int = 790
    /// EVO-1045 · convoy-integrity limit, 0.25 mi in feet. No server threshold exists.
    static let integrityFeet: Int = 1_320
    /// Beyond this fix age a position is drawn as extrapolated, never as live.
    static let liveFixSeconds: Double = 30
    /// READ_CACHED ttl for this surface.
    static let cacheTTL: TimeInterval = 30
    static let pollSeconds: Int = 30
    static let metresToFeet: Double = 3.28084
}

// MARK: - Wire projections (screen-local, private)

/// One row off `escorts.getActiveConvoys` (escorts.ts:985).
private struct FmLiveConvoy: Codable, Identifiable {
    let id: String
    let status: String?
    let maxSpeed: Int?
    let leadDistance: Int?
    let rearDistance: Int?
    let loadNumber: String?
    let origin: String?
    let destination: String?
}

private struct FmConvoySearchInput: Encodable { let search: String? }
private struct FmConvoyIdInput: Encodable { let convoyId: Int }
private struct FmHazardInput: Encodable { let convoyId: Int; let callout: String }
private struct FmLocationInput: Encodable {
    let convoyId: Int; let lat: Double; let lng: Double
    let heading: Double?; let speedMph: Double?
}
private struct FmSendResult: Decodable { let success: Bool?; let id: Int? }

/// One member off `convoy.getMembers` (convoy.ts:951, columns :958-966).
/// `lat`/`lng` are decimal columns and arrive as strings.
private struct FmMemberRow: Codable, Identifiable {
    var id: Int { userId }
    let userId: Int
    let role: String?
    let online: Bool?
    let lastSeenAt: String?
    let lat: String?
    let lng: String?
    let heading: Int?
    let speedMph: Int?
    let name: String?
}

/// One position off `convoy.getConvoyPositions` (convoy.ts:213). Roles here are
/// only ever lead | load | rear (:227) — the three structural slots.
private struct FmPositionRow: Codable, Identifiable {
    var id: String { "\(userId)-\(role)" }
    let userId: Int
    let role: String
    let lat: Double
    let lng: Double
    let speed: Double?
    let heading: Double?
    let timestamp: String?
}

private struct FmPositionsEnvelope: Codable {
    let convoyId: Int?
    let positions: [FmPositionRow]
    /// METRES — haversine calculateDistance convoy.ts:1100.
    let leadDistance: Double?
    let rearDistance: Double?
    let status: String?
}

/// `convoy.getConvoy` (convoy.ts:203-207) — spacing targets and speed cap.
private struct FmConvoyDetail: Codable {
    let id: Int?
    let status: String?
    let targetLeadDistance: Int?
    let targetRearDistance: Int?
    let currentLeadDistance: Int?
    let currentRearDistance: Int?
    let maxSpeedMph: Int?
}

/// One alert off `convoy.getConvoyAlerts` (convoy.ts:641).
private struct FmAlertRow: Codable, Identifiable {
    let id: String
    let type: String
    let severity: String
    let message: String
    let timestamp: String?
}

/// Everything this screen paints, in one Codable envelope so the whole formation
/// can go to `EscortOfflineCache` as a single last-good snapshot.
private struct FmSnapshot: Codable {
    var convoy: FmLiveConvoy?
    var detail: FmConvoyDetail?
    var positions: FmPositionsEnvelope?
    var members: [FmMemberRow]
    var alerts: [FmAlertRow]
    /// Wall-clock at capture — fix ages are measured against this, not against
    /// "now", so a cached paint reports honest (older) ages.
    var capturedAt: Date
}

// MARK: - Derived formation model

private struct FmNode: Identifiable {
    enum Slot: String { case lead = "LEAD", highPole = "HIGH-POLE", load = "LOAD", steer = "STEER", chase = "CHASE" }
    /// Which of the two stores this position actually came from.
    enum Source: String { case tracking = "tracking", convoyMembers = "convoy" }

    let id: Int
    let rank: Int
    let slot: Slot
    let unit: String
    let isSelf: Bool
    /// Signed feet from the LOAD datum: positive ahead, negative behind. nil on the datum.
    let gapFeet: Int?
    let gapMetres: Int?
    let fixAgeSeconds: Int
    let detail: String
    let source: Source

    var isDatum: Bool { slot == .load }
    var isExtrapolated: Bool { Double(fixAgeSeconds) > Law.liveFixSeconds }
}

private struct FmFormation {
    let nodes: [FmNode]
    let speedCapMph: Int
    let lane: String
    let moveId: String

    var escorts: [FmNode] { nodes.filter { !$0.isDatum } }
    var live: Int { nodes.filter { !$0.isExtrapolated }.count }
    var extrapolated: Int { nodes.filter(\.isExtrapolated).count }
    var inLaw: Int { escorts.filter { abs($0.gapFeet ?? 0) <= Law.spacingFeet }.count }
    var leadMarginFeet: Int? {
        guard let g = nodes.first(where: { $0.slot == .lead })?.gapFeet else { return nil }
        return Law.spacingFeet - abs(g)
    }
    var breach: FmNode? { escorts.first { abs($0.gapFeet ?? 0) > Law.integrityFeet } }
}

// MARK: - Screen body

struct EscortConvoyFormationMap: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    private enum Phase { case loading, noConvoy, loaded, failed }

    @State private var phase: Phase = .loading
    @State private var snapshot: FmSnapshot? = nil
    @State private var activeConvoyId: Int? = nil
    /// Non-nil only while painting an EscortOfflineCache snapshot.
    @State private var stalenessLine: String? = nil
    @State private var actionNotice: String? = nil

    private static let cacheKey = "es11-formation"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                header
                iridescentHairline
                switch phase {
                case .loading:  loadingBlock
                case .noConvoy: emptyBlock
                case .failed:   failedBlock
                case .loaded:
                    if let formation = derive() {
                        complianceRuler(formation)
                        formationRail(formation)
                        integrityAlert(formation)
                        corridorStrip(formation)
                        actions
                        if let notice = actionNotice {
                            Text(notice)
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                        provenanceFootnote
                    } else {
                        emptyBlock
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await refreshAll() }
        .eusoRefreshable { await refreshAll() }
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                EusoTripBrandMark(size: 12)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ESCORT · FORMATION")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text("EASTBOUND ESCORT LLC")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .center) {
                Text("Formation")
                    .font(.system(size: 30, weight: .bold)).tracking(-0.5)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: 8)
                if let move = snapshot?.convoy?.loadNumber {
                    HStack(spacing: 8) {
                        Circle().fill(Brand.info).frame(width: 6, height: 6)
                        Text(move)
                            .font(EType.mono(.micro))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, Space.s3).padding(.vertical, 6)
                    .background(Capsule().fill(palette.bgCard)
                        .overlay(Capsule().stroke(palette.borderFaint)))
                }
            }
            if let formation = derive() {
                HStack(spacing: 10) {
                    positionBadge(.lead)
                    Text("String \(formation.nodes.count) nodes")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    liveDot(warn: formation.extrapolated > 0)
                    Text("\(formation.live) live · \(formation.extrapolated) extrapolated")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    Text(session.user?.name ?? "Escort")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
        }
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(height: 1)
            .padding(.horizontal, -14)
    }

    // MARK: - Spacing-compliance ruler (790-ft law · EVO-1032)

    private func complianceRuler(_ f: FmFormation) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("SPACING COMPLIANCE · GAP FROM LOAD", trailing: "EVO-1032")

            GeometryReader { geo in
                let full: CGFloat = 1_600
                let w = geo.size.width
                // A `func` declaration is not allowed inside a @ViewBuilder
                // closure; a `let` holding a closure is. Same behaviour.
                let x: (CGFloat) -> CGFloat = { feet in min(w, (feet / full) * w) }
                let lawX = x(CGFloat(Law.spacingFeet))
                let limX = x(CGFloat(Law.integrityFeet))
                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        Rectangle().fill(Brand.success.opacity(0.20)).frame(width: lawX)
                        Rectangle().fill(Brand.warning.opacity(0.20)).frame(width: max(0, limX - lawX))
                        Rectangle().fill(Brand.danger.opacity(0.20))
                    }
                    .frame(height: 14)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(palette.borderFaint))
                    .offset(y: 16)

                    lawMarker("\(Law.spacingFeet) FT LAW", color: Brand.success, x: lawX)
                    lawMarker("\(Law.integrityFeet.formatted()) FT · 0.25 MI", color: Brand.danger, x: limX)

                    ForEach(f.escorts) { node in
                        rulerTick(node, at: x(CGFloat(abs(node.gapFeet ?? 0))))
                    }
                }
            }
            .frame(height: 62)

            HStack(spacing: 0) {
                dataStat("IN LAW", value: "\(f.inLaw) of \(f.escorts.count)", gradient: true)
                statDivider
                dataStat("LEAD MARGIN",
                         value: f.leadMarginFeet.map { "\($0) ft" } ?? "—",
                         tint: (f.leadMarginFeet ?? 0) < 0 ? Brand.danger : Brand.warning)
                statDivider
                dataStat("SPD CAP", value: "\(f.speedCapMph) mph", tint: palette.textPrimary)
            }
            .frame(height: 46)
        }
    }

    private func lawMarker(_ text: String, color: Color, x: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(text).font(.system(size: 8, weight: .heavy)).tracking(0.4)
                .foregroundStyle(color).fixedSize()
            Rectangle().fill(color.opacity(0.7)).frame(width: 1.4, height: 24)
        }
        .position(x: x, y: 21)
    }

    private func rulerTick(_ node: FmNode, at x: CGFloat) -> some View {
        VStack(spacing: 4) {
            Circle().fill(slotColor(node.slot))
                .frame(width: node.slot == .lead ? 13 : 10, height: node.slot == .lead ? 13 : 10)
                .overlay(Circle().stroke(palette.bgPage, lineWidth: node.slot == .lead ? 2 : 1.6))
            Text("\(shortSlot(node.slot)) \(abs(node.gapFeet ?? 0).formatted())")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(slotColor(node.slot)).fixedSize()
        }
        .position(x: x, y: 34)
    }

    // MARK: - Formation rail (HERO)

    private func formationRail(_ f: FmFormation) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("FORMATION · FRONT → BACK",
                         trailing: stalenessLine ?? "POLL \(Law.pollSeconds) s")
            VStack(spacing: 0) {
                ForEach(Array(f.nodes.enumerated()), id: \.element.id) { idx, node in
                    HStack(alignment: .top, spacing: Space.s3) {
                        railSpine(node,
                                  hasBelow: idx < f.nodes.count - 1,
                                  next: idx < f.nodes.count - 1 ? f.nodes[idx + 1] : nil)
                        nodeCard(node)
                    }
                }
            }
        }
    }

    private func railSpine(_ node: FmNode, hasBelow: Bool, next: FmNode?) -> some View {
        VStack(spacing: 0) {
            ZStack {
                if node.isExtrapolated {
                    Circle()
                        .strokeBorder(slotColor(node.slot),
                                      style: StrokeStyle(lineWidth: 2.5, dash: [4, 3]))
                        .background(Circle().fill(palette.bgCard))
                        .frame(width: 26, height: 26)
                    Text("\(node.rank)")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(slotColor(node.slot))
                } else {
                    Circle().fill(slotColor(node.slot)).frame(width: 26, height: 26)
                    Text("\(node.rank)")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                }
            }
            if hasBelow, let below = next {
                // The spine segment itself carries the register: solid down to a live
                // node, dashed down to an extrapolated one.
                Path { p in
                    p.move(to: CGPoint(x: 1.25, y: 0))
                    p.addLine(to: CGPoint(x: 1.25, y: 42))
                }
                .stroke(below.isExtrapolated ? slotColor(below.slot)
                                             : palette.textPrimary.opacity(0.16),
                        style: below.isExtrapolated
                            ? StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [4, 5])
                            : StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 2.5, height: 42)
            }
        }
        .frame(width: 26)
    }

    private func nodeCard(_ node: FmNode) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s2) {
                    positionBadge(node.slot)
                    Text(node.unit)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    if node.isSelf {
                        Text("YOU")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.bgPage)
                            .padding(.horizontal, Space.s2).padding(.vertical, 3)
                            .background(Capsule().fill(palette.textPrimary))
                    }
                    if node.isExtrapolated {
                        Text("EXTRAP")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(slotColor(node.slot))
                            .padding(.horizontal, Space.s2).padding(.vertical, 3)
                            .background(Capsule().strokeBorder(slotColor(node.slot).opacity(0.6),
                                                               style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    }
                }
                HStack(spacing: Space.s2) {
                    if node.isExtrapolated {
                        Circle().strokeBorder(slotColor(node.slot),
                                              style: StrokeStyle(lineWidth: 1.6, dash: [2, 2]))
                            .frame(width: 7, height: 7)
                        Text("last fix \(node.fixAgeSeconds) s · \(node.detail)")
                            .font(EType.mono(.micro))
                            .foregroundStyle(slotColor(node.slot))
                    } else {
                        Circle().fill(Brand.success).frame(width: 7, height: 7)
                        Text("LIVE · fix \(node.fixAgeSeconds) s · \(node.detail)")
                            .font(EType.mono(.micro))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                .lineLimit(1).minimumScaleFactor(0.75)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                gapValue(node)
                Text(gapSubtitle(node))
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(gapTint(node))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .frame(minHeight: 52)
        .background(nodeBackground(node))
    }

    @ViewBuilder
    private func gapValue(_ node: FmNode) -> some View {
        if node.isDatum {
            Text("DATUM").font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
        } else {
            let feet = abs(node.gapFeet ?? 0)
            let over = feet > Law.integrityFeet
            let label = "\(node.isExtrapolated ? "~" : "")\(feet.formatted()) ft"
            if node.isSelf && !over {
                Text(label).font(.system(size: 16, weight: .heavy, design: .monospaced))
                    .foregroundStyle(LinearGradient.diagonal)
            } else {
                Text(label)
                    .font(.system(size: 16, weight: over ? .heavy : .bold, design: .monospaced))
                    .foregroundStyle(over ? Brand.danger
                                     : (node.isExtrapolated ? slotColor(node.slot) : palette.textPrimary))
            }
        }
    }

    private func gapSubtitle(_ node: FmNode) -> String {
        guard let m = node.gapMetres, let ft = node.gapFeet else { return "all gaps measured here" }
        let side = ft >= 0 ? "ahead" : "behind"
        if abs(ft) > Law.integrityFeet { return "\(abs(m)) m \(side) · OVER LAW" }
        if abs(ft) > Law.spacingFeet { return "\(abs(m)) m \(side) · OVER \(Law.spacingFeet) ft" }
        return "\(abs(m)) m \(side) · IN LAW · \(node.source.rawValue)"
    }

    private func gapTint(_ node: FmNode) -> Color {
        guard let ft = node.gapFeet else { return palette.textTertiary }
        if abs(ft) > Law.integrityFeet { return Brand.danger }
        if abs(ft) > Law.spacingFeet { return Brand.warning }
        return Brand.success
    }

    @ViewBuilder
    private func nodeBackground(_ node: FmNode) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        if node.isExtrapolated {
            shape.fill(palette.bgCard)
                .overlay(shape.strokeBorder(slotColor(node.slot).opacity(0.6),
                                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        } else {
            shape.fill(palette.bgCard)
                .overlay(shape.strokeBorder(node.isSelf ? slotColor(node.slot).opacity(0.4)
                                                        : palette.borderFaint))
                .overlay(alignment: .leading) {
                    Rectangle().fill(slotColor(node.slot)).frame(width: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 1.5))
                }
        }
    }

    // MARK: - Integrity alert (0.25-mi drift · EVO-1045)

    @ViewBuilder
    private func integrityAlert(_ f: FmFormation) -> some View {
        if let breach = f.breach, let feet = breach.gapFeet {
            let miles = Double(abs(feet)) / 5_280.0
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(Brand.danger)
                VStack(alignment: .leading, spacing: 5) {
                    Text("CONVOY INTEGRITY · \(breach.slot.rawValue) DRIFT \(String(format: "%.2f", miles)) mi")
                        .font(.system(size: 11.5, weight: .heavy)).tracking(0.2)
                        .foregroundStyle(Brand.danger)
                    Text(breach.isExtrapolated
                         ? "\(abs(feet).formatted()) ft vs \(Law.integrityFeet.formatted()) ft limit · on a \(breach.fixAgeSeconds) s extrapolated fix — confirm by voice"
                         : "\(abs(feet).formatted()) ft vs \(Law.integrityFeet.formatted()) ft limit · live fix")
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s3)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(Brand.danger.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(Brand.danger.opacity(0.45)))
            )
        }
    }

    // MARK: - Corridor strip (subordinate map canvas)

    private func corridorStrip(_ f: FmFormation) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionLabel("CORRIDOR", trailing: f.lane)
            ZStack {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgSecondary)
                GeometryReader { geo in
                    let w = geo.size.width, h = geo.size.height
                    Path { p in
                        p.move(to: CGPoint(x: 0.03 * w, y: 0.92 * h))
                        p.addCurve(to: CGPoint(x: 0.50 * w, y: 0.56 * h),
                                   control1: CGPoint(x: 0.22 * w, y: 0.80 * h),
                                   control2: CGPoint(x: 0.36 * w, y: 0.62 * h))
                        p.addCurve(to: CGPoint(x: 0.97 * w, y: 0.10 * h),
                                   control1: CGPoint(x: 0.68 * w, y: 0.48 * h),
                                   control2: CGPoint(x: 0.86 * w, y: 0.22 * h))
                    }
                    .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
                }
                HStack(spacing: 0) {
                    ForEach(Array(f.nodes.reversed().enumerated()), id: \.offset) { idx, node in
                        corridorPin(node)
                        if idx < f.nodes.count - 1 { Spacer(minLength: 0) }
                    }
                }
                .padding(.horizontal, 22)

                VStack {
                    HStack {
                        Spacer(minLength: 0)
                        HStack(spacing: Space.s2) {
                            if stalenessLine == nil {
                                Circle().fill(Brand.success).frame(width: 8, height: 8)
                            }
                            Text(stalenessLine ?? "poll \(Law.pollSeconds)s")
                                .font(EType.mono(.micro))
                                .foregroundStyle(stalenessLine == nil ? palette.textPrimary : Brand.warning)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(palette.bgCard.opacity(0.92)))
                    }
                    Spacer(minLength: 0)
                    HStack {
                        legend
                        Spacer(minLength: 0)
                    }
                }
                .padding(Space.s3)
            }
            .frame(height: 110)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func corridorPin(_ node: FmNode) -> some View {
        ZStack {
            if node.isExtrapolated {
                Circle().strokeBorder(slotColor(node.slot),
                                      style: StrokeStyle(lineWidth: 2.2, dash: [4, 3]))
                    .background(Circle().fill(palette.bgCard.opacity(0.92)))
                    .frame(width: 18, height: 18)
                Text(pinGlyph(node.slot))
                    .font(.system(size: 8, weight: .heavy)).foregroundStyle(slotColor(node.slot))
            } else {
                Circle().fill(slotColor(node.slot).opacity(0.22)).frame(width: 28, height: 28)
                Circle().fill(slotColor(node.slot)).frame(width: 19, height: 19)
                    .overlay(Circle().stroke(palette.bgPage, lineWidth: 2))
                Text(pinGlyph(node.slot))
                    .font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Circle().fill(palette.textPrimary).frame(width: 8, height: 8)
                Text("LIVE").font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            HStack(spacing: 5) {
                Circle().strokeBorder(Brand.warning, style: StrokeStyle(lineWidth: 1.6, dash: [2, 2]))
                    .frame(width: 8, height: 8)
                Text("EXTRAPOLATED").font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Brand.warning)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(palette.bgCard.opacity(0.9)))
    }

    // MARK: - Actions (both ONLINE_ONLY)

    private var actions: some View {
        HStack(spacing: Space.s2) {
            Button(action: { Task { await hailChase() } }) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 13, weight: .heavy))
                    Text("HAIL CHASE · CLOSE GAP")
                        .font(.system(size: 12.5, weight: .heavy)).tracking(0.4)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Brand.escort))
            }
            .buttonStyle(.plain)

            Button(action: { Task { await resyncFixes() } }) {
                HStack(spacing: Space.s2) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .heavy))
                    Text("RE-SYNC FIXES").font(.system(size: 12, weight: .heavy)).tracking(0.3)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                .foregroundStyle(Brand.info)
                .frame(width: 150).frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// The two named gaps a reader of this screen must not mistake for shipped truth.
    private var provenanceFootnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(Law.spacingFeet)-ft band and \(Law.integrityFeet.formatted())-ft integrity line are computed on this device — no state-by-state spacing rule is published to the app yet, so check the permit.")
            Text("Positions come from two stores: LEAD / LOAD / CHASE from tracking, STEER / HIGH-POLE from the convoy roster. Formation updates reach other units on their poll, not on a push.")
        }
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(palette.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Register blocks

    private var loadingBlock: some View {
        HStack(spacing: Space.s3) {
            ProgressView()
            Text("Resolving formation…").font(EType.body).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.s6)
    }

    private var emptyBlock: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("No active convoy")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text("The formation rail lights when an assignment starts and the convoy forms. Nothing is cached for a convoy you are not a member of.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Space.s5)
    }

    private var failedBlock: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("Formation unavailable")
                .font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text("No live read and no snapshot inside the \(Int(Law.cacheTTL))-second window. Gaps are not shown rather than shown stale.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: { Task { await refreshAll() } }) {
                Text("Retry").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                    .padding(.horizontal, Space.s5).padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Space.s5)
    }

    // MARK: - Primitives

    private func sectionLabel(_ text: String, trailing: String) -> some View {
        HStack {
            Text(text).font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 8)
            Text(trailing).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private func positionBadge(_ slot: FmNode.Slot) -> some View {
        Text(slot.rawValue)
            .font(.system(size: 9, weight: .heavy)).tracking(0.4)
            .foregroundStyle(slotColor(slot))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(slotColor(slot).opacity(0.16)))
    }

    private func liveDot(warn: Bool) -> some View {
        let c = warn ? Brand.warning : Brand.success
        return ZStack {
            Circle().fill(c.opacity(0.25)).frame(width: 14, height: 14)
            Circle().fill(c).frame(width: 8, height: 8)
        }
    }

    private var statDivider: some View {
        Rectangle().fill(palette.textPrimary.opacity(0.07)).frame(width: 1, height: 28)
    }

    private func dataStat(_ label: String, value: String, tint: Color? = nil,
                          gradient: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            if gradient {
                Text(value).font(.system(size: 16, weight: .heavy, design: .monospaced))
                    .foregroundStyle(LinearGradient.diagonal)
            } else {
                Text(value).font(.system(size: 16, weight: .heavy, design: .monospaced))
                    .foregroundStyle(tint ?? palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Space.s3)
    }

    /// Position colour vocabulary — INJECT_design.md, binding.
    private func slotColor(_ slot: FmNode.Slot) -> Color {
        switch slot {
        case .lead:     return Brand.info      // blue — front escort
        case .chase:    return Brand.escort    // purple — rear escort
        case .steer:    return Brand.warning   // amber — steerer
        case .highPole: return Brand.hazmat    // orange — clearance car
        case .load:     return Brand.success
        }
    }

    private func shortSlot(_ slot: FmNode.Slot) -> String {
        slot == .highPole ? "H-POLE" : slot.rawValue
    }

    private func pinGlyph(_ slot: FmNode.Slot) -> String {
        slot == .highPole ? "HP" : String(slot.rawValue.prefix(1))
    }

    // MARK: - Derivation (server metres → screen feet; fix age → live vs extrapolated)

    private func derive() -> FmFormation? {
        guard let snap = snapshot else { return nil }
        let now = stalenessLine == nil ? Date() : snap.capturedAt
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()

        func age(_ stamp: String?) -> Int {
            guard let s = stamp,
                  let d = iso.date(from: s) ?? isoPlain.date(from: s) else { return 999 }
            return max(0, Int(now.timeIntervalSince(d)))
        }

        // getConvoyPositions emits one row per structural slot, but a duplicate role
        // must never crash the formation — keep the freshest and move on.
        let posByRole = Dictionary((snap.positions?.positions ?? [])
            .map { ($0.role.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first })
        let selfUserId = Int(session.user?.id ?? "")

        // Gaps: the server hands back metres off the haversine (convoy.ts:248-251).
        let leadFeet = (snap.positions?.leadDistance).map { Int(($0 * Law.metresToFeet).rounded()) }
        let rearFeet = (snap.positions?.rearDistance).map { -Int(($0 * Law.metresToFeet).rounded()) }
        let leadMetres = (snap.positions?.leadDistance).map { Int($0.rounded()) }
        let rearMetres = (snap.positions?.rearDistance).map { -Int($0.rounded()) }

        var nodes: [FmNode] = []
        var rank = 0

        func appendNode(slot: FmNode.Slot, member: FmMemberRow?, position: FmPositionRow?,
                        gapFeet: Int?, gapMetres: Int?, source: FmNode.Source) {
            rank += 1
            let uid = position?.userId ?? member?.userId ?? rank
            let fixAge = position != nil ? age(position?.timestamp) : age(member?.lastSeenAt)
            var detail: [String] = []
            if let mph = position?.speed { detail.append("\(Int(mph.rounded())) mph") }
            else if let mph = member?.speedMph { detail.append("\(mph) mph") }
            if let hdg = position?.heading { detail.append(String(format: "hdg %03d°", Int(hdg))) }
            else if let hdg = member?.heading { detail.append(String(format: "hdg %03d°", hdg)) }
            nodes.append(FmNode(id: uid, rank: rank, slot: slot,
                                unit: member?.name ?? position.map { "Unit \($0.userId)" } ?? "Unit —",
                                isSelf: selfUserId != nil && uid == selfUserId,
                                gapFeet: gapFeet, gapMetres: gapMetres,
                                fixAgeSeconds: fixAge,
                                detail: detail.isEmpty ? "no telemetry" : detail.joined(separator: " · "),
                                source: source))
        }

        func member(matching keys: [String]) -> FmMemberRow? {
            snap.members.first { m in
                guard let r = m.role?.uppercased() else { return false }
                return keys.contains(r)
            }
        }

        // Front → back. LEAD / LOAD / CHASE carry tracking positions; STEER and
        // HIGH-POLE can only ever come off the convoy roster (named gap in the header).
        appendNode(slot: .lead, member: member(matching: ["LEAD"]), position: posByRole["lead"],
                   gapFeet: leadFeet, gapMetres: leadMetres, source: .tracking)
        if let hp = member(matching: ["HIGH-POLE", "HIGH_POLE", "HIGHPOLE", "POLE"]) {
            appendNode(slot: .highPole, member: hp, position: nil,
                       gapFeet: nil, gapMetres: nil, source: .convoyMembers)
        }
        appendNode(slot: .load, member: member(matching: ["LOAD", "HAUL"]), position: posByRole["load"],
                   gapFeet: nil, gapMetres: nil, source: .tracking)
        if let st = member(matching: ["STEER", "STEERMAN"]) {
            appendNode(slot: .steer, member: st, position: nil,
                       gapFeet: nil, gapMetres: nil, source: .convoyMembers)
        }
        appendNode(slot: .chase, member: member(matching: ["CHASE", "REAR"]), position: posByRole["rear"],
                   gapFeet: rearFeet, gapMetres: rearMetres, source: .tracking)

        let lane: String = {
            guard let o = snap.convoy?.origin, let d = snap.convoy?.destination else { return "Corridor" }
            return "\(o) → \(d)"
        }()

        return FmFormation(nodes: nodes,
                           speedCapMph: snap.detail?.maxSpeedMph ?? snap.convoy?.maxSpeed ?? 45,
                           lane: lane,
                           moveId: snap.convoy?.loadNumber ?? "—")
    }

    // MARK: - Data plumbing (poll only — A6 has no push half)

    private func refreshAll() async {
        if snapshot == nil { phase = .loading }
        do {
            let rows: [FmLiveConvoy] = try await EusoTripAPI.shared.query(
                "escorts.getActiveConvoys", input: FmConvoySearchInput(search: nil))
            guard let first = rows.first, let cid = Int(first.id) else {
                snapshot = nil; phase = .noConvoy; stalenessLine = nil
                return
            }
            activeConvoyId = cid

            async let detail: FmConvoyDetail? = try? EusoTripAPI.shared.query(
                "convoy.getConvoy", input: FmConvoyIdInput(convoyId: cid))
            async let positions: FmPositionsEnvelope? = try? EusoTripAPI.shared.query(
                "convoy.getConvoyPositions", input: FmConvoyIdInput(convoyId: cid))
            async let members: [FmMemberRow]? = try? EusoTripAPI.shared.query(
                "convoy.getMembers", input: FmConvoyIdInput(convoyId: cid))
            async let alerts: [FmAlertRow]? = try? EusoTripAPI.shared.query(
                "convoy.getConvoyAlerts", input: FmConvoyIdInput(convoyId: cid))

            let resolvedMembers = (await members) ?? []
            let resolvedAlerts = (await alerts) ?? []
            let fresh = FmSnapshot(convoy: first,
                                   detail: await detail,
                                   positions: await positions,
                                   members: resolvedMembers,
                                   alerts: resolvedAlerts,
                                   capturedAt: Date())
            await MainActor.run {
                snapshot = fresh
                stalenessLine = nil
                phase = .loaded
            }
            EscortOfflineCache.store(fresh, key: Self.cacheKey)
        } catch {
            // READ_CACHED(30s): paint last-good, say so, and force every node into
            // the extrapolated register. Never present a cached gap as a live fix.
            if let cached = EscortOfflineCache.load(FmSnapshot.self,
                                                    key: Self.cacheKey,
                                                    ttl: Law.cacheTTL) {
                await MainActor.run {
                    snapshot = cached.value
                    stalenessLine = EscortOfflineCache.stalenessLine(age: cached.age)
                    phase = .loaded
                }
            } else if snapshot == nil {
                await MainActor.run { phase = .failed }
            }
        }
    }

    /// ONLINE_ONLY — pushes this unit's own fix, then re-polls. There is no outbox
    /// for the escort role, so a failure is reported, never queued.
    private func resyncFixes() async {
        guard let cid = activeConvoyId,
              let own = snapshot?.positions?.positions.first(where: { row in
                  Int(session.user?.id ?? "") == row.userId
              }) else {
            await MainActor.run { actionNotice = "No own fix to push — re-syncing reads only." }
            await refreshAll()
            return
        }
        do {
            let _: FmSendResult = try await EusoTripAPI.shared.mutation(
                "convoy.updateMemberLocation",
                input: FmLocationInput(convoyId: cid, lat: own.lat, lng: own.lng,
                                       heading: own.heading, speedMph: own.speed))
            await MainActor.run { actionNotice = nil }
        } catch {
            await MainActor.run {
                actionNotice = "Fix didn't send — check signal and retry. Nothing was queued."
            }
        }
        await refreshAll()
    }

    /// ONLINE_ONLY — broadcasts BEHIND_YOU to the convoy channel (ES-01 spine).
    private func hailChase() async {
        guard let cid = activeConvoyId else { return }
        do {
            let _: FmSendResult = try await EusoTripAPI.shared.mutation(
                "convoy.sendHazard", input: FmHazardInput(convoyId: cid, callout: "BEHIND_YOU"))
            await MainActor.run { actionNotice = "BEHIND YOU sent to the convoy channel" }
        } catch {
            await MainActor.run {
                actionNotice = "Callout didn't send — check signal and retry. Nothing was queued."
            }
        }
    }
}

// MARK: - Screen wrapper (Shell + BottomNav)

struct EscortConvoyFormationMapScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortConvoyFormationMap()
        } nav: {
            BottomNav(
                leading: escortNavLeading_ES11(),
                trailing: escortNavTrailing_ES11(),
                orbState: .idle
            )
        }
    }
}

private func escortNavLeading_ES11() -> [NavSlot] {
    EscortNavRoute.leading(current: .assignments)
}

private func escortNavTrailing_ES11() -> [NavSlot] {
    EscortNavRoute.trailing(current: .assignments)
}

// MARK: - Previews
//
// Previews don't run `.task`, so both variants render in the loading register
// without touching the network.

#Preview("ES-11 · Escort · Convoy Formation Map · Dark") {
    EscortConvoyFormationMapScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("ES-11 · Escort · Convoy Formation Map · Light") {
    EscortConvoyFormationMapScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
