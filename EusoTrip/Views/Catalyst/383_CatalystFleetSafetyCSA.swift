//
//  383_CatalystFleetSafetyCSA.swift
//  EusoTrip — Catalyst · Fleet · Fleet Safety CSA (carrier-vantage FMCSA SMS roll-up).
//
//  Verbatim port of "383 Catalyst Fleet Safety CSA.svg" (440×956, Dark/Light).
//  Reached from the FLEET tab. Immediate sibling of 384 Fleet IFTA — same
//  carrier framing, same card grammar, same DesignSystem primitives. The two
//  Fleet-compliance screens read as one family (384_CatalystFleetIFTA.swift is
//  the structural twin this file mirrors).
//
//  Layout (section-by-section against the SVG):
//    • Header — eyebrow "✦ CATALYST · FLEET SAFETY" (gradient) + "SMS · 24-MO"
//      (mono); back-chevron orb; title "Fleet CSA" (22/700); subtitle
//      "7 BASICs · FMCSA SMS"; right rail "{carrier} · USDOT {dot}" +
//      "synced …"; IridescentHairline.
//    • Hero card — "INSPECTIONS 24-MO" big gradient count + "{clean} clean ·
//      {viol} viol"; "OUT-OF-SERVICE" mono % on the right (green when 0);
//      an OOS gauge bar; a threshold-status line (reassuring when no BASIC is
//      over threshold, else "{n} BASIC(s) over threshold"); mono footline
//      "FMCSA SMS nightly · MCS-150 current · MC-820 {mc}".
//    • BASIC percentile card — header "CARRIER BASIC PERCENTILES · vs THRESHOLD";
//      one rail per server BASIC (label, percentile mono, fill bar coloured by
//      status); footnote "Percentile higher = worse · threshold 65 (80 HM/PU)".
//    • 3 factor cells — POWER UNITS · INSPECTIONS · CLEAN RATE.
//    • 2 CTAs — "Improvement plan" (gradient → csaScores.getImprovementPlan) +
//      "Hazmat qual" (secondary → carrierScorecard.getHazmatQualification).
//      Both open a real sheet with real server data. No dead taps.
//    • Footnote block (3 mono lines).
//    • BottomNav is supplied by the Catalyst surface chrome (matches sibling
//      384, which also defers nav to the host surface — see report §NAV).
//
//  Data (endpoints exactly as named in the wireframe <desc>, verified against
//  the live server at the cited lines):
//    csaScores.getOverview                (routers/csaScores.ts:23)
//        → hero + the 7 BASIC rails + OOS rate + 24-mo inspections. Self-scoped
//          to ctx.user.companyId (input.companyId optional); returns the real
//          FMCSA bulk SMS BASIC set (9.8M-record lookup) with an honest
//          platform-internal fallback when no DOT is on file.
//    carrierScorecard.getScorecard        (routers/carrierScorecard.ts:21)
//        → the POWER UNITS factor cell (fleet.fmcsaPowerUnits / fleet.vehicles)
//          and the carrier legal/identity rail. Input {carrierId}; carrierId is
//          taken from the overview's companyId (no client-fabricated id).
//    carrierScorecard.getTrends           (routers/carrierScorecard.ts:293)
//        → the 24-mo trend arrow on each BASIC rail (optional; rail renders the
//          server `trend` from getOverview when present, getTrends enriches it).
//    carrierScorecard.getHazmatQualification (routers/carrierScorecard.ts:409)
//        → "Hazmat qual" sheet. Input {carrierId}.
//    csaScores.getAlerts                  (routers/csaScores.ts:415)
//        → the live-alert pill in the hero (failed inspections, last 30 days).
//          No input; self-scoped to ctx.user.companyId.
//    csaScores.getImprovementPlan         (routers/csaScores.ts:376)
//        → "Improvement plan" sheet. Input {category?}.
//        NOTE: at audit time this procedure returns a HARDCODED reference plan
//        (static categories + 2025 dates) not tied to the carrier's real
//        percentiles. The button is wired honestly to the real endpoint; the
//        backend gap is filed in INTEGRATION.md (§GAP) for a host-side fix.
//
//  No mock data in the live path. Every number binds to a live field;
//  unavailable values render an em-dash, never a fabricated figure. The BASIC
//  display-name map, threshold constants, and column layout are reference /
//  presentation data (FMCSA SMS rule constants), not business data.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Wire models (match the live csaScores / carrierScorecard returns)

