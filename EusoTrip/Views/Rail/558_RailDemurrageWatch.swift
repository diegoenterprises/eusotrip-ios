//
//  558_RailDemurrageWatch.swift
//  EusoTrip — Rail Engineer · Demurrage Watch (carrier fleet monitor).
//
//  Visual identity: "breach clock" — the hero ring encodes the share of the
//  listed cars the accrual engine is actually billing. Breached cars render
//  with dangerWash. Each row carries a compact accrual-state ring.
//
//  LIVE WIRING — every name verified against server source, none invented:
//    board + KPIs  <- railDemurrageAuto.dashboard   (railDemurrageAuto.ts:96)
//                     -> { summary{activeAccruals,totalChargesAccruing,
//                          disputesOpen,waiversPending}, perCarRunway[],
//                          forecastSeries[], topDwellReasons[], costliestYards[] }
//    Dispute CTA   <- railDemurrageAuto.createDispute (railDemurrageAuto.ts:314,
//                     MUTATION, confirm:true human gate, tenant-checked)
//
//  NOT USED, ON PURPOSE: railShipments.getLiveDemurrage (railShipments.ts:2162)
//    is the 001 Shipper-Home eSang TIP — it returns ONE row
//    ({railRef,headline,action,savings} | null, .limit(1) at :2190) and shares
//    ZERO keys with a fleet board. Decoding it here silently produced an
//    all-nil board that rendered $0 / 0 / green at 0% in every session.
//
//  §W OFFLINE: ONLINE_ONLY. This is a money surface — charge totals are never
//    served from cache (a stale demurrage figure is worse than none) and the
//    dispute commit is never queued for silent replay.
//
//  NAMED GAPS (reported, never faked on screen):
//    · perCarRunway carries no placement timestamp and no dwell hours, so
//      hours-to-free-time-expiry — and therefore any AT RISK verdict — is not
//      derivable. The screen says so instead of guessing.
//    · dashboard falls back to zeros when company scope or the SQL rollup is
//      unavailable (railDemurrageAuto.ts:126-131) and ships no flag telling
//      that apart from a genuinely clean board. The screen discloses it.
//

import SwiftUI

struct RailDemurrageWatchScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailDemurrageWatchBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (railDemurrageAuto.dashboard — verbatim server shape)

/// One entry of `perCarRunway`, built at railDemurrageAuto.ts:157-170 from
/// `WHERE rs.companyId = ? AND dm.status = 'accruing' ORDER BY dm.totalCharge
/// DESC LIMIT 50`. The server's own comment at :161 names `demurrageId` as the
/// id a per-car "Dispute" CTA passes to `createDispute`.
///
/// CAUTION, load-bearing: the server coerces NULL → 0 on `freeTimeHours` (:164)
/// and `chargeableHours` (:165), so a 0 in either field is AMBIGUOUS —
/// "genuinely zero" and "column was NULL" arrive identically. Nothing on this
/// screen reads a bare 0 as a verdict; see `risk(_:)`.
private struct DemurrageRunwayCar558: Decodable, Identifiable {
    let demurrageId: Int?
    let railcarNumber: String?
    let freeTimeHours: Double?
    let chargeableHours: Double?
    let ratePerHour: Double?
    let usdToday: Double?
    let usdProjected: Double?

    /// Deterministic — never a fresh UUID, which would churn the ForEach.
    var id: String { "\(demurrageId.map(String.init) ?? "-")·\(railcarNumber ?? "-")" }
}

/// `dashboard.summary` (railDemurrageAuto.ts:179-188). Same four keys the 641
/// decoder already ships against this procedure.
private struct DemurrageSummary558: Decodable {
    let activeAccruals: Int?
    let totalChargesAccruing: Double?
    let disputesOpen: Int?
    let waiversPending: Int?
}

private struct DemurrageDashboard558: Decodable {
    let summary: DemurrageSummary558?
    let perCarRunway: [DemurrageRunwayCar558]?
}

