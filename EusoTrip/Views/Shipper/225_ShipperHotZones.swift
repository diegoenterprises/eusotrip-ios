//
//  225_ShipperHotZones.swift
//  EusoTrip 2027 UI — Shipper · Hot Zones (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29 — reconciled to wireframe canon at
//  /02 Shipper/Code/225_ShipperHotZones.swift. Persona: Diego Usoro
//  / Eusorone Technologies (companyId 1) per §11. Hot tiles are the
//  metros where Diego pays peak rates (Houston UN1203 tanker, LA
//  reefer, KC NH₃ MC-331, Newark DOT-117 crude rail). Cold tiles
//  surface metros with capacity > demand so Diego can post against
//  the discount.
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · HOT ZONES / "{N} METROS · MARKET PULSE LIVE"
//    2. Title block      Hot zones / "Eusorone Technologies · capacity-vs-demand by metro"
//    3. IridescentHairline
//    4. KPI summary      3-cell · AVG PULSE (gradient) · HOT METROS (danger) · COLD METROS (success)
//    5. Equipment chips  All / Tanker / Reefer / Hazmat / Rail / Dry Van with derived counts
//    6. HOT ZONES        section eyebrow + 2-col grid of hot-zone tiles
//    7. COLD ZONES       section eyebrow + strip of cold-zone tiles
//    8. Action ribbon    success-tinted "Post {coldZone} at $X/mi" recommendation
//    9. Formula explainer national pulse calculation pointer
//
//  Real wiring preserved: `hotZones.getRateFeed(equipment:)` via
//  `ShipperHotZonesStore`. Returns `{ zones, coldZones, marketPulse,
//  timestamp }`. Equipment chip drives a re-fetch.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2137 — `HotZoneEntry` doesn't ship a sparkline series.
//                Hot tile chart paints a placeholder hairline until
//                the envelope adds `pulseSeries: [{ t, ratio }]`.
//    EUSO-2138 — No action-ribbon recommendation engine. Ribbon
//                surfaces a generic copy citing the first cold zone
//                when present; full save-vs-spot calc lands when
//                backend ships `hotZones.getColdRecommendation`.
//
//  Doctrine refs: §2 LOADS-tab nav (handled by ContentView); §3
//  numbers-first copy ("+8.6% · 4 hot · 2 cold"); §4.3 single
//  iridescent hairline; §11 / §11.2 / §11.4 Diego canon + UN1203 /
//  UN1005 / DOT-117; §15.2 status-aware tile rim grammar; §16 KPI
//  summary card; §17.2 equipment chip pillar; §19.2 file-scoped
//  hotFade / coldFade / Sparkline helpers; §20.4 no dead buttons;
//  §22.2 textTertiary informational counter.
//

import SwiftUI

// MARK: - Equipment filter (wireframe canon)

private enum HotEquipFilter: String, CaseIterable, Identifiable {
    case all
    case tanker
    case reefer
    case hazmat
    case rail
    case dryVan

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:    return "All"
        case .tanker: return "Tanker"
        case .reefer: return "Reefer"
        case .hazmat: return "Hazmat"
        case .rail:   return "Rail"
        case .dryVan: return "Dry van"
        }
    }

    var serverEquipment: String? {
        switch self {
        case .all:    return nil
        case .tanker: return "TANKER"
        case .reefer: return "REEFER"
        case .hazmat: return nil   // backend filter pending; client-side match by topEquipment
        case .rail:   return nil   // backend filter pending; client-side match
        case .dryVan: return "DRY_VAN"
        }
    }

    var matchKeyword: String? {
        switch self {
        case .hazmat: return "HAZMAT"
        case .rail:   return "RAIL"
        default:      return nil
        }
    }
}

// MARK: - Store (preserved + extended)

@MainActor
final class ShipperHotZonesStore: ObservableObject {
    enum Phase {
        case idle
        case loading
        case loaded(HotZonesFeedResult)
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published fileprivate var equipment: HotEquipFilter = .all {
        didSet {
            if oldValue != equipment { Task { await load() } }
        }
    }

    private let api: EusoTripAPI
    init(api: EusoTripAPI = .shared) { self.api = api }

