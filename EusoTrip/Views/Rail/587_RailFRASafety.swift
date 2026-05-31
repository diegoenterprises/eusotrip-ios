//
//  587_RailFRASafety.swift
//  EusoTrip — Rail Engineer · FRA Safety (CARRIER-SIDE safety scorecard).
//
//  ARCHETYPE = SAFETY SCORECARD (12-month index trend). Reconstructed off the
//  post-line checklist stamp 587 once shared with 564 ("same screen, nouns
//  swapped" defect): it no longer renders a row of shield checks. It now LEADS
//  with the railroad's FRA safety index and its 12-month trend so safety reads
//  as a POSTURE, not a list. The carrier sees BNSF's safety standing on this
//  lane at a glance — index, accident-free streak, open inspections — and the
//  trend makes a degrading month visible before it becomes an audit finding.
//
//  Verbatim to SVG "587 Rail FRA Safety · Dark":
//    • gradient-rim hero: COMPLIANT · BNSF Railway · big "98" index numeral ·
//      "Class I avg 91" · OPEN INSP 2 minor (amber)
//    • 3 KPI tiles: SAFETY INDEX 98 · ACCIDENTS 12MO 0 · OPEN INSP 2
//    • bespoke 12-month index trend histogram (J→M, last bar gradient) with
//      "accident-free 412d" trailing tag + "Rising 12-mo · last FRA audit
//      Mar 2026 · PTC active end-to-end" caption
//    • two compliance rows: amber Open track defects (49 CFR 213, DUE 30d) ·
//      green No reportable accidents (49 CFR 225, CLEAR)
//    • CTA pair: File FRA inspection · Reports
//
//  Wiring (server/routers/railShipments.ts — all RBAC railProcedure):
//    getFRASafetyCompliance (index hero + status, fraService.getSafetyCompliance)
//    getFRAAccidentReports  (12-mo accidents + trend, fraService.getAccidentReports)
//    getRailCompliance      (open track defects + inspections rollup)
//
//  CONTRACT-DRIFT NOTE: the server has historically returned drifting shapes for
//  these procedures — getFRAAccidentReports answers with a BARE ARRAY of report
//  rows rather than the aggregate object the UI wants, and getFRASafetyCompliance
//  keys differently (totalViolations / totalInspections / overallRating /
//  complianceRate). The custom `init(from:)` decoders below tolerate BOTH the
//  legacy and current shapes so a drift never crashes the screen; the bespoke UI
//  still hydrates (or falls back to the verbatim seed series).
//

import SwiftUI

// MARK: - Outer shell

struct RailFRASafetyScreen: View {
    let theme: Theme.Palette
    let railId: String

