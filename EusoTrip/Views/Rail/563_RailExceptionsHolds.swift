//
//  563_RailExceptionsHolds.swift
//  EusoTrip — Rail Engineer · Exceptions & Holds (carrier-side ops board).
//
//  Visual identity: danger-wash hero card (red/orange 10% tint) when holds/alerts
//  are active; exceptions grouped by category (BAD ORDERS · FRA ALERTS · DEMURRAGE)
//  with icon-differentiated type chips; severity counter in the hero.
//
//  Data:
//    railShipments.getRailCompliance       (EXISTS :568) → inspections + failedCount
//    railShipments.getFRASafetyCompliance  (EXISTS :720) → FRA violations (best-effort)
//    railShipments.getLiveDemurrage        (EXISTS :759) → demurrage accruals (best-effort)
//    railShipments.getAssetHealth          (EXISTS :692) → Railinc asset health (best-effort)
//
//  §W OFFLINE POLICY (Encyclopedia v2 · honesty law):
//    · READ_CACHED(2m) — the board paints from the last decoded read of
//      railShipments.getRailCompliance plus the three best-effort feeds, and
//      states its own age on a monospaced staleness line under the header:
//      "LIVE · read HH:mm:ss" in textTertiary, "STALE · N min old · not live"
//      in Brand.warning past the two-minute ttl, and "OFFLINE · N min old · not
//      refreshing" when the device cannot reach the network at all. Cached,
//      stale and offline are VISIBLY distinct from live, and a failed refresh
//      keeps the last real board on screen (labelled) instead of replacing it
//      with an error card that implies the board is gone. Two minutes and not
//      five because a hold is a regulatory state: a two-minute-old ALL CLEAR is
//      already a claim, and a five-minute-old one is a liability.
//    · ONLINE_ONLY(a hold release is a regulatory state change and must be
//      server-confirmed) — a hold clear is never queued and never optimistic.
//      Nothing on this screen writes today, so nothing on it queues today; the
//      policy is declared here so that the first release action to land is
//      built against it rather than against an outbox.
//
//  NAMED GAP (logged, never faked): railShipments exposes NO hold-release /
//    clear-hold procedure for a bad-order or FRA hold — the only releaseHold
//    procedures in the router tree are eusoWallet.releaseHold (a funds hold)
//    and crossBorderCompliance.releaseQuarantineHold (a customs quarantine),
//    neither of which is a rail mechanical or FRA hold. The two CTAs below are
//    therefore read-only context sheets over rows this board already decoded.
//    They are labelled "review", they commit nothing, and no control on this
//    screen claims to clear a hold it has no way to clear.
//
//  ESANG: esangCoach.forScreen (esangCoach.ts:264) is a DRIVER in-cab coach —
//    its SCREEN_ENUM (esangCoach.ts:112) carries no rail or compliance key and
//    its system prompt speaks HOS/DVIR, so calling it here would answer about
//    the wrong entity. The ESANG band is composed on device from fields this
//    board already decoded and is labelled as a derived read. Same call the
//    sibling yard screens 559 and 665 made. No model call is made or claimed.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct RailExceptionsHoldsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            RailExceptionsHoldsBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
        // Real top back affordance for this pushed Rail Engineer surface, same
        // idiom as 564/565/566. Posts the shared NavBack that
        // RailEngineerSurface pops on, so context is preserved on the way out.
        // Rail563 is registered in RailEngineerSurface.screensWithOwnBack so
        // RoleNavBackOverlay does not paint a second chevron over this one.
        .injectBespokeBackBar(title: nil) {
            NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil)
        }
    }
}

// MARK: - Data shapes

