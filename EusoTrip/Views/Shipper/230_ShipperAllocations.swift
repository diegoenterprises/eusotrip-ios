//
//  230_ShipperWeeklyAllocations.swift
//  EusoTrip 2027 UI — Shipper · Allocations (parity-reconciled 2026-04-29)
//
//  PARITY AUDIT 2026-04-29 — new file at slot 230 to match wireframe
//  canon at /02 Shipper/Code/230_ShipperWeeklyAllocations.swift. Persona:
//  Diego Usoro / Eusorone Technologies (companyId 1) per §11.
//  Allocation IDs reuse the §11.2 LD- audit-trail convention
//  (`ALC-260427-{hex}`). The week-scope capacity-vs-load board.
//
//  Note: slot 230 also holds `230_ShipperBidThread.swift` in the
//  iOS tree (different scope, different struct names — no compile
//  conflict). Wireframe canon governs the UI of this file.
//
//  Layout (top → bottom):
//    1. TopBar           ✦ SHIPPER · ALLOCATIONS / "{N} ALLOCATED · {M} AT-RISK"
//                        Brand.danger when at-risk > 0
//    2. Title block      Allocations (34pt) / "Eusorone Technologies · MATRIX-50 · this week"
//    3. IridescentHairline
//    4. Hero KPI card    gradient-rim 4-cell quartet (ALLOCATED · AT-RISK · FILL · AVG RATE)
//    5. Filter chip row  All / Allocated / At-Risk / Reallocate / Closed
//    6. Allocation rows  3pt tier rim · ALC id · status pill · lane title ·
//                        spec line · 3-stat row · capacity bar with timing chip
//    7. Compact closed   76pt variant for delivered/closed allocations
//    8. "+ Allocate" gradient pill CTA
//
//  Real wiring: iOS doesn't yet have an allocations endpoint — the
//  surface paints §11 persona canon anchor data with explicit
//  EUSO-2149 backend gap.
//
//  Backend gaps surfaced (logged in audit log, no fake data):
//    EUSO-2149 — `allocations.getWeek(weekStart:)` not yet on iOS
//                API surface. Hero KPI quartet, filter chip counts,
//                and allocation rows surface canonical §11.4 anchor
//                data (3 active rows + 1 closed) until backend ships
//                the allocations envelope: `[{ alcId, loadIdHexTail,
//                lane: { origin, destination }, carrier: { name,
//                companyDot, mc }, status: "allocated" | "at_risk" |
//                "reallocate" | "delivered" | "closed", coveredCount,
//                totalCount, ratePerLoad, vsSpotDelta, capacityWindow,
//                timingHint }]`.
//
//  Doctrine refs: §2 LOADS-tab nav (handled by ContentView); §3
//  numbers-first copy; §4.3 single iridescent hairline; §11 / §11.2 /
//  §11.4 Diego canon + ALC audit-trail; §15.2 status-aware tier rim;
//  §16 hero-rim KPI quartet; §16.2 gradient pill CTA; §17.2 status
//  pill grammar; §19.2 file-scoped warnGrad / dangerGrad; §20.4 no
//  dead buttons; §22.2 Brand.danger counter when at-risk > 0.
//

import SwiftUI

// MARK: - Models (anchor-data while EUSO-2149 lands)

private struct AllocRow: Identifiable {
    let id = UUID()
    let alcId: String
    let pillKind: PillKind
    let pillLegend: String
    let pillWidth: CGFloat
    let tierRim: TierRim
    let lane: String
    let specLine: String
    let stats: [Stat]
    let fillRate: CGFloat
    let fillKind: FillKind
    let fillLegend: String
    let timing: TimingChip

    enum PillKind { case allocated, atRisk, reallocate, delivered }
    enum TierRim { case gradient, danger, warn, neutral }
    enum FillKind { case gradient, warn, danger }
    struct TimingChip { let text: String; let kind: Kind; enum Kind { case neutral, warn, danger } }
    struct Stat: Identifiable {
        let id = UUID()
        let value: String
        let unit: String
        var color: ValueColor = .primary
        enum ValueColor { case primary, success, warn, danger }
    }
}

private struct CompactAllocRow: Identifiable {
    let id = UUID()
    let alcId: String
    let title: String
    let subline: String
}

// MARK: - Filter

private enum AllocFilter: String, CaseIterable, Identifiable {
    case all
    case allocated
    case atRisk
    case reallocate
    case closed