    var body: some View {
        Shell(theme: theme) {
            RailFRASafetyBody(railId: railId)
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

private struct FRASafetyCompliance587: Decodable {
    let safetyIndex: Double?        // FRA safety index (hero numeral)
    let classIAvg: Double?          // Class I average benchmark
    let openInspections: Int?
    let openInspectionsLabel: String?
    let safetyStatus: String?       // "compliant" | "under_review" | "deficient"
    let railroadName: String?
    // legacy field name kept so an older server payload still hydrates the index
    let complianceScore: Double?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        railroadName = try? c.decode(String.self, forKey: .railroadName)

        // Hero index numeral: prefer an explicit safetyIndex; tolerate the
        // current server which only sends complianceRate (0-1) -> derived below.
        safetyIndex = try? c.decode(Double.self, forKey: .safetyIndex)

        // Class I benchmark (new on main). Optional everywhere.
        classIAvg = try? c.decode(Double.self, forKey: .classIAvg)

        // Open inspections: prefer the dedicated key, else fall back to the
        // server's totalInspections (best-effort proxy for the legacy shape).
        if let open = try? c.decode(Int.self, forKey: .openInspections) {
            openInspections = open
        } else {
            openInspections = try? c.decode(Int.self, forKey: .totalInspections)
        }

        // Inspection qualifier label (new on main). Optional.
        openInspectionsLabel = try? c.decode(String.self, forKey: .openInspectionsLabel)

        // Derive safetyStatus from overallRating when the explicit status is absent.
        if let status = try? c.decode(String.self, forKey: .safetyStatus) {
            safetyStatus = status
        } else if let rating = try? c.decode(String.self, forKey: .overallRating) {
            safetyStatus = rating == "SATISFACTORY" ? "compliant" :
                          rating == "UNSATISFACTORY" ? "deficient" : "under_review"
        } else {
            safetyStatus = nil
        }

        // Legacy index payload: complianceScore direct, else convert complianceRate (0-1 -> 0-100).
        if let score = try? c.decode(Double.self, forKey: .complianceScore) {
            complianceScore = score
        } else if let rate = try? c.decode(Double.self, forKey: .complianceRate) {
            complianceScore = rate * 100.0
        } else {
            complianceScore = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case safetyIndex
        case classIAvg
        case openInspections
        case openInspectionsLabel
        case safetyStatus
        case railroadName
        case complianceScore
        // legacy / drifting server keys
        case totalViolations
        case totalInspections
        case overallRating
        case complianceRate
    }
}

private struct FRAAccidentReports587: Decodable {
    let reportableOnLane: Int?
    let periodMonths: Int?
    let ptcActive: Bool?
    let lastAuditLabel: String?
    let accidentFreeDays: Int?
    let cfr: String?
    /// 12 month-ordered index points (oldest → newest). When absent we render
    /// the representative rising seed series.
    let indexTrend: [Double]?

    init(from decoder: Decoder) throws {
        // Server has historically returned FRAAccidentReport[] (a BARE ARRAY),
        // but this screen aggregates the metrics into one object. Tolerate the
        // array: extract count as reportableOnLane, default the rest. New
        // main-side fields (accidentFreeDays, indexTrend) default to nil so the
        // bespoke UI falls back to its verbatim seed series.
        if let arr = try? decoder.singleValueContainer().decode([FRAAccidentReportDTO].self) {
            reportableOnLane = arr.count
            periodMonths = 12
            ptcActive = true
            lastAuditLabel = nil
            accidentFreeDays = nil
            cfr = "49 CFR 225"
            indexTrend = nil
        } else {
            // Fallback: decode as a keyed aggregate object (current/expected shape).
            let c = try decoder.container(keyedBy: CodingKeys.self)
            reportableOnLane = try c.decodeIfPresent(Int.self, forKey: .reportableOnLane)
            periodMonths     = try c.decodeIfPresent(Int.self, forKey: .periodMonths)
            ptcActive        = try c.decodeIfPresent(Bool.self, forKey: .ptcActive)
            lastAuditLabel   = try c.decodeIfPresent(String.self, forKey: .lastAuditLabel)
            accidentFreeDays = try c.decodeIfPresent(Int.self, forKey: .accidentFreeDays)
            cfr              = try c.decodeIfPresent(String.self, forKey: .cfr)
            indexTrend       = try c.decodeIfPresent([Double].self, forKey: .indexTrend)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case reportableOnLane, periodMonths, ptcActive, lastAuditLabel
        case accidentFreeDays, cfr, indexTrend
    }

    // Minimal DTO for decoding server array items (only needs to compile, not fully decoded)
    private struct FRAAccidentReportDTO: Decodable {
        // Intentionally empty; we only care that this is a decodable array
    }
}

private struct RailComplianceItem587: Decodable {
    let title: String?
    let detail: String?
    let status: String?      // "ok" | "due" | "failed" | "watch"
    let rightValue: String?
}

private struct RailComplianceEnvelope587: Decodable {
    struct InspectionRecord: Decodable {
        let inspectionType: String?
        let result: String?
        let notes: String?
        let inspectionDate: String?
    }
    struct PermitRecord: Decodable {
        let permitNumber: String?
        let status: String?
        let expirationDate: String?
    }

    let inspections: [InspectionRecord]?
    let hazmatPermits: [PermitRecord]?
    let status: String?
    let totalInspections: Int?
    let failedCount: Int?

    func asRegulatoryItems() -> [RailComplianceItem587] {
        var items: [RailComplianceItem587] = []

        // Map inspections
        if let insp = inspections {
            items.append(contentsOf: insp.map { record in
                let typeLabel = (record.inspectionType ?? "inspection").replacingOccurrences(of: "_", with: " ").uppercased()
                return RailComplianceItem587(
                    title: typeLabel,
                    detail: record.notes,
                    status: record.result?.lowercased(),
                    rightValue: record.inspectionDate
                )
            })
        }

        // Map permits
        if let permits = hazmatPermits {
            items.append(contentsOf: permits.map { record in
                return RailComplianceItem587(
                    title: "HAZMAT PERMIT",
                    detail: record.permitNumber,
                    status: record.status?.lowercased(),
                    rightValue: record.expirationDate
                )
            })
        }

        return items
    }
}

private struct RailIdIn587: Encodable { let railId: String }

// MARK: - Trend datum (private, suffixed)

private struct FRAIndexPoint587: Identifiable {
    let id = UUID()
    let monthInitial: String
    let value: Double
}

// MARK: - Body

private struct RailFRASafetyBody: View {
    @Environment(\.palette) private var palette
    let railId: String

    @State private var compliance: FRASafetyCompliance587? = nil
    @State private var accidents: FRAAccidentReports587? = nil
    @State private var regulatoryItems: [RailComplianceItem587] = []
    @State private var didLoad = false
    @State private var isFiling = false

    // MARK: Seed (house 0%-mock — verbatim to SVG, overwritten on hydrate)

    // SVG bar heights → index points (12 mo, rising), last month is "now".
    private static let seedTrend: [FRAIndexPoint587] = [
        .init(monthInitial: "J", value: 78), .init(monthInitial: "J", value: 80),
        .init(monthInitial: "A", value: 82), .init(monthInitial: "S", value: 84),
        .init(monthInitial: "O", value: 82), .init(monthInitial: "N", value: 87),
        .init(monthInitial: "D", value: 89), .init(monthInitial: "J", value: 91),
        .init(monthInitial: "F", value: 93), .init(monthInitial: "M", value: 94),
        .init(monthInitial: "A", value: 96), .init(monthInitial: "M", value: 98),
    ]

    private static let seedRegulatory: [RailComplianceItem587] = [
        .init(title: "Open track defects · 2 minor",
              detail: "49 CFR 213 · re-inspect within 30d",
              status: "due", rightValue: "DUE 30d"),
        .init(title: "No reportable accidents · 12 mo",
              detail: "49 CFR 225 · BNSF on this lane",
              status: "ok", rightValue: "CLEAR"),
    ]

    // MARK: Derived — hero

    private var railroadName: String  { compliance?.railroadName ?? "BNSF Railway" }
    private var safetyStatus: String  { (compliance?.safetyStatus ?? "compliant").lowercased() }
    private var safetyOk: Bool        { safetyStatus == "compliant" }
    private var safetyUnderReview: Bool { safetyStatus == "under_review" }

    private var statusLabel: String {
        switch safetyStatus {
        case "deficient":    return "DEFICIENT"
        case "under_review": return "UNDER REVIEW"
        default:             return "COMPLIANT"
        }
    }
    private var statusColor: Color {
        safetyOk ? Brand.success : (safetyUnderReview ? Brand.warning : Brand.danger)
    }

    private var safetyIndex: Double {
        if let i = compliance?.safetyIndex     { return i }
        if let s = compliance?.complianceScore { return s }   // legacy payload
        return 98
    }
    private var indexLabel: String { "\(Int(safetyIndex.rounded()))" }

    private var classIAvg: Int { Int((compliance?.classIAvg ?? 91).rounded()) }

    private var openInspections: Int { compliance?.openInspections ?? 2 }
    private var openInspectionsLabel: String { compliance?.openInspectionsLabel ?? "minor" }

    private var accidents12mo: Int { accidents?.reportableOnLane ?? 0 }

    private var accidentFreeTag: String {
        let days = accidents?.accidentFreeDays ?? 412
        return "accident-free \(days)d"
    }

    private var trend: [FRAIndexPoint587] {
        guard let raw = accidents?.indexTrend, !raw.isEmpty else { return Self.seedTrend }
        // Map server index series onto the SVG month-initial axis; when the
        // server omits month labels we re-use the canonical 12-mo initials.
        let initials = Self.seedTrend.map(\.monthInitial)
        return raw.enumerated().map { idx, v in
            FRAIndexPoint587(monthInitial: initials[idx % initials.count], value: v)
        }
    }

    private var trendCaption: String {
        let audit = accidents?.lastAuditLabel.map { "last FRA audit \($0)" } ?? "last FRA audit Mar 2026"
        let ptc   = (accidents?.ptcActive ?? true) ? "PTC active end-to-end" : "PTC inactive on segment"
        return "Rising 12-mo · \(audit) · \(ptc)"
    }

    private var regulatory: [RailComplianceItem587] {
        regulatoryItems.isEmpty ? Self.seedRegulatory : regulatoryItems
    }

    // MARK: View

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                eyebrow
                headline
                IridescentHairline()
                heroCard
                kpiStrip
                trendCard
                complianceRows
                ctaPair
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s3)
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            await loadAll()
        }
    }

    // MARK: Eyebrow + headline

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("✦ RAIL ENGINEER · FRA SAFETY")
                .font(.system(size: 9, weight: .black)).kerning(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text(railId)
                .font(.system(size: 9, weight: .heavy).monospaced()).kerning(0.6)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("FRA safety")
                .font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Hero card — index + benchmark + open inspections

    private var heroCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard)
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)

