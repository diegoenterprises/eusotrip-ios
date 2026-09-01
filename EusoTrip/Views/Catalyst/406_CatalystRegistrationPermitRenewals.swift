//
//  406_CatalystRegistrationPermitRenewals.swift
//  EusoTrip 2027 · 406 Catalyst Registration & Permit Renewals
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//
//  Canonical contract audit (backend origin/main): authority.getMyAuthority
//  supplies identity; permits.list supplies user-scoped permit records;
//  compliance.getExpiringItems supplies due-soon company document records; and
//  permits.renew is the only complete renewal write available here. Per-unit
//  IRP, HVUT, IFTA decal, CVOR, mixed renewal-packet, and fee-payment contracts
//  do not exist, so this screen neither fabricates those rows nor exposes those
//  actions. Compliance documents remain read-only.
//

import SwiftUI

// MARK: - Domain

/// Which deadline band a returned record sits in. Derived, never stored: an
/// item is expired once `daysRemaining < 0`, DUE SOON inside the 30-day
/// horizon, and CLEAR beyond it. Operational authority is not inferred here.
enum CredentialGate: String, Codable, CaseIterable {
    case blocking, dueSoon, clear

    var label: String {
        switch self {
        case .blocking: return "EXPIRED PERMIT RECORDS"
        case .dueSoon:  return "DUE INSIDE 30 DAYS"
        case .clear:    return "CURRENT DATED RECORDS"
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
    /// Only rows sourced from permits.list can be renewed by permits.renew.
    /// Compliance-document rows are intentionally read-only.
    let permitId: String?

    var gate: CredentialGate { CredentialGate.from(daysRemaining: daysRemaining) }

    /// Deadline pill copy — time-relative, never an absolute date.
    var deadlinePill: String {
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
    let cacheCaption: String      // "UPDATED 14 MIN AGO"
    let cacheIsStale: Bool        // last successful in-memory read is old

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

    // Source coverage
    let sourceTitle: String
    let sourceSub: String

    func rows(in gate: CredentialGate) -> [CredentialRow] {
        rows.filter { $0.gate == gate }
    }
}

// MARK: - Store

/// Composes the gate from the real routers and labels the age of the last
/// successful in-memory refresh. Renewal writes require a live connection.
@MainActor
final class RegistrationRenewalsStore: ObservableObject {

    @Published private(set) var vm: RenewalGateVM?
    @Published private(set) var loading = false
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var offline = false
    @Published private(set) var loadError: String?
    @Published private(set) var actionError: String?
    @Published private(set) var actionSuccess: String?
    @Published private(set) var isRenewing = false

    static let freshnessWindow: TimeInterval = 24 * 60 * 60
    private let dueSoonHorizon = 30
    private let railWindowDays = 90

    // MARK: Wire DTOs — shapes taken verbatim from the routers on disk.

    private struct LimitIn: Encodable { let limit: Int }
    private struct PermitListIn: Encodable { let limit: Int; let offset: Int }
    private struct RenewIn: Encodable {
        let permitId: String
        let requestedEndDate: String
        let notes: String?
    }

    /// compliance.getExpiringItems — compliance.ts:276
    private struct ExpiringItem: Decodable {
        let id: String
        let type: String
        let driver: String
        let expiresAt: String
        let daysRemaining: Int
    }

    /// permits.list — permits.ts
    private struct PermitWire: Decodable {
        let id: String
        let permitNumber: String
        let type: String
        let status: String
        let expirationDate: String?
        let states: [String]
        let origin: String?
        let destination: String?
        let commodity: String?
        let fees: Double
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


    // MARK: Load

    func refresh() async {
        loading = true
        loadError = nil
        defer { loading = false }
        let api = EusoTripAPI.shared
        var authority: MyAuthority?
        var documents: [ExpiringItem] = []
        var permits: [PermitWire] = []
        var failures: [String] = []

        do { authority = try await api.queryNoInput("authority.getMyAuthority") }
        catch { failures.append("Authority profile: \(error.eusoUserCopy)") }
        do {
            permits = try await api.query(
                "permits.list", input: PermitListIn(limit: 100, offset: 0))
        } catch { failures.append("Permit records: \(error.eusoUserCopy)") }
        do {
            documents = try await api.query(
                "compliance.getExpiringItems", input: LimitIn(limit: 50))
        } catch { failures.append("Compliance deadlines: \(error.eusoUserCopy)") }

        let reachable = authority != nil || !permits.isEmpty || !documents.isEmpty
        offline = !reachable
        if reachable { lastSyncedAt = Date() }
        loadError = failures.isEmpty ? nil : failures.joined(separator: " ")

        vm = Self.compose(
            authority: authority,
            expiringDocs: documents,
            permits: permits,
            syncedAt: lastSyncedAt,
            dueSoonHorizon: dueSoonHorizon,
            railWindowDays: railWindowDays
        )
    }

    // MARK: Write

    @discardableResult
    func renewPermit(id: String, through endDate: Date, notes: String?) async -> Bool {
        guard !offline else {
            actionError = "A live connection is required to request a permit renewal."
            return false
        }
        isRenewing = true
        actionError = nil
        actionSuccess = nil
        defer { isRenewing = false }
        struct RenewOut: Decodable {
            let success: Bool
            let permitNumber: String?
            let status: String
        }
        let trimmedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let out: RenewOut = try await EusoTripAPI.shared.mutation(
                "permits.renew",
                input: RenewIn(
                    permitId: id,
                    requestedEndDate: ISO8601DateFormatter().string(from: endDate),
                    notes: trimmedNotes?.isEmpty == false ? trimmedNotes : nil))
            actionSuccess = out.permitNumber.map { "Renewal requested for \($0)." }
                ?? "Permit renewal requested."
            await refresh()
            return out.success
        } catch {
            actionError = "The permit renewal was not recorded. \(error.eusoUserCopy)"
            return false
        }
    }

    // MARK: Composition

    private static func recordedFee(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        let value = f.string(from: NSNumber(value: amount)) ?? String(amount)
        return amount > 0 ? "\(value) recorded" : "No fee recorded"
    }

    private static func relative(days: Int) -> String {
        days < 0 ? "\(abs(days)) d ago" : "in \(days) d"
    }

    private static func cacheCaption(_ syncedAt: Date?) -> (String, Bool) {
        guard let syncedAt else { return ("NOT UPDATED", true) }
        let age = Date().timeIntervalSince(syncedAt)
        let stale = age > freshnessWindow
        if age < 60 { return ("UPDATED JUST NOW", stale) }
        if age < 3600 { return ("UPDATED \(Int(age / 60)) MIN AGO", stale) }
        if age < 86_400 { return ("UPDATED \(Int(age / 3600)) H AGO", stale) }
        return ("UPDATED \(Int(age / 86_400)) D AGO", stale)
    }

    private static func parseDate(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(value.prefix(10)))
    }

    private static func daysRemaining(until date: Date) -> Int {
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: date)).day ?? 0
    }

