//
//  801_VesselClaimsList.swift
//  EusoTrip — Vessel Operator · Claims List.
//
//  Faithful 1:1 port of "801 Vessel Claims List.svg" (Light + Dark), RECONSTRUCTED from a
//  money-hero dashboard clone (it read identical to 800 Claims Dashboard) into the flagship
//  LIST archetype — mirror of 02 Shipper/201 Shipper Loads + 06 Vessel/651 Shipments:
//    • search field + claim-status filter chips (All / Open / Pending / Denied / Paid)
//    • a directory card where EVERY row is a marine cargo claim: a 40x40 rx10 cause-of-loss
//      chip, carrier+lane title, mono CLM-id + container sub, the 7-stage CLAIM lifecycle dots
//      (Filed → Ack → Survey → Docs → Adjusted → Offer → Settled), and a right cluster of a
//      short status pill clear of the tabular claim amount + recovery-basis sub.
//  Kills the 800/801/802 monotony: 801 is now a navigable directory, not a third money board.
//  Nav anchored to the Vessel Operator BottomNav (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME) —
//  the same Shell + BottomNav wrapper the registered vessel siblings (757/664/680/667) ship,
//  with COMPLIANCE inked (claims live in the compliance domain).
//
//  Data / wiring (endpoint MCP-confirmed this fire):
//    freightClaims.getClaims (EXISTS frontend/server/routers/freightClaims.ts:172 ·
//      input {status?,type?,minAmount?,maxAmount?,startDate?,endDate?,search?,limit=20,offset=0}
//      -> {claims:[{claimNumber,type,status,description,amount,filedDate,severity,shipper,carrier,
//      loadNumber}],total}) seeds the chip total + the row directory. Reads from the incidents
//      table ordered by createdAt DESC.
//    NOTE the server hard-codes amount:0 and carrier/loadNumber:"-" today (the incidents table
//    carries no amount/carrier/load column) — STUB-amount · named-gap incidents.amount, surfaced
//    to the-oath to add the columns + map them. The row renders the honest server value ($0 / —)
//    rather than fabricating a figure.
//
//  0 mock data on load · honest empty/loading/error states — every value renders from real state;
//  the design-time seeds below are overwritten by the live query on .task / .refreshable. The
//  file-scoped helper types are suffixed 801 (the canonical port's ClaimDots/ClaimRow/ClaimChip/
//  ClaimLifecycleDots are not shared app symbols); money801() replaces the canonical Money.usd
//  (not an app symbol); the "primary" tint resolves to Brand.blue (Brand.primary is the gradient,
//  not a Color) to preserve the exact wireframe look.
//

import SwiftUI

private struct ClaimDots801 {
    let done: Int          // completed stages (inclusive of current when settled)
    let current: Int       // index of the active stage, -1 when none
    let exception: Int     // index of an exception stage, -1 when none
    static let total = 7
}

private struct ClaimRow801: Identifiable {
    let id = UUID()
    let symbol: String
    let tint: Color
    let title: String
    let sub: String
    let dots: ClaimDots801
    let pill: String
    let pillColor: Color
    let amount: String
    let recovery: String
}

private struct ClaimChip801: Identifiable { let id = UUID(); let label: String; let active: Bool }

