//
//  570_RailDemurrageDispute.swift
//  EusoTrip — Rail Engineer · Demurrage Dispute (carrier-side dispute-filing surface).
//
//  Verbatim port of "570 Rail Demurrage Dispute.svg" (Light + Dark).
//  Action companion to watch-only 558 Rail Demurrage Watch. Charge filing surface
//  with dwell attribution, disposition pills, and createDispute CTA.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME).
//
//  Data:
//    railShipments.calculateRailDemurrage  (EXISTS railShipments.ts:597)         → charge hero
//    railDemurrageAuto.dashboard           (EXISTS railDemurrageAuto.ts:18)      → KPI summary
//    railDemurrageAuto.reportByDwellReason (EXISTS railDemurrageAuto.ts:93)      → attribution rows
//    railDemurrageAuto.createDispute       (EXISTS railDemurrageAuto.ts:78)      → File-dispute CTA
//    weather.historical {lat,lon,from,to}  (LIVE; Enterprise-gated)             → cited historical
//      weather evidence auto-attached when a dwell reason is "weather" (max gust / min vis /
//      peak condition + gov-alert overlap). Enterprise-gated → honest "available with the
//      enterprise feed" em-dash state until it returns available:true; never a fabricated report.
//

import SwiftUI

struct RailDemurrageDisputeScreen: View {
    let theme: Theme.Palette
    let railId: String

