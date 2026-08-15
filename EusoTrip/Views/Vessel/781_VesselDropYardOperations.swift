//
//  781_VesselDropYardOperations.swift
//  EusoTrip — Vessel Operator · Drop Yard Operations.
//
//  Faithful port of "781 Vessel Drop Yard Operations.svg" (Light + Dark), adapted onto the canonical
//  DesignSystem (Shell · BottomNav · Theme.Palette · StatusPill · CTAButton · IridescentHairline).
//  Role VESSEL_OPERATOR (carrier-side). Nav anchored to VesselOperatorNavController
//  (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME) with the SHIPMENTS slot inked.
//
//  ARCHETYPE: MONEY/GRID — a drop yard's cost driver is not "where is the box", it is "how long has it
//  been on the ground and what is that costing per day". The hero is therefore a PER-DIEM BURN LADDER:
//  one horizontal capsule per container, capsule LENGTH proportional to days on ground, a single
//  free-time rule crossing all of them, the portion past the rule filled danger, and the accrued dollars
//  printed at each capsule tail. There is deliberately NO occupancy grid on this screen (704 Bay Plan
//  owns the slot matrix this fire) and NO KPI tile row.
//
//  LIVE FUSION: the burn ladder, the accrued total, the header over-LFD count, the container rows and
//  the ESang nudge are five faces of ONE `containers` state and re-reason together off load(). The depot
//  slot budget tape is the second face, off `chassis`. Degraded provider state surfaces an explicit error
//  card, never a frozen number.
//
//  OFFLINE POLICY: READ_CACHED(120s) — the accrued figure renders from the last good payload behind a
//  DASHED rule and a live "cached N ago" line, so a cached balance is visibly distinct from a live one.
//  "Refresh accrual" is ONLINE_ONLY because a stale accrual must never be presented as a current balance;
//  any pay or dispute action is ONLINE_ONLY and is NOT BUILT (no mutation exists — see STUB below).
//
//  Data / wiring (line numbers read first-hand 2026-08-11 against server/routers/yardManagement.ts,
//  md5 a7d700bdb2da8a2b915bb80e8074648d, 2542 lines):
//
//    yardManagement.getContainerTracking (EXISTS yardManagement.ts:1267 · protectedProcedure ·
//      input {locationId?, status?, search?} · returns {containers:[{id, containerNumber, size, type,
//      status, chassisId, locationId, spotId, steamshipLine, bookingNumber, sealNumber, weight,
//      lastFreeDay, demurrageRate, arrivalTime}], summary:{total,onChassis,grounded,loaded,empty}}.
//      TENANCY CORRECT — eq(containersTable.companyId, companyId) at :1280, companyId from
//      ctx.user!.companyId at :1275; this is the house standard. lastFreeDay + demurrageRate +
//      arrivalTime ARE the burn ladder; chassisId IS the linked-pair glyph. demurrageRate is a SQL
//      decimal(10,2) (drizzle/schema.ts:13140) so it is decoded through FlexDouble781.
//
//    yardManagement.getChassisInventory (EXISTS yardManagement.ts:1330 · protectedProcedure ·
//      input {locationId?, status?} · summary {total, available, inUse, maintenance, outOfService}.
//      TENANCY CORRECT — eq(chassisInventory.companyId, companyId) at :1342). Drives the three segments
//      of the depot slot budget tape: IN USE / OUT OF SVC / FREE. There is NO "reserved" hold state in
//      the chassis status enum, so no segment claims one.
//
//    yardManagement.getDropYardOperations (EXISTS yardManagement.ts:1718 · protectedProcedure ·
//      input z.object({locationId: z.string().optional()}).optional()). TENANCY CORRECT —
//      eq(vehicles.companyId, companyId) at :1738, companyId at :1725.
//      *** locationId is ACCEPTED AND NEVER USED — the handler destructures ({ ctx }) only at :1720, so
//          this screen passes nil and does not pretend the filter works. ***
//      *** THREE FABRICATED FIELDS. THIS SCREEN LAUNDERS NONE OF THEM: ***
//        - status is HARDCODED "dropped" for every row (:1777), so summary.awaitingPickup (:1795) is
//          structurally ALWAYS 0 — not decoded, not shown.
//        - spotId is SYNTHESISED FROM THE ARRAY INDEX (:1784) — not decoded, not shown. Every spot id
//          on this screen comes from the REAL containers.spotId column via getContainerTracking.
//        - sealIntact is HARDCODED true (:1785), so summary.sealIssues (:1799) is structurally ALWAYS 0
//          — not decoded, not shown.
//      Only summary.total (:1793) and summary.avgDwellHours (:1796) are real signals, and only those two
//      are consumed (as the yard cross-check caption). The screen states the rest is not instrumented.
//
//    STUB · drop-yard-pickup-request — no mutation in yardManagement.ts is reachable from a container id.
//      yardManagement.assignYardMove EXISTS at :2026 but is keyed on yardMoves.id and cannot be addressed
//      from a CTR container id or a DY drop-yard id. Proposed shape:
//      yardManagement.requestContainerPickup({containerId: string, requestedFor: string,
//      carrierScac?: string}) -> {success: true, moveId: string}. The button renders the gap notice.
//
//    STUB · chassis-pool-burndown-forecast — the 2x26 seam marker on the budget tape has no forecast
//      behind it. Proposed shape: yardManagement.getChassisPoolForecast({locationId, horizonHours}) ->
//      {points:[{at, freeCount}], overflowAt: string?}. The marker is drawn and labelled NOT MODELLED.
//
//    STUB · esang-screen-enum-vessel — esangCoach.forScreen EXISTS (esangCoach.ts:264) but its
//      SCREEN_ENUM (esangCoach.ts:112-125) admits only twelve driver-side keys and none is vessel or
//      yard, so the call would be rejected by zod. The nudge is DERIVED ON DEVICE from the loaded rows
//      and the screen says so. Proposed shape: add "vessel-yard" to SCREEN_ENUM at esangCoach.ts:112.
//
//    CHAIN-OPEN · request pickup / gate-out — nothing on this path writes a blockchainAuditTrail row
//      (grep for blockchainAuditTrail or BlockchainService in yardManagement.ts returns 0) and nothing
//      broadcasts (grep for wsService or getIO or broadcast or io.to returns 0), so a drop-yard state
//      change reaches no counter-party. TERMINAL_QUEUE_UPDATE (shared/websocket-events.ts:225),
//      TERMINAL_GATE_ALERT (:226), TERMINAL_DOCK_ASSIGNED (:223) and TERMINAL_BAY_STATUS (:222) all
//      exist with zero emitters; WS_CHANNELS.TERMINAL_QUEUE (:598) has zero emitters and zero
//      subscribers; WS_CHANNELS.VESSEL_CONTAINER (:629) is only reachable from a booking-status path,
//      never from a container move.
//
//    RBAC — protectedProcedure, auth only, NO mode gate. vesselProcedure (server/_core/trpc.ts:268) is
//      not applied to yardManagement, so this is a MARINE VANTAGE ON A YARD-SHAPED PROCEDURE: a
//      truck-mode operator on the same companyId sees the same rows. Tenancy is correct on all three
//      procedures, so this is a MODE-GATE gap, not a P0-READ-TENANCY.
//
//  ZERO-FALLBACK: state starts EMPTY, the loader overwrites UNCONDITIONALLY, an honest empty response
//  renders the bespoke empty state and never fabricated rows. A container missing arrivalTime,
//  lastFreeDay or demurrageRate yields nil — never a synthesised 0 presented as money. File-scoped types
//  are suffixed 781 to avoid cross-file private collisions.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen wrapper (Shell + vessel operator nav · SHIPMENTS inked)