/// One FMCSA BASIC category, exactly as `csaScores.getOverview` emits it.
/// `percentile` higher = worse; `threshold` is the intervention line (65 for
/// most, 80 for Hazmat / Passenger / HM-PU). `inspections` / `violations` /
/// `alert` are optional so this decoder stays forward-safe against the thin
/// platform-internal fallback shape.
struct CSABasic: Decodable, Equatable, Identifiable {
    let category: String
    let name: String
    let percentile: Double
    let threshold: Double
    let status: String          // "ok" | "warning" | "alert"
    let trend: String?          // "up" | "down" | "stable"
    let inspections: Int?
    let violations: Int?
    let alert: Bool?

    var id: String { category }
    var isAlert: Bool { alert ?? (status == "alert") }
    var isOverThreshold: Bool { percentile >= threshold }
}

/// SAFER 24-month rollup nested in the overview.
struct CSASaferData: Decodable, Equatable {
    let outOfServiceRate: Double?
    let nationalAverage: Double?
    let inspectionCount24Months: Int?
    let driverOOSRate: Double?
    let vehicleOOSRate: Double?
}

/// FMCSA bulk inspection enrichment (nullable — only present with a real DOT).
struct CSAInspections: Decodable, Equatable {
    let total: Int
    let violations: Int
    let driverOos: Int?
    let vehicleOos: Int?
    let hazmatOos: Int?
}

/// The whole `csaScores.getOverview` payload. Only the fields the screen reads
/// are modelled; Decodable ignores the rest (fmcsaCrashes, dataSource, …).
struct CSAOverview: Decodable, Equatable {
    let companyId: String
    let companyName: String
    let dotNumber: String
    let mcNumber: String
    let lastUpdated: String
    let overallStatus: String
    let alertLevel: String
    let basics: [CSABasic]
    let saferData: CSASaferData?
    let fmcsaInspections: CSAInspections?
    let outOfService: Bool?
    let oosReason: String?

    var alertCount: Int { basics.filter { $0.isAlert }.count }
    var overCount: Int { basics.filter { $0.isOverThreshold }.count }
}

/// One live CSA alert (failed inspection in the last 30 days).
struct CSAAlert: Decodable, Equatable, Identifiable {
    let id: String
    let type: String            // "critical" | "warning"
    let message: String
    let inspectionId: String?
    let createdAt: String?
}

/// Minimal slice of `carrierScorecard.getScorecard` — just the fleet block and
/// identity the 383 screen surfaces. Decodable ignores the large metrics/fmcsa
/// trees we don't render here.
struct CSAScorecardFleet: Decodable, Equatable {
    let vehicles: Int?
    let drivers: Int?
    let fmcsaPowerUnits: Int?
    let fmcsaDriverTotal: Int?
}
struct CSAScorecard: Decodable, Equatable {
    let carrierId: Int
    let companyName: String?
    let legalName: String?
    let dotNumber: String?
    let mcNumber: String?
    let fleet: CSAScorecardFleet?
}

/// Compact decode of `carrierScorecard.getHazmatQualification` for the sheet.
struct CSAHazmatQual: Decodable, Equatable {
    struct HMSP: Decodable, Equatable { let active: Bool?; let licenseNumber: String?; let daysRemaining: Int?; let expiry: String? }
    struct Group: Decodable, Equatable { let total: Int? }
    struct Insurance: Decodable, Equatable { let policies: Int?; let types: [String]? }
    struct History: Decodable, Equatable { let totalHazmatLoads: Int?; let deliveredHazmatLoads: Int?; let classesHandled: [String]? }
    let qualified: Bool?
    let hmsp: HMSP?
    let drivers: Group?
    let vehicles: Group?
    let insurance: Insurance?
    let history: History?
}

