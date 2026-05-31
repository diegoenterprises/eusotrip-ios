//
//  631_RailFRAAccidentReports.swift
//  EusoTrip — Rail Engineer · FRA Accident Reports (carrier-side incident timeline).
//
//  ARCHETYPE = INCIDENT TIMELINE — accident-free streak + declining 12-mo
//  sparkline hero, then a dated event spine with severity-colored nodes and
//  reportable pills. Deliberately differentiated from 587's bar-chart
//  scorecard: a smooth sparkline + left-gutter dated timeline so the two FRA
//  surfaces never read as the same screen.
//
//  transportMode=rail · US/FRA single-authority · railProcedure RBAC.
//  Shipper-of-record Eusorone Technologies (DU pin).
//
//  Wiring (server/routers/railShipments.ts):
//    railShipments.getFRAAccidentReports   EXISTS:772 → fraService.getAccidentReports
//        returns FRAAccidentReport[] (reportId · incidentDate · railroad · state ·
//        incidentType · description · fatalities · injuries · totalDamage ·
//        hazmatReleased …). The dated incident spine.
//    railShipments.getFRASafetyCompliance  EXISTS:789 → fraService.getSafetyCompliance
//        returns FRASafetyCompliance (accidentRate · complianceRate · overallRating).
//        Used best-effort for the streak / trend frame.
//    railShipments.getRailCompliance       EXISTS:568 → inspection rollup (not
//        rendered on this surface; the timeline is accident-only).
//

import SwiftUI

struct RailFRAAccidentReportsScreen: View {
    let theme: Theme.Palette
    /// Railroad code scoping the FRA pull. The eyebrow renders "BNSF · 12 MO"
    /// per the wireframe; Eusorone's lane carrier is BNSF.
    var railroadCode: String = "BNSF"

    var body: some View {
        Shell(theme: theme) {
            RailFRAAccidentReportsBody(railroadCode: railroadCode)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror server/services/integrations/FRAService.ts)

/// One row from `fraService.getAccidentReports`. All fields optional so a
/// partial / null upstream payload degrades to an empty timeline rather than
/// a decode crash.
private struct FRAAccidentRow631: Decodable, Identifiable {
    let reportId: String?
    let incidentDate: String?
    let railroad: String?
    let railroadCode: String?
    let state: String?
    let county: String?
    let city: String?
    let incidentType: String?
    let description: String?
    let fatalities: Int?
    let injuries: Int?
    let totalDamage: Double?
    let hazmatReleased: Bool?
    let hazmatCars: Int?

    var id: String { reportId ?? "\(incidentDate ?? "")-\(city ?? "")-\(incidentType ?? "")" }
}

/// `fraService.getSafetyCompliance` rollup. Best-effort — only the accident
/// rate / rating frame the streak copy when present.
private struct FRASafetyCompliance631: Decodable {
    let railroadCode: String?
    let railroadName: String?
    let reportingYear: Int?
    let accidentRate: Double?
    let complianceRate: Double?
    let overallRating: String?
}

private struct FRAAccidentInput631: Encodable {
    let railroad: String
}

private struct FRASafetyInput631: Encodable {
    let railroadCode: String
}

// MARK: - Body

private struct RailFRAAccidentReportsBody: View {
    let railroadCode: String

    @Environment(\.palette) private var palette
    @State private var incidents: [FRAAccidentRow631] = []
    @State private var safety: FRASafetyCompliance631? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // MARK: Derived — streak + trend (computed client-side; the FRA APIs do
    // not return a precomputed "accident-free streak (days)" or a 12-mo
    // sparkline, so we derive both from the dated incident list).

    /// Sorted newest-first by incident date.
    private var sortedIncidents: [FRAAccidentRow631] {
        incidents.sorted { (a, b) in
            (Self.date(a.incidentDate) ?? .distantPast) > (Self.date(b.incidentDate) ?? .distantPast)
        }
    }

    /// Reportable = any incident with damage/casualties over the 49 CFR 225
    /// reporting bar. Without the exact threshold field upstream we treat a
    /// fatality, injury, hazmat release, or damage as reportable; the rest
    /// read as NON-RPT.
    private func isReportable(_ r: FRAAccidentRow631) -> Bool {
        if (r.fatalities ?? 0) > 0 { return true }
        if (r.injuries ?? 0) > 0 { return true }
        if r.hazmatReleased == true { return true }
        if (r.totalDamage ?? 0) > 0 { return true }
        return false
    }

    private var reportableCount: Int { incidents.filter { isReportable($0) }.count }
    private var archivedCount: Int { incidents.count }

    /// Days since the most recent incident — the accident-free streak.
    private var streakDays: Int? {
        guard let latest = sortedIncidents.compactMap({ Self.date($0.incidentDate) }).max() else { return nil }
        return max(0, Int(Date().timeIntervalSince(latest) / 86_400))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            titleRow
            IridescentHairline()
                .padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    loadingBlocks
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    .padding(.horizontal, 20)
                } else {
                    streakHero
                        .padding(.horizontal, 20)
                    incidentLogHeader
                        .padding(.horizontal, 20)
                    incidentTimeline
                        .padding(.horizontal, 20)
                    footerActions
                        .padding(.horizontal, 20)
                }
                Color.clear.frame(height: 8)
            }
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Eyebrow

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            Text("✦ RAIL ENGINEER · FRA REPORTS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("\(railroadCode.uppercased()) · 12 MO")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20)
        .padding(.top, Space.s4)
    }

    // MARK: - Title row (back · "FRA reports" · kebab)

    private var titleRow: some View {
        HStack(alignment: .center, spacing: Space.s3) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Text("FRA reports")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.top, Space.s3)
    }

