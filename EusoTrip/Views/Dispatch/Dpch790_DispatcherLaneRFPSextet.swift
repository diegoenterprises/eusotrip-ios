//
//  Dpch790_DispatcherLaneRFPSextet.swift
//  EusoTrip — Dispatcher · Lane + RFP + Contract sextet (508-513).
//
//  Pixel-match to:
//    508 Dispatcher Lane Board
//    509 Dispatcher Lane Drill
//    510 Dispatcher Haul Detail
//    511 Dispatcher RFP Tender Inbox
//    512 Dispatcher Catalyst Catalog Match Up
//    513 Dispatcher Contract Write Surface
//
//  All 6 share `DispatcherLaneRFPBody`. Zero-fallback wiring (2026-06-09,
//  audit B23): identity binds to the live session user + the tenant's
//  `companies.getProfile` row (name / USDOT / MC); every KPI tile derives
//  from `dispatchRole.getDispatchBoard` aggregates (lanes, hauls,
//  in-transit, unassigned), `dispatch.getPendingTenders` (inbox count) or
//  `dispatch.getAvailableDrivers` (match candidates). Tiles with no live
//  proc behind them render an honest em-dash — never an invented dollar.
//  The fetched board loads render in the LIVE LOADS card. Bottom nav
//  frozen (Dispatcher: Home / Board / ESANG / Me).
//

import SwiftUI

private struct DLRLoad: Decodable, Hashable {
    let id: String
    let loadNumber: String?
    let status: String?
    let shipper: String?
    let origin: String?
    let destination: String?
    let rate: Double?
    let pickupDate: String?
}

private struct DLRBoard: Decodable, Hashable {
    let loads: [DLRLoad]?
    let summary: Summary?
    struct Summary: Decodable, Hashable {
        let total: Int?
        let byStatus: ByStatus?
        struct ByStatus: Decodable, Hashable {
            let unassigned: Int?
            let inTransit: Int?
            let loading: Int?
        }
    }
}

/// Live tenant identity — `companies.getProfile` resolves the session
/// user's company server-side (auto-creates when missing). Tolerant:
/// every field optional so partial rows never kill the decode.
private struct DLRCompany: Decodable, Hashable {
    let name: String?
    let dotNumber: String?
    let mcNumber: String?
}

/// Minimal tender row — only the count feeds the §511 inbox KPI.
private struct DLRTender: Decodable, Hashable {
    let id: TolerantID?
    struct TolerantID: Decodable, Hashable {
        let raw: String
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let i = try? c.decode(Int.self) { raw = String(i) }
            else { raw = (try? c.decode(String.self)) ?? "" }
        }
    }
}
private struct DLRTendersEnvelope: Decodable {
    let tenders: [DLRTender]?
    let items: [DLRTender]?
    var rows: [DLRTender] { tenders ?? items ?? [] }
}

/// Minimal available-driver row — only the count feeds the §512 KPI.
private struct DLRDriver: Decodable, Hashable {
    let id: String
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let i = try? c.decode(Int.self, forKey: .id) { id = String(i) }
        else { id = "" }
    }
    enum CodingKeys: String, CodingKey { case id }
}

enum DispatcherLaneRFPKind: String {
    case laneBoard, laneDrill, haulDetail, rfpInbox, matchUp, contractWrite
}

private struct DLRConfig {
    let eyebrow: String
    let citation: String
    let title: String
}

private extension DispatcherLaneRFPKind {
    var config: DLRConfig {
        switch self {
        case .laneBoard:
            return .init(eyebrow: "DISPATCHER · BOARD · LANES",
                         citation: "DISPATCHER LANE BOARD · §508",
                         title: "Lane board")
        case .laneDrill:
            return .init(eyebrow: "DISPATCHER · BOARD · LANE DRILL",
                         citation: "DISPATCHER LANE DRILL · §509",
                         title: "Lane drill")
        case .haulDetail:
            return .init(eyebrow: "DISPATCHER · BOARD · HAUL DETAIL",
                         citation: "DISPATCHER HAUL DETAIL · §510",
                         title: "Haul detail")
        case .rfpInbox:
            return .init(eyebrow: "DISPATCHER · BOARD · INBOX",
                         citation: "DISPATCHER INBOX · §511",
                         title: "RFP inbox")
        case .matchUp:
            return .init(eyebrow: "DISPATCHER · BOARD · MATCH",
                         citation: "DISPATCHER MATCH UP · §512",
                         title: "Match capacity")
        case .contractWrite:
            return .init(eyebrow: "DISPATCHER · BOARD · CONTRACT · WRITE",
                         citation: "DISPATCHER CONTRACT WRITE · §513",
                         title: "Write counter")
        }
    }
}

