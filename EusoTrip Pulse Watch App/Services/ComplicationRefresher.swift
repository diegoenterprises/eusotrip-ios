//
//  ComplicationRefresher.swift
//  EusoTrip Watch App
//
//  Called from HOSStore / LoadStore after a data mutation so the wrist
//  complications re-render without waiting for their polling timeline.
//  Lives in the Watch App target (not the widget extension) because it
//  is the producer side — the widget extension only *receives* timeline
//  reload requests via WidgetCenter.
//

import WidgetKit

@MainActor
final class ComplicationRefresher {
    static let shared = ComplicationRefresher()
    private init() {}

    func reloadTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: "HOSComplication")
        WidgetCenter.shared.reloadTimelines(ofKind: "ActiveLoadComplication")
    }

    /// Reload every complication kind — cheaper than enumerating when
    /// multiple stores mutate at once (e.g., after a backend poll).
    func reloadAll() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
