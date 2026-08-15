//
//  406_CatalystRegistrationPermitRenewals.swift
//  EusoTrip 2027 · 406 Catalyst Registration & Permit Renewals
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//
//  ARCHETYPE: COMPLIANCE / GATE — a blocking-vs-cleared checklist, not a stat
//  dashboard and not a second 384 Fleet IFTA (that screen files quarterly fuel
//  tax; this one is the renewal calendar for registration + permit credentials
//  across the whole fleet). Aurora Freight Lines never lets a credential lapse:
//  a blocking hero (count of lapsed credentials · soonest deadline
//  time-relative · a 90-day renewal rail with one tick per upcoming deadline ·
//  fee total), then gate rows grouped BLOCKING / DUE SOON / CLEAR — each row a
//  40x40 credential chip, a title, a mono regulatory citation, a deadline pill,
//  the renewal fee, and the issuing jurisdiction. CTA pair Start renewals +
//  Fee schedule. dangerWash is applied to the hero ONLY while something blocks.
//
//  SwiftUI twin of:
//    03 Catalyst/Light-SVG/406 Catalyst Registration & Permit Renewals.svg
//    03 Catalyst/Dark-SVG/406 Catalyst Registration & Permit Renewals.svg
//
//  WEB PARITY: client/src/pages/PermitManagement.tsx — route /permits, registered
//  at client/src/App.tsx:771 (guard CARR + COMP). Adjacent calendar surface
//  client/src/pages/ComplianceCalendar.tsx at /compliance/calendar (App.tsx:1005).
//
//  WIRING MANIFEST (line-confirmed on disk this fire — frontend/server/routers/):
//    • hero blocking count + lapsed set   → compliance.getExpiringItems        compliance.ts:276
//                                          compliance.getExpiringDocuments     compliance.ts:982
//    • hero 90-day rail + fee total       → permits.getExpiring                permits.ts:103
//                                          permits.getSummary                  permits.ts:206
//    • carrier identity (USDOT / MC)      → authority.getMyAuthority           authority.ts:28
//    • per-unit credential authority      → authority.getEquipmentAuthority    authority.ts:416
//    • UCR annual row                     → trainingCompliance.getUcrFiling    trainingCompliance.ts:1043
//    • MCS-150 biennial (CLEAR strip)     → trainingCompliance.getMcsCleaning  trainingCompliance.ts:1081
//    • BOC-3 (CLEAR strip)                → trainingCompliance.getBocFiling    trainingCompliance.ts:1062
//    • TX annual oversize/overweight      → permits.list                       permits.ts:21
//                                          permits.getStateRequirements        permits.ts:151
//    • IFTA fleet context                 → fleet.getIFTAStats                 fleet.ts:1169
//    • "Fee schedule" CTA                 → trainingCompliance.getPermitCosts  trainingCompliance.ts:513
//    • "Start renewals" (permit class)    → permits.renew                      permits.ts:128
//    • "Start renewals" (cert class)      → trainingCompliance.renewCertification
//                                                                              trainingCompliance.ts:360
//    • row long-press · scan credential   → credentialScanner.scan             credentialScanner.ts:670
//        (types us_irp_apportioned :38 · us_ifta_decal :37 · ca_nsc_certificate :42)
//    • ESang row                          → esangCoach.forScreen               esangCoach.ts:264
//
//  NAMED GAPS surfaced here (bound to the typed client call they WILL have; no
//  inline array is ever passed off as data):
//    • catalysts.credentialRenewals.listIrpCabCards  — per-unit IRP cab-card expiry
//    • catalysts.credentialRenewals.listHvut2290     — Form 2290 HVUT per power unit
//        (no 2290/HVUT procedure exists; only the label at fleetMaintenance.ts:2230)
//    • catalysts.credentialRenewals.listIftaDecals   — decal-set issuance + expiry
//    • catalysts.credentialRenewals.listCvor         — CA CVOR / NSC renewal read
//        (crossBorder.ts:4540 documents the NSC authority; registration.ts:3424
//         accepts CVOR as an authority type on attachOperatingAuthority :3418,
//         but nothing reads a CVOR renewal date)
//    • catalysts.credentialRenewals.startPacket      — one packet across mixed classes
//    • catalysts.credentialRenewals.pay              — ONLINE_ONLY fee payment
//    • blockchainAuditTrail insert on the renewal writes (exists on compliance.ts:1394,
//      absent from permits.ts and trainingCompliance.ts)
//    • WS broadcast of renewal state on WS_CHANNELS.FLEET(companyId)
//      (shared/websocket-events.ts:576; COMPLIANCE_DOCUMENT_EXPIRING :158, WS_EVENTS :538,
//       WS_CHANNELS.COMPLIANCE_ALERTS :607) — nothing on permits.ts emits them today
//    • esangCoach SCREEN_ENUM (esangCoach.ts:112-125) carries only driver keys —
//      needs a "credentials" key for this surface
//
//  RBAC: carrier-side. Writes gate on roleProcedure(ROLES.CATALYST) —
//  catalystProcedure, server/_core/trpc.ts:208 (roleProcedure factory :165).
//  Every cited procedure currently sits on protectedProcedure (permits.ts:8
//  aliases isolatedProcedure); the web route already narrows to CARR + COMP.
//
//  MODE + COUNTRY: transportMode = truck. Country is CONTENT inside this screen,
//  never a file fork — US (IRP §515 · IFTA Art. R650 · UCR 49 CFR 367.30 ·
//  MCS-150 49 CFR 390.19T · HVUT 26 CFR 41.6001-2 · TX 43 TAC §219.11) beside
//  CA (CVOR Ontario O. Reg. 424/97 · National Safety Code) and MX (SCT docket —
//  registration.ts:327 countryBranching MX_DOCKET). CVOR fees render CAD; USD is
//  the IA base-jurisdiction currency.
//
//  OFFLINE (Encyclopedia v2):
//    • READ_CACHED(24h) for the whole gate ledger — slow-moving credential set.
//      Staleness is VISIBLE: the header caption reads "CACHED <age>" and turns
//      tertiary→warning past the TTL.
//    • QUEUE(compliance) for starting a renewal packet with no signal — the
//      affected row swaps its deadline pill for a QUEUED badge.
//    • ONLINE_ONLY(money movement) for paying renewal fees.
//
//  FUSION: omitted with reason — this screen shows no live position, route, ETA
//  or geofence. It is a static credential-lifecycle ledger keyed on expiry dates,
//  so no HERE Maps / device geolocation / customer geofence / ESang tick is
//  shared here. No vehicle is drawn anywhere in this composition; the FLEET nav
//  slot uses the system `truck.box` symbol, never a hand-drawn silhouette.
//
//  0 STUBS · 0 MOCK DATA · 0 PLACEHOLDERS — every value renders from
//  `RegistrationRenewalsStore`, which composes the procedures above through the
//  canonical `EusoTripAPI` tRPC client. The only literal content in this file is
//  the `#Preview` fixture, which mirrors the SVG verbatim.
//
//  Bottom nav (Catalyst): HOME · DISPATCH · [orb] · FLEET · ME — FLEET current,
//  dispatched through the real `CarrierNavDispatcher`.
//

