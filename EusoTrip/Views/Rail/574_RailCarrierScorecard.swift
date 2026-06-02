//
//  574_RailCarrierScorecard.swift
//  EusoTrip — Rail Engineer · Carrier Scorecard (composite interchange grade).
//
//  Verbatim port of "574 Rail Carrier Scorecard.svg" (Light + Dark).
//  Composite interchange score + letter grade for 4 rail carriers, 4-cell KPI strip
//  with trend deltas (on-time, claims-free, tender accept, billing accuracy),
//  carrier rows with initials chip and grade pill.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME).
//
//  Data:
//    carrierScorecard.getScorecard   (EXISTS :21)   → composite grade + KPIs
//    carrierScorecard.getTopCarriers (EXISTS :326)  → carrier rows
//    carrierScorecard.getTrends      (EXISTS :293)  → trend deltas (best-effort)
//    carrierScorecard.compareScorecards (EXISTS :210) → Compare CTA
//

import SwiftUI

struct RailCarrierScorecardScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) { RailCarrierScorecardBody() } nav: {
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

// MARK: - Data shapes

/// Tolerant value box for skipping heterogeneous server array items during
/// decode. File-private per the codebase pattern.
private struct AnyCodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = NSNull() }
        else if let b = try? c.decode(Bool.self) { value = b }
        else if let i = try? c.decode(Int.self) { value = i }
        else if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = s }
        else if let a = try? c.decode([AnyCodable].self) { value = a.map { $0.value } }
        else if let o = try? c.decode([String: AnyCodable].self) { value = o.mapValues { $0.value } }
        else { value = NSNull() }
    }
}

private struct Scorecard574: Decodable {
    let compositeScore: Double?
    let compositeGrade: String?
    let qoqDelta: Double?
    let carrierCount: Int?
    let carCount: Int?
    let period: String?
    let ontimePercent: Double?
    let ontimeDelta: Double?
    let claimsFreePercent: Double?
    let claimsFreeDelta: Double?
    let tenderAcceptPercent: Double?
    let tenderAcceptDelta: Double?
    let billingAccuracyPercent: Double?
    let billingAccuracyDelta: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try direct flat mapping first (for backward compatibility)
        var composite = try? c.decode(Double.self, forKey: .compositeScore)
        var grade = try? c.decode(String.self, forKey: .compositeGrade)
        qoqDelta = try? c.decode(Double.self, forKey: .qoqDelta)
        carrierCount = try? c.decode(Int.self, forKey: .carrierCount)
        carCount = try? c.decode(Int.self, forKey: .carCount)
        period = try? c.decode(String.self, forKey: .period)
        var ontime = try? c.decode(Double.self, forKey: .ontimePercent)
        ontimeDelta = try? c.decode(Double.self, forKey: .ontimeDelta)
        var claimsFree = try? c.decode(Double.self, forKey: .claimsFreePercent)
        claimsFreeDelta = try? c.decode(Double.self, forKey: .claimsFreeDelta)
        var tenderAccept = try? c.decode(Double.self, forKey: .tenderAcceptPercent)
        tenderAcceptDelta = try? c.decode(Double.self, forKey: .tenderAcceptDelta)
        var billingAccuracy = try? c.decode(Double.self, forKey: .billingAccuracyPercent)
        billingAccuracyDelta = try? c.decode(Double.self, forKey: .billingAccuracyDelta)

