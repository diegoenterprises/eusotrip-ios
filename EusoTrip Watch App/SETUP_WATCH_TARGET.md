# Add the Watch App + Widget Extension targets in Xcode

The three **iOS-side bridge files** are already wired into the existing
iOS target (WatchAuthBridge.swift, WatchCommandHandler.swift,
EusoTripApp+WatchBridge.swift). What remains is creating the two new
watchOS targets via the Xcode wizard — this step must happen in Xcode
because the `pbxproj` library cannot safely edit projects that use Swift
Package Product dependencies (Lottie, etc.).

Total time: **~15 minutes**.

---

## 1. Add the Watch App target

1. Open `EusoTrip.xcodeproj` in Xcode.
2. **File → New → Target…**
3. Pick the **watchOS** tab → **App** → **Next**.
4. Fill in exactly:
   - Product Name: `EusoTripWatch`
   - Team: (your Eusorone Technologies team)
   - Organization Identifier: `com.app`
   - Bundle Identifier: `com.app.eusotrip.watchkitapp`
   - Language: **Swift**
   - Interface: **SwiftUI**
   - Include Notification Scene: **unchecked**
5. Click **Finish** → if prompted "Activate EusoTripWatch scheme?", click **Activate**.
6. Xcode generates boilerplate (`EusoTripWatchApp.swift`, `ContentView.swift`,
   `Assets.xcassets`, `Preview Content/`, `Info.plist`). **Delete all of
   these** from the target — we already have the real ones in
   `EusoTrip Watch App/`.
   - In the navigator, expand the new `EusoTripWatch` group
   - Select the auto-generated files → Delete → **Move to Trash**
7. In the navigator, right-click the empty `EusoTripWatch` group →
   **Add Files to "EusoTrip"…** → select the entire
   `EusoTrip Watch App/` folder → **ensure**:
   - ✅ "Copy items if needed" = **unchecked** (files already on disk)
   - ✅ "Create groups" = selected
   - ✅ Targets → only **EusoTripWatch** is ticked (NOT EusoTrip, NOT EusoTripWatchWidget yet)
   - Click **Add**
8. Click the project in the navigator → select the **EusoTripWatch**
   target → **General**:
   - Display Name: `EusoTrip`
   - Bundle Identifier: `com.app.eusotrip.watchkitapp`
   - Version: `1.0`
   - Build: `8`
   - Minimum Deployments: watchOS **10.0**
9. **Info** tab → set **Custom iOS Target Properties** to the contents
   of `EusoTrip Watch App/Info.plist` (easiest: right-click Info.plist
   in the navigator → Open As → Source Code, copy everything, paste into
   Info tab source view).
   - Or simpler: in Build Settings, set `INFOPLIST_FILE` to
     `EusoTrip Watch App/Info.plist`.
10. **Signing & Capabilities** tab:
    - Automatically manage signing: **on**
    - Team: Eusorone Technologies
    - Click **+ Capability** → add:
      - **HealthKit** (tick "Background Delivery" under the row)
      - **App Groups** → check `group.com.app.eusotrip`
      - **Push Notifications**
    - The entitlements file at `EusoTrip Watch App/EusoTripWatch.entitlements`
      should be auto-wired; if not, set `CODE_SIGN_ENTITLEMENTS` in Build
      Settings to that path.

---

## 2. Add the Widget Extension target

1. **File → New → Target…**
2. Pick the **watchOS** tab → **Widget Extension** → **Next**.
3. Fill in:
   - Product Name: `EusoTripWatchWidget`
   - Team: Eusorone Technologies
   - Bundle Identifier: `com.app.eusotrip.watchkitapp.widget`
   - Include Configuration App Intent: **unchecked** (we use StaticConfiguration)
   - Include Live Activity: **unchecked** (Live Activities live in the Watch App target, not here)
   - Embed in Application: **EusoTripWatch**
4. Click **Finish** → **Activate** if prompted.
5. Xcode generates `EusoTripWatchWidget.swift`, `EusoTripWatchWidgetBundle.swift`,
   `Info.plist`, entitlements, assets — **delete all of them** (Move to Trash).
