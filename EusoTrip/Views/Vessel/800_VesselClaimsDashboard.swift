//
//  800_VesselClaimsDashboard.swift
//  EusoTrip — Vessel Operator · Claims Dashboard.
//
//  Faithful 1:1 port of "800 Vessel Claims Dashboard.svg" (Light + Dark), RECONSTRUCTED to
//  flagship MONEY-BOARD grammar (mirror of 06 Vessel/801 + 02 Shipper/200 KPI): big gradient
//  exposure figure, aging-split RimCard hero (under-30 / 30–60 / 60–90 / over-90), 4-cell KPI strip
//  (OPEN+DENIED highlighted), itemized recent-claims ledger where EVERY row carries a 40x40 rx10
//  status-coded claim chip + claim mono ID + status·filed-date·type sub + a short status pill clear
//  of the right status-colored tabular amount, CTA pair, ESang row. KILLS the prior chip-less
//  status-dot rows that made it read as a flat list versus the at-bar 801.
//  Nav anchored to VesselOperatorNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME) —
//  the same Shell + BottomNav wrapper the registered vessel sibling 757 ships.
//
//  Data / wiring (endpoint confirmed via EUSOTRIP_PLATFORM MCP this fire):
//    freightClaims.getClaimsDashboard (EXISTS frontend/server/routers/freightClaims.ts:75 · query · {}
//      -> {open,pending,resolved,denied,totalValue,avgResolutionDays,
//          aging:{under30,days30to60,days60to90,over90},
//          recentClaims:[{id,claimNumber,type,status,description,filedDate,amount}]}) seeds the whole
//      board. Aging buckets derive from incidents.createdAt for status='investigating'. NOTE the live
//      endpoint maps incidents (no amount/lane/carrier columns) — totalValue, denied, avgResolutionDays
//      and row amounts come back 0 today; the board renders them honestly (no fabricated $/lanes) and
//      shows a bespoke empty state when no claims exist. recentClaims carries claimNumber·status·
//      filedDate·type — the row sub is built from those real fields, NOT the canonical port's assumed
//      carrier·lane·days-open (which this server does not return).
//    "View open claims" -> open-claims queue (nav handled by the journey hub).
//    "Export" -> freightClaims.exportClaimsLedger — STUB · named-gap (read-only today; a query
//      {status?,format:csv|pdf} -> {url} is the surfaced backend gap). Re-runs load() for now.
//    RBAC: vesselProcedure / roleProcedure(CATALYST,DISPATCHER,ADMIN). transportMode=vessel · USD.
//
//  KpiTile800 / RimCard800 / ESangRow800 / secondaryButton / usd800 are file-scoped bespoke helpers
//  (the canonical port's KpiTile/RimCard/ESangRow/SecondaryButton/Money.usd are not shared app symbols),
//  built from sibling 757's gradient-rim grammar to preserve the exact wireframe look.
//

import SwiftUI

private struct ClaimRow800: Identifiable {
    let id = UUID()
    let claim: String
    let chip: Color
    let pill: String
    let sub: String          // status · filed-date · type context (real endpoint fields)
    let amount: String
    let tone: StatusPill.Kind
    let muted: Bool
}

struct VesselClaimsDashboardScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselClaimsDashboardBody()
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