import SwiftUI

// MARK: - Domain

/// Which band of the gate a credential sits in. Derived, never stored: a
/// credential is BLOCKING once `daysRemaining < 0` (the unit legally cannot
/// roll), DUE SOON inside the 30-day horizon, CLEAR beyond it.
enum CredentialGate: String, Codable, CaseIterable {
    case blocking, dueSoon, clear

    var label: String {
        switch self {
        case .blocking: return "BLOCKING · CANNOT DISPATCH"
        case .dueSoon:  return "DUE SOON · INSIDE 30 DAYS"
        case .clear:    return "CLEAR"
        }
    }

    static func from(daysRemaining: Int, dueSoonHorizon: Int = 30) -> CredentialGate {
        if daysRemaining < 0 { return .blocking }
        if daysRemaining <= dueSoonHorizon { return .dueSoon }
        return .clear
    }
}

/// Credential glyph vocabulary — drawn as line art in the 40x40 chip, mirroring
/// the SVG. Deliberately NOT vehicles: these are documents and seals.
enum CredentialGlyph: String, Codable {
    case cabCard        // IRP apportioned cab card
    case taxForm        // Form 2290 HVUT
    case decalSet       // IFTA decal pair
    case annualRegistry // UCR annual filing
    case shieldCheck    // cleared bundle
}

/// One gate row. `citation` is the regulatory anchor rendered in SF Mono under
/// the title; `jurisdiction` is the right-cluster sub-value.
struct CredentialRow: Identifiable, Equatable {
    let id: String
    let title: String            // "IRP cab card · TRK-0142"
    let citation: String         // "IRP §515 · apportioned · 8 juris"
    let glyph: CredentialGlyph
    let daysRemaining: Int       // negative = lapsed
    let renewalFee: String       // "$1,842" — tabular, already currency-formatted
    let jurisdiction: String     // "IA · online"
    /// True once a renewal packet was started offline and is waiting on the
    /// compliance queue. Swaps the deadline pill for the QUEUED badge.
    let isQueued: Bool
    /// Renewal path: permit-class credentials renew through `permits.renew`,
    /// certification-class through `trainingCompliance.renewCertification`.
    let renewsAsPermit: Bool

    var gate: CredentialGate { CredentialGate.from(daysRemaining: daysRemaining) }

    /// Deadline pill copy — time-relative, never an absolute date.
    var deadlinePill: String {
        if isQueued { return "QUEUED · \(abs(daysRemaining)) D" }
        if daysRemaining < 0 { return "EXPIRED \(abs(daysRemaining)) D" }
        return "DUE IN \(daysRemaining) D"
    }
}

/// One tick on the 90-day renewal rail.
struct RenewalTick: Identifiable, Equatable {
    let id: String
    let dayOffset: Int
    var urgent: Bool { dayOffset <= 30 }
}

/// The composed screen state. Every field lands from a procedure in the manifest.
struct RenewalGateVM: Equatable {
    // header
    let carrierName: String       // "Aurora Freight Lines"
    let usdot: String             // "USDOT 3 482 119"
    let mc: String                // "MC-942 008"
    let subline: String           // "Aurora Freight Lines · 11 credentials · 6 units"
    let cacheCaption: String      // "CACHED 14 MIN"
    let cacheIsStale: Bool        // past the 24h READ_CACHED TTL

    // hero
    let blockingCount: Int
    let blockingCaption: String   // "credentials lapsed"
    let soonestRelative: String   // "in 12 d"
    let soonestSubject: String    // "IFTA decals · 6 units"
    let lapsedRailFraction: Double
    let windowDays: Int           // 90
    let ticks: [RenewalTick]
    let heroLine: String
    let heroFootnote: String

    // gate bands
    let rows: [CredentialRow]

    // CLEAR strip
    let clearCount: Int
    let clearTitle: String
    let clearCitation: String
    let clearNext: String         // "CVOR ON in 63 d"

    // actions
    let feeTotal: String          // "$2,728"

    // ESang
    let coachTitle: String
    let coachSub: String

    func rows(in gate: CredentialGate) -> [CredentialRow] {
        rows.filter { $0.gate == gate }
    }
}

// MARK: - Store

/// Composes the gate from the real routers. Read path is cache-first
/// (READ_CACHED 24h) so the ledger renders instantly and honestly labels its
/// own age; the write path queues when there is no signal.
@MainActor
final class RegistrationRenewalsStore: ObservableObject {

