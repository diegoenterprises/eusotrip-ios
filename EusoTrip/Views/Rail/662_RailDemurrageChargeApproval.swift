//
//  662_RailDemurrageChargeApproval.swift
//  EusoTrip — Rail Engineer · Demurrage Charge Approval (carrier money band).
//
//  PURPOSE: unfreeze demurrage money. A filed dispute flips its charge to
//  'disputed', which blocks the charge from ever reaching 'settled' — so every
//  open dispute is a pile of carrier cash sitting still. This screen is the
//  first and only client surface in the product that can read that frozen pile
//  and record the verdict that releases it.
//
//  Verbatim port of 05 Rail/Light-SVG/662 Rail Demurrage Charge Approval.svg
//  (Light + Dark). Register held vector-for-vector: ✦ eyebrow + right-hand
//  monospaced caption → back chevron + "Demurrage" breadcrumb → gradient hero
//  figure + subline → iridescent hairline → 3-cell posture strip → decision
//  queue → footnote → FREE-TIME REGIME · BY COUNTRY strip → CTA pair → nav.
//
//  ARCHETYPE = MONEY / adjudication queue. Not a list and not a detail card:
//  every row is a case file carrying the amount at stake, the dispute reason,
//  the requested waiver against the charge total, a FREEZE METER showing how
//  long that money has been immobilised, and a two-way verdict (approve waiver
//  / deny) that moves real money in opposite directions. The SVG demanded it —
//  it draws a per-row decision pill and an amount column, which is an
//  adjudication docket, not a feed.
//
//  ── WIRING MANIFEST ───────────────────────────────────────────────────────
//  Posture strip · hero count · accruing runway
//      → railDemurrageAuto.dashboard
//        EXISTS railDemurrageAuto.ts:47 (query) · protectedProcedure · no input
//        reads summary.disputesOpen · summary.totalChargesAccruing · perCarRunway[]
//  Decision docket (rows, freeze meter, at-stake amounts, waiver asks)
//      → railDemurrageAuto.listOpenDisputes
//        EXISTS railDemurrageAuto.ts:351 (query) · roleProcedure(ADMIN, SUPER_ADMIN)
//        in {limit?: 1..200} · out [{disputeId, demurrageId, reason, notes,
//        requestedWaiverAmount, status, submittedBy, submittedAt, ageDays,
//        shipmentId, shipmentNumber, chargeStatus, chargeTotal, chargeableHours,
//        ratePerHour, placedAt, releasedAt}]
//  "Approve waiver" / "Deny" / "Adjudicate oldest"
//      → railDemurrageAuto.resolveDispute
//        EXISTS railDemurrageAuto.ts:422 (MUTATION) · roleProcedure(ADMIN, SUPER_ADMIN)
//        in {confirm: literal true, disputeId, decision: approved|denied,
//        resolutionNotes?: max 2000} · out {success, disputeId, decision, chargeStatus}
//  FREE-TIME REGIME · BY COUNTRY cells (free hours + rate per country)
//      → railDemurrageAuto.calculateAccrual
//        EXISTS railDemurrageAuto.ts:151 (query) · protectedProcedure
//        probed once per country so the regime constants at railDemurrageAuto.ts:17-18
//        are READ from the server, never typed into this file.
//  "Approve all" / bulk clear
//      → STUB · named-gap. railDemurrageAuto.approveCharges DOES NOT EXIST.
//        The SVG <desc> names it; the desc is WRONG and the router wins.
//        Drawn as a stated limitation in the footnote, never as a live button.
//        demurrageCharges.approveCharge (demurrageCharges.ts:538) and
//        demurrageCharges.batchApprove (demurrageCharges.ts:574) are NOT usable
//        here: their chargeId is a truck timer key parsed as DMR-<loadId>-<timerId>
//        (demurrageCharges.ts:100) — a rail_demurrage.id would 400 BAD_REQUEST.
//        Deliberately unwired.
//
//  DB WRITE: resolveDispute updates demurrage_disputes (status/resolvedBy/
//  resolvedAt/notes) at railDemurrageAuto.ts:439 and rail_demurrage.status at
//  railDemurrageAuto.ts:446 — approved ⇒ 'waived' (money forgiven), denied ⇒
//  'accruing' (billable again).
//  AUDIT: blockchainAuditTrail row, eventType "rail.demurrage_dispute_resolved",
//  written at railDemurrageAuto.ts:449.
//  BROADCAST: no WS_EVENTS member covers this verdict. The router emits a
//  locally-cast frame "rail:demurrage_dispute_resolved" to the filer's user
//  channel and the company channel (railDemurrageAuto.ts:496-523) plus a durable
//  notifications row (railDemurrageAuto.ts:540). WS_EVENTS.CHARGE_APPROVED and
//  WS_EVENTS.DISPUTE_OPENED are BOTH ABSENT from the shared vocabulary — this
//  screen therefore re-reads rather than subscribing.
//  RBAC: the board read and the verdict are both ADMIN / SUPER_ADMIN. A
//  RAIL_ENGINEER is denied by roleProcedure (_core/trpc.ts:165) and receives
//  FORBIDDEN, surfaced by the client as EusoTripAPIError.forbidden
//  (Services/EusoTripAPI.swift:1809). That is a designed state here, not an
//  error blob: the docket locks, the reason and the qualifying roles are named
//  on screen, and the freeze posture the engineer CAN read (dashboard, which is
//  protectedProcedure) still renders so they can see the money standing still.
//
//  transportMode = rail. Country is content, never a fork: the FREE-TIME REGIME
//  strip carries US 48h · CA 48h · MX 24h with each country's rate and currency
//  (USD · CAD · MXN), every hour and rate read back from calculateAccrual rather
//  than typed. A docket row whose ratePerHour matches a regime's rate flags that
//  regime — the row is not claimed to belong to that country, because
//  listOpenDisputes carries no country column and US and CA share a rate.
//
//  OFFLINE POLICY (Encyclopedia v2): READ_CACHED(5m) for the whole board — no
//  rail read is in the offline allow-list (Services/EusoTripAPI.swift:1684, six
//  paths, none rail), so a failed read keeps the last decoded figures in memory
//  and the header right register flips from a monospaced "LIVE · HH:mm" to
//  "OFFLINE · CACHED Nm" / "STALE Nm" in Brand.warning — the honesty law's
//  visibly-distinct cached state. The 5m ttl is the real threshold the code
//  enforces: `freshness` stamps STALE the moment the last good load is five
//  minutes old. The cache is in-memory only (last-good state, never persisted),
//  so a cold launch reads live or shows nothing — it never serves a stale board
//  it cannot date. Both verdicts are ONLINE_ONLY because each one
//  moves money in a different direction; the decision buttons and the confirm
//  button disable with the reason printed next to them instead of queueing, and
//  nothing is ever silently swallowed.
//
//  Makes the job easier: a rail engineer or adjudicator can see, in one screen,
//  exactly how much carrier money is frozen behind open demurrage disputes and
//  how long each pile has been stuck, then release it with a recorded verdict —
//  work that had no surface anywhere in the product before this screen.
//

