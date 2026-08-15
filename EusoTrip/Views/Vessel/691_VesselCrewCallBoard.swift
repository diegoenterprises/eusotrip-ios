//
//  691_VesselCrewCallBoard.swift
//  EusoTrip — Vessel Operator · Crew Call Board.
//
//  Faithful port of "691 Vessel Crew Call Board.svg" (Light + Dark), adapted onto the canonical
//  DesignSystem (Shell · BottomNav · Theme.Palette · StatusPill · CTAButton · IridescentHairline).
//  Role VESSEL_OPERATOR (carrier-side). Nav anchored to VesselOperatorNavController
//  (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME) with the COMPLIANCE slot inked — safe manning is a
//  statutory surface (SOLAS V/14, STCW VIII/2), not an operations board.
//
//  ARCHETYPE: BOARD — a muster call is a field of people you must resolve one by one, so the screen is a
//  peg-board of person tiles, not a list. The prior cut was a watch-bill roster (hero + a 128x80 KPI trio +
//  four chip-and-mini-track rows); both of those organs are on the fire 16 forbidden list and none of it
//  survives here.
//
//  LIVE FUSION: the peg-board tiles, the state key counts, the three department coverage bars, the
//  exception rows and the ESang readiness line are FIVE faces of ONE state — the `crew` + `certifications`
//  payload from getVesselCrew. They all re-reason together off load(). Degraded provider state surfaces an
//  explicit error card, never a frozen number.
//
//  OFFLINE POLICY: READ_CACHED(15m) — the roster and certificate expiry hold for fifteen minutes. The
//  staleness is DRAWN, not claimed: the peg-board caption renders "CACHED HH:mm · TTL 15m" and flips to an
//  amber "STALE HH:mm" once the cache age passes the TTL. The call-out write, when it exists, is
//  ONLINE_ONLY(safety) and must never queue — a queued muster call is a lie about a person's whereabouts.
//
//  Data / wiring (line numbers read first-hand 2026-08-11 at HEAD):
//    vesselShipments.getVesselCrew (EXISTS server/routers/vesselShipments.ts:2085 · vesselProcedure ·
//      input {companyId?: z.coerce.number().optional(), search?: string} · returns
//      {crew:[{id,name,email,phone,role,profilePicture,isActive}], certifications: full certifications
//      rows {id,userId,type,name,expiryDate,status,documentUrl,createdAt}, expiringCount: number} —
//      assembled and returned at :2121. Source is the users table filtered by
//      inArray(users.role, ["VESSEL_SHIPPER","VESSEL_OPERATOR","PORT_MASTER","SHIP_CAPTAIN",
//      "VESSEL_BROKER","CUSTOMS_BROKER"]) joined to certifications at :2112, capped .limit(100).
//      Mounted at server/routers.ts:3349. Web peer client/src/pages/vessel/VesselCrew.tsx:58,
//      routed /vessel/crew and /vessel/crew/watch (client/src/App.tsx:1401 and :1405).
//    P0-READ-TENANCY (vesselShipments.ts:2092): companyFilter is input.companyId OR-ELSE
//      ctx.user.companyId, so the CALLER-SUPPLIED companyId WINS over ctx — any vessel-mode user can read
//      another tenant's whole roster incl. email, phone and certifications; and when that value is falsy
//      the company predicate at :2095 is never pushed and the query runs UNSCOPED across all companies,
//      capped only by .limit(100). This screen therefore never sends a caller-chosen companyId unless the
//      host explicitly threads one, and it says so on screen.
//    RBAC: vesselProcedure (server/_core/trpc.ts:268) is a MODE gate only — a CUSTOMS_BROKER and a
//      PORT_MASTER from two different companies pass identically. No tenant or role-within-mode scoping.
//    HONESTY CONSTRAINT: getVesselCrew has NO voyageId / portCallId / shipmentId input at all. It returns
//      PEOPLE WITH VESSEL ROLES, not a crew manifest for a port call. So the peg-board renders identity
//      (initials, rank, certificate expiry, whether a phone is on file) from live rows and REFUSES to
//      render call state as live.
//    STUB · named-gap crew-manifest-unread: vesselCrewManifests (drizzle/schema.ts:12077) carries
//      vesselId, voyageId, crewName, rank, nationality, passportNumber, seamanBookNumber, stcwCertified,
//      embarkedAt, disembarkedAt — and has ZERO readers anywhere in server/ (grep returns 0). Proposed
//      shape: vesselCrew.callBoard({voyageId:number}) -> {manifest:[{id,crewName,rank,nationality,
//      seamanBookNumber,stcwCertified,embarkedAt,disembarkedAt}], calls:[{manifestId,channel,calledAt,
//      ackedAt}], musterRequired:number}.
//    STUB · named-gap crew-call-out: no call / page / muster mutation exists anywhere in server/routers
//      (grep for recordCallOut, musterCall, acknowledgeCall returns 0). Proposed shape:
//      vesselCrew.recordCallOut({manifestId:number, channel:"VOICE"|"SMS"}) inserting a call row, inserting
//      blockchainAuditTrail eventType "vessel.crew_call_out", and broadcasting on
//      WS_CHANNELS.VESSEL_BOOKING (shared/websocket-events.ts:628). CALL and SMS are real Buttons that
//      surface that gap verbatim. Nothing on this screen ever fakes an acknowledgement.
//    STUB · named-gap manning-document: there is no minimum-safe-manning table, so the coverage tick marks
//      the FULL ROSTER of each bucket, never a statutory minimum, and the band says so on screen.
//    CHAIN: getVesselCrew writes no DB row, inserts no blockchainAuditTrail row, and broadcasts on no
//      WS_CHANNELS / WS_EVENTS constant. It is strictly read-only. There is no CHAIN-OPEN verb here and no
//      counter-party to notify — the gap is upstream: the write that would need broadcasting does not exist.
//
//  ZERO-FALLBACK: state starts EMPTY, the loader overwrites UNCONDITIONALLY, an honest empty response
//  renders the bespoke empty state and never fabricated rows. Every counter on screen is derived from THIS
//  state — there is not one parallel literal. File-scoped types are suffixed 691 to avoid cross-file
//  private collisions.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen wrapper (Shell + vessel nav · COMPLIANCE inked)

