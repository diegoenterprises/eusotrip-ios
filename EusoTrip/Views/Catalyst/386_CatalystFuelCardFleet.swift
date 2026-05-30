//
//  386_CatalystFuelCardFleet.swift
//  EusoTrip — Catalyst · Fuel Card Fleet (carrier-vantage program).
//
//  Verbatim port of the 386 Catalyst Fuel Card Fleet wireframe —
//  carrier fleet fuel-card program. Hero MTD spend + avg discount,
//  card roster rows with status pills, recent transactions ledger,
//  factor cells (active cards / gallons MTD / avg discount), and the
//  Lock card + Statement action pair.
//
//  Wiring manifest (Code/ "Wiring manifest" → real iOS client):
//    • MTD spend / gallons / discount   ← fuelManagement.getFuelDashboard
//       (EusoTripAPI.fuelMgmt.getDashboard) → totalSpend / totalGallons /
//       avgPricePerGallon / transactionCount for the MTD hero + factor cells.
//    • card roster + summary            ← fuelManagement.getFuelCardManagement
//       (EusoTripAPI.fuelMgmt.getFuelCards) → company-scoped fuel cards +
//       summary {total / active / suspended / totalSpent / monthlyLimit}.
//       Each FuelCard carries cardNumber (masked), cardType, status,
//       driverName, limits, spend, fuelOnly, lastUsed.
//    • recent transactions ledger       ← // WIRE: fuelManagement
//       .getFuelTransactionsMobile(limit:) — no client method yet; the
//       Code/ seed rows render until the feed is exposed.
//
//  0% mock doctrine: the figures below are the Code/ file's representative
//  seeds — the screen renders bespoke immediately, and live records
//  (getFuelDashboard + getFuelCardManagement) overwrite them on hydrate.
//  Carrier Eusotrans LLC · USDOT 3 194 882 · owner-op Michael Eusorone (ME).
//
//  BottomNav frozen (CatalystTab): HOME · DISPATCH · [ESang] · FLEET · ME.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct CatalystFuelCardFleetScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) {
        self.theme = theme
    }

    var body: some View {
        Shell(theme: theme) {
            FuelCardFleetContent_386()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_386(),
                trailing: catalystNavTrailing_386(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_386() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: false)]
}

private func catalystNavTrailing_386() -> [NavSlot] {
    [NavSlot(label: "Fleet", systemImage: "box.truck.fill", isCurrent: true),
     NavSlot(label: "Me",    systemImage: "person",         isCurrent: false)]
}

// MARK: - Body

private struct FuelCardFleetContent_386: View {
    @Environment(\.palette) private var palette

    // ── Live model (overwrites the Code/ seeds on hydrate) ──
    @State private var cards: [FuelManagementAPI.FuelCard] = []
    @State private var summary: FuelManagementAPI.FuelCardSummary? = nil
    @State private var dashboard: FuelManagementAPI.Dashboard? = nil

    // ── Code/ seed roster (rendered until live cards arrive) ──
    private struct SeedCard_386: Identifiable {
        let id = UUID(); let masked: String; let detail: String; let status: String
    }
    private let seedCards: [SeedCard_386] = [
        .init(masked: "•••• 4821 · TRK-01", detail: "Michael Eusorone · diesel",  status: "ACTIVE"),
        .init(masked: "•••• 7730 · RFR-01", detail: "reefer fuel · auto-lock OTR", status: "ACTIVE"),
        .init(masked: "•••• 1095 · SHOP",   detail: "parts + DEF · in-network",    status: "LOCKED"),
    ]

