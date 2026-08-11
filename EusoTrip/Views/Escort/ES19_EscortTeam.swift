//
//  ES19_EscortTeam.swift
//  EusoTrip — Escort · ES-19 Escort Team (iOS peer of the ES-19 twins).
//
//  A SPLIT-LEDGER BOARD: one move's escort payout drawn as a single ribbon
//  cut into named shares, with the roster beneath it as that ribbon's
//  legend — every seat row wears the colour of its own segment on a left
//  share-tab. Beneath the roster, the availability/reserve bench; beneath
//  that, the SECOND DENSITY — the company reading — folded onto the same
//  surface as a cell matrix instead of a second list of rows. One screen,
//  two densities, not two screens.
//
//  Wiring truth (every anchor opened at the line this firing against
//  frontend/server/routers/escorts.ts, working tree, md5
//  064a1b8459b8013613dac05184cf4277, 4745 lines; convoy.ts 1106 lines):
//
//    REAL  escorts.getMyTeam                escorts.ts:2026
//          No input. Resolves my own live assignments (:2034-2049, status
//          IN accepted/en_route/on_site/escorting/pending, limit 10), then
//          for each one selects EVERY non-cancelled escortAssignment on the
//          same loadId (:2092-2104) and returns per teammate
//          {assignmentId,userId,name,email,phone,position,status,isMe}
//          (:2112-2121) plus totalEscorts (:2165), lane + distance
//          (:2156-2158), the convoy block incl. maxSpeedMph (:2080-2087),
//          and the driver / carrier contacts (:2131, :2142). This is the
//          roster spine — every name, seat and status on this board.
//
//    REAL  escorts.getRouteStates           escorts.ts:3495
//          {originState,destinationState} → {states[],directRoute}. BFS over
//          the adjacency map at :3501-3543. Feeds requiredStates below.
//
//    REAL  escorts.verifyEscortCertifications escorts.ts:3310
//          {escortUserId,requiredStates[]} → {verified,errors[],
//          certifications[]}. Run once per teammate. The expired branch
//          (:3329-3333) and the missing-state branch (:3336-3341) produce
//          the strings this screen shows VERBATIM — including
//          "Missing pilot car certification for state: LA".
//
//    REAL  escorts.findQualifiedEscorts     escorts.ts:3445
//          {routeStates[],position} → escorts with ACTIVE, unexpired certs
//          in ALL route states; GROUP BY user HAVING stateCount ≥ n,
//          ORDER BY stateCount DESC, LIMIT 20 (:3471-3474). Drives BOTH the
//          reserve bench and the one live figure in the fleet band. The
//          server's own LIMIT 20 is printed on the band.
//
//    REAL  escorts.getProfile               escorts.ts:3081
//          escortCompany (:3142) — the company NAME in the fleet band's
//          eyebrow. It is a metadata string, not an entity (see below).
//
//    RBAC  escortProcedure  server/_core/trpc.ts:212 → roleProcedure(ROLES.
//          ESCORT), aliased as protectedProcedure at escorts.ts:11. Every
//          read is anchored to me by resolveEscortUserId (:138), so the
//          roster is only ever the teammates of a move I am myself on —
//          no directory, no other team, no shipper linehaul. getActiveConvoys
//          (:985) admits a convoy only where I am leadUserId or rearUserId
//          (:1003), which is the RBAC fact that makes a team-lead board
//          legitimate and no wider. Mounts: escorts routers.ts:1849,
//          convoy routers.ts:2247.
//
//  DOCUMENTED DIVERGENCES FROM THE TWINS (live screen vs. designed target —
//  zero invention, and nothing fixture is ever dressed as live):
//
//   1. THE SPLIT RIBBON. The twins draw one pot cut into six priced shares.
//      The server cannot supply that today: getMyTeam SELECTS rate and
//      rateType on the teammate query (escorts.ts:2097-2098) and then DROPS
//      both when it builds teamMembers (:2112-2121) — only myRate survives
//      (:2153) — and no procedure anywhere sums a load's escort payouts. So
//      this port renders the ribbon as a SEAT ribbon: one cell per real
//      seat, MY cell priced from myRate, every other cell drawn hatched and
//      labelled UNPRICED, with the pot total shown as an em-dash rather than
//      a number nobody returned. The gap is drawn as the gap. It becomes the
//      twins' ribbon the moment getMyTeam returns rate per teamMember and a
//      teamPayoutTotal.
//
//   2. THE FLEET BAND. The twins show a 22-cell company roster. There is no
//      escort-company entity in the tree: escortCompany is free text inside
//      users.metadata.escortProfile (read escorts.ts:3142, written :3223)
//      with no FK, and companies.getFleet (companies.ts:273) returns
//      VEHICLES scoped by ctx.isolation.companyId (:284-287), which an
//      escort does not carry — it returns [] for this role. So the band here
//      is built from the ONE company-shaped read that exists:
//      findQualifiedEscorts, the certified corridor pool. Its cells are real
//      escorts; the ones already on my string carry a light core. The band
//      names itself "certified pool", never "company roster", and prints the
//      server's LIMIT 20.
//
//   3. BENCH READINESS. findQualifiedEscorts has no availability filter, no
//      lat/lng input and no ETA (:3464-3475), so no "READY 12 min" is drawn.
//      Each bench chip states what the server actually knows: the states
//      that escort is cleared for and how many of the route's states they
//      cover. Per-member availability is unreachable too — getAvailability
//      (:2298) / updateAvailability (:2318) are pinned to the caller
//      (:2304, :2323).
//
//   4. SEAT BADGES. escortAssignments.position is the enum lead | chase |
//      both ONLY (positionSchema escorts.ts:25). STEER does not exist
//      anywhere in the tree; HIGH-POLE exists only as a profile capability
//      flag (positions.heightPole :3138), never as an assignment position.
//      This port draws ONLY what the column holds and labels a `both` seat
//      as LEAD/CHASE. It never invents a STEER or HIGH-POLE row.
//
//   5. SEAT SWAP. No procedure lets a lead move another escort on or off a
//      seat — applyForJob (:890) and acceptJob (:1148) are both self-scoped.
//      REQUEST SWAP is inert and says so in its own caption and its toast.
//
//  OFFLINE: READ_CACHED(10m) on the roster only, and it is a real cache.
//  The getMyTeam payload is stored through EscortOfflineCache
//  (Views/Escort/EscortOfflineCache.swift — used, not re-created); when the
//  live read fails and a snapshot inside the ttl exists, the board paints
//  the snapshot AND renders EscortOfflineCache.stalenessLine behind a GREY
//  dot — a snapshot never wears a live badge. Past the ttl the snapshot is
//  refused and the screen shows its offline state.
//  CERTIFICATION VERDICTS ARE NEVER CACHED. verifyEscortCertifications and
//  findQualifiedEscorts are ONLINE_ONLY reads, because a cert verdict
//  painted from a snapshot is the one number here that could put an
//  uncertified unit across a state line: on the snapshot path the verdicts
//  are cleared to nil and every chip reads NOT VERIFIED, never CLEARED.
//  All mutations stay ONLINE_ONLY — the escort role has no outbox lanes
//  (PLANNED per the Offline Mode Encyclopedia v2). No queue badge, ever.
//
//  CHAIN: SILENT, and both halves are named for the ledger. Server half —
//  escorts.updateJobStatus (escorts.ts:1171-1205) runs its UPDATE and the
//  ES-06 pre-trip interlock and returns with NO websocket fan-out of any
//  kind; escorts.acceptJob (:1148-1169) likewise emits nothing. The only
//  escort fan-out in the router is applyForJob (:915-918) → LOAD room +
//  catalyst + driver + the applicant's own channel, and a team LEAD is on
//  none of those lists because an escort is never the load's driver or
//  catalyst. Client half — RealtimeService.swift:451-458 handles
//  escort:job_applied / job_assigned / job_started / job_completed only;
//  there is no team case and no escort:team_* event to handle even if one
//  were added. Needed: (i) broadcast escort:team_member_status to
//  WS_CHANNELS.LOAD from updateJobStatus and acceptJob, (ii) a matching
//  case in RealtimeService plus a LOAD-room join for the lead. Until both
//  land this board lights on POLL only — the meta dot is amber, reads
//  POLL, and pull-to-refresh is the real refresh path.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Tolerant scalar decoding (raw SQL rows come back loosely typed)

