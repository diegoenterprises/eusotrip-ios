//
//  642_RailAccessorialAnalytics.swift
//  EusoTrip — Rail Engineer · Accessorial Analytics.
//
//  ARCHETYPE = COMPOSITION/SHARE (verbatim port of wireframe 642):
//  the hero is a single full-width stacked spend bar split into the five
//  accessorial categories with a dot legend, so the dominant cost driver
//  is read at a glance; below is a ranked BY-CHARGE-TYPE ledger ordered by
//  spend; a tariff context card; and the Configure-rates / Export CTAs.
//
//  Wiring (REAL · verified against frontend/server/routers/accessorial.ts):
//   • Hero stacked bar + total → accessorial.getDashboardStats(input:{period:"30d"})
//     → { totalAmount, byType:[{type,count,amount}], ... }  (accessorial.ts:422).
//     NOTE: the <desc> proposed a STUB `accessorial.statsByType`; the REAL
//     period-aggregation endpoint that returns exactly the {type,count,amount}
//     composition is `getDashboardStats`, so it is wired here instead of
//     fabricating a non-existent procedure.
//   • Tariff context card → accessorial.getFeeSchedule()  (accessorial.ts:409).
//   • Each ledger row drill → railFreightAudit.auditInvoice — // PORT-GAP:
//     a mutation keyed by invoiceId, and the stats roll-up exposes no
//     per-invoice id, so the drill cannot be wired from this surface
//     without fabricating an id. Rows render the live composition only.
//
//  RBAC: protectedProcedure (rail carrier scope). transportMode=rail · US · USD.
//  NAV (REAL · RailEngineerNavController): HOME · SHIPMENTS · [orb] · COMPLIANCE · ME,
//  current = SHIPMENTS.
//

import SwiftUI

struct RailAccessorialAnalyticsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailAccessorialAnalyticsBody() } nav: {
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

// MARK: - Data shapes (mirror accessorial.ts wire format)

private struct AccessorialByType: Decodable, Identifiable {
    let type: String
    let count: Int
    let amount: Double
    var id: String { type }
}

private struct AccessorialDashboardStats: Decodable {
    let totalClaims: Int
    let totalAmount: Double
    let byType: [AccessorialByType]
}

private struct AccessorialFeeSchedule: Decodable {
    let platformFeePercent: Double?
    let note: String?
}

// MARK: - Charge-type presentation

/// Verbatim palette + glyph + abbreviation mapping for the five charge
/// categories the wireframe enumerates (switching / storage / diversion /
/// weighing / cleaning). When the live roll-up returns a `type` outside
/// these five, it falls through to a neutral slate slice so nothing is
/// fabricated — the real returned series is always what plots.
private struct ChargeStyle {
    let color: Color
    let pillTint: Double
    let abbrev: String
    let glyph: String
    let blurb: String

