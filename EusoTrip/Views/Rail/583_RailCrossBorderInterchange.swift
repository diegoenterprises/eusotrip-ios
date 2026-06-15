//
//  583_RailCrossBorderInterchange.swift
//  EusoTrip — Rail 583 · Cross-Border Interchange
//

import SwiftUI

// MARK: - Outer shell

struct RailCrossBorderInterchangeScreen: View {
    let theme: Theme.Palette
    let railId: String

    var body: some View {
        Shell(theme: theme) {
            RailCrossBorderInterchangeBody(railId: railId)
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

// MARK: - Data shapes

private struct InterchangePoint583: Decodable {
    let cars: Int?
    let carrierFrom: String?
    let carrierTo: String?
    let port: String?
    let direction: String?
    let tradeAgreement: String?
}

private struct CrossingTime583: Decodable {
    let estimatedHours: Double?
}

private struct ComplianceCheckEnvelope583: Decodable {
    let interchangePoint: String?
    let direction: String?
    let regulatory: [ComplianceCheck583]?
    let overallCompliant: Bool?
}

private struct ComplianceCheck583: Decodable {
    let checkName: String?
    let checkCode: String?
    let detail: String?
    let status: String?
    let category: String?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        checkName = try container.decodeIfPresent(String.self, forKey: .checkName)
        checkCode = try container.decodeIfPresent(String.self, forKey: .checkCode)
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        category = try container.decodeIfPresent(String.self, forKey: .category)
    }
    
    enum CodingKeys: String, CodingKey {
        case checkName = "requirement"
        case checkCode = "regulation"
        case detail = "details"
        case status
        case category
    }
}

private struct CrewCerts583: Decodable {
    let certified: Bool?
    let reliefCarrier: String?
    let reliefType: String?
    let hazmatBlock: Bool?
    let carCount: Int?

    init(from decoder: Decoder) throws {
        // Server endpoint getCrewCertRequirements returns RailCrewCertification[]
        // (bare array), not a single CrewCerts583 object.
        // Tolerate bare array by decoding into singleValueContainer and extracting first element.
        let container = try decoder.singleValueContainer()
        if let certs = try? container.decode([RailCrewCertObj].self) {
            // Array case: extract first cert's properties
            let first = certs.first
            self.certified = first?.certType.lowercased().contains("certified") ?? false
            self.reliefCarrier = nil
            self.reliefType = nil
            self.hazmatBlock = false
            self.carCount = nil
        } else {
            // Object case (fallback): decode as keyed container
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.certified = try c.decodeIfPresent(Bool.self, forKey: .certified)
            self.reliefCarrier = try c.decodeIfPresent(String.self, forKey: .reliefCarrier)
            self.reliefType = try c.decodeIfPresent(String.self, forKey: .reliefType)
            self.hazmatBlock = try c.decodeIfPresent(Bool.self, forKey: .hazmatBlock)
            self.carCount = try c.decodeIfPresent(Int.self, forKey: .carCount)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case certified, reliefCarrier, reliefType, hazmatBlock, carCount
    }

    private struct RailCrewCertObj: Decodable {
        let country: String?
        let certType: String
        let description: String?
        let issuingAuthority: String?
        let regulation: String?
        let validityYears: Int?
        let requiredFor: String?
        let crossBorderReciprocity: String?
    }
}

private struct RailIdIn583: Encodable { let railId: String }

// MARK: - Corridor weather shapes (weather.getRouteConditions by railId)
//
// The interchange dwell is the est. crossing time the server hands back; bad
// corridor weather at the crossing pushes that dwell out (gusts forcing a
// speed restriction into the yard, floods/washouts holding the cut, low
// visibility slowing the hand-off). We surface that as an HONEST dwell DELTA
// on top of the base estimate — base + Δweather = total — never silently
// overwriting the server figure, and never a fabricated delta when the
// enterprise feed is dark (available:false / nil today → no delta, no note).

private struct RouteConditions583: Decodable {
    let available: Bool?
    let overallRisk: String?            // "low"|"moderate"|"high"|"extreme"|"unknown"
    let segments: [RouteSegment583]?
    let advisories: [RouteAdvisory583]?
}

private struct RouteSegment583: Decodable {
    let risk: String?
    let condition: String?
    let weatherCode: Int?
    let windGust: Double?               // mph
    let visibility: Double?             // mi
    let precipitationIntensity: Double? // in/hr
    let floods: [RouteFlood583]?
    let overallRisk: String?
}

private struct RouteFlood583: Decodable {
    let severity: String?
    let headline: String?
}

private struct RouteAdvisory583: Decodable {
    let eventType: String?
    let severity: String?
    let headline: String?
}

// MARK: - Body

private struct RailCrossBorderInterchangeBody: View {
    @Environment(\.palette) private var palette
    let railId: String

    @State private var interchangePoint: InterchangePoint583? = nil
    @State private var crossingTime: CrossingTime583? = nil
    @State private var complianceChecks: [ComplianceCheck583] = []
    @State private var crewCerts: CrewCerts583? = nil
    @State private var route: RouteConditions583? = nil
    @State private var isRunningCheck = false

    // MARK: Derived

    private var carrierLabel: String {
        let from = interchangePoint?.carrierFrom ?? "BNSF"
        let to   = interchangePoint?.carrierTo   ?? "KCSM"
        return "\(from) to \(to)"
    }
    private var tradeAgreementLabel: String {
        (interchangePoint?.tradeAgreement ?? "USMCA") + " OK"
    }
    /// The server's base est. crossing dwell (hours) — never mutated.
    private var baseDwellHours: Double? { crossingTime?.estimatedHours }

    /// The honest weather dwell DELTA (added hours) at the crossing, derived
    /// from the REAL corridor envelope. nil when the feed is dark or clear.
    /// Magnitude is a transparent, bounded mapping of the weather DRIVER —
    /// never a fabricated number when the server carries no signal:
    ///   flood/washout hold .......... +2.0h (hardest)
    ///   gust ≥58 mph (restriction) ... +1.5h
    ///   gust ≥40 mph ................. +1.0h
    ///   visibility ≤1 mi ............. +0.75h
    ///   HIGH/SEVERE/EXTREME risk ..... +1.0h
    ///   active severe advisory ....... +0.5h
    /// At most one driver (the worst) is applied so the delta never double-counts.
    private var weatherDelta: (hours: Double, glyph: WeatherIcons.Utility, weatherCode: Int?, color: Color, reason: String)? {
        guard let r = route, r.available != false else { return nil }
        let segs = r.segments ?? []
        let advs = r.advisories ?? []

        for seg in segs {
            if let flood = (seg.floods ?? []).first {
                return (2.0, .alert, seg.weatherCode, Brand.danger,
                        flood.headline ?? "flooding holding the cut at the crossing")
            }
        }
        if let g = segs.compactMap({ s in s.windGust.map { ($0, s) } }).max(by: { $0.0 < $1.0 }) {
            if g.0 >= 58 {
                return (1.5, .wind, g.1.weatherCode, Brand.danger,
                        "\(Int(g.0.rounded())) mph gusts — speed restriction into the yard")
            }
            if g.0 >= 40 {
                return (1.0, .wind, g.1.weatherCode, Brand.warning,
                        "\(Int(g.0.rounded())) mph gusts slowing the hand-off")
            }
        }
        if let v = segs.compactMap({ s in s.visibility.map { ($0, s) } }).min(by: { $0.0 < $1.0 }), v.0 <= 1.0 {
            return (0.75, .eye, v.1.weatherCode, Brand.warning,
                    "\(v.0.formatted(.number.precision(.fractionLength(0...1)))) mi visibility slowing the crossing")
        }
        let risk = (r.overallRisk ?? "").lowercased()
        if ["high", "severe", "extreme", "elevated"].contains(risk) {
            return (1.0, .alert, nil, Brand.danger,
                    "corridor risk \(risk.uppercased()) at the crossing")
        }
        if let adv = advs.first(where: { ["severe", "extreme", "high"].contains(($0.severity ?? "").lowercased()) }) {
            return (0.5, .alert, nil, Brand.warning,
                    adv.headline ?? adv.eventType ?? "active weather advisory on the corridor")
        }
        return nil
    }

    /// Total est. dwell = base + weather delta. Falls back to base when there's
    /// no delta and to nil when the server gave no base estimate.
    private var totalDwellHours: Double? {
        guard let base = baseDwellHours else { return nil }
        return base + (weatherDelta?.hours ?? 0)
    }

    /// The hero figure: the WEATHER-ADJUSTED total when a delta applies, else
    /// the plain base estimate. Honest "-" when the server gave no estimate.
    private var dwellLabel: String {
        guard let h = totalDwellHours else { return "-" }
        return String(format: "%.1fh", h)
    }
    private var portLabel: String {
        guard let p = interchangePoint?.port, let d = interchangePoint?.direction else { return "-" }
        return "\(p) · \(d)"
    }
    private var carCount: Int  { interchangePoint?.cars ?? 0 }
    private var clearedCount: Int {
        complianceChecks.filter { ($0.status ?? "").lowercased() == "cleared" }.count
    }
    private var totalChecks: Int { max(complianceChecks.count, 1) }
    private var checksLabel: String { "\(clearedCount)/\(totalChecks)" }
    private var checksAllClear: Bool {
        !complianceChecks.isEmpty && clearedCount == complianceChecks.count
    }

    // MARK: View

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                eyebrow
                headline
                IridescentHairline()
                heroCard
                if let delta = weatherDelta { weatherDwellChip(delta) }
                kpiStrip
                complianceSection
                crewCertsStrip
                ctaPair
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
        }
        .task { await loadAll() }
    }

    // MARK: Eyebrow + headline

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ RAIL ENGINEER · INTERCHANGE")
                .font(.system(size: 9, weight: .black))
                .kerning(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text(railId)
                .font(.system(size: 9, weight: .heavy).monospaced())
                .kerning(0.6)
                .foregroundColor(palette.textTertiary)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Border interchange")
                .font(.system(size: 28, weight: .heavy))
                .kerning(-0.4)
                .foregroundColor(palette.textPrimary)
                .lineLimit(1)
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(palette.textSecondary)
        }
    }