struct VesselDropYardOperationsScreen: View {
    let theme: Theme.Palette
    /// Depot / yard location filter. Empty means "no location threaded": the queries omit locationId
    /// and return the operator's own company-scoped rows.
    var locationId: String = ""

    init(theme: Theme.Palette, locationId: String = "") {
        self.theme = theme
        self.locationId = locationId
    }

    var body: some View {
        Shell(theme: theme) {
            VesselDropYardOperationsBody781(locationId: locationId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",         systemImage: "person",                isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Lenient numeric box (MySQL decimal(10,2) arrives as String OR Double OR Int)

private struct FlexDouble781: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d; return }
        if let i = try? c.decode(Int.self)    { value = Double(i); return }
        if let s = try? c.decode(String.self) { value = Double(s); return }
        value = nil   // null / missing / non-numeric — honest absence, never a fabricated 0
    }
}

// MARK: - Data shapes (mirror the procedure return rows EXACTLY)

/// `yardManagement.getContainerTracking` -> containers[]
private struct Container781: Decodable, Identifiable {
    let id: String
    let containerNumber: String?
    let size: String?
    let type: String?
    let status: String?
    let chassisId: String?
    let locationId: String?
    let spotId: String?
    let steamshipLine: String?
    let bookingNumber: String?
    let sealNumber: String?
    let weight: Int?
    let lastFreeDay: String?
    let demurrageRate: FlexDouble781?
    let arrivalTime: String?
}

private struct ContainerTrackingResponse781: Decodable {
    let containers: [Container781]
}

/// `yardManagement.getChassisInventory` -> summary
private struct ChassisSummary781: Decodable {
    let total: Int?
    let available: Int?
    let inUse: Int?
    let maintenance: Int?
    let outOfService: Int?
}
private struct ChassisInventoryResponse781: Decodable {
    let summary: ChassisSummary781?
}

/// `yardManagement.getDropYardOperations` -> summary.
/// `dropped`, `awaitingPickup` and `sealIssues` are DELIBERATELY NOT DECODED: they are computed from
/// hardcoded row fields server-side (:1777 / :1785) and are structurally always 0 or always == total.
private struct DropYardSummary781: Decodable {
    let total: Int?
    let avgDwellHours: Int?
}
private struct DropYardResponse781: Decodable {
    let summary: DropYardSummary781?
}

// MARK: - Query inputs

private struct ContainerQuery781: Encodable {
    let locationId: String?
    let status: String?
    let search: String?
}
private struct ChassisQuery781: Encodable {
    let locationId: String?
    let status: String?
}
/// getDropYardOperations accepts `locationId` and never reads it (handler destructures `{ ctx }` only,
/// yardManagement.ts:1720) — so nil is sent and the screen does not claim a working location filter.
private struct DropYardQuery781: Encodable {
    let locationId: String?
}

// MARK: - Derived burn row (computed from the live container payload only)

private struct Burn781: Identifiable {
    let id: String
    let ownerCode: String        // ISO 6346 owner prefix, first 4 of containerNumber
    let number: String
    let daysOnGround: Double?    // nil when arrivalTime is absent
    let freeDays: Double?        // nil when lastFreeDay or arrivalTime is absent
    let ratePerDay: Double?      // nil when demurrageRate is absent
    let accrued: Double?         // nil when any input is absent — never a fabricated 0
    let spot: String?
    let line: String?
    let sizeType: String
    let paired: Bool
    let lfdLabel: String?
    var overFree: Bool {
        guard let d = daysOnGround, let f = freeDays else { return false }
        return d > f
    }
}

// MARK: - Body

private struct VesselDropYardOperationsBody781: View {
    @Environment(\.palette) private var palette
    let locationId: String