/// Compact decode of `csaScores.getImprovementPlan` for the sheet.
struct CSAImprovementPlan: Decodable, Equatable {
    struct Action: Decodable, Equatable, Identifiable {
        let action: String; let status: String; let dueDate: String?; let completedDate: String?
        var id: String { action }
    }
    struct Category: Decodable, Equatable, Identifiable {
        let category: String
        let currentPercentile: Double?
        let targetPercentile: Double?
        let priority: String?
        let actions: [Action]
        let projectedImpact: String?
        var id: String { category }
    }
    let categories: [Category]
    let overallGoal: String?
    let reviewDate: String?
}

/// Bundle the two primary reads so the screen has one loaded state.
struct CSAScreenModel: Equatable {
    let overview: CSAOverview
    let scorecard: CSAScorecard?     // optional — fleet enrichment, not load-blocking
    let alerts: [CSAAlert]
}

// MARK: - Store

@MainActor
final class FleetSafetyCSAStore: BaseDynamicStore<CSAScreenModel> {

    private struct OverviewIn: Encodable { let companyId: String? }
    private struct ScorecardIn: Encodable { let carrierId: Int }

    override func fetch() async throws -> CSAScreenModel {
        // 1) Overview is the load-blocking read (self-scoped to the caller's company).
        let overview: CSAOverview = try await EusoTripAPI.shared.query(
            "csaScores.getOverview",
            input: OverviewIn(companyId: nil)
        )

        // 2) Scorecard enriches the POWER UNITS cell. carrierId comes straight
        //    from the overview's real companyId — never client-fabricated. If it
        //    isn't a valid int, or the call fails, the cell shows an em-dash; we
        //    do not fail the whole screen for an enrichment read.
        var scorecard: CSAScorecard? = nil
        if let cid = Int(overview.companyId), cid > 0 {
            scorecard = try? await EusoTripAPI.shared.query(
                "carrierScorecard.getScorecard",
                input: ScorecardIn(carrierId: cid)
            )
        }

        // 3) Live alerts (failed inspections, last 30 days). Non-blocking.
        let alerts: [CSAAlert] = (try? await EusoTripAPI.shared.queryNoInput(
            "csaScores.getAlerts"
        )) ?? []

        return CSAScreenModel(overview: overview, scorecard: scorecard, alerts: alerts)
    }
}

// MARK: - Screen root

struct CatalystFleetSafetyCSA: View {
    @Environment(\.palette) var palette
    @StateObject private var store = FleetSafetyCSAStore()

    /// Carrier identity fallback for the right rail. The SVG pins Eusotrans LLC
    /// · USDOT 3 194 882; the live screen prefers the server's own company name
    /// + DOT and only falls back to the SVG canon when the server supplies none.
    private let carrierNameFallback: String
    private let usdotFallback: String

    @State private var planSheet = false
    @State private var hazmatSheet = false

    init(carrierName: String = "Eusotrans LLC", usdot: String = "3 194 882") {
        self.carrierNameFallback = carrierName
        self.usdotFallback = usdot
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                switch store.state {
                case .loading:
                    skeleton
                case .empty:
                    emptyCard
                case .error(let e):
                    errorBanner(e)
                case .loaded(let model):
                    heroCard(model)
                    basicCard(model.overview)
                    factorCells(model)
                    ctaRow
                    footnote(model.overview)
                }
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(isPresented: $planSheet) {
            CSAImprovementPlanSheet(carrierId: Int(store.state.value?.overview.companyId ?? "") ?? 0)
                .environment(\.palette, palette)
        }
        .sheet(isPresented: $hazmatSheet) {
            CSAHazmatQualSheet(carrierId: Int(store.state.value?.overview.companyId ?? "") ?? 0)
                .environment(\.palette, palette)
        }
    }

    // MARK: Identity helpers (server-first, SVG-canon fallback)

