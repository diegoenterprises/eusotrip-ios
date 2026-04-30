//
//  026_OffDuty.swift
//  EusoTrip — Lifecycle screen 026 · Off Duty (10-hour reset).
//
//  Pixel-matched to the 2026-04-24 Figma frame
//  `026 Off Duty.png` (Dark + Light). The load has been delivered,
//  paperwork closed, and the driver is in their parked slot
//  starting the federal 10-hour off-duty reset. Surfaces a big
//  gradient countdown to eligible-to-drive, an "eligible by" hint,
//  a 3-ring HOS banks strip (DRIVE / WINDOW / CYCLE), a detention
//  share pay-preview row, and View pay slip / Dim & sleep CTAs.
//
//  Adapts to vertical — rail engineers see federal HOS variant
//  (10h off for hazmat, 8h for general freight); vessel captains
//  see STCW watch-hours reset. Defaults to FMCSA 10-hour.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct OffDuty: View {
    @Environment(\.palette) private var palette
    @Environment(\.lifecycleAdvance) private var advance
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    @State private var activeLoad: Load?

    enum Register { case night, afternoon }
    let register: Register

    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    // MARK: - Figma fallback
    private let fallbackClock         = "07:05"
    private let fallbackParking       = "—"
    private let fallbackCountdownBig  = "9:58"
    private let fallbackCountdownUnit = "h"
    private let fallbackEligibleBy    = "ELIGIBLE 17:03 TODAY"
    private let fallbackNextPickup    = "—"
    private let fallbackNextPickupTip = "Next pickup brief unlocks 17:03 · 2 min before you can roll."
    private let fallbackDriveBank     = "4:30"
    private let fallbackWindowBank    = "2:30"
    private let fallbackCycleBank     = "18:00"
    private let fallbackDriveCap      = "/ 11h"
    private let fallbackWindowCap     = "/ 14h"
    private let fallbackCycleCap      = "/ 70h"
    private let fallbackTodayMiles    = "—"
    private let fallbackTodayCpm      = "—"
    private let fallbackPayHero       = "—"
    private let fallbackPayBonus      = "—"
    private let fallbackPayCaption    = "26% of the $270 detention auto-bills to you; the rest to EusoTrip. Paid Friday."

    private var resetHoursLabel: String {
        switch ctx.vertical {
        case .truck:  return "10-hour reset started"
        case .rail:   return "10-hour rest started (AAR)"
        case .vessel: return "Watch relief started (STCW)"
        }
    }

    private var progressFraction: CGFloat {
        // Rough conversion from "9:58 remaining" → ~0.2% elapsed.
        let remaining = parseHoursMinutes(fallbackCountdownBig) ?? 598
        let total: Double = 600 // 10 hr
        return max(0, min(1, CGFloat((total - remaining) / total)))
    }

    private func parseHoursMinutes(_ s: String) -> Double? {
        let parts = s.split(separator: ":").map(String.init)
        guard parts.count == 2, let h = Double(parts[0]), let m = Double(parts[1]) else {
            return nil
        }
        return h * 60 + m
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                countdownCard
                hosBanksStrip
                payCard
                footerActions
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await hydrateLiveTrip() }
        .screenTileRoot()
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { /* upstream back */ } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(palette.bgCard)
                    .overlay(Circle().strokeBorder(palette.borderFaint))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(LinearGradient.diagonal).frame(width: 6, height: 6)
                    Text("OFF DUTY")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("· SLEEPER BERTH")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textSecondary)
                }
                Text(resetHoursLabel)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(fallbackParking)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            ZStack {
                Circle()
                    .fill(LinearGradient.diagonal)
                    .frame(width: 38, height: 38)
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Countdown card

    private var countdownCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("ELIGIBLE TO DRIVE IN")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(fallbackCountdownBig)
                    .font(.system(size: 82, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text(fallbackCountdownUnit)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 0)
            }

            Text(fallbackEligibleBy)
                .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                .foregroundStyle(Brand.success)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))

            // Progress rail
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bgCardSoft).frame(height: 5)
                    Capsule()
                        .fill(LinearGradient.diagonal)
                        .frame(width: geo.size.width * progressFraction, height: 5)
                }
            }
            .frame(height: 5)
            .padding(.top, Space.s2)

            VStack(alignment: .leading, spacing: 2) {
                Text(fallbackNextPickup)
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(fallbackNextPickupTip)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, Space.s1)
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: HOS banks strip

    private var hosBanksStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("HOURS OF SERVICE · REMAINING")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                bankRing(label: "DRIVE",  value: fallbackDriveBank,  cap: fallbackDriveCap,  fraction: 0.41)
                bankRing(label: "WINDOW", value: fallbackWindowBank, cap: fallbackWindowCap, fraction: 0.18)
                bankRing(label: "CYCLE",  value: fallbackCycleBank,  cap: fallbackCycleCap,  fraction: 0.26)
            }
        }
    }

    private func bankRing(label: String, value: String, cap: String, fraction: Double) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(palette.bgCardSoft, lineWidth: 5)
                    .frame(width: 76, height: 76)
                Circle()
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(
                        LinearGradient.diagonal,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 76, height: 76)
                Text(value)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
            }
            VStack(spacing: 1) {
                Text(label)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Text(cap)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s3)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Pay card

    private var payCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 3) {
                Text("TODAY · BANKED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                HStack(spacing: 6) {
                    Text(fallbackTodayMiles)
                        .font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary)
                    Text(fallbackTodayCpm)
                        .font(EType.mono(.micro)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                }
                Text(fallbackPayCaption)
                    .font(EType.mono(.micro)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 3) {
                Text(fallbackPayHero)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text(fallbackPayBonus)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Brand.success)
                Text("Detention share")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Footer CTAs

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            Button { /* upstream pay-slip sheet */ } label: {
                Text("View pay slip")
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderSoft)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }

            CTAButton(title: "Dim & sleep") {
                // Upstream screen-dim handler. Hooked through the
                // env-injected lifecycle advance once the off-duty
                // sleep mode wires into UIScreen.brightness.
            }
        }
    }

    // MARK: - Hydration

    private func hydrateLiveTrip() async {
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        guard !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) else { return }
        activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
    }
}

struct OffDutyScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            OffDuty(register: .night)
        } nav: {
            BottomNav(leading: driverNavLeading_026(),
                      trailing: driverNavTrailing_026(),
                      orbState: .idle)
        }
    }
}

// PNG canon at `01 Driver/{Light,Dark}/026 Off Duty.png` pins HOME
// current — 026 is the "Off Duty · HOME" day-close surface returning
// to Home root, distinct from the active-trip lifecycle context.
// Icon set + trailing slot normalized to canonical 010-025 layout.
private func driverNavLeading_026() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house.fill", isCurrent: true),
     NavSlot(label: "Trips", systemImage: "truck.box",  isCurrent: false)]
}
private func driverNavTrailing_026() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person.fill", isCurrent: false)]
}

#Preview("026 · Off Duty · Dark") {
    OffDutyScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("026 · Off Duty · Light") {
    OffDutyScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