        // If flat fields not present, map from server's actual shape:
        // overallScore → compositeScore, grade → compositeGrade, metrics.* → percent fields
        if composite == nil {
            composite = try? c.decode(Double.self, forKey: CodingKeys(stringValue: "overallScore") ?? .compositeScore)
        }
        if grade == nil {
            grade = try? c.decode(String.self, forKey: CodingKeys(stringValue: "grade") ?? .compositeGrade)
        }
        if ontime == nil, let metrics = try? c.nestedContainer(keyedBy: MetricsCodingKeys.self, forKey: CodingKeys(stringValue: "metrics") ?? .compositeScore),
           let onTimeDelivery = try? metrics.nestedContainer(keyedBy: MetricsFieldCodingKeys.self, forKey: .onTimeDelivery) {
            ontime = try? onTimeDelivery.decode(Double.self, forKey: .rate)
        }
        if claimsFree == nil, let metrics = try? c.nestedContainer(keyedBy: MetricsCodingKeys.self, forKey: CodingKeys(stringValue: "metrics") ?? .compositeScore),
           let safety = try? metrics.nestedContainer(keyedBy: MetricsFieldCodingKeys.self, forKey: .safety) {
            claimsFree = try? safety.decode(Double.self, forKey: .score)
        }
        if tenderAccept == nil, let metrics = try? c.nestedContainer(keyedBy: MetricsCodingKeys.self, forKey: CodingKeys(stringValue: "metrics") ?? .compositeScore),
           let bidAcceptance = try? metrics.nestedContainer(keyedBy: MetricsFieldCodingKeys.self, forKey: .bidAcceptance) {
            tenderAccept = try? bidAcceptance.decode(Double.self, forKey: .rate)
        }
        if billingAccuracy == nil, let metrics = try? c.nestedContainer(keyedBy: MetricsCodingKeys.self, forKey: CodingKeys(stringValue: "metrics") ?? .compositeScore),
           let completionRate = try? metrics.nestedContainer(keyedBy: MetricsFieldCodingKeys.self, forKey: .completionRate) {
            billingAccuracy = try? completionRate.decode(Double.self, forKey: .rate)
        }

        compositeScore = composite
        compositeGrade = grade
        ontimePercent = ontime
        claimsFreePercent = claimsFree
        tenderAcceptPercent = tenderAccept
        billingAccuracyPercent = billingAccuracy
    }
    
    enum CodingKeys: String, CodingKey {
        case compositeScore, compositeGrade, qoqDelta, carrierCount, carCount, period
        case ontimePercent, ontimeDelta, claimsFreePercent, claimsFreeDelta
        case tenderAcceptPercent, tenderAcceptDelta, billingAccuracyPercent, billingAccuracyDelta
    }
    
    enum MetricsCodingKeys: String, CodingKey {
        case onTimeDelivery, safety, compliance, completionRate, bidAcceptance, hazmat
    }
    
    enum MetricsFieldCodingKeys: String, CodingKey {
        case rate, score
    }
}

private struct TrendData574: Decodable {
    let ontimeDelta: Double?
    let claimsFreeDelta: Double?
    let tenderAcceptDelta: Double?
    let billingAccuracyDelta: Double?
    let compositeDelta: Double?
}

private struct CarrierRow574: Decodable, Identifiable {
    let id: Int
    let name: String?
    let code: String?
    let initials: String?
    let score: Double?
    let grade: String?
    let carCount: Int?
    let laneCount: Int?
    let routeSummary: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Server (carrierScorecard.getTopCarriers) returns carrierId/companyName/totalLoads;
        // code/initials/laneCount/routeSummary aren't in that response (stay nil).
        self.id = (try (c.decodeIfPresent(Int.self, forKey: .id) ?? c.decodeIfPresent(Int.self, forKey: .carrierId))) ?? 0
        self.name = try (c.decodeIfPresent(String.self, forKey: .name) ?? c.decodeIfPresent(String.self, forKey: .companyName))
        self.code = try c.decodeIfPresent(String.self, forKey: .code)
        self.initials = try c.decodeIfPresent(String.self, forKey: .initials)
        self.score = try c.decodeIfPresent(Double.self, forKey: .score)
        self.grade = try c.decodeIfPresent(String.self, forKey: .grade)
        self.carCount = try (c.decodeIfPresent(Int.self, forKey: .carCount) ?? c.decodeIfPresent(Int.self, forKey: .totalLoads))
        self.laneCount = try c.decodeIfPresent(Int.self, forKey: .laneCount)
        self.routeSummary = try c.decodeIfPresent(String.self, forKey: .routeSummary)
    }

    enum CodingKeys: String, CodingKey {
        case id, carrierId, name, companyName, code, initials, score, grade, carCount, totalLoads, laneCount, routeSummary
    }
}

// MARK: - Body

private struct RailCarrierScorecardBody: View {
    @Environment(\.palette) private var palette