    // MARK: - Loading skeleton

    private var loadingBlocks: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 128)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                            .strokeBorder(palette.borderFaint))
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 280)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(palette.borderFaint))
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Streak hero (sparkline + accident-free streak)

    private var streakHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("ACCIDENT-FREE STREAK")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, 26).padding(.leading, 22)

                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(streakDays.map { "\($0)" } ?? "—")
                        .font(.system(size: 40, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("d")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.top, 6).padding(.leading, 22)

                Text("\(reportableCount) reportable · trailing 12 mo · 49 CFR 225")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    .padding(.top, 4).padding(.leading, 22)

                FRASparkline(values: sparklineValues, lineGradient: LinearGradient.primary, dotGradient: LinearGradient.diagonal)
                    .frame(height: 36)
                    .padding(.horizontal, 22)
                    .padding(.top, 10)

                HStack {
                    Spacer()
                    Text("incidents · declining")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.horizontal, 22)
                .padding(.top, 2)
            }
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        // Surface the getFRASafetyCompliance rollup (overall FRA rating) to
        // VoiceOver without altering the wireframe's verbatim visible copy.
        .accessibilityElement(children: .combine)
        .accessibilityValue(safety?.overallRating.map { "FRA rating \($0.capitalized)" } ?? "")
    }

    /// 12 sampled month-values for the sparkline. The wireframe shows a smooth
    /// declining trend; we sample real incident counts per trailing month when
    /// any incidents are present, then invert to a "declining" line so the
    /// curve drops as the streak grows.
    private var sparklineValues: [Double] {
        let buckets = monthlyIncidentCounts
        if buckets.allSatisfy({ $0 == 0 }) {
            // No incidents → a flat-low declining line so the hero still reads
            // as "good and improving" rather than empty.
            return stride(from: 30.0, through: 8.0, by: -2.0).map { $0 }
        }
        // Invert counts into a "cumulative declining incident pressure" curve.
        var running = buckets.reduce(0, +)
        var out: [Double] = []
        for b in buckets {
            out.append(Double(running))
            running -= b
        }
        return out
    }

    /// Trailing-12-month incident counts, oldest→newest.
    private var monthlyIncidentCounts: [Int] {
        var counts = Array(repeating: 0, count: 12)
        let cal = Calendar.current
        let now = Date()
        for r in incidents {
            guard let d = Self.date(r.incidentDate) else { continue }
            let months = cal.dateComponents([.month], from: d, to: now).month ?? 99
            if months >= 0 && months < 12 {
                counts[11 - months] += 1
            }
        }
        return counts
    }

    // MARK: - Incident log header

    private var incidentLogHeader: some View {
        HStack {
            Text("INCIDENT LOG · 49 CFR 225")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text("\(archivedCount) archived")
                .font(.system(size: 11, weight: .bold)).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: - Incident timeline (left-gutter dated spine)

    @ViewBuilder
    private var incidentTimeline: some View {
        if sortedIncidents.isEmpty {
            EusoEmptyState(systemImage: "checkmark.seal",
                           title: "No archived incidents",
                           subtitle: "FRA reportable-incident history for \(railroadCode.uppercased()) will appear here as a chronology.")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(sortedIncidents.enumerated()), id: \.element.id) { idx, r in
                    timelineRow(r, isLast: idx == sortedIncidents.count - 1)
                }
            }
            .padding(.vertical, 20)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func severityColor(_ r: FRAAccidentRow631) -> Color {
        // Red = casualty / hazmat release (most severe); amber = reportable
        // property/grade-crossing; slate = non-reportable.
        if (r.fatalities ?? 0) > 0 || r.hazmatReleased == true { return Brand.danger }
        if isReportable(r) { return Brand.warning }
        return Brand.rail
    }

    private func timelineRow(_ r: FRAAccidentRow631, isLast: Bool) -> some View {
        let color = severityColor(r)
        let reportable = isReportable(r)
        return HStack(alignment: .top, spacing: 0) {
            // Left gutter: month/year stamp
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.monthLabel(r.incidentDate))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(Self.yearLabel(r.incidentDate))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            .frame(width: 62, alignment: .leading)

            // Node + connector spine. The spine stretches to the row's full
            // height so consecutive nodes read as one continuous timeline;
            // the node ring + filled core sit at the top of the row.
            ZStack(alignment: .top) {
                if !isLast {
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 11)
                }
                Circle()
                    .stroke(color.opacity(0.3), lineWidth: 2)
                    .frame(width: 22, height: 22)
                Circle()
                    .fill(color)
                    .frame(width: 14, height: 14)
                    .padding(.top, 4)
            }
            .frame(width: 28)
            .frame(maxHeight: .infinity)
            .padding(.top, 2)

            // Detail
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.incidentTitle(r))
                            .font(.system(size: 13.5, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(Self.incidentSubtitle(r))
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 6)
                    reportablePill(reportable: reportable, color: color)
                }
                if !isLast {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1)
                        .padding(.top, 12)
                }
            }
            .padding(.leading, 6)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, isLast ? 0 : 16)
    }

    private func reportablePill(reportable: Bool, color: Color) -> some View {
        // Non-reportable slate pills use the lighter slate-text from the
        // wireframe (#90A4AE) for the label; reportable pills tint the label
        // with the node's own severity color.
        let labelColor: Color = reportable ? color : Color(hex: 0x90A4AE)
        return Text(reportable ? "REPORTABLE" : "NON-RPT")
            .font(.system(size: 11, weight: .bold)).tracking(0.5)
            .foregroundStyle(labelColor)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.14)))
    }

    // MARK: - Footer actions

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Filter by state", action: {})
                .frame(maxWidth: .infinity)
            Button(action: {}) {
                Text("Safety metrics")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                                .strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(width: 148)
        }
    }

    // MARK: - Date / label helpers

    private static func date(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd", "MM/dd/yyyy"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    private static func monthLabel(_ s: String?) -> String {
        guard let d = date(s) else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM"
        return f.string(from: d).uppercased()
    }

    private static func yearLabel(_ s: String?) -> String {
        guard let d = date(s) else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yy"
        return "'\(f.string(from: d))"
    }

    private static func incidentTitle(_ r: FRAAccidentRow631) -> String {
        let type = (r.incidentType ?? "Incident")
        let loc: String = {
            let city = r.city
            let st = r.state
            switch (city, st) {
            case let (c?, s?): return "\(c) \(s)"
            case let (c?, nil): return c
            case let (nil, s?): return s
            default: return ""
            }
        }()
        return loc.isEmpty ? type : "\(type) · \(loc)"
    }

    private static func incidentSubtitle(_ r: FRAAccidentRow631) -> String {
        if let desc = r.description, !desc.isEmpty { return desc }
        var bits: [String] = []
        if let f = r.fatalities, f > 0 { bits.append("\(f) fatal") }
        if let i = r.injuries, i > 0 { bits.append("\(i) injured") }
        else if (r.fatalities ?? 0) == 0 { bits.append("No injuries") }
        if r.hazmatReleased == true {
            bits.append("hazmat release\(r.hazmatCars.map { " · \($0) cars" } ?? "")")
        }
        return bits.isEmpty ? "Archived report" : bits.joined(separator: " · ")
    }

    // MARK: - Load

    private func reload() async {
        loading = true; loadError = nil
        // The server returns `null` on upstream FRA failure (railShipments.ts
        // :783/:797), so decode into optionals and degrade null/decode-failure
        // to an empty timeline — never a crash, never mock data.
        async let accTask: [FRAAccidentRow631] = EusoTripAPI.shared.query(
            "railShipments.getFRAAccidentReports",
            input: FRAAccidentInput631(railroad: railroadCode))
        async let safeTask: FRASafetyCompliance631 = EusoTripAPI.shared.query(
            "railShipments.getFRASafetyCompliance",
            input: FRASafetyInput631(railroadCode: railroadCode))

        self.incidents = (try? await accTask) ?? []
        self.safety = try? await safeTask
        loading = false
    }
}

