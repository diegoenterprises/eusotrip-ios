//
//  ES31_NotificationsAlerts.swift
//  EusoTrip — Escort · ES-31 Notifications & Alerts (the delivery-path board).
//
//  Built from the ES-31 twins
//  ("07 Escort/{Light,Dark}-SVG/ES-31 Notifications Alerts.svg").
//
//  ARCHETYPE BOARD — a DELIVERY-PATH BOARD. Nine parallel horizontal paths, one per
//  alert class, every one of them run against the same four-station ruler
//  EMIT -> CHANNEL -> CLIENT -> INBOX. A path that completes is drawn whole and
//  terminates in a real notification row. A path that dies is drawn only as far as it
//  gets and terminates in a red cut ON the station where it dies, labelled with the
//  exact missing symbol. The comparison the eye makes is HORIZONTAL, across paths.
//
//  Anti-clone. Deliberately NOT ES-17 Incidents & Claims: that is a VERTICAL SEVERITY
//  SPINE — one rail, four severity bands, rows hung off it in time order, one row blown
//  open. This screen has no severity rail, no blown-open row and no time ordering;
//  its axis is DELIVERY DISTANCE, not consequence. Deliberately NOT ES-14 My Jobs
//  (the nearest trap): that is a SIX-NODE STAGE FUNNEL — ONE flow narrowing through
//  stages with the empty stage drawn as a gap. This is NINE INDEPENDENT FLOWS, none of
//  which is a stage of any other; nothing narrows, and a cut here means "this class of
//  alert cannot physically arrive", not "no items at this stage". Deliberately NOT
//  ES-13's ranked leaderboard: no ordinal rail, no per-row metric bar, no radar ring —
//  the rows are ordered by how far the wire gets, not by value.
//
//  WIRING MANIFEST (every anchor opened at the line first-hand against the live tree
//  ~/Desktop/eusoronetechnologiesinc/frontend this fire):
//
//    REAL  notifications.list           notifications.ts:66   inbox rows; scope
//                                       eq(notifications.userId, ctx.user.id) :99 over
//                                       the `notifications` table drizzle/schema.ts:1022.
//                                       Row formatted notifications.ts:113-139.
//    REAL  notifications.getSummary     notifications.ts:37   {total,unread,read,alerts,
//                                       byCategory}. byCategory is HARD-ZERO at :54 and
//                                       is therefore never rendered.
//    REAL  notifications.getUnreadCount notifications.ts:480  bare Int.
//    REAL  notifications.markAllRead    notifications.ts:500  {channel?} ->
//                                       {success, ok, markedCount, updated}; writes
//                                       isRead/readAt/updatedAt at :516-518.
//    REAL  notifications.snooze         notifications.ts:531  ({notificationId, until})
//    REAL  notifications.archive        notifications.ts:263
//
//    The reader is genuinely alive and genuinely escort-callable. What is absent is a
//    WRITER. The board below is the diagnosis, and every line of it is falsifiable:
//
//    ESC-CP-NOINBOXROW    grep -n "notifications\|emitNotification"
//                         server/routers/escorts.ts  ->  0 hits / 4745 lines.
//                         No escort code path ever persists an alert. Fix pattern is
//                         already proven in-tree at trainingCompliance.ts:405-420
//                         (insert notificationsTable row at :405, emitNotification :412).
//    ESC-CP-JOBSROOM      emit escorts.ts:624 / _core/websocket.ts:1062 / Socket.IO twin
//                         socketService.ts:764 emitting to room "role:escort" at :766;
//                         the server ALREADY auto-joins the escort socket to that room
//                         at socketService.ts:205 and pushes "escort:jobs" for role
//                         ESCORT at _core/websocket.ts:525-526. Both halves swept:
//                         grep -rn "escort:job_available" over the iOS tree -> 2 hits,
//                         BOTH prose comments (ES13_JobMarketplace.swift:61,:64), 0 code;
//                         grep -rn "ESCORT_JOB_AVAILABLE" over the iOS tree -> 0;
//                         grep -rn "ESCORT_JOB_AVAILABLE" client/src -> 1 hit,
//                         useRealtimeEvents.ts:867 inside useEscortJobs() (defined :863,
//                         imported by nothing -> ESC-CP-JOBSHOOKORPHAN).
//                         The frame arrives and falls to `default:` — RealtimeService's
//                         switch has no case for it. ONE switch case fixes it. That file
//                         is a SHARED single-writer file and is NOT edited by this drop;
//                         the exact case is staged in the fire manifest.
//    ESC-CP-CERTSUB       emit escorts.ts:2590 -> WS_CHANNELS.USER(String(userId)) :2589.
//                         grep -rn "escort:cert_uploaded\|ESCORT_CERT_UPLOADED" over the
//                         iOS tree -> 4 hits, ALL prose comments in
//                         ES20_OnboardingRegistration.swift:131-135, 0 code; the same
//                         grep over client/src -> 0. No subscriber on either client.
//    ESC-CP-LEOSILENT     five LEO events — escorts.ts:124 no_show, :1725 on_scene,
//                         :1801 handoff_completed, :1847 incoming_eta, :1894 resolved.
//                         Ten greps (wire string + SCREAMING_CASE constant, iOS half and
//                         web half): forty results, all zero. Four of the five do not
//                         even address the escort — only escorts.ts:1901 targets
//                         USER(escortUserId); the rest go to DISPATCH_UPDATES + LOAD.
//    ESC-CP-CHECKSILENT   escort:check_submitted, emit escorts.ts:1297 and :1531 ->
//                         LOAD(a.loadId) :1301, DISPATCH only when !passed :1305.
//                         Both halves grepped -> iOS 0, web 0.
//    NO CERT-EXPIRY JOB   grep -rn "escortCertifications" server/ --include=*.ts |
//                         grep -v routers/escorts.ts  ->  0 results. Nothing scans
//                         escortCertifications.expirationDate: no cron, no poller, no
//                         scheduler, no notification service. That is why the CERT
//                         EXPIRY path is cut BEFORE its first station.
//    ESC-CP-DOTWRITEONLY  escorts.recordDOTNotification escorts.ts:3407 writes raw SQL
//                         into `system_alerts` (:3427); grep "systemAlerts = mysqlTable"
//                         drizzle/*.ts -> 0. No table, no reader. Not drawn as a path,
//                         because a write with no table is not a delivery path.
//
//  RBAC — the reader is the `notifications` router, gated by isolatedProcedure aliased
//  to the local name protectedProcedure at notifications.ts:10, resolving to
//  t.procedure.use(requireUser).use(isolationMiddleware).use(autoAudit) at
//  _core/trpc.ts:517 — ROLE-BLIND, so ESCORT passes and all 32 procedures are callable
//  today. It is deliberately NOT roleProcedure(ROLES.ESCORT) (_core/trpc.ts:228 over
//  ROLES.ESCORT :23) — that is the gate escorts.ts:11 imports as escortProcedure aliased
//  to protectedProcedure, and escorts.ts is precisely the router that never writes a row.
//  Rows are scoped by user id, not escort id; resolveEscortUserId (escorts.ts:138) does
//  not participate. No loads.rate, no shipper margin, no other-escort HOS here.
//
//  AUDIT — NO blockchainAuditTrail row is inserted. The literal token appears 0 times in
//  notifications.ts, 0 times in escorts.ts and 0 times in hazmatEscort.ts. The audit
//  surface that does fire is recordAuditEvent() reached through the autoAudit middleware
//  at _core/trpc.ts:386, which every isolatedProcedure carries by construction.
//
//  OFFLINE (§W) — reads READ_CACHED(120s) via EscortOfflineCache (key
//  escort.notifications.inbox) with a visible staleness line. Mutations
//  (markAllRead / snooze / archive) are ONLINE_ONLY: there is no escort outbox on the
//  phone (EscortOfflineCache is a read cache only; the outbox is PLANNED per
//  Encyclopedia v2) and a queue badge is NEVER drawn. The eight broken paths are STATIC
//  STRUCTURE, not data — they render identically online and offline and are never
//  stamped cached, because a wiring fact does not go stale.
//
//  HONESTY — when the inbox comes back empty this screen does NOT say "you have no
//  alerts". The truthful statement is "alerts fired and were never stored", and that is
//  what it prints, because on a superload the difference between those two sentences is
//  a missed LEO no-show on a live interstate.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Lenient scalars
//
// `count(*)` comes back through drizzle/mysql2 as a JSON number today, and MySQL
// booleans arrive as either `true/false` or `0/1` depending on the driver path a
// given procedure took. Three escort screens have already shipped permanently empty
// because a decode threw on exactly this. Decode both shapes, never guess.

