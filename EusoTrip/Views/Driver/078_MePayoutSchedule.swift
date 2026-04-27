//
//  078_MePayoutSchedule.swift
//  EusoTrip 2027 UI — Wave 7 (driver · Me · payout schedule)
//
//  Screen 078 · Me · Payout Schedule — the driver's EusoWallet
//  cadence control. Four pieces stacked: frequency picker (daily /
//  weekly / biweekly / monthly), day-of-week picker (shown only for
//  weekly + biweekly cadences), minimum-threshold stepper, and
//  auto-payout toggle. Every control flips with a single mutation
//  through `PayoutScheduleStore.update(...)` — optimistic UI +
//  server reconciliation, no fire-and-forget.
//
//  Cohort B — fully dynamic (SKILL.md §3 "no-mock" pledge):
//
//    • All reads + writes route through the live
//      `wallet.getPayoutSchedule` + `wallet.updatePayoutSchedule`
//      procedures — MCP-verified at
//      `frontend/server/routers/wallet.ts:689, 701`.
//
//    • Next-scheduled-payout date is server-computed; the view
//      surfaces it as-is and never fakes a "Friday at 5pm" string.
//
//    • Minimum-threshold stepper writes the actual minimumAmount in
//      USD — no fake slider that animates without a round-trip.
//
//  Doctrine refs:
//    §2   LinearGradient.diagonal on the active cadence pill + toggle
//         fills. No Brand.info flats.
//    §4   Tokenized spacing, radii, type.
//    §5   Palette semantic throughout.
//    §7   Ternary ShapeStyle wrapped in AnyShapeStyle.
//    §10  Previews land in `.error` under the no-baseURL runtime. No
//         fixtures.
//

import SwiftUI

private enum PayoutFrequency: String, CaseIterable, Identifiable {
    case daily, weekly, biweekly, monthly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .daily:    return "Daily"
        case .weekly:   return "Weekly"
        case .biweekly: return "Bi-weekly"
        case .monthly:  return "Monthly"
        }
    }
    var sub: String {
        switch self {
        case .daily:    return "1–2 business days after each load settles"
        case .weekly:   return "Every week on the day you choose"
        case .biweekly: return "Every other week on the chosen day"
        case .monthly:  return "Once per month on the 1st"
        }
    }
    /// True when the backend honors a `dayOfWeek` selection.
    var supportsDayOfWeek: Bool {
        self == .weekly || self == .biweekly
    }
}

private enum PayoutDay: String, CaseIterable, Identifiable {
    case monday, tuesday, wednesday, thursday, friday
    var id: String { rawValue }
    var short: String {
        switch self {
        case .monday:    return "Mon"
        case .tuesday:   return "Tue"
        case .wednesday: return "Wed"
        case .thursday:  return "Thu"
        case .friday:    return "Fri"
        }
    }
}

// MARK: - Screen root