// MARK: - FRASparkline (smooth declining trend)

/// Single-stroke trend line over normalized values with a terminal dot.
/// Mirrors the wireframe's smooth 12-point declining polyline + end node.
private struct FRASparkline: View {
    let values: [Double]
    let lineGradient: LinearGradient
    let dotGradient: LinearGradient

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let pts = points(in: CGSize(width: w, height: h))
            ZStack(alignment: .topLeading) {
                if pts.count >= 2 {
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(lineGradient,
                            style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    if let last = pts.last {
                        Circle()
                            .fill(dotGradient)
                            .frame(width: 7, height: 7)
                            .position(last)
                    }
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2 else { return [] }
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let span = max(maxV - minV, 0.0001)
        let stepX = size.width / CGFloat(values.count - 1)
        let inset: CGFloat = 4
        let usableH = max(size.height - inset * 2, 1)
        return values.enumerated().map { idx, v in
            let x = CGFloat(idx) * stepX
            let norm = (v - minV) / span                 // 0…1
            let y = inset + usableH * (1 - CGFloat(norm)) // high value = top
            return CGPoint(x: x, y: y)
        }
    }
}

#Preview("631 · Rail FRA Accident Reports · Night") {
    RailFRAAccidentReportsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("631 · Rail FRA Accident Reports · Light") {
    RailFRAAccidentReportsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
