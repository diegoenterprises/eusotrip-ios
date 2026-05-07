//
//  090_MeIfta.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · IFTA Tax)
//
//  Screen 090 · Me · IFTA Tax — owner-operator quarterly fuel-tax
//  forecaster. The driver picks a year + quarter + fleet MPG and
//  sees the estimated total miles, gallons consumed, and quarterly
//  IFTA tax liability pulled from their real delivered loads in
//  that window. Filing deadline chip reminds them when the return
//  is due.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge · 2027
//  motivation "no fake data"):
//
//    • Estimate ships from `iftaCalculator.estimateFromLoads` —
//      MCP-verified at `frontend/server/routers/iftaCalculator.ts`.
//      The server pulls all loads with `status=delivered` +
//      `deliveryDate` in the quarter window, sums `distance`,
//      converts to gallons via fleet MPG, applies a blended
//      $0.30/gal estimator. It's explicitly a FORECAST, not a
//      filing-ready number — the note field on the response says
//      so, and we render it verbatim.
//
//    • Full filing (`calculateQuarter`) requires per-jurisdiction
//      miles + fuel purchases, which is out-of-scope for a one-
//      screen estimator and ships in a follow-up drilldown when
//      the driver has the exporter data ready.
//
//    • Year + quarter + fleet MPG are driver-adjustable. Changes
//      debounce-refetch the estimate so the number is always
//      live against the current server snapshot.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on hero liability + submit CTAs.
//         Brand.warning on deadlines inside 30 days.
//    §4   Tokenized Space/Radius/EType throughout.
//    §5   Palette semantic.
//

import SwiftUI

// MARK: - Screen root

struct MeIfta: View {
    @Environment(\.palette) var palette
    @StateObject private var store = IftaStore()

    @State private var mpgText: String = ""

