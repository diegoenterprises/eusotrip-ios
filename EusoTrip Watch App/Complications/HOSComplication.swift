//
//  HOSComplication.swift
//  EusoTrip Watch App
//
//  WidgetKit complication showing remaining drive hours at a glance.
//  Families:
//    - .accessoryCircular      (corner of a face)
//    - .accessoryRectangular   (modular face row)
//    - .accessoryInline        (inline text)
//
//  Data source: HOSStore's persisted snapshot, read from the shared
//  Application Support file so the widget extension can stay in sync
//  without a live app launch.
//

import WidgetKit
import SwiftUI

// MARK: - Entry

struct HOSComplicationEntry: TimelineEntry {
    let date: Date
    let hos: WatchHOS
}

// MARK: - Provider

struct HOSTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> HOSComplicationEntry {
        HOSComplicationEntry(date: Date(), hos: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (HOSComplicationEntry) -> Void) {
        let hos = loadFromDisk() ?? .placeholder
        completion(HOSComplicationEntry(date: Date(), hos: hos))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HOSComplicationEntry>) -> Void) {
        let hos = loadFromDisk() ?? .placeholder
        let now = Date()
        // Project forward one entry every 15 min for the next 2 hours so
        // the countdown ring updates even when the app isn't in foreground.
        var entries: [HOSComplicationEntry] = []
        for minuteStep in stride(from: 0, through: 120, by: 15) {
            let futureDate = now.addingTimeInterval(Double(minuteStep) * 60)
            var projected = hos
            if hos.status == .driving {
                projected.driveRemainingMinutes = max(0, hos.driveRemainingMinutes - minuteStep)
                projected.windowRemainingMinutes = max(0, hos.windowRemainingMinutes - minuteStep)
            }
            entries.append(HOSComplicationEntry(date: futureDate, hos: projected))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(EusoTripConfig.complicationRefreshSeconds))))
    }

    private func loadFromDisk() -> WatchHOS? {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let url = dir?.appendingPathComponent("hos.json"),
              let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(HOSPersistedSnapshot.self, from: data) else { return nil }
        return snap.hos
    }

    private struct HOSPersistedSnapshot: Codable {
        let hos: WatchHOS
        let ts: Date
    }
}

// MARK: - View

struct HOSComplicationView: View {
    @Environment(\.widgetFamily) var family
    let entry: HOSComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                Circle()
                    .stroke(Color.esangBorder, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: entry.hos.drivePct)
                    .stroke(
                        LinearGradient.esangPrimary,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(formatMinutes(entry.hos.driveRemainingMinutes))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("DRV")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: entry.hos.status.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.hos.driveHoursText)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("\(entry.hos.status.short) · win \(entry.hos.windowHoursText)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        case .accessoryInline:
            Text("HOS \(entry.hos.driveHoursText) drive")
                .font(.system(size: 12, weight: .medium))
        default:
            Text(entry.hos.driveHoursText)
        }
    }

    private func formatMinutes(_ m: Int) -> String {
        let h = m / 60
        let mm = m % 60
        return h > 0 ? "\(h)h" : "\(mm)m"
    }
}

// MARK: - Widget

struct HOSComplication: Widget {
    let kind: String = "HOSComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HOSTimelineProvider()) { entry in
            HOSComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("HOS Hours")
        .description("Shows remaining drive and duty hours.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// ComplicationRefresher lives in EusoTrip Watch App/Services/ so it can
// be called from HOSStore/LoadStore on the Watch App side — this file is
// intended for membership in the Widget Extension target only.
