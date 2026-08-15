//
//  811_VesselClaimsAnalytics.swift
//  EusoTrip — Vessel Operator · Claims Analytics.
//
//  Faithful 1:1 port of the RECONSTRUCTED "811 Vessel Claims Analytics.svg" (Light + Dark) into the
//  RECOVERY-BAR-BOARD archetype: a recovery-rate hero (recovery% + disputed/recovered + trend), then a
//  PEER-RECOVERY board where every carrier is a horizontal recovery-bar row (filled track in success/
//  warning/danger by recovery%), a by-peril PROPORTIONAL stacked bar with legend, the ESang
//  renegotiation-lever advisory, and the Export YTD / Compare CTA pair. Nav anchored to the registered
//  vessel sibling wrapper (757/809/810): Shell + BottomNav (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME),
//  COMPLIANCE inked (claims is a compliance domain).
//
//  Data / wiring (endpoint MCP-confirmed this fire · frontend/server/routers/freightClaims.ts):
//    HERO + BARS + PERIL: freightClaims.getClaimsAnalytics EXISTS :1160 — protectedProcedure ·
//        input { period: "month"|"quarter"|"year" } (NO mode field — the procedure ignores extras, so
//        we send period only). Returns { frequency, avgCost, avgResolutionDays, byType[{type,count,value}],
//        byMonth, byStatus, topCarriers[{carrier,claimCount,totalValue} | {carrier,count,value,recoveryPct}],
//        recoveryRate }. NOTE recoveryRate is a FRACTION (0.72) not a percentage — we ×100. topCarriers
//        ships two candidate shapes across the db/fallback branches; we decode both optionally.
//    COMPARE:  freightClaims.getClaimsDashboard / getDisputeResolution EXIST (drill targets) — Compare is
//        a no-op nav placeholder here (the journey hub owns the push).
//    WRITE (export): STUB · named-gap exportClaimsAnalytics — no backing mutation today; "Export YTD"
//        re-runs load() honestly rather than faking a file write (surfaced to the-oath).
//    RBAC: protectedProcedure.
//
//  ZERO-FALLBACK: state is em-dash/empty/nil-initialized and UNCONDITIONALLY overwritten by the
//  query — no design-time seeds; trend/SLA (no server source) stay hidden; empty peer/peril data
//  renders honest empty states. RimCard811 / secondaryButton811 /
//  PeerBar811 / FlowLegend811 are file-scoped bespoke helpers (the canonical port's
//  RimCard / SecondaryButton are not shared app symbols), built from the registered siblings' grammar to
//  preserve the exact wireframe look.
//

import SwiftUI

private enum PeerTone811 { case best, median, worst }
private struct PeerRow811: Identifiable {
    let id = UUID(); let carrier: String; let sub: String; let pct: Int; let value: String; let tone: PeerTone811
}
private struct PerilSeg811: Identifiable {
    let id = UUID(); let label: String; let value: Double; let color: Color
}

struct VesselClaimsAnalyticsScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselClaimsAnalyticsBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselClaimsAnalyticsBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil

    // ZERO-FALLBACK: em-dash/empty/nil init — values render live or honestly
    // absent. trend/slaLine have NO server source today (getClaimsAnalytics
    // carries no trend or SLA field) so they stay nil and their views hide.
    @State private var subline = "—"
    @State private var recoveryRate = "—"
    @State private var recoverySub: String? = nil
    @State private var trend: String? = nil
    @State private var cycleLine: String? = nil
    @State private var slaLine: String? = nil
    @State private var esangLine: String? = nil

    @State private var peers: [PeerRow811] = []
    @State private var perils: [PerilSeg811] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("Claims analytics").font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Text(subline).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()

                if loading {
                    RimCard811 { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    RimCard811 { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    recoveryHero
                    Text("PEER RECOVERY · top carriers")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    peerCard
                    Text("BY PERIL · \(perilTotalLabel)")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    perilCard
                    esangCard
                    HStack(spacing: 8) {
                        CTAButton(title: "Export YTD", action: { Task { await exportYtd() } }, trailingIcon: "square.and.arrow.up")
                        secondaryButton811(title: "Compare") {}
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · CLAIMS ANALYTICS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("2026 YTD · OCEAN").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            HStack(spacing: 6) {
                Text("Claims").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var recoveryHero: some View {
        RimCard811 {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RECOVERY RATE · 2026 YTD · OCEAN BOOK").font(.system(size: 9, weight: .heavy)).tracking(0.9).foregroundStyle(palette.textTertiary)
                    Text(recoveryRate).font(.system(size: 44, weight: .bold)).tracking(-1)
                        .foregroundStyle(palette.textPrimary).monospacedDigit()
                    Text(recoverySub ?? "—").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 6) {
                    // Trend/SLA render ONLY when the server supplies them — no source today.
                    if let t = trend { StatusPill(text: t, kind: .success) }
                    Text(cycleLine ?? "—").font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).monospacedDigit()
                    if let s = slaLine {
                        Text(s).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).monospacedDigit()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var peerCard: some View {
        if peers.isEmpty {
            // Honest empty — getClaimsAnalytics.topCarriers returns [] today;
            // no invented Maersk/ONE/CMA-CGM ladder.
            EusoEmptyState(systemImage: "chart.bar",
                           title: "No peer recovery data yet",
                           subtitle: "Per-carrier recovery bars appear once carrier-attributed claims land in the analytics.")
        } else {
            VStack(spacing: 18) {
                ForEach(peers) { p in PeerBar811(row: p) }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(palette.borderFaint))
        }
    }

    @ViewBuilder
    private var perilCard: some View {
        if perils.isEmpty {
            EusoEmptyState(systemImage: "chart.pie",
                           title: "No peril breakdown yet",
                           subtitle: "The by-peril split appears once claims are on the book for this period.")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { geo in
                    let total = max(0.0001, perils.reduce(0) { $0 + $1.value })
                    HStack(spacing: 2) {
                        ForEach(perils) { seg in
                            RoundedRectangle(cornerRadius: 3).fill(seg.color)
                                .frame(width: max(4, geo.size.width * CGFloat(seg.value / total)))
                        }
                    }
                }.frame(height: 14)
                FlowLegend811(perils: perils)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 18).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(palette.borderFaint))
        }
    }

    @ViewBuilder
    private var esangCard: some View {
        // Renders only off live peer data — never a fabricated lever/exposure line.
        if !peers.isEmpty, let line = esangLine {
            HStack(spacing: 12) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(worstPeerName) \(worstPeerPct)% is the Q3 renegotiation lever").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text("ESang · \(line)").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.borderFaint))
        }
    }

    // MARK: Derived
    private var perilTotalLabel: String {
        guard !perils.isEmpty else { return "—" }
        let total = perils.reduce(0) { $0 + $1.value }
        return money(total)
    }
    private var worstPeerName: String { peers.first(where: { $0.tone == .worst })?.carrier.components(separatedBy: " ·").first ?? "-" }
    private var worstPeerPct: Int { peers.first(where: { $0.tone == .worst })?.pct ?? 0 }

    // MARK: Data
    /// topCarriers ships two candidate shapes across the live-db vs fallback branches —
    /// {carrier,claimCount,totalValue} and {carrier,count,value,recoveryPct} — so every
    /// field is decoded optionally and coalesced.
    private struct Carrier811: Decodable {
        let carrier: String?
        let count: Int?; let claimCount: Int?
        let value: Double?; let totalValue: Double?
        let recoveryPct: Double?
        var resolvedCount: Int { count ?? claimCount ?? 0 }
        var resolvedValue: Double? { value ?? totalValue }
    }
    private struct PerilType811: Decodable { let type: String?; let count: Int?; let value: Double? }
    private struct Analytics811: Decodable {
        let topCarriers: [Carrier811]?; let byType: [PerilType811]?
        let recoveryRate: Double?; let avgResolutionDays: Double?; let frequency: Int?
    }
    private struct AnalyticsInput811: Encodable { let period: String }

    private func load() async {
        loading = true; loadError = nil
        do {
            let a: Analytics811 = try await EusoTripAPI.shared.query("freightClaims.getClaimsAnalytics",
                                                                     input: AnalyticsInput811(period: "year"))
            // recoveryRate is a FRACTION (0.72) — render as a percentage.
            recoveryRate = a.recoveryRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
            cycleLine = a.avgResolutionDays.map { "\(Int($0.rounded()))d avg cycle" }

            // Claimed dollars = live byType sum; recovered = rate × claimed (both
            // server fields). No invented $116.4k/$214.6k pair.
            let claimed = (a.byType ?? []).reduce(0.0) { $0 + ($1.value ?? 0) }
            subline = "\(a.frequency ?? 0) claims · claimed \(money(claimed)) · 2026 YTD"
            if claimed > 0, let r = a.recoveryRate {
                recoverySub = "\(money(claimed * r)) recovered of \(money(claimed)) claimed"
            } else {
                recoverySub = nil
            }
            // trend / slaLine: NO server source on getClaimsAnalytics — stay nil (hidden).
            trend = nil
            slaLine = nil

            // UNCONDITIONAL overwrite — empty stays empty (honest states render).
            if let tc = a.topCarriers, !tc.isEmpty {
                peers = tc.prefix(3).enumerated().map { idx, c in
                    let tone: PeerTone811 = idx == 0 ? .best : (idx == tc.count - 1 ? .worst : .median)
                    return PeerRow811(carrier: c.carrier ?? "-",
                                      sub: "\(c.resolvedCount) claims",
                                      pct: Int((c.recoveryPct ?? 0).rounded()),
                                      value: money(c.resolvedValue), tone: tone)
                }
                let best = peers.map(\.pct).max() ?? 0
                let worst = peers.first(where: { $0.tone == .worst })
                esangLine = worst.map { "\(max(0, best - $0.pct)) pts below best peer · \($0.value) exposure" }
            } else {
                peers = []
                esangLine = nil
            }
            if let bt = a.byType, !bt.isEmpty {
                let colors: [Color] = [Brand.danger, Brand.info, Brand.warning, Brand.neutral]
                perils = bt.prefix(4).enumerated().map { idx, t in
                    PerilSeg811(label: "\(t.type ?? "-") " + money(t.value), value: t.value ?? 0, color: colors[idx % colors.count])
                }
            } else {
                perils = []
            }
        } catch {
            loadError = error.eusoUserCopy
        }
        loading = false
    }

    /// exportClaimsAnalytics — STUB · named-gap (no backing mutation today); re-run load() honestly.
    private func exportYtd() async { await load() }

    private func money(_ v: Double?) -> String {
        guard let v else { return "-" }
        return v >= 1000 ? "$\(String(format: "%.1f", v/1000))k" : "$\(Int(v))"
    }

    /// Bespoke secondary (outline) button — the canonical port's `SecondaryButton`
    /// is not a shared app symbol, so we hand-roll the same outline grammar the
    /// registered siblings (757/809) use for their secondary CTA.
    private func secondaryButton811(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.blue)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - File-scoped bespoke helpers (preserve the canonical wireframe look)

private struct PeerBar811: View {
    let row: PeerRow811
    @Environment(\.palette) private var palette
    private var color: Color {
        switch row.tone { case .best: return Brand.success; case .median: return Brand.warning; case .worst: return Brand.danger }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.carrier).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text(row.sub).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(row.pct)%").font(.system(size: 15, weight: .heavy)).foregroundStyle(color).monospacedDigit()
                    Text(row.value).font(.system(size: 10.5, weight: .bold)).foregroundStyle(palette.textTertiary).monospacedDigit()
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.borderFaint).frame(height: 6)
                    Capsule().fill(color).frame(width: geo.size.width * CGFloat(row.pct) / 100, height: 6)
                }
            }.frame(height: 6)
        }
    }
}

private struct FlowLegend811: View {
    let perils: [PerilSeg811]
    @Environment(\.palette) private var palette
    var body: some View {
        HStack(spacing: 10) {
            ForEach(perils) { seg in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(seg.color).frame(width: 8, height: 8)
                    Text(seg.label).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Gradient-rim hero card — mirrors the gradient-stroked context cards the
/// registered siblings (757 `RimCard757`, 664 `moveContextCard`) ship; the
/// canonical port's `RimCard` is not a shared app symbol.
private struct RimCard811<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
            )
    }
}

#Preview("811 · Vessel Claims Analytics · Night") { VesselClaimsAnalyticsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("811 · Vessel Claims Analytics · Light") { VesselClaimsAnalyticsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
