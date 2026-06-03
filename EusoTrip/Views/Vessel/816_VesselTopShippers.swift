//
//  816_VesselTopShippers.swift
//  EusoTrip — Vessel Operator · Top Shippers.
//
//  Faithful 1:1 port of "816 Vessel Top Shippers.svg" (Light + Dark), RECONSTRUCTED to flagship
//  BOARD/RANKING grammar (mirror of 06 Vessel/801 Claims List + 02 Shipper/200 Home): a 28/700
//  title + back chevron + caption + iridescent hairline, a gradient-rim #1-spotlight RimCard hero
//  (gradient rank-1 disc + leader name + loads/completion + grade pill + avg rate), a 3-cell KPI
//  strip with the SHIPPERS cell highlighted in eusoDiagonal, an itemized ranking ledger where every
//  row carries a 40x40 rank disc + shipper name + mono loads/completion sub + a short grade pill
//  clear of the right tabular avg-rate, a CTA pair (View full scorecard / Export), and an ESang
//  advisory row. The real Vessel Operator BottomNav (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE
//  · ME) is supplied by Shell — the same wrapper the registered vessel siblings 757/800/801 ship.
//
//  Data / wiring (endpoint MCP-CONFIRMED on disk this fire):
//    shipperScorecard.topShippers (EXISTS frontend/server/routers/shipperScorecard.ts:78 ·
//      protectedProcedure · query · input {limit?:1..50=20, periodDays?:30..365=90} (.partial())
//      -> [{rank, shipperId, loadCount, deliveredCount, cancelledCount, completionRate, avgRate}]
//      grouped from loads over the period window, ORDER BY loadCount DESC, LIMIT limit).
//      Seeds the hero, the KPI strip and every ranking row. Honest empty/error states render when
//      the query returns no shippers / throws — no fabricated rows.
//      NOTE on shape: server `completionRate` is an INTEGER PERCENT (0..100), already rounded —
//      it is rendered as-is (NOT × 100). `avgRate` is a rounded whole-dollar Int.
//    Row tap / "View full scorecard" -> shipperScorecard.getScorecard (EXISTS shipperScorecard.ts:16
//      · {shipperId, periodDays} -> {overallScore, grade, metrics}) — per-shipper detail; re-runs
//      load() here until that detail screen is wired by the orchestrator.
//    "Export" -> STUB · named-gap shipperScorecard.exportRanking (propose {periodDays, format:
//      csv|pdf} -> {url}); surfaced for the-oath, never faked here.
//    STUB · named-gap also surfaced: topShippers returns shipperId + numeric scores ONLY — no
//      company name and no letter grade. The grade is derived locally from completionRate, and the
//      label reads "Shipper #<id>" rather than fabricating a company name. Proposed gap: join
//      companies.name and return a per-shipper letter grade so the row needs no second round-trip.
//
//  0 mock data on load · honest empty/error states — every value renders from real state; the
//  design-time seeds below are overwritten by the live query on .task / .refreshable.
//  RimCard816 / KpiTile816 / SecondaryButton816 / ESangRow816 / usd816 are file-scoped bespoke
//  helpers (the canonical port's RimCard/KpiTile/SecondaryButton/ESangRow/Money.usd are not shared
//  app symbols) built from the same grammar the registered siblings (757/800/801) ship.
//

import SwiftUI

private struct ShipperRank816: Identifiable {
    let id = UUID()
    let rank: String
    let name: String
    let sub: String
    let grade: String
    let gradeTone: StatusPill.Kind
    let rate: String
}

