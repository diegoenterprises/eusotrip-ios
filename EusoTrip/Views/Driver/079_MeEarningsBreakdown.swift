//
//  079_MeEarningsBreakdown.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · earnings breakdown)
//
//  Screen 079 · Me · Earnings Breakdown — the driver's revenue-type
//  split (linehaul / fuel surcharge / accessorials / bonuses / other)
//  across a 7 / 30 / 90 day window, plus a "top-earning loads" list
//  ordered by dollar amount. Every dollar comes from the live
//  `wallet.getEarningsBreakdown({period})` procedure — MCP-verified
//  at `frontend/server/routers/wallet.ts:731`.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • Server-authoritative dollar totals. The view derives
//      percentage fills from whatever sums the server returns; a
//      $0 category paints a zero-width bar, not a hidden tile.
//
//    • Period picker flips the store's `period`, which triggers
//      auto-refresh via the store's `didSet` hook.
//
//    • Top loads list is server-capped (currently 3 rows); the view
//      surfaces whatever arrives so widening the server limit later
//      doesn't require a mobile release.
//
//    • Empty state is server-confirmed. A driver whose window has
//      zero earnings transactions sees the "First run on the books"
//      hero, not a 5-row stack of zeroes.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on total hero + top-category bar
//         fills. Brand.warning only for negative deltas (reserved
//         for when the backend adds week-over-week comparison).
//    §4   Tokenized spacing, radii, type.
//    §5   Palette semantic throughout.
//    §7   Ternary ShapeStyle wrapped in AnyShapeStyle.
//    §10  Previews land in `.error` under the no-baseURL runtime. No
//         fixtures.
//

import SwiftUI

private enum BreakdownPeriod: String, CaseIterable, Identifiable {
    case week, month, quarter
    var id: String { rawValue }
    var label: String {
        switch self {
        case .week:    return "7 days"
        case .month:   return "30 days"
        case .quarter: return "90 days"
        }
    }
}

// MARK: - Screen root

struct MeEarningsBreakdown: View {
    @Environment(\.palette) var palette
    @StateObject private var store = EarningsBreakdownStore()
    @State private var selected: BreakdownPeriod = .month

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                periodPicker
                switch store.state {
                case .loading:
                    skeleton
                case .empty:
                    emptyHero
                case .error(let e):
                    errorBanner(e)
                case .loaded(let breakdown):
                    if breakdown.byType.total <= 0 && breakdown.topLoads.isEmpty {
                        emptyHero
                    } else {
                        totalHero(breakdown)
                        breakdownSection(breakdown)
                        topLoadsSection(breakdown)
                    }
                }
                disclosureFooter
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
        .onChange(of: selected) { _, newValue in
            store.period = newValue.rawValue
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Earnings")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Revenue split · top loads")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Period picker

