//
//  094_MeFuelCards.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · Fuel Cards)
//
//  Screen 094 · Me · Fuel Cards — the driver's fuel-spend cockpit.
//  Hero shows total spend + average MPG + cost-per-mile with
//  month-over-month trend arrows. "My cards" lists the signed-in
//  driver's assigned fuel cards (filtered out of the company-wide
//  admin feed) with daily / monthly utilization bars. Monthly-spend
//  sparkline shows the last few months of fuel outflow.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • Dashboard from `fuelManagement.getFuelDashboard` — MCP-
//      verified at `frontend/server/routers/fuelManagement.ts`.
//      Server computes 30-day vs 60-day trends live from
//      `fuel_transactions` rows; the trend arrows you see are
//      the real delta vs. the prior 30-day window.
//    • Cards from `fuelManagement.getFuelCardManagement` — server
//      ships the whole company roster (admin surface); we narrow
//      to the signed-in driver's `driverId` before rendering so
//      drivers only see their own cards. Last four digits + card
//      type + daily / monthly / total spent are all server-
//      provided.
//    • No fabricated utilization bars. When the server ships a
//      zero limit the row collapses the bar and surfaces "—" so
//      the driver never sees a fake "35% of $0."
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on hero spend + active card.
//         Brand.warning when daily utilization > 80%. Brand.magenta
//         on suspended cards.
//    §4   Tokenized Space/Radius/EType throughout.
//

import SwiftUI

// MARK: - Screen root