private func es19Int<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Int? {
    if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
    if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(v) }
    if let v = try? c.decodeIfPresent(String.self, forKey: key) { return Int(v) }
    return nil
}

private func es19Double<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Double? {
    if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return v }
    if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return Double(v) }
    if let v = try? c.decodeIfPresent(String.self, forKey: key) { return Double(v) }
    return nil
}

// MARK: - Wire contracts (Codable — the roster snapshot is stored verbatim)

/// One teammate inside `escorts.getMyTeam` (escorts.ts:2112-2121).
/// NOTE the absent fields: the server reads rate/rateType on the teammate
/// query (escorts.ts:2097-2098) and then drops them here, so there is no
/// per-seat money on this contract and none is invented.
private struct TeamMemberRow: Codable, Identifiable {
    let assignmentId: Int?
    let userId: Int?
    let name: String?
    /// escortAssignments.position — lead | chase | both (escorts.ts:25).
    let position: String?
    /// escortAssignments.status — pending | accepted | en_route | on_site |
    /// escorting | completed | cancelled.
    let status: String?
    let isMe: Bool?

    var id: String { "\(assignmentId ?? 0)-\(userId ?? 0)" }

    private enum CodingKeys: String, CodingKey {
        case assignmentId, userId, name, position, status, isMe
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assignmentId = es19Int(c, .assignmentId)
        userId       = es19Int(c, .userId)
        name         = try? c.decodeIfPresent(String.self, forKey: .name)
        position     = try? c.decodeIfPresent(String.self, forKey: .position)
        status       = try? c.decodeIfPresent(String.self, forKey: .status)
        isMe         = (try? c.decodeIfPresent(Bool.self, forKey: .isMe)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(assignmentId, forKey: .assignmentId)
        try c.encodeIfPresent(userId, forKey: .userId)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(position, forKey: .position)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(isMe, forKey: .isMe)
    }
}

/// The convoy block on a getMyTeam row (escorts.ts:2080-2087).
private struct TeamConvoyBlock: Codable {
    let status: String?
    let maxSpeedMph: Int?
    let startedAt: String?

