//
//  HereTypicalSpeedChip.swift
//  EusoTrip — typical-speed annotation backed by HERE Traffic
//  Analytics flow.json (historical aggregated speeds per link).
//
//  Why this is here:
//    HereTrafficClient surfaces *live* flow / incidents. Analytics
//    answers a different question: "what's the typical pace on
//    this stretch at this hour?" That number anchors a driver's
//    self-pacing — a spot reading of 58 mph means one thing on a
//    65-mph corridor, another on a 40-mph one — and feeds the
//    "am I early/late vs the lane" narrative ESANG renders on
//    035's bottom summary.
//
//  Behaviour:
//    • Reads the live coordinate from DriverLocationResolver.
//    • Builds a small ~8-mile bbox around the fix.
//    • Calls HereTrafficAnalyticsClient.typicalFlow(bbox:).
//    • Picks the median typical speed across returned links and
//      renders it as a single inline pill.
//    • Hides cleanly when location is denied, the tenant key
//      lacks Analytics access (HERE returns 403 → quiet fail),
//      or no links sit inside the bbox.
//
//  Powered by ESANG AI™.
//

import SwiftUI
import CoreLocation

@MainActor
final class HereTypicalSpeedStore: ObservableObject {
    @Published private(set) var medianSpeed: Double?
    @Published private(set) var sampleCount: Int = 0

    /// ~0.07° latitude ≈ 8 km north–south. Keep the bbox small so
    /// HERE returns a tight set of links representative of the
    /// driver's immediate corridor instead of the whole metro.
    private let halfSpanLat: Double = 0.07
    private let halfSpanLng: Double = 0.07

    func refresh() async {
        guard let coord = await DriverLocationResolver.shared.currentCoordinate() else {
            medianSpeed = nil
            sampleCount = 0
            return
        }
        let bbox = (
            minLng: coord.longitude - halfSpanLng,
            minLat: coord.latitude  - halfSpanLat,
            maxLng: coord.longitude + halfSpanLng,
            maxLat: coord.latitude  + halfSpanLat
        )
        let items: [HereAnalyticsFlowItem]
        do {
            items = try await HereTrafficAnalyticsClient.shared.typicalFlow(
                bbox: bbox,
                time: Date()
            )
        } catch {
            // Quiet fail — chip hides until next refresh succeeds.
            medianSpeed = nil
            sampleCount = 0
            return
        }
        let speeds = items.compactMap { $0.typicalSpeed ?? $0.speed }
            .filter { $0 > 0 }
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
