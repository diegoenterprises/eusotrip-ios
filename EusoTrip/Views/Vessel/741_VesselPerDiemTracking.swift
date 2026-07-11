//
//  741_VesselPerDiemTracking.swift
//  EusoTrip — Vessel Operator · Per Diem (PURPOSE-BUILT ACCRUAL METER).
//
//  Verbatim bespoke port of canonical wireframe "741 Vessel Per Diem · Dark"
//  (06 Vessel · Vessel Operator). The operator watches per-diem accrue by the day
//  across the import fleet and returns each empty container before it crosses the
//  next rate tier, so the bill is contained instead of discovered. A live accrual
//  meter (a tier-banded rail — Day1-2 $150 / Day3-5 $200 / Day6-10 $275 / Day11+
//  $350 — with a ticking day-marker), an accrual-state stepper, a line/rate ledger
//  with ACCRUING/DISPUTED/PAID states, and a fused ESANG return plan. Docked under
//  COMPLIANCE. MATCHED SISTER of 740 Free Time (the terminal gate-out tick that
//  stops free time there IGNITES this meter).
//
//  REAL WIRING (tRPC — re-verified 2026-07-11):
//    · multiModal.getPerDiemTracking {limit}                             (:1390)
//        -> { records:[{containerNumber,shippingLine,status,daysAccrued,dailyRate,
//        totalCharges,location,bookingRef}], summary:{totalAccruing,totalCharges,
//        avgDaysOver} }. Backs the hero total, the meter marker, and the ledger.
//        Live off detentionRecords.
//    · detentionAccessorials.getDetentionDashboard {}          (:450) -> billed /
//        collected / disputed amounts + active count → the accrual-state stepper.
//    · detentionAccessorials.getActiveDetentions {}            (:577) -> the live
//        accruing claims (numeric claimId) targeted by the dispute verb.
//    · detentionAccessorials.disputeDetention {claimId,reason} mutation (:1083)
//        -> the REAL "Dispute charge" verb (holds the line under review).
//    · The exact-second gate-out / empty-return geofence stamps that ignite/stop
//        the meter are the named gap.  STUB · named-gap.
//
//  transportMode=vessel · US · RBAC protectedProcedure. NO mock data — the total,
//  the meter, the ledger, and the ESANG plan derive from the live per-diem rollup.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Data shapes

private struct PerDiemTracking741: Decodable {
    let records: [PerDiemRow741]
    let summary: PerDiemSummary741?
}
private struct PerDiemSummary741: Decodable {
    let totalAccruing: Int?
    let totalCharges: Double?
    let avgDaysOver: Double?
}
private struct PerDiemRow741: Decodable, Identifiable {
    let id: String
    let containerNumber: String?
    let shippingLine: String?
    let status: String?
    let daysAccrued: Int?
    let dailyRate: Double?
    let totalCharges: Double?
    let location: String?
    let bookingRef: String?
}
private struct DetentionDashboard741: Decodable {
    let activeDetentions: Int?
    let billedAmount: Double?
    let collectedAmount: Double?
    let disputedAmount: Double?
}
private struct ActiveDetentions741: Decodable { let detentions: [ActiveDetentionRow741] }
private struct ActiveDetentionRow741: Decodable, Identifiable {
    let id: Int
    let facilityName: String?
    let currentCharge: Double?
    let status: String?
}

// MARK: - Screen

struct VesselPerDiemTrackingScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            VesselPerDiemTrackingBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle)
        }
    }
}

// MARK: - Body

private struct VesselPerDiemTrackingBody: View {
    @Environment(\.palette) private var palette

    @State private var tracking: PerDiemTracking741? = nil
    @State private var dash: DetentionDashboard741? = nil
    @State private var active: ActiveDetentions741? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var disputing = false
    @State private var disputeAck: String? = nil
    @State private var disputeError: String? = nil

