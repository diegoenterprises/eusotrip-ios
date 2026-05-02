//
//  ShipperLoadHomeScreenWidget.swift
//  EusoTripiOSWidgets
//
//  Home Screen widget rendering the shipper's active load (or the
//  next-up posted load when none is in transit). Three families:
//  small / medium / large. Mirrors the rendering authored in the
//  in-app preview at
//  `EusoTrip/Views/Shipper/236_ShipperWidgetGallery.swift`.
//
//  Timeline: refreshes every 15 minutes via the standard
//  `WidgetCenter` schedule. Backed by a static placeholder when the
//  user is not signed in or the API is unreachable; never fabricates
//  load data.
//
//  ⚠ Not yet wired to a Widget Extension target. Drag this file +
//  `EusoTripiOSWidgetsBundle.swift` + `ShipperLoadLiveActivityWidget.swift`
//  + `EusoTrip/Services/ShipperLoadActivityAttributes.swift` into the
//  new target's membership when creating the extension via Xcode.
//

import SwiftUI
import WidgetKit

struct ShipperLoadHomeScreenWidget: Widget {
    private let kind = "com.eusorone.eusotrip.ShipperLoadWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ShipperLoadProvider()) { entry in
            ShipperLoadWidgetView(entry: entry)
        }
        .configurationDisplayName("EusoTrip Active Load")
        .description("Lane, stage, and ETA for the load currently in motion.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Timeline entry + provider

struct ShipperLoadEntry: TimelineEntry {
    let date: Date
    let loadNumber: String
    let stageLabel: String
    let stageIndex: Int   // 0...7
    let laneSummary: String
    let etaSeconds: Int?
    let distanceRemainingMi: Int?
    let alerting: Bool

    static let placeholder = ShipperLoadEntry(
        date: Date(),
        loadNumber: "—",
        stageLabel: "Idle",
        stageIndex: 0,
        laneSummary: "Sign in to see your active load.",
        etaSeconds: nil,
        distanceRemainingMi: nil,
        alerting: false
    )
}

struct ShipperLoadProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShipperLoadEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (ShipperLoadEntry) -> Void) {
        // Real production widget would query the active load from a
        // shared App Group container that the iPhone app writes to
        // when its `ShipperActiveLoadsStore` refreshes. The placeholder
        // is the honest fallback when the App Group is empty (signed
        // out / fresh install / cleared).
        completion(.placeholder)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShipperLoadEntry>) -> Void) {
        // 15-minute refresh cadence. The iPhone app posts
        // `WidgetCenter.shared.reloadAllTimelines()` whenever a load
        // status change lands in the active-loads store, so the
        // widget refreshes quickly when something happens AND falls
        // back to the timeline cadence when the app is dormant.
        let entry = ShipperLoadEntry.placeholder
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Render

struct ShipperLoadWidgetView: View {
    let entry: ShipperLoadEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:  small
        case .systemMedium: medium
        case .systemLarge:  large
        default:            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.loadNumber)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
            Text(entry.stageLabel.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(entry.alerting ? Color.red : Color.green.opacity(0.7)))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Text(entry.laneSummary)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
            if let s = entry.etaSeconds {
                Text("ETA \(formatDuration(s))")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.loadNumber)
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                Text(entry.laneSummary)
                    .font(.system(size: 12, weight: .semibold)).lineLimit(2)
                Spacer(minLength: 0)
                Text(entry.stageLabel.uppercased())
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(entry.alerting ? Color.red : Color.green.opacity(0.7)))
                    .foregroundStyle(.white)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let s = entry.etaSeconds {
                    Text("ETA")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(.secondary)
                    Text(formatDuration(s))
                        .font(.system(size: 22, weight: .heavy, design: .monospaced))
                }
                if let m = entry.distanceRemainingMi {
                    Text("\(m) MI")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.loadNumber)
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                Spacer()
                Text(entry.stageLabel.uppercased())
                    .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(entry.alerting ? Color.red : Color.green.opacity(0.7)))
                    .foregroundStyle(.white)
            }
            Text(entry.laneSummary)
                .font(.system(size: 14, weight: .semibold))
            // 8-stage strip
            HStack(spacing: 4) {
                ForEach(0..<8, id: \.self) { i in
                    Capsule()
                        .fill(i <= entry.stageIndex
                              ? (entry.alerting ? Color.red : Color.green.opacity(0.85))
                              : Color.gray.opacity(0.3))
                        .frame(height: 6)
                }
            }
            HStack(spacing: 16) {
                if let s = entry.etaSeconds {
                    stat("ETA", value: formatDuration(s))
                }
                if let m = entry.distanceRemainingMi {
                    stat("MILES", value: "\(m)")
                }
                Spacer()
            }
            Spacer()
        }
        .padding(14)
    }

    private func stat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .heavy))
                .tracking(0.6).foregroundStyle(.secondary)
            Text(value).font(.system(size: 16, weight: .heavy, design: .monospaced))
        }
    }
}

private func formatDuration(_ seconds: Int) -> String {
    if seconds < 60 { return "\(seconds)s" }
    let m = seconds / 60
    if m < 60 { return "\(m)m" }
    let h = m / 60
    let rm = m % 60
    return rm == 0 ? "\(h)h" : "\(h)h \(rm)m"
}