import SwiftUI

// MARK: - Decodable models (mirror railDemurrageAuto.ts return shapes)

/// One row of `railDemurrageAuto.listOpenDisputes` (railDemurrageAuto.ts:386-408).
/// `disputeId` is the stable identity; everything else optional so a partially
/// joined row (the router LEFT-joins deliberately) still renders.
private struct OpenDispute662: Decodable, Identifiable {
    let id: Int
    let demurrageId: Int?
    let companyId: Int?
    let reason: String?
    let notes: String?
    let requestedWaiverAmount: Double?
    let status: String?
    let submittedBy: Int?
    let submittedAt: String?
    let ageDays: Int?
    let shipmentId: Int?
    let shipmentNumber: String?
    let chargeStatus: String?
    let chargeTotal: Double?
    let chargeableHours: Double?
    let ratePerHour: Double?
    let placedAt: String?
    let releasedAt: String?

    private enum CodingKeys: String, CodingKey {
        case id = "disputeId"
        case demurrageId, companyId, reason, notes, requestedWaiverAmount, status
        case submittedBy, submittedAt, ageDays, shipmentId, shipmentNumber
        case chargeStatus, chargeTotal, chargeableHours, ratePerHour, placedAt, releasedAt
    }
}

/// `railDemurrageAuto.dashboard` → summary block (railDemurrageAuto.ts:130-139).
private struct DemurrageSummary662: Decodable {
    let activeAccruals: Int?
    let totalChargesAccruing: Double?
    let disputesOpen: Int?
    let waiversPending: Int?
}

/// `railDemurrageAuto.dashboard` → one `perCarRunway` entry (railDemurrageAuto.ts:111-120).
private struct RunwayCar662: Decodable, Identifiable {
    let id: Int
    let railcarNumber: String?
    let freeTimeHours: Double?
    let chargeableHours: Double?
    let ratePerHour: Double?
    let usdToday: Double?
    let usdProjected: Double?

    private enum CodingKeys: String, CodingKey {
        case id = "demurrageId"
        case railcarNumber, freeTimeHours, chargeableHours, ratePerHour, usdToday, usdProjected
    }
}

/// `railDemurrageAuto.dashboard` envelope — only the two blocks this screen reads.
private struct DemurrageDashboard662: Decodable {
    let summary: DemurrageSummary662?
    let perCarRunway: [RunwayCar662]?
}

/// `railDemurrageAuto.calculateAccrual` → the free-time / rate constants for a
/// country, read back from the server rather than hardcoded here.
private struct AccrualRegime662: Decodable {
    let country: String?
    let freeTimeHours: Double?
    let ratePerHour: Double?
}

/// Assembled regime cell — the decoded server constants plus the ISO currency
/// that belongs to the country key this client asked for.
private struct Regime662: Identifiable {
    let id: String
    let currency: String
    let freeTimeHours: Double?
    let ratePerHour: Double?
}

/// `railDemurrageAuto.resolveDispute` receipt (railDemurrageAuto.ts:579).
private struct ResolveResult662: Decodable {
    let success: Bool?
    let disputeId: Int?
    let decision: String?
    let chargeStatus: String?
}

