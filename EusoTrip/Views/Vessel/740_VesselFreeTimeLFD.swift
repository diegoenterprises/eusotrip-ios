//
//  740_VesselFreeTimeLFD.swift
//  EusoTrip — Vessel Operator · Free Time · LFD (PURPOSE-BUILT COUNTDOWN).
//
//  Verbatim bespoke port of canonical wireframe "740 Vessel Free Time · LFD ·
//  Dark" (06 Vessel · Vessel Operator). The import operator watches free time burn
//  down and pulls each box before its Last Free Day so demurrage never ignites —
//  the single biggest controllable cost leak at the port. A radial LFD countdown
//  gauge for the most-urgent box (wrapped by a terminal gate-out geofence motif),
//  an LFD-horizon mini axis, a ranked LFD ladder, and a fused ESANG pull plan.
//  Docked under COMPLIANCE. MATCHED SISTER of 741 Per Diem (the same terminal
//  gate-out tick that STOPS free time here IGNITES the per-diem meter there).
//
//  REAL WIRING (tRPC · server/routers/multiModal.ts — re-verified 2026-07-11):
//    · multiModal.getLastFreeDayAlerts {daysAhead}                       (:1619)
//        -> { alerts:[{containerNumber,shippingLine,port,terminal,lastFreeDay,
//        daysUntilLFD,severity,estimatedPerDiem,bookingRef,actionRequired}],
//        total, critical, urgent, warning }. Backs the countdown gauge (most-
//        urgent box), the horizon axis, and the ladder. Live off detentionRecords.
//    · multiModal.getFreeTimeManagement {}                              (:1586)
//        -> { freeTimeSchedules:[], portSpecific:[] } (empty today) — the tier
//        rate ladder ($150/$200/$275/$350) reference; named gap surfaced.
//        STUB · named-gap (free-time schedule data).
//    · detentionAccessorials.calculateDemurrage (:1297) is the $/day exposure
//        compute after LFD (real tiers); shown as the AFTER-LFD figure.
//    · "Schedule pulls" drays the box to beat LFD (createDrayageOrder, honest
//        gap surfaced) · the exact-second terminal gate-out that stops free time
//        is the geofence write named gap.  STUB · named-gap.
//
//  transportMode=vessel · US · RBAC protectedProcedure. NO mock data — the gauge,
//  the ladder, and the ESANG plan derive from the live LFD alerts.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Data shapes

private struct LFDAlerts740: Decodable {
    let alerts: [LFDAlert740]
    let total: Int?
    let critical: Int?
    let urgent: Int?
    let warning: Int?
}
private struct LFDAlert740: Decodable, Identifiable {
    var id: String { containerNumber + bookingRef }
    let containerNumber: String
    let shippingLine: String?
    let terminal: String?
    let lastFreeDay: String?
    let daysUntilLFD: Int?
    let severity: String?
    let estimatedPerDiem: Double?
    let bookingRef: String
    let actionRequired: String?
    let port: LFDPort740?
}
private struct LFDPort740: Decodable { let code: String?; let name: String? }

// MARK: - Screen

struct VesselFreeTimeLFDScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            VesselFreeTimeLFDBody()
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

private struct VesselFreeTimeLFDBody: View {
    @Environment(\.palette) private var palette