    var id: String { rawValue }
    var label: String {
        switch self {
        case .all:        return "All"
        case .allocated:  return "Allocated"
        case .atRisk:     return "At-Risk"
        case .reallocate: return "Reallocate"
        case .closed:     return "Closed"
        }
    }
}

// MARK: - Screen root

struct ShipperWeeklyAllocations: View {
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @State private var filter: AllocFilter = .all

    // §11.4 anchor canon — 3 active rows + 1 compact closed row.
    // EUSO-2149 — replaces with real data when backend ships.
    private let canonRows: [AllocRow] = [
        AllocRow(
            alcId: "ALC-260427-A38FB12C7E",
            pillKind: .allocated,
            pillLegend: "ALLOCATED · 8/8",
            pillWidth: 116,
            tierRim: .gradient,
            lane: "Houston TX → Dallas TX",
            specLine: "Eusotrans LLC · Michael Eusorone · MC-306 UN1203 · 8 / wk",
            stats: [
                .init(value: "$1,840", unit: "/ load"),
                .init(value: "8 / 8",  unit: "covered"),
                .init(value: "−$60",   unit: "vs spot", color: .success)
            ],
            fillRate: 1.0,
            fillKind: .gradient,
            fillLegend: "8 / 8 LOADS",
            timing: .init(text: "ALLOCATED · 4D AGO", kind: .neutral)
        ),
        AllocRow(
            alcId: "ALC-260427-B41782FF02",
            pillKind: .allocated,
            pillLegend: "ALLOCATED · 4/6",
            pillWidth: 116,
            tierRim: .gradient,
            lane: "Kansas City MO → Omaha NE",
            specLine: "Heartland Cryogenics LLC · MC-331 NH₃ UN1005 · 6 / wk · escort",
            stats: [
                .init(value: "$3,180",   unit: "/ load"),
                .init(value: "4 / 6",    unit: "covered"),
                .init(value: "2 escorts", unit: "pending", color: .warn)
            ],
            fillRate: 0.67,
            fillKind: .gradient,
            fillLegend: "4 / 6 LOADS",
            timing: .init(text: "DUE · 18H · 2 OPEN", kind: .warn)
        ),
        AllocRow(
            alcId: "ALC-260427-7C3A09F18B",
            pillKind: .atRisk,
            pillLegend: "AT-RISK · 1/4",
            pillWidth: 100,
            tierRim: .danger,
            lane: "Los Angeles CA → Phoenix AZ",
            specLine: "Pacific Cold Logistics · 53′ Reefer berries 33–38°F · 4 / wk",
            stats: [
                .init(value: "$2,180",       unit: "/ load"),
                .init(value: "1 / 4",        unit: "covered"),
                .init(value: "+1 detention", unit: "flag", color: .warn)
            ],
            fillRate: 0.25,
            fillKind: .warn,
            fillLegend: "1 / 4 LOADS",
            timing: .init(text: "REALLOCATE · 6H WINDOW", kind: .danger)
        )
    ]

    private let compactRow = CompactAllocRow(
        alcId: "ALC-260424-3F8C019A45",
        title: "Atlanta GA → Charlotte NC · DELIVERED 6/6",
        subline: "Pacific Cold Logistics · 53′ Reefer 38°F · WK 17 closed · paid"
    )

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