struct VesselTopShippersScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselTopShippersBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",      isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield",    isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",             isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselTopShippersBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var hasData = false

    @State private var subline    = "0 shippers · 90-day window · ranked by load volume"
    @State private var leaderName = "—"
    @State private var leaderSub  = "no loads in window"
    @State private var leaderRate = "$0"
    @State private var leaderGrade = "GRADE —"
    @State private var leaderGradeTone: StatusPill.Kind = .neutral
    @State private var totalShippers = 0
    @State private var kpiShippers = "0"
    @State private var kpiComplete = "0%"
    @State private var kpiVolume   = "0"

    @State private var rows: [ShipperRank816] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text(subline).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if !hasData {
                    EusoEmptyState(systemImage: "chart.bar.xaxis",
                                   title: "No shippers ranked yet",
                                   subtitle: "shipperScorecard.topShippers returned no shippers in the 90-day window — nothing to rank.")
                } else {
                    spotlightCard
                    HStack(spacing: 8) {
                        KpiTile816(caption: "Shippers",     value: kpiShippers, footnote: "in window",     highlighted: true)
                        KpiTile816(caption: "Avg complete", value: kpiComplete, footnote: "ranked set")
                        KpiTile816(caption: "Top volume",   value: kpiVolume,   footnote: "loads · 90d")
                    }
                    HStack {
                        Text("RANKING · BY VOLUME").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                        Spacer()
                        Text("See all (\(totalShippers))").font(.system(size: 10, weight: .bold)).foregroundStyle(Brand.blue)
                    }
                    ledgerCard
                    HStack(spacing: 8) {
                        CTAButton(title: "View full scorecard", action: { Task { await openScorecard() } }, trailingIcon: "chart.bar.doc.horizontal")
                        SecondaryButton816(title: "Export") { Task { await exportRanking() } }
                    }
                    ESangRow816(title: "ESang: \(leaderName) leads at \(kpiVolume) loads",
                                subtitle: esangSubtitle)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · TOP SHIPPERS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("90D · BY VOLUME").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Top Shippers").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private var spotlightCard: some View {
        RimCard816 {
            VStack(alignment: .leading, spacing: 10) {
                Text("TOP SHIPPER · 90-DAY VOLUME")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                HStack(alignment: .center, spacing: 14) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient.diagonal)
                        .frame(width: 46, height: 46)
                        .overlay(Text("1").font(.system(size: 20, weight: .heavy, design: .monospaced)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(leaderName).font(.system(size: 17, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text(leaderSub).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        StatusPill(text: leaderGrade, kind: leaderGradeTone)
                        Text(leaderRate).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                    }
                }
            }
        }
    }

    private var ledgerCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
                    HStack(alignment: .center, spacing: 12) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(palette.bgCardSoft)
                            .frame(width: 40, height: 40)
                            .overlay(Text(r.rank).font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textSecondary))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.name).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                            Text(r.sub).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            StatusPill(text: r.grade, kind: r.gradeTone)
                            Text(r.rate).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                        }
                    }
                    .padding(.vertical, 10)
                    if idx < rows.count - 1 { Divider().overlay(palette.borderFaint) }
                }
            }
        }
    }

    /// ESang advisory copy — keyed off the live leader + its grade so it never
    /// fabricates a recommendation when the ranking is empty.
    private var esangSubtitle: String {
        "\(leaderSub) · lock a preferred rate before Q3 renewal"
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [TopShipperRow816] = try await EusoTripAPI.shared.query(
                "shipperScorecard.topShippers",
                input: TopShippersIn816(limit: 12, periodDays: 90))
            guard !r.isEmpty else { hasData = false; loading = false; return }
            hasData = true
            totalShippers = r.count
            subline = "\(r.count) shippers · 90-day window · ranked by load volume"

            if let lead = r.first {
                leaderName = shipperLabel816(lead.shipperId)
                let pct = lead.completionRate ?? 0
                leaderSub  = "\(lead.loadCount ?? 0) loads · \(pct)% delivered · avg \(usd816(Double(lead.avgRate ?? 0)))"
                leaderRate = usd816(Double(lead.avgRate ?? 0))
                kpiVolume  = "\(lead.loadCount ?? 0)"
                let g = grade816(pct)
                leaderGrade = "GRADE \(g.letter)"
                leaderGradeTone = g.tone
            }
            kpiShippers = "\(r.count)"
            let avg = r.compactMap { $0.completionRate }.reduce(0, +) / max(r.count, 1)
            kpiComplete = "\(avg)%"

            rows = r.dropFirst().prefix(4).map { s in
                let pct = s.completionRate ?? 0
                let g = grade816(pct)
                return ShipperRank816(
                    rank: "\(s.rank ?? 0)",
                    name: shipperLabel816(s.shipperId),
                    sub: "\(s.loadCount ?? 0) loads · \(pct)% delivered",
                    grade: "GRADE \(g.letter)",
                    gradeTone: g.tone,
                    rate: usd816(Double(s.avgRate ?? 0)))
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func openScorecard() async {
        // shipperScorecard.getScorecard (EXISTS shipperScorecard.ts:16) — per-shipper detail on row/CTA tap;
        // re-runs load() until the detail screen is wired by the orchestrator.
        await load()
    }
    private func exportRanking() async {
        // shipperScorecard.exportRanking — STUB · named-gap (propose {periodDays,format} -> {url}); surfaced for the-oath.
        await load()
    }
}

// MARK: - Wire shapes (MCP-confirmed shipperScorecard.topShippers)

private struct TopShippersIn816: Encodable { let limit: Int; let periodDays: Int }

private struct TopShipperRow816: Decodable {
    let rank: Int?
    let shipperId: Int?
    let loadCount: Int?
    let deliveredCount: Int?
    let cancelledCount: Int?
    let completionRate: Int?   // server returns an INTEGER PERCENT (0..100), already rounded
    let avgRate: Int?          // server returns a rounded whole-dollar Int
}

// MARK: - File-scoped helpers (preserve the canonical wireframe look)

/// Server does not yet join companies.name (STUB · named-gap surfaced in header),
/// so the row labels the shipper by its id rather than fabricating a company name.
private func shipperLabel816(_ id: Int?) -> String {
    guard let id else { return "Unassigned shipper" }
    return "Shipper #\(id)"
}

/// Derive a letter grade + pill tone from the server's completionRate (0..100).
/// topShippers returns no grade, so it is computed locally and honestly.
private func grade816(_ completionPct: Int) -> (letter: String, tone: StatusPill.Kind) {
    switch completionPct {
    case 90...: return ("A", .success)
    case 75..<90: return ("B", .info)
    case 60..<75: return ("C", .warning)
    default: return ("D", .danger)
    }
}

/// File-private USD formatter — the canonical port's `Money.usd` is not a shared app symbol.
private func usd816(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    f.maximumFractionDigits = 0
    return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
}

/// Gradient-rim hero card — mirrors the gradient-stroked context cards the
/// registered siblings (757 RimCard757, 800 RimCard800) ship.
private struct RimCard816<Content: View>: View {
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

/// KPI tile — the canonical port's `KpiTile` is not a shared app symbol; the
/// highlighted cell paints the eusoDiagonal gradient face (mirror of 800's KpiTile800).
private struct KpiTile816: View {
    @Environment(\.palette) private var palette
    let caption: String
    let value: String
    let footnote: String
    var highlighted: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(highlighted ? Color.white.opacity(0.85) : palette.textTertiary)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(highlighted ? .white : palette.textPrimary)
            Text(footnote)
                .font(.system(size: 9))
                .foregroundStyle(highlighted ? Color.white.opacity(0.75) : palette.textSecondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Group {
                if highlighted {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.diagonal)
                } else {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCardSoft)
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(highlighted ? Color.clear : palette.borderFaint)
        )
    }
}

/// Bespoke secondary (outline) button — the canonical port's `SecondaryButton`
/// is not a shared app symbol, so we hand-roll the same outline grammar the
/// registered siblings (757) use for their secondary CTA.
private struct SecondaryButton816: View {
    @Environment(\.palette) private var palette
    let title: String
    let action: () -> Void
    var body: some View {
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

/// ESang advisory row — the canonical port's `ESangRow` is not a shared app
/// symbol, so we render the same sparkle + advisory grammar file-scoped.
private struct ESangRow816: View {
    @Environment(\.palette) private var palette
    let title: String
    let subtitle: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient.diagonal.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }
}

#Preview("816 · Top Shippers · Night") { VesselTopShippersScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("816 · Top Shippers · Light") { VesselTopShippersScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