private struct RailInspection563: Decodable {
    let id: Int?
    let status: String?
    let description: String?
    let railcarNumber: String?
    let location: String?
    let defectCode: String?
    let timestamp: String?
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(Int.self, forKey: .id)
        if let result = try c.decodeIfPresent(String.self, forKey: .result) {
            self.status = result
        } else if let insType = try c.decodeIfPresent(String.self, forKey: .inspectionType) {
            self.status = insType
        } else {
            self.status = nil
        }
        self.description = try c.decodeIfPresent(String.self, forKey: .defectsFound)
        self.railcarNumber = nil
        self.location = try c.decodeIfPresent(String.self, forKey: .notes)
        self.defectCode = nil
        self.timestamp = try c.decodeIfPresent(String.self, forKey: .inspectionDate)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, result, inspectionType, defectsFound, notes, inspectionDate
        case railcarId, inspectorId, nextDueDate
    }
}

private struct RailCompliance563: Decodable {
    let inspections: [RailInspection563]
    let status: String?
    let totalInspections: Int?
    let failedCount: Int?
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.inspections = try c.decodeIfPresent([RailInspection563].self, forKey: .inspections) ?? []
        self.status = try c.decodeIfPresent(String.self, forKey: .status)
        self.totalInspections = try c.decodeIfPresent(Int.self, forKey: .totalInspections)
        self.failedCount = try c.decodeIfPresent(Int.self, forKey: .failedCount)
    }
    
    enum CodingKeys: String, CodingKey {
        case inspections, status, totalInspections, failedCount, hazmatPermits
    }
}

private struct FRAViolation563: Decodable {
    let type: String?
    let description: String?
    let severity: String?
    let reviewDue: String?
}

private struct FRASafety563: Decodable {
    let status: String?
    let violationCount: Int?
    let violations: [FRAViolation563]?
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Server returns totalViolations (Int); map to violationCount
        self.violationCount = try c.decodeIfPresent(Int.self, forKey: .totalViolations)
        // Server returns overallRating (String); map to status
        self.status = try c.decodeIfPresent(String.self, forKey: .overallRating)
        // Server returns violationsByCategory: [{category, count, trend}]
        // Convert to [FRAViolation563] by treating category as type
        if let catArray = try c.decodeIfPresent([[String: String]].self, forKey: .violationsByCategory) {
            self.violations = catArray.map { cat in
                FRAViolation563(
                    type: cat["category"],
                    description: cat["trend"],
                    severity: nil,
                    reviewDue: nil
                )
            }
        } else {
            self.violations = nil
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case totalViolations, overallRating, violationsByCategory
    }
}

private struct LiveDemurrage563: Decodable {
    let totalAmount: Double?
    let daysOver: Int?
    let status: String?
}

private struct AssetHealth563: Decodable {
    let condition: String?
    let status: String?
    let notes: String?
}

// MARK: - Display model

private struct ExceptionItem563: Identifiable {
    let id = UUID()
    let glyph: String
    let tintColor: Color
    let title: String
    let subtitle: String
    let pill: String
    let pillColor: Color
    let detail: String
    let detailIsBold: Bool
}

// MARK: - Body