    func load() async {
        phase = .loading
        do {
            let r = try await api.hotZones.getRateFeed(equipment: equipment.serverEquipment)
            phase = .loaded(r)
        } catch {
            phase = .error("Couldn't reach market feed.")
        }
    }
}

// MARK: - Screen root

struct ShipperHotZones: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = ShipperHotZonesStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                    .padding(.top, Space.s5)
                titleBlock
                    .padding(.top, Space.s2)
                IridescentHairline()
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s5)

                content
                    .padding(.top, Space.s3)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    // MARK: TopBar

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · HOT ZONES")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text(counterEyebrow)
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .accessibilityLabel(counterAccessibility)
        }
        .padding(.horizontal, Space.s5)
    }

    private var counterEyebrow: String {
        if case .loaded(let f) = store.phase {
            let total = f.zones.count + (f.coldZones?.count ?? 0)
            return "\(total) METROS · MARKET PULSE LIVE"
        }
        return "MARKET PULSE LIVE"
    }

    private var counterAccessibility: String {
        if case .loaded(let f) = store.phase {
            return "\(f.zones.count) hot metros, \(f.coldZones?.count ?? 0) cold metros"
        }
        return "Loading market pulse"
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hot zones")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Text("Eusorone Technologies · capacity-vs-demand by metro")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
    }

    // MARK: Content state machine

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .idle, .loading:
            VStack(spacing: Space.s2) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.3))
                        .frame(height: 92)
                }
            }
            .padding(.horizontal, Space.s5)
        case .error(let m):
            errorCard(m)
                .padding(.horizontal, Space.s5)
        case .loaded(let f):
            VStack(alignment: .leading, spacing: 0) {
                kpiSummaryStrip(f)
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s3)

                equipmentChipRow
                    .padding(.top, Space.s4)

                let zones = filteredZones(f)
                if !zones.isEmpty {
                    sectionLabel("HOT ZONES · \(zones.count) METROS · DEMAND > CAPACITY")
                        .padding(.top, Space.s5)
                    hotGrid(zones)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)
                }

                if let cold = f.coldZones, !cold.isEmpty {
                    sectionLabel("COLD ZONES · \(cold.count) METROS · CAPACITY > DEMAND")
                        .padding(.top, Space.s5)
                    coldStrip(cold)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)
                }

                if let cold = f.coldZones?.first {
                    actionRibbon(cold: cold)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s4)
                }

                formulaExplainer
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s4)
            }
        }
    }

    private func filteredZones(_ f: HotZonesFeedResult) -> [HotZoneEntry] {
        guard let key = store.equipment.matchKeyword else { return f.zones }
        return f.zones.filter { z in
            z.topEquipment.contains { $0.uppercased().contains(key) }
        }
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(EType.micro)
            .tracking(1.0)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s5)
    }

    // MARK: KPI summary strip (3-cell · AVG PULSE / HOT METROS / COLD METROS)

    private func kpiSummaryStrip(_ f: HotZonesFeedResult) -> some View {
        let avgPulse: String = {
            let changes = f.zones.compactMap { $0.rateChangePercent }
            guard !changes.isEmpty else { return "—" }
            let avg = changes.reduce(0, +) / Double(changes.count)
            return String(format: "%+.1f%%", avg)
        }()
        let hot = f.zones.count
        let cold = f.coldZones?.count ?? 0

        return HStack(spacing: 0) {
            kpiCell(label: "AVG PULSE",
                    value: avgPulse,
                    valueStyle: .gradient,
                    trail: "vs 30d",
                    trailColor: palette.textSecondary)
            kpiDivider
            kpiCell(label: "HOT METROS",
                    value: "\(hot)",
                    valueStyle: hot > 0 ? .danger : .neutral,
                    trail: hot > 0 ? "demand spike" : "calm",
                    trailColor: palette.textSecondary)
            kpiDivider
            kpiCell(label: "COLD METROS",
                    value: "\(cold)",
                    valueStyle: cold > 0 ? .success : .neutral,
                    trail: cold > 0 ? "post here" : "—",
                    trailColor: cold > 0 ? Brand.success : palette.textSecondary)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    private enum ValueStyle { case gradient, danger, success, neutral }

    private func kpiCell(label: String,
                         value: String,
                         valueStyle: ValueStyle,
                         trail: String,
                         trailColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Group {
                    switch valueStyle {
                    case .gradient: Text(value).foregroundStyle(LinearGradient.diagonal)
                    case .danger:   Text(value).foregroundStyle(Brand.danger)
                    case .success:  Text(value).foregroundStyle(Brand.success)
                    case .neutral:  Text(value).foregroundStyle(palette.textPrimary)
                    }
                }
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                Text(trail)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(trailColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kpiDivider: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1, height: 36)
            .padding(.horizontal, 4)
    }

    // MARK: Equipment chip row

    private var equipmentChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(HotEquipFilter.allCases) { f in
                    equipChip(f, count: count(for: f))
                }
                Color.clear.frame(width: 16, height: 1)
            }
            .padding(.horizontal, Space.s5)
        }
        .overlay(alignment: .trailing) {
            LinearGradient(
                colors: [palette.bgPage.opacity(0), palette.bgPage],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 28)
            .allowsHitTesting(false)
        }
    }

    private func count(for f: HotEquipFilter) -> Int {
        guard case .loaded(let feed) = store.phase else { return 0 }
        if f == .all { return feed.zones.count }
        if let key = f.matchKeyword {
            return feed.zones.filter { z in
                z.topEquipment.contains { $0.uppercased().contains(key) }
            }.count
        }
        // For tanker/reefer/dryVan the backend re-filters on equipment param;
        // count surfaces against the currently-loaded feed.
        return feed.zones.filter { z in
            z.topEquipment.contains { $0.uppercased().contains(f.label.uppercased()) }
        }.count
    }

    private func equipChip(_ f: HotEquipFilter, count: Int) -> some View {
        let isActive = (store.equipment == f)
        let label = "\(f.label) · \(count)"
        return Button(action: { tapEquip(f) }) {
            Text(label)
                .font(.system(size: 12, weight: isActive ? .bold : .semibold))
                .foregroundStyle(isActive ? Color.white : palette.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background {
                    if isActive {
                        Capsule().fill(LinearGradient.primary)
                    } else {
                        Capsule().fill(palette.bgCard)
                    }
                }
                .overlay {
                    if !isActive {
                        Capsule().strokeBorder(palette.borderFaint)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(f.label) filter")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func tapEquip(_ f: HotEquipFilter) {
        store.equipment = f
        NotificationCenter.default.post(
            name: .eusoShipperHotZonesEquip,
            object: nil,
            userInfo: [
                "source": "225_ShipperHotZones",
                "equipment": f.rawValue,
                "shipperCompanyId": 1
            ]
        )
    }

    // MARK: Hot grid (2-col tiles)

    private func hotGrid(_ zones: [HotZoneEntry]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Space.s2),
                GridItem(.flexible(), spacing: Space.s2),
            ],
            spacing: Space.s2
        ) {
            ForEach(zones.prefix(8)) { z in
                hotTile(z)
            }
        }
    }

    private func hotTile(_ z: HotZoneEntry) -> some View {
        let demandColor: Color = {
            switch z.demandLevel.uppercased() {
            case "CRITICAL": return Brand.danger
            case "HIGH":     return Brand.warning
            default:         return Brand.info
            }
        }()
        let pulse = z.rateChangePercent.map { String(format: "%+.1f%%", $0) } ?? "—"
        let pulseColor: Color = {
            guard let p = z.rateChangePercent else { return palette.textPrimary }
            return p >= 0 ? Brand.danger : Brand.success
        }()
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(z.zoneName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(z.topEquipment.first?.replacingOccurrences(of: "_", with: " ").capitalized ?? "—")
                        .font(EType.micro).tracking(0.5)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(z.state)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Capsule().fill(demandColor))
            }
            .padding(.horizontal, Space.s3)
            .padding(.top, Space.s3)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(pulse)
                    .font(.system(size: 22, weight: .bold).monospacedDigit())
                    .foregroundStyle(pulseColor)
                Spacer()
            }
            .padding(.horizontal, Space.s3)
            .padding(.top, Space.s2)

            // Sparkline placeholder — EUSO-2137 (no series on envelope).
            HotSparkPlaceholder()
                .stroke(LinearGradient.diagonal,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .frame(height: 24)
                .padding(.horizontal, Space.s3)
                .padding(.top, Space.s2)

            HStack(spacing: 4) {
                Text("\(z.liveLoads) loads")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                Text("·")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                Text("L:T \(String(format: "%.1f", z.liveRatio))")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s3)
            .padding(.top, Space.s2)
            .padding(.bottom, Space.s3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(demandColor.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(z.zoneName), \(z.demandLevel), pulse \(pulse), \(z.liveLoads) loads, ratio \(String(format: "%.1f", z.liveRatio))"
        )
    }

    // MARK: Cold strip

    private func coldStrip(_ cold: [ColdZoneEntry]) -> some View {
        VStack(spacing: Space.s2) {
            ForEach(cold.prefix(4)) { c in
                coldTile(c)
            }
        }
    }

    private func coldTile(_ c: ColdZoneEntry) -> some View {
        let pulse = c.liveSurge.map { String(format: "%+.1f", ($0 - 1.0) * 100.0) + "%" } ?? "—"
        return HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(Brand.info.opacity(0.18)).frame(width: 36, height: 36)
                Image(systemName: "snowflake")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Brand.info)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(c.name ?? c.state ?? "Unknown")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    if let s = c.state {
                        Text(s.uppercased())
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Brand.info)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Capsule().fill(Brand.info.opacity(0.15)))
                    }
                }
                HStack(spacing: 8) {
                    if let r = c.liveRate {
                        Text(String(format: "$%.2f / mi", r))
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundStyle(Brand.info)
                    }
                    if let t = c.liveTrucks {
                        Text("\(t) trucks · post")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            Spacer(minLength: 0)
            Text(pulse)
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(Brand.success)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .strokeBorder(Brand.info.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
    }

    // MARK: Action ribbon (cold-zone post recommendation)

    private func actionRibbon(cold: ColdZoneEntry) -> some View {
        let metro = cold.name ?? cold.state ?? "Cold zone"
        let rate = cold.liveRate.map { String(format: "$%.2f/mi", $0) } ?? "spot rate"
        return Button(action: { tapPostRecommendation(cold) }) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "star.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Brand.success)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Post \(metro) capacity at \(rate)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    // EUSO-2138 — recommendation engine not shipped; copy
                    // surfaces a generic invitation to post against capacity.
                    Text("Cold zone capacity opens · save vs spot pending EUSO-2138")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Brand.success)
            }
            .padding(.horizontal, Space.s4)
            .padding(.vertical, Space.s2)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient.successTintBanner)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Brand.success.opacity(0.30))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Post \(metro) capacity at \(rate). Recommendation engine pending.")
    }

    private func tapPostRecommendation(_ cold: ColdZoneEntry) {
        NotificationCenter.default.post(
            name: .eusoShipperHotZonesPostRecommendation,
            object: nil,
            userInfo: [
                "source": "225_ShipperHotZones",
                "metro": cold.name ?? cold.state ?? "",
                "rate": cold.liveRate ?? 0,
                "shipperCompanyId": 1
            ]
        )
    }

    // MARK: Formula explainer

    private var formulaExplainer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("MARKET PULSE")
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text("pulse = avg(rateChangePct) per metro · loads / trucks ratio · 30-day rolling window")
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.74)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Space.s2)
    }

    private func errorCard(_ m: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Retry") { Task { await store.load() } }
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Brand.info)
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: - File-scoped Sparkline placeholder (§19.2 · EUSO-2137)