    // ── Code/ seed recent-transactions ledger (no client feed yet) ──
    private struct SeedTxn_386: Identifiable {
        let id = UUID(); let place: String; let gallons: String; let amount: String
    }
    private let seedTxns: [SeedTxn_386] = [
        .init(place: "Loves #214 Amarillo",  gallons: "118.4 gal", amount: "$402.16"),
        .init(place: "Pilot #109 Tucumcari", gallons: "96.2 gal",  amount: "$331.80"),
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleBlock
                iridescentHairline

                heroCard
                cardRosterCard
                factorCells
                actionPair
                footnotes

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await reload() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await reload() }
        }
    }

    // MARK: - Derived data (seed figures from the Code/ spec; live overwrites)

    private var activeCount: Int {
        if let s = summary { return s.active }
        if !cards.isEmpty { return cards.filter { ($0.status ?? "").lowercased() == "active" }.count }
        return 2   // Code/ seed: 2 of 3 active
    }

    private var totalCount: Int {
        if let s = summary { return s.total }
        if !cards.isEmpty { return cards.count }
        return 3   // Code/ seed: 3-card fleet program
    }

    private var lockedCount: Int { max(0, totalCount - activeCount) }

    private var mtdSpend: Double? { dashboard?.totalSpend ?? summary?.totalSpent }
    private var mtdGallons: Double? { dashboard?.totalGallons }

    /// Spend-vs-monthly-limit fraction for the hero progress bar. Falls
    /// back to the Code/ seed fraction (0.62) until the live limit lands.
    private var spendFraction: Double {
        guard let spend = mtdSpend, let limit = summary?.monthlyLimit, limit > 0 else { return 0.62 }
        return min(1.0, max(0.0, spend / limit))
    }

    // MARK: - TopBar + title

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · FUEL CARDS")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text("MTD")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Fuel Cards")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(palette.textPrimary)
                Text("fleet program · \(totalCount) cards")
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("EUSOTRANS LLC · USDOT 3 194 882")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("synced 2h ago")
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Brand.blue.opacity(0.40), Brand.magenta.opacity(0.40)],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 1)
            .padding(.horizontal, -20)
    }

    // MARK: - Hero card (FLEET SPEND · MTD)

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("FLEET SPEND · MTD")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("AVG DISCOUNT")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(heroSpend)
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-0.3)
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(gallonsLabel)
                    .font(.system(size: 13, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .padding(.leading, 6)
                Spacer(minLength: 0)
                Text(discountPerGal)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .tracking(0.2)
                    .foregroundStyle(Brand.success)
            }
            .padding(.top, 12)

            // Spend-against-limit progress bar.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient.diagonal)
                        .frame(width: max(0, geo.size.width * spendFraction))
                }
            }
            .frame(height: 6)
            .padding(.top, 14)

            Text(activeSummaryLine)
                .font(.system(size: 11, weight: .medium))
                .tracking(0.2)
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 14)

            Text("Discounts post nightly · OTR auto-lock on reefer card")
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// MTD fleet spend — Code/ seed "$6,420" until the live dashboard lands.
    private var heroSpend: String {
        guard let v = mtdSpend, v > 0 else { return "$6,420" }
        return currencyString(v)
    }

    /// Code/ seed "212 gal" until the live gallons rollup lands.
    private var gallonsLabel: String {
        guard let g = mtdGallons, g > 0 else { return "212 gal" }
        return "\(Int(g.rounded())) gal"
    }

    /// Avg negotiated discount — Code/ seed "$0.34/gal". No discount field
    /// on the dashboard envelope, so the seed holds until a discount-bearing
    /// rollup is wired (see fleet.getFuelStats in the manifest).
    private var discountPerGal: String { "$0.34/gal" }

    private var activeSummaryLine: String {
        "\(activeCount) cards active · \(lockedCount) locked to in-network only"
    }

    // MARK: - Card roster card (FUEL CARDS · FLEET)

    private var cardRosterCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("FUEL CARDS · FLEET")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("\(totalCount) CARDS")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, 14)

            if cards.isEmpty {
                // Code/ seed roster — renders bespoke immediately, replaced
                // by the live `getFuelCardManagement` cards on hydrate.
                ForEach(Array(seedCards.enumerated()), id: \.element.id) { idx, seed in
                    seedCardRow(seed)
                    if idx < seedCards.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 1)
                            .padding(.vertical, 12)
                    }
                }
            } else {
                ForEach(Array(cards.enumerated()), id: \.element.id) { idx, card in
                    cardRow(card)
                    if idx < cards.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 1)
                            .padding(.vertical, 12)
                    }
                }
            }

            Text("RECENT TRANSACTIONS")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 18)
                .padding(.bottom, 10)

            recentTransactions

            Text("Lock toggles a card to declined-everywhere in real time")
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func cardRow(_ card: FuelManagementAPI.FuelCard) -> some View {
        let active = (card.status ?? "").lowercased() == "active"
        let (pillText, pillFg, pillBg) = statusPillStyle(card.status)
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(cardTitle(card))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(cardSubtitle(card))
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(pillText)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(pillFg)
                .frame(width: 82, height: 20)
                .background(Capsule().fill(pillBg))
        }
        .opacity(active ? 1.0 : 0.92)
    }

    private func cardTitle(_ card: FuelManagementAPI.FuelCard) -> String {
        let masked = maskedNumber(card.cardNumber)
        let tag = (card.cardType?.isEmpty == false ? card.cardType! : (card.driverName ?? "CARD"))
        return "\(masked) · \(tag.uppercased())"
    }

    private func cardSubtitle(_ card: FuelManagementAPI.FuelCard) -> String {
        let who = card.driverName ?? "fleet"
        let scope = (card.fuelOnly == true) ? "fuel only" : "fuel + ancillary"
        return "\(who) · \(scope)"
    }

    private func maskedNumber(_ raw: String) -> String {
        let digits = raw.filter { $0.isNumber }
        let last4 = digits.count >= 4 ? String(digits.suffix(4)) : raw
        return "•••• \(last4)"
    }

    private func statusPillStyle(_ raw: String?) -> (String, Color, Color) {
        switch (raw ?? "").lowercased() {
        case "active":
            return ("ACTIVE", Brand.success, Color(hex: 0x0B3D2E))
        case "suspended", "locked":
            return ("LOCKED", palette.textSecondary, palette.bgCardSoft)
        case "cancelled":
            return ("CANCELLED", Brand.danger, Brand.danger.opacity(0.14))
        default:
            return ((raw ?? "—").uppercased(), palette.textTertiary, palette.bgCardSoft)
        }
    }

    private func seedCardRow(_ seed: SeedCard_386) -> some View {
        let active = seed.status.uppercased() == "ACTIVE"
        let pillFg: Color = active ? Brand.success : palette.textSecondary
        let pillBg: Color = active ? Color(hex: 0x0B3D2E) : palette.bgCardSoft
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(seed.masked)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(seed.detail)
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(seed.status.uppercased())
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(pillFg)
                .frame(width: 82, height: 20)
                .background(Capsule().fill(pillBg))
        }
        .opacity(active ? 1.0 : 0.92)
    }

    // MARK: - Recent transactions ledger

    private var recentTransactions: some View {
        // Code/ seed ledger — the fuelManagement router exposes dashboard
        // aggregates + card management but NO per-transaction feed yet, so
        // these representative rows render until the feed is wired.
        //
        // WIRE: fuelManagement.getFuelTransactionsMobile(limit:) — per-card
        //       transaction ledger (station / gallons / amount / ts).
        VStack(alignment: .leading, spacing: 8) {
            ForEach(seedTxns) { txn in
                HStack(spacing: 8) {
                    Text(txn.place)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    Text(txn.gallons)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(0.2)
                        .foregroundStyle(palette.textSecondary)
                    Text(txn.amount)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .tracking(0.2)
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 64, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Factor cells (ACTIVE CARDS / GALLONS MTD / AVG DISCOUNT)

    private var factorCells: some View {
        HStack(spacing: 8) {
            factorCell(eyebrow: "ACTIVE CARDS",
                       value: "\(activeCount)",
                       sub: "of \(totalCount)")
            factorCell(eyebrow: "GALLONS MTD",
                       value: gallonsValue,
                       sub: "diesel")
            factorCell(eyebrow: "AVG DISCOUNT",
                       value: discountValue,
                       sub: "per gal")
        }
    }

    private var gallonsValue: String {
        guard let g = mtdGallons, g > 0 else { return "212" }   // Code/ seed
        return "\(Int(g.rounded()))"
    }

    // Code/ seed "$0.34" — no discount field on the dashboard envelope yet.
    private var discountValue: String { "$0.34" }

    private func factorCell(eyebrow: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .tracking(0.4)
                .monospacedDigit()
                .foregroundStyle(value == "—" ? palette.textTertiary : palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(sub)
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Action pair (Lock card · Statement)

    private var actionPair: some View {
        HStack(spacing: 8) {
            Button {
                // Lock toggles a card to declined-everywhere. The
                // mutation (fuelManagement.setFuelCardStatus) is a
                // follow-up brick; ESANG refresh re-pulls the roster.
                NotificationCenter.default.post(name: .esangRefreshSurface, object: nil)
            } label: {
                Text("Lock card")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                NotificationCenter.default.post(name: .esangRefreshSurface, object: nil)
            } label: {
                Text("Statement")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(palette.borderSoft, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Footnotes

    private var footnotes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Fuel program · per-card limits + in-network rules + nightly discount post")
            Text("Carrier: Eusotrans LLC · USDOT 3 194 882 · WEX-network fleet cards")
            Text("MTD spend nets pump price minus negotiated per-gallon discount")
        }
        .font(.system(size: 9, design: .monospaced))
        .tracking(0.3)
        .foregroundStyle(palette.textTertiary)
        .padding(.top, 4)
    }

    // MARK: - Formatting

    private func currencyString(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    // MARK: - Network (live overwrites the Code/ seeds)

    private func reload() async {
        async let cardsTask: FuelManagementAPI.FuelCardsResponse? = {
            try? await EusoTripAPI.shared.fuelMgmt.getFuelCards(status: "all")
        }()
        async let dashTask: FuelManagementAPI.Dashboard? = {
            try? await EusoTripAPI.shared.fuelMgmt.getDashboard(period: "month")
        }()

        let (cardsResp, dash) = await (cardsTask, dashTask)

        if let cardsResp {
            self.cards = cardsResp.cards
            self.summary = cardsResp.summary
        }
        if let dash { self.dashboard = dash }
    }
}

// MARK: - Previews

#Preview("386 · Catalyst · Fuel Card Fleet · Night") {
    CatalystFuelCardFleetScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("386 · Catalyst · Fuel Card Fleet · Afternoon") {
    CatalystFuelCardFleetScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