    @State private var scorecard: Scorecard574? = nil
    @State private var carriers: [CarrierRow574] = []
    @State private var trends: TrendData574? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var isComparing = false

    // MARK: Derived

    private var captionLabel: String {
        let period = scorecard?.period ?? "YTD"
        let count  = scorecard?.carrierCount ?? carriers.count
        return "\(period) · \(count) CARRIERS"
    }
    private var gradeLabel: String  { scorecard?.compositeGrade ?? "—" }
    private var scoreLabel: String  {
        guard let s = scorecard?.compositeScore else { return "—" }
        return String(format: "%.1f", s)
    }
    private var qoqLabel: String {
        let d = scorecard?.qoqDelta ?? trends?.compositeDelta
        guard let d = d else { return "" }
        let arrow = d >= 0 ? "▲" : "▼"
        return "\(arrow) \(d >= 0 ? "+" : "")\(String(format: "%.1f", d)) QoQ"
    }
    private var qoqPositive: Bool { (scorecard?.qoqDelta ?? trends?.compositeDelta ?? 0) >= 0 }
    private var compositeSubLabel: String {
        let count = scorecard?.carrierCount ?? carriers.count
        let cars  = scorecard?.carCount ?? 0
        return "weighted across \(count) rail carriers · \(cars) cars"
    }

    // KPI values + trends
    private func pctLabel(_ v: Double?) -> String {
        guard let v = v else { return "—" }
        return v >= 10 ? String(format: "%.0f%%", v) : String(format: "%.1f%%", v)
    }
    private func trendTuple(_ delta: Double?, unit: String = " pts") -> (String, Bool)? {
        guard let d = delta else { return nil }
        let sign = d >= 0 ? "+" : ""
        return ("\(sign)\(String(format: "%.1f", d))\(unit)", d >= 0)
    }

    private var ontimeLabel:    String { pctLabel(scorecard?.ontimePercent) }
    private var claimsLabel:    String { pctLabel(scorecard?.claimsFreePercent) }
    private var tenderLabel:    String { pctLabel(scorecard?.tenderAcceptPercent) }
    private var billingLabel:   String { pctLabel(scorecard?.billingAccuracyPercent) }

    private var ontimeTrend:    (String, Bool)? { trendTuple(scorecard?.ontimeDelta  ?? trends?.ontimeDelta) }
    private var claimsTrend:    (String, Bool)? { trendTuple(scorecard?.claimsFreeDelta ?? trends?.claimsFreeDelta) }
    private var tenderTrend:    (String, Bool)? { trendTuple(scorecard?.tenderAcceptDelta ?? trends?.tenderAcceptDelta) }
    private var billingTrend:   (String, Bool)? { trendTuple(scorecard?.billingAccuracyDelta ?? trends?.billingAccuracyDelta) }

    private func carrierColor(_ code: String?) -> Color {
        switch (code ?? "").uppercased() {
        case "BNSF", "BN": return Color(hex: 0xFF6B00)
        case "UP":         return Brand.warning
        case "NS":         return Brand.blue
        case "CSX":        return Brand.success
        case "CN":         return Color(hex: 0x8C00E0)
        case "KCS", "CP":  return Brand.danger
        default:
            let palette: [Color] = [Brand.success, Brand.blue, Brand.warning, Brand.danger]
            return palette[abs((code ?? "X").hashValue) % palette.count]
        }
    }

    private func gradeColor(_ grade: String?) -> Color {
        let g = grade ?? ""
        if g.hasPrefix("A") { return Brand.success }
        if g.hasPrefix("B") { return Brand.warning }
        if g.hasPrefix("C") { return Brand.rail }
        return Brand.danger
    }