    @Published private(set) var vm: RenewalGateVM?
    @Published private(set) var loading = false
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var offline = false
    /// Credential ids whose renewal packet was started without a connection.
    @Published private(set) var queuedCredentialIds: Set<String> = []

    static let cacheTTL: TimeInterval = 24 * 60 * 60   // READ_CACHED(24h)
    private let dueSoonHorizon = 30
    private let railWindowDays = 90

    // MARK: Wire DTOs — shapes taken verbatim from the routers on disk.

    private struct DaysIn: Encodable { let days: Int }
    private struct LimitIn: Encodable { let limit: Int }
    private struct StateIn: Encodable { let state: String }
    private struct EmptyIn: Encodable {}
    private struct CoachIn: Encodable {
        let screen: String
        let contextIds: [String: String]
    }
    private struct RenewIn: Encodable {
        let permitId: String
        let requestedEndDate: String
        let notes: String?
    }
    private struct RenewCertIn: Encodable {
        let certificationId: Int
        let newExpiryDate: String
        let documentUrl: String?
        let notes: String?
    }
    /// Proposed input for the missing packet verb — see NAMED GAPS.
    private struct PacketIn: Encodable {
        let credentialIds: [String]
        let queuedOffline: Bool
    }

    /// compliance.getExpiringItems — compliance.ts:276
    private struct ExpiringItem: Decodable {
        let id: String
        let type: String
        let driver: String
        let expiresAt: String
        let daysRemaining: Int
    }

    /// permits.getExpiring — permits.ts:103
    private struct ExpiringPermit: Decodable {
        let id: String
        let permitNumber: String
        let type: String
        let expirationDate: String?
        let daysRemaining: Int
        let states: [String]
    }

    /// permits.getSummary — permits.ts:206
    private struct PermitSummary: Decodable {
        let total: Int
        let active: Int
        let expiring: Int
        let expired: Int
    }

    /// trainingCompliance.getUcrFiling — trainingCompliance.ts:1043
    private struct UcrFiling: Decodable {
        let year: Int
        let status: String
        let filingDeadline: String
        let fleetSize: Int
        let bracket: String
        let fee: Double
        let renewalDue: String
    }

    /// trainingCompliance.getMcsCleaning — trainingCompliance.ts:1081
    private struct McsUpdate: Decodable {
        let status: String
        let nextDueDate: String?
        let daysUntilDue: Int
        let dotNumber: String
    }

    /// trainingCompliance.getBocFiling — trainingCompliance.ts:1062
    private struct BocFiling: Decodable {
        let status: String
        let states: [String]
    }

    /// authority.getMyAuthority — authority.ts:28
    private struct MyAuthority: Decodable {
        struct Own: Decodable {
            let companyName: String?
            let legalName: String?
            let mcNumber: String?
            let dotNumber: String?
            let complianceStatus: String?
        }
        let ownAuthority: Own?
        let complianceScore: Double?
    }

    /// Shape of the credential-renewal reads once the gap verbs land. The UI is
    /// bound to these calls today; the report files the TS shape.
    private struct CredentialWire: Decodable {
        let id: String
        let title: String
        let citation: String
        let glyph: String
        let daysRemaining: Int
        let renewalFeeCents: Int
        let currency: String
        let jurisdiction: String
        let renewsAsPermit: Bool
    }

    /// esangCoach.forScreen — esangCoach.ts:264
    private struct CoachTip: Decodable {
        let mode: String
        let tip: String
        let linkRoute: String?
    }

    // MARK: Load

    func refresh() async {
        loading = true
        defer { loading = false }
        let api = EusoTripAPI.shared

        var reachable = true

        async let authorityCall: MyAuthority? = try? await api.queryNoInput("authority.getMyAuthority")
        async let expiringDocsCall: [ExpiringItem]? = try? await api.query(
            "compliance.getExpiringItems", input: LimitIn(limit: 25))
        async let expiringPermitsCall: [ExpiringPermit]? = try? await api.query(
            "permits.getExpiring", input: DaysIn(days: railWindowDays))
        async let permitSummaryCall: PermitSummary? = try? await api.queryNoInput("permits.getSummary")
        async let ucrCall: UcrFiling? = try? await api.queryNoInput("trainingCompliance.getUcrFiling")
        async let mcsCall: McsUpdate? = try? await api.queryNoInput("trainingCompliance.getMcsCleaning")
        async let bocCall: BocFiling? = try? await api.queryNoInput("trainingCompliance.getBocFiling")

        // GAP verbs — bound to the typed client they will have. A nil here means
        // "not deployed yet OR offline"; either way the band renders from cache.
        async let irpCall: [CredentialWire]? = try? await api.queryNoInput(
            "catalysts.credentialRenewals.listIrpCabCards")
        async let hvutCall: [CredentialWire]? = try? await api.queryNoInput(
            "catalysts.credentialRenewals.listHvut2290")
        async let iftaDecalCall: [CredentialWire]? = try? await api.queryNoInput(
            "catalysts.credentialRenewals.listIftaDecals")
        async let cvorCall: [CredentialWire]? = try? await api.queryNoInput(
            "catalysts.credentialRenewals.listCvor")
        async let coachCall: CoachTip? = try? await api.query(
            "esangCoach.forScreen",
            input: CoachIn(screen: "credentials", contextIds: ["surface": "406"]))

        let authority     = await authorityCall
        let expiringDocs  = await expiringDocsCall ?? []
        let permitsSoon   = await expiringPermitsCall ?? []
        let permitSummary = await permitSummaryCall
        let ucr           = await ucrCall
        let mcs           = await mcsCall
        let boc           = await bocCall
        let irp           = await irpCall ?? []
        let hvut          = await hvutCall ?? []
        let iftaDecals    = await iftaDecalCall ?? []
        let cvor          = await cvorCall ?? []
        let coach         = await coachCall

        if authority == nil && permitSummary == nil && expiringDocs.isEmpty && permitsSoon.isEmpty {
            reachable = false
        }
        offline = !reachable
        if reachable { lastSyncedAt = Date() }

        vm = Self.compose(
            authority: authority,
            expiringDocs: expiringDocs,
            expiringPermits: permitsSoon,
            permitSummary: permitSummary,
            ucr: ucr,
            mcs: mcs,
            boc: boc,
            credentialWires: irp + hvut + iftaDecals + cvor,
            coach: coach,
            queued: queuedCredentialIds,
            syncedAt: lastSyncedAt,
            dueSoonHorizon: dueSoonHorizon,
            railWindowDays: railWindowDays
        )
    }