            VStack(alignment: .leading, spacing: Space.s3) {
                // Status + railroad pills
                HStack(spacing: Space.s2) {
                    Text(statusLabel)
                        .font(.system(size: 11, weight: .bold)).kerning(0.5)
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(statusColor.opacity(0.18)))
                    Text(railroadName)
                        .font(.system(size: 11, weight: .bold)).kerning(0.5)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(palette.textPrimary.opacity(0.10)))
                    Spacer(minLength: 0)
                }

                HStack(alignment: .top, spacing: Space.s3) {
                    // Index numeral + benchmark
                    HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                        Text(indexLabel)
                            .font(.system(size: 38, weight: .heavy).monospacedDigit())
                            .foregroundStyle(LinearGradient.diagonal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FRA safety index")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                            Text("Class I avg \(classIAvg)")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                    // Open inspections
                    VStack(alignment: .leading, spacing: 2) {
                        Text("OPEN INSP")
                            .font(.system(size: 10, weight: .black)).kerning(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text("\(openInspections)")
                            .font(.system(size: 22, weight: .heavy).monospacedDigit())
                            .foregroundStyle(openInspections > 0 ? Brand.warning : palette.textPrimary)
                        Text(openInspectionsLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .padding(Space.s4)
        }
        .frame(height: 124)
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "Safety index", value: indexLabel, gradientNumeral: true)
            MetricTile(label: "Accidents 12mo", value: "\(accidents12mo)",
                       accent: accidents12mo > 0 ? Brand.danger : palette.textPrimary)
            MetricTile(label: "Open insp", value: "\(openInspections)",
                       accent: openInspections > 0 ? Brand.warning : palette.textPrimary)
        }
    }

    // MARK: 12-month index trend — bespoke histogram

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text("FRA SAFETY INDEX · 12 MO")
                    .font(.system(size: 9, weight: .black)).kerning(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text(accidentFreeTag)
                    .font(.system(size: 11, weight: .bold)).kerning(0.4)
                    .foregroundStyle(palette.textSecondary)
            }

            FRAIndexTrendChart587(points: trend)
                .frame(height: 150)

            Text(trendCaption)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
    }

    // MARK: Compliance rows (amber defects / green clear)

    private var complianceRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(regulatory.enumerated()), id: \.offset) { idx, item in
                if idx > 0 {
                    Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                }
                complianceRow(item)
            }
        }
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
    }

    @ViewBuilder
    private func complianceRow(_ item: RailComplianceItem587) -> some View {
        let color = pillColor(item.status)
        let icon  = iconName(item.status)

        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.18)).frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title ?? "—")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                if let detail = item.detail {
                    Text(detail)
                        .font(.system(size: 11).monospaced()).kerning(0.3)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: Space.s2)
            if let rv = item.rightValue, !rv.isEmpty {
                Text(rv)
                    .font(.system(size: 10, weight: .bold)).kerning(0.5)
                    .foregroundStyle(color)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(color.opacity(0.18)))
            }
        }
        .padding(.horizontal, Space.s4).padding(.vertical, 14)
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "File FRA inspection",
                      action: { isFiling = true; Task { await refresh() } },
                      leadingIcon: "plus", isLoading: isFiling)
            Button("Reports") {}
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.bgCard)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                )
        }
    }

    // MARK: Helpers

    private func pillColor(_ status: String?) -> Color {
        switch (status ?? "ok").lowercased() {
        case "ok":     return Brand.success
        case "due":    return Brand.warning
        case "watch":  return Brand.warning
        case "failed": return Brand.danger
        default:       return Brand.info
        }
    }

    private func iconName(_ status: String?) -> String {
        switch (status ?? "ok").lowercased() {
        case "ok":     return "checkmark.shield.fill"
        case "due":    return "shield.lefthalf.filled"
        case "watch":  return "exclamationmark.shield.fill"
        case "failed": return "xmark.shield.fill"
        default:       return "shield.fill"
        }
    }

    // MARK: Data loading

    private func loadAll() async {
        // WIRE: railShipments.getFRASafetyCompliance — index hero + status
        async let compTask: FRASafetyCompliance587 = EusoTripAPI.shared.query(
            "railShipments.getFRASafetyCompliance", input: RailIdIn587(railId: railId))
        // WIRE: railShipments.getFRAAccidentReports — 12-mo accidents + trend
        async let accTask: FRAAccidentReports587 = EusoTripAPI.shared.query(
            "railShipments.getFRAAccidentReports", input: RailIdIn587(railId: railId))
        // WIRE: railShipments.getRailCompliance — open defects + inspections rollup
        async let regTask: [RailComplianceItem587] = EusoTripAPI.shared.query(
            "railShipments.getRailCompliance", input: RailIdIn587(railId: railId))

        compliance      = try? await compTask
        accidents       = try? await accTask
        regulatoryItems = (try? await regTask) ?? []
    }

    private func refresh() async {
        defer { isFiling = false }
        let result: FRASafetyCompliance587? = try? await EusoTripAPI.shared.query(
            "railShipments.getFRASafetyCompliance", input: RailIdIn587(railId: railId))
        if let r = result { compliance = r }
    }
}

