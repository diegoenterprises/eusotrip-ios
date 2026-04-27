//
//  ActiveLoadComplication.swift
//  EusoTrip Watch App
//
//  Complication showing the current load — origin → destination, pickup
//  time, hazmat flag. Tap targets the in-app load detail surface.
//

import WidgetKit
import SwiftUI

struct ActiveLoadEntry: TimelineEntry {
    let date: Date
    let load: WatchLoad?
}

struct ActiveLoadProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActiveLoadEntry {
        ActiveLoadEntry(date: Date(), load: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ActiveLoadEntry) -> Void) {
        completion(ActiveLoadEntry(date: Date(), load: loadFromDisk() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ActiveLoadEntry>) -> Void) {
        let entry = ActiveLoadEntry(date: Date(), load: loadFromDisk())
        completion(Timeline(
            entries: [entry],
            policy: .after(Date().addingTimeInterval(EusoTripConfig.complicationRefreshSeconds))
        ))
    }

    private func loadFromDisk() -> WatchLoad? {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let url = dir?.appendingPathComponent("loads.json"),
              let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(LoadsSnapshot.self, from: data) else { return nil }
        return snap.active
    }

    private struct LoadsSnapshot: Codable {
        let active: WatchLoad?
        let upcoming: [WatchLoad]
        let ts: Date
    }
}

struct ActiveLoadComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: ActiveLoadEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: entry.load?.hazmat == true ? "exclamationmark.triangle.fill" : "shippingbox.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text(entry.load?.destState ?? "---")
                    .font(.system(size: 10, weight: .semibold))
            }
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 14, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.load?.displayId ?? "No load")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("\(entry.load?.originShort ?? "-") → \(entry.load?.destShort ?? "-")")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        case .accessoryInline:
            if let load = entry.load {
                Text("\(load.displayId) · \(load.destShort)")
                    .font(.system(size: 12, weight: .medium))
            } else {
                Text("No active load")
            }
        default:
            Text(entry.load?.displayId ?? "-")
        }
    }
}

struct ActiveLoadComplication: Widget {
    let kind: String = "ActiveLoadComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActiveLoadProvider()) { entry in
            ActiveLoadComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Active Load")
        .description("Shows your current load and destination.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// Widget bundle (@main) lives in
// EusoTripWatchWidget/EusoTripWatchWidgetBundle.swift — it declares this
// complication + HOSComplication as the two widgets exposed on the face.