    private func carrierSub(_ c: CarrierRow574) -> String {
        var parts: [String] = []
        if let cars  = c.carCount   { parts.append("\(cars) cars") }
        if let lanes = c.laneCount  { parts.append("\(lanes) lanes") }
        if let route = c.routeSummary { parts.append(route) }
        return parts.joined(separator: " · ")
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading scorecard…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    kpiStrip
                    carrierList
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
                    Text("RAIL ENGINEER · SCORECARD")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text(captionLabel)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Carrier scorecard")
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
        HStack(spacing: 16) {
            Text(gradeLabel)
                .font(.system(size: 36, weight: .heavy))
                .foregroundStyle(Color.white)
                .frame(width: 76, height: 76)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient.diagonal)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text("COMPOSITE INTERCHANGE SCORE")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(scoreLabel)
                        .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    if !qoqLabel.isEmpty {
                        Text(qoqLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(qoqPositive ? Brand.success : Brand.danger)
                    }
                }
                Text(compositeSubLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
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

    // MARK: - KPI strip (4-cell with trend deltas)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            kpiTile("ON-TIME",     value: ontimeLabel,  trend: ontimeTrend,  isGradient: true)
            kpiTile("CLAIMS-FREE", value: claimsLabel,  trend: claimsTrend)
            kpiTile("TENDER ACPT", value: tenderLabel,  trend: tenderTrend)
            kpiTile("BILL ACC",    value: billingLabel, trend: billingTrend)
        }
    }

    @ViewBuilder
    private func kpiTile(_ label: String, value: String, trend: (String, Bool)?, isGradient: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if isGradient {
                Text(value)
                    .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
            } else {
                Text(value)
                    .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
            if let (t, pos) = trend {
                Text(t)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(pos ? Brand.success : Brand.danger)
            } else {
                Color.clear.frame(height: 14)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
    }

    // MARK: - Carrier list

    private var carrierList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("RAIL CARRIERS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getTopCarriers")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if carriers.isEmpty {
                EusoEmptyState(
                    systemImage: "tram",
                    title: "No carrier data",
                    subtitle: "Rail carrier performance scores will appear here."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(carriers.enumerated()), id: \.element.id) { idx, carrier in
                        carrierRow(carrier)
                        if idx < carriers.count - 1 {
                            Divider()
                                .padding(.leading, 68)
                                .overlay(palette.borderFaint)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
            }
        }
    }

    private func carrierRow(_ c: CarrierRow574) -> some View {
        let color     = carrierColor(c.code)
        let initials  = c.initials ?? String((c.code ?? c.name ?? "?").prefix(2)).uppercased()
        let gColor    = gradeColor(c.grade)
        let scoreStr  = c.score.map { String(format: "%.1f", $0) } ?? "—"

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.14))
                    .frame(width: 40, height: 40)
                Text(initials)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(c.name ?? c.code ?? "—")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(carrierSub(c))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(c.grade ?? "—")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(gColor)
                    .frame(width: 44, height: 24)
                    .background(Capsule().fill(gColor.opacity(0.14)))
                Text(scoreStr)
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(16)
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Compare carriers", action: { Task { await compareCarriers() } }, isLoading: isComparing)
            Button {} label: {
                Text("Export report")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load / Actions

    private func load() async {
        loading = true; loadError = nil
        struct EmptyIn: Encodable {}
        do {
            async let sc: Scorecard574 = EusoTripAPI.shared.query(
                "carrierScorecard.getScorecard", input: EmptyIn())
            async let rows: [CarrierRow574] = EusoTripAPI.shared.query(
                "carrierScorecard.getTopCarriers", input: EmptyIn())
            let (s, c) = try await (sc, rows)
            self.scorecard = s
            self.carriers  = c
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        do {
            let t: TrendData574 = try await EusoTripAPI.shared.query(
                "carrierScorecard.getTrends", input: EmptyIn())
            self.trends = t
        } catch { /* best-effort trend enrichment */ }
        loading = false
    }

    private func compareCarriers() async {
        isComparing = true
        struct EmptyIn: Encodable {}
        struct CompareOut: Decodable {
            init(from decoder: Decoder) throws {
                // Server returns a bare array of carrier comparison objects.
                // Decode and discard — we don't use the data yet.
                let c = try decoder.singleValueContainer()
                _ = try c.decode([AnyCodable].self)
            }
        }
        do {
            let _: CompareOut = try await EusoTripAPI.shared.query(
                "carrierScorecard.compareScorecards", input: EmptyIn())
        } catch { /* non-fatal */ }
        isComparing = false
    }
}

#Preview("574 · Rail Carrier Scorecard · Night") { RailCarrierScorecardScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("574 · Rail Carrier Scorecard · Light") { RailCarrierScorecardScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