struct VesselCrewCallBoardScreen: View {
    let theme: Theme.Palette
    /// Tenant the board reads. 0 (the default, and the ONLY safe value) omits companyId from the wire so
    /// the server falls back to ctx.user.companyId. A non-zero value is only ever passed when the host
    /// explicitly threads one, because vesselShipments.ts:2092 lets a caller-supplied companyId override
    /// ctx — see the P0-READ-TENANCY note in the file header.
    var companyId: Int = 0

    init(theme: Theme.Palette, companyId: Int = 0) {
        self.theme = theme
        self.companyId = companyId
    }

    var body: some View {
        Shell(theme: theme) {
            VesselCrewCallBoardBody691(companyId: companyId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",         systemImage: "person",                isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror vesselShipments.getVesselCrew return rows exactly)

/// `getVesselCrew().crew[]` — the select list at vesselShipments.ts:2100-2108.
private struct CrewMember691: Decodable, Identifiable {
    let id: Int
    let name: String?
    let email: String?
    let phone: String?
    let role: String?
    let profilePicture: String?
    let isActive: Bool?
}

/// `getVesselCrew().certifications[]` — `db.select().from(certifications)` at :2112, so the FULL row
/// (drizzle/schema.ts:1945): id, userId, type, name, expiryDate, status, documentUrl, createdAt.
private struct CrewCert691: Decodable, Identifiable {
    let id: Int
    let userId: Int?
    let type: String?
    let name: String?
    let expiryDate: String?
    let status: String?
    let documentUrl: String?
}

private struct CrewCallBoardPayload691: Decodable {
    let crew: [CrewMember691]
    let certifications: [CrewCert691]?
    /// Server-computed count of certs expiring inside 90 days (:2115-2119). Absent on the
    /// no-database early return at :2089, hence optional.
    let expiringCount: Int?
}

/// The four states a tile can carry. EVERY ONE OF THESE IS DERIVED FROM A LIVE FIELD ON THE WIRE.
/// The call-board states the design calls for — CALLED / ACKED / ONBOARD — are deliberately NOT here:
/// nothing on the wire can prove them, and the state key renders them as an explicit gap instead.
private enum PegState691: Int, CaseIterable {
    case noContact = 0   // users.phone is null or blank  -> there is literally no channel to call
    case offRoster = 1   // users.isActive == false        -> not on the active roster
    case certExp   = 2   // a certifications row expires inside 90 days
    case ready     = 3   // active, contactable, no cert expiring inside 90 days

    var label: String {
        switch self {
        case .noContact: return "NO CONTACT"
        case .offRoster: return "OFF ROSTER"
        case .certExp:   return "CERT EXP"
        case .ready:     return "READY"
        }
    }
    var short: String {
        switch self {
        case .noContact: return "NO CTC"
        case .offRoster: return "OFF"
        case .certExp:   return "CERT"
        case .ready:     return "READY"
        }
    }
    var source: String {
        switch self {
        case .noContact: return "LIVE phone"
        case .offRoster: return "LIVE isActive"
        case .certExp:   return "LIVE certs"
        case .ready:     return "LIVE roster"
        }
    }
}

private enum Dept691: String, CaseIterable, Identifiable {
    case bridge     = "Bridge"
    case operations = "Operations"
    case brokerage  = "Brokerage"
    var id: String { rawValue }

    /// The buckets are the REAL role enum getVesselCrew filters on (vesselShipments.ts:2091) —
    /// not invented shipboard departments. Deck / Engine / Catering do not exist on this wire.
    var roles: [String] {
        switch self {
        case .bridge:     return ["SHIP_CAPTAIN", "PORT_MASTER"]
        case .operations: return ["VESSEL_OPERATOR", "VESSEL_SHIPPER"]
        case .brokerage:  return ["VESSEL_BROKER", "CUSTOMS_BROKER"]
        }
    }
}

// MARK: - Body

private struct VesselCrewCallBoardBody691: View {
    @Environment(\.palette) private var palette
    let companyId: Int

    // Live state — starts empty, load() overwrites unconditionally.
    @State private var crew: [CrewMember691] = []
    @State private var certs: [CrewCert691] = []
    @State private var serverExpiringCount: Int? = nil
    @State private var syncedAt: Date? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var gapNotice: String? = nil
    @State private var showCerts = false

    /// READ_CACHED(15m) — the roster holds fifteen minutes, then the caption goes amber.
    private let cacheTTL: TimeInterval = 15 * 60

    // MARK: Derived reads — every counter on screen comes from here, never a literal

    private var certsByUser: [Int: [CrewCert691]] {
        Dictionary(grouping: certs.filter { $0.userId != nil }, by: { $0.userId ?? -1 })
    }

    private func daysUntil691(_ iso: String?) -> Int? {
        guard let iso, !iso.isEmpty else { return nil }
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        let date = f1.date(from: iso) ?? f2.date(from: iso)
        guard let date else { return nil }
        return Int(floor(date.timeIntervalSinceNow / 86_400))
    }

    /// The soonest-expiring live certificate for a person, if any.
    private func soonestCert691(_ m: CrewMember691) -> (cert: CrewCert691, days: Int)? {
        let rows = certsByUser[m.id] ?? []
        let dated = rows.compactMap { c -> (CrewCert691, Int)? in
            guard let d = daysUntil691(c.expiryDate) else { return nil }
            return (c, d)
        }
        return dated.min(by: { $0.1 < $1.1 }).map { (cert: $0.0, days: $0.1) }
    }

    private func hasPhone691(_ m: CrewMember691) -> Bool {
        guard let p = m.phone else { return false }
        return !p.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func state691(_ m: CrewMember691) -> PegState691 {
        if !hasPhone691(m) { return .noContact }
        if (m.isActive ?? true) == false { return .offRoster }
        if let s = soonestCert691(m), s.days >= 0, s.days <= 90 { return .certExp }
        return .ready
    }

    /// Worst first, so the board reads top-left to bottom-right in the order the duty officer must work.
    private var orderedCrew: [CrewMember691] {
        crew.sorted { a, b in
            let sa = state691(a).rawValue, sb = state691(b).rawValue
            if sa != sb { return sa < sb }
            return (a.name ?? "").localizedCaseInsensitiveCompare(b.name ?? "") == .orderedAscending
        }
    }

    private var pegTiles: [CrewMember691] { Array(orderedCrew.prefix(12)) }

    private func count691(_ s: PegState691) -> Int { crew.filter { state691($0) == s }.count }

    private var noContactCount: Int { count691(.noContact) }

    /// EXCEPTIONS = everyone, because nothing on this wire can prove an acknowledgement. That is the
    /// honest reading of "who has not acked", and the section header says exactly that.
    private var exceptions: [CrewMember691] { orderedCrew }

    private var cacheAge: TimeInterval { syncedAt.map { -$0.timeIntervalSinceNow } ?? 0 }
    private var isStale: Bool { syncedAt != nil && cacheAge > cacheTTL }
    private var syncedLabel: String {
        guard let syncedAt else { return "NOT SYNCED" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return isStale ? "STALE \(f.string(from: syncedAt))" : "CACHED \(f.string(from: syncedAt)) · TTL 15m"
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s5) {
                eyebrow
                titleRow
                IridescentHairline()

                if loading {
                    loadingState
                } else if let err = loadError {
                    errorState(err)
                } else if crew.isEmpty {
                    emptyState
                } else {
                    pegBoardSection
                    coverageSection
                    exceptionSection
                }

                if let note = gapNotice { gapCard(note) }

                esangRow
                countryFooter
                ctaPair

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
        .sheet(isPresented: $showCerts) {
            CrewCertSheet691(certs: certs, crew: crew).environment(\.palette, palette)
        }
    }

    // MARK: Header

    private var eyebrow: some View {
        HStack {
            HStack(spacing: 5) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                Text("VESSEL · COMPLIANCE · CREW CALL")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
            }
            Spacer()
            // Honest scope chip: the tenant actually asked for, or "CTX SCOPE" when we let the server
            // scope from ctx (the safe path — see P0-READ-TENANCY in the header).
            Text(companyId > 0 ? "CO \(companyId)" : "CTX SCOPE")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleRow: some View {
        HStack(alignment: .center) {
            Text("Crew call board")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
        }
    }

    // MARK: Loading / error / empty

    private var loadingState: some View {
        VStack(spacing: Space.s2) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 248)
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 110)
            }
        }
    }

    private func errorState(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Roster feed degraded").font(EType.bodyStrong).foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("No tile is drawn from a cached guess — the board stays empty until the crew roster answers.")
                .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NO ONE ROSTERED").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text("Nobody to call")
                .font(.system(size: 22, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text("The crew roster for this company came back empty. That is the real answer, not a loading state — no tiles are drawn.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s5).frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.xl)
    }

    // MARK: HERO ORGAN — muster peg-board

    private var pegBoardSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("MUSTER PEG-BOARD · \(crew.count) ROSTERED")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(syncedLabel)
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(isStale ? Brand.warning : palette.textTertiary)
            }

            HStack(alignment: .top, spacing: Space.s3) {
                // 3-column peg field of person tiles
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                          spacing: 8) {
                    ForEach(pegTiles) { m in
                        PegTile691(initials: initials691(m.name),
                                   rank: rankToken691(m.role),
                                   state: state691(m))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                stateKey
                    .frame(width: 96, alignment: .leading)
            }

            if crew.count > pegTiles.count {
                Text("\(crew.count - pegTiles.count) more rostered below the peg field — every one of them is in the exception list.")
                    .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.xl)
    }

    /// The state key does two jobs: it decodes the four LIVE tile states, and it names — in the same
    /// breath — the three call-board states the platform cannot prove yet. That is the whole point of
    /// this screen: you can see at a glance which half of the muster is real.
    private var stateKey: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(PegState691.allCases.sorted(by: { $0.rawValue < $1.rawValue }), id: \.rawValue) { s in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(color691(s)).frame(width: 12, height: 12)
                        Text("\(count691(s))")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(palette.textPrimary)
                    }
                    Text(s.label).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(palette.textPrimary)
                    Text(s.source).font(.system(size: 8, weight: .bold)).tracking(0.3)
                        .foregroundStyle(Brand.success)
                }
            }

            LinearGradient.primary.frame(height: 1.5).opacity(0.55)

            VStack(alignment: .leading, spacing: 2) {
                Text("CALLED · ACKED\n· ONBOARD")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(palette.textPrimary)
                Text("STUB — no call\nwrite, manifest\nunread")
                    .font(.system(size: 8, weight: .bold)).tracking(0.3)
                    .foregroundStyle(Brand.warning)
                Text("MUSTER COUNT")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary).padding(.top, 4)
                Text("NOT PERSISTED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Brand.warning)
            }
        }
    }

    private func color691(_ s: PegState691) -> Color {
        switch s {
        case .ready:     return Brand.success
        case .certExp:   return Brand.warning
        case .noContact: return Brand.danger
        case .offRoster: return Brand.neutral
        }
    }

    // MARK: MID-BAND ORGAN — department coverage bars + roster tick

    private var coverageSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("ROLE COVERAGE · REACHABLE vs ROSTERED")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("MIN MANNING · STUB")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Brand.warning)
            }

            VStack(alignment: .leading, spacing: Space.s3) {
                ForEach(Dept691.allCases) { d in
                    let members = crew.filter { d.roles.contains(($0.role ?? "").uppercased()) }
                    let reachable = members.filter { hasPhone691($0) && ($0.isActive ?? true) }.count
                    let total = members.count
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(d.rawValue).font(.system(size: 11, weight: .bold))
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(total == 0 ? "0 rostered" : "\(reachable) reachable · \(total) rostered")
                                .font(.system(size: 11, weight: .bold)).monospacedDigit()
                                .foregroundStyle(total == 0 ? palette.textTertiary
                                                 : (reachable == total ? Brand.success : Brand.danger))
                        }
                        CoverageBar691(fillFrac: total == 0 ? 0 : Double(reachable) / Double(total),
                                       showTick: total > 0)
                    }
                }

                Text("The hard tick marks the FULL ROSTER of the bucket, not a statutory minimum: this platform carries no minimum-safe-manning table, so no legal floor is drawn. Buckets are the crew roles this platform actually records — Deck, Engine and Catering are not among them.")
                    .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if let n = serverExpiringCount {
                    Text("\(n) certificate\(n == 1 ? "" : "s") expiring inside 90 days (server-computed at vesselShipments.ts:2115).")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(n > 0 ? Brand.warning : palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.lg)
        }
    }

    // MARK: ROW GRAMMAR — exception rows only

    private var exceptionSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("EXCEPTIONS · NO ACK · \(exceptions.count) OF \(crew.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("ACK CLOCK · STUB")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Brand.warning)
            }

            Text("Nothing on this wire can prove an acknowledgement, so every rostered hand is an exception until a call-out row can be written. This list is not filtered down to flatter the number.")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(Array(exceptions.enumerated()), id: \.element.id) { idx, m in
                    exceptionRow(m)
                    if idx < exceptions.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1)
                            .padding(.vertical, 2)
                    }
                }
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .eusoCard(radius: Radius.lg)
        }
    }

    private func exceptionRow(_ m: CrewMember691) -> some View {
        let st = state691(m)
        let soonest = soonestCert691(m)
        return HStack(alignment: .center, spacing: Space.s3) {
            // r14 initials disc — NOT a square chip
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 28, height: 28)
                Text(initials691(m.name))
                    .font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(m.name?.isEmpty == false ? (m.name ?? "—") : "Unnamed roster row")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(certLine691(m, st, soonest))
                    .font(EType.mono(.caption))
                    .foregroundStyle(st == .noContact ? Brand.danger : palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Right cluster — the minutes-since-call slot, honestly empty.
            VStack(alignment: .trailing, spacing: 1) {
                Text("SINCE CALL").font(.system(size: 8, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                Text("—").font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
            }

            // 52x24 rx12 micro pair — real Buttons, honest gap notice.
            HStack(spacing: 6) {
                Button { gapNotice = callGapNotice(m, channel: "VOICE") } label: {
                    Text("CALL").font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 24)
                        .background(Capsule().fill(LinearGradient.primary))
                }
                .buttonStyle(.plain)
                Button { gapNotice = callGapNotice(m, channel: "SMS") } label: {
                    Text("SMS").font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 52, height: 24)
                        .background(Capsule().strokeBorder(palette.borderSoft))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, Space.s2)
    }

    private func certLine691(_ m: CrewMember691, _ st: PegState691, _ soonest: (cert: CrewCert691, days: Int)?) -> String {
        let rank = rankLabel691(m.role)
        if st == .noContact { return "\(rank) · no phone on file" }
        if st == .offRoster { return "\(rank) · isActive false" }
        if let s = soonest {
            let nm = (s.cert.name?.isEmpty == false ? s.cert.name : s.cert.type) ?? "certificate"
            return s.days < 0 ? "\(rank) · \(nm) EXPIRED" : "\(rank) · \(nm) exp \(s.days)d"
        }
        return "\(rank) · no certificate on file"
    }

    private func callGapNotice(_ m: CrewMember691, channel: String) -> String {
        let who = m.name?.isEmpty == false ? (m.name ?? "this hand") : "this roster row"
        return "Nothing was written. \(who) was not marked called and no acknowledgement was recorded — call-out logging is not built yet, so the \(channel) button had nowhere to record it and sent no message. Raise the hand on the radio or by phone, and keep the muster on paper until call-out logging ships."
    }

    private func gapCard(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("HONEST GAP").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.warning)
                Spacer()
                Button { gapNotice = nil } label: {
                    Text("DISMISS").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
            }
            Text(note).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.warning.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Brand.warning.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: ESang · muster readiness (fused off the same roster read)

    private var esangRow: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Circle().fill(Color.white.opacity(0.35)).frame(width: 14, height: 14).offset(x: -5, y: -5)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG · MUSTER READINESS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text(esangHeadline).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(esangDetail).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private var esangHeadline: String {
        if crew.isEmpty { return "No roster to read yet" }
        if noContactCount == 0 { return "Every rostered hand has a contact channel" }
        return "\(noContactCount) hand\(noContactCount == 1 ? " has" : "s have") no phone on file"
    }

    private var esangDetail: String {
        if crew.isEmpty { return "This line is derived from the live roster read, so it stays silent until one lands." }
        if noContactCount == 0 {
            return "Contact is the only part of the muster this platform can prove today — the called and acknowledged states still have no write behind them."
        }
        return "Fix contact before the next muster: a hand with no channel cannot be called at all, and the platform cannot record the attempt either way."
    }

    // MARK: Country footer · manning regime

    private var countryFooter: some View {
        HStack(spacing: 6) {
            Text("MANNING REGIME").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 4)
            regimePill("US · USCG", active: true)
            regimePill("CA · TC MPR", active: false)
            regimePill("MX · SEMAR", active: false)
        }
    }

    private func regimePill(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .foregroundStyle(active ? Brand.blue : palette.textTertiary)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(active ? Brand.info.opacity(0.10) : palette.tintNeutral))
    }

    // MARK: CTA pair (varied off the retired 260 + 132)

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Start muster call", action: {
                gapNotice = "Nothing was written. Muster calls are not available yet: this platform cannot tell who is expected on THIS voyage — only who holds a vessel role at all — and it has nowhere to record that you called. Nobody was paged. Muster over the radio and take attendance on paper."
            }, leadingIcon: "megaphone.fill")
            Button { showCerts = true } label: {
                Text("Certificates")
                    .font(EType.title).foregroundStyle(palette.textPrimary)
                    .frame(width: 148).frame(minHeight: 52)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Formatting helpers

    private func initials691(_ name: String?) -> String {
        let parts = (name ?? "").split(separator: " ").filter { !$0.isEmpty }
        if parts.isEmpty { return "—" }
        if parts.count == 1 { return String(parts[0].prefix(2)).uppercased() }
        return (String(parts[0].prefix(1)) + String(parts[parts.count - 1].prefix(1))).uppercased()
    }

    private func rankToken691(_ role: String?) -> String {
        switch (role ?? "").uppercased() {
        case "SHIP_CAPTAIN":    return "MST"
        case "PORT_MASTER":     return "PM"
        case "VESSEL_OPERATOR": return "OPS"
        case "VESSEL_SHIPPER":  return "SHP"
        case "VESSEL_BROKER":   return "BRK"
        case "CUSTOMS_BROKER":  return "CHB"
        default:                return "—"
        }
    }

    private func rankLabel691(_ role: String?) -> String {
        switch (role ?? "").uppercased() {
        case "SHIP_CAPTAIN":    return "Ship Captain"
        case "PORT_MASTER":     return "Port Master"
        case "VESSEL_OPERATOR": return "Vessel Operator"
        case "VESSEL_SHIPPER":  return "Vessel Shipper"
        case "VESSEL_BROKER":   return "Vessel Broker"
        case "CUSTOMS_BROKER":  return "Customs Broker"
        default:                return "Role not set"
        }
    }

    // MARK: Loader — the one and only source of every number on this screen

    private func load() async {
        loading = true; loadError = nil
        // companyId is omitted (nil) unless the host explicitly threaded one, so the server scopes from
        // ctx.user.companyId. Sending a caller-chosen tenant here is exactly the P0-READ-TENANCY hole at
        // vesselShipments.ts:2092 — this screen refuses to exercise it by default.
        struct CrewIn691: Encodable { let companyId: Int?; let search: String? }
        do {
            let payload: CrewCallBoardPayload691 = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselCrew",
                input: CrewIn691(companyId: companyId > 0 ? companyId : nil, search: nil))
            // UNCONDITIONAL overwrite — an honest empty roster clears the board.
            crew = payload.crew
            certs = payload.certifications ?? []
            serverExpiringCount = payload.expiringCount
            syncedAt = Date()
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }
}