    static func resolve(_ rawType: String) -> ChargeStyle {
        switch rawType.lowercased() {
        case let t where t.contains("switch"):
            return ChargeStyle(color: Brand.blue,            pillTint: 0.14, abbrev: "SW", glyph: "arrow.left.arrow.right", blurb: "intra-yard")
        case let t where t.contains("storage") || t.contains("demurrage") || t.contains("detention"):
            return ChargeStyle(color: Brand.warning,         pillTint: 0.18, abbrev: "ST", glyph: "shippingbox",          blurb: "over free time")
        case let t where t.contains("divers") || t.contains("reroute") || t.contains("reconsign"):
            return ChargeStyle(color: Brand.escort,          pillTint: 0.16, abbrev: "DV", glyph: "arrow.triangle.branch", blurb: "gateway swap")
        case let t where t.contains("weigh") || t.contains("reweigh"):
            return ChargeStyle(color: Brand.info,            pillTint: 0.16, abbrev: "WG", glyph: "scalemass",            blurb: "scale ticket")
        case let t where t.contains("clean") || t.contains("washout"):
            return ChargeStyle(color: Color(hex: 0x607D8B),  pillTint: 0.18, abbrev: "CL", glyph: "drop",                blurb: "tank washout")
        default:
            return ChargeStyle(color: Brand.neutral,         pillTint: 0.14, abbrev: "AX", glyph: "doc.text.magnifyingglass", blurb: "accessorial")
        }
    }
}

/// Title-case label for a raw `type` string off the wire.
private func chargeTitle(_ rawType: String) -> String {
    switch rawType.lowercased() {
    case let t where t.contains("switch"):  return "Switching"
    case let t where t.contains("storage") || t.contains("demurrage"): return "Storage / demurrage"
    case let t where t.contains("detention"): return "Detention"
    case let t where t.contains("divers") || t.contains("reroute"): return "Diversion / reroute"
    case let t where t.contains("weigh"): return "Weighing"
    case let t where t.contains("clean") || t.contains("washout"): return "Cleaning"
    default:
        return rawType.prefix(1).uppercased() + rawType.dropFirst()
    }
}

private func usd(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 0
    let n = f.string(from: NSNumber(value: v)) ?? "\(Int(v))"
    return "$\(n)"
}

// MARK: - Body

private struct RailAccessorialAnalyticsBody: View {
    @Environment(\.palette) private var palette

    @State private var stats: AccessorialDashboardStats? = nil
    @State private var feeSchedule: AccessorialFeeSchedule? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    /// Ranked descending by spend — the ledger order the wireframe shows.
    private var rankedTypes: [AccessorialByType] {
        (stats?.byType ?? []).sorted { $0.amount > $1.amount }
    }

    private var total: Double { stats?.totalAmount ?? 0 }
    private var invoiceCount: Int { (stats?.byType ?? []).reduce(into: 0) { acc, t in acc += t.count } }

