//
//  HereTypicalSpeedChip.swift
//  EusoTrip — typical-speed annotation backed by HERE Real-Time
//  Traffic v7 flow (free-flow baseline speed per link).
//
//  Why this is here:
//    The live `speed` says how fast traffic is moving right now;
//    the `freeFlow` baseline says how fast the road *typically*
//    flows with no congestion. That baseline anchors a driver's
//    self-pacing — a spot reading of 58 mph means one thing on a
//    65-mph corridor, another on a 40-mph one — and feeds the
//    "am I early/late vs the lane" narrative ESANG renders on
//    035's bottom summary.
//
//  Behaviour:
//    • Reads the live coordinate from DriverLocationResolver.
//    • Calls HereTrafficClient.flow(near:radiusMeters:) on the v7
//      `data.traffic.hereapi.com/v7/flow` endpoint.
//    • Reads each link's `currentFlow.freeFlow` (meters/second),
//      converts to mph (×2.23694), and renders the median across
//      returned links as a single inline pill.
//    • Hides cleanly when location is denied, the request fails
//      (quiet fail), or no links sit inside the radius.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

@MainActor
final class HereTypicalSpeedStore: ObservableObject {
    @Published private(set) var medianSpeed: Double?
    @Published private(set) var sampleCount: Int = 0

    /// Meters/second → mph.
    private let mpsToMph: Double = 2.23694

    /// ~12 km radius around the fix. Keep it tight so HERE returns a
    /// set of links representative of the driver's immediate corridor
    /// instead of the whole metro.
    private let radiusMeters: Int = 12_000

    func refresh() async {
        guard let coord = await DriverLocationResolver.shared.currentCoordinate() else {
            medianSpeed = nil
            sampleCount = 0
            return
        }
        let results: [HereTrafficFlowResult]
        do {
            results = try await HereTrafficClient.shared.flow(
                near: coord,
                radiusMeters: radiusMeters
            )
        } catch {
            // Quiet fail — chip hides until next refresh succeeds.
            medianSpeed = nil
            sampleCount = 0
            return
        }
        // `freeFlow` is the typical (uncongested) speed baseline in
        // meters/second; convert to mph for the chip.
        let speeds = results.compactMap { $0.currentFlow?.freeFlow }
            .filter { $0 > 0 }
            .map { $0 * mpsToMph }
            .sorted()
        guard !speeds.isEmpty else {
            medianSpeed = nil
            sampleCount = 0
            return
        }
        let mid = speeds.count / 2
        medianSpeed = speeds.count.isMultiple(of: 2)
            ? (speeds[mid - 1] + speeds[mid]) / 2
            : speeds[mid]
        sampleCount = speeds.count
    }
}

struct HereTypicalSpeedChip: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = HereTypicalSpeedStore()

    var body: some View {
        Group {
            if let mph = store.medianSpeed {
                HStack(spacing: 6) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("TYPICAL \(Int(mph.rounded())) mph")
                        .font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: 0)
                    Text("EUSOTRIP · n=\(store.sampleCount)")
                        .font(EType.micro).tracking(0.4)
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(palette.bgCardSoft)
                .overlay(
                    Capsule()
                        .strokeBorder(palette.borderFaint)
                )
                .clipShape(Capsule())
            } else {
                EmptyView()
            }
        }
        .task { await store.refresh() }
    }
}

#Preview("HereTypicalSpeedChip · Dark") {
    HereTypicalSpeedChip()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
        .padding()
        .background(Theme.dark.bgPage)
}

#Preview("HereTypicalSpeedChip · Light") {
    HereTypicalSpeedChip()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
        .padding()
        .background(Theme.light.bgPage)
}