/// Int that also accepts a JSON string or a JSON bool on the wire.
struct ES31FlexInt: Codable, Hashable {
    let value: Int
    init(_ v: Int) { value = v }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { value = i; return }
        if let d = try? c.decode(Double.self) { value = Int(d); return }
        if let s = try? c.decode(String.self), let i = Int(s) { value = i; return }
        if let b = try? c.decode(Bool.self) { value = b ? 1 : 0; return }
        throw DecodingError.typeMismatch(
            Int.self,
            .init(codingPath: decoder.codingPath, debugDescription: "not an integer-ish value"))
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(value)
    }
}

/// Bool that also accepts 0/1 or "0"/"1"/"true"/"false".
struct ES31FlexBool: Codable, Hashable {
    let value: Bool
    init(_ v: Bool) { value = v }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { value = b; return }
        if let i = try? c.decode(Int.self) { value = i != 0; return }
        if let s = try? c.decode(String.self) {
            value = (s == "1" || s.lowercased() == "true"); return
        }
        throw DecodingError.typeMismatch(
            Bool.self,
            .init(codingPath: decoder.codingPath, debugDescription: "not a boolean-ish value"))
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(value)
    }
}

// MARK: - Wire contracts (mirror server/routers/notifications.ts)

/// One row of `notifications.list`, formatted server-side at notifications.ts:113-139.
/// `metadata` is arbitrary JSON and is deliberately NOT modelled — nothing on this
/// surface reads it, so nothing on this surface can be broken by its shape.
struct ES31InboxRow: Codable, Identifiable, Hashable {
    let id: String
    let type: String
    let category: String?
    let title: String
    let message: String?
    let createdAt: String?
    let timeAgo: String?
    let isRead: ES31FlexBool

