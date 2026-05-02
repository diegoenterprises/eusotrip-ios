//
//  ShipperLoadLiveActivityWidget.swift
//  EusoTripiOSWidgets
//
//  ActivityKit-rendered Live Activity widget for the iPhone Lock
//  Screen + Dynamic Island. Sister of the existing
//  `DriverLoadLiveActivity` shipped in
//  `EusoTrip Pulse Watch App/LiveActivities/DriverLoadLiveActivity.swift`,
//  but built around the `ShipperLoadActivityAttributes` schema
//  from `EusoTrip/Services/ShipperLoadActivityAttributes.swift`.
//
//  The visual layout mirrors the preview surface in
//  `EusoTrip/Views/Shipper/232_ShipperLockScreenLiveActivity.swift`
//  so the in-app preview and the on-device render carry the same
//  shape.
//
//  ⚠ This file is staged for the iOS Widget Extension target that
//  has not yet been wired up. See the bundle file's header comment
//  for the Xcode UI steps to create the extension target and add
//  these files to its membership.
//

import SwiftUI
#if canImport(ActivityKit) && canImport(WidgetKit)
import ActivityKit
import WidgetKit

@available(iOS 16.1, *)
struct ShipperLoadLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ShipperLoadActivityAttributes.self) { context in
            // Lock Screen banner.
            LockScreenView(context: context)
                .padding(12)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let secs = context.state.etaSeconds, secs > 0 {
                        Text(formatDuration(secs))
                            .font(.system(size: 14, weight: .heavy, design: .monospaced))
                            .foregroundStyle(context.state.alerting ? .red : .white)
                    } else {
                        Text("—")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.loadNumber)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 6) {
                        Text(context.state.stageLabel.uppercased())
                            .font(.system(size: 10, weight: .heavy))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(context.state.alerting ? Color.red : Color.green.opacity(0.7)))
                        Text(context.state.laneSummary)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer()
                    }
                }
            } compactLeading: {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.white)
            } compactTrailing: {
                if let secs = context.state.etaSeconds, secs > 0 {
                    Text(formatDuration(secs))
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(context.state.alerting ? .red : .white)
                } else {
                    Text("—").font(.system(size: 12, weight: .heavy, design: .monospaced))
                }
            } minimal: {
                Image(systemName: context.state.alerting ? "exclamationmark.triangle.fill" : "shippingbox.fill")
                    .foregroundStyle(context.state.alerting ? .red : .white)
            }
        }
    }
}

// MARK: - Lock Screen view

@available(iOS 16.1, *)
private struct LockScreenView: View {
    let context: ActivityViewContext<ShipperLoadActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(context.attributes.loadNumber)
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                Spacer()
                stagePill
            }
            Text(context.state.laneSummary)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
            HStack(spacing: 16) {
                stat("ETA", value: etaText)
                stat("MILES", value: milesText)
                stat("DRIVER", value: context.state.driverName)
            }
        }
        .foregroundStyle(.white)
    }

    private var stagePill: some View {
        Text("STAGE \(context.state.stageIndex + 1)/8 · \(context.state.stageLabel.uppercased())")
            .font(.system(size: 9, weight: .heavy))
            .tracking(0.6)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(context.state.alerting ? Color.red : Color.green.opacity(0.7)))
    }

    private var etaText: String {
        guard let s = context.state.etaSeconds, s > 0 else { return "—" }
        return formatDuration(s)
    }
    private var milesText: String {
        guard let m = context.state.distanceRemainingMi else { return "—" }
        return "\(m) mi"
    }

    private func stat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9, weight: .heavy))
                .tracking(0.6).foregroundStyle(.white.opacity(0.6))
            Text(value).font(.system(size: 12, weight: .heavy, design: .monospaced))
        }
    }
}

// MARK: - Helpers

private func formatDuration(_ seconds: Int) -> String {
    if seconds < 60 { return "\(seconds)s" }
    let m = seconds / 60
    if m < 60 { return "\(m)m" }
    let h = m / 60
    let rm = m % 60
    return rm == 0 ? "\(h)h" : "\(h)h \(rm)m"
}

#endif