    private static func compose(
        authority: MyAuthority?,
        expiringDocs: [ExpiringItem],
        permits: [PermitWire],
        syncedAt: Date?,
        dueSoonHorizon: Int,
        railWindowDays: Int
    ) -> RenewalGateVM {

        let datedPermits = permits.compactMap { permit -> CredentialRow? in
            guard let rawDate = permit.expirationDate,
                  let expiration = parseDate(rawDate) else { return nil }
            let route = [permit.origin, permit.destination]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " → ")
            let detail = [permit.status.replacingOccurrences(of: "_", with: " "),
                          permit.commodity, route.isEmpty ? nil : route]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            return CredentialRow(
                id: "permit-\(permit.id)",
                title: "\(permit.type.replacingOccurrences(of: "_", with: " ").capitalized) · \(permit.permitNumber)",
                citation: detail.isEmpty ? "Permit record" : detail,
                glyph: .taxForm,
                daysRemaining: daysRemaining(until: expiration),
                renewalFee: recordedFee(permit.fees),
                jurisdiction: permit.states.isEmpty ? "Jurisdiction not recorded"
                    : permit.states.joined(separator: "/"),
                permitId: permit.id)
        }

        let documentRows = expiringDocs.map {
            CredentialRow(
                id: "doc-\($0.id)",
                title: "\($0.type.replacingOccurrences(of: "_", with: " ").capitalized) · \($0.driver)",
                citation: "Compliance document · expires \($0.expiresAt)",
                glyph: .cabCard,
                daysRemaining: $0.daysRemaining,
                renewalFee: "No fee data",
                jurisdiction: "Document record",
                permitId: nil)
        }

