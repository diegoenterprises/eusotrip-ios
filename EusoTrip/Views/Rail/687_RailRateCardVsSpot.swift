//
//  687_RailRateCardVsSpot.swift
//  EusoTrip — Rail · Shipper · Rate-Card vs Spot (brick 687).
//
//  Verbatim SwiftUI port of "05 Rail/687 Rail Rate-Card vs Spot" (Dark).
//  SHIPPER-SIDE two-lane head-to-head DECISION: bifurcate contract rate-card
//  vs live spot for the same lane and recommend the cheaper qualified source
//  before tendering. Composition follows function — a recommendation hero over
//  a two-column compare (rate, commitment, validity, fuel surcharge, transit)
//  with a per-attribute winner check.
//
//  Web parity: app/(rail)/rate/compare/page.tsx.
//
//  tRPC wiring (honest binding — rate-card is real, spot is a logged STUB):
//    • rate-card ← railShipments.getTariffRate (EXISTS railShipments.ts:2012 →
//                  TariffRateResult: totalRate, transit, surcharges, validity)
//    • book      ← railTenderWorkflow.submitTender (EXISTS railTenderWorkflow.ts:85,
//                  gated on a linked shipmentId)
//    • STUB → the-oath: getMarketRate (RailRateService defines MarketRateResult
//                  but no proc consumes it; the spot column reads 'spot
//                  unavailable' and the recommendation defaults to the rate-card
//                  — never invents a spot number).
//
//  RBAC: railProcedure. transportMode = rail · tri-country currency band
//  US USD STB / CA CAD CTA / MX MXN ARTF.
//  BottomNav: canonical Shipper enum HOME · LOADS · [orb] · WALLET · ME.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen root

struct RailRateCardVsSpotScreen: View {
    let theme: Theme.Palette
    var originStation: String = "Kansas City"
    var destStation: String = "Houston"
    var carType: String = "covered_hopper"
    var commodityStcc: String = "0112210"
    var railcarCount: Int = 25
    var shipmentId: Int? = nil