    // live rows only — no seeds, no demo arrays
    @State private var containers: [Container781] = []
    @State private var chassis: ChassisSummary781? = nil
    @State private var yard: DropYardSummary781? = nil

    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var chassisUnavailable = false
    @State private var yardUnavailable = false
    @State private var loadedAt: Date? = nil
    @State private var showPickupGap = false

    private let capsuleHeight: CGFloat = 18
    private let capsulePitchGap: CGFloat = 8      // 18 + 8 = pitch 26, matching the SVG
    private let ownerColumn: CGFloat = 34
    private let nominalPointsPerDay: CGFloat = 22

    // ── Derived state — every counter below reads THIS state, never a parallel literal ──

    private var burns: [Burn781] {
        containers.map { c in
            let arrival = Self.iso(c.arrivalTime)
            let lfd = Self.iso(c.lastFreeDay)
            let days = arrival.map { Date().timeIntervalSince($0) / 86_400.0 }
            let free: Double? = {
                guard let a = arrival, let l = lfd else { return nil }
                return max(0, l.timeIntervalSince(a) / 86_400.0)
            }()
            let rate = c.demurrageRate?.value
            let accrued: Double? = {
                guard let d = days, let f = free, let r = rate else { return nil }
                return max(0, d - f) * r
            }()
            let num = c.containerNumber ?? c.id
            return Burn781(
                id: c.id,
                ownerCode: String(num.prefix(4)).uppercased(),
                number: num,
                daysOnGround: days,
                freeDays: free,
                ratePerDay: rate,
                accrued: accrued,
                spot: c.spotId,
                line: c.steamshipLine,
                sizeType: [c.size, c.type].compactMap { $0 }.joined(separator: " "),
                paired: (c.chassisId?.isEmpty == false),
                lfdLabel: lfd.map { Self.dayMonth.string(from: $0).uppercased() }
            )
        }
        .sorted { ($0.daysOnGround ?? -1) > ($1.daysOnGround ?? -1) }
    }

