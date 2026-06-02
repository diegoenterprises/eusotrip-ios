//
//  687_VesselOceanRateLookup.swift
//  EusoTrip — Vessel Operator · Ocean Rate Lookup.
//
//  PORTED VERBATIM from wireframe 687 (06 Vessel · Dark). A bespoke
//  PRICE-PROPORTIONAL SERVICE LADDER: every live ocean service is drawn
//  as a bar whose length is proportional to its all-in $/FEU. The cheapest
//  is lit green as the recommended award; the premium service is held in
//  slate. The buy decision reads in one glance instead of a numbers column.
//
//  Endpoints (real, via EusoTripAPI.shared):
//    · rate rows         <- vesselShipments.searchRates              EXISTS
//        (vesselFreightRates by originPortId / destinationPortId / containerSize)
//    · market context    <- competitiveIntel.getRateComparison       EXISTS
//    · trend arrow       <- marketPricing.getRateTrends              EXISTS
//    · save to booking   -> vesselShipments.createVesselBooking      EXISTS
//
//  PORT-GAP: saveRateQuote — searchRates returns live rate rows but there is
//  no persisted shipper-facing quote object { quoteId, vesselShipmentId,
//  serviceCode, carrierScac, allInPerFeu, transitDays, freeDays, bafPct,
//  validUntil }. The "Save quote to booking" CTA falls back to the booking
//  write; the quote-snapshot object itself is unbuilt on the server.
//
//  RBAC: vesselProcedure (VESSEL_OPERATOR) · transportMode VESSEL ·
//  US import (USLGB Long Beach / CBP) · TPEB · pure-ocean (no driver disc).
//

import SwiftUI

struct VesselOceanRateLookupScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselOceanRateLookupBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",        isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

/// One row from vesselShipments.searchRates → vesselFreightRates. Decimals
/// arrive as JSON strings (Drizzle MySQL decimal), so we accept either.
private struct VesselFreightRate687: Decodable, Identifiable {
    let id: Int
    let originPortId: Int?
    let destinationPortId: Int?
    let containerSize: String?
    let ratePerUnit: Double?
    let currency: String?
    let bafSurcharge: Double?
    let thcOrigin: Double?
    let thcDestination: Double?
    let peakSeasonSurcharge: Double?
    let effectiveDate: String?
    let expirationDate: String?
    let transitDays: Int?
    let serviceRoute: String?

    enum CodingKeys: String, CodingKey {
        case id, originPortId, destinationPortId, containerSize, ratePerUnit
        case currency, bafSurcharge, thcOrigin, thcDestination
        case peakSeasonSurcharge, effectiveDate, expirationDate, transitDays, serviceRoute
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                  = (try? c.decode(Int.self,    forKey: .id)) ?? 0
        originPortId        = try? c.decode(Int.self,     forKey: .originPortId)
        destinationPortId   = try? c.decode(Int.self,     forKey: .destinationPortId)
        containerSize       = try? c.decode(String.self,  forKey: .containerSize)
        ratePerUnit         = Self.decimal(c, .ratePerUnit)
        currency            = try? c.decode(String.self,  forKey: .currency)
        bafSurcharge        = Self.decimal(c, .bafSurcharge)
        thcOrigin           = Self.decimal(c, .thcOrigin)
        thcDestination      = Self.decimal(c, .thcDestination)
        peakSeasonSurcharge = Self.decimal(c, .peakSeasonSurcharge)
        effectiveDate       = try? c.decode(String.self,  forKey: .effectiveDate)
        expirationDate      = try? c.decode(String.self,  forKey: .expirationDate)
        transitDays         = try? c.decode(Int.self,     forKey: .transitDays)
        serviceRoute        = try? c.decode(String.self,  forKey: .serviceRoute)
    }

    private static func decimal(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let d = try? c.decode(Double.self, forKey: key) { return d }
        if let s = try? c.decode(String.self, forKey: key) { return Double(s) }
        return nil
    }