// MARK: - Peg tile (86x52 rx12 · r13 initials disc + rank 8/800 + live state fill)

private struct PegTile691: View {
    @Environment(\.palette) private var palette
    let initials: String
    let rank: String
    let state: PegState691

    private var color: Color {
        switch state {
        case .ready:     return Brand.success
        case .certExp:   return Brand.warning
        case .noContact: return Brand.danger
        case .offRoster: return Brand.neutral
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().fill(color.opacity(0.18)).frame(width: 26, height: 26)
                Text(initials).font(.system(size: 10, weight: .heavy)).foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(rank).font(.system(size: 8, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textPrimary)
                Text(state.short).font(.system(size: 8, weight: .bold)).tracking(0.4)
                    .foregroundStyle(color)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.08)))
        // Dashed rim = the call layer (CALLED / ACKED / ONBOARD) is unproven for EVERY tile, because no
        // call-out write and no manifest read exist. The fill is live; the rim says the muster is not.
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(color.opacity(0.55),
                          style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5])))
    }
}

// MARK: - Coverage bar (368x10 rx5 fill + hard 2x16 roster tick)

private struct CoverageBar691: View {
    @Environment(\.palette) private var palette
    let fillFrac: Double
    let showTick: Bool

    var body: some View {
        GeometryReader { geo in
            let w = max(geo.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(palette.tintNeutral).frame(height: 10)
                if fillFrac > 0 {
                    Capsule().fill(LinearGradient.primary)
                        .frame(width: max(8, w * min(1, fillFrac)), height: 10)
                }
                if showTick {
                    Rectangle().fill(palette.textPrimary)
                        .frame(width: 2, height: 16)
                        .offset(x: w - 2)
                }
            }
            .frame(width: w, height: 16, alignment: .leading)
        }
        .frame(height: 16)
    }
}

