# EusoTripiOSWidgets — staged code for the iPhone Widget Extension

This directory contains the code for an iPhone Widget Extension that
hasn't been wired up as an Xcode target yet. The Swift files are written
against the canonical types in the main EusoTrip target — they will
compile cleanly once added to a Widget Extension's target membership.

## What's in here

| File | Renders |
|------|---------|
| `EusoTripiOSWidgetsBundle.swift` | `@main` `WidgetBundle` — declares all widgets the extension exposes |
| `ShipperLoadLiveActivityWidget.swift` | Lock Screen + Dynamic Island for an active load (uses `ShipperLoadActivityAttributes`) |
| `ShipperLoadHomeScreenWidget.swift` | Small / Medium / Large home-screen widget for the active load |
| `Info.plist` | Extension Info.plist (`NSExtensionPointIdentifier = com.apple.widgetkit-extension`) |

## What the in-app side already ships (committed)

These can call into the widget extension as soon as it exists:

- `EusoTrip/Services/ShipperLoadActivityAttributes.swift`
  — `ActivityAttributes` schema + `ShipperLoadLiveActivityController`
  for `start` / `update` / `end`.
- `EusoTrip/Services/ShipperHandoffContinuity.swift`
  — `NSUserActivity` Handoff broker.
- `EusoTrip/Services/ShipperHapticEscalation.swift`
  — Taptic + CoreHaptics wrist signatures.
- `EusoTrip/Services/ShipperAppIntents.swift`
  — 7 real `AppIntent` conformers wired to existing tRPC clients.
- `EusoTrip/Info.plist`
  — `NSSupportsLiveActivities` + `NSUserActivityTypes` declared.

## Steps to ship the Widget Extension target (Xcode UI)

1. **Open `EusoTrip.xcodeproj` in Xcode.**
2. **File → New → Target → Widget Extension.**
   - Product Name: `EusoTripiOSWidgets`
   - Bundle Identifier: `<main-app-bundle-id>.EusoTripiOSWidgets`
     (e.g., if main is `com.eusorone.eusotrip`, use
     `com.eusorone.eusotrip.EusoTripiOSWidgets`)
   - **Include Live Activity:** ✅ check the box.
   - Embed in Application: `EusoTrip`.
3. **Xcode generates a stub** `EusoTripiOSWidgets/` group with placeholder
   files. **Delete the placeholder files** Xcode generated, then **drag in**
   the four files already in this directory (the bundle, both widgets,
   and Info.plist) — Xcode will offer to update target membership; tick
   `EusoTripiOSWidgets` only.
4. **Add the shared schema to the new target's membership.** Select
   `EusoTrip/Services/ShipperLoadActivityAttributes.swift` in the
   navigator → File Inspector → Target Membership → tick
   `EusoTripiOSWidgets`. (It must compile in BOTH the main app and
   the widget extension so both sides reference the same
   `ActivityAttributes` type identity.)
5. **Add an App Group capability** to BOTH targets (Project →
   Signing & Capabilities → + Capability → App Groups). Use the
   same group identifier on both, e.g. `group.com.eusorone.eusotrip`.
   This lets the iPhone app write the active-load snapshot to a
   shared `UserDefaults` / file URL that the widget's
   `TimelineProvider` can read. The main app provides the writer;
   the widget provides the reader.
6. **Build the widget scheme** (Product → Scheme → choose
   `EusoTripiOSWidgets` → Cmd-B). It should compile clean once
   the shared attribute file is in target membership.
7. **Run on a real device** (Live Activities don't fire reliably
   on the simulator). Trigger a Live Activity from the app via
   `ShipperLoadLiveActivityController.shared.start(...)` — it
   should appear on the Lock Screen + Dynamic Island.

## What still requires Apple Developer Portal work

Even after the Widget Extension target lands, three Arc L surfaces
still need account-level provisioning that can't be done from code:

- **CarPlay (240)** — request the
  `com.apple.developer.carplay-charging` (or fleet equivalent)
  entitlement via developer.apple.com. Add a `CPSceneConfiguration`
  to main `Info.plist`. Fleet/freight CarPlay is currently
  approval-gated — Apple's commercial-vehicle program.
- **Apple Pay (239)** — provision a merchant ID + add Apple Pay
  capability to the main target. Requires the merchant agreement
  with Apple.
- **Watch Complication (233)** — the existing Watch App target
  already has scaffolding at `EusoTrip Pulse Watch App/Complications/`
  + `EusoTripWatchWidget/` (orphaned bundle). Wiring those into a
  watchOS Widget Extension target is parallel work to the iOS
  extension above; same Xcode UI flow but selecting **Widget
  Extension (watchOS)** as the target template.
