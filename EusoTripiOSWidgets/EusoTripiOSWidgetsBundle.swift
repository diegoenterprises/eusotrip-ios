//
//  EusoTripiOSWidgetsBundle.swift
//  EusoTripiOSWidgets
//
//  iOS Widget Extension entry point. Declares every widget the
//  EusoTrip iPhone app surfaces:
//
//    · ShipperLoadLiveActivityWidget    — Lock Screen + Dynamic
//                                          Island for an active load
//                                          (driven by ActivityKit
//                                          via `ShipperLoadActivityAttributes`).
//    · ShipperLoadHomeScreenWidget      — small/medium/large home-
//                                          screen widget showing the
//                                          active load's lifecycle
//                                          stage + ETA.
//    · ShipperFocusModeWidget           — Focus filter passthrough
//                                          authoring (ON-DEVICE
//                                          companion to 235's preview
//                                          surface).
//
//  ⚠ This file is NOT yet wired into a Widget Extension target. To
//  ship on-device widget rendering, create a new Xcode target via
//  File → New → Target → Widget Extension, name it
//  `EusoTripiOSWidgets`, and add this directory's files + the
//  `ShipperLoadActivityAttributes` type from
//  `EusoTrip/Services/ShipperLoadActivityAttributes.swift` to that
//  target's membership. The shared attribute type lets the iPhone
//  app's `ShipperLoadLiveActivityController.start(...)` and the
//  widget bundle's `ActivityConfiguration(for:)` both reference the
//  exact same schema.
//
//  Once the target ships, iOS automatically picks up the
//  `ActivityConfiguration` and `Widget` declarations below — no
//  additional registration is required.
//

import WidgetKit
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

@main
struct EusoTripiOSWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // Live Activity (Lock Screen + Dynamic Island) — only
        // available on iOS 16.1+. The widget extension auto-
        // dispatches to the Driver vs Shipper variant based on
        // the attributes type the running activity declares.
        if #available(iOS 16.1, *) {
            ShipperLoadLiveActivityWidget()
        }
        // Home screen widgets are iOS 14+ — no availability gate
        // needed since the project deploys iOS 17.
        ShipperLoadHomeScreenWidget()
    }
}
