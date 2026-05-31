//
//  558_RailDemurrageWatch.swift
//  EusoTrip — Rail Engineer · Demurrage Watch (carrier fleet monitor).
//
//  Visual identity: "breach clock" — the hero shows a large arc ring encoding
//  the highest-risk car's accrual position relative to free time. Breached cars
//  render with dangerWash. Each row has a compact accrual-progress ring.
//

import SwiftUI

struct RailDemurrageWatchScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailDemurrageWatchBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct DemurrageCar558: Decodable, Identifiable {
    let id: Int
    let loadId: String?
    let carNumber: String?
    let carType: String?
    let location: String?
    let freeTimeHours: Int?
    let accruedHours: Int?
    let chargeUsd: Double?
    let hazmatUn: String?
}

private struct DemurrageWatch558: Decodable {
    let totalAccruingUsd: Double?
    let atRiskCount: Int?
    let breachedCount: Int?
    let cars: [DemurrageCar558]?
}

private struct RailDemurrageWatchBody: View {
    @Environment(\.palette) private var palette
    @State private var watch: DemurrageWatch558? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    private enum Risk { case clear, atRisk, breached }

    private func risk(_ c: DemurrageCar558) -> Risk {
        let free = c.freeTimeHours ?? 48, accrued = c.accruedHours ?? 0
        if accrued >= free { return .breached }
        if free - accrued < 12 { return .atRisk }
        return .clear
    }

    private func riskColor(_ r: Risk) -> Color {
        switch r { case .clear: return Brand.success; case .atRisk: return Brand.warning; case .breached: return Brand.danger }
    }

    // Worst-risk car fraction (0-1) for the breach clock ring
    private var worstCarFraction: Double {
        let cars = watch?.cars ?? []
        guard !cars.isEmpty else { return 0 }
        return cars.map { c -> Double in
            let free = Double(c.freeTimeHours ?? 48)
            let accrued = Double(c.accruedHours ?? 0)
            return min(accrued / max(free, 1), 1.0)
        }.max() ?? 0
    }

    private var breachClockColor: Color {
        worstCarFraction >= 1.0 ? Brand.danger : (worstCarFraction > 0.7 ? Brand.warning : Brand.success)
    }

    private var hasBreach: Bool { (watch?.breachedCount ?? 0) > 0 }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading demurrage…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    breachClockHero
                    kpiStrip
                    if hasBreach { breachBanner }
                    watchList
                    CTAButton(title: "Export demurrage report", leadingIcon: "square.and.arrow.up")
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Eyebrow + headline

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("RAIL ENGINEER · DEMURRAGE WATCH").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Demurrage watch")
                .font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Breach clock hero