        var rows = datedPermits + documentRows

        rows.sort { $0.daysRemaining < $1.daysRemaining }

        let blocking = rows.filter { $0.gate == .blocking }
        let dueSoon  = rows.filter { $0.gate == .dueSoon }
        let clear    = rows.filter { $0.gate == .clear }

        let soonest = dueSoon.first ?? clear.first
        let ticks = rows
            .filter { $0.daysRemaining >= 0 && $0.daysRemaining <= railWindowDays }
            .map { RenewalTick(id: $0.id, dayOffset: $0.daysRemaining) }

        let own = authority?.ownAuthority
        let dotNumber: String = own?.dotNumber ?? "—"
        let mcNumber: String = own?.mcNumber ?? "—"
        let dot = "USDOT \(dotNumber)"
        let mcNo = "MC-\(mcNumber)"
        let carrier: String = {
            if let n = own?.companyName, !n.isEmpty { return n }
            if let n = own?.legalName, !n.isEmpty { return n }
            return "—"
        }()
        let (caption, stale) = cacheCaption(syncedAt)
        let undatedPermitCount = permits.count - datedPermits.count

        return RenewalGateVM(
            carrierName: carrier,
            usdot: dot,
            mc: mcNo,
            subline: "\(carrier) · \(rows.count) dated renewal records",
            cacheCaption: caption,
            cacheIsStale: stale,
            blockingCount: blocking.count,
            blockingCaption: blocking.count == 1 ? "expired record" : "expired records",
            soonestRelative: soonest.map { relative(days: $0.daysRemaining) } ?? "none due",
            soonestSubject: soonest?.title ?? "nothing inside \(railWindowDays) d",
            lapsedRailFraction: rows.isEmpty ? 0 : Double(blocking.count) / Double(rows.count),
            windowDays: railWindowDays,
            ticks: ticks,
            heroLine: "\(blocking.count) expired permit records · \(dueSoon.count) dated records due inside \(dueSoonHorizon) d",
            heroFootnote: "\(ticks.count) dated records plotted inside \(railWindowDays) d",
            rows: rows,
            clearCount: clear.count,
            clearTitle: "\(clear.count) dated records beyond 30 days",
            clearCitation: "Current status reflects only records returned by the connected ledgers",
            clearNext: clear.first.map { "\($0.jurisdiction) \(relative(days: $0.daysRemaining))" } ?? "—",
            sourceTitle: "Connected renewal coverage",
            sourceSub: "\(permits.count) personal permit records · \(expiringDocs.count) company due-soon documents · \(undatedPermitCount) permits without an expiration date"
        )
    }
}

// MARK: - Screen

