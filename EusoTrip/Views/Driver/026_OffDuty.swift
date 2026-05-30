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
    @Environment(\.driverNavBack) private var navBack
    @EnvironmentObject private var session: EusoTripSession

    @StateObject private var lifecycle = TripLifecycleStore()
    /// Live HOS snapshot — drives the 3-ring banks strip (DRIVE /
    /// WINDOW / CYCLE), the "eligible to drive in" countdown, and the
    /// off-duty duty-status flip on the Dim & sleep CTA. Mirrors the
    /// wiring 045_DepartingReceiver uses for its Off-duty action and
    /// 035/018 use for the in-cab HOS clock.
    @StateObject private var hos = HOSLiveStore()
    @State private var activeLoad: Load?
    /// Next assigned load (if any) — powers the next-pickup row. Pulled
    /// off `loads.search(status:"assigned")` the same way the lifecycle
    /// store hydrates the active in-flight load.
    @State private var nextLoad: LoadSummary?
    @State private var didLoad: Bool = false
    @State private var isDimming: Bool = false
    @State private var showPaySlip: Bool = false

    enum Register { case night, afternoon }
    let register: Register

    init(register: Register = .night) { self.register = register }

    private var ctx: LifecycleProductContext {
        LifecycleProductContext(load: activeLoad, role: session.user?.role)
    }

    private static let em = "—"

    // MARK: - Live HOS bindings
    //
    // Every value collapses to an em-dash sentinel until `hos.status`
    // hydrates — we never fabricate an HOS bank number, an eligibility
    // time, or a countdown. The server snapshot is hours (Double);
    // HOSStatus.formatHours renders "4h 30m" exactly like the ELD
    // overview tiles.

    /// True only after the first HOS fetch resolved (success or empty).
    private var hosReady: Bool { hos.status != nil }

    private var driveBankValue: String {
        guard let s = hos.status else { return Self.em }
        return HOSStatus.formatHours(s.drivingRemaining)
    }
    private var windowBankValue: String {
        guard let s = hos.status else { return Self.em }
        return HOSStatus.formatHours(s.onDutyRemaining)
    }
    private var cycleBankValue: String {
        guard let s = hos.status else { return Self.em }
        return HOSStatus.formatHours(s.cycleRemaining)
    }

    /// Ring fill fractions — bank remaining over the FMCSA cap. Zero
    /// (empty ring) until the snapshot lands so nothing animates from a
    /// fake value.
    private var driveFraction: Double {
        guard let s = hos.status else { return 0 }
        return max(0, min(1, s.drivingRemaining / 11.0))
    }
    private var windowFraction: Double {
        guard let s = hos.status else { return 0 }
        return max(0, min(1, s.onDutyRemaining / 14.0))
    }
    private var cycleFraction: Double {
        guard let s = hos.status else { return 0 }
        return max(0, min(1, s.cycleRemaining / 70.0))
    }

    /// Eligible-to-drive countdown. The federal reset returns the driver
    /// to a full drive window; `nextBreakDue` is the server's authority
    /// on when the clock frees up. Until the reset clears, the driver is
    /// off-duty, so we surface the remaining reset window when the
    /// server reports `canDrive == false`, and "ELIGIBLE NOW" when it
    /// flips true. No fabricated 9:58.
    private var countdownBig: String {
        guard let mins = minutesUntilEligible() else { return Self.em }
        let h = mins / 60
        let m = mins % 60
        return "\(h):" + String(format: "%02d", m)
    }
    private var countdownUnit: String { hosReady ? "h" : "" }

    private var eligibleByLabel: String {
        guard let s = hos.status else { return "" }
        if s.canDrive { return "ELIGIBLE NOW" }
        guard let iso = s.nextBreakDue,
              let date = Self.iso.date(from: iso) else { return "RESET IN PROGRESS" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "ELIGIBLE \(f.string(from: date))"
    }

    /// Minutes until the driver can roll again. nil = unhydrated.
    private func minutesUntilEligible() -> Int? {
        guard let s = hos.status else { return nil }
        if s.canDrive { return 0 }
        guard let iso = s.nextBreakDue,
              let date = Self.iso.date(from: iso) else { return nil }
        let delta = Int(date.timeIntervalSinceNow / 60)
        return max(0, delta)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Static chrome (caps + copy that aren't load-bearing data)
    private let fallbackParking       = "—"
    private let fallbackDriveCap      = "/ 11h"
    private let fallbackWindowCap     = "/ 14h"
    private let fallbackCycleCap      = "/ 70h"
    private let fallbackTodayMiles    = "—"
    private let fallbackTodayCpm      = "—"
    private let fallbackPayHero       = "—"
    private let fallbackPayBonus      = "—"
    private let fallbackPayCaption    = "Detention share auto-bills to you per the load's accessorial split; the balance to EusoTrip. Settled on the next pay run."

    /// Parking slot — surfaced from the just-closed load's delivery
    /// location when hydrated; em-dash until then.
    private var parkingLabel: String {
        if let d = activeLoad?.deliveryLocation, !d.city.isEmpty {
            return "Parked near \(d.city), \(d.state)"
        }
        return fallbackParking
    }

    /// Next-pickup headline — the next assigned load's lane, or an
    /// honest "No next load assigned" when the board is empty.
    private var nextPickupLabel: String {
        guard let n = nextLoad else {
            return hosReady ? "No next load assigned" : Self.em
        }
        return n.origin.isEmpty ? n.loadNumber : "\(n.origin) → \(n.destination)"
    }

    private var nextPickupTip: String {
        guard nextLoad != nil else {
            return "Your dispatcher hasn't tendered the next load yet — the brief will appear here when one lands."
        }
        if let label = eligibleByLabelTip {
            return "Next pickup brief unlocks once your reset clears · \(label)."
        }
        return "Next pickup brief unlocks once your 10-hour reset clears."
    }

    private var eligibleByLabelTip: String? {
        guard let s = hos.status, !s.canDrive,
              let iso = s.nextBreakDue,
              let date = Self.iso.date(from: iso) else { return nil }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "eligible \(f.string(from: date))"
    }

    private var resetHoursLabel: String {
        switch ctx.vertical {
        case .truck:  return "10-hour reset started"
        case .rail:   return "10-hour rest started (AAR)"
        case .vessel: return "Watch relief started (STCW)"
        }
    }

    /// Progress along the reset window. Derived from how much of the
    /// 10-hour reset is already behind the driver (server `nextBreakDue`
    /// minus remaining). Zero until the snapshot lands.
    private var progressFraction: CGFloat {
        guard let mins = minutesUntilEligible() else { return 0 }
        let total: Double = 600 // 10 hr reset
        let elapsed = total - Double(mins)
        return max(0, min(1, CGFloat(elapsed / total)))
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
        .sheet(isPresented: $showPaySlip) {
            MeEarnings068(theme: palette)
                .environment(\.palette, palette)
                .environmentObject(session)
        }
        .screenTileRoot()
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { navBack?() } label: {
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
                    LoadModeBadge(modeRaw: activeLoad?.transportMode,
                                  multiVehicleCount: activeLoad?.multiVehicleCount,
                                  compact: true)
                }
                Text(resetHoursLabel)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(parkingLabel)
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
                if !didLoad && !hosReady {
                    // Honest loading state — shimmer placeholder, never a
                    // fabricated countdown.
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.bgCardSoft)
                        .frame(width: 150, height: 64)
                        .redacted(reason: .placeholder)
                } else {
                    Text(countdownBig)
                        .font(.system(size: 82, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal)
                        .monospacedDigit()
                    Text(countdownUnit)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer(minLength: 0)
            }

            if !eligibleByLabel.isEmpty {
                Text(eligibleByLabel)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().stroke(Brand.success.opacity(0.5), lineWidth: 1))
            }

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
                Text(nextPickupLabel)
                    .font(EType.body.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(nextPickupTip)
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
                bankRing(label: "DRIVE",  value: driveBankValue,  cap: fallbackDriveCap,  fraction: driveFraction)
                bankRing(label: "WINDOW", value: windowBankValue, cap: fallbackWindowCap, fraction: windowFraction)
                bankRing(label: "CYCLE",  value: cycleBankValue,  cap: fallbackCycleCap,  fraction: cycleFraction)
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
            Button { showPaySlip = true } label: {
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

            CTAButton(
                title: "Dim & sleep",
                action: { Task { await dimAndSleep() } },
                isLoading: isDimming
            )
        }
    }

    // MARK: - Hydration

    private func hydrateLiveTrip() async {
        defer { didLoad = true }
        // Live HOS snapshot (banks strip + eligibility countdown).
        await hos.bootstrap()
        // The just-delivered load that put the driver on the reset.
        await lifecycle.hydrateActiveLoad()
        await lifecycle.refresh()
        if !lifecycle.loadId.isEmpty, let n = Int(lifecycle.loadId) {
            activeLoad = try? await EusoTripAPI.shared.loads.getById(n)
        }
        // Next assigned load — powers the next-pickup row. Empty board
        // is fine; the row renders an honest "No next load assigned".
        nextLoad = try? await EusoTripAPI.shared.loads
            .search(status: "assigned", limit: 1).first
    }

    /// Dim & sleep — the off-duty screen IS the off-duty action, so the
    /// CTA flips FMCSA duty status to off-duty the same way 045's
    /// Off-duty button does, then lets the env-injected advance own the
    /// next-screen move. HOSLiveStore's toast reports success / failure.
    private func dimAndSleep() async {
        isDimming = true
        defer { isDimming = false }
        _ = await hos.changeStatus(
            to: .offDuty,
            location: parkingLabel == fallbackParking ? "" : parkingLabel,
            remark: "Off-duty reset (026)",
            loadId: lifecycle.loadId.isEmpty ? nil : lifecycle.loadId
        )
        advance?()
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

private func driverNavLeading_026() -> [NavSlot] {
    [NavSlot(label: "Home",  systemImage: "house",       isCurrent: true),
     NavSlot(label: "Trips", systemImage: "truck.box",   isCurrent: false)]
}
private func driverNavTrailing_026() -> [NavSlot] {
    [NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",    systemImage: "person",           isCurrent: false)]
}

#Preview("026 · Off Duty · Dark") {
    OffDutyScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("026 · Off Duty · Light") {
    OffDutyScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