    private func sharePct(_ amount: Double) -> Double {
        total > 0 ? (amount / total) * 100 : 0
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    loadingState
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                } else if rankedTypes.isEmpty {
                    EusoEmptyState(systemImage: "chart.bar.xaxis",
                                   title: "No accessorial spend",
                                   subtitle: "30-day accessorial roll-up will appear here once invoices land.")
                } else {
                    heroCard
                    ledgerCard
                    tariffCard
                    ctaRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Header (eyebrow + 30-DAY · title + BNSF / invoices)

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("RAIL ENGINEER · ACCESSORIALS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("30-DAY")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Accessorial spend")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("BNSF")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("\(invoiceCount) invoices")
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 168)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                            .strokeBorder(palette.borderFaint))
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 270)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint))
        }
    }

    // MARK: - HERO · stacked composition bar

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TOTAL ACCESSORIAL · 30D")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Text(usd(total))
                        .font(.system(size: 30, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("vs prior 30d")
                        .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                    // Prior-window delta is not exposed by getDashboardStats;
                    // // PORT-GAP — comparison endpoint absent, so the delta
                    // chip is rendered neutral ("--") rather than fabricated.
                    Text("--")
                        .font(EType.mono(.body)).fontWeight(.bold)
                        .foregroundStyle(palette.textTertiary)
                }
            }

            // Stacked spend bar — proportional to live share, plotted with
            // GeometryReader so the five (or fewer) slices fill the width.
            GeometryReader { geo in
                let totalW = geo.size.width
                let gap: CGFloat = 2
                let n = rankedTypes.count
                let usableW = max(0, totalW - gap * CGFloat(max(0, n - 1)))
                let slice: (Double) -> CGFloat = { amt in
                    total > 0 ? usableW * CGFloat(amt / total) : 0
                }
                HStack(spacing: gap) {
                    ForEach(rankedTypes) { row in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(ChargeStyle.resolve(row.type).color)
                            .frame(width: slice(row.amount))
                    }
                }
                .frame(width: totalW, alignment: .leading)
            }
            .frame(height: 20)
            .padding(.top, 18)

            // Legend — dot + "Title NN%"
            FlowLegend(rows: rankedTypes.map { row in
                LegendItem(color: ChargeStyle.resolve(row.type).color,
                           label: "\(chargeTitle(row.type)) \(Int(sharePct(row.amount).rounded()))%")
            }, trailing: "\(rankedTypes.count) charge types", palette: palette)
            .padding(.top, 16)
        }
        .padding(Space.s5)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    // MARK: - BY CHARGE TYPE ledger

    private var ledgerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("BY CHARGE TYPE · RANKED")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getDashboardStats")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(Array(rankedTypes.prefix(3).enumerated()), id: \.element.id) { idx, row in
                    ledgerRow(row)
                    if idx < min(2, rankedTypes.count - 1) {
                        Divider().overlay(palette.borderFaint)
                            .padding(.vertical, 2)
                    }
                }

                if rankedTypes.count > 3 {
                    Divider().overlay(palette.borderFaint).padding(.vertical, 2)
                    let tail = rankedTypes.dropFirst(3)
                    let tailLine = tail.map { "\(chargeTitle($0.type)) \(usd($0.amount))" }
                        .joined(separator: " · ")
                    Text(tailLine)
                        .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                }
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func ledgerRow(_ row: AccessorialByType) -> some View {
        let style = ChargeStyle.resolve(row.type)
        // Drill → railFreightAudit.auditInvoice: // PORT-GAP — the stats
        // roll-up returns no per-invoice id to audit, so the row is a
        // read-only composition entry rather than a tappable drill.
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(style.color.opacity(style.pillTint))
                    .frame(width: 40, height: 40)
                Image(systemName: style.glyph)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(style.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(chargeTitle(row.type))
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("\(row.count) inv · \(Int(sharePct(row.amount).rounded()))% · \(style.blurb)")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            Text(style.abbrev)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(style.color)
                .frame(width: 46, height: 22)
                .background(Capsule().fill(style.color.opacity(style.pillTint)))
            Text(usd(row.amount))
                .font(.system(size: 14, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Tariff context card

    private var tariffCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TARIFF · getFeeSchedule")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("STB-tariffed")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            Text(feeSchedule?.note
                 ?? "STB-tariffed accessorials · open to renegotiate above-tariff lines")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA row (Configure rates · Export)

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Configure rates", action: { Task { await loadFeeSchedule() } })
            Button {
                // Export shares the live roll-up — no dedicated export
                // endpoint exists; // PORT-GAP — wired to a no-op until
                // an accessorial.exportReport procedure ships.
            } label: {
                Text("Export")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(width: 148)
        }
    }

    // MARK: - Load

    private func reload() async {
        loading = true; loadError = nil
        struct StatsIn: Encodable { let period: String }
        do {
            async let s: AccessorialDashboardStats = EusoTripAPI.shared.query(
                "accessorial.getDashboardStats", input: StatsIn(period: "30d"))
            async let fee: AccessorialFeeSchedule = EusoTripAPI.shared.queryNoInput(
                "accessorial.getFeeSchedule")
            let (stat, sched) = try await (s, fee)
            self.stats = stat
            self.feeSchedule = sched
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func loadFeeSchedule() async {
        do {
            self.feeSchedule = try await EusoTripAPI.shared.queryNoInput(
                "accessorial.getFeeSchedule")
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Legend (dot + label, wraps to grid)

private struct LegendItem: Identifiable {
    let color: Color
    let label: String
    var id: String { label }
}

private struct FlowLegend: View {
    let rows: [LegendItem]
    let trailing: String
    let palette: Theme.Palette

    private let columns = [GridItem(.flexible(), alignment: .leading),
                           GridItem(.flexible(), alignment: .leading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(rows) { item in
                    HStack(spacing: 9) {
                        Circle().fill(item.color).frame(width: 8, height: 8)
                        Text(item.label)
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            HStack {
                Spacer()
                Text(trailing)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }
}

#Preview("642 · Rail Accessorial Analytics · Night") {
    RailAccessorialAnalyticsScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}
#Preview("642 · Rail Accessorial Analytics · Light") {
    RailAccessorialAnalyticsScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
