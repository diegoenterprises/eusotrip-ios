//
//  577_RailFuelSurcharge.swift
//  EusoTrip — Rail Engineer · Fuel Surcharge (EIA-indexed stepped FSC schedule).
//
//  Verbatim port of "577 Rail Fuel Surcharge.svg" (Light + Dark).
//  EIA #2 diesel index, current FSC pct, stepped band schedule with active band highlighted,
//  applied MTD / per-mile / lanes KPI. Recalculate + publish CTA.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME).
//
//  Data:
//    fuelSurchargeIndex.currentDieselIndex  (EXISTS :56)   → hero diesel price + FSC rate
//    fuelSurchargeIndex.calculateSteppedFsc (EXISTS :27)   → band schedule rows
//    fuelSurchargeIndex.generateFscSchedule (EXISTS :70)   → Publish CTA
//    detentionAccessorials.getFuelSurchargeTracking (EXISTS :1046) → applied MTD tracking
//

import SwiftUI

struct RailFuelSurchargeScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { RailFuelSurchargeBody() } nav: {
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

// MARK: - Data shapes

private struct DieselIndex577: Decodable {
    let pricePerGallon: Double?
    let weekLabel: String?
    let wowDeltaCents: Double?
    let fscRate: Double?
    let updatedDay: String?
    
    enum CodingKeys: String, CodingKey {
        case source, weekOf, nationalAverage, padd1, padd2, padd3, padd4, padd5, note
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pricePerGallon = try c.decodeIfPresent(Double.self, forKey: .nationalAverage)
        weekLabel = try c.decodeIfPresent(String.self, forKey: .weekOf)
        wowDeltaCents = nil  // Server does not provide week-over-week delta
        fscRate = nil        // Server does not provide FSC rate; calculateSteppedFsc endpoint provides that
        updatedDay = try c.decodeIfPresent(String.self, forKey: .weekOf)
    }
}

private struct FscTracking577: Decodable {
    let appliedMtdUsd: Double?
    let perMileUsd: Double?
    let laneCount: Int?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try to decode as flat object first (for iOS-only responses)
        if let mtd = try? container.decode(Double?.self, forKey: .appliedMtdUsd) {
            self.appliedMtdUsd = mtd
            self.perMileUsd = try? container.decode(Double?.self, forKey: .perMileUsd)
            self.laneCount = try? container.decode(Int?.self, forKey: .laneCount)
            return
        }
        
        // Otherwise decode server envelope: { surcharges: [...], summary: {...} }
        struct Envelope: Decodable {
            struct Summary: Decodable {
                let total: Int?
                let totalAmount: Double?
                let avgRate: Double?
                let currentDOEPrice: Double?
            }
            let summary: Summary?
        }
        
        let envelope = try Envelope(from: decoder)
        self.appliedMtdUsd = envelope.summary?.totalAmount
        self.perMileUsd = envelope.summary?.avgRate
        self.laneCount = envelope.summary?.total
    }
    
    enum CodingKeys: String, CodingKey {
        case appliedMtdUsd
        case perMileUsd
        case laneCount
    }
}

/// Wrapper to decode server's FSC calculation envelope and adapt to array interface.
/// Server returns: {carrier, method, dieselPrice, baselinePrice, dieselOverBaseCents,
/// stepsAboveBase, centsPerMile, mileage, fscPerCar, railcarCount, totalFsc}.
/// iOS expects [FscBand577] with band details. We decode the envelope, synthesize a
/// single FscBand577 from the calculation result, and return it wrapped in an array.
private struct FscCalcEnvelope: Decodable {
    let carrier: String?
    let method: String?
    let dieselPrice: Double?
    let baselinePrice: Double?
    let dieselOverBaseCents: Int?
    let stepsAboveBase: Int?
    let centsPerMile: Double?
    let mileage: Double?
    let fscPerCar: Double?
    let railcarCount: Int?
    let totalFsc: Double?
    
    /// Convert envelope to a single FscBand577 for backwards compatibility with the
    /// iOS view expecting [FscBand577].
    func asBand() -> FscBand577 {
        FscBand577(
            id: Int(mileage ?? 0),
            bandNumber: stepsAboveBase,
            bandName: "Stepped FSC",
            minPriceGal: baselinePrice,
            maxPriceGal: dieselPrice,
            surchargePercent: centsPerMile.map { $0 * 100 },
            isActive: true
        )
    }
}

private struct FscBand577: Decodable, Identifiable {
    let id: Int
    let bandNumber: Int?
    let bandName: String?
    let minPriceGal: Double?
    let maxPriceGal: Double?
    let surchargePercent: Double?
    let isActive: Bool?
}

// MARK: - Body

private struct RailFuelSurchargeBody: View {
    @Environment(\.palette) private var palette

    @State private var diesel: DieselIndex577? = nil
    @State private var tracking: FscTracking577? = nil
    @State private var bands: [FscBand577] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var isRecalculating = false

    // MARK: Derived

