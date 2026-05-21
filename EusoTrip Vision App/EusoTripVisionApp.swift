//
//  EusoTripVisionApp.swift
//  EusoTrip — visionOS app entry point.
//
//  visionOS lockstep with the iPhone P0-16 audio-only XR pre-haul
//  surface. Per the founder's 2026-05-20 directive: "whatever XR
//  you build for android type code you do also for vision os."
//
//  Architecture:
//    - Same server endpoints (`xrChecklist.getChecklist`,
//      `confirmItem`, `getSessionState`) the iPhone bridge uses.
//    - visionOS-native immersive presentation: a Volume scene
//      pins the current checklist item card in the driver's
//      field of view while the audio plays through visionOS's
//      spatial audio engine.
//    - Wire types + Ed25519 signature verification are
//      copy-imports from the iPhone target so the visionOS
//      bundle has no dependency on the iPhone framework — the
//      RawValue strings are identical (server validates).
//
//  Activation status: this folder ships AS scaffolding. The
//  visionOS Xcode target itself is not yet added to
//  EusoTrip.xcodeproj — adding it via pbxproj surgery is fragile.
//  See `EusoTrip Vision App/README.md` for the activation
//  checklist when the founder is ready to flip this on.
//

import SwiftUI

@main
struct EusoTripVisionApp: App {
    var body: some Scene {
        WindowGroup {
            VisionRootView()
        }
        .windowStyle(.plain)

        // Immersive volumetric scene for the XR pre-haul checklist —
        // shipping crate-sized cards that orbit the driver while
        // audio plays. Falls back gracefully to a flat Window on
        // devices that don't support volumetric layouts.
        WindowGroup(id: "xr-prehaul") {
            VisionXRPreHaulView()
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 0.8, height: 0.5, depth: 0.3, in: .meters)
    }
}

/// Cold-launch root. Pairs to the user's account (token already
/// stored on the phone via Continuity / iCloud Keychain), then
/// surfaces the XR pre-haul launcher.
private struct VisionRootView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var loadIdInput: String = ""

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 56, weight: .heavy))
                .foregroundStyle(LinearGradient(
                    colors: [.cyan, .green],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            Text("EusoTrip · visionOS")
                .font(.largeTitle.bold())
            Text("Hands-free pre-haul checklist for hazmat / reefer / tanker / livestock pickups.")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 480)

            TextField("Active load ID (e.g. load_1077)", text: $loadIdInput)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)
                .autocorrectionDisabled()

            Button {
                openWindow(id: "xr-prehaul", value: loadIdInput.trimmingCharacters(in: .whitespaces))
            } label: {
                Label("Start pre-haul checklist", systemImage: "headphones")
                    .font(.title3.bold())
                    .padding(.horizontal, 24).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(loadIdInput.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