private struct DispatcherLaneRFPShell<Content: View>: View {
    let theme: Theme.Palette
    let content: () -> Content
    var body: some View {
        Shell(theme: theme) { content() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Board", systemImage: "rectangle.stack.fill", isCurrent: true)],
                trailing: [NavSlot(label: "ESANG", systemImage: "sparkles", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",   isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct DispatcherLaneRFPBody: View {
    let kind: DispatcherLaneRFPKind

    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession
    @State private var board: DLRBoard?
    @State private var company: DLRCompany?
    @State private var tenderCount: Int?
    @State private var candidateCount: Int?

    // MARK: - Live derivations (board aggregates only — no invented values)

    private var liveLoads: [DLRLoad] { board?.loads ?? [] }

    private var laneGroups: [(lane: String, count: Int)] {
        let pairs = liveLoads.map { "\($0.origin ?? "—") → \($0.destination ?? "—")" }
        return Dictionary(grouping: pairs, by: { $0 })
            .map { (lane: $0.key, count: $0.value.count) }
            .sorted { $0.count == $1.count ? $0.lane < $1.lane : $0.count > $1.count }
    }
    private var topLane: (lane: String, count: Int)? { laneGroups.first }
    private var focusLoad: DLRLoad? {
        liveLoads.first(where: { ($0.status ?? "").lowercased().contains("transit") }) ?? liveLoads.first
    }
    private var totalStr: String { (board?.summary?.total).map(String.init) ?? "—" }
    private var lanesStr: String { board == nil ? "—" : String(laneGroups.count) }
    private var inTransitStr: String { (board?.summary?.byStatus?.inTransit).map(String.init) ?? "—" }
    private var unassignedStr: String { (board?.summary?.byStatus?.unassigned).map(String.init) ?? "—" }
    private var loadingStr: String { (board?.summary?.byStatus?.loading).map(String.init) ?? "—" }

    private func money(_ v: Double?) -> String {
        guard let v else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: v.rounded())) ?? String(Int(v.rounded())))
    }

    var body: some View {
        let c = kind.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header(c)
                pill(c)
                chainPill
                identityRow
                kpiGrid
                liveLoadsCard
                nextStepCard
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func header(_ c: DLRConfig) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(c.eyebrow).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(c.title).font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text(subhead).font(EType.caption).foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.72)
        }
    }

    private var subhead: String {
        switch kind {
        case .laneBoard:
            return "LANES \(lanesStr) · HAULS \(totalStr) · IN TRANSIT \(inTransitStr)"
        case .laneDrill:
            if let t = topLane { return "TOP LANE \(t.count) HAULS · LIVE \(totalStr)" }
            return board == nil ? "LIVE BOARD —" : "NO LANES LIVE"
        case .haulDetail:
            if let l = focusLoad { return "\(l.loadNumber ?? l.id) · \((l.status ?? "—").uppercased())" }
            return board == nil ? "LIVE BOARD —" : "NO LIVE HAUL"
        case .rfpInbox:
            return "INBOX \(tenderCount.map(String.init) ?? "—") · HAULS \(totalStr)"
        case .matchUp:
            return "CAND \(candidateCount.map(String.init) ?? "—") · UNASSIGNED \(unassignedStr)"
        case .contractWrite:
            return "COUNTER — · HAULS \(totalStr)"
        }
    }

    private func pill(_ c: DLRConfig) -> some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text(c.citation).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(pillCopy).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var pillCopy: String {
        guard let s = board?.summary else {
            return "Live board unreachable — pull to refresh."
        }
        let total = s.total ?? liveLoads.count
        switch kind {
        case .laneBoard:
            return "\(total) live hauls across \(laneGroups.count) lanes · \(s.byStatus?.inTransit ?? 0) in transit."
        case .laneDrill:
            if let t = topLane { return "Top lane \(t.lane) · \(t.count) hauls live." }
            return "No live lanes on the board."
        case .haulDetail:
            if let l = focusLoad {
                return "\(l.loadNumber ?? l.id) · \(l.origin ?? "—") → \(l.destination ?? "—") · \((l.status ?? "—").replacingOccurrences(of: "_", with: " "))."
            }
            return "No live haul to drill."
        case .rfpInbox:
            if let n = tenderCount { return "\(n) pending tenders in the inbox." }
            return "Tender inbox unreachable — count em-dash until it answers."
        case .matchUp:
            if let n = candidateCount { return "\(n) drivers available to match · \(s.byStatus?.unassigned ?? 0) unassigned loads." }
            return "Driver pool unreachable — candidate count em-dash until it answers."
        case .contractWrite:
            return "No live RFP under counter — terms surface when a tender opens."
        }
    }

    private var chainPill: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("CHAIN CONTEXT").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(chainCopy).font(.caption2).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var chainCopy: String {
        let org = (company?.name?.isEmpty == false) ? company!.name! : "—"
        return "\(org) · \(totalStr) active hauls across \(lanesStr) lanes"
    }

    private var identityRow: some View {
        let userName = session.user?.name
        let roleLabel = (session.user?.role ?? "DISPATCHER").replacingOccurrences(of: "_", with: " ").lowercased()
        let orgName = (company?.name?.isEmpty == false) ? company!.name! : nil
        let usdot = (company?.dotNumber?.isEmpty == false) ? company!.dotNumber! : "—"
        let mc = (company?.mcNumber?.isEmpty == false) ? company!.mcNumber! : "—"
        let initials: String = {
            let parts = (userName ?? "").split(separator: " ").prefix(2).compactMap { $0.first }
            return parts.isEmpty ? "?" : String(parts).uppercased()
        }()
        return LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(initials).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(orgName ?? "—") · \(userName ?? "—") · \(roleLabel)")
                        .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.72)
                    Text("USDOT \(usdot) · MC \(mc) · LIVE \(totalStr) hauls")
                        .font(.caption2).foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.72)
                }
                Spacer()
            }
        }
    }

    private var kpiGrid: some View {
        let kpis: [(String, String, String, Color)] = {
            switch kind {
            case .laneBoard:
                return [
                    ("LANES",      lanesStr,      "live corridors", .blue),
                    ("HAULS",      totalStr,      "active · live",  .blue),
                    ("IN TRANSIT", inTransitStr,  "rolling now",    .green),
                    ("UNASSIGNED", unassignedStr, "need cover",     .orange),
                ]
            case .laneDrill:
                return [
                    ("TOP LANE",   topLane.map { String($0.count) } ?? "—",
                                   topLane?.lane ?? "no lanes live", .blue),
                    ("LANES",      lanesStr,      "live corridors", .blue),
                    ("IN TRANSIT", inTransitStr,  "rolling now",    .green),
                    ("LOADING",    loadingStr,    "at dock",        .orange),
                ]
            case .haulDetail:
                return [
                    ("RATE",   money(focusLoad?.rate),
                               focusLoad?.loadNumber ?? "no live haul", .green),
                    ("STATUS", (focusLoad?.status ?? "—").replacingOccurrences(of: "_", with: " ").uppercased(),
                               "live state", .blue),
                    ("PICKUP", focusLoad?.pickupDate?.isEmpty == false ? focusLoad!.pickupDate! : "—",
                               "scheduled", .orange),
                    ("HAULS",  totalStr, "on board", .blue),
                ]
            case .rfpInbox:
                return [
                    ("INBOX",      tenderCount.map(String.init) ?? "—", "pending tenders", .blue),
                    ("UNASSIGNED", unassignedStr, "need cover",     .orange),
                    ("BOOK",       "—", "no live source", .green),
                    ("HIT-RATE",   "—", "no live source", .green),
                ]
            case .matchUp:
                return [
                    ("CAND",       candidateCount.map(String.init) ?? "—", "available drivers", .blue),
                    ("UNASSIGNED", unassignedStr, "need cover",     .orange),
                    ("BEST",       "—", "no live source", .green),
                    ("RFP",        "—", "no live source", .blue),
                ]
            case .contractWrite:
                return [
                    ("COUNTER", "—", "no live source", .green),
                    ("DELTA",   "—", "no live source", .green),
                    ("TIMER",   "—", "no live source", .orange),
                    ("TERMS",   "—", "no live source", .blue),
                ]
            }
        }()
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(kpis.enumerated()), id: \.offset) { _, k in
                VStack(alignment: .leading, spacing: 4) {
                    Text(k.0).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text(k.1).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(k.3)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(k.2).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(k.3.opacity(0.3)))
            }
        }
    }

    /// The fetched board loads, rendered (audit B23: "the fetched loads
    /// are never rendered"). Honest empty line when the board is empty
    /// or unreachable.
    private var liveLoadsCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("LIVE LOADS · BOARD").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                if liveLoads.isEmpty {
                    Text(board == nil ? "Live board unreachable — pull to refresh."
                                      : "No live loads on the board.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                } else {
                    ForEach(Array(liveLoads.prefix(6)), id: \.id) { l in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l.loadNumber ?? l.id)
                                    .font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                                    .lineLimit(1).minimumScaleFactor(0.72)
                                Text("\(l.origin ?? "—") → \(l.destination ?? "—") · \((l.status ?? "—").replacingOccurrences(of: "_", with: " "))")
                                    .font(.caption2).foregroundStyle(palette.textTertiary)
                                    .lineLimit(1).minimumScaleFactor(0.72)
                            }
                            Spacer(minLength: 0)
                            Text(money(l.rate))
                                .font(.caption2.weight(.bold).monospacedDigit()).foregroundStyle(palette.textSecondary)
                        }
                    }
                    if liveLoads.count > 6 {
                        Text("+ \(liveLoads.count - 6) more on the board")
                            .font(.caption2).foregroundStyle(palette.textTertiary)
                    }
                }
            }
        }
    }

    private var nextStepCard: some View {
        let copy: String = {
            guard let s = board?.summary else {
                return "The live board did not answer on this pass. The board is blank because the read failed, not because there is nothing on it — pull to refresh."
            }
            let total = s.total ?? liveLoads.count
            switch kind {
            case .laneBoard:
                if let t = topLane { return "\(laneGroups.count) lanes live with \(total) hauls. \(t.lane) holds \(t.count); drill in for detail." }
                return "No live lanes. Post or assign loads to populate the board."
            case .laneDrill:
                if let t = topLane { return "Top lane \(t.lane) carries \(t.count) of \(total) live hauls." }
                return "No live lanes to drill."
            case .haulDetail:
                if let l = focusLoad { return "\(l.loadNumber ?? l.id) \(l.origin ?? "—") → \(l.destination ?? "—") is \((l.status ?? "—").replacingOccurrences(of: "_", with: " ")). Confirm next gate from the board." }
                return "No live haul selected."
            case .rfpInbox:
                if let n = tenderCount { return n == 0 ? "Tender inbox is clear." : "\(n) pending tenders await a decision." }
                return "Tender inbox unreachable — retry on refresh."
            case .matchUp:
                if let n = candidateCount { return "\(n) drivers available · \(s.byStatus?.unassigned ?? 0) unassigned loads to cover." }
                return "Driver pool unreachable — retry on refresh."
            case .contractWrite:
                return "Open a tender from the inbox to draft a counter — no live RFP is under negotiation."
            }
        }()
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT STEP").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(copy).font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func load() async {
        async let b: Void = loadBoard()
        async let c: Void = loadCompany()
        async let t: Void = loadTenders()
        async let d: Void = loadCandidates()
        _ = await (b, c, t, d)
    }

    private func loadBoard() async {
        struct In: Encodable { let status: String?; let priority: String? }
        do { board = try await EusoTripAPI.shared.query("dispatchRole.getDispatchBoard", input: In(status: nil, priority: "all")) }
        catch { board = nil }
    }

    private func loadCompany() async {
        struct In: Encodable { let companyId: Int? }
        do { company = try await EusoTripAPI.shared.query("companies.getProfile", input: In(companyId: nil)) }
        catch { company = nil }
    }

    private func loadTenders() async {
        guard kind == .rfpInbox else { return }
        struct In: Encodable { let limit: Int }
        do {
            let env: DLRTendersEnvelope = try await EusoTripAPI.shared.query("dispatch.getPendingTenders", input: In(limit: 50))
            tenderCount = env.rows.count
        } catch { tenderCount = nil }
    }

    private func loadCandidates() async {
        guard kind == .matchUp else { return }
        struct In: Encodable { let limit: Int }
        do {
            let rows: [DLRDriver] = try await EusoTripAPI.shared.query("dispatch.getAvailableDrivers", input: In(limit: 50))
            candidateCount = rows.count
        } catch { candidateCount = nil }
    }
}

