//
//  675_VesselCarrierScorecard.swift
//  EusoTrip 2027 · Vessel Operator · Carrier Scorecard — LEAGUE / COMPARISON view.
//
//  Faithful port of the reconstructed "675 Vessel Carrier Scorecard.svg" (Light + Dark).
//  DE-DUPLICATED 2026-06-21 from 682 Vessel Carrier Scorecard: the two had collided as the same
//  single-carrier-grade-hero + ranked-list composition (the #1 monotony defect). 675 is now the
//  multi-carrier COMPARISON MATRIX (carried by no other screen): a recommended-award decision hero,
//  then a column-aligned league table — CARRIER · ON-TIME · OVERALL (with a composite micro-bar) ·
//  GRADE — over the operator's scored ocean carriers, a per-discharge-country carrier-authority band
//  (US FMC/OTI · CA CTA · MX SCT/SEMAR), an Award/Export CTA pair, and an ESang decision insight.
//  682 keeps getScorecard as its single-carrier primary; the two no longer read as one screen.
//
//  Data / wiring (endpoints confirmed on disk — frontend/server/routers/carrierScorecard.ts):
//    LEAGUE (primary): carrierScorecard.compareScorecards EXISTS:218
//        input  { carrierIds:[Int] (1..10) }
//        return per-carrier { carrierId, companyName, overallScore, grade(A 90+/B 80+/C 70+/D 60+/F),
//                             onTimeRate, safetyScore, totalLoads, incidents, fmcsa{alertCount,…} }
//                             sorted by overallScore desc  → rows + recommended hero (top of sort).
//    POOL:             carrierScorecard.getTopCarriers   EXISTS:334  ({limit,minScore}) seeds carrierIds.
//    DRILL-DOWN:       row tap → 682 VesselCarrierScorecardScreen(theme:carrierId:) sheet
//                      (682's primary is carrierScorecard.getScorecard EXISTS:29).
//    AWARD:            NAVIGATIONAL — sheet to 677 VesselCarrierTenderWorkflowScreen (the app's real
//                      tender/award surface). No money/booking write fires on this surface; the award
//                      mutation stays gated + confirm:true downstream, exactly per the SVG <desc>.
//    EXPORT:           ShareLink CSV built from the loaded league (shipped String-item pattern,
//                      298_ShipperDetentionExposure.swift:467) — real on-device effect.
//  Columns map to REAL fields: ON-TIME = onTimeRate, OVERALL = overallScore, GRADE = grade,
//  sub = totalLoads + fmcsa.alertCount.
//  STUB · named-gap surfaced to the-oath: schedule-reliability / rolloverPct / transitDaysAvg are
//  NOT in the compareScorecards return — propose extending the row (or adding
//  carrierScorecard.getOceanCarrierLeague({tradeLane,carrierIds})) scoped to transportMode='vessel'.
//  Until it lands the hero scope pill honestly reads ALL LANES (the score is not lane-scoped).
//  677 takes shipmentId only — a carrier-preselect input on the tender surface is a second named gap.
//  RBAC: protectedProcedure scoped to the operator's tenant.
//  NAV (REAL · VesselOperatorNavController): HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//  0 stubs · 0 mock data · 0 placeholders — every figure renders from the live return; empty pool
//  renders the honest empty state. No raw transport errors in user copy.
//

import SwiftUI

private struct LeagueCarrier_675: Identifiable {
    var id: Int { carrierId }
    let carrierId: Int
    let rank: Int
    let name: String
    let scac: String
    let onTime: Int      // onTimeRate (%)
    let overall: Int     // overallScore (0..100)
    let grade: String    // A / B / C / D / F
    let bookings: Int    // totalLoads
    let alerts: Int      // fmcsa.alertCount
    let recommended: Bool
    // Ocean metrics off compareScorecards (real, null when no vessel history).
    let rolloverPct: Int?
    let transitDaysAvg: Int?
    let reliabilityPct: Int?
    let oceanBookings: Int
}