    /// The hero ladder shows the six longest-standing boxes — the same six the money is coming from.
    private var ladder: [Burn781] { Array(burns.filter { $0.daysOnGround != nil }.prefix(6)) }

    private var accruedTotal: Double? {
        let vals = burns.compactMap { $0.accrued }
        return vals.isEmpty ? nil : vals.reduce(0, +)
    }
    private var ratelessCount: Int { burns.filter { $0.accrued == nil }.count }
    private var overLfdCount: Int { burns.filter { $0.overFree }.count }

    /// The single free-time rule crossing every capsule. Drawn at the MEDIAN free-time boundary across
    /// the loaded rows; each capsule still splits at its OWN lastFreeDay, so LFD dispersion stays
    /// visible rather than flattened into one number.
    private var ruleDay: Double? {
        let f = burns.compactMap { $0.freeDays }.sorted()
        guard !f.isEmpty else { return nil }
        return f[f.count / 2]
    }

    private var topBurner: Burn781? {
        burns.filter { ($0.accrued ?? 0) > 0 }.max { ($0.accrued ?? 0) < ($1.accrued ?? 0) }
    }

    // ── View ──

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s5) {
                header
                IridescentHairline()

                if loading {
                    loadingCard
                } else if let err = loadError {
                    errorCard(err)
                } else if containers.isEmpty {
                    emptyCard
                } else {
                    burnLadderSection
                    accrualBand
                    slotBudgetTape
                    containerRows
                    esangNudge
                }

                triCountryFooter
                ctaPair
            }
            .padding(.horizontal, Space.s5)
            .padding(.bottom, Space.s8)
        }
        .eusoRefreshTask { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                EusoTripEyebrow(verbatim: "VESSEL · DROP YARD · PER-DIEM")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("USLGB PIER J")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Drop yard")
                    .font(EType.h1).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if overLfdCount > 0 {
                    StatusPill(text: "\(overLfdCount) over LFD", kind: .danger)
                } else if !loading && loadError == nil && !containers.isEmpty {
                    StatusPill(text: "inside free time", kind: .success)
                }
            }
            Text(subline)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.top, Space.s5)
    }

    private var subline: String {
        if loading { return "reading the yard clock…" }
        if loadError != nil { return "yard clock unavailable" }
        let n = containers.count
        return "\(n) \(n == 1 ? "box" : "boxes") on ground · accruing past the last free day"
    }

    // MARK: HERO ORGAN — per-diem burn ladder

    private var burnLadderSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("PER-DIEM BURN LADDER · \(ladder.count) ON GROUND")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(ruleDay.map { "LFD DAY \(Int($0.rounded()))" } ?? "NO LFD ON FILE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }

            GeometryReader { geo in
                let usable = max(80, geo.size.width - ownerColumn - 62)   // 62 reserved for the money tail
                let maxDays = ladder.compactMap { $0.daysOnGround }.max() ?? 1
                let ppd = maxDays > 0 ? min(nominalPointsPerDay, usable / CGFloat(maxDays)) : nominalPointsPerDay

                ZStack(alignment: .topLeading) {
                    VStack(spacing: capsulePitchGap) {
                        ForEach(ladder) { b in
                            capsuleRow(b, ppd: ppd)
                        }
                    }
                    if let rd = ruleDay {
                        Rectangle()
                            .fill(Brand.danger.opacity(0.85))
                            .frame(width: 2)
                            .frame(maxHeight: .infinity)
                            .offset(x: ownerColumn + CGFloat(rd) * ppd)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: CGFloat(max(1, ladder.count)) * capsuleHeight
                   + CGFloat(max(0, ladder.count - 1)) * capsulePitchGap)
            .padding(Space.s4)
            .eusoCard(radius: Radius.xl)

            Text(ladderCaption)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var ladderCaption: String {
        guard ruleDay != nil else {
            return "NO LAST-FREE-DAY ON FILE FOR THESE BOXES · NO BILLABLE SPLIT CAN BE DRAWN"
        }
        return "RULE = MEDIAN FREE-TIME BOUNDARY · EACH BAR SPLITS AT ITS OWN LAST FREE DAY"
    }

    private func capsuleRow(_ b: Burn781, ppd: CGFloat) -> some View {
        let days = CGFloat(b.daysOnGround ?? 0)
        let width = max(6, days * ppd)
        let splitDays = min(CGFloat(b.freeDays ?? days), days)
        let splitX = splitDays * ppd

        return HStack(spacing: 0) {
            Text(b.ownerCode)
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
                .frame(width: ownerColumn, alignment: .leading)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient.diagonal)
                    .frame(width: width, height: capsuleHeight)
                if b.overFree {
                    Capsule()
                        .fill(Brand.danger.opacity(0.92))
                        .frame(width: width, height: capsuleHeight)
                        .mask(
                            HStack(spacing: 0) {
                                Color.clear.frame(width: splitX)
                                Rectangle()
                            }
                        )
                }
            }
            .frame(width: width, height: capsuleHeight)

            Text(tailLabel(b))
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tailTint(b))
                .padding(.leading, 8)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(b.number), \(b.daysOnGround.map { String(format: "%.1f", $0) } ?? "unknown") days on ground, \(tailLabel(b)) accrued")
    }

    private func tailLabel(_ b: Burn781) -> String {
        guard let a = b.accrued else { return b.ratePerDay == nil ? "no rate" : "no LFD" }
        return Self.money(a)
    }
    private func tailTint(_ b: Burn781) -> Color {
        guard let a = b.accrued else { return palette.textTertiary }
        return a > 0 ? Brand.danger : palette.textTertiary
    }

    // MARK: Accrual band — the READ_CACHED affordance lives here

    private var accrualBand: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ACCRUED PAST LAST FREE DAY")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    stalenessLine
                }
                Spacer()
                if let total = accruedTotal {
                    Text(Self.money(total))
                        .font(.system(size: 22, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.primary)
                } else {
                    Text("no rate on file")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            DashedRule781()
            if ratelessCount > 0 {
                Text("\(ratelessCount) of \(burns.count) boxes have no demurrage rate or no last free day on file — excluded from the total, never counted as zero.")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private var stalenessLine: some View {
        Group {
            if let at = loadedAt {
                (Text("cached ") + Text(at, style: .relative) + Text(" ago · pay or dispute is live-only"))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            } else {
                Text("not yet read · pay or dispute is live-only")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: MID-BAND ORGAN — depot slot budget tape

    private var slotBudgetTape: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("DEPOT SLOT BUDGET · CHASSIS POOL")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(chassis?.total.map { "\($0) SLOTS" } ?? "POOL UNREAD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }

            if chassisUnavailable || chassis == nil {
                Text("Chassis pool did not answer on this read. No segment is drawn rather than a guessed one.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            } else {
                let inUse = chassis?.inUse ?? 0
                let out = (chassis?.maintenance ?? 0) + (chassis?.outOfService ?? 0)
                let free = chassis?.available ?? 0
                let total = max(1, inUse + out + free)

                GeometryReader { geo in
                    let w = geo.size.width
                    let wIn = w * CGFloat(inUse) / CGFloat(total)
                    let wOut = w * CGFloat(out) / CGFloat(total)
                    let wFree = max(0, w - wIn - wOut)

                    ZStack(alignment: .topLeading) {
                        HStack(spacing: 0) {
                            segment(width: wIn,   fill: Brand.blue.opacity(0.30),    text: "\(inUse) IN USE", tint: Brand.blue)
                            segment(width: wOut,  fill: Brand.warning.opacity(0.30), text: "\(out) OUT",      tint: Brand.warning)
                            segment(width: wFree, fill: Brand.success.opacity(0.24), text: "\(free) FREE",    tint: Brand.success)
                        }
                        .clipShape(Capsule())
                        .frame(height: 18)

                        // Seam marker: 2x26 projecting from the OUT/FREE seam. No forecast behind it.
                        Rectangle()
                            .fill(Brand.warning)
                            .frame(width: 2, height: 26)
                            .offset(x: min(max(0, w - 2), wIn + wOut), y: 10)
                    }
                }
                .frame(height: 36)

                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Brand.warning)
                    Text("POOL BURN-DOWN NOT MODELLED · NOTHING FORECASTS THIS POOL")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(Brand.warning)
                }
            }
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func segment(width: CGFloat, fill: Color, text: String, tint: Color) -> some View {
        Rectangle()
            .fill(fill)
            .frame(width: max(0, width), height: 18)
            .overlay(
                Text(text)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .fixedSize()
                    .opacity(width > 44 ? 1 : 0)
            )
    }

    // MARK: ROW GRAMMAR — linked equipment pair glyph, pitch 60

    private var containerRows: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("CONTAINERS ON GROUND · PAIR STATE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(yardCrossCheck)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(burns.enumerated()), id: \.element.id) { idx, b in
                    containerRow(b)
                    if idx < burns.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1)
                    }
                }
            }
            .padding(.vertical, Space.s2)
            .eusoCard(radius: Radius.lg)

            Text("Drop-yard status and seal state are not tracked yet, so they are left blank rather than guessed. The spot shown above is the one on the container record, not a live yard assignment — verify it on the ground.")
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var yardCrossCheck: String {
        if yardUnavailable { return "yard cross-check unread" }
        guard let y = yard else { return "yard cross-check unread" }
        let t = y.total.map(String.init) ?? "?"
        let d = y.avgDwellHours.map { "\($0)h" } ?? "?"
        return "\(t) trailers · avg \(d)"
    }

    private func containerRow(_ b: Burn781) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            LinkedPairGlyph781(paired: b.paired, tint: rowTint(b))

            VStack(alignment: .leading, spacing: 3) {
                Text(b.number)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                Text(rowSub(b))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: Space.s2)

            VStack(alignment: .trailing, spacing: 3) {
                Text(b.lfdLabel.map { "LFD \($0)" } ?? "NO LFD")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                Text(tailLabel(b))
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(tailTint(b))
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s2)
    }

    private func rowTint(_ b: Burn781) -> Color {
        guard b.daysOnGround != nil, b.freeDays != nil else { return Brand.neutral }
        if b.overFree { return b.paired ? Brand.danger : Brand.warning }
        return Brand.success
    }

    private func rowSub(_ b: Burn781) -> String {
        var parts: [String] = []
        parts.append(b.spot.map { "spot \($0)" } ?? "no spot on file")
        if let l = b.line, !l.isEmpty { parts.append(l) }
        if !b.sizeType.isEmpty { parts.append(b.sizeType) }
        parts.append(b.paired ? "paired" : "pair broken")
        return parts.joined(separator: " · ")
    }

    // MARK: ESang — derived on device, and it says so

    private var esangNudge: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 28, height: 28)
                Circle().fill(Color.white.opacity(0.18)).frame(width: 12, height: 12).offset(x: -4, y: -4)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(esangLine)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(2)
                Text("derived on device from loaded rows · no coach call for vessel")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private var esangLine: String {
        guard let t = topBurner, let a = t.accrued else {
            return "Nothing is past its last free day right now."
        }
        return "Move \(t.number) first — \(Self.money(a)) and climbing."
    }

    // MARK: Tri-country footer (small, never a feature organ)

    private var triCountryFooter: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("PER-DIEM REGIME · TRI-COUNTRY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("USD · CAD · MXN")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 8) {
                regimeChip("US · UIIA", active: true)
                regimeChip("CA · SUFFERANCE", active: false)
                regimeChip("MX · RECINTO", active: false)
            }
        }
    }

    private func regimeChip(_ text: String, active: Bool) -> some View {
        HStack(spacing: 6) {
            if active { Circle().fill(Brand.blue).frame(width: 6, height: 6) }
            Text(text)
                .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                .foregroundStyle(active ? Brand.blue : palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(active ? Brand.blue.opacity(0.10) : palette.bgCardSoft))
        .overlay(Capsule().stroke(active ? Brand.blue.opacity(0.45) : Color.clear, lineWidth: 1))
    }

    // MARK: CTA pair — each face carries its own honesty

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(spacing: 8) {
                CTAButton(
                    title: "Refresh accrual",
                    action: { Task { await load() } },
                    subtitle: "LIVE LINK · ONLINE ONLY",
                    isLoading: loading
                )
                .frame(maxWidth: .infinity)

                Button {
                    showPickupGap = true
                } label: {
                    VStack(spacing: 2) {
                        Text("Request pickup")
                            .font(EType.title)
                            .foregroundStyle(palette.textPrimary)
                        Text("NO WRITE PATH · STUB")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(palette.bgCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .stroke(palette.borderSoft, lineWidth: 1)
                    )
                }
                .frame(maxWidth: .infinity)
            }

            if showPickupGap {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PICKUP REQUEST IS NOT BUILT")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(Brand.warning)
                    Text("A pickup cannot be requested from a container on this screen — moves are assigned against a queued yard move, not against a box. Nothing here would record an audit trail or notify the drayage carrier, so a drop-yard change reaches no counter-party today. Call the carrier.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                    Button("Dismiss") { showPickupGap = false }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Brand.blue)
                }
                .padding(Space.s4)
                .eusoCard(radius: Radius.md)
            }
        }
    }

    // MARK: Loading / error / empty

    private var loadingCard: some View {
        HStack(spacing: Space.s3) {
            ProgressView()
            Text("Reading the yard clock…")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func errorCard(_ msg: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("YARD CLOCK UNAVAILABLE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(Brand.danger)
            Text(msg).font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("No accrual is shown. A stale per-diem figure is worse than none.")
                .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("NO BOXES ON GROUND")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text("The container table returned no rows for this company. Nothing is accruing per-diem.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: - Network

    private func load() async {
        loading = true
        loadError = nil
        chassisUnavailable = false
        yardUnavailable = false

        let loc: String? = locationId.isEmpty ? nil : locationId

        do {
            let res: ContainerTrackingResponse781 = try await EusoTripAPI.shared.query(
                "yardManagement.getContainerTracking",
                input: ContainerQuery781(locationId: loc, status: nil, search: nil))
            // UNCONDITIONAL overwrite: an honest empty response clears the ladder and the rows.
            containers = res.containers
            loadedAt = Date()
        } catch {
            loadError = error.eusoUserCopy
            containers = []
        }

        // Chassis pool is the budget tape's only source. A failure hides the tape, never guesses it.
        do {
            let res: ChassisInventoryResponse781 = try await EusoTripAPI.shared.query(
                "yardManagement.getChassisInventory",
                input: ChassisQuery781(locationId: loc, status: nil))
            chassis = res.summary
            chassisUnavailable = (res.summary == nil)
        } catch {
            chassis = nil
            chassisUnavailable = true
        }

        // Yard cross-check. locationId is sent as nil on purpose: the procedure accepts it and never
        // reads it (yardManagement.ts:1720), so passing a value would imply a filter that does not run.
        // Only summary.total and summary.avgDwellHours are decoded — the other three are hardcoded.
        do {
            let res: DropYardResponse781 = try await EusoTripAPI.shared.query(
                "yardManagement.getDropYardOperations",
                input: DropYardQuery781(locationId: nil))
            yard = res.summary
            yardUnavailable = (res.summary == nil)
        } catch {
            yard = nil
            yardUnavailable = true
        }

        loading = false
    }

    // MARK: - Formatting helpers

    private static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd MMM"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func iso(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    private static func money(_ v: Double) -> String {
        "$" + v.formatted(.number.precision(.fractionLength(0)).grouping(.automatic))
    }
}

// MARK: - Linked equipment pair glyph (22x16 box chip + 10x3 bar + 20x10 chassis chip)
// The joining bar is DASHED when the box has no chassisId — a broken pair reads at a glance.

private struct LinkedPairGlyph781: View {
    @Environment(\.palette) private var palette
    let paired: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(tint.opacity(0.85))
                .frame(width: 22, height: 16)

            Group {
                if paired {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(LinearGradient.primary)
                        .frame(width: 10, height: 3)
                } else {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 1.5))
                        p.addLine(to: CGPoint(x: 10, y: 1.5))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 3, dash: [2.5, 2.5]))
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 10, height: 3)
                }
            }

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(paired ? tint.opacity(0.32) : palette.tintNeutral)
                .frame(width: 20, height: 10)
        }
        .frame(width: 52, height: 16)
        .accessibilityLabel(paired ? "box and chassis paired" : "box has no chassis, pair broken")
    }
}

// MARK: - Dashed rule (the visible READ_CACHED affordance)

private struct DashedRule781: View {
    @Environment(\.palette) private var palette
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0.5))
                p.addLine(to: CGPoint(x: geo.size.width, y: 0.5))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .foregroundStyle(palette.borderFaint)
        }
        .frame(height: 1)
    }
}

// MARK: - Previews

#Preview("781 Drop Yard Operations · Light") {
    VesselDropYardOperationsScreen(theme: Theme.light)
        .environment(\.palette, Theme.light)
}

#Preview("781 Drop Yard Operations · Dark") {
    VesselDropYardOperationsScreen(theme: Theme.dark)
        .environment(\.palette, Theme.dark)
}
