# EusoTrip · visionOS app target

**Status:** Scaffolding shipped 2026-05-20 (IO 2026 P0-16 lockstep). Xcode target activation pending — see activation checklist below.

## What's in this folder

- `EusoTripVisionApp.swift` — visionOS `@main` entry point. Hosts a flat root window + a volumetric `xr-prehaul` window for the immersive checklist.
- `Views/VisionXRPreHaulView.swift` — visionOS-native version of the iPhone P0-16 XR pre-haul checklist UI. Same server contract (`xrChecklist.getChecklist` + `confirmItem`), visionOS-native presentation.
- `Info.plist` — visionOS app plist with mic + speech recognition usage descriptions for hands-free confirmation.

## Why it's not built yet

Per founder's directive 2026-05-20 ("whatever XR you build for android type code you do also for vision os"), the server contract was designed to be platform-agnostic — the iOS P0-16 sprint locked in `xrChecklist.*` endpoints + the Ed25519-signed observation pattern. The visionOS target needs a new `PBXNativeTarget` entry in `EusoTrip.xcodeproj/project.pbxproj`, which is fragile when done via Bash/Edit alone (Xcode IDE has a one-click "Add Target" flow that does it safely).

## Activation checklist (when ready to ship)

1. Open `EusoTrip.xcodeproj` in Xcode.
2. **File → New → Target → visionOS App**. Name: `EusoTrip Vision App`. Bundle id: `com.app.eusotrip.vision`. Language: Swift.
3. When prompted "Activate scheme?" — yes.
4. In the new target's General tab:
   - Minimum deployments: **visionOS 1.0+**
   - Display name: `EusoTrip · Vision`
5. Delete the auto-generated `EusoTripVisionApp.swift` + `ContentView.swift` placeholders Xcode creates (we have our own).
6. In the Project Navigator, right-click the `EusoTrip Vision App` group → **Add Files to "EusoTrip"...** → select `EusoTripVisionApp.swift` + `Views/VisionXRPreHaulView.swift`. Tick **Copy items if needed = OFF** (files are already in the right folder) and **Add to targets: EusoTrip Vision App** (only — NOT the iPhone target).
7. Replace the auto-generated `Info.plist` with the one in this folder.
8. **Signing & Capabilities** tab on the new target:
   - Team: same as iPhone target (665Z3ZBZS2 per `build/ExportOptions.plist`)
   - Add capability: **Keychain Sharing** with access group `com.app.eusotrip.shared` so it reads the same auth token the iPhone target uses.
9. **EusoTripAPI binding** — the placeholder networking in `VisionXRPreHaulView.swift` resolves once a shared "Sources" folder is added. Two paths:
   - **Frameworks path** (preferred): Promote `EusoTripAPI.swift` + `ESangTTSPlayer.swift` + `XRSessionBridge.swift` to a Swift Package, depend on it from both iPhone + visionOS targets.
   - **File-membership path** (faster): Add `EusoTrip/Services/EusoTripAPI.swift` + `EusoTrip/Services/EusoTripConfig.swift` to the visionOS target's compile sources via the File Inspector.
10. Build the scheme. First build pulls the new target's package deps and compiles in ~1 min.

After activation, every `xrChecklist.*` mutation works on visionOS identically to the iPhone — same Ed25519 signature verification, same audit chain entries, same `HazmatOverlay.placardsAffixed` overlay row writes.

## What's intentionally not in scope (yet)

- Volumetric scene polish — the current `xr-prehaul` window is a flat card. Future P1 work could render the checklist items as floating 3D cards in a 360° arc around the driver.
- Spatial audio routing — visionOS routes through head-fixed audio by default; tuning the audio to feel "from the trailer side" is a P1 polish item.
- Hand-tracking confirmation — pinch gesture to confirm an item without voice. P1.