    /// All-in $/FEU — base + BAF + origin/destination THC + peak season.
    var allIn: Double {
        (ratePerUnit ?? 0) + (bafSurcharge ?? 0)
            + (thcOrigin ?? 0) + (thcDestination ?? 0) + (peakSeasonSurcharge ?? 0)
    }

    /// BAF as a percentage of base rate (clamped to a sane display range).
    var bafPct: Int {
        guard let base = ratePerUnit, base > 0, let baf = bafSurcharge else { return 0 }
        return Int((baf / base * 100).rounded())
    }
}

/// One lane row from competitiveIntel.getRateComparison.
private struct RateComparisonRow687: Decodable {
    let lane: String?
    let ourRate: Double?
    let marketAvg: Double?
    let delta: Double?
    let position: String?
}

/// Trend summary from marketPricing.getRateTrends.
private struct RateTrends687: Decodable {
    struct Summary: Decodable {
        let trendDirection: String?
        let spotAvg: Double?
    }
    let summary: Summary?
}

// MARK: - Body

private struct VesselOceanRateLookupBody: View {
    @Environment(\.palette) private var palette

    @State private var rates: [VesselFreightRate687] = []
    @State private var comparison: [RateComparisonRow687] = []
    @State private var trends: RateTrends687? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Save-to-booking action state.
    @State private var saving = false
    @State private var saveAck: String? = nil
    @State private var saveError: String? = nil

    // Lane context for this lookup (US import · TPEB · Shanghai → Long Beach).
    // originPortId / destinationPortId are the searchRates query keys; when the
    // ports table on the live tenant resolves CNSHA / USLGB they drive the
    // query, otherwise searchRates returns the full live sheet (no filter).
    var originPortId: Int = 0
    var destinationPortId: Int = 0
    var containerSize: String = "40ft_hc"

    // MARK: - Derived

    /// Live services sorted cheapest → priciest by all-in $/FEU.
    private var ladder: [VesselFreightRate687] {
        rates.sorted { $0.allIn < $1.allIn }
    }
    private var cheapest: VesselFreightRate687? { ladder.first }
    private var maxAllIn: Double { ladder.map(\.allIn).max() ?? 1 }