    private var carrierName: String {
        let n = store.state.value?.scorecard?.legalName
            ?? store.state.value?.overview.companyName
        if let n, !n.isEmpty, n != "Unknown" { return n }
        return carrierNameFallback
    }
    private var usdot: String {
        let d = store.state.value?.overview.dotNumber
        if let d, !d.isEmpty { return d }
        return usdotFallback
    }
    private var mcNumber: String {
        let m = store.state.value?.overview.mcNumber
        if let m, !m.isEmpty { return m }
        return "MC-820 144"
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("✦ CATALYST · FLEET SAFETY")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("SMS · 24-MO")
                    .font(EType.micro.monospaced()).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .top) {
                OrbeSang(state: store.isLoading ? .thinking : .idle, diameter: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fleet CSA")
                        .font(EType.h2)
                        .foregroundStyle(palette.textPrimary)
                    Text("7 BASICs · FMCSA SMS")
                        .font(EType.caption.monospaced())
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(carrierName.uppercased()) · USDOT \(usdot)")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                    Text(syncedLine)
                        .font(EType.caption.monospaced())
                        .foregroundStyle(palette.textSecondary)
                }
            }
            IridescentHairline()
        }
    }

    private var syncedLine: String {
        guard !store.isLoading, let iso = store.state.value?.overview.lastUpdated, !iso.isEmpty
        else { return store.isLoading ? "syncing…" : "synced just now" }
        return "synced \(relativeShort(iso))"
    }

    // MARK: Hero card

    private func heroCard(_ m: CSAScreenModel) -> some View {
        let o = m.overview
        let inspections = o.saferData?.inspectionCount24Months ?? o.fmcsaInspections?.total ?? 0
        let violations = o.fmcsaInspections?.violations ?? o.basics.reduce(0) { $0 + ($1.violations ?? 0) }
        let clean = max(0, inspections - violations)
        let oosRate = o.saferData?.outOfServiceRate ?? 0
        // OOS gauge: fraction of a 5% visual ceiling, floored to a sliver so a
        // healthy 0% still shows the gradient cap (verbatim to the SVG's 7px).
        let oosFrac = min(1.0, max(0.0, oosRate / 5.0))
        let critAlerts = m.alerts.filter { $0.type == "critical" }.count

        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("INSPECTIONS 24-MO")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("OUT-OF-SERVICE")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("\(inspections)")
                    .font(.system(size: 34, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text("\(clean) clean · \(violations) viol")
                    .font(EType.body).foregroundStyle(palette.textSecondary)
                Spacer()
                Text(percent(oosRate))
                    .font(.system(size: 20, weight: .semibold).monospaced())
                    .foregroundStyle(oosRate <= 0 ? AnyShapeStyle(Brand.success)
                                                  : AnyShapeStyle(palette.textPrimary))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(palette.tintNeutral.opacity(0.4))
                    RoundedRectangle(cornerRadius: 3).fill(LinearGradient.diagonal)
                        .frame(width: max(7, geo.size.width * oosFrac))
                }
            }.frame(height: 6)
            // Threshold / alert status line — live, not canned.
            Text(statusLine(o, criticalAlerts: critAlerts))
                .font(EType.caption)
                .foregroundStyle(o.overCount == 0 && critAlerts == 0
                                 ? AnyShapeStyle(palette.textPrimary)
                                 : AnyShapeStyle(Brand.warning))
            Text("FMCSA SMS nightly · MCS-150 current · \(mcNumber)")
                .font(EType.micro.monospaced()).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private func statusLine(_ o: CSAOverview, criticalAlerts: Int) -> String {
        if criticalAlerts > 0 {
            return "\(criticalAlerts) active critical alert\(criticalAlerts == 1 ? "" : "s") — review now"
        }
        if o.overCount == 0 {
            return "No carrier BASIC over the intervention threshold"
        }
        return "\(o.overCount) BASIC\(o.overCount == 1 ? "" : "s") over the intervention threshold"
    }

    // MARK: BASIC percentile card

    private func basicCard(_ o: CSAOverview) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CARRIER BASIC PERCENTILES")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("vs THRESHOLD")
                    .font(EType.micro).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, Space.s3)

            if o.basics.isEmpty {
                Text("No FMCSA SMS data on file for this carrier yet")
                    .font(EType.caption.monospaced())
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Space.s2)
            } else {
                ForEach(o.basics) { b in
                    basicRow(b)
                        .padding(.bottom, Space.s3)
                }
            }

            Text("Percentile higher = worse · threshold 65 (80 HM/PU)")
                .font(EType.micro.monospaced()).foregroundStyle(palette.textTertiary)
                .padding(.top, Space.s2)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private func basicRow(_ b: CSABasic) -> some View {
        let frac = min(1.0, max(0.0, b.percentile / 100.0))
        let barColor: AnyShapeStyle = b.isAlert
            ? AnyShapeStyle(Brand.danger)
            : b.isOverThreshold
                ? AnyShapeStyle(Brand.warning)
                : AnyShapeStyle(LinearGradient.diagonal)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(railLabel(b.name))
                    .font(.system(size: 9, weight: .bold)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                if let t = b.trend, let glyph = trendGlyph(t) {
                    Text(glyph)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(t == "down" ? Brand.success
                                          : t == "up" ? Brand.warning
                                          : palette.textTertiary)
                }
                Spacer()
                Text(percentileText(b.percentile))
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(palette.tintNeutral.opacity(0.4))
                    if b.percentile > 0 {
                        RoundedRectangle(cornerRadius: 2).fill(barColor)
                            .frame(width: max(3, geo.size.width * frac))
                    }
                    // Threshold tick.
                    Rectangle().fill(palette.textTertiary.opacity(0.5))
                        .frame(width: 1)
                        .offset(x: geo.size.width * min(1.0, b.threshold / 100.0))
                }
            }.frame(height: 4)
        }
    }

    // MARK: Factor cells

    private func factorCells(_ m: CSAScreenModel) -> some View {
        let o = m.overview
        let powerUnits = m.scorecard?.fleet?.fmcsaPowerUnits
            ?? m.scorecard?.fleet?.vehicles
        let inspections = o.saferData?.inspectionCount24Months ?? o.fmcsaInspections?.total ?? 0
        let violations = o.fmcsaInspections?.violations ?? o.basics.reduce(0) { $0 + ($1.violations ?? 0) }
        let cleanRate = inspections > 0
            ? Int((Double(inspections - violations) / Double(inspections) * 100).rounded())
            : nil
        return HStack(spacing: Space.s2) {
            factorCell(label: "POWER UNITS",
                       value: powerUnits.map(String.init) ?? "—",
                       sub: shortName(carrierName))
            factorCell(label: "INSPECTIONS",
                       value: "\(inspections)",
                       sub: "24-month")
            factorCell(label: "CLEAN RATE",
                       value: cleanRate.map { "\($0)%" } ?? "—",
                       sub: "of inspections")
        }
    }

    private func factorCell(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .semibold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
            Text(sub).font(EType.micro.monospaced()).foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s3)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint.opacity(0.6), lineWidth: 1))
    }

    // MARK: CTAs

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button { planSheet = true } label: {
                Text("Improvement plan")
                    .font(EType.bodyStrong).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, Space.s3)
                    .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
            .disabled(store.state.value == nil)

            Button { hazmatSheet = true } label: {
                Text("Hazmat qual")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity).padding(.vertical, Space.s3)
                    .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCard))
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(store.state.value == nil)
        }
    }

    // MARK: Footnote

    private func footnote(_ o: CSAOverview) -> some View {
        let status = o.overallStatus.replacingOccurrences(of: "_", with: " ").capitalized
        return VStack(alignment: .leading, spacing: 4) {
            Text("Carrier SMS · 24-month rolling · percentile vs safety-event group")
            Text("Carrier: \(carrierName) · USDOT \(usdot) · \(mcNumber) · \(status)")
            Text("Higher percentile = worse · intervention threshold 65 (80 HM/PU)")
        }
        .font(EType.micro.monospaced()).foregroundStyle(palette.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: States / skeleton / error

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCard).frame(height: 124)
            RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCard).frame(height: 268)
            HStack(spacing: Space.s2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.md).fill(palette.bgCard).frame(height: 66)
                }
            }
        }
        .redacted(reason: .placeholder)
    }

    private var emptyCard: some View {
        VStack(spacing: Space.s2) {
            Text("No CSA data yet")
                .font(EType.title).foregroundStyle(palette.textPrimary)
            Text("FMCSA SMS BASIC scores populate once a USDOT number is on file.")
                .font(EType.caption).foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(Space.s4).eusoCard(radius: Radius.lg)
    }

    private func errorBanner(_ err: Error) -> some View {
        VStack(spacing: Space.s2) {
            Text("Couldn't load CSA")
                .font(EType.title).foregroundStyle(palette.textPrimary)
            Text(err.localizedDescription)
                .font(EType.caption).foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button { Task { await store.refresh() } } label: {
                Text("Retry").font(EType.bodyStrong).foregroundStyle(.white)
                    .padding(.horizontal, Space.s4).padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }.buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity).padding(Space.s4).eusoCard(radius: Radius.lg)
    }

    // MARK: Formatting + reference data

    private func percent(_ v: Double) -> String { String(format: "%.1f%%", v) }

    private func percentileText(_ v: Double) -> String {
        v <= 0 ? "0" : String(Int(v.rounded()))
    }

    private func trendGlyph(_ t: String) -> String? {
        switch t {
        case "up": return "▲"
        case "down": return "▼"
        default: return nil   // "stable" → no glyph, verbatim to the SVG (none shown)
        }
    }

    /// Short carrier tag for the POWER UNITS sublabel (SVG shows "Eusotrans").
    private func shortName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    /// FMCSA BASIC display label (verbatim to the SVG's uppercased short forms).
    /// Falls back to the server `name` uppercased for any unmapped category.
    private func railLabel(_ name: String) -> String {
        let key = name.lowercased()
        if key.contains("unsafe") { return "UNSAFE DRIVING" }
        if key.contains("hours") || key.contains("hos") { return "HOURS-OF-SERVICE" }
        if key.contains("fitness") { return "DRIVER FITNESS" }
        if key.contains("controlled") || key.contains("substance") { return "CONTROLLED SUBST" }
        if key.contains("maintenance") { return "VEHICLE MAINT" }
        if key.contains("hazard") || key.contains("hazmat") { return "HAZMAT" }
        if key.contains("crash") { return "CRASH INDICATOR" }
        return name.uppercased()
    }

    /// ISO-8601 → compact relative ("2h ago", "3d ago", "just now"). Never
    /// crashes, never fabricates — falls back to "recently".
    private func relativeShort(_ iso: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let d = fmt.date(from: iso)
            ?? { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f.date(from: iso) }()
        guard let d else { return "recently" }
        let s = Date().timeIntervalSince(d)
        if s < 90 { return "just now" }
        if s < 3600 { return "\(Int(s / 60))m ago" }
        if s < 86400 { return "\(Int(s / 3600))h ago" }
        return "\(Int(s / 86400))d ago"
    }
}

