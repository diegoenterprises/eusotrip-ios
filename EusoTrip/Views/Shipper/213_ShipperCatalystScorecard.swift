//
//  213_ShipperCatalystScorecard.swift
//  EusoTrip 2027 UI — brick 213 (shipper · catalyst scorecards)
//
//  Carrier-reputation directory from the SHIPPER's vantage. Every
//  catalyst the shipper has worked with, sorted by spend, with a
//  letter grade computed from on-time + completion + spend share, a
//  5-star rating, and a tappable detail sheet for the per-catalyst
//  trend.
//
//  Web peer reference: `/shipper-scorecard` (`ShipperScorecard.tsx`)
//  grades SHIPPERS for catalysts to filter by — the inverse vantage
//  doesn't exist on web yet. This iOS brick fills the gap with the
//  data the platform already exposes via:
//
//    • shippers.getCatalystPerformance(period) — top catalysts in
//      window (totalLoads, delivered, onTimeRate, totalSpend)
//    • shippers.getFavoriteCatalysts() — aggregate of working carriers
//      across all time (loadsCompleted, totalSpend, dotNumber)
//
//  We merge both into one ranked list — DOT/MC come from
//  `getFavoriteCatalysts`, period KPIs come from
//  `getCatalystPerformance`. Ranking is by `totalSpend` desc within
//  the active period.
//
//  Design doctrine (per Driver Figma 010-103):
//    §1   Gradient hero + grade pill on every row.
//    §2   `.easeOut(0.12)` press scale on every tappable row.
//    §4   Tokenized Space/Radius/EType.
//    §5   Palette semantic. Grade colors: A→Brand.success, B→Brand.info,
//         C→Brand.warning, D/F→Brand.danger.
//    §10  Dark + Light previews.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Store

@MainActor
final class ShipperCatalystScorecardStore: ObservableObject {
    enum LoadState {
        case loading
        case empty
        case error(String)
        case loaded(merged: [MergedRow])
    }

    /// One row in the merged directory — period KPIs from
    /// `getCatalystPerformance` joined with all-time DOT from
    /// `getFavoriteCatalysts`. Either side may be missing (a brand-new
    /// catalyst has period KPIs but no history; a long-time partner
    /// inactive this period has history but no period row). The view
    /// renders em-dash sentinels for the missing side.
    struct MergedRow: Identifiable, Hashable {
        let catalystId: String
        let name: String
        let dotNumber: String?
        let totalLoads: Int
        let delivered: Int
        let onTimeRate: Int
        let totalSpend: Double
        let lifetimeLoads: Int
        let lifetimeSpend: Double

        var id: String { catalystId }

        /// Letter grade derived from on-time × completion × spend
        /// share. Conservative weighting so a 95% on-time catalyst
        /// with 4 loads doesn't outrank a 92% on-time catalyst with
        /// 40 loads — volume signal carries weight.
        var grade: Grade {
            // Completion ratio (delivered / totalLoads). 0..1.
            let completion = totalLoads > 0
                ? Double(delivered) / Double(totalLoads)
                : 0
            // On-time as 0..1.
            let onTime = Double(onTimeRate) / 100.0
            // Volume weight — log-scaled so 1 vs 100 loads doesn't
            // dominate the score. caps at 1.0 around 50 loads.
            let volume = min(1.0, log10(Double(max(totalLoads, 1)) + 1) / log10(50.0))
            // Score 0..100. On-time 50%, completion 30%, volume 20%.
            let score = (onTime * 0.5 + completion * 0.3 + volume * 0.2) * 100.0
            switch score {
            case 90...:    return .a
            case 80..<90:  return .b
            case 70..<80:  return .c
            case 60..<70:  return .d
            default:       return .f
            }
        }

        /// 0..5 star count from on-time + completion. Half-star
        /// granularity so an 87% on-time partner reads as 4.5 stars.
        var starCount: Double {
            let onTime = Double(onTimeRate) / 100.0
            let completion = totalLoads > 0
                ? Double(delivered) / Double(totalLoads)
                : 0
            let avg = (onTime + completion) / 2.0
            return (avg * 5.0 * 2).rounded() / 2.0
        }