    var body: some View {
        Shell(theme: theme) { RailDemurrageDisputeBody(railId: railId) } nav: {
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

private struct DemurrageCharge570: Decodable {
    let id: String?
    let railId: String?
    let facilityName: String?
    let containerNumber: String?
    let shipper: String?
    let accruedUsd: Double?
    let daysAccrued: Int?
    let dailyRateUsd: Double?
    let contestedUsd: Double?
    let contestedDays: Int?
    let status: String?
    // Facility geo + dwell window — anchor the cited historical-weather
    // lookup. All optional: when the charge proc omits them (today, until
    // the yard geocode + placed/released window land on the wire) the
    // evidence call is honestly gated rather than fabricated.
    let facilityLat: Double?
    let facilityLon: Double?
    let placedAt: String?        // ISO8601 — dwell window start (car placed)
    let releasedAt: String?      // ISO8601 — dwell window end (released/now)
}

// MARK: - Historical weather evidence (weather.historical envelope)

/// The cited historical-weather report attached when a dwell reason is
/// "weather" — decodes `weather.historical({lat,lon,from,to})` 1:1. The
/// proc is Enterprise-gated (Tomorrow.io history tier): until the key
/// lands it returns `available:false` / nulls, so every field is optional
/// and the screen renders the honest "available with the enterprise feed"
/// state rather than inventing a max gust / min visibility / peak code.
private struct HistoricalWeatherEvidence570: Decodable {
    let available: Bool?
    /// Peak gust over the dwell window, mph (the high-profile / yard metric).
    let maxGustMph: Double?
    /// Worst (minimum) visibility over the window, miles.
    let minVisibilityMi: Double?
    /// The most-hazardous Tomorrow.io weatherCode seen + its phrase — the
    /// "peak condition" the citation leads with.
    let peakWeatherCode: Int?
    let peakCondition: String?
    /// Government bulletins that overlapped the dwell window — the
    /// gov-alert overlap that turns a weather dwell into carrier-exonerating
    /// evidence. Same row shape as weather.getAlerts / getRouteConditions
    /// advisories (eventType · severity · headline · expiresAt).
    let govAlerts: [GovAlert570]?
    let source: String?
    let computedAt: String?

    struct GovAlert570: Decodable, Identifiable {
        let eventType: String?
        let severity: String?
        let headline: String?
        let expiresAt: String?
        var id: String { (headline ?? eventType ?? "alert") + (expiresAt ?? "") }
    }

    var isAvailable: Bool { available == true }
}

private struct DemurrageDashboard570: Decodable {
    let totalAccruedUsd: Double?
    let totalContestedUsd: Double?
    let winRatePct: Double?
}

private struct DwellAttribution570: Decodable, Identifiable {
    let id: Int
    let reason: String?
    let reasonLabel: String?
    let days: Double?
    let attribution: String?
    let disposition: String?        // "contest" | "valid" | "waiver"
    let amountUsd: Double?
}

// MARK: - Body

private struct RailDemurrageDisputeBody: View {
    @Environment(\.palette) private var palette
    let railId: String

    @State private var charge: DemurrageCharge570? = nil
    @State private var dashboard: DemurrageDashboard570? = nil
    @State private var attributions: [DwellAttribution570] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var isFiling = false

    // Cited historical-weather evidence for the "weather" dwell reason.
    // nil while not yet requested / not applicable; non-nil holds the
    // envelope (which is itself honest: available:false until enterprise).
    @State private var weatherEvidence: HistoricalWeatherEvidence570? = nil
    @State private var loadingEvidence = false

    // MARK: Derived

    private var accruedLabel: String  { charge?.accruedUsd.map { "$\(Int($0))" } ?? dashboard?.totalAccruedUsd.map { "$\(Int($0))" } ?? "-" }
    private var contestedLabel: String {
        let amt = charge?.contestedUsd ?? attributions.filter { contestDisp($0.disposition) }.compactMap { $0.amountUsd }.reduce(0, +)
        return amt > 0 ? "$\(Int(amt))" : "-"
    }
    private var contestedAmount: Double {
        charge?.contestedUsd ?? attributions.filter { contestDisp($0.disposition) }.compactMap { $0.amountUsd }.reduce(0, +)
    }
    private var winRateLabel: String { dashboard?.winRatePct.map { "\(Int($0))%" } ?? "-" }
    private var disputeIdCaption: String { charge?.id ?? "DEM--" }

    private func contestDisp(_ d: String?) -> Bool { (d ?? "").lowercased() == "contest" }

    /// True when a dwell-attribution row attributes dwell to weather — the
    /// trigger to fetch + attach the cited historical-weather report.
    private func isWeatherReason(_ r: String?) -> Bool {
        (r ?? "").lowercased().contains("weather")
    }

    /// The weather dwell row, when one exists (drives the evidence section
    /// + the contestable amount the citation backs).
    private var weatherDwellRow: DwellAttribution570? {
        attributions.first { isWeatherReason($0.reason) }
    }

    /// "May 21 – May 23" — the dwell window the citation covers, from the
    /// charge's placed/released ISO stamps. nil when the window is absent.
    private var dwellWindowLabel: String? {
        let iso = ISO8601DateFormatter()
        guard let from = charge?.placedAt.flatMap(iso.date(from:)) else { return nil }
        let to = charge?.releasedAt.flatMap(iso.date(from:)) ?? Date()
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("MMM d")
        return "\(f.string(from: from)) – \(f.string(from: to))"
    }

    private var chargeContextSub: String {
        let days = charge?.daysAccrued ?? 0
        let rate = charge?.dailyRateUsd.map { "@$\(Int($0))" } ?? ""
        let container = charge?.containerNumber ?? "-"
        let shipper = charge?.shipper ?? "-"
        return "\(container) · \(shipper)\(days > 0 || !rate.isEmpty ? " · \(days) days \(rate)" : "")"
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading dispute…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    kpiStrip
                    attributionList
                    if weatherDwellRow != nil { weatherEvidenceSection }
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
                    Text("RAIL ENGINEER · DEMURRAGE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text(disputeIdCaption)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Demurrage dispute")
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
                Text((charge?.status ?? "CONTESTABLE").uppercased())
                    .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                    .foregroundStyle(Brand.warning)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.warning.opacity(0.16)))
                Text(charge?.facilityName ?? "-")
                    .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(palette.textPrimary.opacity(0.06)))
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(accruedLabel)
                        .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    let days = charge?.daysAccrued ?? 0
                    let rate = charge?.dailyRateUsd.map { " · \(days) days @ $\(Int($0))" } ?? ""
                    Text("accrued\(rate)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text(chargeContextSub)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("CONTESTED")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(contestedLabel)
                        .font(.system(size: 22, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(Brand.danger)
                    Text("\(charge?.contestedDays ?? 0) days")
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
            MetricTile(label: "ACCRUED",   value: accruedLabel)
            MetricTile(label: "CONTESTED", value: contestedLabel, gradientNumeral: true)
            MetricTile(label: "WIN RATE",  value: winRateLabel, accent: Brand.success)
        }
    }

    // MARK: - Attribution list

    private var attributionList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("DWELL ATTRIBUTION")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("reportByDwellReason")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if attributions.isEmpty {
                EusoEmptyState(
                    systemImage: "doc.text.magnifyingglass",
                    title: "No dwell attribution",
                    subtitle: "Dwell reason breakdown will appear here."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(attributions.enumerated()), id: \.element.id) { idx, attr in
                        attributionRow(attr)
                        if idx < attributions.count - 1 {
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

    /// SF glyph for the non-weather dwell reasons. The "weather" reason is
    /// NOT handled here — it renders the bespoke `WeatherIcons` glyph in
    /// `attributionRow` (keyed off the cited report's peak weatherCode), per
    /// the weather-bespoke doctrine — so this never returns a weather symbol.
    private func reasonIcon(_ reason: String?) -> String {
        switch (reason ?? "").lowercased() {
        case let r where r.contains("congestion") || r.contains("ramp"): return "chart.line.uptrend.xyaxis"
        case let r where r.contains("consignee") || r.contains("building"): return "building.2"
        case let r where r.contains("gate") || r.contains("outage"): return "exclamationmark.circle"
        default: return "clock"
        }
    }

    private func reasonChipColor(_ reason: String?, disposition: String?) -> Color {
        let disp = (disposition ?? "").lowercased()
        if disp == "waiver" { return Brand.info }
        if disp == "valid"  { return Color(red: 0.38, green: 0.49, blue: 0.55) }
        let r = (reason ?? "").lowercased()
        if r.contains("weather") { return Brand.info }
        return Brand.warning
    }

    private func dispositionChipColor(_ d: String?) -> Color {
        switch (d ?? "").lowercased() {
        case "contest": return Brand.warning
        case "waiver":  return Brand.success
        default:        return Color(red: 0.38, green: 0.49, blue: 0.55)
        }
    }
    private func dispositionPillLabel(_ d: String?) -> String {
        (d ?? "VALID").uppercased()
    }

    private func attributionRow(_ attr: DwellAttribution570) -> some View {
        let reason     = attr.reason ?? ""
        let disp       = attr.disposition
        let chipColor  = reasonChipColor(reason, disposition: disp)
        let pillColor  = dispositionChipColor(disp)
        let label      = attr.reasonLabel ?? reason.replacingOccurrences(of: "_", with: " ").capitalized
        let daysStr    = attr.days.map { $0 == Double(Int($0)) ? "\(Int($0)) day\(Int($0) == 1 ? "" : "s")" : "\($0) days" } ?? "-"
        let attribStr  = attr.attribution ?? "-"
        let amountStr  = attr.amountUsd.map { $0 == 0 ? "$0" : "$\(Int($0))" } ?? "-"

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(chipColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                if isWeatherReason(reason) {
                    // Bespoke weather glyph — keyed off the cited report's
                    // peak weatherCode when it has resolved, else the neutral
                    // cloud (WeatherIcons never guesses a condition).
                    WeatherIcons.symbolView(
                        for: weatherEvidence?.peakWeatherCode ?? 0, size: 22
                    )
                } else {
                    Image(systemName: reasonIcon(reason))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(chipColor)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("\(daysStr) · \(attribStr)")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(dispositionPillLabel(disp))
                    .font(.system(size: 10, weight: .bold)).kerning(0.4)
                    .foregroundStyle(pillColor)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(pillColor.opacity(0.14)))
                Text(amountStr)
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(attr.amountUsd == 0 ? palette.textTertiary : palette.textPrimary)
            }
        }
        .padding(16)
    }

    // MARK: - Weather evidence (cited historical report)

    /// The §"weather dwell → cited historical evidence" surface. Renders
    /// when a dwell row attributes time to weather. Honest by construction:
    /// while `weather.historical` is Enterprise-gated it returns
    /// `available:false`/nulls, so we show the "available with the
    /// enterprise feed" em-dash state — never a fabricated max gust / vis /
    /// peak condition. When the key lands and `available:true` arrives, the
    /// same view fills with the cited readings + the gov-alert overlap.
    private var weatherEvidenceSection: some View {
        let ev = weatherEvidence
        let resolved = ev?.isAvailable == true

        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("WEATHER EVIDENCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("weather.historical")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }

            VStack(alignment: .leading, spacing: 12) {
                // Header row: glyph + title + auto-attach status pill.
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Brand.info.opacity(0.14))
                            .frame(width: 40, height: 40)
                        WeatherIcons.symbolView(for: ev?.peakWeatherCode ?? 0, size: 24)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Cited historical weather")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text(dwellWindowLabel.map { "\(charge?.facilityName ?? "Facility") · \($0)" }
                             ?? (charge?.facilityName ?? "Facility dwell window"))
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .tracking(0.3)
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    let pillText  = loadingEvidence ? "FETCHING" : (resolved ? "ATTACHED" : "ENTERPRISE")
                    let pillColor = loadingEvidence ? palette.textTertiary : (resolved ? Brand.success : Brand.info)
                    Text(pillText)
                        .font(.system(size: 10, weight: .bold)).kerning(0.4)
                        .foregroundStyle(pillColor)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(pillColor.opacity(0.14)))
                }

                Divider().overlay(palette.borderFaint)

                if resolved {
                    // ── Cited readings: max gust / min vis / peak condition ──
                    HStack(spacing: 18) {
                        evidenceMetric(.wind, "MAX GUST",
                                       ev?.maxGustMph.map { "\(Int($0.rounded())) mph" } ?? "—")
                        evidenceMetric(.eye, "MIN VIS",
                                       ev?.minVisibilityMi.map {
                                           "\($0.formatted(.number.precision(.fractionLength(0...1)))) mi"
                                       } ?? "—")
                        evidenceMetric(.precip, "PEAK COND",
                                       ev?.peakCondition ?? "—")
                    }

                    // ── Government bulletin overlap ──
                    if let alerts = ev?.govAlerts, !alerts.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(alerts) { govAlertRow($0) }
                        }
                    }

                    Text(citationFooter(ev))
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                } else {
                    // ── Honest Enterprise-gated empty state ──
                    HStack(alignment: .top, spacing: 10) {
                        WeatherIcons.utility(.alert, size: 16, tint: Brand.info)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Historical weather evidence available with the enterprise feed")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.textPrimary)
                            Text("Once the Tomorrow.io history tier is licensed, the max gust, minimum visibility, peak condition and any overlapping government bulletins for this dwell window auto-attach as a cited exhibit.")
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                }
            }
            .padding(16)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(resolved ? Brand.info.opacity(0.45) : palette.borderFaint)
            )
        }
    }

    /// One cited reading tile (glyph + label + live value or "—").
    private func evidenceMetric(_ glyph: WeatherIcons.Utility, _ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                WeatherIcons.utility(glyph, size: 13, tint: palette.textTertiary)
                Text(label)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            Text(value)
                .font(.system(size: 15, weight: .heavy)).monospacedDigit()
                .foregroundStyle(value == "—" ? palette.textTertiary : palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One overlapping government bulletin row inside the citation.
    private func govAlertRow(_ a: HistoricalWeatherEvidence570.GovAlert570) -> some View {
        let sev = WeatherSnapshot.AlertSeverity(capString: a.severity)
        let title = a.headline ?? a.eventType ?? "Government bulletin"
        return HStack(spacing: 8) {
            WeatherIcons.utility(.alert, size: 13, tint: sev.color)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Spacer()
            Text(sev.label)
                .font(.system(size: 9, weight: .heavy)).kerning(0.4)
                .foregroundStyle(sev.color)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(sev.color.opacity(0.14)))
        }
    }

    /// The provenance footer — "Tomorrow.io history · computed 2m ago".
    /// Each clause omitted honestly when its field is absent.
    private func citationFooter(_ ev: HistoricalWeatherEvidence570?) -> String {
        var parts: [String] = []
        if let s = ev?.source, !s.isEmpty { parts.append(s) }
        if let iso = ev?.computedAt, let d = ISO8601DateFormatter().date(from: iso) {
            let secs = max(0, Int(Date().timeIntervalSince(d)))
            let ago = secs < 60 ? "just now" : (secs < 3600 ? "\(secs/60)m ago" : "\(secs/3600)h ago")
            parts.append("computed \(ago)")
        }
        parts.append("attached as dispute exhibit")
        return parts.joined(separator: " · ")
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        let cLabel = contestedAmount > 0 ? "File dispute · $\(Int(contestedAmount))" : "File dispute"
        return HStack(spacing: Space.s2) {
            CTAButton(title: cLabel, action: { Task { await fileDispute() } }, leadingIcon: "list.bullet.rectangle", isLoading: isFiling)
            Button {} label: {
                Text("Save draft")
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
        struct RailIn: Encodable { let railId: String }
        struct EmptyIn: Encodable {}
        do {
            async let charge: DemurrageCharge570 = EusoTripAPI.shared.query(
                "railShipments.calculateRailDemurrage", input: RailIn(railId: railId))
            async let dash: DemurrageDashboard570 = EusoTripAPI.shared.query(
                "railDemurrageAuto.dashboard", input: EmptyIn())
            async let attrs: [DwellAttribution570] = EusoTripAPI.shared.query(
                "railDemurrageAuto.reportByDwellReason", input: RailIn(railId: railId))
            let (c, d, a) = try await (charge, dash, attrs)
            self.charge       = c
            self.dashboard    = d
            self.attributions = a
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false

        // A weather dwell reason → fetch + auto-attach the cited historical
        // weather report. Best-effort: a miss must never fail the dispute
        // surface (the section degrades to its honest Enterprise state).
        if weatherDwellRow != nil { await loadWeatherEvidence() }
    }

    /// Pull `weather.historical({lat,lon,from,to})` for the facility + the
    /// dwell window and stash the envelope as cited evidence. The proc is
    /// Enterprise-gated, so today it returns `available:false`/nulls and the
    /// section shows the honest "available with the enterprise feed" state.
    /// Never fabricates: when the facility geo or window is absent we still
    /// call with what the charge supplies and bind whatever the server
    /// honestly returns.
    private func loadWeatherEvidence() async {
        loadingEvidence = true
        defer { loadingEvidence = false }
        // The Tomorrow.io history product is anchored on lat/lon + a time
        // window. Encode null-as-absent so the server can gate honestly when
        // the facility geocode or placed/released stamps haven't landed.
        struct HistoricalIn: Encodable {
            let lat: Double?
            let lon: Double?
            let from: String?
            let to: String?
        }
        let input = HistoricalIn(
            lat: charge?.facilityLat,
            lon: charge?.facilityLon,
            from: charge?.placedAt,
            to: charge?.releasedAt
        )
        do {
            let ev: HistoricalWeatherEvidence570 = try await EusoTripAPI.shared.query(
                "weather.historical", input: input)
            self.weatherEvidence = ev
        } catch {
            // Keep the honest empty section; never blank or invent a report.
            self.weatherEvidence = nil
        }
    }

    private func fileDispute() async {
        isFiling = true
        struct DisputeIn: Encodable { let railId: String; let contestedUsd: Double; let reason: String }
        struct DisputeOut: Decodable {}
        do {
            let _: DisputeOut = try await EusoTripAPI.shared.query(
                "railDemurrageAuto.createDispute",
                input: DisputeIn(railId: railId, contestedUsd: contestedAmount, reason: "carrier-attributable dwell"))
            await load()
        } catch { /* keep current state */ }
        isFiling = false
    }
}

#Preview("570 · Rail Demurrage Dispute · Night") { RailDemurrageDisputeScreen(theme: Theme.dark, railId: "RAIL-260523-7C3A0B12D4").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("570 · Rail Demurrage Dispute · Light") { RailDemurrageDisputeScreen(theme: Theme.light, railId: "RAIL-260523-7C3A0B12D4").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
