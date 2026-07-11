//
//  793_VesselDetentionByFacility.swift
//  EusoTrip — Vessel Operator · Detention by Facility (RANKED-BAR archetype).
//
//  Faithful 1:1 port of "793 Vessel Detention by Facility.svg" (Light + Dark).
//  A ranked horizontal-bar surface (deliberately NOT the split-hero of 790 nor
//  the live clock of 791): the total-spend figure headlines, then a single
//  ranking card lists facilities as severity-coloured proportional bars (rank +
//  name + events/avg-dwell + bar + charge), and an ESang card names the biggest
//  concentration and the pull it would re-route. Ranks terminals by the dollars
//  they cost in detention so the operator can renegotiate free time or reroute
//  pulls away from the worst gate.
//
//  WIRING (server/routers/detentionAccessorials.ts — verified this fire):
//    · getDetentionByFacility {dateFrom?,dateTo?,limit}? (query, protectedProcedure,
//        companyId-scoped :973)
//        -> { facilities[{rank,facilityName,eventCount,totalCharges,
//             avgWaitMinutes,maxWaitMinutes,avgCharge,disputeCount,score}] }
//        bar width = totalCharges / max(totalCharges) · colour by rank band.
//    · "Filter" -> re-queries (date-range placeholder).
//    · "Export ranking" -> exportFacilityRanking NAMED SERVER GAP — surfaced
//      honestly.
//  transportMode=vessel · USLGB · USD. No mock data.
//

import SwiftUI

private struct FacilityRank793: Decodable, Identifiable {
    var id: Int { rank ?? 0 }
    let rank: Int?
    let facilityName: String?
    let eventCount: Int?
    let totalCharges: Double?
    let avgWaitMinutes: Int?
    let disputeCount: Int?
    let score: Int?
}
private struct FacilityResponse793: Decodable { let facilities: [FacilityRank793]? }

struct VesselDetentionByFacilityScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselDetentionByFacilityBody() } nav: { VesselDetnNav(active: .compliance) }
    }
}

private struct VesselDetentionByFacilityBody: View {
    @Environment(\.palette) private var palette
    @State private var data: FacilityResponse793? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionError: String? = nil
    @State private var busy = false

    private var facilities: [FacilityRank793] { data?.facilities ?? [] }
    private var totalSpend: Double { facilities.reduce(0) { $0 + ($1.totalCharges ?? 0) } }
    private var maxSpend: Double { facilities.map { $0.totalCharges ?? 0 }.max() ?? 1 }

    private func barColor(_ f: FacilityRank793) -> Color {
        switch f.rank ?? 99 {
        case 1, 2: return Color(hex: 0xFF6B61)
        case 3, 4: return Brand.warning
        default:   return Brand.info
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                VDetnEyebrow(section: "BY FACILITY", caption: "RANKED · 30D")
                titleBlock
                IridescentHairline()

                if loading {
                    loadingCard
                } else if let err = loadError {
                    errorCard(err)
                } else if facilities.isEmpty {
                    EusoEmptyState(systemImage: "chart.bar.xaxis",
                                   title: "No facility spend",
                                   subtitle: "getDetentionByFacility returned no ranked terminals in this window. No detention charges to attribute.")
                } else {
                    rankingCard
                    esangCard
                    ctaPair
                    if let e = actionError { errorCard(e) }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(VDetn.money(totalSpend))
                .font(.system(size: 34, weight: .bold, design: .monospaced)).tracking(-0.6)
                .foregroundStyle(LinearGradient.diagonal).minimumScaleFactor(0.6).lineLimit(1)
            Text("\(facilities.count) facilities · ranked by 30-day detention spend")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Ranking card

    private var rankingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("WORST OFFENDERS · CHARGES").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("EVENTS · AVG DWELL").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, Space.s3)
            Rectangle().fill(palette.borderFaint).frame(height: 1)
            VStack(spacing: 0) {
                ForEach(Array(facilities.prefix(6).enumerated()), id: \.element.id) { _, f in
                    facilityBar(f)
                }
            }
            .padding(.top, Space.s3)
        }
        .padding(Space.s5)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private func facilityBar(_ f: FacilityRank793) -> some View {
        let frac = maxSpend > 0 ? CGFloat((f.totalCharges ?? 0) / maxSpend) : 0
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("\(f.rank ?? 0)").font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary).frame(width: 16, alignment: .leading)
                Text(f.facilityName ?? "Terminal").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Spacer()
                Text("\(f.eventCount ?? 0) · \(VDetn.hoursMin(f.avgWaitMinutes ?? 0))")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 10) {
                Color.clear.frame(width: 16)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.textPrimary.opacity(0.08)).frame(height: 10)
                        Capsule().fill(barColor(f)).frame(width: max(4, g.size.width * frac), height: 10)
                    }
                }
                .frame(height: 10)
                Text(VDetn.money(f.totalCharges ?? 0))
                    .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: ESang concentration card

    private var esangCard: some View {
        let top = facilities.first
        let share = (top?.totalCharges ?? 0) > 0 && totalSpend > 0
            ? Int(((top?.totalCharges ?? 0) / totalSpend * 100).rounded()) : 0
        let alt = facilities.dropFirst().min { ($0.totalCharges ?? 0) < ($1.totalCharges ?? 0) }
        return HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 36, height: 36)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear], center: .topLeading, startRadius: 0, endRadius: 18)).frame(width: 36, height: 36)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG AI").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Text("\(top?.facilityName ?? "Top terminal") is \(share)% of all spend")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                Text("shift recurring pulls to \(alt?.facilityName ?? "a lighter gate") to trim the concentration")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    // MARK: CTA

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: busy ? "Loading…" : "Export ranking", action: { exportGap() })
            secondaryButton793(title: "Filter") { Task { await load() } }.frame(width: 130)
        }
    }

    private func secondaryButton793(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(EType.title).foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color(hex: 0x232932))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Load / actions

    private struct FacInput793: Encodable { let limit: Int }

    private func load() async {
        busy = !loading; loadError = nil
        do {
            self.data = try await EusoTripAPI.shared.query(
                "detentionAccessorials.getDetentionByFacility", input: FacInput793(limit: 12))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false; busy = false
    }

    private func exportGap() {
        actionError = "Ranking export isn't wired yet — detentionAccessorials.exportFacilityRanking is a named server gap. The ranking reads live; the CSV writer is pending."
    }

    private var loadingCard: some View {
        LifecycleCard { Text("Ranking facilities by spend…").font(EType.caption).foregroundStyle(palette.textSecondary) }
    }
    private func errorCard(_ e: String) -> some View {
        LifecycleCard(accentDanger: true) { Text(e).font(EType.caption).foregroundStyle(Brand.danger) }
    }
}

#Preview("793 · Vessel Detention by Facility · Night") { VesselDetentionByFacilityScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("793 · Vessel Detention by Facility · Light") { VesselDetentionByFacilityScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