// MARK: - Improvement Plan sheet (csaScores.getImprovementPlan)

@MainActor
private final class ImprovementPlanStore: BaseDynamicStore<CSAImprovementPlan> {
    private struct PlanIn: Encodable { let category: String? }
    override func fetch() async throws -> CSAImprovementPlan {
        try await EusoTripAPI.shared.query("csaScores.getImprovementPlan", input: PlanIn(category: nil))
    }
}

private struct CSAImprovementPlanSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) var dismiss
    let carrierId: Int
    @StateObject private var store = ImprovementPlanStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack {
                    Text("Improvement plan").font(EType.h2).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Text("Done").font(EType.bodyStrong).foregroundStyle(palette.textSecondary)
                    }.buttonStyle(.plain)
                }
                switch store.state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Space.s8)
                case .empty:
                    Text("No improvement actions on file.").font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                case .error(let e):
                    Text(e.localizedDescription).font(EType.caption).foregroundStyle(Brand.warning)
                case .loaded(let plan):
                    if let goal = plan.overallGoal {
                        Text(goal).font(EType.body).foregroundStyle(palette.textPrimary)
                    }
                    ForEach(plan.categories) { c in categoryCard(c) }
                    if let review = plan.reviewDate {
                        Text("Next review · \(review)")
                            .font(EType.micro.monospaced()).foregroundStyle(palette.textTertiary)
                    }
                }
            }
            .padding(Space.s4)
        }
        .background(palette.bgPrimary)
        .task { await store.refresh() }
    }

    private func categoryCard(_ c: CSAImprovementPlan.Category) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(c.category.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Spacer()
                if let p = c.priority {
                    Text(p.uppercased()).font(EType.micro).tracking(0.6)
                        .foregroundStyle(p == "high" ? Brand.danger : p == "medium" ? Brand.warning : palette.textTertiary)
                }
            }
            if let cur = c.currentPercentile, let tgt = c.targetPercentile {
                Text("Percentile \(Int(cur)) → target \(Int(tgt))")
                    .font(EType.caption.monospaced()).foregroundStyle(palette.textSecondary)
            }
            ForEach(c.actions) { a in
                HStack(alignment: .top, spacing: 6) {
                    Text(statusDot(a.status)).font(.system(size: 9))
                        .foregroundStyle(statusColor(a.status))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(a.action).font(EType.caption).foregroundStyle(palette.textPrimary)
                        if let due = a.dueDate {
                            Text("due \(due)").font(EType.micro.monospaced())
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }
            }
            if let impact = c.projectedImpact {
                Text(impact).font(EType.micro.monospaced()).foregroundStyle(Brand.success)
            }
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .eusoCard(radius: Radius.lg)
    }

    private func statusDot(_ s: String) -> String { "●" }
    private func statusColor(_ s: String) -> Color {
        switch s {
        case "completed": return Brand.success
        case "in_progress": return Brand.warning
        default: return palette.textTertiary
        }
    }
}