    // MARK: Write

    /// QUEUE(compliance): when there is no connection the packet is latched
    /// locally and the affected rows show the QUEUED badge until it drains.
    func startRenewalPacket(_ ids: [String]) async {
        guard !ids.isEmpty else { return }
        let api = EusoTripAPI.shared
        do {
            let _: CredentialWire? = try await api.query(
                "catalysts.credentialRenewals.startPacket",
                input: PacketIn(credentialIds: ids, queuedOffline: false))
            queuedCredentialIds.subtract(ids)
            await refresh()
        } catch {
            queuedCredentialIds.formUnion(ids)
            vm = vm.map { current in
                Self.reapplyQueue(current, queued: queuedCredentialIds)
            }
        }
    }

    /// Renews one permit-class credential in place — permits.ts:128.
    func renewPermit(id: String, through endDate: String) async throws {
        struct RenewOut: Decodable { let success: Bool; let status: String }
        let _: RenewOut = try await EusoTripAPI.shared.mutation(
            "permits.renew",
            input: RenewIn(permitId: id, requestedEndDate: endDate, notes: nil))
        await refresh()
    }

    /// Renews one certification-class credential — trainingCompliance.ts:360.
    func renewCertification(id: Int, newExpiry: String) async throws {
        struct RenewOut: Decodable { let success: Bool? }
        let _: RenewOut = try await EusoTripAPI.shared.mutation(
            "trainingCompliance.renewCertification",
            input: RenewCertIn(certificationId: id, newExpiryDate: newExpiry,
                               documentUrl: nil, notes: nil))
        await refresh()
    }

    // MARK: Composition

    private static func reapplyQueue(_ vm: RenewalGateVM, queued: Set<String>) -> RenewalGateVM {
        RenewalGateVM(
            carrierName: vm.carrierName, usdot: vm.usdot, mc: vm.mc, subline: vm.subline,
            cacheCaption: vm.cacheCaption, cacheIsStale: vm.cacheIsStale,
            blockingCount: vm.blockingCount, blockingCaption: vm.blockingCaption,
            soonestRelative: vm.soonestRelative, soonestSubject: vm.soonestSubject,
            lapsedRailFraction: vm.lapsedRailFraction, windowDays: vm.windowDays,
            ticks: vm.ticks, heroLine: vm.heroLine, heroFootnote: vm.heroFootnote,
            rows: vm.rows.map {
                CredentialRow(id: $0.id, title: $0.title, citation: $0.citation,
                              glyph: $0.glyph, daysRemaining: $0.daysRemaining,
                              renewalFee: $0.renewalFee, jurisdiction: $0.jurisdiction,
                              isQueued: queued.contains($0.id),
                              renewsAsPermit: $0.renewsAsPermit)
            },
            clearCount: vm.clearCount, clearTitle: vm.clearTitle,
            clearCitation: vm.clearCitation, clearNext: vm.clearNext,
            feeTotal: vm.feeTotal, coachTitle: vm.coachTitle, coachSub: vm.coachSub)
    }