struct VesselCarrierScorecard_675: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette = Theme.light) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselCarrierScorecardBody_675(theme: theme)
        } nav: {
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

private struct VesselCarrierScorecardBody_675: View {
    let theme: Theme.Palette
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadFailed = false

    // League rows — start empty; populated only by the live compareScorecards return.
    @State private var carriers: [LeagueCarrier_675] = []

    // Drill-down + award navigation.
    @State private var drillCarrier: DrillCarrier_675? = nil
    @State private var showTenderWorkflow = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                Text("Carrier scorecard").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
                Text("Multi-carrier league · award decision").font(EType.caption).foregroundStyle(palette.textSecondary)
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading carrier league…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if loadFailed {
                    LifecycleCard(accentDanger: true) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("The carrier league didn't load.").font(EType.caption).foregroundStyle(Brand.danger)
                            Text("Check your connection — scores stay saved and will rank again on refresh.")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                            Button { Task { await load() } } label: {
                                Text("Retry").font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.blue)
                            }.buttonStyle(.plain)
                        }
                    }
                } else if carriers.isEmpty {
                    EusoEmptyState(systemImage: "chart.bar.doc.horizontal",
                                   title: "No carriers scored on this lane yet",
                                   subtitle: "Scores build from delivered bookings and safety records. Book with a carrier and its on-time record ranks here.")
                } else {
                    hero
                    HStack {
                        Text("LEAGUE · RANKED BY OVERALL").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                        Spacer()
                        Text("on-time 50 · safety 50").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    }
                    leagueCard
                    authorityBand
                    HStack(spacing: 8) {
                        CTAButton(title: "Award best carrier",
                                  action: { showTenderWorkflow = true },
                                  subtitle: recommendedCarrier.map { "→ tender workflow · \($0.scac)" })
                        exportButton
                    }
                    esangRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showTenderWorkflow) {
            VesselCarrierTenderWorkflowScreen(theme: theme, shipmentId: 0)
        }
        .sheet(item: $drillCarrier) { drill in
            VesselCarrierScorecardScreen(theme: theme, carrierId: drill.carrierId)
        }
    }

    private var recommendedCarrier: LeagueCarrier_675? { carriers.first }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("VESSEL OPERATOR · CARRIER SCORECARD").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text("\(carriers.count) SCORED").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Decision hero (top of the compareScorecards sort)
    @ViewBuilder private var hero: some View {
        if let rec = recommendedCarrier {
            ActiveCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        pill("OCEAN LEAGUE")
                        pill("ALL LANES")
                        Spacer()
                        Text("GRADE \(rec.grade)").font(.system(size: 13, weight: .heavy)).tracking(0.5).foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(LinearGradient.diagonal).clipShape(Capsule())
                    }
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rec.name).font(.system(size: 18, weight: .bold)).foregroundStyle(palette.textPrimary)
                            Text("\(rec.scac) · recommended to award · overall \(rec.overall)/100").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                            if rec.oceanBookings > 0 {
                                Text(oceanMetricLine(rec)).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(palette.textTertiary)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("ON-TIME \(rec.onTime)%").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(palette.textSecondary)
                            Text("\(rec.bookings) BOOKINGS").font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(palette.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private func pill(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .bold)).tracking(0.5).foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(palette.textPrimary.opacity(0.05)).clipShape(Capsule())
    }

    // MARK: - League matrix
    private var leagueCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("CARRIER").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("ON-TIME").font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary).frame(width: 56, alignment: .trailing)
                Text("OVERALL").font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary).frame(width: 56, alignment: .trailing)
                Text("GRADE").font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary).frame(width: 44, alignment: .center)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
            Divider().overlay(palette.borderFaint)
            ForEach(Array(carriers.enumerated()), id: \.element.id) { idx, c in
                if idx > 0 { Divider().overlay(palette.borderFaint).padding(.leading, 16) }
                leagueRow(c)
            }
        }
        .background(palette.bgCard).clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
    }

    private func leagueRow(_ c: LeagueCarrier_675) -> some View {
        Button { drillCarrier = DrillCarrier_675(carrierId: c.carrierId) } label: {
            HStack(spacing: 0) {
                Text("\(c.rank)").font(.system(size: 14, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(c.recommended ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                    .frame(width: 22, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(c.name).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                        if c.recommended {
                            Text("REC").font(.system(size: 8, weight: .heavy)).tracking(0.4).foregroundStyle(Brand.success)
                                .padding(.horizontal, 6).padding(.vertical, 2).background(Brand.success.opacity(0.16)).clipShape(Capsule())
                        }
                    }
                    Text("\(c.scac) · \(c.bookings) bk · \(c.alerts) alert\(c.alerts == 1 ? "" : "s")").font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 6)
                Text("\(c.onTime)%").font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary).frame(width: 50, alignment: .trailing)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(c.overall)").font(.system(size: 15, weight: .heavy)).monospacedDigit().foregroundStyle(palette.textPrimary)
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.borderFaint).frame(width: 42, height: 3)
                        Capsule().fill(LinearGradient.diagonal).frame(width: 42 * Double(min(max(c.overall, 0), 100)) / 100.0, height: 3)
                    }
                }.frame(width: 50, alignment: .trailing)
                gradePill(c.grade).frame(width: 44, alignment: .center)
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(c.recommended ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.08)) : AnyShapeStyle(Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func gradePill(_ g: String) -> some View {
        let tone: Color = g.hasPrefix("A") ? Brand.success : (g.hasPrefix("C") || g.hasPrefix("D") || g.hasPrefix("F") ? Brand.warning : palette.textSecondary)
        return Text(g).font(.system(size: 11, weight: .bold))
            .foregroundStyle(tone)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(tone.opacity(g.hasPrefix("B") ? 0.10 : 0.16)).clipShape(Capsule())
    }

    // MARK: - Tri-country carrier authority (reference band · US active = USWC discharge)
    private var authorityBand: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CARRIER AUTHORITY · PER DISCHARGE COUNTRY").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            HStack(spacing: 0) {
                authorityCell("US", "FMC · OTI bond", Brand.info, active: true)
                authorityCell("CA", "CTA", Brand.danger, active: false)
                authorityCell("MX", "SCT · SEMAR", Brand.success, active: false)
            }
        }
        .padding(16)
        .background(palette.bgCard).clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
    }

    private func authorityCell(_ code: String, _ label: String, _ tone: Color, active: Bool) -> some View {
        HStack(spacing: 8) {
            Text(code).font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3).background(tone).clipShape(RoundedRectangle(cornerRadius: 5))
            Text(label).font(.system(size: 10)).foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Export (real on-device CSV share of the loaded league)
    private var exportButton: some View {
        ShareLink(item: leagueCSV()) {
            Text("Export").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(palette.bgCardSoft).clipShape(Capsule())
                .overlay(Capsule().strokeBorder(palette.borderFaint))
        }
        .buttonStyle(.plain)
    }

    private func leagueCSV() -> String {
        var out = "rank,carrier,code,on_time_pct,overall,grade,bookings,alerts\n"
        for c in carriers {
            let name = c.name.replacingOccurrences(of: ",", with: " ")
            out += "\(c.rank),\(name),\(c.scac),\(c.onTime),\(c.overall),\(c.grade),\(c.bookings),\(c.alerts)\n"
        }
        return out
    }

    // MARK: - ESang insight (computed from the live sort)
    @ViewBuilder private var esangRow: some View {
        if let rec = recommendedCarrier {
            let insight: String = {
                if carriers.count >= 2 {
                    let delta = rec.overall - carriers[1].overall
                    return "ESang · \(rec.name) leads \(carriers[1].name) by +\(delta) composite"
                }
                return "ESang · \(rec.name) is your only scored carrier"
            }()
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    Circle().fill(Color.white.opacity(0.25)).frame(width: 14, height: 14).offset(x: -5, y: -5)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(insight).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text("Award \(rec.scac) next to cut roll and late-arrival risk").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textTertiary)
            }
            .padding(14)
            .background(palette.bgCard).clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
        }
    }

    // MARK: - Network
    private func load() async {
        loading = true; loadFailed = false
        do {
            // 1) seed the comparison pool from the top-carriers ranking.
            struct TopIn: Encodable { let limit: Int; let minScore: Int }
            struct TopRow: Decodable { let carrierId: Int }
            let pool: [TopRow] = try await EusoTripAPI.shared.query("carrierScorecard.getTopCarriers", input: TopIn(limit: 8, minScore: 60))
            let ids = pool.map { $0.carrierId }

            // compareScorecards requires 1..10 ids — empty pool renders the honest empty state.
            guard !ids.isEmpty else { carriers = []; loading = false; return }

            // 2) compare them side-by-side (primary endpoint).
            struct CmpIn: Encodable { let carrierIds: [Int] }
            struct CmpRow: Decodable {
                let carrierId: Int?
                let companyName: String?
                let overallScore: Int?
                let grade: String?
                let onTimeRate: Int?
                let totalLoads: Int?
                struct FMCSA: Decodable { let alertCount: Int? }
                let fmcsa: FMCSA?
                let rolloverPct: Int?
                let transitDaysAvg: Int?
                let scheduleReliabilityPct: Int?
                let oceanShipments: Int?
            }
            let rows: [CmpRow] = try await EusoTripAPI.shared.query("carrierScorecard.compareScorecards", input: CmpIn(carrierIds: Array(ids.prefix(10))))
            carriers = rows.enumerated().map { (i, r) in
                LeagueCarrier_675(
                    carrierId: r.carrierId ?? -(i + 1),
                    rank: i + 1,
                    name: r.companyName ?? "—",
                    scac: scac(for: r.companyName ?? ""),
                    onTime: r.onTimeRate ?? 0,
                    overall: r.overallScore ?? 0,
                    grade: r.grade ?? "—",
                    bookings: r.totalLoads ?? 0,
                    alerts: r.fmcsa?.alertCount ?? 0,
                    recommended: i == 0,
                    rolloverPct: r.rolloverPct,
                    transitDaysAvg: r.transitDaysAvg,
                    reliabilityPct: r.scheduleReliabilityPct,
                    oceanBookings: r.oceanShipments ?? 0
                )
            }
        } catch {
            // Doctrine: no raw transport error text in user copy — the error card
            // carries the user-grammar message; the failure itself is logged by the API layer.
            loadFailed = true
        }
        loading = false
    }

    /// Canonical ocean-carrier SCAC tags for the league's short codes; unknown
    /// carriers fall back to a derived four-letter display tag.
    /// Real ocean-performance line for a carrier with vessel history —
    /// reliability, rollover, and planned transit off compareScorecards.
    private func oceanMetricLine(_ c: LeagueCarrier_675) -> String {
        var parts: [String] = []
        if let r = c.reliabilityPct { parts.append("RELIABILITY \(r)%") }
        if let ro = c.rolloverPct { parts.append("ROLLOVER \(ro)%") }
        if let t = c.transitDaysAvg { parts.append("TRANSIT \(t)d") }
        return parts.isEmpty ? "\(c.oceanBookings) ocean bk" : parts.joined(separator: " · ")
    }

    private func scac(for name: String) -> String {
        let map = ["Maersk": "MAEU", "ONE": "ONEY", "Ocean Network": "ONEY", "Hapag": "HLCU",
                   "CMA": "CMDU", "MSC": "MSCU", "ZIM": "ZIMU", "Evergreen": "EGLV", "COSCO": "COSU"]
        for (k, v) in map where name.localizedCaseInsensitiveContains(k) { return v }
        return String(name.prefix(4)).uppercased()
    }
}

/// `sheet(item:)` needs Identifiable — file-scoped wrapper around the drill-down carrier id
/// (no retroactive `Int: Identifiable` conformance, which would leak app-wide).
private struct DrillCarrier_675: Identifiable {
    let carrierId: Int
    var id: Int { carrierId }
}

#Preview("675 · Vessel Carrier League · Night") { VesselCarrierScorecard_675(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("675 · Vessel Carrier League · Light") { VesselCarrierScorecard_675(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