    // Tier reference (real FMC-style ladder, dollars per day).
    private let tiers: [(label: String, band: String, rate: Int, days: ClosedRange<Int>)] = [
        ("$150", "DAY 1-2", 150, 1...2),
        ("$200", "DAY 3-5", 200, 3...5),
        ("$275", "DAY 6-10", 275, 6...10),
        ("$350", "DAY 11+", 350, 11...30),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            IridescentHairline().padding(.horizontal, Space.s5)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    loadingState
                } else if let err = loadError {
                    errorCard(err)
                } else {
                    accrualHero
                    stateStepper
                    ledgerSection
                    esangCard
                    countrySegment
                    if let ack = disputeAck { ackBanner(ack) }
                    if let err = disputeError { errBanner(err) }
                    ctaRow
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Derived

    private var records: [PerDiemRow741] { tracking?.records ?? [] }
    private var accruing: [PerDiemRow741] { records.filter { statusKey($0.status) == "accruing" } }
    private var accruingTotal: Double {
        tracking?.summary?.totalCharges ?? records.reduce(0) { $0 + ($1.totalCharges ?? 0) }
    }
    private var accruingCount: Int { tracking?.summary?.totalAccruing ?? accruing.count }
    private var avgDaysOver: Double { tracking?.summary?.avgDaysOver ?? 0 }
    private var maxDaysAccrued: Int { records.map { $0.daysAccrued ?? 0 }.max() ?? 0 }
    private var topRate: Int { tierFor(maxDaysAccrued).rate }

    private func statusKey(_ s: String?) -> String { (s ?? "").lowercased() }
    private func tierFor(_ days: Int) -> (label: String, band: String, rate: Int, days: ClosedRange<Int>) {
        tiers.first { $0.days.contains(days) } ?? tiers[0]
    }
    /// Fraction 0…1 the day-marker sits along the 4-band rail.
    private var markerFraction: Double {
        let d = max(1, min(14, maxDaysAccrued == 0 ? 1 : maxDaysAccrued))
        return min(1, Double(d) / 14.0)
    }

    /// First real accruing detention claim (numeric id) for the dispute verb.
    private var disputeTarget: ActiveDetentionRow741? {
        (active?.detentions ?? []).first { statusKey($0.status) == "accruing" }
            ?? (active?.detentions ?? []).first
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle").font(.system(size: 8, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · PER DIEM")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("LIVE").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            Text("Per diem")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary).padding(.top, Space.s4)
        }
        .padding(.horizontal, Space.s5).padding(.top, Space.s5).padding(.bottom, Space.s3)
    }

    // MARK: Accrual meter hero

    private var accrualHero: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(currency(accruingTotal))
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(LinearGradient.primary)
                    Text("accruing this month · across \(records.count) container\(records.count == 1 ? "" : "s")")
                        .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ACCRUING").font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
                    Text("\(accruingCount)").font(.system(size: 26, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text(avgDaysOver > 0 ? String(format: "avg %.1fd over", avgDaysOver) : "on free time")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(Brand.warning)
                }
            }
            tierRail
        }
        .padding(Space.s5).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
    }

    private var tierRail: some View {
        let tierColors: [Color] = [Brand.success, Brand.warning, Color(hex: 0xFF7043), Brand.danger]
        return VStack(alignment: .leading, spacing: 6) {
            Text("RATE LADDER · top box at DAY \(maxDaysAccrued) · +$\(topRate)/day")
                .font(.system(size: 9, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textTertiary)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 3) {
                        ForEach(0..<4, id: \.self) { i in
                            Capsule().fill(tierColors[i].opacity(0.45)).frame(maxWidth: .infinity)
                        }
                    }
                    // Live day marker.
                    Circle().fill(Brand.warning).frame(width: 11, height: 11)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .offset(x: min(w - 11, max(0, w * markerFraction - 5.5)))
                }
            }
            .frame(height: 10)
            HStack(spacing: 3) {
                ForEach(Array(tiers.enumerated()), id: \.offset) { i, t in
                    VStack(spacing: 1) {
                        Text(t.label).font(.system(size: 8, weight: i == currentTierIdx ? .heavy : .bold))
                            .foregroundStyle(i == currentTierIdx ? Brand.warning : palette.textTertiary)
                        Text(t.band).font(.system(size: 6.5, weight: .heavy)).tracking(0.2).foregroundStyle(palette.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
    private var currentTierIdx: Int { tiers.firstIndex { $0.days.contains(max(1, maxDaysAccrued)) } ?? 0 }

    // MARK: Accrual-state stepper

    private var stateStepper: some View {
        let stages = ["FREE", "ACCRUING", "DISPUTED", "BILLED", "SETTLED"]
        let currentIdx = currentStageIdx
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("ACCRUAL STATE · stage \(currentIdx + 1) of 5")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("detentionRecords").font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.offset) { idx, s in
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().fill(idx <= currentIdx ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.textPrimary.opacity(0.10)))
                                .frame(width: idx == currentIdx ? 18 : 14, height: idx == currentIdx ? 18 : 14)
                            if idx < currentIdx {
                                Image(systemName: "checkmark").font(.system(size: 7, weight: .heavy)).foregroundStyle(.white)
                            } else if idx == currentIdx {
                                Circle().fill(Brand.warning).frame(width: 7, height: 7)
                            }
                        }
                        Text(s).font(.system(size: 8, weight: .heavy)).tracking(0.2)
                            .foregroundStyle(idx <= currentIdx ? palette.textPrimary : palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity)
                    if idx < stages.count - 1 {
                        Rectangle().fill(idx < currentIdx ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.textPrimary.opacity(0.10)))
                            .frame(height: 2).offset(y: -9)
                    }
                }
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
    private var currentStageIdx: Int {
        if (dash?.collectedAmount ?? 0) > 0 && accruingCount == 0 { return 4 }
        if (dash?.billedAmount ?? 0) > 0 { return 3 }
        if (dash?.disputedAmount ?? 0) > 0 { return 2 }
        if accruingCount > 0 { return 1 }
        return 0
    }

    // MARK: Ledger

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("ACCRUAL BREAKDOWN · LINE / RATE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("calculateDetention").font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
            }
            if records.isEmpty {
                EusoEmptyState(systemImage: "clock.badge.exclamationmark",
                               title: "No per-diem accruing",
                               subtitle: "Empty containers appear here with their live daily accrual as detention starts.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(records.enumerated()), id: \.element.id) { idx, r in
                        ledgerRow(r)
                        if idx < records.count - 1 { Divider().overlay(palette.borderFaint).padding(.leading, 68) }
                    }
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func ledgerRow(_ r: PerDiemRow741) -> some View {
        let st = statusKey(r.status)
        let (label, c, glyph): (String, Color, String) = {
            switch st {
            case "accruing": return ("ACCRUING", Brand.warning, "clock.fill")
            case "disputed": return ("DISPUTED", Brand.escort, "exclamationmark.triangle.fill")
            case "paid":     return ("PAID", Brand.success, "checkmark.circle.fill")
            case "waived":   return ("WAIVED", palette.textTertiary, "minus.circle.fill")
            default:         return (st.uppercased(), palette.textSecondary, "clock")
            }
        }()
        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(c.opacity(0.14)).frame(width: 40, height: 40)
                Image(systemName: glyph).font(.system(size: 16, weight: .semibold)).foregroundStyle(c)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(r.containerNumber ?? "container") · \(r.shippingLine ?? "")")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(ledgerMeta(r)).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 4) {
                Text(label).font(.system(size: 10, weight: .heavy)).tracking(0.4).foregroundStyle(c)
                Text(currency(r.totalCharges ?? 0))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(st == "paid" ? palette.textSecondary : palette.textPrimary)
            }
        }
        .padding(Space.s4)
    }
    private func ledgerMeta(_ r: PerDiemRow741) -> String {
        var parts: [String] = []
        let d = r.daysAccrued ?? 0
        if d > 0, let rate = r.dailyRate, rate > 0 { parts.append("\(d)d × \(currency(rate))/d") }
        if let loc = r.location, !loc.isEmpty { parts.append(loc) }
        return parts.isEmpty ? (r.bookingRef ?? "detention line") : parts.joined(separator: " · ")
    }

    // MARK: ESANG return plan

    private var esangCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text("ESANG · RETURN PLAN").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(returnHeadline).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(returnDetail).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
    private var returnHeadline: String {
        guard let top = accruing.max(by: { ($0.totalCharges ?? 0) < ($1.totalCharges ?? 0) }) else {
            return "No empties accruing per-diem right now"
        }
        return "Return \(top.containerNumber ?? "the top empty") before the next tier"
    }
    private var returnDetail: String {
        let d = maxDaysAccrued
        let next = tiers.first { $0.days.lowerBound > d }
        if let n = next { return "Stops the meter before the day-\(n.days.lowerBound) $\(n.rate) tier" }
        return "Times the empty return to contain the daily bill."
    }

    // MARK: Country segment

    private var countrySegment: some View {
        CountrySegment(chips: [
            .init(code: "US · FMC", instrument: "TIERED $/DAY · USD", active: true),
            .init(code: "CA · CTA", instrument: "CARRIER TARIFF · CAD", active: false),
            .init(code: "MX · SAT", instrument: "ESTADÍAS · MXN", active: false)])
    }

    // MARK: CTA

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button { Task { await dispute() } } label: {
                HStack(spacing: 6) {
                    if disputing { ProgressView().tint(.white).scaleEffect(0.8) }
                    Image(systemName: "exclamationmark.bubble.fill").font(.system(size: 13, weight: .bold))
                    Text(disputing ? "Filing…" : "Dispute charge").font(.system(size: 15, weight: .bold))
                }.foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary).clipShape(Capsule())
            }.buttonStyle(.plain).disabled(disputing).frame(maxWidth: .infinity)
            Button { } label: {
                Text("Export").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(minWidth: 110, minHeight: 48).padding(.horizontal, Space.s3)
                    .background(palette.bgCard).overlay(Capsule().strokeBorder(palette.borderFaint)).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
    }

    // MARK: States / format

    private func ackBanner(_ msg: String) -> some View {
        LifecycleCard(accentGradient: true) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text(msg).font(EType.caption).foregroundStyle(palette.textPrimary)
            }
        }
    }
    private func errBanner(_ msg: String) -> some View {
        LifecycleCard(accentDanger: true) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                Text(msg).font(EType.caption).foregroundStyle(Brand.danger)
            }
        }
    }
    private func errorCard(_ err: String) -> some View {
        LifecycleCard(accentDanger: true) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            }
        }
    }
    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 172)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 200)
        }
    }
    private func currency(_ v: Double) -> String {
        v == v.rounded() ? "$\(Int(v).formatted(.number.grouping(.automatic)))" : "$\(String(format: "%.2f", v))"
    }

    // MARK: Load / mutate

    private func load() async {
        loading = true; loadError = nil
        struct PdIn: Encodable { let limit: Int }
        do {
            async let t: PerDiemTracking741 = EusoTripAPI.shared.query("multiModal.getPerDiemTracking", input: PdIn(limit: 50))
            async let d: DetentionDashboard741 = EusoTripAPI.shared.queryNoInput("detentionAccessorials.getDetentionDashboard")
            async let a: ActiveDetentions741 = EusoTripAPI.shared.queryNoInput("detentionAccessorials.getActiveDetentions")
            let (tr, ds, ac) = try await (t, d, a)
            self.tracking = tr; self.dash = ds; self.active = ac
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func dispute() async {
        disputeAck = nil; disputeError = nil
        guard let target = disputeTarget else {
            disputeError = "No accruing detention claim to dispute yet."
            return
        }
        disputing = true
        struct In: Encodable { let claimId: Int; let reason: String }
        struct Res: Decodable { let success: Bool? }
        let reason = "Per-diem rate/tier under review for \(target.facilityName ?? "this facility") — requesting billing correction."
        do {
            let res: Res = try await EusoTripAPI.shared.mutation(
                "detentionAccessorials.disputeDetention", input: In(claimId: target.id, reason: reason))
            if res.success == true {
                disputeAck = "Dispute filed on claim #\(target.id) · held under review."
                await load()
            } else {
                disputeError = "Dispute did not confirm. Try again."
            }
        } catch {
            disputeError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        disputing = false
    }
}

#Preview("741 · Vessel Per Diem · Night") {
    VesselPerDiemTrackingScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("741 · Vessel Per Diem · Light") {
    VesselPerDiemTrackingScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