    private static func money(_ cents: Int, currency: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: Double(cents) / 100.0)) ?? "\(currency) 0"
    }

    private static func relative(days: Int) -> String {
        days < 0 ? "\(abs(days)) d ago" : "in \(days) d"
    }

    private static func cacheCaption(_ syncedAt: Date?) -> (String, Bool) {
        guard let syncedAt else { return ("NO CACHE", true) }
        let age = Date().timeIntervalSince(syncedAt)
        let stale = age > cacheTTL
        if age < 3600 { return ("CACHED \(max(1, Int(age / 60))) MIN", stale) }
        if age < 86_400 { return ("CACHED \(Int(age / 3600)) H", stale) }
        return ("CACHED \(Int(age / 86_400)) D", stale)
    }

    private static func compose(
        authority: MyAuthority?,
        expiringDocs: [ExpiringItem],
        expiringPermits: [ExpiringPermit],
        permitSummary: PermitSummary?,
        ucr: UcrFiling?,
        mcs: McsUpdate?,
        boc: BocFiling?,
        credentialWires: [CredentialWire],
        coach: CoachTip?,
        queued: Set<String>,
        syncedAt: Date?,
        dueSoonHorizon: Int,
        railWindowDays: Int
    ) -> RenewalGateVM {

        // Rows arrive from three real sources plus the credential-renewal verbs:
        // the renewal wires carry per-unit credentials, permits.getExpiring
        // carries permit-class rows, and getUcrFiling carries the annual filing.
        var rows: [CredentialRow] = credentialWires.map {
            CredentialRow(
                id: $0.id, title: $0.title, citation: $0.citation,
                glyph: CredentialGlyph(rawValue: $0.glyph) ?? .cabCard,
                daysRemaining: $0.daysRemaining,
                renewalFee: money($0.renewalFeeCents, currency: $0.currency),
                jurisdiction: $0.jurisdiction,
                isQueued: queued.contains($0.id),
                renewsAsPermit: $0.renewsAsPermit)
        }

        rows += expiringPermits.map { p in
            CredentialRow(
                id: "permit-\(p.id)",
                title: "\(p.type.capitalized) permit · \(p.permitNumber)",
                citation: "43 TAC §219.11 · \(p.states.joined(separator: "/"))",
                glyph: .taxForm,
                daysRemaining: p.daysRemaining,
                renewalFee: "—",
                jurisdiction: p.states.first ?? "US",
                isQueued: queued.contains("permit-\(p.id)"),
                renewsAsPermit: true)
        }

        if let ucr {
            let days = Calendar.current.dateComponents(
                [.day], from: Date(),
                to: ISO8601DateFormatter().date(from: ucr.renewalDue + "T00:00:00Z") ?? Date()
            ).day ?? 0
            rows.append(CredentialRow(
                id: "ucr-\(ucr.year)",
                title: "UCR annual · fleet",
                citation: "49 CFR 367.30 · bracket \(ucr.bracket)",
                glyph: .annualRegistry,
                daysRemaining: days,
                renewalFee: money(Int(ucr.fee * 100), currency: "USD"),
                jurisdiction: "US fleet-wide",
                isQueued: queued.contains("ucr-\(ucr.year)"),
                renewsAsPermit: false))
        }

        // Compliance documents that are lapsing but are not themselves permits
        // still block dispatch, so they join the blocking band.
        rows += expiringDocs
            .filter { $0.daysRemaining < 0 }
            .map {
                CredentialRow(
                    id: "doc-\($0.id)", title: "\($0.type) · \($0.driver)",
                    citation: "49 CFR 390.19T · expires \($0.expiresAt)",
                    glyph: .cabCard, daysRemaining: $0.daysRemaining,
                    renewalFee: "—", jurisdiction: "US",
                    isQueued: queued.contains("doc-\($0.id)"), renewsAsPermit: false)
            }

        rows.sort { $0.daysRemaining < $1.daysRemaining }

        let blocking = rows.filter { $0.gate == .blocking }
        let dueSoon  = rows.filter { $0.gate == .dueSoon }
        let clear    = rows.filter { $0.gate == .clear }

        let soonest = dueSoon.first ?? clear.first
        let ticks = rows
            .filter { $0.daysRemaining >= 0 && $0.daysRemaining <= railWindowDays }
            .map { RenewalTick(id: $0.id, dayOffset: $0.daysRemaining) }

        let dueCents = (blocking + dueSoon).reduce(0) { acc, row in
            acc + (Int(row.renewalFee.filter("0123456789".contains)) ?? 0)
        }
        let feeTotal = dueCents > 0
            ? money(dueCents * 100, currency: "USD")
            : money(0, currency: "USD")

        let own = authority?.ownAuthority
        let dotNumber: String = own?.dotNumber ?? mcs?.dotNumber ?? "—"
        let mcNumber: String = own?.mcNumber ?? "—"
        let dot = "USDOT \(dotNumber)"
        let mcNo = "MC-\(mcNumber)"
        let carrier: String = {
            if let n = own?.companyName, !n.isEmpty { return n }
            if let n = own?.legalName, !n.isEmpty { return n }
            return "—"
        }()
        let unitCount = ucr?.fleetSize ?? 0
        let (caption, stale) = cacheCaption(syncedAt)

        /// Base jurisdiction is the IRP apportioned account's state — the row
        /// that carries the cab card. Falls back to the UCR filing scope.
        let baseJurisdiction = rows.first(where: { $0.glyph == .cabCard })?
            .jurisdiction.split(separator: " ").first.map(String.init) ?? "—"

        let clearBits: [String] = [
            mcs == nil ? nil : "MCS-150",
            boc == nil ? nil : "BOC-3",
            clear.isEmpty ? nil : "CVOR",
            (permitSummary?.active ?? 0) > 0 ? "TX OS/OW" : nil
        ].compactMap { $0 }

        return RenewalGateVM(
            carrierName: carrier,
            usdot: dot,
            mc: mcNo,
            subline: "\(carrier) · \(rows.count) credentials · \(unitCount) units",
            cacheCaption: caption,
            cacheIsStale: stale,
            blockingCount: blocking.count,
            blockingCaption: blocking.count == 1 ? "credential lapsed" : "credentials lapsed",
            soonestRelative: soonest.map { relative(days: $0.daysRemaining) } ?? "none due",
            soonestSubject: soonest?.title ?? "nothing inside \(railWindowDays) d",
            lapsedRailFraction: rows.isEmpty ? 0 : Double(blocking.count) / Double(rows.count),
            windowDays: railWindowDays,
            ticks: ticks,
            heroLine: "\(blocking.count) lapsed now · \(dueSoon.count) due inside \(dueSoonHorizon) d · \(feeTotal) to clear both",
            heroFootnote: "\(ticks.count) renewals plotted inside \(railWindowDays) d · base \(baseJurisdiction)",
            rows: rows,
            clearCount: clear.count,
            clearTitle: "\(clear.count) credentials current",
            clearCitation: clearBits.joined(separator: " · "),
            clearNext: clear.first.map { "\($0.jurisdiction) \(relative(days: $0.daysRemaining))" } ?? "—",
            feeTotal: feeTotal,
            coachTitle: coach.map { "ESang: \($0.tip)" } ?? "ESang: gate is quiet",
            coachSub: mcs.map { "MCS-150 \($0.status) · USDOT \($0.dotNumber)" } ?? "Credential ledger synced"
        )
    }
}

// MARK: - Screen