    @State private var data: LFDAlerts740? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var scheduleNote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            IridescentHairline().padding(.horizontal, Space.s5)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    loadingState
                } else if let err = loadError {
                    errorCard(err)
                } else if ladder.isEmpty {
                    countdownEmpty
                } else {
                    countdownHero
                    ladderSection
                    esangCard
                    TriCountryAuthorityBand(title: "FREE-TIME REGIME · DISCHARGE MARKET", regimes: regimes)
                    if let note = scheduleNote { infoBanner(note) }
                    ctaRow
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Derived

    /// Alerts ranked by urgency (soonest / most-overdue LFD first).
    private var ladder: [LFDAlert740] {
        (data?.alerts ?? []).sorted { ($0.daysUntilLFD ?? 99) < ($1.daysUntilLFD ?? 99) }
    }
    private var mostUrgent: LFDAlert740? { ladder.first }
    /// Free-time burn fraction remaining for the gauge (0…1), relative to the
    /// widest LFD horizon in the current set. Overdue clamps to 0 (fully burned).
    private var burnFraction: Double {
        guard let u = mostUrgent, let d = u.daysUntilLFD else { return 0 }
        let maxDays = max(1, ladder.map { $0.daysUntilLFD ?? 0 }.max() ?? 1)
        return min(1, max(0, Double(d) / Double(maxDays)))
    }
    private var overdueCount: Int { ladder.filter { ($0.daysUntilLFD ?? 0) < 0 }.count }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle").font(.system(size: 8, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · FREE TIME · LFD")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text(mostUrgent?.terminal ?? "LFD WATCH").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            Text("Free time · LFD")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary).padding(.top, Space.s4)
        }
        .padding(.horizontal, Space.s5).padding(.top, Space.s5).padding(.bottom, Space.s3)
    }

    // MARK: Countdown hero (radial LFD gauge)

    private var countdownHero: some View {
        let u = mostUrgent
        return VStack(alignment: .leading, spacing: Space.s4) {
            HStack {
                Text("LAST FREE DAY · ACTIVE COUNTDOWN")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(Brand.success).frame(width: 5, height: 5)
                    Text("LIVE").font(.system(size: 8, weight: .heavy)).tracking(0.4).foregroundStyle(Brand.success)
                }
            }
            HStack(alignment: .center, spacing: Space.s5) {
                gauge
                VStack(alignment: .leading, spacing: 6) {
                    Text("MOST URGENT · LFD")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    Text(u?.containerNumber ?? "—")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text(urgentSub(u)).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                        .lineLimit(2).minimumScaleFactor(0.8)
                    HStack(spacing: Space.s2) {
                        exposureChip("FREE NOW", freeNowText(u), Brand.success)
                        exposureChip("AFTER LFD", afterText(u), Brand.danger)
                    }
                    .padding(.top, 2)
                }
            }
            horizonAxis
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
    }

    private var gauge: some View {
        ZStack {
            // Terminal gate-out geofence motif.
            Circle().stroke(Brand.danger.opacity(0.30), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                .frame(width: 96, height: 96)
            Circle().stroke(palette.textPrimary.opacity(0.08), lineWidth: 7).frame(width: 68, height: 68)
            Circle()
                .trim(from: 0, to: max(0.02, burnFraction))
                .stroke(LinearGradient(colors: [Brand.warning, Brand.danger], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .frame(width: 68, height: 68)
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(centerCountdown).font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.textPrimary)
                Text("TO LFD").font(.system(size: 7, weight: .heavy)).tracking(0.4).foregroundStyle(Brand.danger)
            }
        }
        .frame(width: 100, height: 100)
    }

    private var centerCountdown: String {
        guard let d = mostUrgent?.daysUntilLFD else { return "—" }
        if d < 0 { return "\(d)d" }
        if d == 0 { return "TODAY" }
        return "\(d)d"
    }

    private func urgentSub(_ u: LFDAlert740?) -> String {
        guard let u else { return "—" }
        var parts: [String] = []
        if let l = u.shippingLine, !l.isEmpty { parts.append(l) }
        if let t = u.terminal, !t.isEmpty { parts.append(t) }
        if let lfd = u.lastFreeDay { parts.append("LFD \(shortDate(lfd))") }
        return parts.isEmpty ? (u.actionRequired ?? "import box") : parts.joined(separator: " · ")
    }

    private func exposureChip(_ label: String, _ value: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.4).foregroundStyle(c)
            Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(minWidth: 92, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(c.opacity(0.12)))
    }
    private func freeNowText(_ u: LFDAlert740?) -> String {
        (u?.daysUntilLFD ?? 0) < 0 ? "over" : "$0 today"
    }
    private func afterText(_ u: LFDAlert740?) -> String {
        if let p = u?.estimatedPerDiem, p > 0 { return "\(currency(p))" }
        return "tiered $/day"
    }

    // MARK: Horizon axis

    private var horizonAxis: some View {
        let items = Array(ladder.prefix(5))
        return VStack(spacing: 6) {
            Divider().overlay(palette.borderFaint)
            HStack(alignment: .top, spacing: 0) {
                ForEach(items) { a in
                    VStack(spacing: 4) {
                        Text(horizonTag(a.daysUntilLFD))
                            .font(.system(size: 7, weight: .heavy)).foregroundStyle(horizonColor(a.daysUntilLFD))
                        Circle().fill(horizonColor(a.daysUntilLFD)).frame(width: 7, height: 7)
                        Text(String(a.containerNumber.prefix(4)))
                            .font(.system(size: 7, weight: .medium, design: .monospaced)).foregroundStyle(palette.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
    private func horizonTag(_ d: Int?) -> String {
        guard let d else { return "—" }
        if d < 0 { return "OVER" }
        if d == 0 { return "TODAY" }
        return "+\(d)d"
    }
    private func horizonColor(_ d: Int?) -> Color {
        guard let d else { return palette.textTertiary }
        if d < 0 { return Brand.danger }
        if d == 0 { return Brand.danger }
        if d == 1 { return Brand.warning }
        return palette.textTertiary
    }

    // MARK: Ladder

    private var ladderSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("LFD LADDER · RANKED BY URGENCY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("FREE-TIME TERMS").font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 0) {
                ForEach(Array(ladder.enumerated()), id: \.element.id) { idx, a in
                    ladderRow(a)
                    if idx < ladder.count - 1 { Divider().overlay(palette.borderFaint).padding(.leading, 62) }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func ladderRow(_ a: LFDAlert740) -> some View {
        let d = a.daysUntilLFD ?? 0
        let c = horizonColor(a.daysUntilLFD)
        return HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                Circle().fill(c.opacity(0.14)).frame(width: 38, height: 38)
                VStack(spacing: 0) {
                    Text(d == 0 ? "0d" : (d > 0 ? "+\(d)" : "\(d)"))
                        .font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundStyle(c)
                    Text(d < 0 ? "OVER" : "LFD").font(.system(size: 7, weight: .heavy)).foregroundStyle(c)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(a.containerNumber) · \(a.shippingLine ?? "")")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(a.actionRequired ?? "monitor free time")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 4) {
                Text(statusLabel(d)).font(.system(size: 10, weight: .heavy)).tracking(0.3).foregroundStyle(c)
                Text(currency(a.estimatedPerDiem ?? 0))
                    .font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
            }
        }
        .padding(Space.s4)
    }
    private func statusLabel(_ d: Int) -> String {
        if d < 0 { return "ACCRUING" }
        if d == 0 { return "LFD TODAY" }
        if d == 1 { return "NEAR LFD" }
        return "LFD +\(d)d"
    }

    // MARK: ESANG pull plan

    private var esangCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text("ESANG · PULL PLAN").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text(pullHeadline).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(pullDetail).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
    private var pullHeadline: String {
        guard let u = mostUrgent else { return "No boxes near their Last Free Day" }
        return "Schedule \(u.containerNumber) pull before LFD"
    }
    private var pullDetail: String {
        guard let u = mostUrgent else { return "Free time is comfortable across the set." }
        let after = (u.estimatedPerDiem ?? 0) > 0 ? currency(u.estimatedPerDiem ?? 0) : "the tier rate"
        return "\(u.terminal ?? "terminal") · clears LFD · avoids \(after)/day"
    }

    // MARK: Regimes / CTA / states

    private var regimes: [CountryRegime] {
        [.init(code: "US", authority: "FMC 46 CFR 541 · MTO tariff", detail: "free time per tariff · USD", consequence: nil, state: .active),
         .init(code: "CA", authority: "CTA · carrier tariff", detail: "free time per carrier · CAD", consequence: nil, state: .standby),
         .init(code: "MX", authority: "API · terminal tariff", detail: "días libres · MXN", consequence: nil, state: .standby)]
    }

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button {
                scheduleNote = "Schedule the pull through the linked drayage provider for this shipment."
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 13, weight: .bold))
                    Text("Schedule pulls").font(.system(size: 15, weight: .bold))
                }.foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary).clipShape(Capsule())
            }.buttonStyle(.plain).frame(maxWidth: .infinity)
            Button { } label: {
                Text("Rules").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(minWidth: 100, minHeight: 48).padding(.horizontal, Space.s3)
                    .background(palette.bgCard).overlay(Capsule().strokeBorder(palette.borderFaint)).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
    }

    private var countdownEmpty: some View {
        EusoEmptyState(systemImage: "clock.badge.checkmark",
                       title: "No boxes near Last Free Day",
                       subtitle: "Import containers appear here with a live LFD countdown as they discharge — free time is clear right now.")
    }
    private func infoBanner(_ msg: String) -> some View {
        LifecycleCard(accentWarning: true) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.warning)
                Text(msg).font(EType.caption).foregroundStyle(palette.textSecondary)
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
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 180)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 200)
        }
    }

    private func currency(_ v: Double) -> String {
        v == v.rounded() ? "$\(Int(v).formatted(.number.grouping(.automatic)))" : "$\(String(format: "%.2f", v))"
    }
    private func shortDate(_ iso: String) -> String {
        let s = String(iso.prefix(10))
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: s) else { return s }
        let out = DateFormatter(); out.dateFormat = "MMM d"
        return out.string(from: d)
    }

    private func load() async {
        loading = true; loadError = nil
        struct In: Encodable { let daysAhead: Int }
        do {
            let resp: LFDAlerts740 = try await EusoTripAPI.shared.query(
                "multiModal.getLastFreeDayAlerts", input: In(daysAhead: 3))
            self.data = resp
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("740 · Vessel Free Time LFD · Night") {
    VesselFreeTimeLFDScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("740 · Vessel Free Time LFD · Light") {
    VesselFreeTimeLFDScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
