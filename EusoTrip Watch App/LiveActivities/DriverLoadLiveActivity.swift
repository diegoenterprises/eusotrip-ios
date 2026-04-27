//
//  DriverLoadLiveActivity.swift
//  EusoTrip Watch App
//
//  The WidgetKit-rendered UI for the shared DriverLoadActivityAttributes.
//  watchOS picks this up automatically for the Smart Stack; iOS uses the
//  same code for Lock Screen and Dynamic Island.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct DriverLoadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DriverLoadActivityAttributes.self) { context in
            // Lock screen / full banner presentation.
            LockScreenLoadView(context: context)
                .padding(12)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.loadDisplayId, systemImage: "shippingbox.fill")
                        .font(.system(size: 14, weight: .semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.etaMinutes)m ETA")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("\(context.attributes.originCity) → \(context.attributes.destCity)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label("\(context.state.milesRemaining) mi", systemImage: "road.lanes")
                            .font(.system(size: 11))
                        Spacer()
                        Label(driveTime(for: context.state.hosDriveRemainingMinutes), systemImage: "clock.fill")
                            .font(.system(size: 11))
                    }
                }
            } compactLeading: {
                Image(systemName: "shippingbox.fill")
            } compactTrailing: {
                Text("\(context.state.etaMinutes)m")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            } minimal: {
                Image(systemName: "shippingbox.fill")
            }
        }
    }

    private func driveTime(for minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return String(format: "%dh %02dm", h, m)
    }
}

private struct LockScreenLoadView: View {
    let context: ActivityViewContext<DriverLoadActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(context.attributes.loadDisplayId, systemImage: "shippingbox.fill")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                if context.attributes.hazmat {
                    Text("HAZMAT")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.esangHazmat, in: Capsule())
                }
            }
            HStack(spacing: 8) {
                Text(context.attributes.originCity)
                    .font(.system(size: 16, weight: .semibold))
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Text(context.attributes.destCity)
                    .font(.system(size: 16, weight: .semibold))
            }
            Text(context.state.nextWaypoint)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack {
                Label("\(context.state.etaMinutes)m ETA", systemImage: "timer")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Label("\(context.state.milesRemaining) mi", systemImage: "road.lanes")
                    .font(.system(size: 12))
            }
            .foregroundStyle(.white)
        }
    }
}