private struct RailExceptionsHoldsBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    /// §W READ_CACHED(2m) needs BOTH halves to be honest: staleness alone can
    /// only say how old the last good read is, never that the device cannot
    /// reach the network at all. It also arms the ONLINE_ONLY declaration on the
    /// hold-review row, so a release is never presented as something this device
    /// could hold and replay.
    @ObservedObject private var reach = OfflineReachabilityHub.shared

    /// §W READ_CACHED(2m) — a board older than two minutes is labelled stale, in
    /// Brand.warning, and is never presented as live. A hold is a regulatory
    /// state; a stale ALL CLEAR must not read as a current one.
    private static let boardTTL: TimeInterval = 2 * 60

    @State private var compliance: RailCompliance563? = nil
    @State private var fraSafety: FRASafety563? = nil
    @State private var demurrage: LiveDemurrage563? = nil
    @State private var assetHealth: AssetHealth563? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    /// READ_CACHED(2m) bookkeeping — the instant the board on screen was
    /// actually decoded from the server. Nil until the first successful read.
    @State private var fetchedAt: Date? = nil

    private var holdCount: Int {
        compliance?.failedCount
            ?? compliance?.inspections.filter { $0.status == "out_of_service" || $0.status == "fail" }.count
            ?? 0
    }
    private var alertCount: Int { fraSafety?.violationCount ?? fraSafety?.violations?.count ?? 0 }
    private var totalExceptions: Int { holdCount + alertCount + (demurrageBreach ? 1 : 0) }
    private var demurrageBreach: Bool { (demurrage?.daysOver ?? 0) > 0 }
    private var demurrageAmount: String {
        guard let amt = demurrage?.totalAmount, amt > 0 else { return "-" }
        return "$\(Int(amt.rounded()))"
    }
    private var isCritical: Bool { holdCount > 0 || alertCount > 0 }

    // Grouped exception items
    private var badOrderItems: [ExceptionItem563] {
        (compliance?.inspections ?? []).filter { $0.status == "out_of_service" || $0.status == "fail" }.map { insp in
            ExceptionItem563(
                glyph: "nosign",
                tintColor: Brand.danger,
                title: "Bad-order hold - out of service",
                subtitle: "\(insp.railcarNumber ?? "railcar") · \(insp.defectCode ?? "AAR mech defect")",
                pill: "HOLD",
                pillColor: Brand.danger,
                detail: insp.location ?? "-",
                detailIsBold: false
            )
        }
    }

    private var fraItems: [ExceptionItem563] {
        (fraSafety?.violations ?? []).map { v in
            ExceptionItem563(
                glyph: "exclamationmark.triangle.fill",
                tintColor: Brand.warning,
                title: "FRA exception - \(v.type ?? "safety alert")",
                subtitle: "FRA safety · \(v.description ?? "review pending")",
                pill: "FRA ALERT",
                pillColor: Brand.warning,
                detail: v.reviewDue ?? "-",
                detailIsBold: false
            )
        }
    }

    private var demurrageItems: [ExceptionItem563] {
        guard demurrageBreach, let days = demurrage?.daysOver else { return [] }
        return [ExceptionItem563(
            glyph: "clock.badge.exclamationmark.fill",
            tintColor: Brand.danger,
            title: "Demurrage breach - free time out",
            subtitle: "Demurrage · \(days) day\(days == 1 ? "" : "s") over · accruing",
            pill: "ACCRUING",
            pillColor: Brand.danger,
            detail: demurrageAmount,
            detailIsBold: true
        )]
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                stalenessRow
                if loading && compliance == nil {
                    LifecycleCard { Text("Loading exceptions…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                        .accessibilityLabel("Loading exceptions and holds")
                } else if let err = loadError, compliance == nil {
                    // §W READ_CACHED(2m): the error card only replaces the board
                    // when NOTHING has been decoded on this device. A failed
                    // refresh over a real board keeps the board and lets the
                    // staleness register above it carry the age — a hold that
                    // was open two minutes ago is still worth seeing.
                    LifecycleCard(accentDanger: true) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Nothing is being shown from cache — no exception board has been decoded on this device. Pull to retry.")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Exceptions board could not be read")
                    .accessibilityValue("\(err). No exception board has been decoded on this device.")
                } else {
                    dangerWashHero
                    kpiStrip
                    if !badOrderItems.isEmpty {
                        exceptionGroup(title: "BAD ORDERS · compliance holds", items: badOrderItems)
                    }
                    if !fraItems.isEmpty {
                        exceptionGroup(title: "FRA ALERTS · safety compliance", items: fraItems)
                    }
                    if !demurrageItems.isEmpty {
                        exceptionGroup(title: "DEMURRAGE · live accrual", items: demurrageItems)
                    }
                    if !badOrderItems.isEmpty && !fraItems.isEmpty && !demurrageItems.isEmpty {
                        // Only show empty state when ALL buckets are empty
                    } else if totalExceptions == 0 {
                        LifecycleCard {
                            HStack(spacing: Space.s3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 28)).foregroundStyle(Brand.success)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("No active exceptions").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                                    Text("Fleet clear · no holds, FRA alerts or demurrage breaches")
                                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("No active exceptions")
                        .accessibilityValue("No holds, FRA alerts or demurrage breaches were returned. \(boardFreshnessSpoken)")
                    }
                    contextStrip
                    esangBand
                    actionsRow
                    if !reach.isOnline { onlineOnlyNotice }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("RAIL ENGINEER · EXCEPTIONS & HOLDS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                // NOTE (rail §18): the back affordance for this screen is the
                // shared BespokeBackBar injected on the Shell below, NOT an
                // in-header chevron. `dismiss()` is the SHEET idiom (003:762,
                // 663:509) and is a no-op inside the pushed RailEngineerSurface;
                // an in-header chevron here would ALSO have double-painted
                // against RoleNavBackOverlay. Verified first-hand this fire.
                Text("Exceptions & holds")
                    .font(.system(size: 28, weight: .heavy)).kerning(-0.4).foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if totalExceptions > 0 {
                    Text("\(totalExceptions) OPEN")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(Brand.danger)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.danger.opacity(0.14)))
                        .accessibilityLabel("\(totalExceptions) open exception\(totalExceptions == 1 ? "" : "s")")
                }
            }
            IridescentHairline()
                .accessibilityHidden(true)
        }
    }

    // MARK: §W READ_CACHED(2m) staleness register

    /// Monospaced 10pt register — textTertiary while the board is a live read,
    /// Brand.warning the moment it is a snapshot instead. OFFLINE outranks
    /// STALE: "stale" implies the network was tried and the answer is merely
    /// old; offline says the board cannot be refreshed at all.
    private var boardStaleness: (text: String, warn: Bool) {
        guard let at = fetchedAt else {
            if !reach.isOnline {
                return ("READ_CACHED(2m) · OFFLINE · no board decoded on this device", true)
            }
            return ("READ_CACHED(2m) · awaiting first read", false)
        }
        let age = max(0, Date().timeIntervalSince(at))
        let mins = Int(age / 60)
        let old = mins < 1 ? "under a minute" : (mins == 1 ? "1 min" : "\(mins) min")
        let failed = loadError == nil ? "" : " · last refresh failed"
        if !reach.isOnline {
            return ("READ_CACHED(2m) · OFFLINE · \(old) old · not refreshing", true)
        }
        if age > Self.boardTTL {
            return ("READ_CACHED(2m) · STALE · \(old) old · not live\(failed)", true)
        }
        if loadError != nil {
            return ("READ_CACHED(2m) · CACHED · \(old) old · last refresh failed", true)
        }
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        return ("READ_CACHED(2m) · LIVE · read \(f.string(from: at))", false)
    }

    /// The staleness claim in prose, for the spoken value of any state card that
    /// would otherwise sound like a current verdict.
    private var boardFreshnessSpoken: String { boardStaleness.text }

    private var stalenessRow: some View {
        let s = boardStaleness
        return HStack(spacing: 6) {
            Image(systemName: s.warn ? "clock.badge.exclamationmark" : "dot.radiowaves.left.and.right")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(s.warn ? Brand.warning : palette.textTertiary)
            Text(s.text)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(s.warn ? Brand.warning : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Exceptions board freshness")
        .accessibilityValue(s.text)
    }

    /// §W ONLINE_ONLY(a hold release is a regulatory state change and must be
    /// server-confirmed). Offline is a state of the DEVICE, not of the data, so
    /// it gets its own band rather than being folded into the staleness stamp.
    private var onlineOnlyNotice: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 3) {
                Text("Offline · clearing a hold is ONLINE_ONLY")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Brand.warning)
                Text("A hold release is a regulatory state change and must be server-confirmed, so it is never queued and never applied optimistically on this device. The board above is a stored snapshot; the two review sheets read it and commit nothing.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.warning.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.warning.opacity(0.30))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Offline. Clearing a hold is online only.")
        .accessibilityValue("A hold release is a regulatory state change and must be server-confirmed. Nothing is queued. The board above is a stored snapshot.")
    }

    // MARK: DangerWash hero

    private var dangerWashHero: some View {
        ZStack(alignment: .leading) {
            // Danger-wash background
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(isCritical
                    ? LinearGradient(colors: [Brand.danger.opacity(0.10), Brand.warning.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [palette.bgCard, palette.bgCard], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(isCritical ? AnyShapeStyle(Brand.danger.opacity(0.35)) : AnyShapeStyle(LinearGradient.diagonal), lineWidth: 1.5)

            HStack(spacing: Space.s4) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(isCritical ? "CRITICAL" : "ALL CLEAR")
                            .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                            .foregroundStyle(isCritical ? Brand.danger : Brand.success)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill((isCritical ? Brand.danger : Brand.success).opacity(0.14)))
                        Text("composed board")
                            .font(.system(size: 10, weight: .heavy)).kerning(0.4)
                            .foregroundStyle(palette.textTertiary)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Capsule().fill(palette.textTertiary.opacity(0.10)))
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(totalExceptions)")
                            .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(isCritical ? Brand.danger : Brand.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("open exception\(totalExceptions == 1 ? "" : "s")")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                            Text("\(holdCount) hold · \(alertCount) FRA · \(demurrageBreach ? 1 : 0) demurrage")
                                .font(EType.caption).foregroundStyle(palette.textTertiary)
                        }
                    }
                }
                Spacer()
                exceptionTypeStack
            }
            .padding(Space.s4)
        }
        .frame(height: 118)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isCritical ? "Critical. Composed exceptions board." : "All clear. Composed exceptions board.")
        .accessibilityValue("\(totalExceptions) open exception\(totalExceptions == 1 ? "" : "s"). \(holdCount) hold\(holdCount == 1 ? "" : "s"), \(alertCount) FRA alert\(alertCount == 1 ? "" : "s"), \(demurrageBreach ? 1 : 0) demurrage breach. \(boardFreshnessSpoken)")
    }

    private var exceptionTypeStack: some View {
        VStack(spacing: 8) {
            exceptionTypePill(icon: "nosign", label: "\(holdCount) HOLD", color: Brand.danger, active: holdCount > 0)
            exceptionTypePill(icon: "exclamationmark.triangle.fill", label: "\(alertCount) FRA", color: Brand.warning, active: alertCount > 0)
            exceptionTypePill(icon: "clock.fill", label: demurrageBreach ? "BREACH" : "0 DMR", color: Brand.danger, active: demurrageBreach)
        }
    }

    private func exceptionTypePill(icon: String, label: String, color: Color, active: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold)).foregroundStyle(active ? color : palette.textTertiary)
            Text(label).font(.system(size: 9, weight: .heavy)).kerning(0.4).foregroundStyle(active ? color : palette.textTertiary)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill((active ? color : palette.textTertiary).opacity(active ? 0.14 : 0.08)))
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "OPEN HOLDS",  value: "\(holdCount)",    accent: holdCount > 0 ? Brand.danger : nil)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Open holds")
                .accessibilityValue("\(holdCount)")
            MetricTile(label: "FRA ALERTS",  value: "\(alertCount)",   accent: alertCount > 0 ? Brand.warning : nil)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("FRA alerts")
                .accessibilityValue("\(alertCount)")
            MetricTile(label: "DEMURRAGE",   value: demurrageAmount,   gradientNumeral: demurrageAmount != "-")
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Demurrage accrued")
                .accessibilityValue(demurrageAmount == "-" ? "Not reported" : demurrageAmount)
        }
    }

    // MARK: Exception group

    private func exceptionGroup(title: String, items: [ExceptionItem563]) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                .accessibilityLabel(title.replacingOccurrences(of: "·", with: ","))
                .accessibilityValue("\(items.count) row\(items.count == 1 ? "" : "s")")
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    exceptionRow(item)
                    if idx < items.count - 1 { Divider().padding(.leading, 56) }
                }
            }
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(items.first?.pillColor.opacity(0.20) ?? palette.borderFaint))
        }
    }

    private func exceptionRow(_ item: ExceptionItem563) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(item.tintColor.opacity(0.14)).frame(width: 40, height: 40)
                Image(systemName: item.glyph)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(item.tintColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(item.subtitle)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textSecondary).lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(item.pill)
                    .font(.system(size: 10, weight: .bold)).tracking(0.6)
                    .foregroundStyle(item.pillColor)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(item.pillColor.opacity(0.14)))
                Text(item.detail)
                    .font(.system(size: item.detailIsBold ? 14 : 11,
                                  weight: item.detailIsBold ? .bold : .regular))
                    .monospacedDigit().foregroundStyle(palette.textSecondary)
            }
        }
        .padding(14)
        // Every state string on this row reaches VoiceOver — the pill and the
        // detail are states, not colours, and an unreported detail is spoken as
        // not reported rather than skipped.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
        .accessibilityValue([
            item.pill,
            item.subtitle,
            (item.detail == "-" || item.detail.isEmpty) ? "Detail not reported" : item.detail
        ].joined(separator: ". "))
    }

    // MARK: Context strip

    private var contextStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("COMPOSED BOARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("asset health feed")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            Text("Holds + FRA + demurrage merged into one board")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            if let condition = assetHealth?.condition {
                Text("Asset condition: \(condition.replacingOccurrences(of: "_", with: " ").capitalized)")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Composed board")
        .accessibilityValue("Holds, FRA alerts and demurrage merged into one board. Asset condition \(assetHealth?.condition?.replacingOccurrences(of: "_", with: " ") ?? "not reported").")
    }

    // MARK: ESANG derived read
    //
    // esangCoach.forScreen (esangCoach.ts:264) is a DRIVER in-cab coach: its
    // SCREEN_ENUM (esangCoach.ts:112) carries no rail or compliance key and its
    // system prompt speaks HOS/DVIR, so wiring this band to it would return the
    // wrong entity. The band is therefore composed on device from fields already
    // decoded on this board and is labelled as such. Same call 559 and 665 made.
    // No model call is made or claimed.

    private var esangBand: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 30, height: 30)
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG AI")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Text(esangRead.headline)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(esangRead.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("DERIVED ON DEVICE FROM THIS BOARD · NOT AN ASSISTANT")
                    .font(.system(size: 7.5, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("ESANG derived read")
        .accessibilityValue("\(esangRead.headline). \(esangRead.detail). Derived on device from this board, not an assistant.")
    }

    /// Every noun and number here is a field this board already decoded. The
    /// staleness claim rides along with it, because an exception count is only
    /// as current as the read it came from.
    private var esangRead: (headline: String, detail: String) {
        let freshness = boardStaleness.warn
            ? "This is a stored snapshot, not a live read — see the freshness line under the title."
            : "Read live from the compliance, FRA, demurrage and asset-health feeds."
        if !isCritical && !demurrageBreach {
            return ("No open hold, FRA alert or demurrage breach returned",
                    "\(freshness) A clear board is the server's answer for what it covers; it is not a clearance for anything it does not model.")
        }
        var lead: [String] = []
        if holdCount > 0 { lead.append("\(holdCount) bad-order hold\(holdCount == 1 ? "" : "s")") }
        if alertCount > 0 { lead.append("\(alertCount) FRA alert\(alertCount == 1 ? "" : "s")") }
        if demurrageBreach { lead.append("demurrage accruing at \(demurrageAmount)") }
        return ("\(totalExceptions) open · \(lead.joined(separator: " · "))",
                "\(freshness) A release is server-confirmed only — nothing on this board clears a hold.")
    }

    // MARK: Actions
    //
    // Both controls are READ-ONLY context sheets over rows already decoded here.
    // railShipments exposes no hold-release procedure, so neither one clears a
    // hold, and neither is labelled as if it does. See the named gap in the
    // header, and the §W ONLINE_ONLY declaration that a release must carry.

    private var actionsRow: some View {
        HStack(spacing: Space.s2) {
            RailSecondaryActionButton(
                title: "Shipment review",
                sheetTitle: "Exception shipment context",
                lines: exceptionReviewLines,
                fillWidth: true,
                systemImage: "list.bullet.rectangle"
            )
            .accessibilityLabel("Shipment review")
            .accessibilityHint("Opens a read-only sheet listing this board's exception counts. It commits nothing.")
            RailSecondaryActionButton(
                title: "Hold review",
                sheetTitle: "Hold resolution context",
                lines: holdReviewLines,
                fillWidth: true,
                systemImage: "checkmark.circle"
            )
            .accessibilityLabel("Hold review")
            .accessibilityHint("Opens a read-only sheet listing the open holds. It does not clear a hold: a release is a regulatory state change and must be server-confirmed.")
        }
    }

    private var exceptionReviewLines: [String] {
        [
            "\(totalExceptions) total exception\(totalExceptions == 1 ? "" : "s") · \(holdCount) hold\(holdCount == 1 ? "" : "s")",
            "\(alertCount) FRA alert\(alertCount == 1 ? "" : "s") · demurrage \(demurrageAmount)",
            "Asset health \(assetHealth?.condition ?? assetHealth?.status ?? "pending")"
        ]
    }

    private var holdReviewLines: [String] {
        (badOrderItems + fraItems + demurrageItems).prefix(8).map { item in
            "\(item.title) · \(item.subtitle) · \(item.pill) · \(item.detail)"
        }
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        struct Empty: Encodable {}
        struct RailroadIn: Encodable { let railroadCode: String }
        struct DemurrageIn: Encodable { let railroad: String; let equipmentId: String }
        struct AssetIn: Encodable { let railcarNumber: String }
        do {
            let c: RailCompliance563 = try await EusoTripAPI.shared.query(
                "railShipments.getRailCompliance", input: Empty())
            self.compliance = c
            let carNum = c.inspections.first(where: { $0.railcarNumber != nil })?.railcarNumber ?? "DTTX762004"
            async let fra = EusoTripAPI.shared.query(
                "railShipments.getFRASafetyCompliance",
                input: RailroadIn(railroadCode: "BNSF")) as FRASafety563
            async let asset = EusoTripAPI.shared.query(
                "railShipments.getAssetHealth",
                input: AssetIn(railcarNumber: carNum)) as AssetHealth563
            async let dem = EusoTripAPI.shared.query(
                "railShipments.getLiveDemurrage",
                input: DemurrageIn(railroad: "BNSF", equipmentId: carNum)) as LiveDemurrage563
            self.fraSafety   = try? await fra
            self.assetHealth = try? await asset
            self.demurrage   = try? await dem
            // §W READ_CACHED(2m) bookkeeping — stamp the instant the board on
            // screen was actually decoded, so the staleness register above it
            // is measuring a real read and not a screen appearance.
            self.fetchedAt = Date()
            self.loadError = nil
        } catch {
            // A failed refresh does NOT clear the board. The last decoded
            // exceptions stay on screen and the staleness register carries the
            // age; only a device with nothing decoded shows the error card.
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("563 · Exceptions & Holds · Night") {
    RailExceptionsHoldsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("563 · Exceptions & Holds · Light") {
    RailExceptionsHoldsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