/// The two verdicts the server's zod enum accepts (railDemurrageAuto.ts:426).
private enum Verdict662: String, CaseIterable, Identifiable {
    case denied
    case approved
    var id: String { rawValue }

    /// The consequence the router actually applies (railDemurrageAuto.ts:437-438).
    var headline: String {
        switch self {
        case .approved: return "Approve the waiver"
        case .denied:   return "Deny the dispute"
        }
    }
    var consequence: String {
        switch self {
        case .approved: return "The charge is waived. The money is forgiven and never billed."
        case .denied:   return "The charge returns to accruing. It is billable again and unfreezes."
        }
    }
    var tint: Color { self == .approved ? Brand.success : Brand.danger }
}

// MARK: - Screen

struct RailDemurrageChargeApproval_662: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            RailDemurrageApprovalBody662()
        } nav: {
            // Compliance carries the current flag: a verdict here is an audited
            // money-gate act — it writes an immutable blockchainAuditTrail row —
            // which is the Compliance tab's whole remit, not Shipments' tracking.
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",         systemImage: "person",           isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct RailDemurrageApprovalBody662: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: EusoTripSession
    @ObservedObject private var reach = OfflineReachabilityHub.shared

    // Server state — never cleared on a failed read, so the cached figures stay
    // on screen behind an explicit staleness stamp instead of blanking.
    @State private var dashboard: DemurrageDashboard662? = nil
    @State private var docket: [OpenDispute662] = []
    @State private var regimes: [Regime662] = []

    // Load posture
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var docketForbidden: String? = nil
    @State private var lastLoadedAt: Date? = nil
    @State private var tick = Date()

    // Verdict flow (ONLINE_ONLY · confirm:true · human-gated)
    @State private var verdictCase: OpenDispute662? = nil
    @State private var verdict: Verdict662 = .denied
    @State private var resolutionNotes: String = ""
    @State private var waiverAcknowledged = false
    @State private var submitting = false
    @State private var toast: String? = nil

    // MARK: Derived

    private var roleRaw: String { (session.user?.role ?? "").uppercased() }
    private var canAdjudicate: Bool { roleRaw == "ADMIN" || roleRaw == "SUPER_ADMIN" }
    private var roleLabel: String {
        roleRaw.isEmpty ? "This session" : roleRaw.replacingOccurrences(of: "_", with: " ")
    }
    private var locked: Bool { !canAdjudicate || docketForbidden != nil }

    private var summary: DemurrageSummary662? { dashboard?.summary }
    private var runway: [RunwayCar662] { dashboard?.perCarRunway ?? [] }
    private var frozenTotal: Double { docket.reduce(0) { $0 + ($1.chargeTotal ?? 0) } }
    private var waiverTotal: Double { docket.reduce(0) { $0 + ($1.requestedWaiverAmount ?? 0) } }
    private var oldestDays: Int { docket.compactMap { $0.ageDays }.max() ?? 0 }
    private var openCount: Int { docket.isEmpty ? (summary?.disputesOpen ?? 0) : docket.count }
    private var oldestCase: OpenDispute662? {
        docket.max(by: { ($0.ageDays ?? 0) < ($1.ageDays ?? 0) })
    }
    private var docketRates: Set<Int> {
        Set(docket.compactMap { $0.ratePerHour }.map { Int($0.rounded()) })
    }
    private var gradientRegimeId: String? {
        regimes.first(where: { r in
            guard let rate = r.ratePerHour else { return false }
            return docketRates.contains(Int(rate.rounded()))
        })?.id
    }

    private var heroFigure: String { docket.isEmpty ? "\(openCount)" : money662(frozenTotal) }
    private var heroUnit: String {
        docket.isEmpty ? (openCount == 1 ? "dispute frozen" : "disputes frozen") : "frozen"
    }
    private var heroSubline: String {
        if locked && openCount > 0 {
            return "This money cannot reach settled while a dispute is open · charge totals unlock with adjudication access"
        }
        if openCount == 0 {
            return runway.isEmpty
                ? "Nothing is frozen and nothing is accruing right now"
                : "Nothing frozen · \(runway.count) car\(runway.count == 1 ? "" : "s") still accruing below"
        }
        return "\(openCount) dispute\(openCount == 1 ? "" : "s") hold\(openCount == 1 ? "s" : "") this money · oldest \(oldestDays)d frozen"
    }

    /// Monospaced staleness stamp in the header right register (honesty law).
    private var freshness: (String, Color) {
        guard let t = lastLoadedAt else { return ("READING", palette.textTertiary) }
        let mins = max(0, Int(tick.timeIntervalSince(t)) / 60)
        if !reach.isOnline { return ("OFFLINE · CACHED \(mins)m", Brand.warning) }
        if mins >= 5 { return ("STALE \(mins)m", Brand.warning) }
        return ("LIVE · \(hhmm662(t))", palette.textTertiary)
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topRegister
                breadcrumb
                hero
                IridescentHairline()
                postureStrip
                banners
                docketSection
                runwaySection
                // Grouped: the register above already spends 8 of ViewBuilder's
                // 10 subview slots.
                Group {
                    footnote
                    regimeStrip
                    ctaPair
                    Color.clear.frame(height: 96)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await load() }
        .task { await staleTicker() }
        .refreshable { await load() }
        .overlay(alignment: .bottom) { toastView }
        .sheet(item: $verdictCase) { c in verdictSheet(c) }
    }

    // MARK: Header register

    private var topRegister: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\u{2726} RAIL ENGINEER · APPROVALS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.diagonal)
            Spacer(minLength: Space.s2)
            Text(freshness.0)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(freshness.1)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            Text("Demurrage")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: 0)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(heroFigure)
                    .font(.system(size: 32, weight: .bold)).kerning(-0.6).monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(heroUnit)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
            }
            Text(heroSubline)
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Posture strip (3 slim cells — mirrors the SVG at y=198)

    private var postureStrip: some View {
        HStack(spacing: Space.s2) {
            postureCell(
                label: "FROZEN",
                value: docket.isEmpty ? "—" : money662(frozenTotal),
                gradient: true,
                accent: nil
            )
            postureCell(
                label: "OPEN",
                value: "\(openCount)",
                gradient: false,
                accent: openCount > 0 ? Brand.info : nil
            )
            postureCell(
                label: "OLDEST",
                value: docket.isEmpty ? "—" : "\(oldestDays)d",
                gradient: false,
                accent: oldestDays > 0 ? Brand.warning : nil
            )
        }
    }

    private func postureCell(label: String, value: String, gradient: Bool, accent: Color?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(gradient ? Color.white.opacity(0.85) : (accent ?? palette.textTertiary))
                .lineLimit(1).minimumScaleFactor(0.75)
            Text(value)
                .font(.system(size: 20, weight: .bold)).monospacedDigit()
                .foregroundStyle(gradient ? Color.white : (accent ?? palette.textPrimary))
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 64)
        .background(
            Group {
                if gradient { LinearGradient.diagonal }
                else if let accent { accent.opacity(0.10) }
                else { palette.bgCard }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(gradient ? Color.clear : (accent?.opacity(0.45) ?? palette.borderFaint))
        )
    }

    // MARK: Banners — every degraded state named, never swallowed

    @ViewBuilder
    private var banners: some View {
        if !reach.isOnline {
            LifecycleCard(accentWarning: true) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 12, weight: .heavy)).foregroundStyle(Brand.warning)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Offline · figures are the last successful read")
                            .font(.system(size: 12, weight: .heavy)).foregroundStyle(Brand.warning)
                        Text("A verdict moves money in one direction or the other, so it is online-only and cannot be queued for replay. The decision controls stay disabled until the connection returns.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
        if locked {
            LifecycleCard(accentWarning: true) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 12, weight: .heavy)).foregroundStyle(Brand.warning)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Adjudication is gated to ADMIN and SUPER ADMIN")
                            .font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        Text("\(roleLabel) can file a demurrage dispute and watch it, but cannot record the verdict that releases the charge. The frozen posture above is read from the shared demurrage dashboard, which every signed-in role may read.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                        if let msg = docketForbidden {
                            Text(msg)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(palette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        if let err = loadError {
            LifecycleCard(accentDanger: true) {
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Decision docket

    private var docketSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("DECISION DOCKET")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: Space.s2)
                Text("case · freeze · at stake")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }

            if loading && docket.isEmpty && !locked {
                LifecycleCard {
                    Text("Reading the frozen docket…")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            } else if locked {
                LifecycleCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Docket withheld")
                            .font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary)
                        Text("Case files carry the filer, the reason and the amount at stake, so the server releases them only to an adjudicating role. Nothing is guessed here in their place.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if openCount > 0 {
                            Text("\(openCount) dispute\(openCount == 1 ? " is" : "s are") open against this company's demurrage right now.")
                                .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.warning)
                        }
                    }
                }
            } else if docket.isEmpty {
                EusoEmptyState(
                    systemImage: "checkmark.seal",
                    title: "No demurrage money is frozen",
                    subtitle: "Every filed dispute has a verdict. Charges are free to move to settled."
                )
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(docket) { d in docketRow(d) }
                }
            }
        }
    }

    private func docketRow(_ d: OpenDispute662) -> some View {
        let age = d.ageDays ?? 0
        let fraction = oldestDays > 0 ? Double(age) / Double(oldestDays) : 0
        let tint: Color = fraction >= 0.66 ? Brand.danger : (fraction >= 0.33 ? Brand.warning : Brand.info)
        let amount = d.chargeTotal ?? 0

        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("DSP-\(d.id)")
                        .font(.system(size: 14, weight: .bold)).monospaced()
                        .foregroundStyle(palette.textPrimary)
                    Text(d.shipmentNumber ?? "charge #\(d.demurrageId ?? 0)")
                        .font(.system(size: 11, weight: .semibold)).monospaced()
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(money662(amount))
                        .font(.system(size: 16, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text("AT STAKE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }

            HStack(spacing: 6) {
                Text((d.reason ?? "other").replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(tint)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(tint.opacity(0.14)))
                if let cs = d.chargeStatus, !cs.isEmpty {
                    Text(cs.uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(palette.tintNeutral))
                }
                Spacer(minLength: 0)
            }

            // The freeze meter — the reason this screen exists. Fill is this
            // case's age against the oldest case on the docket, so escalation is
            // relative to live data and never a typed threshold.
            FreezeMeter662(fraction: fraction, tint: tint, palette: palette)

            HStack(spacing: 6) {
                Image(systemName: "snowflake")
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(tint)
                Text("\(age)d frozen")
                    .font(.system(size: 11, weight: .heavy)).foregroundStyle(tint)
                if let at = d.submittedAt {
                    Text("· filed \(shortDate662(at))")
                        .font(EType.caption).foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
            }

            Text(basisLine662(d))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)

            if let w = d.requestedWaiverAmount, w > 0 {
                Text("Waiver requested · \(money662(w)) of \(money662(amount))")
                    .font(EType.caption).foregroundStyle(Brand.warning)
            }

            if let n = d.notes, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(n)
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Space.s2) {
                decisionButton("Deny", icon: "xmark.circle.fill", color: Brand.danger) {
                    openVerdict(d, .denied)
                }
                decisionButton("Approve waiver", icon: "checkmark.seal.fill", color: Brand.success) {
                    openVerdict(d, .approved)
                }
            }
            if !reach.isOnline {
                Text("Offline — a verdict cannot be queued")
                    .font(.system(size: 10, weight: .heavy)).foregroundStyle(Brand.warning)
            }
        }
        .padding(Space.s3)
        .padding(.leading, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(tint.opacity(0.28))
        )
    }

    private func decisionButton(_ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .heavy))
                Text(title).font(.system(size: 11, weight: .heavy))
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Capsule().fill(color.opacity(0.14)))
            .overlay(Capsule().strokeBorder(color.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .disabled(!reach.isOnline || submitting)
        .opacity(reach.isOnline ? 1 : 0.5)
    }

    // MARK: Accruing runway — what has not frozen yet (protectedProcedure, always readable)

    @ViewBuilder
    private var runwaySection: some View {
        if !runway.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .firstTextBaseline) {
                    Text("STILL ACCRUING")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: Space.s2)
                    Text("today · +24h")
                        .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
                VStack(spacing: 0) {
                    ForEach(Array(runway.prefix(4).enumerated()), id: \.element.id) { idx, car in
                        runwayRow(car)
                        if idx < min(runway.count, 4) - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
                if let accruing = summary?.totalChargesAccruing, accruing > 0 {
                    Text("\(money662(accruing)) accruing across \(summary?.activeAccruals ?? runway.count) car\((summary?.activeAccruals ?? runway.count) == 1 ? "" : "s") — none of it frozen yet")
                        .font(EType.caption).foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func runwayRow(_ car: RunwayCar662) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "train.side.front.car")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.rail)
                .frame(width: 34, height: 34)
                .background(Brand.rail.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(car.railcarNumber ?? "car #\(car.id)")
                    .font(.system(size: 13, weight: .bold)).monospaced()
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(String(format: "%.0fh free · %.1fh chargeable @ %@/h",
                            car.freeTimeHours ?? 0,
                            car.chargeableHours ?? 0,
                            money662(car.ratePerHour ?? 0)))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.65)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 3) {
                Text(money662(car.usdToday ?? 0))
                    .font(.system(size: 14, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("→ \(money662(car.usdProjected ?? 0))")
                    .font(.system(size: 10, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(Brand.warning)
            }
        }
        .padding(Space.s3)
    }

    // MARK: Footnote — the bulk gap, stated instead of drawn as a button

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Each verdict is recorded one dispute at a time — the server has no bulk-approve verb for rail demurrage, so nothing on this screen clears a batch.")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if waiverTotal > 0 {
                Text("\(money662(waiverTotal)) of the \(money662(frozenTotal)) frozen is under a waiver request.")
                    .font(.system(size: 11, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Every verdict writes an immutable audit entry against the charge.")
                .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Free-time regime strip (values read from the server, never typed)

    @ViewBuilder
    private var regimeStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("FREE-TIME REGIME · BY COUNTRY")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            if regimes.isEmpty {
                LifecycleCard {
                    Text("Free-time regimes are read from the accrual engine and were not returned on the last pass. Nothing is substituted for them.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: Space.s2) {
                    ForEach(regimes) { r in regimeCell(r) }
                }
            }
        }
    }

    private func regimeCell(_ r: Regime662) -> some View {
        let matched = docketRates.contains(Int((r.ratePerHour ?? -1).rounded()))
        let isGradient = (r.id == gradientRegimeId)
        return VStack(alignment: .leading, spacing: 3) {
            Text(String(format: "%@ · %.0fh free", r.id, r.freeTimeHours ?? 0))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isGradient ? Color.white : palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.65)
            Text("\(money662(r.ratePerHour ?? 0))/hr · \(r.currency)")
                .font(.system(size: 10))
                .foregroundStyle(isGradient ? Color.white.opacity(0.9) : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.65)
            if matched {
                Text("RATE ON DOCKET")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(isGradient ? Color.white.opacity(0.9) : Brand.warning)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Group { if isGradient { LinearGradient.primary } else { palette.bgCard } })
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(isGradient ? Color.clear : (matched ? Brand.warning.opacity(0.45) : palette.borderFaint))
        )
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            primaryCTA
            RailSecondaryActionButton(
                title: "Docket",
                sheetTitle: "Frozen demurrage docket",
                lines: docketContextLines,
                width: 132,
                systemImage: "snowflake"
            )
        }
    }

    @ViewBuilder
    private var primaryCTA: some View {
        if locked {
            unavailableCTA(
                icon: "lock.fill",
                title: "Adjudication gated",
                reason: "ADMIN or SUPER ADMIN records the verdict"
            )
        } else if !reach.isOnline {
            unavailableCTA(
                icon: "wifi.slash",
                title: "Verdict is online-only",
                reason: "Money movement is never queued for replay"
            )
        } else if let c = oldestCase {
            CTAButton(
                title: "Adjudicate oldest",
                action: { openVerdict(c, .denied) },
                leadingIcon: "hammer.fill",
                subtitle: "DSP-\(c.id) · \(money662(c.chargeTotal ?? 0)) · \(c.ageDays ?? 0)D FROZEN",
                isLoading: submitting
            )
            .frame(maxWidth: .infinity)
        } else {
            unavailableCTA(
                icon: "checkmark.seal",
                title: "Nothing to adjudicate",
                reason: "No dispute is holding a charge"
            )
        }
    }

    private func unavailableCTA(icon: String, title: String, reason: String) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 13, weight: .bold))
                Text(title).font(EType.title)
            }
            Text(reason.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .foregroundStyle(palette.textTertiary)
        .frame(maxWidth: .infinity, minHeight: 52)
        .padding(.vertical, 4)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }

    private var docketContextLines: [String] {
        var lines: [String] = []
        lines.append("\(openCount) open dispute\(openCount == 1 ? "" : "s") · oldest \(oldestDays)d frozen")
        if !docket.isEmpty { lines.append("\(money662(frozenTotal)) frozen · \(money662(waiverTotal)) under waiver request") }
        if let a = summary?.totalChargesAccruing, a > 0 {
            lines.append("\(money662(a)) still accruing across \(summary?.activeAccruals ?? 0) car\((summary?.activeAccruals ?? 0) == 1 ? "" : "s")")
        }
        for d in docket.prefix(8) {
            lines.append("DSP-\(d.id) · \(d.shipmentNumber ?? "charge #\(d.demurrageId ?? 0)") · \(money662(d.chargeTotal ?? 0)) · \(d.ageDays ?? 0)d · \((d.reason ?? "other").replacingOccurrences(of: "_", with: " "))")
        }
        if locked { lines.append("Verdicts require ADMIN or SUPER ADMIN — this session cannot record one") }
        return lines
    }

    // MARK: Verdict sheet (confirm:true · human-gated · ONLINE_ONLY)

    private func verdictSheet(_ c: OpenDispute662) -> some View {
        let amount = c.chargeTotal ?? 0
        let waiver = c.requestedWaiverAmount ?? 0
        let blocked = !reach.isOnline || (verdict == .approved && !waiverAcknowledged)

        return ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(spacing: 6) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("RECORD VERDICT · MOVES MONEY")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Dispute DSP-\(c.id)")
                        .font(.system(size: 22, weight: .heavy)).kerning(-0.3)
                        .foregroundStyle(palette.textPrimary)
                    Text("\(money662(amount)) has been frozen for \(c.ageDays ?? 0) day\((c.ageDays ?? 0) == 1 ? "" : "s") on \(c.shipmentNumber ?? "charge #\(c.demurrageId ?? 0)").")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                LifecycleCard {
                    caseFact("REASON", (c.reason ?? "other").replacingOccurrences(of: "_", with: " ").uppercased())
                    caseFact("CHARGE AT STAKE", money662(amount))
                    if waiver > 0 { caseFact("WAIVER REQUESTED", money662(waiver)) }
                    caseFact("BASIS", basisLine662(c))
                    if let s = c.chargeStatus { caseFact("CHARGE STATUS", s.uppercased()) }
                    if let n = c.notes, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        caseFact("FILED NOTE", n)
                    }
                }

                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("VERDICT")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    ForEach(Verdict662.allCases) { v in
                        Button {
                            verdict = v
                            if v == .denied { waiverAcknowledged = false }
                        } label: {
                            HStack(alignment: .top, spacing: Space.s3) {
                                Image(systemName: verdict == v ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(verdict == v ? v.tint : palette.textTertiary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(v.headline)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(palette.textPrimary)
                                    Text(v.consequence)
                                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(Space.s3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(palette.bgCard)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .strokeBorder(verdict == v ? v.tint.opacity(0.55) : palette.borderFaint)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("RESOLUTION NOTES (OPTIONAL · MAX 2000)")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    TextField("Why this verdict…", text: $resolutionNotes, axis: .vertical)
                        .lineLimit(2...5)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .padding(Space.s3)
                        .background(palette.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderFaint)
                        )
                    Text("The note is appended to the dispute record and repeated to the filer.")
                        .font(EType.caption).foregroundStyle(palette.textTertiary)
                }

                // Confirm-gate on the destructive path: approving forgives the
                // money outright, so it needs an explicit acknowledgement before
                // the commit button will fire.
                if verdict == .approved {
                    Button {
                        waiverAcknowledged.toggle()
                    } label: {
                        HStack(alignment: .top, spacing: Space.s3) {
                            Image(systemName: waiverAcknowledged ? "checkmark.square.fill" : "square")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(waiverAcknowledged ? Brand.success : palette.textTertiary)
                            Text("I confirm this waives \(money662(amount)) — the charge is forgiven and will not be billed.")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(Space.s3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Brand.success.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(Brand.success.opacity(waiverAcknowledged ? 0.55 : 0.25))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    Task { await submitVerdict(c) }
                } label: {
                    HStack {
                        Spacer()
                        if submitting {
                            ProgressView().tint(.white)
                        } else {
                            Text(verdict == .approved
                                 ? "Confirm waiver · \(money662(amount))"
                                 : "Confirm denial · \(money662(amount)) billable again")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(blocked || submitting)
                .opacity(blocked || submitting ? 0.55 : 1)

                if blocked {
                    Text(reach.isOnline
                         ? "Tick the acknowledgement above — a waiver forgives money and will not fire without it."
                         : "Offline. A verdict moves money and is never queued for replay; reconnect to record it.")
                        .font(EType.caption).foregroundStyle(Brand.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Recorded against the charge in the immutable audit trail. Approving releases the freeze by waiving the charge; denying releases it by returning the charge to accruing.")
                    .font(EType.caption).foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Color.clear.frame(height: 24)
            }
            .padding(20)
        }
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func caseFact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 118, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func openVerdict(_ c: OpenDispute662, _ v: Verdict662) {
        verdict = v
        resolutionNotes = ""
        waiverAcknowledged = false
        verdictCase = c
    }

    // MARK: Toast

    @ViewBuilder
    private var toastView: some View {
        if let t = toast {
            Text(t)
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .lineLimit(2).multilineTextAlignment(.center)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(Brand.success))
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func showToast(_ msg: String) {
        withAnimation(.easeOut(duration: 0.18)) { toast = msg }
        Task {
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation(.easeOut(duration: 0.18)) { toast = nil }
        }
    }

    // MARK: Formatting

    private func money662(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = v == v.rounded() ? 0 : 2
        f.minimumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v))
    }

    private func hhmm662(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private func shortDate662(_ iso: String) -> String {
        let out = DateFormatter()
        out.dateFormat = "MMM d · HH:mm"
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: iso) { return out.string(from: d) }
        let f2 = ISO8601DateFormatter()
        if let d = f2.date(from: iso) { return out.string(from: d) }
        return String(iso.prefix(16))
    }

    private func basisLine662(_ d: OpenDispute662) -> String {
        var parts: [String] = []
        let hours = d.chargeableHours ?? 0
        let rate = d.ratePerHour ?? 0
        if hours > 0 || rate > 0 {
            parts.append(String(format: "%.1fh chargeable @ %@/h", hours, money662(rate)))
        }
        if let p = d.placedAt { parts.append("placed \(shortDate662(p))") }
        if let r = d.releasedAt { parts.append("released \(shortDate662(r))") }
        return parts.isEmpty ? "charge detail not returned for this case" : parts.joined(separator: " · ")
    }

    // MARK: Data

    private func staleTicker() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if Task.isCancelled { return }
            tick = Date()
        }
    }

    private func fetchDashboard() async -> Result<DemurrageDashboard662, Error> {
        struct DashIn: Encodable {}
        do {
            let out: DemurrageDashboard662 = try await EusoTripAPI.shared.query(
                "railDemurrageAuto.dashboard", input: DashIn())
            return .success(out)
        } catch {
            return .failure(error)
        }
    }

    private func fetchDocket() async -> Result<[OpenDispute662], Error> {
        struct DocketIn: Encodable { let limit: Int }
        do {
            let out: [OpenDispute662] = try await EusoTripAPI.shared.query(
                "railDemurrageAuto.listOpenDisputes", input: DocketIn(limit: 100))
            return .success(out)
        } catch {
            return .failure(error)
        }
    }

    /// Probes the accrual engine for one country's free-time and rate so the
    /// regime strip renders the server's own constants instead of typed numbers.
    private func fetchRegime(_ country: String, at stamp: String) async -> AccrualRegime662? {
        struct RegimeIn: Encodable {
            let placementTime: String
            let country: String
            let railcarCount: Int
        }
        do {
            let out: AccrualRegime662 = try await EusoTripAPI.shared.query(
                "railDemurrageAuto.calculateAccrual",
                input: RegimeIn(placementTime: stamp, country: country, railcarCount: 1))
            return out
        } catch {
            return nil
        }
    }

    private func load() async {
        if dashboard == nil && docket.isEmpty { loading = true }
        loadError = nil

        let stamp = ISO8601DateFormatter().string(from: Date())

        async let dashTask = fetchDashboard()
        async let docketTask = fetchDocket()
        async let usTask = fetchRegime("US", at: stamp)
        async let caTask = fetchRegime("CA", at: stamp)
        async let mxTask = fetchRegime("MX", at: stamp)

        let dashResult = await dashTask
        let docketResult = await docketTask
        let usProbe = await usTask
        let caProbe = await caTask
        let mxProbe = await mxTask

        var anySuccess = false

        switch dashResult {
        case .success(let d):
            dashboard = d
            anySuccess = true
        case .failure(let err):
            loadError = (err as? EusoTripAPIError)?.errorDescription ?? err.localizedDescription
        }

        switch docketResult {
        case .success(let rows):
            docket = rows
            docketForbidden = nil
            anySuccess = true
        case .failure(let err):
            if let api = err as? EusoTripAPIError, case .forbidden(let msg) = api {
                // Designed state, not an error: the RBAC gate on this router is
                // ADMIN / SUPER_ADMIN. Keep the message, lock the docket, and
                // leave the dashboard-derived posture intact.
                docketForbidden = msg
                docket = []
            } else if loadError == nil {
                loadError = (err as? EusoTripAPIError)?.errorDescription ?? err.localizedDescription
            }
        }

        // Currency belongs to the country key this client asked for; the hours
        // and the rate belong to the server.
        var built: [Regime662] = []
        let probes: [(String, String, AccrualRegime662?)] = [
            ("US", "USD", usProbe),
            ("CA", "CAD", caProbe),
            ("MX", "MXN", mxProbe),
        ]
        for probe in probes {
            guard let p = probe.2 else { continue }
            anySuccess = true
            built.append(Regime662(
                id: p.country ?? probe.0,
                currency: probe.1,
                freeTimeHours: p.freeTimeHours,
                ratePerHour: p.ratePerHour
            ))
        }
        if !built.isEmpty { regimes = built }

        if anySuccess { lastLoadedAt = Date() }
        tick = Date()
        loading = false
    }

    private func submitVerdict(_ c: OpenDispute662) async {
        guard reach.isOnline else {
            showToast("Offline — a verdict moves money and cannot be queued")
            return
        }
        // `confirm` is a z.literal(true) on the server: omit it and the call 400s.
        struct ResolveIn: Encodable {
            let confirm: Bool
            let disputeId: Int
            let decision: String
            let resolutionNotes: String?

            enum CodingKeys: String, CodingKey {
                case confirm, disputeId, decision, resolutionNotes
            }
            // Hand-rolled so an absent note is omitted rather than sent as null —
            // zod `.optional()` rejects an explicit null.
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(confirm, forKey: .confirm)
                try c.encode(disputeId, forKey: .disputeId)
                try c.encode(decision, forKey: .decision)
                try c.encodeIfPresent(resolutionNotes, forKey: .resolutionNotes)
            }
        }

        submitting = true
        let trimmed = resolutionNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let res: ResolveResult662 = try await EusoTripAPI.shared.mutation(
                "railDemurrageAuto.resolveDispute",
                input: ResolveIn(
                    confirm: true,
                    disputeId: c.id,
                    decision: verdict.rawValue,
                    resolutionNotes: trimmed.isEmpty ? nil : String(trimmed.prefix(2000))
                )
            )
            verdictCase = nil
            resolutionNotes = ""
            waiverAcknowledged = false
            let charge = res.chargeStatus ?? (verdict == .approved ? "waived" : "accruing")
            showToast("DSP-\(c.id) \(res.decision ?? verdict.rawValue) · charge \(charge) · \(money662(c.chargeTotal ?? 0)) unfrozen")
            await load()
        } catch {
            if let api = error as? EusoTripAPIError, case .forbidden(let msg) = api {
                docketForbidden = msg
                verdictCase = nil
                showToast("Verdict refused · \(msg)")
            } else {
                showToast((error as? EusoTripAPIError)?.errorDescription ?? "Verdict failed")
            }
        }
        submitting = false
    }
}

// MARK: - Freeze meter
//
// The signature element of this screen: a track whose fill is how long THIS
// case's money has been immobilised relative to the oldest case on the live
// docket. Ticks give the eye a scale without printing a number, and the tint
// escalates purely from that ratio — no typed day thresholds anywhere.

private struct FreezeMeter662: View {
    let fraction: Double
    let tint: Color
    let palette: Theme.Palette

    var body: some View {
        GeometryReader { geo in
            let width = max(0, geo.size.width)
            let filled = min(1.0, max(0.04, fraction.isFinite ? fraction : 0))
            ZStack(alignment: .leading) {
                Capsule().fill(palette.tintNeutral)
                Capsule().fill(tint).frame(width: width * filled)
            }
            .overlay(
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        Spacer(minLength: 0)
                        Rectangle().fill(palette.bgCard).frame(width: 1)
                    }
                    Spacer(minLength: 0)
                }
            )
        }
        .frame(height: 7)
    }
}

#Preview("662 · Rail Demurrage Charge Approval · Night") {
    RailDemurrageChargeApproval_662(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("662 · Rail Demurrage Charge Approval · Light") {
    RailDemurrageChargeApproval_662(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