    private let years: [Int] = {
        let this = Calendar.current.component(.year, from: Date())
        return Array((this - 4)...(this)).reversed()
    }()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                selectors
                liabilityHero
                summaryStrip
                noteBlock
                footer
            }
            .padding(.horizontal, Space.s4)
            .padding(.top, Space.s4)
            .padding(.bottom, Space.s8)
        }
        .task {
            mpgText = String(format: "%.1f", store.fleetMpg)
            await store.refresh()
        }
        .refreshable { await store.refresh() }
        // RealtimeService → IFTA fuel/mileage data refreshes when
        // load events fire (new mileage logged, fuel purchase added).
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await store.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eusoLoadAssigned)) { _ in
            Task { await store.refresh() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("IFTA Tax")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Quarterly fuel-tax forecast from your real loads")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: store.isLoading ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: Selectors

    private var selectors: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("PERIOD")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("FLEET MPG")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s2) {
                Menu {
                    ForEach(years, id: \.self) { y in
                        // Button(LocalizedStringKey) auto-formats Ints
                        // with locale grouping → renders "2,026" for
                        // year 2026. Wrap in String() to bypass the
                        // LocalizedStringKey path so the year reads as
                        // a year, not a thousands-separated number.
                        Button(String(y)) {
                            store.year = y
                            Task { await store.refresh() }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(String(store.year))
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                            .monospacedDigit()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s2)
                    .overlay(
                        Capsule().stroke(palette.textTertiary.opacity(0.5), lineWidth: 1)
                    )
                }

                Menu {
                    ForEach(IftaAPI.Quarter.allCases) { q in
                        Button(q.label) {
                            store.quarter = q
                            Task { await store.refresh() }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(store.quarter.label)
                            .font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    .padding(.horizontal, Space.s3)
                    .padding(.vertical, Space.s2)
                    .overlay(
                        Capsule().stroke(palette.textTertiary.opacity(0.5), lineWidth: 1)
                    )
                }

                Spacer()

                HStack(spacing: 4) {
                    TextField("6.5", text: $mpgText)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                        .keyboardType(.decimalPad)
                        .frame(width: 52)
                        .multilineTextAlignment(.trailing)
                        .onSubmit { applyMpg() }
                    Text("mpg")
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.horizontal, Space.s3)
                .padding(.vertical, Space.s2)
                .overlay(
                    Capsule().stroke(palette.textTertiary.opacity(0.5), lineWidth: 1)
                )
            }
        }
    }

    private func applyMpg() {
        if let v = Double(mpgText), v >= 1, v <= 20 {
            store.fleetMpg = v
            Task { await store.refresh() }
        } else {
            mpgText = String(format: "%.1f", store.fleetMpg)
        }
    }

    // MARK: Liability hero

    private var liabilityHero: some View {
        VStack(spacing: Space.s3) {
            if let est = store.estimate {
                Text("ESTIMATED LIABILITY")
                    .font(EType.micro)
                    .tracking(1.3)
                    .foregroundStyle(palette.textTertiary)
                Text(currency(est.estimatedTaxLiability))
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text(est.period)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                deadlineChip
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
                    systemImage: "fuelpump",
                    title: "No loads in this quarter",
                    subtitle: "Once deliveries complete in the selected window, your IFTA forecast lands here."
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Space.s5)
        .eusoCard(radius: Radius.lg)
    }

    private var deadlineChip: some View {
        let deadline = store.quarter.filingDeadline(year: store.year)
        let urgent = isDeadlineUrgent(deadline)
        return HStack(spacing: 4) {
            Image(systemName: "calendar")
                .font(.system(size: 10, weight: .semibold))
            Text("FILING BY \(humanize(deadline))")
                .font(EType.micro)
                .tracking(1.1)
        }
        .foregroundStyle(urgent ? Brand.warning : palette.textTertiary)
        .padding(.horizontal, Space.s2)
        .padding(.vertical, 4)
        .overlay(
            Capsule().stroke(urgent ? Brand.warning : palette.textTertiary.opacity(0.55),
                             lineWidth: 1)
        )
    }

    // MARK: Summary strip

    private var summaryStrip: some View {
        let est = store.estimate
        return HStack(spacing: Space.s2) {
            summaryTile(
                label: "LOADS",
                value: "\(est?.loadsInPeriod ?? 0)"
            )
            summaryTile(
                label: "MILES",
                value: compactNumber(est?.estimatedTotalMiles ?? 0)
            )
            summaryTile(
                label: "GALLONS",
                value: compactNumber(est?.estimatedGallonsConsumed ?? 0)
            )
        }
    }

    private func summaryTile(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(EType.micro)
                .tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.bodyStrong)
                .foregroundStyle(LinearGradient.diagonal)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s3)
        .eusoCard(radius: Radius.md)
    }

    // MARK: Server note

    @ViewBuilder
    private var noteBlock: some View {
        if let note = store.estimate?.note, !note.isEmpty {
            HStack(alignment: .top, spacing: Space.s2) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text(note)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.tintNeutral.opacity(0.35))
            )
        }
    }

    // MARK: Footer

    private var footer: some View {
        Text("For your actual filing, keep fuel receipts by state + track miles by jurisdiction via your ELD. The full filing calculator lands next.")
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

    private func humanize(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let date = f.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.dateFormat = "MMM d"
        return out.string(from: date)
    }

    private func isDeadlineUrgent(_ iso: String) -> Bool {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let date = f.date(from: iso) else { return false }
        let days = date.timeIntervalSinceNow / 86400
        return days > 0 && days < 30
    }
}

// MARK: - Screen wrapper

struct MeIftaScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MeIfta()
        } nav: {
            BottomNav(
                leading: driverNavLeading_090(),
                trailing: driverNavTrailing_090(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_090() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_090() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "wallet.pass", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: true)]
}

// MARK: - Previews

#Preview("090 · IFTA · Night") {
    MeIftaScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("090 · IFTA · Afternoon") {
    MeIftaScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