        enum Grade: String {
            case a = "A"
            case b = "B"
            case c = "C"
            case d = "D"
            case f = "F"
        }
    }

    @Published private(set) var state: LoadState = .loading
    @Published var period: ShipperAPI.SpendingPeriod = .month {
        didSet {
            if oldValue != period { Task { await refresh() } }
        }
    }

    private let api: EusoTripAPI

    init(api: EusoTripAPI = .shared) {
        self.api = api
    }

    func refresh() async {
        if case .loaded = state {} else { state = .loading }
        do {
            async let perfTask = api.shipper.getCatalystPerformance(period: period)
            async let favTask  = api.shipper.getFavoriteCatalysts()
            let (perf, fav) = try await (perfTask, favTask)

            // Index favorites by catalystId so we can fold DOT in.
            let favById: [String: ShipperAPI.FavoriteCatalyst] = Dictionary(
                uniqueKeysWithValues: fav.map { ($0.catalystId, $0) }
            )

            // Start with period rows; fill DOT from favorites.
            var merged: [MergedRow] = perf.map { p in
                let f = favById[p.catalystId]
                return MergedRow(
                    catalystId:    p.catalystId,
                    name:          p.name,
                    dotNumber:     f?.dotNumber,
                    totalLoads:    p.totalLoads,
                    delivered:     p.delivered,
                    onTimeRate:    p.onTimeRate,
                    totalSpend:    p.totalSpend,
                    lifetimeLoads: f?.loadsCompleted ?? p.totalLoads,
                    lifetimeSpend: f?.totalSpend ?? p.totalSpend
                )
            }
            // Append history-only catalysts that didn't move loads in
            // this window so the directory still surfaces them.
            let perfIds = Set(perf.map(\.catalystId))
            for f in fav where !perfIds.contains(f.catalystId) {
                merged.append(MergedRow(
                    catalystId:    f.catalystId,
                    name:          f.name,
                    dotNumber:     f.dotNumber,
                    totalLoads:    0,
                    delivered:     0,
                    onTimeRate:    0,
                    totalSpend:    0,
                    lifetimeLoads: f.loadsCompleted,
                    lifetimeSpend: f.totalSpend
                ))
            }
            merged.sort { $0.totalSpend > $1.totalSpend }

            state = merged.isEmpty ? .empty : .loaded(merged: merged)
        } catch {
            state = .error("Couldn't reach catalyst performance service.")
        }
    }
}

// MARK: - Screen root