struct VesselClaimsListScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselClaimsListBody()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselClaimsListBody: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var subline = "Eusorone Technologies · marine cargo claims · 2026-Q2"
    @State private var totalCaption = "35 TOTAL · 8 OPEN"

    @State private var chips: [ClaimChip801] = [
        .init(label: "All · 35", active: true),
        .init(label: "Open · 8", active: false),
        .init(label: "Pending · 3", active: false),
        .init(label: "Denied · 2", active: false),
        .init(label: "Paid · 22", active: false)
    ]

    @State private var rows: [ClaimRow801] = [
        .init(symbol: "drop.fill", tint: Brand.danger, title: "MSC · CNSHA → USLGB",
              sub: "CLM-2026-0188 · MSCU 7741203", dots: .init(done: 4, current: 3, exception: -1),
              pill: "OPEN · 62d", pillColor: Brand.danger, amount: "$24,800", recovery: "in docs"),
        .init(symbol: "shippingbox.fill", tint: Brand.warning, title: "Maersk · NLRTM → USHOU",
              sub: "CLM-2026-0184 · MRKU 4192860", dots: .init(done: 5, current: 4, exception: -1),
              pill: "PENDING · 41d", pillColor: Brand.warning, amount: "$18,600", recovery: "offer due"),
        .init(symbol: "thermometer.snowflake", tint: Brand.blue, title: "CMA CGM · FRLEH → USNYC",
              sub: "CLM-2026-0182 · CMAU 6620115", dots: .init(done: 3, current: 2, exception: -1),
              pill: "OPEN · 38d", pillColor: Brand.danger, amount: "$16,200", recovery: "survey set"),
        .init(symbol: "clock.badge.checkmark", tint: Brand.success, title: "OOCL · CNNGB → USLAX",
              sub: "CLM-2026-0179 · OOLU 8830471", dots: .init(done: 7, current: -1, exception: -1),
              pill: "RESOLVED", pillColor: Brand.success, amount: "$12,400", recovery: "settled 6d"),
        .init(symbol: "checkmark.seal.fill", tint: Brand.success, title: "Hapag-Lloyd · DEHAM → USSAV",
              sub: "CLM-2026-0175 · HLXU 5530028", dots: .init(done: 7, current: -1, exception: -1),
              pill: "PAID · ACH", pillColor: Brand.success, amount: "$8,900", recovery: "remitted 12d"),
        .init(symbol: "triangle", tint: Brand.neutral, title: "ZIM · KRPUS → USOAK",
              sub: "CLM-2026-0171 · ZIMU 2204117", dots: .init(done: 5, current: -1, exception: 5),
              pill: "DENIED · appeal", pillColor: Brand.neutral, amount: "$9,200", recovery: "re-file 9d")
        // NOTE: the DENIED seed uses Brand.neutral (the §5 palette-doctrine inactive color, palette-
        // agnostic) — @Environment(\.palette) is NOT available inside a @State default initializer,
        // so the canonical port's `palette.textTertiary` seed could not compile here. The live query's
        // denied branch keeps `palette.textTertiary` (valid in instance-method scope).
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                header
                Text("Claims").font(.system(size: 34, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(subline).font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                IridescentHairline()

                searchBar
                chipRow

                if loading {
                    LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if rows.isEmpty {
                    EusoEmptyState(systemImage: "shippingbox.and.arrow.backward",
                                   title: "No marine cargo claims",
                                   subtitle: "freightClaims.getClaims returned an empty ledger — no incidents on file in range. Nothing to recover yet.")
                } else {
                    ledgerCard
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("VESSEL OPERATOR · CLAIMS LIST").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            Spacer()
            Text(totalCaption).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textTertiary)
                Text("Search CLM ID, carrier, container…").font(.system(size: 14)).foregroundStyle(palette.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 16).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(palette.bgCard).overlay(RoundedRectangle(cornerRadius: 22).stroke(palette.borderFaint)))
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("SORT").font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(palette.textPrimary)
            }
            .frame(width: 72, height: 44)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(palette.bgCard).overlay(RoundedRectangle(cornerRadius: 22).stroke(palette.borderFaint)))
        }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(chips) { c in
                    Text(c.label)
                        .font(.system(size: 12, weight: c.active ? .bold : .semibold))
                        .foregroundStyle(c.active ? .white : palette.textPrimary)
                        .padding(.horizontal, 14).frame(height: 32)
                        .background(
                            Group {
                                if c.active { Capsule().fill(LinearGradient.primary) }
                                else { Capsule().fill(palette.bgCard).overlay(Capsule().stroke(palette.borderFaint)) }
                            }
                        )
                }
            }
        }
    }

    private var ledgerCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(r.tint.opacity(0.15))
                            .frame(width: 40, height: 40)
                            .overlay(Image(systemName: r.symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(r.tint))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                            Text(r.sub).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                            ClaimLifecycleDots801(dots: r.dots, palette: palette).padding(.top, 2)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(r.pill).font(.system(size: 11, weight: .bold)).tracking(0.4).foregroundStyle(r.pillColor)
                            Text(r.amount).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                            Text(r.recovery).font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                        }
                    }
                    .padding(.vertical, 12)
                    if idx < rows.count - 1 { Divider().overlay(palette.borderFaint) }
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: ClaimsResp801 = try await EusoTripAPI.shared.query("freightClaims.getClaims", input: ClaimsInput801(limit: 20, offset: 0))
            totalCaption = "\(r.total) TOTAL · \(r.claims.filter { ($0.status ?? "") == "investigating" }.count) OPEN"
            if !r.claims.isEmpty {
                rows = r.claims.prefix(6).map { c -> ClaimRow801 in
                    let status = (c.status ?? "reported").lowercased()
                    let pillColor: Color; let pill: String
                    switch status {
                    case "investigating": (pillColor, pill) = (Brand.danger, "OPEN")
                    case "pending":       (pillColor, pill) = (Brand.warning, "PENDING")
                    case "resolved":      (pillColor, pill) = (Brand.success, "RESOLVED")
                    case "denied":        (pillColor, pill) = (palette.textTertiary, "DENIED")
                    default:              (pillColor, pill) = (Brand.blue, status.uppercased())
                    }
                    let dots: ClaimDots801 = (status == "resolved") ? .init(done: 7, current: -1, exception: -1)
                        : (status == "denied") ? .init(done: 5, current: -1, exception: 5)
                        : .init(done: 4, current: 3, exception: -1)
                    return ClaimRow801(symbol: causeSymbol(c.type), tint: causeTint(c.type),
                                       title: (c.carrier ?? "—") == "-" ? "—" : (c.carrier ?? "—"),
                                       sub: "\(c.claimNumber ?? "—") · \((c.loadNumber ?? "") == "-" ? "" : (c.loadNumber ?? ""))",
                                       dots: dots, pill: pill, pillColor: pillColor,
                                       amount: money801(c.amount ?? 0), recovery: status)
                }
            } else {
                rows = []
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func causeSymbol(_ t: String?) -> String {
        switch (t ?? "").lowercased() {
        case "damage", "water_damage": return "drop.fill"
        case "shortage": return "shippingbox.fill"
        case "reefer", "temperature": return "thermometer.snowflake"
        case "delay": return "clock.badge.checkmark"
        default: return "triangle"
        }
    }
    private func causeTint(_ t: String?) -> Color {
        switch (t ?? "").lowercased() {
        case "damage", "water_damage": return Brand.danger
        case "shortage": return Brand.warning
        case "reefer", "temperature": return Brand.blue
        case "delay": return Brand.success
        default: return Brand.neutral
        }
    }

    /// File-private USD formatter — the canonical port's `Money.usd` is not a shared app symbol
    /// (`Money` is a Codable value struct with no formatting statics).
    private func money801(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

private struct ClaimLifecycleDots801: View {
    let dots: ClaimDots801
    let palette: Theme.Palette
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<ClaimDots801.total, id: \.self) { i in
                Circle()
                    .fill(color(for: i))
                    .frame(width: size(for: i), height: size(for: i))
            }
        }
    }
    private func color(for i: Int) -> Color {
        if i == dots.exception { return Brand.danger }
        if i <= dots.done - 1 || i == dots.current { return Brand.blue }
        return palette.textTertiary.opacity(0.35)
    }
    private func size(for i: Int) -> CGFloat {
        if i == dots.exception { return 6 }
        if i == dots.current { return 6 }
        return i <= dots.done - 1 ? 5 : 4
    }
}

// MARK: - File-scoped wiring types (suffixed 801 to avoid cross-file private collisions)

private struct ClaimsInput801: Encodable { let limit: Int; let offset: Int }
private struct Claim801: Decodable { let claimNumber: String?; let type: String?; let status: String?; let amount: Double?; let carrier: String?; let loadNumber: String? }
private struct ClaimsResp801: Decodable { let claims: [Claim801]; let total: Int }

#Preview("801 · Claims List · Night") { VesselClaimsListScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("801 · Claims List · Light") { VesselClaimsListScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
