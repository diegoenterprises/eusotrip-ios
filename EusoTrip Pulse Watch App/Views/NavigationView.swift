//
//  NavigationView.swift
//  EusoTrip Pulse Watch App
//
//  F14 — Turn-by-turn surface for the keep-alive navigation session.
//
//  Layout (top → bottom):
//    1. Big maneuver glyph — rotation cue the driver can see in their
//       peripheral vision without looking straight at the wrist.
//    2. Distance-to-turn readout (feet < 1000, else tenths of a mile).
//    3. Instruction text — road name if present.
//    4. Remaining miles to destination + a single-line progress bar.
//    5. End button at the bottom so the driver can always bail.
//

import SwiftUI
import WatchKit

struct NavigationSessionView: View {
    @ObservedObject private var nav = NavigationSession.shared

    // SwiftUI's built-in `NavigationView` name is reserved for the
    // classic stack container, so we disambiguate by calling this
    // one `NavigationSessionView`. Anything that used to push
    // `NavigationView()` (the app's old plain name) should push
    // `NavigationSessionView()` instead.

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 6) {
                    if nav.hasArrived {
                        arrivedBlock
                    } else if let m = nav.nextManeuver {
                        maneuverGlyph(m)
                        distanceReadout
                        instructionText(m)
                        progressStrip
                        endButton
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }

            // Modular Ultra bezel — navigation summary in the four
            // corner labels so the driver keeps glanceable context
            // even when scrolling past the maneuver glyph.
            ModularTickBezel(
                corners: .init(
                    topLeading:     navCornerNextManeuver,
                    topTrailing:    navCornerBand,
                    bottomLeading:  navCornerRemaining,
                    bottomTrailing: navCornerRouteLeft
                )
            )
            .allowsHitTesting(false)
        }
        .navigationTitle("Route")
    }

    // MARK: - Modular Ultra corner labels
    //
    // These match the real NavigationSession API:
    //   - `band: ManeuverBand` with cases far / tentative / headsUp /
    //     turnNow / passed — used for haptic de-dupe, not ETA.
    //   - `distanceToNextMeters` — meters to the active maneuver.
    //   - `remainingMeters` — meters left on the whole route.
    //   - No etaDate exists; we surface route-distance instead.

    private var navCornerNextManeuver: String {
        guard !nav.hasArrived, let m = nav.nextManeuver else {
            return nav.hasArrived ? "ARRIVED" : "NO ROUTE"
        }
        switch m.kind {
        case .depart:      return "DEPART"
        case .turnLeft:    return "LEFT"
        case .turnRight:   return "RIGHT"
        case .slightLeft:  return "SL LEFT"
        case .slightRight: return "SL RIGHT"
        case .sharpLeft:   return "SH LEFT"
        case .sharpRight:  return "SH RIGHT"
        case .keepLeft:    return "KEEP L"
        case .keepRight:   return "KEEP R"
        case .uTurn:       return "U TURN"
        case .merge:       return "MERGE"
        case .exit:        return "EXIT"
        case .ferry:       return "FERRY"
        case .tollPlaza:   return "TOLL"
        case .roundabout:  return "RNDABT"
        case .arrive:      return "ARRIVE"
        }
    }

    private var navCornerBand: String {
        // Proximity band — the Apple Watch Ultra UI convention for a
        // short distance-class label. Maps onto the haptic tiers.
        switch nav.band {
        case .far:       return "FAR"
        case .tentative: return "~2 MI"
        case .headsUp:   return "~1 MI"
        case .turnNow:   return "NOW"
        case .passed:    return "PASSED"
        }
    }

    private var navCornerRemaining: String {
        let meters = nav.distanceToNextMeters
        if !meters.isFinite { return "—" }
        if meters < 305 { return "\(Int(meters * 3.28084)) FT" }
        return String(format: "%.1f MI", meters / 1609.34)
    }

    private var navCornerRouteLeft: String {
        let meters = nav.remainingMeters
        if meters <= 0 || !meters.isFinite { return "—" }
        return String(format: "%.0f MI LEFT", meters / 1609.34)
    }

    // MARK: - Maneuver glyph

    @ViewBuilder
    private func maneuverGlyph(_ m: Maneuver) -> some View {
        Image(systemName: m.kind.glyph)
            .font(.system(size: 40, weight: .bold))
            .foregroundStyle(bandTint(nav.band))
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }

    // MARK: - Distance readout

    @ViewBuilder
    private var distanceReadout: some View {
        let meters = nav.distanceToNextMeters
        VStack(spacing: 0) {
            Text(formatDistance(meters))
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(bandTint(nav.band))
            Text(meters < 305 ? "FT" : "MI")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters.isInfinite || meters.isNaN { return "—" }
        if meters < 305 { // under 1000 ft
            let feet = meters * 3.28084
            // Round to nearest 10 ft so the display doesn't flicker.
            let rounded = (feet / 10).rounded() * 10
            return String(format: "%.0f", max(0, rounded))
        }
        let miles = meters / 1609.344
        if miles < 10 {
            return String(format: "%.1f", miles)
        }
        return String(format: "%.0f", miles)
    }

    // MARK: - Instruction text

    @ViewBuilder
    private func instructionText(_ m: Maneuver) -> some View {
        VStack(spacing: 2) {
            Text(m.instruction)
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            if let road = m.road, !road.isEmpty {
                Text(road.uppercased())
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Progress strip

    @ViewBuilder
    private var progressStrip: some View {
        let totalMeters = nav.maneuvers.last?.cumulativeMeters ?? 0
        let remaining = nav.remainingMeters
        let progress: Double = {
            guard totalMeters > 0 else { return 0 }
            return max(0, min(1, 1 - (remaining / totalMeters)))
        }()
        VStack(spacing: 2) {
            HStack {
                Text("\(formatMiles(remaining)) mi left")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(nav.currentIndex + 1)/\(nav.maneuvers.count)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .tint(.esangBlue)
        }
        .padding(.top, 2)
    }

    private func formatMiles(_ meters: Double) -> String {
        let miles = meters / 1609.344
        if miles < 10 { return String(format: "%.1f", miles) }
        return String(format: "%.0f", miles)
    }

    // MARK: - End button

    @ViewBuilder
    private var endButton: some View {
        Button {
            WKInterfaceDevice.current().play(.stop)
            nav.endRoute()
        } label: {
            Text("End Route")
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
        }
        .tint(.secondary)
        .padding(.top, 4)
    }

    // MARK: - Arrived + empty

    @ViewBuilder
    private var arrivedBlock: some View {
        VStack(spacing: 6) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color.esangGreen)
            Text("Arrived")
                .font(.system(size: 18, weight: .heavy))
            Text("Confirm paperwork in the load card.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Close") {
                nav.endRoute()
            }
            .tint(.secondary)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "location.slash")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("No active route")
                .font(.caption.bold())
            Text("Start navigation from iPhone.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 20)
    }

    // MARK: - Colors

    private func bandTint(_ band: ManeuverBand) -> Color {
        switch band {
        case .far:        return .primary
        case .tentative:  return .esangAmber
        case .headsUp:    return .esangAmber
        case .turnNow:    return .esangDanger
        case .passed:     return .secondary
        }
    }
}

#if DEBUG
struct NavigationSessionView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationSessionView()
    }
}
#endif