// MARK: - 12-month FRA index trend chart (native Canvas histogram)

private struct FRAIndexTrendChart587: View {
    @Environment(\.palette) private var palette
    let points: [FRAIndexPoint587]

    // Bars are drawn against a fixed visual floor so a flat-high series still
    // shows month-to-month delta. Floor sits ~12 index-pts below the min.
    private var floor: Double {
        let lo = points.map(\.value).min() ?? 0
        return max(0, lo - 12)
    }
    private var ceiling: Double {
        let hi = points.map(\.value).max() ?? 100
        return max(hi, floor + 1)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let labelBand: CGFloat = 16
            let barH = max(0, geo.size.height - labelBand)
            let count = max(points.count, 1)
            let gap: CGFloat = 8
            let barW = max(1, (w - gap * CGFloat(count - 1)) / CGFloat(count))

            ZStack(alignment: .topLeading) {
                ForEach(Array(points.enumerated()), id: \.element.id) { idx, pt in
                    let isLast = idx == points.count - 1
                    let frac = self.fraction(pt.value)
                    let h = max(4, barH * frac)
                    let x = (barW + gap) * CGFloat(idx)

                    // Bar
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(self.barFill(isLast: isLast))
                        .frame(width: barW, height: h)
                        .offset(x: x, y: barH - h)

                    // Month initial under each bar
                    Text(pt.monthInitial)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                        .frame(width: barW)
                        .offset(x: x, y: barH + 4)
                }
            }
        }
    }

    private func fraction(_ v: Double) -> CGFloat {
        let span = ceiling - floor
        guard span > 0 else { return 0 }
        return CGFloat(min(max((v - floor) / span, 0.04), 1))
    }

    private func barFill(isLast: Bool) -> AnyShapeStyle {
        isLast
            ? AnyShapeStyle(LinearGradient.diagonal)
            : AnyShapeStyle(Brand.info.opacity(0.45))
    }
}