private struct VesselClaimsDashboardBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var hasData = false

    @State private var exposure = "$0"
    @State private var subline  = "total claim exposure · 0 open"
    // aging of the open claims, counts; bar widths derive from these
    @State private var aging = (under30: 0, d30to60: 0, d60to90: 0, over90: 0)
    @State private var counts = (open: 0, pending: 0, resolved: 0, denied: 0)
    @State private var recentTotal = 0

    @State private var rows: [ClaimRow800] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text(exposure).font(.system(size: 34, weight: .bold, design: .monospaced)).foregroundStyle(LinearGradient.diagonal)
                Text(subline).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()

                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if !hasData {
                    EusoEmptyState(systemImage: "doc.text.magnifyingglass",
                                   title: "No claims on file",
                                   subtitle: "getClaimsDashboard returned an empty ledger — no incidents to triage. Nothing to age or escalate.")
                } else {
                    agingCard
                    kpiRow
                    HStack {
                        Text("RECENT CLAIMS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                        Spacer()
                        Text("See all (\(recentTotal))").font(.system(size: 10, weight: .bold)).foregroundStyle(Brand.blue)
                    }
                    claimsCard
                    HStack(spacing: 8) {
                        CTAButton(title: "View open claims", action: {}, trailingIcon: "tray.full")
                        secondaryButton(title: "Export") { Task { await exportLedger() } }
                    }
                    ESangRow800(title: esangTitle, subtitle: esangSubtitle)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · CLAIMS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("USLGB · 2026-Q2").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: 6) {
                Text("Compliance").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var agingCard: some View {
        RimCard800 {
            VStack(alignment: .leading, spacing: 12) {
                Text("OPEN-CLAIM AGING · DAYS OPEN").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                GeometryReader { geo in
                    let total = CGFloat(max(aging.under30 + aging.d30to60 + aging.d60to90 + aging.over90, 1))
                    HStack(spacing: 2) {
                        Capsule().fill(Brand.success).frame(width: geo.size.width * CGFloat(aging.under30) / total)
                        Capsule().fill(Brand.blue).frame(width: geo.size.width * CGFloat(aging.d30to60) / total)
                        Capsule().fill(Brand.warning).frame(width: geo.size.width * CGFloat(aging.d60to90) / total)
                        Capsule().fill(Brand.danger)
                    }
                }.frame(height: 10)
                HStack(alignment: .top, spacing: 0) {
                    agingLegend(Brand.success, "<30d",   "\(aging.under30)", palette.textPrimary)
                    agingLegend(Brand.blue,    "30–60d", "\(aging.d30to60)", palette.textPrimary)
                    agingLegend(Brand.warning, "60–90d", "\(aging.d60to90)", palette.textPrimary)
                    agingLegend(Brand.danger,  ">90d",   "\(aging.over90)",  Brand.danger)
                }
            }
        }
    }

    private func agingLegend(_ dot: Color, _ label: String, _ value: String, _ tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) { Circle().fill(dot).frame(width: 8, height: 8); Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textPrimary) }
            Text(value).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(tone)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kpiRow: some View {
        HStack(spacing: 8) {
            KpiTile800(caption: "OPEN",     value: "\(counts.open)",     footnote: "investigating", highlighted: true)
            KpiTile800(caption: "PENDING",  value: "\(counts.pending)",  footnote: "in review",     highlighted: false)
            KpiTile800(caption: "RESOLVED", value: "\(counts.resolved)", footnote: "YTD",           highlighted: false)
            KpiTile800(caption: "DENIED",   value: "\(counts.denied)",   footnote: "appeal open",   highlighted: true)
        }
    }

    private var claimsCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(r.chip.opacity(0.14))
                            .frame(width: 40, height: 40)
                            .overlay(Image(systemName: "doc.text").font(.system(size: 16, weight: .semibold)).foregroundStyle(r.chip))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.claim).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(r.muted ? palette.textSecondary : palette.textPrimary)
                            Text(r.sub).font(.system(size: 11)).foregroundStyle(r.muted ? palette.textTertiary : palette.textSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            StatusPill(text: r.pill, kind: r.tone)
                            Text(r.amount).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(r.muted ? palette.textTertiary : r.chip)
                        }
                    }
                    .padding(.vertical, 10)
                    if idx < rows.count - 1 { Divider().overlay(palette.borderFaint) }
                }
            }
        }
    }

    // ESang advisory derives from real loaded state (worst-aging bucket / open count).
    private var esangTitle: String {
        if aging.over90 > 0 { return "ESang: \(aging.over90) claim\(aging.over90 == 1 ? "" : "s") aging past 90 days" }
        if counts.open > 0 { return "ESang: \(counts.open) open claim\(counts.open == 1 ? "" : "s") to triage" }
        return "ESang: claims queue is clear"
    }
    private var esangSubtitle: String {
        if aging.over90 > 0 { return "work them now · denial risk rises sharply after 90d" }
        if counts.open > 0 { return "investigate before they age into the 60–90d band" }
        return "no open incidents in range — nothing to escalate"
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            struct Aging: Decodable { let under30: Int?; let days30to60: Int?; let days60to90: Int?; let over90: Int? }
            struct Claim: Decodable { let claimNumber: String?; let type: String?; let status: String?; let filedDate: String?; let amount: Double? }
            struct Out: Decodable { let open: Int?; let pending: Int?; let resolved: Int?; let denied: Int?; let totalValue: Double?; let avgResolutionDays: Int?; let aging: Aging?; let recentClaims: [Claim]? }
            let r: Out = try await EusoTripAPI.shared.query("freightClaims.getClaimsDashboard", input: EmptyInput800())

            exposure = usd800(r.totalValue ?? 0)
            if let a = r.aging { aging = (a.under30 ?? 0, a.days30to60 ?? 0, a.days60to90 ?? 0, a.over90 ?? 0) }
            counts = (r.open ?? 0, r.pending ?? 0, r.resolved ?? 0, r.denied ?? 0)
            let openTxt = "\(counts.open) open"
            if let d = r.avgResolutionDays, d > 0 {
                subline = "total claim exposure · \(openTxt) · avg \(d)d to resolve"
            } else {
                subline = "total claim exposure · \(openTxt)"
            }

            let claims = r.recentClaims ?? []
            recentTotal = claims.count
            rows = claims.map { c in
                let status = (c.status ?? "reported").lowercased()
                let tone = tone(for: status)
                let chip = chipColor(for: tone)
                let muted = (status == "denied" || status == "closed")
                let typeTxt = (c.type ?? "incident").replacingOccurrences(of: "_", with: " ")
                var subParts: [String] = [status.uppercased(), typeTxt]
                if let d = c.filedDate, !d.isEmpty { subParts.append("filed \(d)") }
                return ClaimRow800(
                    claim: c.claimNumber ?? "—",
                    chip: chip,
                    pill: status.uppercased(),
                    sub: subParts.joined(separator: " · "),
                    amount: usd800(c.amount ?? 0),
                    tone: tone,
                    muted: muted)
            }

            // Honest "has data": real claims OR any non-zero count/aging to show the board.
            hasData = !claims.isEmpty || counts.open + counts.pending + counts.resolved + counts.denied > 0
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func tone(for status: String) -> StatusPill.Kind {
        switch status {
        case "resolved", "closed":            return .success
        case "investigating", "pending", "reported": return .warning
        case "open", "filed":                 return .danger
        case "denied":                        return .neutral
        default:                              return .info
        }
    }

    private func chipColor(for tone: StatusPill.Kind) -> Color {
        switch tone {
        case .success: return Brand.success
        case .warning: return Brand.warning
        case .danger:  return Brand.danger
        case .info:    return Brand.info
        case .hazmat:  return Brand.danger
        case .neutral: return Brand.neutral
        }
    }

    /// freightClaims.exportClaimsLedger — STUB · named-gap (surfaced to the-oath). Re-runs load().
    private func exportLedger() async { await load() }

    /// Bespoke secondary (outline) button — the canonical port's `SecondaryButton`
    /// is not a shared app symbol, so we hand-roll the same outline grammar sibling
    /// 757 ships for its secondary CTA.
    private func secondaryButton(title: String, action: @escaping () -> Void) -> some View {
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

/// USD formatter — the canonical port's `Money.usd` is not a shared app symbol
/// (Money is a value struct), so we format file-scoped.
private func usd800(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    f.maximumFractionDigits = 0
    return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
}

/// 4-cell KPI tile — the canonical port's `KpiTile` is not a shared app symbol,
/// so we render the same caption/value/footnote grammar file-scoped. `highlighted`
/// paints a gradient rim (OPEN / DENIED) to read against the muted cells.
private struct KpiTile800: View {
    @Environment(\.palette) private var palette
    let caption: String
    let value: String
    let footnote: String
    let highlighted: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption).font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(highlighted ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textPrimary))
            Text(footnote).font(.system(size: 8)).foregroundStyle(palette.textTertiary).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(highlighted ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.borderFaint),
                              lineWidth: highlighted ? 1.5 : 1)
        )
    }
}

/// Gradient-rim hero card — mirrors sibling 757's `RimCard757` gradient-stroked
/// context card grammar.
private struct RimCard800<Content: View>: View {
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

/// ESang advisory row — the canonical port's `ESangRow` is not a shared app
/// symbol, so we render the same sparkle + advisory grammar file-scoped.
private struct ESangRow800: View {
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

private struct EmptyInput800: Encodable {}

#Preview("800 · Claims Dashboard · Night") { VesselClaimsDashboardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("800 · Claims Dashboard · Light") { VesselClaimsDashboardScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