    private enum CodingKeys: String, CodingKey { case status, maxSpeedMph, startedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status      = try? c.decodeIfPresent(String.self, forKey: .status)
        maxSpeedMph = es19Int(c, .maxSpeedMph)
        startedAt   = try? c.decodeIfPresent(String.self, forKey: .startedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(maxSpeedMph, forKey: .maxSpeedMph)
        try c.encodeIfPresent(startedAt, forKey: .startedAt)
    }
}

/// One row of `escorts.getMyTeam` (escorts.ts:2146-2167) — one move I am on,
/// with the whole escort crew of that move attached.
private struct TeamAssignment: Codable, Identifiable {
    let assignmentId: Int?
    let loadId: Int?
    let loadNumber: String?
    let myPosition: String?
    let myStatus: String?
    /// The ONLY money on this contract: escortAssignments.rate for ME
    /// (escorts.ts:2153).
    let myRate: Double?
    let myRateType: String?
    let cargoType: String?
    let origin: String?
    let destination: String?
    let distance: Double?
    let convoy: TeamConvoyBlock?
    let teamMembers: [TeamMemberRow]?
    let totalEscorts: Int?
    let startedAt: String?

    var id: String { "\(assignmentId ?? 0)" }
    var lane: String { "\(origin ?? "—") → \(destination ?? "—")" }

    private enum CodingKeys: String, CodingKey {
        case assignmentId, loadId, loadNumber, myPosition, myStatus, myRate,
             myRateType, cargoType, origin, destination, distance, convoy,
             teamMembers, totalEscorts, startedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        assignmentId = es19Int(c, .assignmentId)
        loadId       = es19Int(c, .loadId)
        loadNumber   = try? c.decodeIfPresent(String.self, forKey: .loadNumber)
        myPosition   = try? c.decodeIfPresent(String.self, forKey: .myPosition)
        myStatus     = try? c.decodeIfPresent(String.self, forKey: .myStatus)
        myRate       = es19Double(c, .myRate)
        myRateType   = try? c.decodeIfPresent(String.self, forKey: .myRateType)
        cargoType    = try? c.decodeIfPresent(String.self, forKey: .cargoType)
        origin       = try? c.decodeIfPresent(String.self, forKey: .origin)
        destination  = try? c.decodeIfPresent(String.self, forKey: .destination)
        distance     = es19Double(c, .distance)
        convoy       = try? c.decodeIfPresent(TeamConvoyBlock.self, forKey: .convoy)
        teamMembers  = (try? c.decodeIfPresent([TeamMemberRow].self, forKey: .teamMembers)) ?? []
        totalEscorts = es19Int(c, .totalEscorts)
        startedAt    = try? c.decodeIfPresent(String.self, forKey: .startedAt)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(assignmentId, forKey: .assignmentId)
        try c.encodeIfPresent(loadId, forKey: .loadId)
        try c.encodeIfPresent(loadNumber, forKey: .loadNumber)
        try c.encodeIfPresent(myPosition, forKey: .myPosition)
        try c.encodeIfPresent(myStatus, forKey: .myStatus)
        try c.encodeIfPresent(myRate, forKey: .myRate)
        try c.encodeIfPresent(myRateType, forKey: .myRateType)
        try c.encodeIfPresent(cargoType, forKey: .cargoType)
        try c.encodeIfPresent(origin, forKey: .origin)
        try c.encodeIfPresent(destination, forKey: .destination)
        try c.encodeIfPresent(distance, forKey: .distance)
        try c.encodeIfPresent(convoy, forKey: .convoy)
        try c.encodeIfPresent(teamMembers, forKey: .teamMembers)
        try c.encodeIfPresent(totalEscorts, forKey: .totalEscorts)
        try c.encodeIfPresent(startedAt, forKey: .startedAt)
    }
}

/// `escorts.getRouteStates` (escorts.ts:3495).
private struct RouteStatesInput: Encodable {
    let originState: String
    let destinationState: String
}
private struct RouteStatesResult: Decodable {
    let states: [String]?
    let directRoute: Bool?
}

/// `escorts.verifyEscortCertifications` (escorts.ts:3310).
private struct VerifyCertsInput: Encodable {
    let escortUserId: Int
    let requiredStates: [String]
}
private struct VerifyCertsResult: Decodable {
    let verified: Bool?
    /// Server-authored strings. Shown verbatim — never paraphrased.
    let errors: [String]?

    private enum CodingKeys: String, CodingKey { case verified, errors }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        verified = (try? c.decodeIfPresent(Bool.self, forKey: .verified)) ?? false
        errors   = (try? c.decodeIfPresent([String].self, forKey: .errors)) ?? []
    }
}

/// `escorts.findQualifiedEscorts` (escorts.ts:3445).
private struct QualifiedInput: Encodable {
    let routeStates: [String]
    let position: String
}
private struct QualifiedEscort: Decodable, Identifiable {
    let userId: Int?
    let name: String?
    let certifiedStates: [String]?
    let statesCovered: Int?

    var id: Int { userId ?? 0 }