    var unread: Bool { !isRead.value }
}

/// `notifications.list` envelope (notifications.ts:141-145).
struct ES31InboxPage: Codable, Hashable {
    let notifications: [ES31InboxRow]
    let total: ES31FlexInt
    let hasMore: Bool
}

/// `notifications.list` input (notifications.ts:67-74). `byCategory` is never sent
/// because the server hard-zeroes it at :54.
struct ES31ListInput: Encodable {
    var read: Bool?
    var archived: Bool = false
    var limit: Int = 25
    var offset: Int = 0
}

/// `notifications.getSummary` (notifications.ts:37). Only the three counters that are
/// really computed (:45-47) are modelled; `byCategory` is hard-zero at :54 and is
/// deliberately unmodelled so it can never be rendered as data.
struct ES31Summary: Codable, Hashable {
    let total: ES31FlexInt
    let unread: ES31FlexInt
}

/// `notifications.markAllRead` (notifications.ts:500-525).
struct ES31MarkAllInput: Encodable { var channel: String? = nil }
struct ES31MarkAllResult: Codable, Hashable {
    let success: Bool
    let markedCount: ES31FlexInt
}

/// The READ_CACHED(120s) disk snapshot.
struct ES31Snapshot: Codable {
    var summary: ES31Summary
    var rows: [ES31InboxRow]
}

// MARK: - The delivery-path model (STATIC STRUCTURE, not data)
//
// These nine rows are a census of the wiring, taken by grep against the live tree.
// They are code truth, not server truth: they do not load, do not cache, do not go
// stale and are never stamped CACHED. Changing them requires changing the tree.

enum ES31Station: Int, CaseIterable {
    case emit = 0, channel = 1, client = 2, inbox = 3
    var label: String {
        switch self {
        case .emit:    return "EMIT"
        case .channel: return "CHANNEL"
        case .client:  return "CLIENT"
        case .inbox:   return "INBOX"
        }
    }
}

struct ES31Path: Identifiable, Hashable {
    let id: String
    /// Nil means the path completes end to end.
    let diesAt: ES31Station?
    /// Emit-side evidence, file:line.
    let evidence: String
    /// The exact missing symbol, or the reason the terminal is not a stored row.
    let missing: String
}

enum ES31Census {
    /// Twelve escort-domain realtime events fire (shared/websocket-events.ts:245-297).
    static let eventsThatFire = 12
    /// Four of them have an iOS switch case (RealtimeService.swift:499-508).
    static let eventsThatArrive = 4
    /// None of them persists a row (grep escorts.ts -> 0 / 4745).
    static let eventsThatPersist = 0