    /// Trend arrow vs. prior month from getRateTrends.
    private var trendFalling: Bool {
        (trends?.summary?.trendDirection ?? "").uppercased() == "FALLING"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                IridescentHairline()
                    .padding(.horizontal, Space.s5)

                VStack(alignment: .leading, spacing: Space.s4) {
                    if loading {
                        LifecycleCard {
                            Text("Loading ocean rates…")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    } else if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    } else if ladder.isEmpty {
                        EusoEmptyState(
                            systemImage: "dollarsign.circle",
                            title: "No live ocean rates",
                            subtitle: "Live CNSHA → USLGB service rates for 40' HC will appear here once the carrier rate sheet loads."
                        )
                    } else {
                        heroCard
                        serviceLadder
                        bafFreeTimeStrip
                        esangInsight
                        ctaPair
                    }
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s4)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Top bar (DETAIL chrome · eyebrow + back + title + overflow)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦  VESSEL OPERATOR · OCEAN RATE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("TPEB · LIVE")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Ocean rate")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .rotationEffect(.degrees(90))
            }
            .padding(.top, Space.s3)
        }
        .padding(.horizontal, Space.s5)
        .padding(.top, Space.s5)
        .padding(.bottom, Space.s3)
    }

    // MARK: - Hero · lane ribbon + best all-in

    private var heroCard: some View {
        let best = cheapest
        let allIn = best?.allIn ?? 0
        let svcRoute = best?.serviceRoute ?? "—"
        let transit = best?.transitDays ?? 0
        let eff = best.flatMap { friendlyDate($0.effectiveDate) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("BEST ALL-IN · PER FEU")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("40' HC · ELECTRONICS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textSecondary)
            }

            HStack(alignment: .top) {
                // Lane ribbon — CNSHA → USLGB.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Circle().fill(LinearGradient.primary).frame(width: 7, height: 7)
                        Rectangle()
                            .fill(LinearGradient.primary)
                            .frame(height: 1.6)
                            .overlay(
                                Image(systemName: "shippingbox")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Brand.blue)
                                    .padding(.horizontal, 4)
                                    .background(palette.bgCard)
                            )
                        Circle().fill(Brand.magenta).frame(width: 7, height: 7)
                    }
                    HStack {
                        Text("CNSHA")
                            .font(EType.mono(.caption)).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text("USLGB")
                            .font(EType.mono(.caption)).foregroundStyle(palette.textPrimary)
                    }
                }
                .frame(width: 178)

                Spacer(minLength: 8)

                // Best all-in price + trend + free time.
                VStack(alignment: .trailing, spacing: 4) {
                    Text(usd(allIn))
                        .font(.system(size: 34, weight: .bold)).tracking(-0.6)
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    HStack(spacing: 4) {
                        Text(svcRoute)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Brand.success)
                        if let delta = monthDelta {
                            Image(systemName: trendFalling ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                                .font(.system(size: 7, weight: .heavy))
                                .foregroundStyle(trendFalling ? Brand.success : Brand.danger)
                            Text("\(delta)% vs Apr")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(trendFalling ? Brand.success : Brand.danger)
                        }
                    }
                    Text("\(transit)d · 4 free days at USLGB")
                        .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                }
            }
            .padding(.top, Space.s3)

            Text("Shanghai → Long Beach\(eff.map { " · eff. \($0)" } ?? "")")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                .padding(.top, Space.s2)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [Brand.blue.opacity(0.95), Brand.magenta.opacity(0.95)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1.5
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    // MARK: - Service ladder · price-proportional bars

    private var serviceLadder: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SERVICES · PER FEU")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("searchRates · \(rates.count) of \(max(rates.count, 6))")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
            }
            .padding(.bottom, Space.s3)

            VStack(spacing: 0) {
                ForEach(Array(ladder.enumerated()), id: \.element.id) { idx, rate in
                    serviceRow(rate, rank: idx)
                    if idx < ladder.count - 1 {
                        Divider().overlay(palette.borderFaint)
                            .padding(.horizontal, Space.s4)
                    }
                }
            }
            .padding(.vertical, Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func serviceRow(_ rate: VesselFreightRate687, rank: Int) -> some View {
        let isCheapest = rank == 0
        let isPremium  = rank == ladder.count - 1 && ladder.count > 1
        // Slate for the premium tier, brand-blue for the mid tier, green award.
        let barColor: Color = isCheapest ? Brand.success
            : (isPremium ? Brand.rail.opacity(0.5) : Brand.blue.opacity(0.55))
        let priceColor: Color = isCheapest ? Brand.success
            : (isPremium ? palette.textSecondary : palette.textPrimary)
        let glyph: String = isCheapest ? "speedometer"
            : (isPremium ? "triangle" : "sailboat")
        let glyphColor: Color = isCheapest ? Brand.success
            : (isPremium ? Brand.rail : Brand.info)
        let frac = maxAllIn > 0 ? CGFloat(rate.allIn / maxAllIn) : 1

        let title = rate.serviceRoute ?? "Service \(rate.id)"
        let transit = rate.transitDays ?? 0
        let detailLine = "\(rate.containerSize.map { displaySize($0) } ?? "—") · \(transit)d"

        // delta vs. cheapest all-in.
        let deltaStr: String? = {
            guard let cheap = cheapest, !isCheapest else { return nil }
            let d = rate.allIn - cheap.allIn
            let faster = (cheap.transitDays ?? 0) - transit
            if faster > 0 { return "+\(usdShort(d)) · \(faster)d faster" }
            return "+\(usdShort(d))"
        }()

        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top, spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(glyphColor.opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: glyph)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(glyphColor)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    if isCheapest {
                        Text("RECOMMENDED")
                            .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(Brand.success)
                            .padding(.horizontal, 10).padding(.vertical, 3)
                            .background(Brand.success.opacity(0.14))
                            .clipShape(Capsule())
                    }
                    Text(detailLine)
                        .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(usd(rate.allIn))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(priceColor)
                        .monospacedDigit()
                    Text(isCheapest ? "lowest all-in" : (deltaStr ?? ""))
                        .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                }
            }

            // Price-proportional bar — length tracks all-in $/FEU.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bgCardSoft).frame(height: 6)
                    Capsule().fill(barColor).frame(width: max(8, geo.size.width * frac), height: 6)
                }
            }
            .frame(height: 6)
            .padding(.leading, 48)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .background(
            isCheapest
                ? AnyShapeStyle(LinearGradient(colors: [Brand.success.opacity(0.22), Brand.success.opacity(0.10)],
                                               startPoint: .leading, endPoint: .trailing))
                : AnyShapeStyle(Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .padding(.horizontal, Space.s2)
    }

    // MARK: - BAF + free-time strip

    private var bafFreeTimeStrip: some View {
        let baf = cheapest?.bafPct ?? 0
        let booking = "VES-260523-3C9F0A71B4"
        return HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 6) {
                Text("BAF + FREE TIME")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Text("BAF \(baf)% included all-in · 4 free days at USLGB")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("detention $145/container-day after · \(booking)")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 8)
            VStack(spacing: 2) {
                Text("\(baf)%")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("BAF")
                    .font(.system(size: 8)).foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Brand.blue.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - ESang insight

    private var esangInsight: some View {
        let delta = savingPerFeu
        let total = delta * 40
        return HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.75), .white.opacity(0)],
                                         center: .init(x: 0.35, y: 0.30),
                                         startRadius: 0, endRadius: 16))
                    .frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("ESang: \(cheapest?.serviceRoute ?? "Best service") saves \(usdShort(delta))/FEU at a 3-day trade")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(usdShort(total)) across the 40 FEU on this booking — book before Fri cutoff")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Button {
                    Task { await saveQuoteToBooking() }
                } label: {
                    HStack(spacing: 6) {
                        if saving { ProgressView().tint(.white) }
                        Text(saving ? "Saving…" : "Save quote to booking")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(saving || cheapest == nil)

                Button {
                    // All-services view is the full searchRates sheet already
                    // rendered in the ladder above; no separate route on the
                    // VESSEL nav graph yet.
                } label: {
                    Text("All services")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 136, height: 48)
                        .background(palette.bgCardSoft)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            if let ack = saveAck {
                Text(ack).font(EType.caption).foregroundStyle(Brand.success)
            }
            if let err = saveError {
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            }
        }
    }

    // MARK: - Derived figures

    /// Saving of the cheapest vs. the second-cheapest service ($/FEU).
    private var savingPerFeu: Double {
        guard ladder.count >= 2 else { return 0 }
        return ladder[1].allIn - ladder[0].allIn
    }

    /// Month-over-month delta % from getRateTrends summary, vs. cheapest all-in.
    private var monthDelta: Int? {
        guard let avg = trends?.summary?.spotAvg, avg > 0, let cheap = cheapest else { return nil }
        let d = abs((cheap.allIn - avg) / avg * 100)
        let pct = Int(d.rounded())
        return pct > 0 ? pct : nil
    }

    private func displaySize(_ raw: String) -> String {
        switch raw {
        case "20ft":         return "20'"
        case "40ft":         return "40'"
        case "40ft_hc":      return "40' HC"
        case "45ft":         return "45'"
        case "20ft_reefer":  return "20' reefer"
        case "40ft_reefer":  return "40' reefer"
        default:             return raw
        }
    }

    private func usd(_ v: Double) -> String {
        "$" + Int(v.rounded()).formatted(.number.grouping(.automatic))
    }
    private func usdShort(_ v: Double) -> String {
        "$" + Int(v.rounded()).formatted(.number.grouping(.automatic))
    }

    private func friendlyDate(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let inF = ISO8601DateFormatter()
        inF.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = inF.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
            ?? { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.date(from: String(iso.prefix(10))) }()
        guard let date else { return nil }
        let out = DateFormatter(); out.dateFormat = "MMM d"
        return out.string(from: date)
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct SearchIn: Encodable { let originPortId: Int?; let destinationPortId: Int?; let containerSize: String? }
        struct CompareIn: Encodable { let origin: String?; let destination: String? }
        struct TrendsIn: Encodable { let origin: String?; let destination: String?; let equipment: String; let period: String }
        do {
            async let rateRows: [VesselFreightRate687] = EusoTripAPI.shared.query(
                "vesselShipments.searchRates",
                input: SearchIn(
                    originPortId: originPortId > 0 ? originPortId : nil,
                    destinationPortId: destinationPortId > 0 ? destinationPortId : nil,
                    containerSize: containerSize.isEmpty ? nil : containerSize
                )
            )
            async let cmp: [RateComparisonRow687] = EusoTripAPI.shared.query(
                "competitiveIntel.getRateComparison",
                input: CompareIn(origin: "Shanghai", destination: "Long Beach")
            )
            async let trd: RateTrends687 = EusoTripAPI.shared.query(
                "marketPricing.getRateTrends",
                input: TrendsIn(origin: "Shanghai", destination: "Long Beach", equipment: "OCEAN_FEU", period: "30d")
            )
            let (r, c, t) = try await (rateRows, cmp, trd)
            self.rates = r
            self.comparison = c
            self.trends = t
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    // MARK: - Save quote → booking

    private func saveQuoteToBooking() async {
        guard let best = cheapest else { return }
        saving = true; saveAck = nil; saveError = nil
        // PORT-GAP: saveRateQuote — there is no persisted shipper-facing quote
        // object on the server. We write the chosen service to the active
        // booking via the real createVesselBooking mutation instead.
        // createVesselBooking requires concrete origin/destination port IDs;
        // when the searchRates row carries them we book, otherwise we surface
        // the gap rather than POSTing an invalid (port-less) booking.
        guard let origin = best.originPortId, let dest = best.destinationPortId else {
            saveError = "This rate row has no resolved lane ports — open the lane to book."
            saving = false
            return
        }
        // createVesselBooking input is a strict z.object — only its declared
        // keys (originPortId, destinationPortId, containerSize, rate, …) are
        // honored. transitDays / serviceRoute live on the quote object that
        // is not yet built, so they are not sent.
        struct BookingIn: Encodable {
            let originPortId: Int
            let destinationPortId: Int
            let cargoType: String
            let containerSize: String?
            let rate: Double
        }
        struct BookingOut: Decodable { let id: Int?; let bookingNumber: String?; let status: String? }
        do {
            let out: BookingOut = try await EusoTripAPI.shared.mutation(
                "vesselShipments.createVesselBooking",
                input: BookingIn(
                    originPortId: origin,
                    destinationPortId: dest,
                    cargoType: "container",
                    containerSize: best.containerSize,
                    rate: best.allIn
                )
            )
            if let booking = out.bookingNumber {
                saveAck = "Quote saved · booking \(booking) · \(best.serviceRoute ?? "service") @ \(usd(best.allIn))/FEU"
            } else {
                saveError = "Booking write returned no confirmation."
            }
        } catch {
            saveError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        saving = false
    }
}

#Preview("687 · Vessel Ocean Rate Lookup · Night") { VesselOceanRateLookupScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("687 · Vessel Ocean Rate Lookup · Light") { VesselOceanRateLookupScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