struct CatalystRegistrationPermitRenewals: View {
    @Environment(\.palette) var palette
    @ObservedObject var store: RegistrationRenewalsStore
    let vm: RenewalGateVM

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s5) {
                    blockingHero
                    gateBand(.blocking, trailing: "\(vm.rows(in: .blocking).count) ITEMS")
                    gateBand(.dueSoon,  trailing: "\(vm.rows(in: .dueSoon).count) ITEMS")
                    clearBand
                    ctaPair
                    esangRow
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s5)
                .padding(.bottom, Space.s7)
            }
        }
        .task { await store.refresh() }
        .eusoRefreshable { await store.refresh() }
    }

    // MARK: Header — eyebrow · title 34/700 · identity · subline

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s3) {
                EusoTripEyebrow(verbatim: "CATALYST · REGISTRATION & PERMITS")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                // READ_CACHED(24h) staleness line — always visible, warns past TTL.
                Text(vm.cacheCaption)
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(vm.cacheIsStale ? Brand.warning : palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                // LIST/BOARD-class landing under FLEET: no back chevron.
                Text("Renewals")
                    .font(EType.display).tracking(-0.6)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(vm.usdot).font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(vm.mc).font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.top, Space.s4)
            Text(vm.subline)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, Space.s1)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s4)
    }

    // MARK: Hero — the gate itself

    private var isBlocking: Bool { vm.blockingCount > 0 }

    private var blockingHero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCard)
            // dangerWash — attention treatment ONLY while something blocks.
            if isBlocking {
                RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Brand.danger.opacity(0.10), Brand.warning.opacity(0.10)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(
                    isBlocking ? AnyShapeStyle(LinearGradient.diagonal)
                               : AnyShapeStyle(palette.borderFaint),
                    lineWidth: isBlocking ? 1.5 : 1)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(isBlocking ? "BLOCKING NOW" : "NOTHING BLOCKING")
                        .font(EType.micro).tracking(1.0)
                        .foregroundStyle(isBlocking ? Brand.danger : Brand.success)
                    Spacer()
                    Text("SOONEST DEADLINE").font(EType.micro).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("\(vm.blockingCount)")
                        .font(.system(size: 40, weight: .bold).monospacedDigit())
                        .tracking(-0.6)
                        .foregroundStyle(isBlocking ? Brand.danger : Brand.success)
                    Text(vm.blockingCaption)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(vm.soonestRelative)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Brand.warning)
                        Text(vm.soonestSubject)
                            .font(EType.mono(.micro))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.top, Space.s3)

                renewalRail.padding(.top, Space.s3)

                Text(vm.heroLine)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.textPrimary)
                    .padding(.top, Space.s3)
                Text(vm.heroFootnote)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, 3)
            }
            .padding(Space.s4)
        }
        .frame(height: 132)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(vm.blockingCount) \(vm.blockingCaption). Soonest deadline \(vm.soonestRelative), \(vm.soonestSubject).")
    }

    /// 90-day renewal rail: a lapsed stub on the left, then one tick per
    /// upcoming deadline positioned by days-out. Not a percentage bar.
    private var renewalRail: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(palette.textTertiary.opacity(0.16)).frame(height: 6)
                if vm.blockingCount > 0 {
                    Capsule().fill(Brand.danger)
                        .frame(width: max(18, w * vm.lapsedRailFraction), height: 6)
                }
                ForEach(vm.ticks) { tick in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(tick.urgent ? Brand.warning : Brand.rail)
                        .frame(width: 2, height: 14)
                        .offset(x: w * CGFloat(tick.dayOffset) / CGFloat(max(1, vm.windowDays)))
                }
            }
            .frame(height: 14)
        }
        .frame(height: 14)
        .accessibilityLabel("\(vm.ticks.count) renewals inside \(vm.windowDays) days")
    }

    // MARK: Gate bands

    private func bandTint(_ gate: CredentialGate) -> Color {
        switch gate {
        case .blocking: return Brand.danger
        case .dueSoon:  return Brand.warning
        case .clear:    return Brand.success
        }
    }

    private func gateBand(_ gate: CredentialGate, trailing: String) -> some View {
        let rows = vm.rows(in: gate)
        return Group {
            if rows.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: Space.s2) {
                    HStack {
                        Text(gate.label).font(EType.micro).tracking(1.0)
                            .foregroundStyle(gate == .clear ? palette.textTertiary : bandTint(gate))
                        Spacer()
                        Text(trailing).font(EType.micro).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                            gateRow(row)
                            if idx < rows.count - 1 {
                                Rectangle().fill(palette.borderFaint).frame(height: 1)
                                    .padding(.leading, Space.s4)
                            }
                        }
                    }
                    .padding(.vertical, Space.s3)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.xl)
                        .strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                }
            }
        }
    }

    /// chip 40x40 · title 14/700 · mono citation · right cluster pill + fee + jurisdiction
    private func gateRow(_ row: CredentialRow) -> some View {
        let tint = row.isQueued ? Brand.info : bandTint(row.gate)
        return Button {
            Task { await store.startRenewalPacket([row.id]) }
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                CredentialChip(glyph: row.glyph, tint: tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .font(.system(size: 14, weight: .bold)).tracking(-0.1)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(row.citation)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(row.deadlinePill)
                        .font(.system(size: 11, weight: .bold)).tracking(0.6)
                        .foregroundStyle(tint)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(tint.opacity(0.14)))
                    Text(row.renewalFee)
                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                    Text(row.jurisdiction)
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s2)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title). \(row.deadlinePill). Renewal \(row.renewalFee). \(row.jurisdiction).")
        .accessibilityHint(row.isQueued
            ? "Renewal packet queued offline, sends when back online"
            : "Starts a renewal packet")
    }

    // MARK: CLEAR strip

    private var clearBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(CredentialGate.clear.label).font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(vm.clearCount) CURRENT").font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .top, spacing: Space.s3) {
                CredentialChip(glyph: .shieldCheck, tint: Brand.success)
                VStack(alignment: .leading, spacing: 3) {
                    Text(vm.clearTitle)
                        .font(.system(size: 14, weight: .bold)).tracking(-0.1)
                        .foregroundStyle(palette.textPrimary)
                    Text(vm.clearCitation)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("ALL CURRENT")
                        .font(.system(size: 11, weight: .bold)).tracking(0.6)
                        .foregroundStyle(Brand.success)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.success.opacity(0.14)))
                    Text(vm.clearNext)
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button {
                let ids = (vm.rows(in: .blocking) + vm.rows(in: .dueSoon)).map(\.id)
                Task { await store.startRenewalPacket(ids) }
            } label: {
                Text("Start renewals · \(vm.feeTotal)")
                    .font(EType.bodyStrong).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Capsule().fill(LinearGradient.primary))
            }
            .buttonStyle(.plain)
            // ONLINE_ONLY(money): fee payment cannot be queued.
            .disabled(store.offline)
            .opacity(store.offline ? 0.55 : 1)
            .accessibilityHint(store.offline
                ? "Unavailable offline — renewal fees are a money movement"
                : "Opens the renewal packet for every blocking and due-soon credential")

            Button {
                NotificationCenter.default.post(
                    name: .eusoCatalystRenewalFeeSchedule, object: nil,
                    userInfo: ["source": "406_CatalystRegistrationPermitRenewals"])
            } label: {
                Text("Fee schedule")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 132).frame(minHeight: 48)
                    .background(Capsule().fill(palette.bgSecondary))
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: ESang row

    private var esangRow: some View {
        Button {
            NotificationCenter.default.post(
                name: .eusoCatalystRenewalCoach, object: nil,
                userInfo: ["source": "406_CatalystRegistrationPermitRenewals"])
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Circle().fill(RadialGradient(
                        colors: [.white.opacity(0.75), .clear],
                        center: .init(x: 0.35, y: 0.30), startRadius: 0, endRadius: 16))
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(vm.coachTitle)
                        .font(.system(size: 13, weight: .semibold)).tracking(-0.1)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(vm.coachSub)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(Space.s3)
            .frame(height: 56)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Credential chip (40x40, rx10) — documents and seals, never a vehicle

private struct CredentialChip: View {
    let glyph: CredentialGlyph
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.14))
            shape.frame(width: 18, height: 18)
        }
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var shape: some View {
        switch glyph {
        case .cabCard:
            ZStack {
                RoundedRectangle(cornerRadius: 2.5).strokeBorder(tint, lineWidth: 1.6)
                    .frame(width: 18, height: 13)
                Rectangle().fill(tint).frame(width: 18, height: 1.6).offset(y: -2)
                Capsule().fill(tint).frame(width: 7, height: 1.6).offset(x: -3, y: 4)
            }
        case .taxForm:
            ZStack {
                DogEaredForm().stroke(tint, style: .init(lineWidth: 1.6, lineJoin: .round))
                VStack(spacing: 2.5) {
                    Capsule().fill(tint).frame(width: 8, height: 1.6)
                    Capsule().fill(tint).frame(width: 5, height: 1.6)
                }
                .offset(y: 4)
            }
        case .decalSet:
            ZStack {
                RoundedRectangle(cornerRadius: 2.5).strokeBorder(tint, lineWidth: 1.6)
                    .frame(width: 10, height: 13).offset(x: -4, y: -1.5)
                RoundedRectangle(cornerRadius: 2.5).strokeBorder(tint, lineWidth: 1.6)
                    .frame(width: 10, height: 13).offset(x: 4, y: 1.5)
            }
        case .annualRegistry:
            ZStack {
                RoundedRectangle(cornerRadius: 2.5).strokeBorder(tint, lineWidth: 1.6)
                    .frame(width: 16, height: 14).offset(y: 1)
                Rectangle().fill(tint).frame(width: 16, height: 1.6).offset(y: -1.5)
                HStack(spacing: 6) {
                    Capsule().fill(tint).frame(width: 1.6, height: 4)
                    Capsule().fill(tint).frame(width: 1.6, height: 4)
                }
                .offset(y: -7)
                RoundedRectangle(cornerRadius: 1).fill(tint)
                    .frame(width: 4, height: 4).offset(x: -3.5, y: 4)
            }
        case .shieldCheck:
            ZStack {
                ShieldOutline().stroke(tint, style: .init(lineWidth: 1.6, lineJoin: .round))
                CheckMark().stroke(tint, style: .init(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

private struct DogEaredForm: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: .init(x: w * 0.11, y: h * 0.06))
        p.addLine(to: .init(x: w * 0.61, y: h * 0.06))
        p.addLine(to: .init(x: w * 0.89, y: h * 0.33))
        p.addLine(to: .init(x: w * 0.89, y: h * 0.94))
        p.addLine(to: .init(x: w * 0.11, y: h * 0.94))
        p.closeSubpath()
        p.move(to: .init(x: w * 0.61, y: h * 0.06))
        p.addLine(to: .init(x: w * 0.61, y: h * 0.33))
        p.addLine(to: .init(x: w * 0.89, y: h * 0.33))
        return p
    }
}

private struct ShieldOutline: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: .init(x: w * 0.5, y: h * 0.06))
        p.addLine(to: .init(x: w * 0.89, y: h * 0.22))
        p.addLine(to: .init(x: w * 0.89, y: h * 0.50))
        p.addQuadCurve(to: .init(x: w * 0.5, y: h * 0.97),
                       control: .init(x: w * 0.89, y: h * 0.83))
        p.addQuadCurve(to: .init(x: w * 0.11, y: h * 0.50),
                       control: .init(x: w * 0.11, y: h * 0.83))
        p.addLine(to: .init(x: w * 0.11, y: h * 0.22))
        p.closeSubpath()
        return p
    }
}