// MARK: - Certificates sheet (live certifications rows from the SAME payload)

private struct CrewCertSheet691: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let certs: [CrewCert691]
    let crew: [CrewMember691]

    private var nameByUser: [Int: String] {
        Dictionary(crew.map { ($0.id, $0.name ?? "Unnamed roster row") }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s3) {
                    Text("Live per-person certificate rows for this roster. This is the only per-crew source EusoTrip holds — the vessel certificate register covers ISPS and insurance at ship level and carries no individual STCW entry, so check the seafarer’s own book for anything missing here.")
                        .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if certs.isEmpty {
                        Text("No certificate rows returned for this roster.")
                            .font(EType.bodyStrong).foregroundStyle(palette.textTertiary)
                            .padding(.top, Space.s3)
                    } else {
                        ForEach(certs) { c in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text((c.name?.isEmpty == false ? c.name : c.type) ?? "Certificate")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(palette.textPrimary)
                                    Spacer()
                                    StatusPill(text: c.status ?? "unknown",
                                               kind: (c.status ?? "") == "active" ? .success
                                                   : ((c.status ?? "") == "expired" ? .danger : .neutral))
                                }
                                Text("\(nameByUser[c.userId ?? -1] ?? "Unlinked") · expires \(c.expiryDate ?? "not set")")
                                    .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                                    .lineLimit(1)
                            }
                            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
                            .eusoRow(radius: Radius.md)
                        }
                    }
                }
                .padding(Space.s5)
            }
            .background(palette.bgPage.ignoresSafeArea())
            .navigationTitle("Certificates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("691 Crew Call Board · Light") {
    VesselCrewCallBoardScreen(theme: Theme.light).environment(\.palette, Theme.light)
}

#Preview("691 Crew Call Board · Dark") {
    VesselCrewCallBoardScreen(theme: Theme.dark).environment(\.palette, Theme.dark)
}