    init(theme: Theme.Palette = Theme.dark) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            RailRateCardVsSpotBody(originStation: originStation, destStation: destStation,
                                   carType: carType, commodityStcc: commodityStcc,
                                   railcarCount: railcarCount, shipmentId: shipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house.fill",       isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person.fill",     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data (mirror TariffRateResult)

private struct TariffSurcharge687: Decodable { let amount: Double?; let description: String?; let type: String? }
private struct RateCard687: Decodable {
    let tariffNumber: String?
    let totalRate: Double?
    let baseRate: Double?
    let currency: String?
    let transitDays: Int?
    let surcharges: [TariffSurcharge687]?
    let expirationDate: String?
    let railroad: String?
    let tariffAuthority: String?
    let minWeight: Double?
}

// MARK: - Body

private struct RailRateCardVsSpotBody: View {
    let originStation: String
    let destStation: String
    let carType: String
    let commodityStcc: String
    let railcarCount: Int
    let shipmentId: Int?

    @Environment(\.palette) private var palette

    @State private var card: RateCard687? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var booking = false
    @State private var actionNote: String? = nil

    private func short(_ s: String) -> String {
        switch s.lowercased() {
        case "kansas city": return "KC"
        case "houston":     return "HOU"
        default:            return String(s.prefix(3)).uppercased()
        }
    }
    private var laneLabel: String { "\(short(originStation)) → \(short(destStation))" }
    private var railRefId: String { "\(short(originStation))→\(short(destStation))·HOP" }
    private var currencyCode: String { card?.currency ?? "USD" }

    private var totalRate: Double? { card?.totalRate ?? card?.baseRate }
    private var fuelSurcharge: Double? {
        guard let s = card?.surcharges else { return nil }
        let sum = s.compactMap { $0.amount }.reduce(0, +)
        return sum > 0 ? sum : nil
    }

    private func money(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "$\(Int(v.rounded()).formatted(.number.grouping(.automatic)))"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                chipRow
                if loading {
                    LifecycleCard { Text("Pricing the lane…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if card == nil {
                    EusoEmptyState(systemImage: "tag.slash",
                                   title: "Tariff unavailable",
                                   subtitle: "No contract rate-card resolved for this lane. Rate-card requires a RAILINC tariff source.")
                } else {
                    recommendationHero
                    compareSection
                    regimeRow
                    if let note = actionNote {
                        Text(note).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Brand.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("✦ SHIPPER · RAIL · RATE SOURCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(railRefId)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Rate-card vs spot")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, 10)
            Text("Covered hopper · \(railcarCount) cars · STCC \(commodityStcc)")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary).padding(.top, 4)
            IridescentHairline().padding(.top, 14)
        }
    }

    private var chipRow: some View {
        HStack(spacing: Space.s2) {
            miniChip("card wins", tint: Brand.success)
            miniChip("spot unavailable", tint: palette.textSecondary)
            miniChip("valid \(validityDays)", tint: Color(hex: 0x6FA8FF))
        }
    }

    @ViewBuilder
    private func miniChip(_ text: String, tint: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .heavy)).tracking(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(palette.bgCard))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Recommendation hero

    private var recommendationHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.success)
                Text("RECOMMENDED · CONTRACT RATE-CARD")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Brand.success)
                Spacer(minLength: 4)
                Text("BEST QUALIFIED")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.3).foregroundStyle(Brand.success)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.success.opacity(0.14)))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(money(totalRate))
                    .font(.system(size: 28, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("/car").font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textSecondary)
            }
            Text(heroSub)
                .font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s5)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    private var heroSub: String {
        let auth = card?.tariffAuthority ?? "STB tariff"
        if let tr = totalRate {
            return "\(auth) · spot unavailable so contract is recommended · \(money(tr * Double(railcarCount))) total on \(railcarCount) cars"
        }
        return "\(auth) · spot unavailable · rate-card recommended"
    }

    // MARK: Compare section

    private var compareSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RATE COMPARISON")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(Color(hex: 0x9FB0BE))
                Spacer()
                Text("per car · \(railcarCount) cars").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
            VStack(spacing: 0) {
                columnHeaders
                Divider().padding(.horizontal, 16).overlay(palette.borderFaint)
                compareRow("Rate / car", cardValue: money(totalRate), spotValue: "unavailable", cardWins: true)
                compareRow("Commitment", cardValue: "\(railcarCount) cars", spotValue: "none", cardWins: true)
                compareRow("Validity", cardValue: validityDays, spotValue: "—", cardWins: true)
                compareRow("Fuel surcharge", cardValue: fuelSurcharge.map { "+\(money($0))" } ?? "included", spotValue: "—", cardWins: true)
                compareRow("Transit", cardValue: card?.transitDays.map { "\($0) days" } ?? "—", spotValue: "—", cardWins: true)
            }
            .padding(.vertical, 6)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            Text("Spot column pending — getMarketRate (RailInc spot) is not yet mounted; the recommendation defaults to the contract rate-card and never invents a spot number.")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var columnHeaders: some View {
        HStack(spacing: 8) {
            Text("RATE-CARD")
                .font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(Brand.success)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Brand.success.opacity(0.14)))
            Text("SPOT")
                .font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.borderFaint))
        }
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 2)
    }

    @ViewBuilder
    private func compareRow(_ label: String, cardValue: String, spotValue: String, cardWins: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 9.5, weight: .bold)).tracking(0.3).foregroundStyle(palette.textTertiary)
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text(cardValue)
                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Brand.success)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if cardWins {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.success)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(spotValue)
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: Regime chips

    private var regimeRow: some View {
        HStack(spacing: Space.s2) {
            regimeChip("US · USD", "STB tariff", active: true)
            regimeChip("CA · CAD", "CTA tariff", active: false)
            regimeChip("MX · MXN", "ARTF tarifa", active: false)
        }
    }

    @ViewBuilder
    private func regimeChip(_ title: String, _ sub: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                .foregroundStyle(active ? Color(hex: 0x6FA8FF) : palette.textSecondary)
            Text(sub).font(.system(size: 9, weight: .heavy))
                .foregroundStyle(active ? Color(hex: 0x6FA8FF) : palette.textSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(active ? Color(hex: 0x6FA8FF).opacity(0.20) : palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(active ? Color.clear : palette.borderFaint))
    }

    // MARK: CTA

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: booking ? "Booking…" : "Book contract",
                      action: { Task { await bookContract() } },
                      trailingIcon: "checkmark.seal.fill",
                      isLoading: booking)
            RailSecondaryActionButton(
                title: "Book spot",
                sheetTitle: "Spot rate context",
                lines: [
                    "\(laneLabel) · covered hopper · \(railcarCount) cars · STCC \(commodityStcc)",
                    "Rate-card \(money(totalRate))/car · \(currencyCode) · \(card?.tariffAuthority ?? "STB")",
                    "Validity \(validityDays) · transit \(card?.transitDays.map { "\($0)d" } ?? "—")",
                    "Spot booking pending — getMarketRate is not mounted, so spot cannot be quoted or booked."
                ],
                systemImage: "bolt.horizontal"
            )
        }
    }

    private var validityDays: String {
        guard let exp = card?.expirationDate, let d = parseDate(exp) else { return "—" }
        let days = Int((d.timeIntervalSinceNow / 86400).rounded())
        return days > 0 ? "\(days) days" : "expired"
    }

    private func parseDate(_ s: String) -> Date? {
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: String(s.prefix(10)))
    }

    // MARK: Load / actions

    private func load() async {
        loading = true; loadError = nil; actionNote = nil
        struct TariffIn: Encodable { let originStation: String; let destStation: String; let carType: String; let commodity: String }
        do {
            let c = try await EusoTripAPI.shared.query(
                "railShipments.getTariffRate",
                input: TariffIn(originStation: originStation, destStation: destStation, carType: carType, commodity: commodityStcc)) as RateCard687?
            self.card = c
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func bookContract() async {
        guard let shipmentId else {
            actionNote = "Attach a rail shipment to book — Book contract tenders the lane at the rate-card via submitTender once a shipment is linked."
            return
        }
        booking = true; actionNote = nil
        struct TenderIn: Encodable {
            let shipmentId: Int; let carrier: String
            let originScac: String; let destinationScac: String
            let commodityStcc: String; let carType: String
            let railcarCount: Int; let pickupDate: String
        }
        do {
            struct Ack: Decodable { let tenderId: String? }
            let carrier = (card?.railroad).flatMap { scacFor($0) } ?? "BNSF"
            let iso = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400)).prefix(10)
            _ = try await EusoTripAPI.shared.mutation(
                "railTenderWorkflow.submitTender",
                input: TenderIn(shipmentId: shipmentId, carrier: carrier,
                                originScac: short(originStation), destinationScac: short(destStation),
                                commodityStcc: commodityStcc, carType: carType,
                                railcarCount: railcarCount, pickupDate: String(iso))) as Ack
            actionNote = "Contract booked at \(money(totalRate))/car."
        } catch {
            actionNote = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        booking = false
    }

    private func scacFor(_ railroad: String) -> String? {
        let r = railroad.uppercased()
        if r.contains("BNSF") { return "BNSF" }
        if r.contains("UNION") || r == "UP" { return "UP" }
        if r.contains("CPKC") { return "CPKC" }
        if r.contains("CSX") { return "CSX" }
        if r.contains("NORFOLK") || r == "NS" { return "NS" }
        if r.contains("CN") { return "CN" }
        return nil
    }
}

#Preview("687 · Rail Rate-Card vs Spot · Night") {
    RailRateCardVsSpotScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("687 · Rail Rate-Card vs Spot · Light") {
    RailRateCardVsSpotScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