struct MeFuelCards: View {
    @Environment(\.palette) var palette
    @EnvironmentObject private var session: EusoTripSession
    @StateObject private var store = FuelCardsStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                dashboardHero
                trendStrip
                sparkline
                myCardsSection
                footer
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await seedAndRefresh() }
        .refreshable { await seedAndRefresh() }
        .onChange(of: session.user?.id) { _, newId in
            store.driverId = newId ?? ""
            Task { await store.refresh() }
        }
    }

    private func seedAndRefresh() async {
        store.driverId = session.user?.id ?? ""
        await store.refresh()
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Fuel Cards")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Spend · MPG · cost/mile")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Dashboard hero

    private var dashboardHero: some View {
        let d = store.dashboard
        return VStack(spacing: Space.s3) {
            Text("SPEND · LAST 30 DAYS")
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text(currency(d?.totalSpend ?? 0))
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
            HStack(spacing: Space.s4) {
                miniStat(label: "GAL", value: compactNumber(d?.totalGallons ?? 0))
                miniStat(label: "MILES", value: compactNumber(d?.totalMiles ?? 0))
                miniStat(label: "MPG", value: String(format: "%.1f", d?.avgMpg ?? 0))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func miniStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(EType.micro)
                .tracking(1.2)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Trend strip

    private var trendStrip: some View {
        let t = store.dashboard?.trends
        return HStack(spacing: Space.s2) {
            trendTile(
                label: "SPEND",
                value: percentFmt(t?.spendChange ?? 0),
                positive: (t?.spendChange ?? 0) <= 0   // lower spend = good
            )
            trendTile(
                label: "MPG",
                value: percentFmt(t?.mpgChange ?? 0),
                positive: (t?.mpgChange ?? 0) >= 0     // higher MPG = good
            )
            trendTile(
                label: "CPM",
                value: percentFmt(t?.costPerMileChange ?? 0),
                positive: (t?.costPerMileChange ?? 0) <= 0  // lower CPM = good
            )
        }
    }

    private func trendTile(label: String, value: String, positive: Bool) -> some View {
        let up = value.hasPrefix("+")
        let icon = up ? "arrow.up.right" : (value == "0%" ? "minus" : "arrow.down.right")
        let tint: Color = positive ? .green : Brand.warning
        return VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(value)
                    .font(EType.bodyStrong)
                    .monospacedDigit()
            }
            .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Sparkline

    @ViewBuilder
    private var sparkline: some View {
        if let monthly = store.dashboard?.monthlySpend, !monthly.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text("MONTHLY SPEND")
                        .font(EType.micro)
                        .tracking(1.3)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text(latestMonthLabel(monthly))
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                GeometryReader { geo in
                    let maxAmount = max(1, monthly.map(\.amount).max() ?? 1)
                    HStack(alignment: .bottom, spacing: Space.s1) {
                        ForEach(monthly) { m in
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(LinearGradient.diagonal)
                                    .frame(height: max(4, (m.amount / maxAmount) * (geo.size.height - 16)))
                                Text(shortMonth(m.month))
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundStyle(palette.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: 80)
            }
            .padding(Space.s3)
            .eusoCard(radius: Radius.md)
        }
    }

    // MARK: My cards

    private var myCardsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("MY CARDS")
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            if store.myCards.isEmpty && !store.isLoading {
                EusoEmptyState(
                    systemImage: "creditcard",
                    title: "No fuel card assigned",
                    subtitle: "Your carrier assigns fuel cards from the fleet admin surface. Once one is linked to your driver profile it'll show up here with live utilization."
                )
            } else {
                ForEach(store.myCards) { c in
                    cardRow(c)
                }
            }
        }
    }

    private func cardRow(_ c: FuelManagementAPI.FuelCard) -> some View {
        let status = (c.status ?? "active").lowercased()
        let isActive = status == "active"
        let dailyUtil = c.dailyLimit > 0 ? c.dailySpent / c.dailyLimit : 0
        let monthlyUtil = c.monthlyLimit > 0 ? c.monthlySpent / c.monthlyLimit : 0
        return VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text((c.cardType ?? "Fuel Card").capitalized)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(c.cardNumber)
                        .font(EType.caption.monospaced())
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                statusChip(status)
            }

            if c.dailyLimit > 0 {
                utilBar(
                    label: "Today",
                    spent: c.dailySpent,
                    limit: c.dailyLimit,
                    utilization: dailyUtil
                )
            }
            if c.monthlyLimit > 0 {
                utilBar(
                    label: "Month",
                    spent: c.monthlySpent,
                    limit: c.monthlyLimit,
                    utilization: monthlyUtil
                )
            }

            HStack {
                if let exp = c.expirationDate, !exp.isEmpty {
                    Text("Expires \(humanizeDate(exp))")
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                if c.fuelOnly == true {
                    Label("Fuel only", systemImage: "fuelpump")
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                }
            }

            if !isActive {
                Text("This card is \(status). Tap support to reactivate.")
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
            }
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    private func utilBar(label: String, spent: Double, limit: Double, utilization: Double) -> some View {
        let urgent = utilization >= 0.8
        let capped = max(0, min(1, utilization))
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(currency(spent)) / \(currency(limit))")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.tintNeutral.opacity(0.5))
                    Capsule()
                        .fill(urgent
                              ? AnyShapeStyle(Brand.warning)
                              : AnyShapeStyle(LinearGradient.diagonal))
                        .frame(width: max(4, geo.size.width * capped))
                }
            }
            .frame(height: 5)
        }
    }

    @ViewBuilder
    private func statusChip(_ status: String) -> some View {
        switch status {
        case "active":
            Text("ACTIVE")
                .font(EType.micro).tracking(1.2)
                .foregroundStyle(.white)
                .padding(.horizontal, Space.s2).padding(.vertical, 3)
                .background(Capsule().fill(LinearGradient.diagonal))
        case "suspended":
            Text("SUSPENDED")
                .font(EType.micro).tracking(1.2)
                .foregroundStyle(Brand.magenta)
                .padding(.horizontal, Space.s2).padding(.vertical, 3)
                .overlay(Capsule().stroke(Brand.magenta, lineWidth: 1))
        case "cancelled":
            Text("CANCELLED")
                .font(EType.micro).tracking(1.2)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, Space.s2).padding(.vertical, 3)
                .overlay(Capsule().stroke(palette.textTertiary.opacity(0.55), lineWidth: 1))
        default:
            Text(status.uppercased())
                .font(EType.micro).tracking(1.2)
                .foregroundStyle(palette.textTertiary)
                .padding(.horizontal, Space.s2).padding(.vertical, 3)
                .overlay(Capsule().stroke(palette.textTertiary.opacity(0.4), lineWidth: 1))
        }
    }

    // MARK: Footer

    private var footer: some View {
        Text("Daily + monthly limits are set by your carrier admin. If you need a temporary lift (long haul or hazmat surcharge), open a ticket from Me · Support.")
            .font(EType.caption)
            .foregroundStyle(palette.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Space.s2)
    }

    // MARK: Helpers

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }

    private func compactNumber(_ value: Double) -> String {
        if value >= 100_000 {
            return String(format: "%.0fK", value / 1000.0)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", value / 1000.0)
        }
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private func percentFmt(_ value: Double) -> String {
        if value == 0 { return "0%" }
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(Int(value.rounded()))%"
    }

    private func humanizeDate(_ iso: String) -> String {
        let inF = DateFormatter()
        inF.dateFormat = "yyyy-MM-dd"
        inF.locale = Locale(identifier: "en_US_POSIX")
        let altF = ISO8601DateFormatter()
        let date = inF.date(from: String(iso.prefix(10))) ?? altF.date(from: iso)
        guard let date else { return iso }
        let out = DateFormatter()
        out.dateFormat = "MMM yyyy"
        return out.string(from: date)
    }

    private func shortMonth(_ raw: String) -> String {
        // Server ships month as "Jan", "2026-03", or "2026-03-01" —
        // be forgiving about any of those shapes.
        let s = String(raw.prefix(7))
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM"
        if let date = df.date(from: s) {
            let out = DateFormatter()
            out.dateFormat = "MMM"
            return out.string(from: date)
        }
        return String(raw.prefix(3)).capitalized
    }

    private func latestMonthLabel(_ months: [FuelManagementAPI.MonthSpend]) -> String {
        guard let last = months.last else { return "" }
        return shortMonth(last.month)
    }
}

// MARK: - Screen wrapper

struct MeFuelCardsScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeFuelCards()
        } nav: {
            BottomNav(
                leading: driverNavLeading_094(),
                trailing: driverNavTrailing_094(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_094() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_094() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "wallet.pass", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("094 · Fuel Cards · Night") {
    MeFuelCardsScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("094 · Fuel Cards · Afternoon") {
    MeFuelCardsScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