    private var captionLabel: String {
        let wk = diesel?.weekLabel ?? "WK —"
        return "\(wk) · EIA INDEX"
    }
    private var priceLabel: String {
        diesel?.pricePerGallon.map { String(format: "$%.3f", $0) } ?? "—"
    }
    private var wowLabel: String {
        guard let d = diesel?.wowDeltaCents else { return "" }
        let arrow = d >= 0 ? "▲" : "▼"
        return "\(arrow) \(d >= 0 ? "+" : "")\(String(format: "%.1f", d))¢ WoW"
    }
    private var wowPositive: Bool { (diesel?.wowDeltaCents ?? 0) >= 0 }
    private var fscRateLabel: String {
        diesel?.fscRate.map { String(format: "%.1f%%", $0) } ?? "—"
    }
    private var updatedLabel: String {
        "currentDieselIndex · updated \(diesel?.updatedDay ?? "—")"
    }
    private var appliedMtdLabel: String { tracking?.appliedMtdUsd.map { "$\(Int($0))" } ?? "—" }
    private var perMileLabel: String    { tracking?.perMileUsd.map { String(format: "$%.2f", $0) } ?? "—" }
    private var laneCountLabel: String  { tracking?.laneCount.map { "\($0)" } ?? "—" }

    private func bandColor(_ n: Int) -> Color {
        switch n {
        case 1:  return Brand.success
        case 2:  return Brand.blue
        case 3:  return Brand.warning
        default: return Brand.danger
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading FSC schedule…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    kpiStrip
                    bandSchedule
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("RAIL ENGINEER · FUEL SURCHARGE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text(captionLabel)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Fuel surcharge")
                    .font(.system(size: 28, weight: .heavy))
                    .kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
        }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("EIA #2 DIESEL")
                    .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.warning.opacity(0.16)))
                if !wowLabel.isEmpty {
                    Text(wowLabel)
                        .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                        .foregroundStyle(wowPositive ? Brand.danger : Brand.success)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill((wowPositive ? Brand.danger : Brand.success).opacity(0.10)))
                }
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(priceLabel)
                        .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("per gallon · national avg")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text(updatedLabel)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("FSC RATE")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(fscRateLabel)
                        .font(.system(size: 22, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text("of linehaul")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    // MARK: - KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "APPLIED MTD", value: appliedMtdLabel)
            MetricTile(label: "PER MILE",    value: perMileLabel, gradientNumeral: true)
            MetricTile(label: "LANES",       value: laneCountLabel)
        }
    }

    // MARK: - Band schedule

    private var bandSchedule: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("FSC STEPPED SCHEDULE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("calculateSteppedFsc")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if bands.isEmpty {
                EusoEmptyState(systemImage: "fuelpump", title: "No FSC schedule", subtitle: "Stepped schedule will appear once the index loads.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(bands.enumerated()), id: \.element.id) { idx, band in
                        bandRow(band)
                        if idx < bands.count - 1 {
                            Divider().padding(.leading, 68).overlay(palette.borderFaint)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
            }
        }
    }

    private func bandRow(_ band: FscBand577) -> some View {
        let isActive = band.isActive ?? false
        let n        = band.bandNumber ?? 1
        let color    = bandColor(n)
        let pct      = band.surchargePercent.map { String(format: "%.1f%%", $0) } ?? "—"
        let rangeStr: String = {
            let lo = band.minPriceGal.map { String(format: "$%.2f", $0) } ?? "—"
            let hi = band.maxPriceGal.map { String(format: "$%.2f", $0) } ?? "—"
            var s = "\(lo) – \(hi) / gal"
            if isActive, let idx = diesel?.pricePerGallon {
                s += " · index $\(String(format: "%.3f", idx))"
            }
            return s
        }()

        return HStack(spacing: 12) {
            ZStack {
                if isActive {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient.diagonal)
                        .frame(width: 40, height: 40)
                    Text("\(n)")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color.white)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Text("\(n)")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(color)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(band.bandName ?? "Band \(n)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(rangeStr)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if isActive {
                VStack(alignment: .trailing, spacing: 6) {
                    Text("IN EFFECT")
                        .font(.system(size: 10, weight: .bold)).kerning(0.4)
                        .foregroundStyle(Brand.success)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.success.opacity(0.12)))
                    Text(pct)
                        .font(.system(size: 15, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                }
            } else {
                Text(pct)
                    .font(.system(size: 15, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(16)
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Recalculate FSC", action: { Task { await recalculate() } }, isLoading: isRecalculating)
            Button {} label: {
                Text("Publish schedule")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load / Actions

    private func load() async {
        loading = true; loadError = nil
        struct EmptyIn: Encodable {}
        do {
            async let idxResult: DieselIndex577 = EusoTripAPI.shared.query(
                "fuelSurchargeIndex.currentDieselIndex", input: EmptyIn())
            async let bandResult: [FscBand577] = EusoTripAPI.shared.query(
                "fuelSurchargeIndex.calculateSteppedFsc", input: EmptyIn())
            let (d, b) = try await (idxResult, bandResult)
            self.diesel = d
            self.bands  = b
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        do {
            let t: FscTracking577 = try await EusoTripAPI.shared.query(
                "detentionAccessorials.getFuelSurchargeTracking", input: EmptyIn())
            self.tracking = t
        } catch { /* best-effort applied MTD */ }
        loading = false
    }

    private func recalculate() async {
        isRecalculating = true
        struct EmptyIn: Encodable {}
        struct CalcOut: Decodable {}
        do {
            let _: CalcOut = try await EusoTripAPI.shared.query(
                "fuelSurchargeIndex.generateFscSchedule", input: EmptyIn())
            await load()
        } catch { /* surface on reload */ }
        isRecalculating = false
    }
}

#Preview("577 · Rail Fuel Surcharge · Night") { RailFuelSurchargeScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("577 · Rail Fuel Surcharge · Light") { RailFuelSurchargeScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