struct CatalystRegistrationPermitRenewals: View {
    @Environment(\.palette) var palette
    @ObservedObject var store: RegistrationRenewalsStore
    let vm: RenewalGateVM
    @State private var renewalTarget: CredentialRow?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s5) {
                    blockingHero
                    gateBand(.blocking, trailing: "\(vm.rows(in: .blocking).count) ITEMS")
                    gateBand(.dueSoon,  trailing: "\(vm.rows(in: .dueSoon).count) ITEMS")
                    if vm.clearCount > 0 { clearBand }
                    if vm.rows.isEmpty { emptyLedger }
                    sourceRow
                    if let success = store.actionSuccess { statusLine(success, Brand.success) }
                    if let error = store.actionError ?? store.loadError { statusLine(error, Brand.warning) }
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s5)
                .padding(.bottom, Space.s7)
            }
        }
        .task { await store.refresh() }
        .eusoRefreshable { await store.refresh() }
        .sheet(item: $renewalTarget) { row in
            PermitRenewalSheet(store: store, row: row)
        }
    }

    // MARK: Header — eyebrow · title 34/700 · identity · subline

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s3) {
                EusoTripEyebrow(verbatim: "CATALYST · REGISTRATION & PERMITS")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                // Age of the last successful in-memory refresh.
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
                    Text(isBlocking ? "EXPIRED RECORDS RETURNED" : "NO EXPIRED RECORDS RETURNED")
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
    @ViewBuilder
    private func gateRow(_ row: CredentialRow) -> some View {
        if row.permitId != nil {
            Button { renewalTarget = row } label: { gateRowContent(row) }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the permit renewal request")
        } else {
            gateRowContent(row)
                .accessibilityHint("This compliance document is read-only here")
        }
    }

    private func gateRowContent(_ row: CredentialRow) -> some View {
        let tint = bandTint(row.gate)
        return HStack(alignment: .top, spacing: Space.s3) {
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
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                Text(row.jurisdiction)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
            if row.permitId != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.title). \(row.deadlinePill). \(row.renewalFee). \(row.jurisdiction).")
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
                    Text("CURRENT RECORDS")
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

    private var emptyLedger: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("NO DATED RENEWAL RECORDS")
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text("No permit expiration dates or due-soon compliance documents were returned.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var sourceRow: some View {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Circle().fill(RadialGradient(
                        colors: [.white.opacity(0.75), .clear],
                        center: .init(x: 0.35, y: 0.30), startRadius: 0, endRadius: 16))
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(vm.sourceTitle)
                        .font(.system(size: 13, weight: .semibold)).tracking(-0.1)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(vm.sourceSub)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(Space.s3)
            .frame(height: 56)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func statusLine(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(EType.caption)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PermitRenewalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: RegistrationRenewalsStore
    let row: CredentialRow

    @State private var requestedEndDate = Calendar.current.date(
        byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var notes = ""

    private var minimumEndDate: Date {
        Calendar.current.date(
            byAdding: .day,
            value: max(0, row.daysRemaining + 1),
            to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Permit") {
                    LabeledContent("Record", value: row.title)
                    LabeledContent("Current deadline", value: row.deadlinePill)
                    LabeledContent("Jurisdiction", value: row.jurisdiction)
                }
                Section("Renewal request") {
                    DatePicker("Requested end date", selection: $requestedEndDate,
                               in: minimumEndDate..., displayedComponents: .date)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
                if store.offline {
                    Text("A live connection is required to request renewal.")
                        .foregroundStyle(Brand.warning)
                }
                if let error = store.actionError {
                    Text(error).foregroundStyle(Brand.warning)
                }
            }
            .navigationTitle("Renew permit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.isRenewing ? "Submitting…" : "Submit") {
                        guard let permitId = row.permitId else { return }
                        Task {
                            let success = await store.renewPermit(
                                id: permitId, through: requestedEndDate, notes: notes)
                            if success { dismiss() }
                        }
                    }
                    .disabled(row.permitId == nil || store.offline || store.isRenewing)
                }
            }
        }
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
    cacheCaption: "UPDATED 14 MIN AGO",
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
                      permitId: "142"),
        CredentialRow(id: "hvut-trk0311", title: "Form 2290 · TRK-0311",
                      citation: "26 CFR 41.6001-2 · HVUT · 80k lb", glyph: .taxForm,
                      daysRemaining: -11, renewalFee: "$550", jurisdiction: "IRS e-file",
                      permitId: nil),
        CredentialRow(id: "ifta-2027", title: "IFTA decals · 6 units",
                      citation: "IFTA Art. R650 · 2027 set", glyph: .decalSet,
                      daysRemaining: 12, renewalFee: "$60", jurisdiction: "IA base · 8 juris",
                      permitId: "2027"),
        CredentialRow(id: "ucr-2027", title: "UCR annual · fleet",
                      citation: "Permit record", glyph: .annualRegistry,
                      daysRemaining: 26, renewalFee: "$276", jurisdiction: "US fleet-wide",
                      permitId: nil),
    ],
    clearCount: 7,
    clearTitle: "7 credentials current",
    clearCitation: "MCS-150 · BOC-3 · CVOR · TX OS/OW",
    clearNext: "CVOR ON in 63 d",
    sourceTitle: "Connected renewal coverage",
    sourceSub: "4 permit records · 2 due-soon documents · 0 undated permits"
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