    /// The one path that runs all four stations whole.
    static let completeLane = ES31Path(
        id: "GENERIC NOTIFICATION LANE",
        diesAt: nil,
        evidence: "createNotification.ts:34 · websocket.ts:768 · RTS.swift:253 · notifications.ts:66",
        missing: "")

    /// The eight that do not, ordered by how far the wire gets before it breaks.
    static let brokenPaths: [ES31Path] = [
        ES31Path(id: "CERT EXPIRY", diesAt: .emit,
                 evidence: "escort_certifications.expirationDate is pull-only via getCertificationStats:2485",
                 missing: "MISSING: any scanner — grep escortCertifications outside escorts.ts = 0"),
        ES31Path(id: "LEO RELAY x4", diesAt: .channel,
                 evidence: "emit escorts.ts:124 no_show · :1725 on_scene · :1801 handoff · :1847 incoming_eta",
                 missing: "MISSING: WS_CHANNELS.USER(escortUserId) — only DISPATCH + LOAD"),
        ES31Path(id: "CHECK+SURVEY", diesAt: .channel,
                 evidence: "emit escorts.ts:1297 submitVehicleCheck · escorts.ts:1531 completeRouteSurvey",
                 missing: "MISSING: USER() fan-out — LOAD:1301, DISPATCH only if !passed:1305"),
        ES31Path(id: "JOB AVAILABLE", diesAt: .client,
                 evidence: "emit escorts.ts:624 · role:escort auto-joined socketService.ts:205, emitted :766",
                 missing: "MISSING: case \"escort:job_available\" RealtimeService.swift:499"),
        ES31Path(id: "CERT UPLOAD", diesAt: .client,
                 evidence: "emit escorts.ts:2590 to WS_CHANNELS.USER(userId) :2589 — the frame reaches the device",
                 missing: "MISSING: ESCORT_CERT_UPLOADED case — iOS 0 hits, web 0 hits"),
        ES31Path(id: "LEO RESOLVED", diesAt: .client,
                 evidence: "emit escorts.ts:1894 to USER(escortUserId) :1901 — the one LEO event addressed to you",
                 missing: "MISSING: escort:leo_no_show_resolved case — iOS 0, web 0"),
        ES31Path(id: "JOB LIFECYCLE", diesAt: .inbox,
                 evidence: "applied escorts.ts:915 · assigned/started/completed websocket.ts:1078/1115/1150",
                 missing: "RealtimeService.swift:499-508 refreshes only — no row, no history"),
        ES31Path(id: "CONVOY ALERT", diesAt: .inbox,
                 evidence: "emit escorts.ts:4524-4549 to USER(each convoy member) · iOS case :509-520 fires",
                 missing: "posts .eusoNotificationReceived — transient toast, nothing persists"),
    ]
}

// MARK: - Service seam
//
// One protocol, one live implementation. Errors are THROWN, never `try?`-swallowed:
// a swallowed decode is how two escort screens shipped permanently empty.

protocol ES31InboxService {
    func summary() async throws -> ES31Summary
    func page(unreadOnly: Bool) async throws -> ES31InboxPage
    func markAllRead() async throws -> ES31MarkAllResult
}

struct ES31LiveInboxService: ES31InboxService {
    func summary() async throws -> ES31Summary {
        try await EusoTripAPI.shared.queryNoInput("notifications.getSummary")
    }
    func page(unreadOnly: Bool) async throws -> ES31InboxPage {
        try await EusoTripAPI.shared.query(
            "notifications.list",
            input: ES31ListInput(read: unreadOnly ? false : nil))
    }
    func markAllRead() async throws -> ES31MarkAllResult {
        try await EusoTripAPI.shared.mutation(
            "notifications.markAllRead", input: ES31MarkAllInput())
    }
}

// MARK: - Screen

struct EscortNotificationsAlerts: View {
    @Environment(\.palette) private var palette

    let service: any ES31InboxService

    init(service: any ES31InboxService = ES31LiveInboxService()) {
        self.service = service
    }

    private static let cacheKey = "escort.notifications.inbox"
    private static let cacheTTL: TimeInterval = 120

    private enum Phase { case loading, loaded, failed }