struct MePayoutSchedule: View {
    @Environment(\.palette) var palette
    @StateObject private var store = PayoutScheduleStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Space.s5) {
                header
                switch store.state {
                case .loading:
                    skeleton
                case .empty:
                    // Single-value store — `.empty` shouldn't happen
                    // but keep a graceful fallback.
                    emptyHero
                case .error(let e):
                    errorBanner(e)
                case .loaded(let schedule):
                    nextPayoutHero(schedule)
                    frequencySection(schedule)
                    if let freq = PayoutFrequency(rawValue: schedule.frequency.lowercased()),
                       freq.supportsDayOfWeek {
                        dayOfWeekSection(schedule)
                    }
                    minimumSection(schedule)
                    autoPayoutSection(schedule)
                }
                disclosureFooter
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
                Text("Payout Schedule")
                    .font(EType.h1)
                    .foregroundStyle(LinearGradient.diagonal)
                Text("Cadence · day · minimum · auto")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer()
            OrbESang(state: (store.isLoading || store.isSaving) ? .thinking : .idle, diameter: 40)
        }
    }

    // MARK: States

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.45))
                .frame(height: 120)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.35))
                .frame(height: 100)
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.tintNeutral.opacity(0.3))
                .frame(height: 80)
        }
    }

    private var emptyHero: some View {
        EusoEmptyState(
            systemImage: "calendar.badge.clock",
            title: "Schedule unavailable",
            subtitle: "We couldn't load your payout cadence. Pull to refresh."
        )
    }

    private func errorBanner(_ err: Error) -> some View {
        VStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(palette.textSecondary)
            Text("Can't load schedule")
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

    // MARK: Next-payout hero

    private func nextPayoutHero(_ schedule: WalletAPI.PayoutSchedule) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("NEXT SCHEDULED PAYOUT")
                .font(EType.micro).tracking(1.3)
                .foregroundStyle(palette.textTertiary)
            if let pretty = prettyDate(schedule.nextScheduledPayout) {
                Text(pretty)
                    .font(EType.h2)
                    .foregroundStyle(LinearGradient.diagonal)
            } else {
                Text("—")
                    .font(EType.h2)
                    .foregroundStyle(palette.textSecondary)
                Text("Your first payout posts after your first settled load.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s2) {
                summaryPill("Cadence", summaryLabel(for: schedule.frequency))
                if let freq = PayoutFrequency(rawValue: schedule.frequency.lowercased()),
                   freq.supportsDayOfWeek,
                   !schedule.dayOfWeek.isEmpty {
                    summaryPill("Day", schedule.dayOfWeek.capitalized)
                }
                summaryPill("Minimum", money(schedule.minimumAmount))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private func summaryPill(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(EType.micro).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(EType.caption)
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, Space.s2)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(palette.bgCard.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(palette.borderFaint.opacity(0.6), lineWidth: 1)
        )
    }

    // MARK: Frequency

    private func frequencySection(_ schedule: WalletAPI.PayoutSchedule) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("CADENCE")
                .font(EType.micro).tracking(1.4)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: Space.s2) {
                ForEach(PayoutFrequency.allCases) { freq in
                    frequencyRow(freq, current: schedule)
                }
            }
        }
    }

    private func frequencyRow(_ freq: PayoutFrequency, current: WalletAPI.PayoutSchedule) -> some View {
        let selected = freq.rawValue == current.frequency.lowercased()
        return Button {
            guard !selected else { return }
            Task {
                // When transitioning to a cadence that doesn't honor
                // dayOfWeek, reset the server-side value so the
                // scheduler doesn't retain a stale Friday tag on a
                // Monthly plan.
                let dow = freq.supportsDayOfWeek
                    ? (current.dayOfWeek.isEmpty ? "friday" : current.dayOfWeek)
                    : ""
                await store.update(frequency: freq.rawValue, dayOfWeek: dow)
            }
        } label: {
            HStack(spacing: Space.s3) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textSecondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(freq.label)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(freq.sub)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s3)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(palette.bgCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(selected ? Color.white.opacity(0.25) : palette.borderFaint, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Day of week

    private func dayOfWeekSection(_ schedule: WalletAPI.PayoutSchedule) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("PAYOUT DAY")
                .font(EType.micro).tracking(1.4)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                ForEach(PayoutDay.allCases) { day in
                    dayPill(day, current: schedule)
                }
            }
        }
    }

    private func dayPill(_ day: PayoutDay, current: WalletAPI.PayoutSchedule) -> some View {
        let selected = day.rawValue == current.dayOfWeek.lowercased()
        return Button {
            guard !selected else { return }
            Task { await store.update(dayOfWeek: day.rawValue) }
        } label: {
            Text(day.short)
                .font(EType.bodyStrong)
                .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textPrimary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    ZStack {
                        if selected {
                            Capsule().fill(LinearGradient.diagonal)
                        } else {
                            Capsule().fill(palette.bgCard)
                        }
                    }
                )
                .overlay(
                    Capsule().strokeBorder(selected ? Color.white.opacity(0.25) : palette.borderFaint, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Minimum

    private func minimumSection(_ schedule: WalletAPI.PayoutSchedule) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("MINIMUM PER PAYOUT")
                .font(EType.micro).tracking(1.4)
                .foregroundStyle(palette.textTertiary)
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(money(schedule.minimumAmount))
                        .font(EType.numeric)
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    Spacer()
                    HStack(spacing: Space.s1) {
                        stepperButton(label: "−",
                                      disabled: schedule.minimumAmount <= 5) {
                            Task {
                                let next = max(5, schedule.minimumAmount - 5)
                                await store.update(minimumAmount: next)
                            }
                        }
                        stepperButton(label: "+",
                                      disabled: schedule.minimumAmount >= 5000) {
                            Task {
                                let next = min(5000, schedule.minimumAmount + 5)
                                await store.update(minimumAmount: next)
                            }
                        }
                    }
                }
                Text("Payouts below this amount queue and settle on the next cycle once the threshold is met.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.s2) {
                    ForEach([25.0, 50.0, 100.0, 250.0], id: \.self) { preset in
                        presetMinimum(preset, current: schedule)
                    }
                }
            }
            .padding(Space.s3)
            .eusoCard(radius: Radius.lg)
        }
    }

    private func stepperButton(label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(disabled ? AnyShapeStyle(palette.textTertiary) : AnyShapeStyle(palette.textPrimary))
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(palette.bgCardSoft)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(palette.borderFaint.opacity(0.6), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func presetMinimum(_ preset: Double, current: WalletAPI.PayoutSchedule) -> some View {
        let selected = abs(preset - current.minimumAmount) < 0.01
        return Button {
            guard !selected else { return }
            Task { await store.update(minimumAmount: preset) }
        } label: {
            Text(money(preset))
                .font(EType.caption)
                .foregroundStyle(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(palette.textSecondary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    ZStack {
                        if selected {
                            Capsule().fill(LinearGradient.diagonal)
                        } else {
                            Capsule().fill(palette.bgCard.opacity(0.6))
                        }
                    }
                )
                .overlay(
                    Capsule().strokeBorder(selected ? Color.white.opacity(0.25) : palette.borderFaint.opacity(0.6), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: Auto-payout

    private func autoPayoutSection(_ schedule: WalletAPI.PayoutSchedule) -> some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("AUTO-PAYOUT")
                .font(EType.micro).tracking(1.4)
                .foregroundStyle(palette.textTertiary)
            Toggle(isOn: Binding(
                get: { schedule.autoPayoutEnabled },
                set: { newValue in
                    Task { await store.update(autoPayoutEnabled: newValue) }
                }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Send automatically")
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text("On when I can, off when I want to hold and release on demand")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(GradientToggleStyle())
            .padding(Space.s3)
            .eusoCard(radius: Radius.lg)
        }
    }

    // MARK: Footer

    private var disclosureFooter: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            HStack(spacing: Space.s2) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
                Text("How payouts work")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
            }
            Text("Payouts run against your default method (manage in Payment Methods). With auto-payout off, Eusowallet still accrues earnings — you press Pay now when you want the release. Instant payouts land in ~30 minutes for a 1.5% fee; standard ACH lands in 1–2 business days free.")
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

    private func summaryLabel(for raw: String) -> String {
        PayoutFrequency(rawValue: raw.lowercased())?.label ?? raw.capitalized
    }

    private func money(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }

    private func prettyDate(_ iso: String) -> String? {
        guard !iso.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let out = DateFormatter()
            out.dateFormat = "EEEE, MMM d"
            return out.string(from: d)
        }
        return iso
    }
}

// MARK: - Screen wrapper

struct MePayoutScheduleScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            MePayoutSchedule()
        } nav: {
            BottomNav(
                leading: driverNavLeading_078(),
                trailing: driverNavTrailing_078(),
                orbState: .idle
            )
        }
    }
}

private func driverNavLeading_078() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",  isCurrent: false),
     NavSlot(label: "Haul",  systemImage: "trophy", isCurrent: false)]
}
private func driverNavTrailing_078() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "wallet.pass", isCurrent: true),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: false)]
}

// MARK: - Previews

#Preview("078 · Me Payout Schedule · Night") {
    MePayoutScheduleScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("078 · Me Payout Schedule · Afternoon") {
    MePayoutScheduleScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