struct ShipperCatalystScorecard: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var store = ShipperCatalystScorecardStore()
    @State private var selected: ShipperCatalystScorecardStore.MergedRow?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                periodChips
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .sheet(item: $selected) { row in
            CatalystDetailSheet(row: row)
                .environment(\.palette, palette)
                .presentationDragIndicator(.visible)
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.18),
            value: store.period
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "rosette")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36)
                .background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · CARRIER SCORECARDS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Catalysts working your loads")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("Letter grades, 5-star reputation, spend share — pick your top performers, drop the rest.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    // MARK: Period chips

    private var periodChips: some View {
        HStack(spacing: Space.s2) {
            ForEach([ShipperAPI.SpendingPeriod.month,
                     .quarter,
                     .year], id: \.self) { p in
                chipButton(label: chipLabel(for: p), active: store.period == p) {
                    store.period = p
                }
            }
        }
    }

    private func chipLabel(for p: ShipperAPI.SpendingPeriod) -> String {
        switch p {
        case .month:   return "30 days"
        case .quarter: return "90 days"
        case .year:    return "12 months"
        }
    }

    private func chipButton(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(EType.bodyStrong)
                .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s2)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(active
                              ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18))
                              : AnyShapeStyle(palette.bgCard))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(active ? palette.borderSoft : palette.borderFaint, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .loading:
            VStack(spacing: Space.s2) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.3))
                        .frame(height: 80)
                }
            }
        case .empty:
            EusoEmptyState(
                systemImage: "rosette",
                title: "No carrier history yet",
                subtitle: "Once catalysts start delivering your loads, their scorecards land here — letter grades, on-time %, and rolling 5-star reputation.",
                comingSoon: false
            )
        case .error(let msg):
            errorBanner(msg)
        case .loaded(let merged):
            summaryStrip(merged)
            VStack(spacing: Space.s2) {
                ForEach(merged) { row in
                    catalystRow(row)
                }
            }
        }
    }

    // MARK: Summary strip

    private func summaryStrip(_ rows: [ShipperCatalystScorecardStore.MergedRow]) -> some View {
        let totalLoads = rows.reduce(0) { $0 + $1.totalLoads }
        let totalSpend = rows.reduce(0) { $0 + $1.totalSpend }
        let avgOnTime: Int = {
            let withLoads = rows.filter { $0.totalLoads > 0 }
            guard !withLoads.isEmpty else { return 0 }
            let sum = withLoads.reduce(0) { $0 + $1.onTimeRate }
            return sum / withLoads.count
        }()
        return HStack(spacing: Space.s2) {
            summaryTile(label: "CARRIERS", value: "\(rows.filter { $0.totalLoads > 0 }.count)")
            summaryTile(label: "LOADS",    value: "\(totalLoads)")
            summaryTile(label: "AVG ON-TIME", value: "\(avgOnTime)%")
            summaryTile(label: "SPEND",    value: formatThousands(totalSpend), prefix: "$")
        }
    }

    private func summaryTile(label: String, value: String, prefix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 1) {
                if !prefix.isEmpty {
                    Text(prefix)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(palette.textTertiary)
                }
                Text(value)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Catalyst row

    private func catalystRow(_ r: ShipperCatalystScorecardStore.MergedRow) -> some View {
        Button {
            selected = r
        } label: {
            HStack(alignment: .top, spacing: Space.s3) {
                gradeBadge(r.grade)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(r.name)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1)
                        if let dot = r.dotNumber, !dot.isEmpty {
                            Text("DOT \(dot)")
                                .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    starsRow(r.starCount)
                    HStack(spacing: 8) {
                        microPair(label: "ON-TIME", value: r.totalLoads > 0 ? "\(r.onTimeRate)%" : "—")
                        Divider().frame(width: 1, height: 10).overlay(palette.borderFaint)
                        microPair(label: "LOADS", value: r.totalLoads > 0 ? "\(r.totalLoads)" : "—")
                        Divider().frame(width: 1, height: 10).overlay(palette.borderFaint)
                        microPair(label: "SPEND", value: r.totalSpend > 0 ? "$\(formatThousands(r.totalSpend))" : "—")
                    }
                }
                Spacer(minLength: Space.s2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(CatalystRowButtonStyle())
    }

    private func gradeBadge(_ grade: ShipperCatalystScorecardStore.MergedRow.Grade) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(gradeBackground(grade))
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(gradeStroke(grade), lineWidth: 1.5)
            Text(grade.rawValue)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(gradeForeground(grade))
        }
        .frame(width: 44, height: 44)
    }

    private func gradeBackground(_ grade: ShipperCatalystScorecardStore.MergedRow.Grade) -> AnyShapeStyle {
        switch grade {
        case .a: return AnyShapeStyle(Brand.success.opacity(0.18))
        case .b: return AnyShapeStyle(Brand.info.opacity(0.18))
        case .c: return AnyShapeStyle(Brand.warning.opacity(0.18))
        case .d: return AnyShapeStyle(Brand.danger.opacity(0.16))
        case .f: return AnyShapeStyle(Brand.danger.opacity(0.22))
        }
    }

    private func gradeStroke(_ grade: ShipperCatalystScorecardStore.MergedRow.Grade) -> Color {
        switch grade {
        case .a: return Brand.success.opacity(0.6)
        case .b: return Brand.info.opacity(0.6)
        case .c: return Brand.warning.opacity(0.6)
        case .d, .f: return Brand.danger.opacity(0.6)
        }
    }

    private func gradeForeground(_ grade: ShipperCatalystScorecardStore.MergedRow.Grade) -> Color {
        switch grade {
        case .a: return Brand.success
        case .b: return Brand.info
        case .c: return Brand.warning
        case .d, .f: return Brand.danger
        }
    }

    private func starsRow(_ count: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                let filled = Double(i) + 0.5 <= count
                let half   = !filled && Double(i) + 0.0 < count && count < Double(i) + 1.0
                Image(systemName: half ? "star.leadinghalf.filled" : (filled ? "star.fill" : "star"))
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(filled || half ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
            }
            Text(String(format: "%.1f", count))
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textSecondary)
                .padding(.leading, 4)
                .monospacedDigit()
        }
    }

    private func microPair(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Scorecards unavailable")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(msg)
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                Task { await store.refresh() }
            } label: {
                Text("Retry")
                    .font(EType.bodyStrong)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s4)
                    .padding(.vertical, Space.s2)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func formatThousands(_ value: Double) -> String {
        let n = Int(value.rounded())
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000    { return String(format: "%.0fk", Double(n) / 1_000) }
        if n >= 1_000     { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }
}