// MARK: - Screens (508-513)

struct DispatcherLaneBoardScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherLaneRFPShell(theme: theme) { DispatcherLaneRFPBody(kind: .laneBoard) } }
}
struct DispatcherLaneDrillScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherLaneRFPShell(theme: theme) { DispatcherLaneRFPBody(kind: .laneDrill) } }
}
struct DispatcherHaulDetailScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherLaneRFPShell(theme: theme) { DispatcherLaneRFPBody(kind: .haulDetail) } }
}
struct DispatcherRFPInboxScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherLaneRFPShell(theme: theme) { DispatcherLaneRFPBody(kind: .rfpInbox) } }
}
struct DispatcherMatchUpScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherLaneRFPShell(theme: theme) { DispatcherLaneRFPBody(kind: .matchUp) } }
}
struct DispatcherContractWriteScreen: View {
    let theme: Theme.Palette
    var body: some View { DispatcherLaneRFPShell(theme: theme) { DispatcherLaneRFPBody(kind: .contractWrite) } }
}

// MARK: - Previews

#Preview("508 Board · Dark")    { DispatcherLaneBoardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("509 Drill · Light")   { DispatcherLaneDrillScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("510 Haul · Dark")     { DispatcherHaulDetailScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("511 Inbox · Light")   { DispatcherRFPInboxScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
#Preview("512 Match · Dark")    { DispatcherMatchUpScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("513 Contract · Light"){ DispatcherContractWriteScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