    private enum CodingKeys: String, CodingKey {
        case userId, name, certifiedStates, statesCovered
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId          = es19Int(c, .userId)
        name            = try? c.decodeIfPresent(String.self, forKey: .name)
        certifiedStates = (try? c.decodeIfPresent([String].self, forKey: .certifiedStates)) ?? []
        statesCovered   = es19Int(c, .statesCovered)
    }
}
private struct QualifiedResult: Decodable {
    let escorts: [QualifiedEscort]?
    let totalAvailable: Int?
}

/// Subset of `escorts.getProfile` (escorts.ts:3081) — the company NAME only.
private struct EscortProfileLite: Decodable {
    let escortCompany: String?
}

// MARK: - Seat vocabulary (only what escortAssignments.position holds)

private enum TeamSeatKind: String {
    case lead, chase, both, unknown

    init(_ raw: String?) {
        switch (raw ?? "").lowercased() {
        case "lead":  self = .lead
        case "chase": self = .chase
        case "both":  self = .both
        default:      self = .unknown
        }
    }

    var label: String {
        switch self {
        case .lead:    return "LEAD"
        case .chase:   return "CHASE"
        case .both:    return "LEAD/CHASE"
        case .unknown: return "SEAT"
        }
    }

    func tint(_ palette: Theme.Palette) -> Color {
        switch self {
        case .lead:    return Brand.blue
        case .chase:   return Brand.escort
        case .both:    return Brand.info
        case .unknown: return palette.textTertiary
        }
    }
}

/// Per-member verdict from verifyEscortCertifications. `nil` means the
/// verdict has not been fetched — it is NEVER treated as cleared.
private struct CertVerdict {
    let verified: Bool
    let errors: [String]

    var chip: String {
        if verified { return "CLEARED" }
        guard let first = errors.first else { return "NOT CLEARED" }
        if first.lowercased().contains("missing") {
            // "Missing pilot car certification for state: LA"
            let st = first.components(separatedBy: ":").last?
                .trimmingCharacters(in: .whitespaces) ?? ""
            return st.isEmpty ? "NOT CLEARED" : "\(st) MISSING · BLOCKED"
        }
        if first.lowercased().contains("expired") { return "CERT EXPIRED" }
        return "NOT CLEARED"
    }

    var isBlocking: Bool { !verified }
}

// MARK: - Screen

struct EscortTeam: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    private enum Phase { case loading, empty, loaded, failed }

    private static let cacheTTL: TimeInterval = 10 * 60
    private static let teamKey = "es19-my-team"

    @State private var phase: Phase = .loading
    @State private var assignments: [TeamAssignment] = []
    @State private var selectedId: String? = nil

    /// ONLINE_ONLY reads — deliberately never written to disk.
    @State private var routeStates: [String] = []
    @State private var verdicts: [Int: CertVerdict] = [:]
    @State private var pool: [QualifiedEscort] = []
    @State private var poolTotal: Int? = nil
    @State private var companyName: String? = nil

    /// Non-nil only while the board is painting a disk snapshot.
    @State private var stalenessLine: String? = nil
    @State private var verifying = false
    @State private var toast: String? = nil

    // MARK: Derived

    private var active: TeamAssignment? {
        if let sid = selectedId, let hit = assignments.first(where: { $0.id == sid }) { return hit }
        let rolling = assignments.first {
            ["escorting", "en_route", "on_site"].contains(($0.myStatus ?? "").lowercased())
        }
        return rolling ?? assignments.first
    }

    private var crew: [TeamMemberRow] {
        // Me first, then the rest in the order the server returned them.
        let rows = active?.teamMembers ?? []
        return rows.sorted { a, b in ((a.isMe ?? false) ? 0 : 1) < ((b.isMe ?? false) ? 0 : 1) }
    }

    private var blockedCount: Int {
        crew.filter { m in
            guard let uid = m.userId, let v = verdicts[uid] else { return false }
            return v.isBlocking
        }.count
    }