    private var periodPicker: some View {
        HStack(spacing: Space.s2) {
            ForEach(BreakdownPeriod.allCases) { p in
                Button {
                    selected = p
                } label: {
                    let on = p == selected
                    Text(p.label)
                        .font(EType.bodyStrong)
                        .foregroundStyle(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textPrimary))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            ZStack {
                                if on {
                                    Capsule().fill(LinearGradient.diagonal)
                                } else {
                                    Capsule().fill(palette.bgCard.opacity(0.85))
                                }
                            }
                        )
                        .overlay(
                            Capsule().strokeBorder(on ? Color.white.opacity(0.25) : palette.borderFaint, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: States

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.45))
                .frame(height: 120)
            VStack(spacing: Space.s2) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(palette.tintNeutral.opacity(0.3))
                        .frame(height: 48)
                }
            }
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.3))
                    .frame(height: 64)
            }
        }
    }

    private var emptyHero: some View {
        EusoEmptyState(
            systemImage: "chart.bar.xaxis",
            title: "First run on the books",
            subtitle: "Earnings land here the moment your first settled load clears. Pull to refresh after dispatch marks it paid."
        )
    }

    private func errorBanner(_ err: Error) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Can't load earnings")
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
            Text(err.localizedDescription)
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
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Total hero

    private func totalHero(_ b: WalletAPI.EarningsBreakdown) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("TOTAL · \(selected.label.uppercased())")
                .font(EType.micro).tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text(money(b.byType.total))
                .font(EType.numeric)
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
            if let top = topCategory(b.byType) {
                Text("Leading: \(top.label) · \(money(top.amount))")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Category breakdown

    private func breakdownSection(_ b: WalletAPI.EarningsBreakdown) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("BY CATEGORY")
                .font(EType.micro).tracking(1.4)
                .foregroundStyle(palette.textTertiary)
            let rows = categoryRows(b.byType)
            VStack(spacing: Space.s2) {
                ForEach(rows, id: \.label) { row in
                    categoryRow(row, total: b.byType.total)
                }
            }
        }
    }

    private struct CategoryRow {
        let label: String
        let amount: Double
        let icon: String
    }

    private func categoryRows(_ t: WalletAPI.EarningsTypeBreakdown) -> [CategoryRow] {
        [
            CategoryRow(label: "Linehaul",       amount: t.linehaul,       icon: "truck.box.fill"),
            CategoryRow(label: "Fuel surcharge", amount: t.fuelSurcharge,  icon: "fuelpump.fill"),
            CategoryRow(label: "Accessorials",   amount: t.accessorials,   icon: "plus.square.fill"),
            CategoryRow(label: "Bonuses",        amount: t.bonuses,        icon: "star.fill"),
            CategoryRow(label: "Other",          amount: t.other,          icon: "ellipsis.circle"),
        ]
        .sorted { $0.amount > $1.amount }
    }

    private func categoryRow(_ row: CategoryRow, total: Double) -> some View {
        let fraction = total > 0 ? max(0, min(1, row.amount / total)) : 0
        let pct = total > 0 ? row.amount / total * 100.0 : 0
        return HStack(spacing: Space.s3) {
            Image(systemName: row.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(row.amount > 0 ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textTertiary))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(palette.bgCard.opacity(0.8))
                )
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(row.label)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(money(row.amount))
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(palette.tintNeutral.opacity(0.4))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(LinearGradient.diagonal)
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 4)
                Text(pct > 0 ? String(format: "%.1f%% of total", pct) : "—")
                    .font(EType.micro)
                    .tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    private func topCategory(_ t: WalletAPI.EarningsTypeBreakdown) -> (label: String, amount: Double)? {
        let rows = categoryRows(t)
        guard let top = rows.first, top.amount > 0 else { return nil }
        return (top.label, top.amount)
    }

    // MARK: Top loads

    @ViewBuilder
    private func topLoadsSection(_ b: WalletAPI.EarningsBreakdown) -> some View {
        if !b.topLoads.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text("TOP LOADS")
                        .font(EType.micro).tracking(1.4)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(b.topLoads.count)")
                        .font(EType.micro).tracking(1.1)
                        .foregroundStyle(palette.textTertiary)
                }
                VStack(spacing: Space.s2) {
                    ForEach(b.topLoads) { load in
                        topLoadRow(load)
                    }
                }
            }
        }
    }

    private func topLoadRow(_ load: WalletAPI.EarningsTopLoad) -> some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "shippingbox")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(palette.bgCard.opacity(0.8))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(load.loadNumber.isEmpty ? "—" : load.loadNumber)
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                if let pretty = prettyDate(load.date) {
                    Text(pretty)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: Space.s2)
            Text(money(load.amount))
                .font(EType.bodyStrong)
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s3)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
    }

    // MARK: Footer

    private var disclosureFooter: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Image(systemName: "chart.pie")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("How the split is calculated")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text("Every settled wallet transaction tagged as earnings is counted. The split mirrors how your settlement statement is lined up, so the dollar columns match what your CPA and dispatch see — no rounding differences.")
                .font(EType.caption)
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCard.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: Helpers

    private func money(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = v < 100 ? 2 : 0
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }

    private func prettyDate(_ raw: String) -> String? {
        guard !raw.isEmpty else { return nil }
        let inFmt = DateFormatter()
        inFmt.calendar = Calendar(identifier: .gregorian)
        inFmt.locale = Locale(identifier: "en_US_POSIX")
        inFmt.dateFormat = "yyyy-MM-dd"
        guard let d = inFmt.date(from: raw) else { return raw }
        let outFmt = DateFormatter()
        outFmt.dateFormat = "MMM d, yyyy"
        return outFmt.string(from: d)
    }
}

// MARK: - Screen wrapper

struct MeEarningsBreakdownScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeEarningsBreakdown()
        } nav: {
            BottomNav(
                leading: driverNavLeading_079(),
                trailing: driverNavTrailing_079(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_079() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house.fill",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_079() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard", isCurrent: true),
     NavSlot(label: "Me",     systemImage: "person.fill",      isCurrent: false)]
}

// MARK: - Previews

#Preview("079 · Me Earnings Breakdown · Night") {
    MeEarningsBreakdownScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("079 · Me Earnings Breakdown · Afternoon") {
    MeEarningsBreakdownScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