private struct RailDemurrageWatchBody: View {
    @Environment(\.palette) private var palette
    /// §W ONLINE_ONLY. Money surface: charge totals are never served from cache
    /// and the dispute commit is never queued.
    @ObservedObject private var reach = OfflineReachabilityHub.shared
    @State private var board: DemurrageDashboard558? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    /// The `rail_demurrage.id` the Dispute CTA files against. Nil ⇒ fall back
    /// to the costliest billing car (perCarRunway is ORDER BY totalCharge DESC).
    @State private var disputeTargetId: Int? = nil
    @State private var filing = false
    @State private var fileAck: String? = nil
    @State private var fileError: String? = nil

    /// Three states, never two. `.atRisk` is deliberately ABSENT — see
    /// `atRiskUnavailableNote`; the feed cannot support that verdict.
    private enum Risk { case clear, breached, unknown }

    /// The verdict comes from the accrual engine's OWN fields, never a default.
    /// · any chargeable hour or any dollar on the charge ⇒ it is billing now.
    /// · a 0 only reads CLEAR when the row reported BOTH figures and carries a
    ///   real free-time term — the server collapses NULL → 0
    ///   (railDemurrageAuto.ts:164-165), so a bare 0 proves nothing.
    /// · anything else is UNKNOWN, and is drawn as UNKNOWN.
    private func risk(_ c: DemurrageRunwayCar558) -> Risk {
        if (c.chargeableHours ?? 0) > 0 || (c.usdToday ?? 0) > 0 { return .breached }
        guard let chargeable = c.chargeableHours, chargeable == 0,
              c.usdToday != nil,
              let free = c.freeTimeHours, free > 0 else { return .unknown }
        return .clear
    }

    private func riskColor(_ r: Risk) -> Color {
        switch r {
        case .clear:    return Brand.success
        case .breached: return Brand.danger
        case .unknown:  return Brand.warning
        }
    }

    private func riskLabel(_ r: Risk) -> String {
        switch r {
        case .clear:    return "CLEAR"
        case .breached: return "BREACHED"
        case .unknown:  return "UNKNOWN"
        }
    }

    private var cars: [DemurrageRunwayCar558] { board?.perCarRunway ?? [] }
    private var breachedCars: [DemurrageRunwayCar558] { cars.filter { risk($0) == .breached } }
    private var unknownCars: [DemurrageRunwayCar558] { cars.filter { risk($0) == .unknown } }

    /// Breach SHARE of the listed cars — the only fleet fraction this feed can
    /// support. It is NOT an accrual-vs-free-time position: `perCarRunway`
    /// carries no placement time, so per-car dwell is genuinely unknown.
    /// Nil while nothing is listed, so the ring reads UNKNOWN, not green zero.
    private var breachShare: Double? {
        guard !cars.isEmpty else { return nil }
        return Double(breachedCars.count) / Double(cars.count)
    }

    /// Green is reserved for a board that is BOTH fully reported and clear.
    /// One unknown car is enough to withhold the verdict.
    private var breachClockColor: Color {
        guard let share = breachShare else { return Brand.warning }
        if share > 0 { return Brand.danger }
        return unknownCars.isEmpty ? Brand.success : Brand.warning
    }

    private var hasBreach: Bool { !breachedCars.isEmpty }