    /// Bench = the certified corridor pool minus everyone already seated.
    private var bench: [QualifiedEscort] {
        let seated = Set(crew.compactMap { $0.userId })
        return pool.filter { !seated.contains($0.userId ?? -1) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrowRow
                titleRow
                metaRow
                hairline
                content
                Color.clear.frame(height: 104)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await refresh() }
        .refreshable { await refresh() }
        .overlay(alignment: .bottom) { toastLayer }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            loadingBlock
        case .failed:
            offlineBlock
        case .empty:
            emptyBlock
        case .loaded:
            splitSection
            rosterSection
            benchSection
            fleetSection
            if let line = stalenessLine { cacheStrip(line) }
            actionBar
        }
    }

    // MARK: Header

    private var eyebrowRow: some View {
        HStack {
            Text("✦ ESCORT · TEAM OPS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer(minLength: Space.s2)
            Text(companyCaps)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    /// escorts.getProfile.escortCompany (escorts.ts:3142) when the server has
    /// one; otherwise the session's company, otherwise the honest generic.
    private var companyCaps: String {
        if let c = companyName, !c.trimmingCharacters(in: .whitespaces).isEmpty {
            return c.uppercased()
        }
        if let cid = session.user?.companyId, !cid.isEmpty { return "COMPANY · \(cid)".uppercased() }
        return "ESCORT NETWORK"
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Text("Escort Team")
                .font(.system(size: 28, weight: .heavy)).tracking(-0.4)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer(minLength: 0)
            if let n = active?.loadNumber, !n.isEmpty {
                HStack(spacing: 6) {
                    Circle().fill(AnyShapeStyle(Brand.escort)).frame(width: 6, height: 6)
                    Text(n)
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(palette.bgCardSoft)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))
            }
        }
    }

    /// AMBER, never green. CHAIN is SILENT on both halves — a teammate's state
    /// change reaches this board on poll only, and the dot says so.
    private var mySeat: TeamSeatKind { TeamSeatKind(active?.myPosition) }

    private var metaRow: some View {
        HStack(spacing: Space.s3) {
            Text(mySeat.label)
                .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                .foregroundStyle(mySeat.tint(palette))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(mySeat.tint(palette).opacity(0.16))
                .clipShape(Capsule())
            Text("\(crew.count) seat\(crew.count == 1 ? "" : "s")\(blockedCount > 0 ? " · \(blockedCount) blocked" : "")")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .lineLimit(1)
            HStack(spacing: 5) {
                Circle().fill(AnyShapeStyle(Brand.warning)).frame(width: 8, height: 8)
                Text("POLL")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer(minLength: 0)
            Text(session.user?.name ?? "Escort")
                .font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    private var hairline: some View {
        Rectangle().fill(palette.iridescentHairline)
            .frame(height: 1).padding(.horizontal, -14)
    }

    // MARK: Split ledger — the hero, drawn from what the server actually gives

    private var splitSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHead("TEAM PAYOUT · SHARES ON THIS MOVE",
                        trailing: laneMetaShort, trailingTint: palette.textTertiary)

            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top, spacing: Space.s4) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MY SHARE · \((active?.myRateType ?? "flat").uppercased())")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(palette.textTertiary)
                        Text(currency(active?.myRate))
                            .font(.system(size: 26, weight: .heavy, design: .monospaced))
                            .tracking(-0.8)
                            .foregroundStyle(LinearGradient.diagonal)
                            .minimumScaleFactor(0.75).lineLimit(1)
                    }
                    Rectangle().fill(palette.borderFaint).frame(width: 1, height: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(active?.lane ?? "—")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Text(laneMeta)
                            .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                        // The pot total has no procedure — it renders as the
                        // em-dash it is, never as a computed guess.
                        Text("TEAM TOTAL —  ·  \(pricedCount) of \(crew.count) shares priced")
                            .font(EType.mono(.micro).weight(.bold))
                            .foregroundStyle(Brand.warning)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                }

                seatRibbon

                Text("✱ getMyTeam reads the teammate rate and then drops it (escorts.ts:2112-2121) — only my own share is returned, and no procedure sums the pot. Unpriced seats are drawn as holes, not as numbers.")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(card)
        }
    }

    private var pricedCount: Int { (active?.myRate ?? 0) > 0 ? 1 : 0 }

    /// One cell per REAL seat. Mine is priced; the rest are drawn hatched
    /// because the server does not return their rate.
    private var seatRibbon: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 2) {
                ForEach(crew) { m in
                    let isMe = m.isMe ?? false
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(isMe && (active?.myRate ?? 0) > 0
                              ? AnyShapeStyle(LinearGradient.primary)
                              : AnyShapeStyle(palette.textTertiary.opacity(0.14)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(
                                    isMe ? Color.clear : palette.textTertiary.opacity(0.55),
                                    style: StrokeStyle(lineWidth: 1, dash: isMe ? [] : [3, 2]))
                        )
                        .frame(height: 16)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 2) {
                ForEach(crew) { m in
                    Text((m.isMe ?? false) && (active?.myRate ?? 0) > 0 ? "MINE" : "UNPRICED")
                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                        .foregroundStyle((m.isMe ?? false) ? Brand.blue : palette.textTertiary)
                        .frame(maxWidth: .infinity)
                        .minimumScaleFactor(0.6).lineLimit(1)
                }
            }
        }
    }

    private var laneMeta: String {
        var bits: [String] = []
        if let d = active?.distance, d > 0 { bits.append("\(Int(d)) mi") }
        bits.append("\(crew.count) escort seat\(crew.count == 1 ? "" : "s")")
        if let cap = active?.convoy?.maxSpeedMph, cap > 0 { bits.append("\(cap) mph cap") }
        return bits.joined(separator: " · ")
    }

    private var laneMetaShort: String {
        if let s = active?.convoy?.status, !s.isEmpty { return "CONVOY \(s.uppercased())" }
        return (active?.cargoType ?? "OVERSIZE").uppercased()
    }

    // MARK: Roster — the ribbon's legend

    private var rosterSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHead("ROSTER · SEAT · CERT · SHARE",
                        trailing: rosterTrailing,
                        trailingTint: blockedCount > 0 ? Brand.danger : Brand.success)

            VStack(spacing: 3) {
                ForEach(crew) { m in seatRow(m) }
            }

            Text(routeStates.isEmpty
                 ? "✱ Cert verdicts need the route's states — pull to refresh while online."
                 : "✱ Verdicts are live reads of verifyEscortCertifications against \(routeStates.joined(separator: "+")) (escorts.ts:3310). Seat labels are escortAssignments.position, which carries lead | chase | both only.")
                .font(.system(size: 7.5, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rosterTrailing: String {
        if stalenessLine != nil { return "CERTS NOT VERIFIED" }
        if verdicts.isEmpty { return "VERIFYING…" }
        return blockedCount > 0 ? "\(blockedCount) NOT CLEARED" : "ALL CLEARED"
    }

    private func seatRow(_ m: TeamMemberRow) -> some View {
        let seat = TeamSeatKind(m.position)
        let verdict = m.userId.flatMap { verdicts[$0] }
        let blocked = verdict?.isBlocking ?? false
        let isMe = m.isMe ?? false
        let tint: Color = blocked ? Brand.danger : seat.tint(palette)

        return HStack(spacing: 0) {
            // share-tab — the tether back to this seat's ribbon cell
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isMe ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(tint))
                .frame(width: 4, height: 24)
                .padding(.trailing, 8)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(seat.label)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(seat.tint(palette))
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Capsule().fill(seat.tint(palette).opacity(0.16)))
                    Text(m.name ?? "Escort")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    if isMe {
                        Text("YOU").font(.system(size: 8, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(Brand.blue)
                    }
                    Spacer(minLength: Space.s2)
                    // Only MY rate exists on this contract. Everyone else's
                    // seat renders an em-dash, never a fabricated figure.
                    Text(isMe ? currency(active?.myRate) : "—")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(isMe ? palette.textPrimary : palette.textTertiary)
                }
                HStack(spacing: Space.s2) {
                    Text(statusLine(m))
                        .font(EType.mono(.micro))
                        .foregroundStyle(blocked ? Brand.danger : palette.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: Space.s1)
                    certChip(verdict)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(blocked ? Brand.danger.opacity(0.08) : palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(blocked ? Brand.danger.opacity(0.45) : palette.borderFaint,
                                  lineWidth: 1))
        )
    }

    private func statusLine(_ m: TeamMemberRow) -> String {
        let st = (m.status ?? "").replacingOccurrences(of: "_", with: " ").uppercased()
        var bits: [String] = []
        if !st.isEmpty { bits.append(st) }
        if let uid = m.userId { bits.append("ID \(uid)") }
        return bits.isEmpty ? "SEATED" : bits.joined(separator: " · ")
    }

    /// A missing verdict is NEVER drawn as cleared — that is the whole point
    /// of keeping cert reads out of the cache.
    private func certChip(_ v: CertVerdict?) -> some View {
        let text: String
        let tint: Color
        if let v {
            text = v.chip
            tint = v.verified ? Brand.success : Brand.danger
        } else {
            text = stalenessLine != nil ? "AS OF SNAPSHOT" : "NOT VERIFIED"
            tint = palette.textTertiary
        }
        return Text(text)
            .font(.system(size: 7.5, weight: .heavy)).tracking(0.3)
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.16)))
            .lineLimit(1)
    }

    // MARK: Availability · reserve bench (real pool, no invented ETA)

    private var benchSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHead("AVAILABILITY · RESERVE BENCH",
                        trailing: bench.isEmpty ? "NONE RETURNED" : "\(bench.count) CERTIFIED",
                        trailingTint: bench.isEmpty ? palette.textTertiary : Brand.success)

            VStack(alignment: .leading, spacing: Space.s2) {
                if bench.isEmpty {
                    Text(routeStates.isEmpty
                         ? "Bench needs a live connection — findQualifiedEscorts is an ONLINE_ONLY read."
                         : "No certified escort outside this crew covers \(routeStates.joined(separator: "+")).")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    let shown = Array(bench.prefix(3))
                    HStack(spacing: Space.s2) {
                        ForEach(shown.indices, id: \.self) { i in benchChip(shown[i]) }
                    }
                }
                Text("✱ The server returns no availability, distance or ETA for a bench escort (escorts.ts:3464-3475), so none is drawn — only the states they are certified for.")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(card)
        }
    }

    private func benchChip(_ b: QualifiedEscort) -> some View {
        let covers = (b.statesCovered ?? 0) >= routeStates.count && !routeStates.isEmpty
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(covers ? Brand.success : Brand.warning)
                    .frame(width: 8, height: 8)
                Text(b.name ?? "Escort")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
            }
            Text((b.certifiedStates ?? []).joined(separator: "+"))
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(covers ? Brand.success : palette.textSecondary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(covers ? Brand.success.opacity(0.10) : palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(covers ? Brand.success.opacity(0.55) : palette.borderFaint,
                                  lineWidth: 1))
        )
    }

    // MARK: Fleet band — the SECOND DENSITY, built from the one company-shaped read

    private var fleetSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            sectionHead("CERTIFIED POOL · CORRIDOR DENSITY",
                        trailing: routeStates.isEmpty ? "OFFLINE" : routeStates.joined(separator: " + "),
                        trailingTint: palette.textTertiary)

            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .top, spacing: Space.s3) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("CERTIFIED FOR THIS ROUTE")
                            .font(.system(size: 7.5, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(palette.textTertiary)
                        HStack(spacing: 6) {
                            Text(poolTotal.map(String.init) ?? "—")
                                .font(.system(size: 20, weight: .heavy, design: .monospaced))
                                .foregroundStyle(LinearGradient.diagonal)
                            if poolTotal != nil {
                                Circle().fill(AnyShapeStyle(Brand.success)).frame(width: 6, height: 6)
                                Text("LIVE").font(.system(size: 7.5, weight: .heavy)).tracking(0.4)
                                    .foregroundStyle(Brand.success)
                            }
                        }
                        Text("server cap 20")
                            .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                    }
                    Rectangle().fill(palette.borderFaint).frame(width: 1, height: 46)
                    poolMatrix
                    Spacer(minLength: 0)
                }
                Text("✱ This is the certified corridor pool, not a company roster: there is no escort-company entity — escortCompany is a metadata string (escorts.ts:3142) and companies.getFleet returns vehicles scoped to a companyId an escort does not carry.")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(card)
        }
    }

    /// One cell per escort the server actually returned. The cells already
    /// seated on my string carry a light core.
    private var poolMatrix: some View {
        let seated = Set(crew.compactMap { $0.userId })
        let cells: [QualifiedEscort] = Array(pool.prefix(20))
        let rows: [[QualifiedEscort]] = stride(from: 0, to: cells.count, by: 10).map {
            Array(cells[$0 ..< min($0 + 10, cells.count)])
        }
        return VStack(alignment: .leading, spacing: 6) {
            if cells.isEmpty {
                Text("no pool returned")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            } else {
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 6) {
                        ForEach(rows[r].indices, id: \.self) { c in
                            poolCell(rows[r][c], seated: seated)
                        }
                    }
                }
                Text("◉ = already on this string · \(seated.count) seated")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private func poolCell(_ e: QualifiedEscort, seated: Set<Int>) -> some View {
        let onString = seated.contains(e.userId ?? -1)
        return ZStack {
            Circle().fill(onString ? Brand.blue : Brand.blue.opacity(0.45))
            if onString {
                Circle().fill(palette.bgCard).frame(width: 4, height: 4)
            }
        }
        .frame(width: 11, height: 11)
    }

    // MARK: States

    private var loadingBlock: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 58)
            }
        }
        .redacted(reason: .placeholder)
    }

    private var emptyBlock: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("No team on the board")
                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text("escorts.getMyTeam returns a crew only for moves you are assigned to. Take a job and the seats appear here.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
    }

    private var offlineBlock: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 6) {
                Circle().fill(palette.textTertiary).frame(width: 8, height: 8)
                Text("OFFLINE").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("No connection and no snapshot inside 10 minutes. A stale roster is refused rather than shown as current — pull to refresh.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card)
    }

    private func cacheStrip(_ line: String) -> some View {
        HStack(spacing: Space.s2) {
            Circle().fill(palette.textTertiary).frame(width: 8, height: 8)
            Text("READ_CACHED 10m · \(line) · certs live-only")
                .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: Space.s2)
            Text("SNAPSHOT")
                .font(.system(size: 8.5, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1))
        )
    }

    // MARK: Actions

    private var actionBar: some View {
        HStack(spacing: Space.s2) {
            Button {
                Task { await verifyCrew() }
            } label: {
                Text(verifying ? "VERIFYING…" : verifyLabel)
                    .font(.system(size: 13, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(routeStates.isEmpty
                                ? AnyShapeStyle(palette.textTertiary.opacity(0.4))
                                : AnyShapeStyle(LinearGradient.primary))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(verifying || routeStates.isEmpty)

            Button {
                toast = "No seat-swap procedure exists yet — applyForJob and acceptJob are both self-scoped, so a lead cannot move another escort onto a seat. Filed, not faked."
            } label: {
                VStack(spacing: 2) {
                    Text("REQUEST SWAP")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textPrimary)
                    Text("✱ no procedure yet")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
                .frame(width: 150, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCardSoft)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderSoft, lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var verifyLabel: String {
        routeStates.isEmpty ? "VERIFY · ONLINE ONLY"
                            : "VERIFY CREW · \(routeStates.joined(separator: "+"))"
    }

    @ViewBuilder
    private var toastLayer: some View {
        if let msg = toast {
            Text(msg)
                .font(EType.caption).foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.textPrimary.opacity(0.92)))
                .padding(.horizontal, 20).padding(.bottom, 108)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task {
                    try? await Task.sleep(nanoseconds: 3_600_000_000)
                    await MainActor.run { withAnimation(.easeOut(duration: 0.2)) { toast = nil } }
                }
        }
    }

    // MARK: Shared chrome

    private func sectionHead(_ title: String, trailing: String, trailingTint: Color) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s2)
            Text(trailing)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(trailingTint)
                .lineLimit(1)
        }
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .fill(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private func currency(_ v: Double?) -> String {
        guard let v, v > 0 else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }

    // MARK: - Data · READ_CACHED(10m) roster + ONLINE_ONLY cert/pool reads

    private func refresh() async {
        if assignments.isEmpty { phase = .loading }
        do {
            let rows: [TeamAssignment] = try await EusoTripAPI.shared.queryNoInput("escorts.getMyTeam")
            EscortOfflineCache.store(rows, key: Self.teamKey)
            await MainActor.run {
                assignments = rows
                stalenessLine = nil          // live read — no staleness line
                phase = rows.isEmpty ? .empty : .loaded
            }
            await loadLiveOnlyReads()
        } catch {
            await paintSnapshotOrFail()
        }
    }

    /// The honesty law: paint the last-good roster only if it is inside the
    /// declared ttl, always render its age, and drop every cert verdict — a
    /// safety verdict is never served from disk.
    private func paintSnapshotOrFail() async {
        guard let cached = EscortOfflineCache.load([TeamAssignment].self,
                                                   key: Self.teamKey,
                                                   ttl: Self.cacheTTL) else {
            await MainActor.run { if assignments.isEmpty { phase = .failed } }
            return
        }
        let line = EscortOfflineCache.stalenessLine(age: cached.age)
        await MainActor.run {
            assignments = cached.value
            verdicts = [:]                 // cert verdicts are never cached
            pool = []
            poolTotal = nil
            routeStates = []
            stalenessLine = line
            phase = cached.value.isEmpty ? .empty : .loaded
        }
    }

    /// ONLINE_ONLY: route states → per-member cert verdicts + the certified
    /// corridor pool + the company name. Nothing here is ever written to disk.
    private func loadLiveOnlyReads() async {
        guard let a = active else { return }
        let states = await resolveRouteStates(a)
        await MainActor.run { routeStates = states }
        guard !states.isEmpty else { return }

        // Company name (subset of getProfile — escorts.ts:3081).
        if companyName == nil {
            let profile: EscortProfileLite? = try? await EusoTripAPI.shared
                .queryNoInput("escorts.getProfile")
            if let c = profile?.escortCompany, !c.isEmpty {
                await MainActor.run { companyName = c }
            }
        }

        // Certified corridor pool — bench + the band's live figure.
        if let q: QualifiedResult = try? await EusoTripAPI.shared.query(
            "escorts.findQualifiedEscorts",
            input: QualifiedInput(routeStates: states, position: "both")) {
            await MainActor.run {
                pool = q.escorts ?? []
                poolTotal = q.totalAvailable ?? q.escorts?.count
            }
        }

        await verifyCrew(states: states, announce: false)
    }

    /// Runs escorts.verifyEscortCertifications (escorts.ts:3310) once per
    /// seated escort. Server error strings are surfaced verbatim.
    private func verifyCrew(states: [String]? = nil, announce: Bool = true) async {
        let required = states ?? routeStates
        guard !required.isEmpty else {
            if announce {
                await MainActor.run {
                    toast = "Cert verification needs a live connection and a resolved route — pull to refresh."
                }
            }
            return
        }
        await MainActor.run { verifying = true }
        defer { Task { await MainActor.run { verifying = false } } }

        var found: [Int: CertVerdict] = [:]
        await withTaskGroup(of: (Int, CertVerdict)?.self) { group in
            for m in crew {
                guard let uid = m.userId else { continue }
                group.addTask {
                    do {
                        let r: VerifyCertsResult = try await EusoTripAPI.shared.query(
                            "escorts.verifyEscortCertifications",
                            input: VerifyCertsInput(escortUserId: uid, requiredStates: required))
                        return (uid, CertVerdict(verified: r.verified ?? false,
                                                 errors: r.errors ?? []))
                    } catch {
                        return nil
                    }
                }
            }
            for await result in group {
                if let (uid, v) = result { found[uid] = v }
            }
        }

        await MainActor.run {
            verdicts = found
            guard announce else { return }
            let bad = found.values.filter { $0.isBlocking }
            if bad.isEmpty {
                toast = found.isEmpty
                    ? "Verification didn't reach the server. Nothing on this crew is marked cleared."
                    : "Crew cleared for \(required.joined(separator: "+"))."
            } else if let first = bad.compactMap({ $0.errors.first }).first {
                toast = first          // the server's own wording, verbatim
            } else {
                toast = "\(bad.count) seat\(bad.count == 1 ? "" : "s") not cleared for \(required.joined(separator: "+"))."
            }
        }
    }

    /// escorts.getRouteStates (escorts.ts:3495). Origin/destination arrive as
    /// "City, ST" (escorts.ts:2156-2157), so the state is the trailing token.
    private func resolveRouteStates(_ a: TeamAssignment) async -> [String] {
        guard let o = stateCode(a.origin), let d = stateCode(a.destination) else { return [] }
        if let r: RouteStatesResult = try? await EusoTripAPI.shared.query(
            "escorts.getRouteStates",
            input: RouteStatesInput(originState: o, destinationState: d)),
           let s = r.states, !s.isEmpty {
            return s
        }
        // No local invention beyond the two endpoints the roster already gave us.
        return o == d ? [o] : [o, d]
    }

    private func stateCode(_ loc: String?) -> String? {
        guard let loc else { return nil }
        let tail = loc.components(separatedBy: ",").last?
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
        return tail.count == 2 ? tail : nil
    }
}

// MARK: - Registered surface wrapper

struct EscortTeamScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortTeam()
        } nav: {
            // Escort role tab bar TRIP · COMMS · PERMIT · ME. The team board is
            // a pushed route under TRIP until a dedicated TEAM slot lands —
            // EscortNavController.swift is a single-writer file and is NOT
            // edited by this drop. Nav entry needed: EscortNavRoute.map gains
            // "team": "ES19" (EscortNavController.swift:39-44), owner's call.
            BottomNav(
                leading: [
                    NavSlot(label: "Trip",  systemImage: "house",       isCurrent: true),
                    NavSlot(label: "Comms", systemImage: "bubble.left", isCurrent: false),
                ],
                trailing: [
                    NavSlot(label: "Permit", systemImage: "doc.text", isCurrent: false),
                    NavSlot(label: "Me",     systemImage: "person",   isCurrent: false),
                ],
                orbState: .idle
            )
        }
    }
}

#if DEBUG
// Previews don't run `.task`, so both variants render in the loading
// register without touching the network or the cache.
#Preview("ES-19 · Escort Team · Dark") {
    EscortTeamScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("ES-19 · Escort Team · Light") {
    EscortTeamScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
#endif