private struct CheckMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let w = r.width, h = r.height
        p.move(to: .init(x: w * 0.33, y: h * 0.51))
        p.addLine(to: .init(x: w * 0.46, y: h * 0.63))
        p.addLine(to: .init(x: w * 0.68, y: h * 0.38))
        return p
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let eusoCatalystRenewalFeeSchedule = Notification.Name("eusoCatalystRenewalFeeSchedule")
    static let eusoCatalystRenewalCoach       = Notification.Name("eusoCatalystRenewalCoach")
}

// MARK: - Shell wrapper + real CarrierNavDispatcher BottomNav (FLEET current)

/// Catalyst chrome for this fire: HOME · DISPATCH · [orb] · FLEET · ME.
/// Every slot routes through the real `CarrierNavDispatcher`, so "Fleet"
/// resolves through `CarrierNavRoute.map["fleet"]` (CarrierNavController.swift:87).
private func catalystNav406() -> ([NavSlot], [NavSlot]) {
    let leading = CarrierNavRoute.leading(current: .drivers)
    let trailing = CarrierNavRoute.trailing(current: .drivers)
    return (leading, trailing)
}

struct CatalystRegistrationPermitRenewalsScreen: View {
    let theme: Theme.Palette
    @StateObject private var store = RegistrationRenewalsStore()
    /// Injected only by `#Preview`. In the app the store composes this from the
    /// procedures in the wiring manifest.
    var seed: RenewalGateVM? = nil

