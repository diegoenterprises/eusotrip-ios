//
//  095_MeRateIntel.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · Rate Intel)
//
//  Screen 095 · Me · Rate Intel — rate-trend + forecast cockpit for
//  owner-operators + dispatchers. Hero shows the current-window
//  average rate + delta vs. the prior window + direction arrow.
//  Forecast strip surfaces the server's next-week + next-month
//  forecast (with real model-confidence). Factor list shows what
//  the server attributes the trend to — if any.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • Trend + forecast ship from `rates.getTrends` — MCP-verified
//      at `frontend/server/routers/rates.ts`. Server computes the
//      current window from delivered loads in the period and
//      compares to the immediately-prior window of the same
//      length.
//    • Equipment + period are driver-adjustable. Changing either
//      re-runs the query against the live server.
//    • Forecast confidence is the server's own estimate — we
//      render it verbatim as a percentage; we do NOT synthesize
//      our own confidence number.
//    • Factor list appears only when the server actually returned
//      attribution rows. No placeholders.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on hero avg + forecast up chip.
//         Brand.warning on watch-level chg, Brand.magenta on drop.
//    §4   Tokenized Space/Radius/EType throughout.
//

import SwiftUI

// MARK: - Screen root

struct MeRateIntel: View {
    @Environment(\.palette) var palette
    @StateObject private var store = RateIntelStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                selectors
                trendHero
                forecastStrip
                factorsSection
                footer
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("Rate Intel")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Market trend · forecast · negotiation floor")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbeSang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Selectors

    private var selectors: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("FILTERS")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
            }
            HStack(spacing: Space.s2) {
                Menu {
                    ForEach(RatesAPI.Equipment.allCases) { e in
                        Button(e.label) {
                            store.equipment = e
                            Task { await store.refresh() }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "truck.box")
                        Text(store.equipment.label)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s2)
                    .overlay(
                        Capsule().stroke(palette.textTertiary.opacity(0.5), lineWidth: 1)
                    )
                }

                Menu {
                    ForEach(RatesAPI.Period.allCases) { p in
                        Button(p.label) {
                            store.period = p
                            Task { await store.refresh() }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        Text(store.period.label)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s2)
                    .overlay(
                        Capsule().stroke(palette.textTertiary.opacity(0.5), lineWidth: 1)
                    )
                }
                Spacer()
            }
        }
    }

    // MARK: Trend hero

    private var trendHero: some View {
        let t = store.trends
        let direction = (t?.trend ?? "stable").lowercased()
        let pct = t?.changePercent ?? 0
        let (icon, tint): (String, Color) = {
            switch direction {
            case "up":   return ("arrow.up.right",   .green)
            case "down": return ("arrow.down.right", Brand.magenta)
            default:     return ("equal",            palette.textSecondary)
            }
        }()
        return VStack(spacing: Space.s3) {
            if t != nil {
                Text("AVERAGE RATE · \(store.period.label.uppercased())")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                Text(currency(t?.currentAvg ?? 0))
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                    Text(percentDelta(pct))
                        .font(EType.bodyStrong)
                        .monospacedDigit()
                    Text("vs prior \(store.period.label)")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
                .foregroundStyle(tint)

                if let prev = t?.previousAvg, prev > 0 {
                    Text("Prior avg \(currency(prev))")
                        .font(EType.micro)
                        .foregroundStyle(palette.textTertiary)
                }
            } else if store.isLoading {
                ProgressView()
                    .frame(height: 100)
            } else if let err = store.lastError {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                    Text(err.localizedDescription)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                        .multilineTextAlignment(.center)
                }
            } else {
                EusoEmptyState(
                    systemImage: "chart.line.uptrend.xyaxis",
                    title: "No rate history in this window",
                    subtitle: "Trends will surface once delivered loads in the selected window have landed."
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s5)
        .eusoCard(radius: Radius.lg)
    }

    // MARK: Forecast strip

    @ViewBuilder
    private var forecastStrip: some View {
        if let t = store.trends {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack {
                    Text("FORECAST")
                        .font(EType.micro)
                        .tracking(1.3)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    confidenceChip(t.forecast.confidence)
                }
                HStack(spacing: Space.s2) {
                    forecastTile(
                        label: "NEXT WEEK",
                        value: currency(t.forecast.nextWeek),
                        delta: t.forecast.nextWeek - t.currentAvg
                    )
                    forecastTile(
                        label: "NEXT MONTH",
                        value: currency(t.forecast.nextMonth),
                        delta: t.forecast.nextMonth - t.currentAvg
                    )
                }
            }
        }
    }

    private func forecastTile(label: String, value: String, delta: Double) -> some View {
        let positive = delta >= 0
        let arrow = positive ? "arrow.up.right" : "arrow.down.right"
        let tint: Color = positive ? .green : Brand.magenta
        return VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.numeric)
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
            HStack(spacing: 3) {
                Image(systemName: arrow)
                    .font(.system(size: 10, weight: .bold))
                Text(currency(abs(delta)))
                    .font(EType.caption)
                    .monospacedDigit()
            }
            .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    private func confidenceChip(_ c: Double) -> some View {
        let pct = Int((c * 100).rounded())
        let high = pct >= 70
        let tint: Color = high ? .green : (pct >= 40 ? Brand.warning : palette.textTertiary)
        return HStack(spacing: 4) {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 10, weight: .semibold))
            Text("CONFIDENCE \(pct)%")
                .font(EType.micro)
                .tracking(1.1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Space.s2)
        .padding(.vertical, 4)
        .overlay(
            Capsule().stroke(tint.opacity(0.6), lineWidth: 1)
        )
    }

    // MARK: Factors

    @ViewBuilder
    private var factorsSection: some View {
        if let factors = store.trends?.factors, !factors.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                Text("DRIVING FACTORS")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                ForEach(factors) { f in
                    factorRow(f)
                }
            }
        }
    }

    private func factorRow(_ f: RatesAPI.TrendFactor) -> some View {
        let impact = (f.impact ?? "").lowercased()
        let tint: Color = impact.contains("positive") || impact.contains("up")
            ? .green
            : (impact.contains("negative") || impact.contains("down") ? Brand.magenta : palette.textSecondary)
        return HStack(alignment: .top, spacing: Space.s2) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(f.factor?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Factor")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                if let desc = f.description, !desc.isEmpty {
                    Text(desc)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer()
            if let i = f.impact, !i.isEmpty {
                Text(i.uppercased())
                    .font(EType.micro)
                    .tracking(1.1)
                    .foregroundStyle(tint)
            }
        }
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Footer

    private var footer: some View {
        Text("Rate intel is a signal — not a guarantee. Use the forecast with your actual cost structure (CPM + deadhead + FSC) when negotiating.")
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

    private func percentDelta(_ value: Double) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "" : "")
        let pct = String(format: "%.1f", value)
        return "\(sign)\(pct)%"
    }
}

// MARK: - Screen wrapper

struct MeRateIntelScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeRateIntel()
        } nav: {
            BottomNav(
                leading: driverNavLeading_095(),
                trailing: driverNavTrailing_095(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_095() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_095() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("095 · Rate Intel · Night") {
    MeRateIntelScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("095 · Rate Intel · Afternoon") {
    MeRateIntelScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