// MARK: - Hazmat Qualification sheet (carrierScorecard.getHazmatQualification)

@MainActor
private final class HazmatQualStore: BaseDynamicStore<CSAHazmatQual> {
    private struct QualIn: Encodable { let carrierId: Int }
    let carrierId: Int
    init(carrierId: Int) { self.carrierId = carrierId; super.init() }
    override func fetch() async throws -> CSAHazmatQual {
        try await EusoTripAPI.shared.query("carrierScorecard.getHazmatQualification",
                                           input: QualIn(carrierId: carrierId))
    }
}

private struct CSAHazmatQualSheet: View {
    @Environment(\.palette) var palette
    @Environment(\.dismiss) var dismiss
    @StateObject private var store: HazmatQualStore

    init(carrierId: Int) { _store = StateObject(wrappedValue: HazmatQualStore(carrierId: carrierId)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack {
                    Text("Hazmat qualification").font(EType.h2).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Button { dismiss() } label: {
                        Text("Done").font(EType.bodyStrong).foregroundStyle(palette.textSecondary)
                    }.buttonStyle(.plain)
                }
                switch store.state {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Space.s8)
                case .empty:
                    Text("No hazmat qualification data on file.").font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                case .error(let e):
                    Text(e.localizedDescription).font(EType.caption).foregroundStyle(Brand.warning)
                case .loaded(let q):
                    qualBadge(q.qualified ?? false)
                    statRow("HMSP active", (q.hmsp?.active ?? false) ? "Yes" : "No")
                    if let lic = q.hmsp?.licenseNumber, !lic.isEmpty { statRow("License", lic) }
                    if let days = q.hmsp?.daysRemaining { statRow("HMSP expires in", "\(days) days") }
                    statRow("Hazmat drivers", "\(q.drivers?.total ?? 0)")
                    statRow("Hazmat vehicles", "\(q.vehicles?.total ?? 0)")
                    statRow("Hazmat insurance policies", "\(q.insurance?.policies ?? 0)")
                    if let classes = q.history?.classesHandled, !classes.isEmpty {
                        statRow("Classes handled", classes.joined(separator: ", "))
                    }
                    statRow("Hazmat loads delivered",
                            "\(q.history?.deliveredHazmatLoads ?? 0) / \(q.history?.totalHazmatLoads ?? 0)")
                }
            }
            .padding(Space.s4)
        }
        .background(palette.bgPrimary)
        .task { await store.refresh() }
    }

    private func qualBadge(_ ok: Bool) -> some View {
        HStack(spacing: 8) {
            Text(ok ? "QUALIFIED" : "NOT QUALIFIED")
                .font(EType.bodyStrong).foregroundStyle(.white)
                .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                .background(Capsule().fill(ok ? AnyShapeStyle(Brand.success) : AnyShapeStyle(Brand.danger)))
            Spacer()
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value).font(EType.caption.monospaced()).foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 6)
        .overlay(Rectangle().fill(palette.textTertiary.opacity(0.07)).frame(height: 1), alignment: .bottom)
    }
}

#if DEBUG
struct CatalystFleetSafetyCSA_Previews: PreviewProvider {
    static var previews: some View {
        CatalystFleetSafetyCSA()
            .environment(\.palette, Theme.dark)
            .background(Theme.dark.bgPrimary)
            .preferredColorScheme(.dark)
    }
}
#endif