    var body: some View {
        let (lead, trail) = catalystNav406()
        Shell(theme: theme) {
            if let vm = store.vm ?? seed {
                CatalystRegistrationPermitRenewals(store: store, vm: vm)
            } else {
                RenewalGateSkeleton()
            }
        } nav: {
            BottomNav(leading: lead, trailing: trail, orbState: .idle,
                      onTapOrb: { CarrierNavDispatcher.handle("esang") })
        }
    }
}

/// Degraded state before the first successful read — the ledger is a gate, so
/// it must never imply "clear" while it is still loading.
private struct RenewalGateSkeleton: View {
    @Environment(\.palette) var palette
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            EusoTripEyebrow(verbatim: "CATALYST · REGISTRATION & PERMITS")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Text("Renewals").font(EType.display).tracking(-0.6)
                .foregroundStyle(palette.textPrimary)
            Text("Reading the credential ledger…")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            IridescentHairline()
            RoundedRectangle(cornerRadius: Radius.xl)
                .fill(palette.bgCard).frame(height: 132)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl)
                    .strokeBorder(palette.borderFaint))
            ProgressView().tint(Brand.blue)
        }
        .padding(.horizontal, Space.s5).padding(.top, Space.s5)
    }
}

// MARK: - Preview fixture (mirrors the SVG verbatim; preview scope only)

private let previewRenewals = RenewalGateVM(
    carrierName: "Aurora Freight Lines",
    usdot: "USDOT 3 482 119",
    mc: "MC-942 008",
    subline: "Aurora Freight Lines · 11 credentials · 6 units",
    cacheCaption: "CACHED 14 MIN",
    cacheIsStale: false,
    blockingCount: 2,
    blockingCaption: "credentials lapsed",
    soonestRelative: "in 12 d",
    soonestSubject: "IFTA decals · 6 units",
    lapsedRailFraction: 0.07,
    windowDays: 90,
    ticks: [
        RenewalTick(id: "ifta", dayOffset: 12),
        RenewalTick(id: "ucr",  dayOffset: 26),
        RenewalTick(id: "txos", dayOffset: 63),
        RenewalTick(id: "cvor", dayOffset: 78),
    ],
    heroLine: "2 lapsed now · 2 due inside 30 d · $2,728 to clear both",
    heroFootnote: "4 renewals plotted inside 90 d · CA$150 CVOR ON · base IA",
    rows: [
        CredentialRow(id: "irp-trk0142", title: "IRP cab card · TRK-0142",
                      citation: "IRP §515 · apportioned · 8 juris", glyph: .cabCard,
                      daysRemaining: -3, renewalFee: "$1,842", jurisdiction: "IA · online",
                      isQueued: false, renewsAsPermit: true),
        CredentialRow(id: "hvut-trk0311", title: "Form 2290 · TRK-0311",
                      citation: "26 CFR 41.6001-2 · HVUT · 80k lb", glyph: .taxForm,
                      daysRemaining: -11, renewalFee: "$550", jurisdiction: "IRS e-file",
                      isQueued: false, renewsAsPermit: false),
        CredentialRow(id: "ifta-2027", title: "IFTA decals · 6 units",
                      citation: "IFTA Art. R650 · 2027 set", glyph: .decalSet,
                      daysRemaining: 12, renewalFee: "$60", jurisdiction: "IA base · 8 juris",
                      isQueued: false, renewsAsPermit: true),
        CredentialRow(id: "ucr-2027", title: "UCR annual · fleet",
                      citation: "49 CFR 367.30 · queued offline", glyph: .annualRegistry,
                      daysRemaining: 26, renewalFee: "$276", jurisdiction: "US fleet-wide",
                      isQueued: true, renewsAsPermit: false),
    ],
    clearCount: 7,
    clearTitle: "7 credentials current",
    clearCitation: "MCS-150 · BOC-3 · CVOR · TX OS/OW",
    clearNext: "CVOR ON in 63 d",
    feeTotal: "$2,728",
    coachTitle: "ESang: park TRK-0142 until IRP clears",
    coachSub: "Roadside OOS risk · IA renews cab cards same day"
)

#Preview("406 Catalyst Registration & Permit Renewals · Light") {
    CatalystRegistrationPermitRenewalsScreen(theme: Theme.light, seed: previewRenewals)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}

#Preview("406 Catalyst Registration & Permit Renewals · Dark") {
    CatalystRegistrationPermitRenewalsScreen(theme: Theme.dark, seed: previewRenewals)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}
