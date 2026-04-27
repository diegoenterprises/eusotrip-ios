//
//  EusoTripWatchWidgetBundle.swift
//  EusoTripWatchWidget
//
//  Entry point for the watchOS widget extension. Declares all
//  complications surfaced on the watch face. Register new complications
//  by adding them to the `body` WidgetBundle below.
//
//  Shared model types (WatchHOS, WatchLoad) and tokens (EusoTripConfig,
//  WatchTheme) live in the Watch App target but must also be added to
//  this extension's target membership so the complication views compile.
//

import WidgetKit
import SwiftUI

@main
struct EusoTripWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        HOSComplication()
        ActiveLoadComplication()
    }
}