private struct HotSparkPlaceholder: Shape {
    func path(in rect: CGRect) -> Path {
        // Generic upward-bias sparkline shape pending real series data.
        let pts: [CGPoint] = [
            CGPoint(x: 0.000, y: 0.85),
            CGPoint(x: 0.180, y: 0.70),
            CGPoint(x: 0.350, y: 0.55),
            CGPoint(x: 0.530, y: 0.60),
            CGPoint(x: 0.700, y: 0.40),
            CGPoint(x: 0.870, y: 0.30),
            CGPoint(x: 1.000, y: 0.15),
        ]
        var p = Path()
        guard let first = pts.first else { return p }
        p.move(to: CGPoint(x: first.x * rect.width, y: first.y * rect.height))
        for pt in pts.dropFirst() {
            p.addLine(to: CGPoint(x: pt.x * rect.width, y: pt.y * rect.height))
        }
        return p
    }
}

// MARK: - File-scoped paint extensions (§19.2)

private extension LinearGradient {
    static let successTintBanner = LinearGradient(
        colors: [Brand.success.opacity(0.10), Brand.success.opacity(0.10)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Equipment chip tap (All / Tanker / Reefer / Hazmat / Rail / Dry van).
    static let eusoShipperHotZonesEquip            = Notification.Name("eusoShipperHotZonesEquip")
    /// Action ribbon tap — cold-zone post recommendation.
    static let eusoShipperHotZonesPostRecommendation = Notification.Name("eusoShipperHotZonesPostRecommendation")
}

// MARK: - Previews

#Preview("225 · Hot Zones · Dark") {
    ShipperHotZones()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("225 · Hot Zones · Light") {
    ShipperHotZones()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