6. Right-click the `EusoTripWatchWidget` group → **Add Files to "EusoTrip"…**
   Select:
   - `EusoTripWatchWidget/EusoTripWatchWidgetBundle.swift` (our @main bundle)
   - `EusoTripWatchWidget/Info.plist`
   - `EusoTripWatchWidget/EusoTripWatchWidget.entitlements`
   Targets: only **EusoTripWatchWidget** ticked.
7. **Now add the two complication Swift files to the widget extension
   target**. Navigate to `EusoTrip Watch App/Complications/` in the
   navigator, select:
   - `HOSComplication.swift`
   - `ActiveLoadComplication.swift`
   In the File Inspector (right panel), under **Target Membership**:
   - ✅ EusoTripWatchWidget (tick)
   - ❌ EusoTripWatch (unticked) — these are widget-only
8. **Shared model + config files must be members of BOTH targets**
   (Watch App and Widget Extension), because the complications reference
   them. Select each of the following in the navigator and tick both
   target memberships:
   - `EusoTrip Watch App/Models/WatchHOS.swift` → EusoTripWatch **+** EusoTripWatchWidget
   - `EusoTrip Watch App/Models/WatchLoad.swift` → EusoTripWatch **+** EusoTripWatchWidget
   - `EusoTrip Watch App/EusoTripConfig.swift` → EusoTripWatch **+** EusoTripWatchWidget
   - `EusoTrip Watch App/WatchTheme.swift` → EusoTripWatch **+** EusoTripWatchWidget
9. **Signing & Capabilities** for the Widget target:
   - Team: Eusorone Technologies
   - **+ Capability** → **App Groups** → `group.com.app.eusotrip`
10. **General** tab:
    - Version: `1.0`, Build: `8`
    - Minimum Deployments: watchOS 10.0

---

## 3. Add the Watch App to the iOS target's "Embed Watch Content"

1. Select the project → **EusoTrip** (iOS) target → **General**.
2. Scroll to **Frameworks, Libraries, and Embedded Content**.
3. If the Watch app isn't already embedded (Xcode usually does this
   automatically when you add a watch target, but verify), click **+** →
   `EusoTripWatch.app` → **Embed Without Signing** (Xcode signs it
   during archive).

---

## 4. Sanity build

In Xcode's scheme selector (top bar), switch to **EusoTripWatch → Apple Watch Series 10 (Simulator)** and hit **⌘B**.

Expected: ✅ Build Succeeded.

Then switch to **EusoTrip → iPhone 16 Pro** and ⌘B. Expected: ✅ Build Succeeded (with the three new iOS bridge files compiled in).

---

## 5. Archive & upload (build 8)

When both targets build clean:

1. Switch scheme to **EusoTrip → Any iOS Device (arm64)**.
2. **Product → Archive**.
3. Xcode archives iOS + Watch App + Widget as one `.xcarchive`.
4. In the Organizer that pops up: **Distribute App** → **App Store Connect** → **Upload** → follow prompts.

App Store Connect will automatically associate the watch app with the
iOS app because they share the `com.app.eusotrip` prefix and the
`WKCompanionAppBundleIdentifier` is set correctly in `Info.plist`.

---

## Troubleshooting

**"ExtensionDelegate" not found.** The Info.plist references
`$(PRODUCT_MODULE_NAME).ExtensionDelegate` but watchOS 10+ SwiftUI apps
don't need this key. If the build complains, remove the
`WKExtensionDelegateClassName` line from `EusoTrip Watch App/Info.plist`.

**"Cannot find 'ComplicationRefresher' in scope" in HOSStore.** Confirm
that `EusoTrip Watch App/Services/ComplicationRefresher.swift` is a
member of the EusoTripWatch target.

**"Cannot find 'WatchHOS' in scope" in HOSComplication.** The shared
model files (step 8 above) must have BOTH target memberships ticked.

**Widget doesn't appear on the watch face.** After install, long-press
the watch face → Edit → rotate to the complication slot → tap + → scroll
to the EusoTrip section. The system can take 30–60 seconds to index
freshly-installed complications.

**"Provisioning profile couldn't be created" for the new bundle IDs.**
In App Store Connect → Certificates, Identifiers & Profiles → Identifiers,
register `com.app.eusotrip.watchkitapp` and
`com.app.eusotrip.watchkitapp.widget` before you attempt Archive.