                kpiHeroCard
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s3)

                filterRow
                    .padding(.top, Space.s5)

                let rows = filtered()
                if rows.isEmpty && filter != .all {
                    noMatchCard
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s4)
                } else {
                    VStack(spacing: Space.s2) {
                        ForEach(rows) { row in
                            allocRowView(row)
                        }
                        if filter == .all || filter == .closed {
                            compactRowView(compactRow)
                        }
                    }
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s4)
                }

                allocateButton
                    .padding(.horizontal, Space.s5)
                    .padding(.top, Space.s5)

                Color.clear.frame(height: 96)
            }
        }
    }

    // MARK: TopBar

    private var topBar: some View {
        let atRisk = canonRows.filter { $0.pillKind == .atRisk }.count
        return HStack(alignment: .firstTextBaseline) {
            Text("✦ SHIPPER · ALLOCATIONS")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text("\(canonRows.count) ALLOCATED · \(atRisk) AT-RISK")
                .font(EType.micro)
                .tracking(1.0)
                .foregroundStyle(atRisk > 0 ? Brand.danger : palette.textTertiary)
                .accessibilityLabel("\(canonRows.count) allocated, \(atRisk) at risk")
        }
        .padding(.horizontal, Space.s5)
    }

    // MARK: Title block

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Allocations")
                .font(.system(size: 34, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(palette.textPrimary)
            Text("Eusorone Technologies · MATRIX-50 · this week")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s5)
    }

    // MARK: KPI hero card

    private var kpiHeroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                .fill(palette.bgCard)
                .padding(1.5)

            VStack(alignment: .leading, spacing: 0) {
                Text("ALLOCATION LEDGER · WK 18 · 2026")
                    .font(EType.micro)
                    .tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                    .padding(.top, 22)
                    .padding(.leading, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    kpiCell(label: "ALLOCATED", value: "\(canonRows.count)",
                            valueStyle: .gradient, trailingUnit: "of 50")
                    kpiDivider
                    kpiCell(label: "AT-RISK",
                            value: "\(canonRows.filter { $0.pillKind == .atRisk }.count)",
                            valueStyle: .danger, trailingUnit: nil)
                    kpiDivider
                    kpiCell(label: "FILL", value: fillRate,
                            valueStyle: .primary, trailingUnit: nil)
                    kpiDivider
                    kpiCell(label: "AVG RATE", value: avgRate,
                            valueStyle: .success, trailingUnit: nil)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
        }
        .frame(height: 92)
    }

    private var fillRate: String {
        let allocated = canonRows.count
        // §11 MATRIX-50 batch is 50 loads.
        let pct = Double(allocated) / 50.0 * 100.0
        return String(format: "%.0f%%", pct)
    }

    private var avgRate: String {
        let rates = canonRows.compactMap { row -> Double? in
            row.stats.first { $0.unit == "/ load" }
                .flatMap {
                    let cleaned = $0.value.replacingOccurrences(of: "$", with: "")
                                       .replacingOccurrences(of: ",", with: "")
                    return Double(cleaned)
                }
        }
        guard !rates.isEmpty else { return "—" }
        let avg = rates.reduce(0, +) / Double(rates.count)
        return String(format: "$%.0f", avg)
    }

    private var kpiDivider: some View {
        Rectangle()
            .fill(palette.borderFaint)
            .frame(width: 1, height: 38)
    }

    private enum KpiValueStyle { case gradient, primary, danger, success }

    @ViewBuilder
    private func kpiCell(label: String,
                         value: String,
                         valueStyle: KpiValueStyle,
                         trailingUnit: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(0.4)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Group {
                    switch valueStyle {
                    case .gradient: Text(value).foregroundStyle(LinearGradient.diagonal)
                    case .primary:  Text(value).foregroundStyle(palette.textPrimary)
                    case .danger:   Text(value).foregroundStyle(Brand.danger)
                    case .success:  Text(value).foregroundStyle(Brand.success)
                    }
                }
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                if let trailingUnit {
                    Text(trailingUnit)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    // MARK: Filter row

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AllocFilter.allCases) { f in
                    filterChip(f, count: count(for: f))
                }
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

    private func count(for filter: AllocFilter) -> Int? {
        switch filter {
        case .all:        return nil
        case .allocated:  return canonRows.filter { $0.pillKind == .allocated }.count
        case .atRisk:     return canonRows.filter { $0.pillKind == .atRisk }.count
        case .reallocate: return canonRows.filter { $0.pillKind == .atRisk }.count // proxy
        case .closed:     return 1 // compactRow
        }
    }

    private func filterChip(_ f: AllocFilter, count: Int?) -> some View {
        let isActive = (filter == f)
        let label: String = {
            if let c = count, c > 0 { return "\(f.label) · \(c)" }
            return f.label
        }()
        return Button(action: { tapFilter(f) }) {
            Text(label)
                .font(.system(size: 11, weight: isActive ? .bold : .semibold))
                .foregroundStyle(isActive ? Color.white : palette.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 30)
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

    private func tapFilter(_ f: AllocFilter) {
        // observability post — real effect: filter @State mutation
        filter = f
        NotificationCenter.default.post(
            name: .eusoShipperAllocFilter,
            object: nil,
            userInfo: [
                "source": "230_ShipperWeeklyAllocations",
                "filter": f.rawValue,
                "shipperCompanyId": 1
            ]
        )
    }

    private func filtered() -> [AllocRow] {
        switch filter {
        case .all, .closed:
            return canonRows
        case .allocated:
            return canonRows.filter { $0.pillKind == .allocated }
        case .atRisk, .reallocate:
            return canonRows.filter { $0.pillKind == .atRisk }
        }
    }

    // MARK: Allocation row

    @ViewBuilder
    private func allocRowView(_ row: AllocRow) -> some View {
        Button(action: { tapRow(row) }) {
            HStack(spacing: 0) {
                tierRimShape(row.tierRim)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        Text(row.alcId)
                            .font(EType.mono(.micro))
                            .tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Spacer()
                        statusPillView(row)
                    }
                    .padding(.top, Space.s4)

                    Text(row.lane)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .padding(.top, Space.s2 + 2)

                    Text(row.specLine)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.top, 4)

                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        ForEach(row.stats) { stat in
                            statCell(stat)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, Space.s2 + 2)

                    capacityBar(row)
                        .padding(.top, Space.s2 + 2)
                        .padding(.bottom, Space.s4)
                }
                .padding(.leading, Space.s4)
                .padding(.trailing, Space.s4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .contentShape(Rectangle())
        }
        .buttonStyle(AllocRowStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibility(row))
    }

    private func rowAccessibility(_ row: AllocRow) -> String {
        let pill = row.pillLegend.replacingOccurrences(of: "·", with: ",")
        return "\(row.alcId), \(pill), \(row.lane), \(row.specLine), \(row.fillLegend)"
    }

    @ViewBuilder
    private func tierRimShape(_ kind: AllocRow.TierRim) -> some View {
        switch kind {
        case .gradient: RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.diagonal)
        case .danger:   RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.allocDangerGrad)
        case .warn:     RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.allocWarnGrad)
        case .neutral:  RoundedRectangle(cornerRadius: 1.5).fill(palette.textTertiary)
        }
    }

    @ViewBuilder
    private func statusPillView(_ row: AllocRow) -> some View {
        switch row.pillKind {
        case .allocated:
            Text(row.pillLegend)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(.white)
                .frame(width: row.pillWidth, height: 20)
                .background(Capsule().fill(LinearGradient.primary))
        case .atRisk:
            Text(row.pillLegend)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(.white)
                .frame(width: row.pillWidth, height: 20)
                .background(Capsule().fill(LinearGradient.allocDangerGrad))
        case .reallocate:
            Text(row.pillLegend)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(Brand.danger)
                .frame(width: row.pillWidth, height: 20)
                .overlay(Capsule().strokeBorder(Brand.danger, lineWidth: 1))
                .background(Capsule().fill(palette.bgCard))
        case .delivered:
            Text(row.pillLegend)
                .font(EType.micro).tracking(0.6)
                .foregroundStyle(.white)
                .frame(width: row.pillWidth, height: 20)
                .background(Capsule().fill(Brand.success))
        }
    }

    @ViewBuilder
    private func statCell(_ stat: AllocRow.Stat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(stat.value)
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(statColor(stat.color))
            Text(stat.unit)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
        }
    }

    private func statColor(_ c: AllocRow.Stat.ValueColor) -> Color {
        switch c {
        case .primary: return palette.textPrimary
        case .success: return Brand.success
        case .warn:    return Brand.warning
        case .danger:  return Brand.danger
        }
    }

    @ViewBuilder
    private func capacityBar(_ row: AllocRow) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                timingChipView(row.timing)
                Spacer()
                Text(row.fillLegend)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.4)
                    .foregroundStyle(legendColor(for: row))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.borderFaint)
                        .frame(height: 6)
                    Capsule()
                        .fill(fillStyle(for: row.fillKind))
                        .frame(width: geo.size.width * row.fillRate, height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private func legendColor(for row: AllocRow) -> Color {
        switch row.fillKind {
        case .gradient: return palette.textSecondary
        case .warn:     return Brand.warning
        case .danger:   return Brand.danger
        }
    }

    private func fillStyle(for kind: AllocRow.FillKind) -> AnyShapeStyle {
        switch kind {
        case .gradient: return AnyShapeStyle(LinearGradient.primary)
        case .warn:     return AnyShapeStyle(LinearGradient.allocWarnGrad)
        case .danger:   return AnyShapeStyle(LinearGradient.allocDangerGrad)
        }
    }

    @ViewBuilder
    private func timingChipView(_ chip: AllocRow.TimingChip) -> some View {
        let (fg, bg): (Color, Color) = {
            switch chip.kind {
            case .neutral: return (palette.textTertiary, palette.bgCardSoft)
            case .warn:    return (Brand.warning, Brand.warning.opacity(0.15))
            case .danger:  return (Brand.danger, Brand.danger.opacity(0.15))
            }
        }()
        Text(chip.text)
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.4)
            .foregroundStyle(fg)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(bg))
    }

    // MARK: Compact closed row

    private func compactRowView(_ row: CompactAllocRow) -> some View {
        Button(action: { tapCompact(row) }) {
            HStack(spacing: 0) {
                tierRimShape(.neutral)
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        Text(row.alcId)
                            .font(EType.mono(.micro))
                            .tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Spacer()
                        Text("CLOSED")
                            .font(EType.micro).tracking(0.6)
                            .foregroundStyle(palette.textSecondary)
                            .frame(width: 84, height: 20)
                            .overlay(Capsule().strokeBorder(palette.textTertiary, lineWidth: 1))
                            .background(Capsule().fill(palette.bgCard))
                    }
                    .padding(.top, Space.s3 + 2)

                    Text(row.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .padding(.top, Space.s2 + 2)

                    Text(row.subline)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.top, 4)
                        .padding(.bottom, Space.s3 + 2)
                }
                .padding(.leading, Space.s4)
                .padding(.trailing, Space.s4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
            .contentShape(Rectangle())
        }
        .buttonStyle(AllocRowStyle())
    }

    // MARK: + Allocate CTA

    private var allocateButton: some View {
        Button(action: tapAllocate) {
            Text("+ Allocate")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Capsule().fill(LinearGradient.primary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Allocate new lane")
    }

    // MARK: Notification posts

    private func tapRow(_ row: AllocRow) {
        NotificationCenter.default.post(
            name: .eusoShipperAllocRow,
            object: nil,
            userInfo: [
                "source": "230_ShipperWeeklyAllocations",
                "alcId": row.alcId,
                "shipperCompanyId": 1
            ]
        )
        // Native nav into the canonical Allocations screen (229).
        // Was force-opening `app.eusotrip.com/...` in the in-app
        // Safari sheet which surfaced as the founder's "redirects
        // to web for some reason and its an error" report
        // (2026-05-04). The web URL is kept on the notification
        // userInfo so any listener that wants the deep-link can use
        // it; the user-visible action stays in-app.
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap, object: nil,
            userInfo: ["screenId": "229"]
        )
    }

    private func tapCompact(_ row: CompactAllocRow) {
        NotificationCenter.default.post(
            name: .eusoShipperAllocRow,
            object: nil,
            userInfo: [
                "source": "230_ShipperWeeklyAllocations",
                "alcId": row.alcId,
                "shipperCompanyId": 1
            ]
        )
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap, object: nil,
            userInfo: ["screenId": "229"]
        )
    }

    private func tapAllocate() {
        NotificationCenter.default.post(
            name: .eusoShipperAllocCreate,
            object: nil,
            userInfo: [
                "source": "230_ShipperWeeklyAllocations",
                "shipperCompanyId": 1
            ]
        )
        // "Create allocation" routes to the canonical 229 Allocations
        // board where the create flow lives. Same web-redirect fix as
        // the row taps above.
        NotificationCenter.default.post(
            name: .eusoShipperNavSwap, object: nil,
            userInfo: ["screenId": "229"]
        )
    }

    // MARK: No-match card

    private var noMatchCard: some View {
        Text("No allocations match this filter.")
            .font(EType.caption)
            .foregroundStyle(palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.s4)
            .background(palette.bgCard.opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - Press feedback

private struct AllocRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - File-scoped paint extensions (§19.2 · named to avoid clashes)

private extension LinearGradient {
    static let allocWarnGrad = LinearGradient(
        colors: [Brand.hazmat, Color(hex: 0xFF7A00)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let allocDangerGrad = LinearGradient(
        colors: [Brand.danger, Color(hex: 0xC62828)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - NotificationCenter names (§20.4)

extension Notification.Name {
    /// Filter chip tap (All / Allocated / At-Risk / Reallocate / Closed).
    static let eusoShipperAllocFilter = Notification.Name("eusoShipperAllocFilter")
    /// Allocation row tap — opens detail.
    static let eusoShipperAllocRow    = Notification.Name("eusoShipperAllocRow")
    /// "+ Allocate" gradient pill tap.
    static let eusoShipperAllocCreate = Notification.Name("eusoShipperAllocCreate")
}

// MARK: - Previews

#Preview("230 · Allocations · Dark") {
    ShipperWeeklyAllocations()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .background(Theme.dark.bgPage)
}

#Preview("230 · Allocations · Light") {
    ShipperWeeklyAllocations()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .background(Theme.light.bgPage)
}