    // MARK: Hero card

    private var heroCard: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Radius.xl)
                .fill(palette.bgCard)
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)

            VStack(alignment: .leading, spacing: Space.s3) {
                // Top pills
                HStack(spacing: Space.s2) {
                    Text(tradeAgreementLabel)
                        .font(.system(size: 11, weight: .bold))
                        .kerning(0.5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Brand.success.opacity(0.14)))
                        .foregroundColor(Brand.success)

                    Text(carrierLabel)
                        .font(.system(size: 11, weight: .bold))
                        .kerning(0.5)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.05)))
                        .foregroundColor(palette.textPrimary)
                }

                // Dwell figure + cars column
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: Space.s2) {
                        Text(dwellLabel)
                            .font(.system(size: 34, weight: .bold).monospacedDigit())
                            .foregroundStyle(LinearGradient.diagonal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("est. crossing dwell")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(palette.textSecondary)
                            Text(portLabel)
                                .font(.system(size: 11))
                                .foregroundColor(palette.textTertiary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CARS")
                            .font(.system(size: 10, weight: .black))
                            .kerning(0.6)
                            .foregroundColor(palette.textTertiary)
                        Text("\(carCount)")
                            .font(.system(size: 22, weight: .bold).monospacedDigit())
                            .foregroundColor(palette.textPrimary)
                        Text("in block")
                            .font(.system(size: 11))
                            .foregroundColor(palette.textSecondary)
                    }
                }
            }
            .padding(Space.s4)
        }
        .frame(height: 116)
    }

    // MARK: Weather dwell-delta chip (bespoke — WeatherIcons, never an SF Symbol)
    //
    // Sits directly under the dwell hero so the adjusted figure reads
    // honestly: the hero shows base + Δweather as the TOTAL, this chip shows
    // the breakdown and the weather DRIVER (verbatim from the server). Honest
    // hidden when the corridor is clear / the enterprise feed is dark.

    private func weatherDwellChip(_ delta: (hours: Double, glyph: WeatherIcons.Utility, weatherCode: Int?, color: Color, reason: String)) -> some View {
        let baseStr = baseDwellHours.map { String(format: "%.1fh", $0) } ?? "-"
        let deltaStr = String(format: "+%.1fh", delta.hours)
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(delta.color.opacity(0.14))
                    .frame(width: 40, height: 40)
                if let code = delta.weatherCode, code != 0 {
                    WeatherIcons.symbolView(for: code, size: 24)
                } else {
                    WeatherIcons.utility(delta.glyph, size: 20, tint: delta.color)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Weather dwell")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundColor(palette.textPrimary)
                    Text(deltaStr)
                        .font(.system(size: 11, weight: .heavy).monospacedDigit())
                        .foregroundColor(delta.color)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(delta.color.opacity(0.14)))
                }
                Text("\(baseStr) base \(deltaStr) weather · \(delta.reason)")
                    .font(.system(size: 11))
                    .foregroundColor(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(delta.color.opacity(0.35), lineWidth: 1)
                )
        )
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "CHECKS", value: checksLabel,    accent: checksAllClear ? Brand.success : palette.textPrimary)
            MetricTile(label: "CARS",   value: "\(carCount)")
            MetricTile(label: "DWELL",  value: dwellLabel)
        }
    }

    // MARK: Compliance checks

    private var complianceSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("COMPLIANCE CHECKS")
                .font(.system(size: 9, weight: .black))
                .kerning(1.0)
                .foregroundColor(palette.textTertiary)

            VStack(spacing: 0) {
                ForEach(Array(complianceChecks.enumerated()), id: \.offset) { idx, check in
                    if idx > 0 {
                        Divider()
                            .overlay(Color.black.opacity(0.06))
                            .padding(.horizontal, Space.s4)
                    }
                    complianceRow(check)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }

    @ViewBuilder
    private func complianceRow(_ check: ComplianceCheck583) -> some View {
        let (chipColor, chipIcon) = checkChipInfo(check)
        let (pillLabel, pillColor) = checkPillInfo(check.status)
        let subText = [check.checkCode, check.detail].compactMap { $0 }.joined(separator: " · ")

        HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(chipColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: chipIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(chipColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(check.checkName ?? "-")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(palette.textPrimary)
                if !subText.isEmpty {
                    Text(subText)
                        .font(.system(size: 11).monospaced())
                        .kerning(0.4)
                        .foregroundColor(palette.textSecondary)
                }
            }
            Spacer()
            Text(pillLabel)
                .font(.system(size: 11, weight: .bold))
                .kerning(0.5)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(pillColor.opacity(0.14)))
                .foregroundColor(pillColor)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 14)
    }

    // MARK: Crew certs strip

    private var crewCertsStrip: some View {
        let certified     = crewCerts?.certified     ?? false
        let reliefCarrier = crewCerts?.reliefCarrier ?? "KCSM"
        let reliefType    = crewCerts?.reliefType    ?? "gateway"
        let hazmat        = crewCerts?.hazmatBlock   ?? false
        let cars          = crewCerts?.carCount      ?? carCount
        let line1 = certified
            ? "interchange crew certified · \(reliefCarrier) relief at \(reliefType)"
            : "crew certification pending"
        let line2 = "est. crossing \(dwellLabel) · \(hazmat ? "hazmat block" : "standard block") · \(cars) cars"

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CREW CERTS")
                    .font(.system(size: 9, weight: .black))
                    .kerning(0.8)
                    .foregroundColor(palette.textTertiary)
                Spacer()
            }
            Text(line1)
                .font(.system(size: 11))
                .foregroundColor(palette.textSecondary)
            Text(line2)
                .font(.system(size: 11))
                .foregroundColor(palette.textSecondary)
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(Color.black.opacity(0.06), lineWidth: 1)
                )
        )
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(
                title: "Run check",
                action: { isRunningCheck = true; Task { await runCheck() } },
                leadingIcon: "plus",
                isLoading: isRunningCheck
            )
            Button("Border docs") {}
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(palette.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    Capsule()
                        .fill(palette.bgCard)
                        .overlay(Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1))
                )
        }
    }

    // MARK: Helpers

    private func checkChipInfo(_ check: ComplianceCheck583) -> (Color, String) {
        let cat    = (check.category ?? "").lowercased()
        let status = (check.status   ?? "").lowercased()
        let color: Color = status == "cleared" ? Brand.success
                         : (status == "failed" ? Brand.danger : Brand.warning)
        return (cat == "dg" || cat == "hazmat")
            ? (color, "exclamationmark.triangle.fill")
            : (color, "doc.badge.checkmark.fill")
    }

    private func checkPillInfo(_ status: String?) -> (String, Color) {
        switch (status ?? "").lowercased() {
        case "cleared": return ("CLEARED", Brand.success)
        case "failed":  return ("FAILED",  Brand.danger)
        case "hold":    return ("HOLD",    Brand.danger)
        case "pending": return ("PENDING", Brand.info)
        default:        return ("-",       Brand.info)
        }
    }

    // MARK: Data loading

    private func loadAll() async {
        async let pointTask: InterchangePoint583 = EusoTripAPI.shared.query(
            "railShipments.getCrossBorderInterchangePoints",
            input: RailIdIn583(railId: railId)
        )
        async let timeTask: CrossingTime583 = EusoTripAPI.shared.query(
            "railShipments.estimateRailBorderCrossingTime",
            input: RailIdIn583(railId: railId)
        )
        async let checksTask: [ComplianceCheck583] = EusoTripAPI.shared.query(
            "railShipments.checkCrossBorderRailCompliance",
            input: RailIdIn583(railId: railId)
        )
        async let certsTask: CrewCerts583 = EusoTripAPI.shared.query(
            "railShipments.getCrossBorderCrewCerts",
            input: RailIdIn583(railId: railId)
        )
        // Corridor weather at the crossing — by railId (the screen's anchor).
        // Enterprise-gated, so available:false / nil today → no dwell delta,
        // no note. Soft-fail: a weather error never breaks the interchange.
        async let routeTask: RouteConditions583 = EusoTripAPI.shared.query(
            "weather.getRouteConditions",
            input: RailIdIn583(railId: railId)
        )

        interchangePoint = try? await pointTask
        crossingTime     = try? await timeTask
        complianceChecks = (try? await checksTask) ?? []
        crewCerts        = try? await certsTask
        route            = try? await routeTask
    }

    private func runCheck() async {
        defer { isRunningCheck = false }
        let result: [ComplianceCheck583]? = try? await EusoTripAPI.shared.query(
            "railShipments.checkCrossBorderRailCompliance",
            input: RailIdIn583(railId: railId)
        )
        if let r = result { complianceChecks = r }
    }
}