    @State private var phase: Phase = .loading
    @State private var summary: ES31Summary?
    @State private var rows: [ES31InboxRow] = []
    @State private var unreadOnly = false
    @State private var stalenessLine: String?
    @State private var errorMessage: String?
    @State private var writeError: String?
    @State private var isMarking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            metaRow.padding(.top, 12)
            completeLaneSection.padding(.top, 20)
            brokenBoardSection.padding(.top, 22)
            honestyLines.padding(.top, 14)
            ctaRow.padding(.top, 10)
        }
        .padding(.horizontal, Space.s4)
        .padding(.top, 18)
        .task { await load() }
        .eusoRefreshable { await load(force: true) }
    }

    // MARK: Header — HOME/LIST ramp: H1 34 · subline 12 · hairline

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                EusoTripEyebrow(verbatim: "ESCORT · NOTIFICATIONS & ALERTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: 8)
                Text("EASTBOUND ESCORT LLC")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            // The ratio is a WIRING CENSUS, not server data — it describes the
            // delivery system, which is code truth. It never loads and never caches.
            Text("\(ES31Census.eventsThatArrive) of \(ES31Census.eventsThatFire) arrive")
                .font(.system(size: 34, weight: .bold)).tracking(-0.6)
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 22)
            Text("\(ES31Census.eventsThatFire) escort events fire · \(ES31Census.eventsThatArrive) reach the phone · \(ES31Census.eventsThatPersist) of \(ES31Census.eventsThatFire) are stored")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 6)
            palette.iridescentHairline
                .frame(height: 1)
                .padding(.top, 14)
        }
    }

    // MARK: Meta row — sits BELOW the hairline so the ramp stays 34/138/158

    private var metaRow: some View {
        HStack(spacing: 8) {
            chip("READER LIVE", tint: Brand.success)
            chip("WRITER ABSENT", tint: Brand.danger)
            Spacer(minLength: 6)
            Text("JORDAN ESCOTO · LEAD")
                .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(0.2)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy)).tracking(0.5)
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.14)))
    }

    // MARK: The one lane that completes — the ActiveCard (rimmed, max one per screen)

    private var completeLaneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("THE ONE LANE THAT COMPLETES", trailing: readerTag,
                          trailingTint: summary == nil ? Brand.danger : palette.textTertiary)
            activeCard
        }
    }

    private var readerTag: String {
        if let s = summary { return "\(s.unread.value) UNREAD · \(s.total.value) ON FILE" }
        if phase == .failed { return "INBOX UNREACHABLE" }
        return "READING…"
    }

    private var activeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Generic notification lane")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 8)
                Text("COMPLETE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.success)
            }
            stationRuler.padding(.top, 12)
            ES31TrackView(diesAt: nil, palette: palette)
                .frame(height: 20)
                .padding(.top, 2)
            HStack(spacing: 0) {
                captionCell("createNotification.ts:34")
                captionCell("USER_NOTIFICATIONS")
                captionCell("RTS.swift:253")
                captionCell("notifications:66")
            }
            .padding(.top, 2)

            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.top, 10)

            terminal.padding(.top, 10)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                .fill(palette.bgCard))
        .padding(1.5)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(
                    colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)))
    }

    /// The terminal of the completing path: real rows, or the honest reason there are
    /// none. NEVER "you have no alerts" — the truthful statement is that alerts fired
    /// and were never stored.
    @ViewBuilder private var terminal: some View {
        switch phase {
        case .loading:
            Text("READING INBOX…")
                .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 40)
        case .failed:
            VStack(alignment: .leading, spacing: 4) {
                Text("INBOX UNREACHABLE")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.danger)
                Text(errorMessage ?? "Notifications couldn't be loaded. Pull to retry.")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .loaded:
            if rows.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(unreadOnly ? "NO UNREAD ROW ON FILE" : "NO ROW ON FILE")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("No notification records are available. This does not confirm that no escort events occurred.")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.prefix(3).enumerated()), id: \.element.id) { idx, row in
                        if idx > 0 { Rectangle().fill(palette.borderFaint).frame(height: 1) }
                        inboxRow(row)
                    }
                }
                if let stalenessLine {
                    Text(stalenessLine.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(0.4)
                        .foregroundStyle(Brand.warning)
                        .padding(.top, 6)
                }
            }
        }
    }

    /// Canon ListRow anatomy: 40×40 rx10 icon chip · 12pt gutter · title 14/700 ·
    /// mono sub 11 · trailing tag 11/700 · trailing value 14/700 tabular.
    private func inboxRow(_ row: ES31InboxRow) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Brand.info.opacity(0.16))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: glyph(for: row.type))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Brand.info))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("type=\(row.type)\(row.category.map { " · \($0)" } ?? "")")
                    .font(.system(size: 11, design: .monospaced)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.unread ? "UNREAD" : "READ")
                    .font(.system(size: 11, weight: .bold)).tracking(0.6)
                    .foregroundStyle(row.unread ? AnyShapeStyle(LinearGradient.primary)
                                                : AnyShapeStyle(palette.textTertiary))
                // timeAgo is computed server-side (notifications.ts:121) — never
                // synthesized here. When the server omits it, nothing is drawn.
                if let ago = row.timeAgo, !ago.isEmpty {
                    Text(ago)
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func glyph(for type: String) -> String {
        switch type {
        case "message":             return "envelope"
        case "compliance_expiring": return "checkmark.seal"
        case "payment_received":    return "dollarsign.circle"
        case "geofence_alert",
             "weather_alert":       return "exclamationmark.triangle"
        default:                    return "bell"
        }
    }

    // MARK: The board of paths that die

    private var brokenBoardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("PATHS THAT DIE · 8 CLASSES · 12 EVENTS",
                          trailing: "RED CUT = WHERE IT DIES",
                          trailingTint: Brand.danger)
            VStack(alignment: .leading, spacing: 0) {
                stationRuler
                ForEach(Array(ES31Census.brokenPaths.enumerated()), id: \.element.id) { idx, path in
                    brokenBand(path).padding(.top, idx == 0 ? 12 : 14)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.bgCard))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        }
    }

    private func brokenBand(_ path: ES31Path) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(path.id)
                    .font(.system(size: 8.5, weight: .heavy)).tracking(0.15)
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 78, alignment: .leading)
                ES31TrackView(diesAt: path.diesAt, palette: palette)
                    .frame(height: 18)
            }
            Text(path.evidence)
                .font(.system(size: 7.5, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("DIES AT \(path.diesAt?.label ?? "—") · \(path.missing)")
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundStyle(Brand.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stationRuler: some View {
        HStack(spacing: 0) {
            ForEach(ES31Station.allCases, id: \.rawValue) { st in
                Text(st.label)
                    .font(.system(size: 7.5, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func captionCell(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 6.5, design: .monospaced))
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
    }

    private func sectionHeader(_ title: String, trailing: String,
                               trailingTint: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: 8)
            Text(trailing)
                .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                .foregroundStyle(trailingTint)
        }
    }

    // MARK: Honesty + CTA

    private var honestyLines: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("ONLY SAVED NOTIFICATIONS APPEAR HERE · UNSAVED ESCORT EVENTS ARE NOT SHOWN")
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            Text("CHANGES REQUIRE A CONNECTION · FAILED UPDATES ARE NOT QUEUED")
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
            if let writeError {
                Text(writeError.uppercased())
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Brand.danger)
            }
        }
        .foregroundStyle(palette.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var ctaRow: some View {
        HStack(spacing: 8) {
            Button {
                Task { await markAllRead() }
            } label: {
                Text(isMarking ? "MARKING…" : "MARK ALL READ")
                    .font(.system(size: 12, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity).frame(height: 42)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .disabled(isMarking || (summary?.unread.value ?? 0) == 0)
            .opacity(isMarking || (summary?.unread.value ?? 0) == 0 ? 0.45 : 1)

            Button {
                unreadOnly.toggle()
                Task { await load(force: true) }
            } label: {
                Text(unreadOnly ? "ALL ROWS" : "UNREAD ONLY")
                    .font(.system(size: 11.5, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 144).frame(height: 42)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(palette.borderSoft, lineWidth: 1.5))
            }
        }
    }

    // MARK: Data — READ_CACHED(120s) reads, ONLINE_ONLY writes, nothing swallowed

    private func load(force: Bool = false) async {
        if !force, unreadOnly == false,
           let cached = EscortOfflineCache.load(ES31Snapshot.self,
                                                key: Self.cacheKey, ttl: Self.cacheTTL) {
            summary = cached.value.summary
            rows = cached.value.rows
            stalenessLine = EscortOfflineCache.stalenessLine(age: cached.age)
            phase = .loaded
        }

        do {
            let loadedSummary = try await service.summary()
            let loadedPage = try await service.page(unreadOnly: unreadOnly)

            summary = loadedSummary
            rows = loadedPage.notifications
            stalenessLine = nil          // a live read is on glass now
            errorMessage = nil
            phase = .loaded

            // Only the unfiltered view seeds the cache, so a filtered page can never
            // be replayed offline as if it were the whole inbox.
            if !unreadOnly {
                EscortOfflineCache.store(
                    ES31Snapshot(summary: loadedSummary, rows: loadedPage.notifications),
                    key: Self.cacheKey)
            }
        } catch {
            // Never swallowed. If a snapshot is already on glass it stays, still
            // wearing its staleness line; otherwise the screen says so out loud.
            errorMessage = "Notifications couldn't be loaded. Check your connection and pull to retry."
            if summary == nil { phase = .failed }
        }
    }

    /// ONLINE_ONLY. There is no escort outbox, so a failure is reported, never queued
    /// and never badged.
    private func markAllRead() async {
        guard !isMarking else { return }
        isMarking = true
        writeError = nil
        defer { isMarking = false }
        do {
            let result = try await service.markAllRead()
            guard result.success else {
                writeError = "Notifications weren't marked as read. Nothing changed; try again."
                return
            }
            await load(force: true)
        } catch {
            writeError = "Notifications couldn't be marked as read. Check your connection and try again."
        }
    }
}

// MARK: - The track
//
// One horizontal path against the shared four-station ruler. `diesAt == nil` draws it
// whole in the brand gradient and terminates in a ring; otherwise it draws solid to the
// death station, cuts it with the red break glyph, and continues dead-dashed to the end
// with every unreached station drawn hollow.

struct ES31TrackView: View {
    let diesAt: ES31Station?
    let palette: Theme.Palette

    var body: some View {
        Canvas { ctx, size in
            let leadIn: CGFloat = 14
            let y = size.height / 2
            let span = size.width - leadIn
            func sx(_ i: Int) -> CGFloat { leadIn + span * CGFloat(i) / 3.0 }

            let live = palette.textSecondary
            let dead = palette.textTertiary

            guard let die = diesAt else {
                var whole = Path()
                whole.move(to: CGPoint(x: 0, y: y))
                whole.addLine(to: CGPoint(x: sx(3), y: y))
                ctx.stroke(whole,
                           with: .linearGradient(Gradient(colors: [Brand.blue, Brand.magenta]),
                                                 startPoint: CGPoint(x: 0, y: y),
                                                 endPoint: CGPoint(x: size.width, y: y)),
                           style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                for i in 0..<3 {
                    ctx.fill(Path(ellipseIn: CGRect(x: sx(i) - 4.5, y: y - 4.5,
                                                    width: 9, height: 9)),
                             with: .color(Brand.blue))
                }
                let ring = CGRect(x: sx(3) - 6.5, y: y - 6.5, width: 13, height: 13)
                ctx.stroke(Path(ellipseIn: ring), with: .color(Brand.magenta), lineWidth: 2)
                ctx.fill(Path(ellipseIn: CGRect(x: sx(3) - 2.6, y: y - 2.6,
                                                width: 5.2, height: 5.2)),
                         with: .color(Brand.magenta))
                return
            }

            let dieX = sx(die.rawValue)

            // Solid run: origin -> just short of the cut.
            var solid = Path()
            solid.move(to: CGPoint(x: 0, y: y))
            solid.addLine(to: CGPoint(x: max(0, dieX - 9), y: y))
            ctx.stroke(solid, with: .color(live),
                       style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

            for i in 0..<4 where sx(i) < dieX - 1 {
                ctx.fill(Path(ellipseIn: CGRect(x: sx(i) - 4, y: y - 4, width: 8, height: 8)),
                         with: .color(live))
            }

            // The cut: halo + severed end-cap + the two-slash break glyph.
            ctx.fill(Path(ellipseIn: CGRect(x: dieX - 9.5, y: y - 9.5, width: 19, height: 19)),
                     with: .color(Brand.danger.opacity(0.13)))
            var cap = Path()
            cap.move(to: CGPoint(x: dieX - 9, y: y - 3.5))
            cap.addLine(to: CGPoint(x: dieX - 9, y: y + 3.5))
            ctx.stroke(cap, with: .color(Brand.danger),
                       style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            var slash = Path()
            slash.move(to: CGPoint(x: dieX - 5.5, y: y + 6.5))
            slash.addLine(to: CGPoint(x: dieX - 1, y: y - 6.5))
            slash.move(to: CGPoint(x: dieX + 1.5, y: y + 6.5))
            slash.addLine(to: CGPoint(x: dieX + 6, y: y - 6.5))
            ctx.stroke(slash, with: .color(Brand.danger),
                       style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

            // Dead continuation.
            if dieX < sx(3) - 1 {
                var ghost = Path()
                ghost.move(to: CGPoint(x: dieX + 10, y: y))
                ghost.addLine(to: CGPoint(x: sx(3), y: y))
                ctx.stroke(ghost, with: .color(dead),
                           style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                for i in 0..<4 where sx(i) > dieX + 1 {
                    ctx.stroke(Path(ellipseIn: CGRect(x: sx(i) - 3.5, y: y - 3.5,
                                                      width: 7, height: 7)),
                               with: .color(dead), lineWidth: 1)
                }
            }
        }
    }
}

// MARK: - Registered surface wrapper

struct EscortNotificationsAlertsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            EscortNotificationsAlerts()
        } nav: {
            // The escort notifications hub lives under ME — RealtimeService.swift:250-252
            // routes .eusoNotificationReceived to the "Me > Notifications hub".
            // EscortNavController.swift is a single-writer file and is NOT edited here.
            BottomNav(
                leading: EscortNavRoute.leading(current: .me),
                trailing: EscortNavRoute.trailing(current: .me),
                orbState: .idle
            )
        }
    }
}

// MARK: - Fixtures + previews (DEBUG only)

#if DEBUG
struct ES31PreviewService: ES31InboxService {
    var rows: [ES31InboxRow]
    var unread: Int
    var throwsOnRead = false

    func summary() async throws -> ES31Summary {
        if throwsOnRead { throw URLError(.notConnectedToInternet) }
        return ES31Summary(total: ES31FlexInt(rows.count), unread: ES31FlexInt(unread))
    }
    func page(unreadOnly: Bool) async throws -> ES31InboxPage {
        if throwsOnRead { throw URLError(.notConnectedToInternet) }
        let filtered = unreadOnly ? rows.filter { $0.unread } : rows
        return ES31InboxPage(notifications: filtered,
                             total: ES31FlexInt(filtered.count),
                             hasMore: false)
    }
    func markAllRead() async throws -> ES31MarkAllResult {
        ES31MarkAllResult(success: true, markedCount: ES31FlexInt(unread))
    }

    static let populated = ES31PreviewService(
        rows: [
            ES31InboxRow(id: "9041", type: "message", category: "system",
                         title: "New message from Dispatch",
                         message: "Hold at MP 88 until the LEO unit clears.",
                         createdAt: "2026-08-17T14:39:00.000Z", timeAgo: "2m ago",
                         isRead: ES31FlexBool(false)),
            ES31InboxRow(id: "9038", type: "compliance_expiring", category: "compliance",
                         title: "Certification Renewed",
                         message: "Your TX P/EVO expires in 26 days",
                         createdAt: "2026-08-17T11:02:00.000Z", timeAgo: "5h ago",
                         isRead: ES31FlexBool(false)),
        ],
        unread: 2)

    /// The state the tree is actually in for an escort today: the reader answers and
    /// there is nothing in it, because nothing writes.
    static let empty = ES31PreviewService(rows: [], unread: 0)
    static let offline = ES31PreviewService(rows: [], unread: 0, throwsOnRead: true)
}

#Preview("ES-31 · Notifications & Alerts · Light") {
    EscortNotificationsAlertsScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}

#Preview("ES-31 · Notifications & Alerts · Dark") {
    EscortNotificationsAlertsScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("ES-31 · empty inbox (the honest today) · Light") {
    Shell(theme: Theme.light) {
        EscortNotificationsAlerts(service: ES31PreviewService.empty)
    } nav: {
        BottomNav(leading: EscortNavRoute.leading(current: .me),
                  trailing: EscortNavRoute.trailing(current: .me),
                  orbState: .idle)
    }
    .preferredColorScheme(.light)
}

#Preview("ES-31 · reader unreachable · Dark") {
    Shell(theme: Theme.dark) {
        EscortNotificationsAlerts(service: ES31PreviewService.offline)
    } nav: {
        BottomNav(leading: EscortNavRoute.leading(current: .me),
                  trailing: EscortNavRoute.trailing(current: .me),
                  orbState: .idle)
    }
    .preferredColorScheme(.dark)
}
#endif