    /// Grouped whole-dollar formatter. Nil in ⇒ em-dash out. A missing money
    /// figure is NEVER rendered as $0.
    private func usd(_ value: Double?) -> String {
        guard let value else { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: Int(value))) ?? "\(Int(value))")
    }

    private func count(_ value: Int?) -> String { value.map(String.init) ?? "—" }

    /// SUPPRESS THE VERDICT, stated in one line so the operator knows exactly
    /// which input is missing and what therefore cannot be judged.
    private var atRiskUnavailableNote: String {
        "AT RISK is not shown: the accrual feed reports chargeable hours, not placement time, so hours-to-expiry cannot be derived."
    }

    /// An all-zero board is exactly what the server also returns when company
    /// scope can't be resolved or the SQL rollup throws
    /// (railDemurrageAuto.ts:105-131), and it ships no flag telling the two
    /// apart. We refuse to call that a clean board.
    private var boardIsAllZero: Bool {
        cars.isEmpty
            && (board?.summary?.activeAccruals ?? 0) == 0
            && (board?.summary?.totalChargesAccruing ?? 0) == 0
            && (board?.summary?.disputesOpen ?? 0) == 0
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading demurrage…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    breachClockHero
                    kpiStrip
                    if boardIsAllZero { unresolvedBoardNote }
                    if hasBreach { breachBanner }
                    watchList
                    ctaRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Eyebrow + headline

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("RAIL ENGINEER · DEMURRAGE WATCH").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Demurrage watch")
                .font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Breach clock hero

    private var breachClockHero: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard)
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)

            HStack(spacing: Space.s4) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("FLEET ACCRUAL")
                        .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(palette.textTertiary.opacity(0.10)))
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(usd(board?.summary?.totalChargesAccruing))
                            .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("accruing now")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                            Text(heroSubline)
                                .font(EType.caption).foregroundStyle(palette.textTertiary)
                        }
                    }
                }
                Spacer()
                BreachClockRing558(fraction: breachShare,
                                   color: breachClockColor,
                                   caption: breachRingCaption)
            }
            .padding(Space.s4)
        }
        .frame(height: 120)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fleet demurrage accruing")
        .accessibilityValue("\(usd(board?.summary?.totalChargesAccruing)) accruing. \(breachRingAccessibility)")
    }

    private var heroSubline: String {
        cars.isEmpty
            ? "no cars listed · demurrage engine"
            : "\(cars.count) listed car\(cars.count == 1 ? "" : "s") · demurrage engine"
    }

    /// DISCLOSE THE BASIS: the ring is the breached SHARE of listed cars, not
    /// an accrual position, so it is labelled "breached / listed", not a %.
    private var breachRingCaption: String {
        breachShare == nil ? "—" : "\(breachedCars.count)/\(cars.count)"
    }

    private var breachRingAccessibility: String {
        guard breachShare != nil else { return "Breach share unknown — no cars listed." }
        return "\(breachedCars.count) of \(cars.count) listed cars are billing now. \(unknownCars.count) have an unknown accrual state."
    }

    // MARK: KPI strip

    // Every tile is now the figure the server actually reports. The old
    // "AT RISK" tile is gone: the accrual feed has no placement time, so the
    // hours-to-expiry it claimed to summarise does not exist. Its slot carries
    // the company's open-dispute count, which IS reported.
    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "ACCRUING", value: usd(board?.summary?.totalChargesAccruing), gradientNumeral: true)
                .accessibilityLabel("Charges accruing")
                .accessibilityValue(usd(board?.summary?.totalChargesAccruing))
            MetricTile(label: "CARS", value: count(board?.summary?.activeAccruals), accent: Brand.warning)
                .accessibilityLabel("Cars accruing")
                .accessibilityValue(count(board?.summary?.activeAccruals))
            MetricTile(label: "DISPUTED", value: count(board?.summary?.disputesOpen), accent: Brand.danger)
                .accessibilityLabel("Open disputes")
                .accessibilityValue(count(board?.summary?.disputesOpen))
        }
    }

    // MARK: Unresolved-board disclosure

    private var unresolvedBoardNote: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Brand.warning)
            Text("Board reads empty. The accrual service returns these same zeros when your company scope or its rollup is unavailable, and sends no flag to tell those apart — so this is not a confirmed clear board.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .background(Brand.warning.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.warning.opacity(0.30)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Board state unresolved")
        .accessibilityValue("Empty board. Not a confirmed clear board — the accrual service returns identical zeros when scope or its rollup is unavailable.")
    }

    // MARK: Breach banner

    private var breachBanner: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold)).foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(breachedCars.count) listed car\(breachedCars.count == 1 ? "" : "s") past free time")
                    .font(.system(size: 14, weight: .heavy)).foregroundStyle(Brand.danger)
                Text("Charges accruing. Request early release, or file a dispute below.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            Spacer()
        }
        .padding(Space.s3)
        .background(Brand.danger.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.danger.opacity(0.30)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Breach warning")
        .accessibilityValue("\(breachedCars.count) listed cars are past free time and billing now. Request early release, or file a dispute.")
    }

    // MARK: Watch list

    private var watchList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ACCRUING CARS · demurrage engine")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            Text(atRiskUnavailableNote)
                .font(EType.caption).foregroundStyle(palette.textTertiary)
                .accessibilityLabel("Why at risk is not shown")
                .accessibilityValue(atRiskUnavailableNote)
            if cars.isEmpty {
                Text("No accruing cars returned for your company.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(cars) { c in carRow(c) }
                }
            }
        }
    }

    private func carRow(_ c: DemurrageRunwayCar558) -> some View {
        let r = risk(c)
        let color = riskColor(r)
        // 1 = the engine is billing · 0 = inside free time · nil = the row did
        // not report enough to say. NEVER a computed accrued/free position:
        // perCarRunway carries no placement time, so per-car dwell is unknown.
        let frac: Double?
        switch r {
        case .breached: frac = 1
        case .clear:    frac = 0
        case .unknown:  frac = nil
        }
        let isTarget = (c.demurrageId != nil && c.demurrageId == disputeTargetId)
        let freeText = (c.freeTimeHours ?? 0) > 0
            ? "\(Int(c.freeTimeHours ?? 0))h free"
            : "free time not reported"
        let chargeableText = c.chargeableHours.map { "\(Int($0))h chargeable" } ?? "chargeable hours not reported"
        let rateText = c.ratePerHour.map { "\(usd($0))/h" } ?? "rate not reported"

        return Button {
            if c.demurrageId != nil { disputeTargetId = c.demurrageId }
        } label: {
            HStack(spacing: Space.s3) {
                CarAccrualRing558(fraction: frac, color: color, breached: r == .breached)
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.railcarNumber ?? "car not reported")
                        .font(.system(size: 12, weight: .bold)).monospaced().foregroundStyle(palette.textPrimary)
                    Text("\(freeText) · \(chargeableText) · \(rateText)")
                        .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(usd(c.usdToday))
                        .font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(color)
                    Text(riskLabel(r))
                        .font(.system(size: 9, weight: .heavy)).foregroundStyle(color)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(color.opacity(0.14)))
                }
            }
            .padding(Space.s3)
            .frame(minHeight: 44)
            .background(r == .breached ? Brand.danger.opacity(0.06) : palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(isTarget
                                    ? Brand.warning
                                    : (r == .breached ? Brand.danger.opacity(0.30) : palette.borderFaint),
                                  lineWidth: isTarget ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(c.demurrageId == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Car \(c.railcarNumber ?? "not reported")")
        .accessibilityValue("\(riskLabel(r)). \(usd(c.usdToday)) accrued. \(freeText). \(chargeableText). \(rateText).\(isTarget ? " Selected for dispute." : "")")
        .accessibilityHint(c.demurrageId == nil
                           ? "No charge id on this row — it cannot be disputed."
                           : "Double tap to select this charge for dispute.")
    }

    // MARK: CTAs — report (real, on-device) + Dispute (real mutation)

    private var reportLines: [String] {
        var lines = [
            "Cars accruing (company): \(count(board?.summary?.activeAccruals))",
            "Charges accruing: \(usd(board?.summary?.totalChargesAccruing))",
            "Open disputes: \(count(board?.summary?.disputesOpen))",
            "Waivers pending: \(count(board?.summary?.waiversPending))",
            "Cars listed on this board: \(cars.count)",
            "Breached (billing now): \(breachedCars.count)",
            "Unknown accrual state: \(unknownCars.count)",
            atRiskUnavailableNote
        ]
        for c in cars.prefix(12) {
            let free = (c.freeTimeHours ?? 0) > 0 ? "\(Int(c.freeTimeHours ?? 0))h free" : "free time not reported"
            lines.append("\(c.railcarNumber ?? "car not reported"): \(riskLabel(risk(c))) · \(free) · \(usd(c.usdToday)) accrued")
        }
        return lines
    }

    /// The charge the Dispute CTA files against: the tapped row, else the
    /// costliest billing car. Only a car the engine is actually billing can be
    /// disputed — there is no charge to contest on a car inside free time.
    private var disputeTarget: DemurrageRunwayCar558? {
        if let id = disputeTargetId, let hit = cars.first(where: { $0.demurrageId == id }) { return hit }
        return breachedCars.first
    }

    /// HONEST DISABLE — the control stays visible and always names its reason.
    private var disputeBlockedReason: String? {
        if !reach.isOnline {
            return "Offline · filing a dispute is ONLINE_ONLY. It moves a billable charge to disputed, so it is never queued for silent replay."
        }
        if disputeTarget?.demurrageId == nil {
            return "Nothing to dispute yet — no listed car is being billed. Tap a BREACHED row to pick a charge."
        }
        return nil
    }

    private var ctaRow: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                RailSecondaryActionButton(
                    title: "Demurrage report",
                    sheetTitle: "Demurrage watch report",
                    lines: reportLines,
                    fillWidth: true,
                    systemImage: "square.and.arrow.up"
                )
                .frame(maxWidth: .infinity)

                Button(action: { Task { await fileDispute() } }) {
                    HStack(spacing: 6) {
                        if filing { ProgressView().controlSize(.small).tint(.white) }
                        Text("Dispute")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(filing || disputeBlockedReason != nil)
                .opacity(disputeBlockedReason == nil ? 1 : 0.45)
                .accessibilityLabel("File demurrage dispute")
                .accessibilityValue(disputeBlockedReason
                                    ?? "Files against \(disputeTarget?.railcarNumber ?? "the costliest billing car"), \(usd(disputeTarget?.usdToday)) accrued.")
            }

            if let reason = disputeBlockedReason {
                Text(reason)
                    .font(EType.caption).foregroundStyle(Brand.warning)
                    .accessibilityLabel("Dispute unavailable")
                    .accessibilityValue(reason)
            } else if let t = disputeTarget {
                Text("Files against \(t.railcarNumber ?? "the selected charge") · \(usd(t.usdToday)) accrued")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            if let ack = fileAck {
                Text(ack)
                    .font(EType.caption).foregroundStyle(Brand.success)
                    .accessibilityLabel("Dispute filed")
                    .accessibilityValue(ack)
            }
            if let err = fileError {
                Text(err)
                    .font(EType.caption).foregroundStyle(Brand.danger)
                    .accessibilityLabel("Dispute failed")
                    .accessibilityValue(err)
            }
        }
    }

    // MARK: Data

    /// §W ONLINE_ONLY, enforced and not merely declared. A demurrage figure is
    /// money; a stale cached charge total is worse than none, so the read is
    /// refused offline with the reason stated.
    private func load() async {
        loading = true; loadError = nil
        struct Empty: Encodable {}
        guard reach.isOnline else {
            loadError = "Offline · demurrage figures are ONLINE_ONLY. Charge totals are never served from cache, because a stale figure is worse than none."
            loading = false
            return
        }
        do {
            let dash: DemurrageDashboard558 = try await EusoTripAPI.shared.query(
                "railDemurrageAuto.dashboard", input: Empty())
            self.board = dash
            // Re-point the dispute target if the selected charge left the board.
            if let id = disputeTargetId,
               !(dash.perCarRunway ?? []).contains(where: { $0.demurrageId == id }) {
                disputeTargetId = nil
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// Filed body — every line is a decoded server field, composed on device.
    /// Clipped to the server's `notes` ceiling (z.string().max(2000)).
    private var disputeNotes: String {
        guard let t = disputeTarget else { return "Filed from the rail demurrage watch board." }
        var lines = ["Filed from the rail demurrage watch board."]
        lines.append("Car: \(t.railcarNumber ?? "not reported")")
        lines.append((t.freeTimeHours ?? 0) > 0
                     ? "Free time on file: \(Int(t.freeTimeHours ?? 0))h"
                     : "Free time on file: not reported")
        lines.append(t.chargeableHours.map { "Chargeable hours: \(Int($0))" } ?? "Chargeable hours: not reported")
        lines.append(t.ratePerHour.map { "Rate: \(usd($0)) per hour" } ?? "Rate: not reported")
        lines.append("Accrued to date: \(usd(t.usdToday))")
        lines.append("Projected at +24h: \(usd(t.usdProjected))")
        return String(lines.joined(separator: "\n").prefix(2000))
    }

    /// ONLINE_ONLY commit against `railDemurrageAuto.createDispute`
    /// (railDemurrageAuto.ts:314 — MUTATION, `confirm:true` human gate,
    /// tenant-checked server-side to the charge's owning company).
    ///
    /// `reason` is filed as "other", the enum member that asserts nothing: this
    /// board collects no rationale from the operator, and picking
    /// "service_failure" here would attribute fault to a carrier on no
    /// evidence. The measured basis goes in `notes`; 570 is the screen that
    /// carries a real reason picker.
    private func fileDispute() async {
        guard reach.isOnline else {
            fileError = "Offline · dispute not filed. This commit is ONLINE_ONLY."
            return
        }
        guard let demurrageId = disputeTarget?.demurrageId else {
            fileError = "No billing charge selected — there is nothing to dispute."
            return
        }
        filing = true; fileAck = nil; fileError = nil
        defer { filing = false }

        struct DisputeIn: Encodable {
            let confirm: Bool
            let demurrageId: Int
            let reason: String
            let notes: String?
            let requestedWaiverAmount: Double?
        }
        struct DisputeOut: Decodable {
            let disputeId: String?
            let status: String?
        }

        // Only ask for a waiver when a real accrued figure exists; the server
        // clamps it to 0…9_999_999 and treats it as optional.
        let accrued: Double? = disputeTarget?.usdToday
        let waiver: Double? = (accrued ?? 0) > 0 ? accrued : nil

        do {
            let out: DisputeOut = try await EusoTripAPI.shared.mutation(
                "railDemurrageAuto.createDispute",
                input: DisputeIn(confirm: true,
                                 demurrageId: demurrageId,
                                 reason: "other",
                                 notes: disputeNotes,
                                 requestedWaiverAmount: waiver))
            fileAck = "Dispute \(out.disputeId ?? "filed") · \(out.status ?? "submitted")"
            await load()
        } catch {
            // Surfaced, never swallowed — the operator must never see a dispute
            // that was not actually filed.
            fileError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Breach clock ring (hero)
//
// The arc sweeps from empty up to the REAL breached share of the listed cars
// using a decelerating settle spring. When any listed car is billing, the ring
// carries an ambient breathing glow — a seamless continuous loop signalling
// live, ongoing charge accrual. Under Reduce Motion the ring snaps straight to
// its final state with no sweep and no pulse.
//
// A nil fraction means the share is genuinely unknown (nothing listed). That
// renders as a DASHED track with no arc and no hand — never a full green ring
// sitting at zero, which is what an unknown board used to look like.
private struct BreachClockRing558: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Real breached share (0…1) of the listed cars. Nil ⇒ unknown.
    let fraction: Double?
    let color: Color
    /// Text drawn inside the ring — "breached/listed", or an em-dash.
    let caption: String

    /// The fraction the arc currently animates toward. Starts at 0 so the ring
    /// winds up into its true position on appear.
    @State private var shown: Double = 0
    /// Drives the ambient breach pulse (continuous, breached-only).
    @State private var breathing = false

    private var isBreached: Bool { (fraction ?? 0) > 0 }
    private var isUnknown: Bool { fraction == nil }

    var body: some View {
        let pulse = isBreached && !reduceMotion
        return ZStack {
            // Track — dashed while the share is unknown.
            Circle()
                .stroke(color.opacity(0.16),
                        style: isUnknown
                            ? StrokeStyle(lineWidth: 7, dash: [3, 4])
                            : StrokeStyle(lineWidth: 7))
                .frame(width: 72, height: 72)
            if !isUnknown {
                // Filled arc — clock-style trim, bound to the real share
                Circle()
                    .trim(from: 0, to: shown)
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 72, height: 72)
                    .shadow(color: pulse ? color.opacity(breathing ? 0.55 : 0.15) : .clear,
                            radius: pulse ? (breathing ? 7 : 3) : 0)
                // Clock hand tick mark — tracks the same real share
                Rectangle()
                    .fill(color)
                    .frame(width: 2, height: 10)
                    .offset(y: -26)
                    .rotationEffect(.degrees(shown * 360 - 90))
            }
            VStack(spacing: 1) {
                Image(systemName: isUnknown ? "questionmark" : "clock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(caption)
                    .font(.system(size: 9, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(color)
            }
            // Scale breathing on the whole ring while breached.
            .scaleEffect(pulse ? (breathing ? 1.0 : 0.97) : 1.0)
        }
        .onAppear { settle() }
        .onChange(of: fraction) { _, _ in settle() }
    }

    private func settle() {
        let target = fraction ?? 0
        if reduceMotion {
            shown = target
            breathing = false
            return
        }
        // Decelerating settle — the ring winds up to its true position.
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            shown = target
        }
        // Ambient breach pulse: seamless autoreversing loop (start == end).
        if isBreached {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                breathing = true
            }
        } else {
            breathing = false
        }
    }
}

// MARK: - Per-car accrual ring (list row)
//
// Each row's compact ring settles to that car's REAL billing state with a
// decelerating spring. Reduce Motion snaps straight to final.
//
// The accrual feed carries no placement time, so a per-car accrued/free
// position does not exist and is never drawn. The ring is a three-state glyph:
//   1   the engine is billing this car (full arc, exclamation)
//   0   inside free time (empty arc, clock)
//   nil the row did not report enough to say (DASHED track, question mark)
private struct CarAccrualRing558: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 1 · 0 · nil — see above. Nil never renders as an empty green ring.
    let fraction: Double?
    let color: Color
    let breached: Bool

    @State private var shown: Double = 0

    private var isUnknown: Bool { fraction == nil }

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.18),
                        style: isUnknown
                            ? StrokeStyle(lineWidth: 5, dash: [3, 3])
                            : StrokeStyle(lineWidth: 5))
                .frame(width: 44, height: 44)
            if !isUnknown {
                Circle()
                    .trim(from: 0, to: shown)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 44, height: 44)
            }
            Image(systemName: isUnknown ? "questionmark" : (breached ? "exclamationmark" : "clock"))
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(color)
        }
        .onAppear { settle() }
        .onChange(of: fraction) { _, _ in settle() }
    }

    private func settle() {
        let target = fraction ?? 0
        if reduceMotion {
            shown = target
            return
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            shown = target
        }
    }
}

#Preview("558 · Rail Demurrage Watch · Night") { RailDemurrageWatchScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("558 · Rail Demurrage Watch · Light") { RailDemurrageWatchScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