// MARK: - Press feedback

/// Mirrors the Driver doctrine §B.4 row-press recipe — 0.12s easeOut
/// + 0.985 scale on press, no haptic (rows aren't primary CTAs; the
/// haptic budget is reserved for `CTAButton`).
private struct CatalystRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Detail sheet

private struct CatalystDetailSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let row: ShipperCatalystScorecardStore.MergedRow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s4) {
                heroCard
                lifetimeCard
                periodCard
                whyThisGradeCard
                Color.clear.frame(height: 48)
            }
            .padding(Space.s4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.bgPage.ignoresSafeArea())
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.grade.rawValue)
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                Text(String(format: "%.1f / 5", row.starCount))
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textSecondary)
                Spacer()
            }
            Text(row.name)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            if let dot = row.dotNumber, !dot.isEmpty {
                Text("DOT \(dot)")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(LinearGradient(
                    colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var periodCard: some View {
        sectionCard(title: "THIS WINDOW") {
            VStack(spacing: 6) {
                kvRow("Loads", value: row.totalLoads > 0 ? "\(row.totalLoads)" : "—")
                kvRow("Delivered", value: row.totalLoads > 0 ? "\(row.delivered)" : "—")
                kvRow("On-time rate", value: row.totalLoads > 0 ? "\(row.onTimeRate)%" : "—")
                kvRow("Total spend", value: row.totalSpend > 0 ? formatMoney(row.totalSpend) : "—")
            }
        }
    }

    private var lifetimeCard: some View {
        sectionCard(title: "LIFETIME") {
            VStack(spacing: 6) {
                kvRow("Loads completed", value: "\(row.lifetimeLoads)")
                kvRow("Lifetime spend", value: formatMoney(row.lifetimeSpend))
            }
        }
    }

    private var whyThisGradeCard: some View {
        sectionCard(title: "WHY THIS GRADE") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Score = on-time × 50% + completion × 30% + volume × 20% (log-scaled).")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("90+ → A · 80–89 → B · 70–79 → C · 60–69 → D · <60 → F")
                    .font(EType.micro).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text(title)
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            content()
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func kvRow(_ key: String, value: String) -> some View {
        HStack {
            Text(key)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
        }
    }

    private func formatMoney(_ value: Double) -> String {
        let n = Int(value.rounded())
        if n >= 1_000_000 { return String(format: "$%.1fM", Double(n) / 1_000_000) }
        if n >= 10_000    { return String(format: "$%.0fk", Double(n) / 1_000) }
        return "$\(n)"
    }
}

// MARK: - Previews

#Preview("213 · Catalyst Scorecards · Night") {
    ShipperCatalystScorecard()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("213 · Catalyst Scorecards · Afternoon") {
    ShipperCatalystScorecard()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