    private var breachClockHero: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard)
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)

            HStack(spacing: Space.s4) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("FLEET ACCRUAL")
                        .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(palette.textTertiary.opacity(0.10)))
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("$\(Int(watch?.totalAccruingUsd ?? 0))")
                            .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("accruing now")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textSecondary)
                            Text("\(watch?.cars?.count ?? 0) in-yard cars · getLiveDemurrage")
                                .font(EType.caption).foregroundStyle(palette.textTertiary)
                        }
                    }
                }
                Spacer()
                BreachClockRing558(fraction: worstCarFraction, color: breachClockColor)
            }
            .padding(Space.s4)
        }
        .frame(height: 120)
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "ACCRUING", value: "$\(Int(watch?.totalAccruingUsd ?? 0))", gradientNumeral: true)
            MetricTile(label: "AT RISK",  value: "\(watch?.atRiskCount ?? 0)",   accent: Brand.warning)
            MetricTile(label: "BREACHED", value: "\(watch?.breachedCount ?? 0)", accent: Brand.danger)
        }
    }

    // MARK: Breach banner

    private var breachBanner: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold)).foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(watch?.breachedCount ?? 0) car\(watch?.breachedCount == 1 ? "" : "s") past free time")
                    .font(.system(size: 14, weight: .heavy)).foregroundStyle(Brand.danger)
                Text("Charges accruing — request early release or contest with carrier")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            Spacer()
        }
        .padding(Space.s3)
        .background(Brand.danger.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Brand.danger.opacity(0.30)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Watch list

    private var watchList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("IN-YARD CARS · calculateRailDemurrage")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            VStack(spacing: Space.s2) {
                ForEach(watch?.cars ?? []) { c in carRow(c) }
            }
        }
    }

    private func carRow(_ c: DemurrageCar558) -> some View {
        let r = risk(c)
        let color = riskColor(r)
        let free = Double(c.freeTimeHours ?? 48)
        let accrued = Double(c.accruedHours ?? 0)
        let frac = min(accrued / max(free, 1), 1.0)

        return HStack(spacing: Space.s3) {
            // Accrual arc — sweeps to the car's real accrued/free fraction
            CarAccrualRing558(fraction: frac, color: color, breached: r == .breached)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(c.loadId ?? "—") · \(c.carNumber ?? "—")")
                        .font(.system(size: 12, weight: .bold)).monospaced().foregroundStyle(palette.textPrimary)
                    if c.hazmatUn != nil {
                        Text("HAZMAT")
                            .font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.warning)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Capsule().fill(Brand.warning.opacity(0.16)))
                    }
                }
                Text("\(c.carType ?? "—") · \(c.freeTimeHours ?? 48)h free · \(c.accruedHours ?? 0)h accrued · \(c.location ?? "—")")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("$\(Int(c.chargeUsd ?? 0))")
                    .font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(color)
                Text(r == .breached ? "BREACHED" : r == .atRisk ? "AT RISK" : "CLEAR")
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(color.opacity(0.14)))
            }
        }
        .padding(Space.s3)
        .background(r == .breached ? Brand.danger.opacity(0.06) : palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(r == .breached ? Brand.danger.opacity(0.30) : palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Data

    private func load() async {
        loading = true; loadError = nil
        struct Empty: Encodable {}
        do {
            self.watch = try await EusoTripAPI.shared.query("railShipments.getLiveDemurrage", input: Empty())
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Breach clock ring (hero)
//
// The arc + clock hand sweep from empty up to the worst car's real accrual
// fraction (accruedHours / freeTimeHours) using a decelerating settle spring,
// so the hero reads as the clock "winding up" to its true position. Once a car
// has actually breached free time (fraction >= 1) the ring carries an ambient
// breathing glow — a seamless continuous loop that signals live, ongoing
// charge accrual. Under Reduce Motion the ring snaps straight to its final
// state with no sweep and no pulse.
private struct BreachClockRing558: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Real worst-car fraction (0…1) from the data model.
    let fraction: Double
    let color: Color

    /// The fraction the arc/hand currently animate toward. Starts at 0 so the
    /// clock winds up into its true position on appear.
    @State private var shown: Double = 0
    /// Drives the ambient breach pulse (continuous, breached-only).
    @State private var breathing = false

    private var isBreached: Bool { fraction >= 1.0 }

    var body: some View {
        let pulse = isBreached && !reduceMotion
        return ZStack {
            // Track
            Circle().stroke(color.opacity(0.16), lineWidth: 7).frame(width: 72, height: 72)
            // Filled arc — clock-style trim, bound to the real fraction
            Circle()
                .trim(from: 0, to: shown)
                .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 72, height: 72)
                .shadow(color: pulse ? color.opacity(breathing ? 0.55 : 0.15) : .clear,
                        radius: pulse ? (breathing ? 7 : 3) : 0)
            // Clock hand tick mark — tracks the same real fraction
            Rectangle()
                .fill(color)
                .frame(width: 2, height: 10)
                .offset(y: -26)
                .rotationEffect(.degrees(shown * 360 - 90))
            VStack(spacing: 1) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(fraction >= 1 ? "BREACH" : "\(Int(fraction * 100))%")
                    .font(.system(size: 9, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(color)
            }
            // Scale breathing on the whole ring while breached.
            .scaleEffect(pulse ? (breathing ? 1.0 : 0.97) : 1.0)
        }
        .onAppear { settle() }
        .onChange(of: fraction) { _, _ in settle() }
    }

    private func settle() {
        if reduceMotion {
            shown = fraction
            breathing = false
            return
        }
        // Decelerating settle — the clock winds up to its true position.
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
            shown = fraction
        }
        // Ambient breach pulse: seamless autoreversing loop (start == end).
        if isBreached {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                breathing = true
            }
        } else {
            breathing = false
        }
    }
}

// MARK: - Per-car accrual ring (list row)
//
// Each row's compact ring sweeps from empty up to that car's real accrued/free
// fraction with a decelerating settle spring, so the list reads as the cars
// filling toward their free-time limit. Reduce Motion snaps straight to final.
private struct CarAccrualRing558: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Real accrued/free fraction (0…1) for this car.
    let fraction: Double
    let color: Color
    let breached: Bool

    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: 5).frame(width: 44, height: 44)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 44, height: 44)
            Image(systemName: breached ? "exclamationmark" : "clock")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(color)
        }
        .onAppear { settle() }
        .onChange(of: fraction) { _, _ in settle() }
    }

    private func settle() {
        if reduceMotion {
            shown = fraction
            return
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            shown = fraction
        }
    }
}

#Preview("558 · Rail Demurrage Watch · Night") { RailDemurrageWatchScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("558 · Rail Demurrage Watch · Light") { RailDemurrageWatchScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
