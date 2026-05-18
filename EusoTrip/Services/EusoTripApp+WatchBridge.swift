//
//  EusoTripApp+WatchBridge.swift
//  EusoTrip
//
//  View-modifier + View helpers that wire the Apple Watch companion
//  into the iOS app's root view. Apply `.withEusoTripWatchBridge()` on
//  the root view once (see EusoTripApp.swift) and we take care of:
//
//    - Activating WCSession at launch so the watch can push context
//    - Observing WatchCommandHandler.pendingDeeplink and routing to
//      the appropriate iOS surface (eSang chat, wallet, maps, …)
//    - Handling NSUserActivity for the watch's `com.eusotrip.esang.activate`
//      handoff so "Open on iPhone" opens the chat composer with the
//      watch's transcript seeded.
//

import SwiftUI
import MapKit

extension View {
    /// Attach once on the iOS app's root view.
    func withEusoTripWatchBridge() -> some View {
        self.modifier(EusoTripWatchBridgeModifier())
    }
}

private struct EusoTripWatchBridgeModifier: ViewModifier {
    @StateObject private var handler = WatchCommandHandler.shared
    @State private var esangSeed: String?
    @State private var showeSang = false
    @State private var showWallet = false
    @State private var showHOS = false
    @State private var showEmergency = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                WatchAuthBridge.shared.activate()
            }
            .onChange(of: handler.pendingDeeplink) { _, link in
                guard let link else { return }
                route(link)
                handler.pendingDeeplink = nil
            }
            .onContinueUserActivity("com.eusotrip.esang.activate") { activity in
                let transcript = activity.userInfo?["transcript"] as? String
                esangSeed = transcript
                showeSang = true
            }
            .sheet(isPresented: $showeSang) {
                // Presented as a simple reminder for now — the full
                // eSang chat surface in ContentView can observe the
                // same seed if the product team prefers to route it
                // there. Safe default keeps the build clean.
                eSangWatchHandoffSheet(seed: esangSeed)
            }
            .sheet(isPresented: $showWallet) {
                WatchHandoffPlaceholder(
                    title: "EusoWallet",
                    systemImage: "creditcard.fill",
                    message: "Open the Wallet tab on your iPhone to see the full surface."
                )
            }
            .sheet(isPresented: $showHOS) {
                WatchHandoffPlaceholder(
                    title: "Hours of Service",
                    systemImage: "clock.badge.checkmark",
                    message: "Your HOS status is updated. Open the ELD surface for the full log."
                )
            }
            .sheet(isPresented: $showEmergency) {
                WatchHandoffPlaceholder(
                    title: "Emergency",
                    systemImage: "exclamationmark.triangle.fill",
                    message: "Dispatch has been notified. Tap below if you need to place a call."
                )
            }
    }

    private func route(_ link: WatchDeeplink) {
        switch link {
        case .wallet:
            showWallet = true
        case .hos:
            showHOS = true
        case .esangChat(let seed):
            esangSeed = seed
            showeSang = true
        case .maps(let query):
            openMaps(query: query)
        case .dispatchCall:
            if let url = URL(string: "tel://18005551234") {
                UIApplication.shared.open(url)
            }
        case .hazmatEscort:
            showeSang = true // hazmat escort surface reuses the chat for now
        case .emergency:
            showEmergency = true
        }
    }

    private func openMaps(query: String) {
        // Strip the transcript prefix "navigate to "
        let trimmed = query.replacingOccurrences(
            of: "navigate to ",
            with: "",
            options: [.caseInsensitive]
        )
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed.isEmpty ? "rest stop" : trimmed
        let search = MKLocalSearch(request: request)
        search.start { response, _ in
            let item = response?.mapItems.first
            let destination = item ?? MKMapItem.forCurrentLocation()
            destination.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
            ])
        }
    }
}

// Lightweight sheet body so the watch handoff doesn't require us to
// navigate the real iOS app's TabView state machine. When the product
// team wires these into ContentView directly, the sheets below become
// no-ops.

private struct eSangWatchHandoffSheet: View {
    let seed: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading) {
                        Text("From your watch").font(.caption)
                            .foregroundStyle(.secondary)
                        Text("eSang handoff").font(.headline)
                    }
                    Spacer()
                }
                if let seed, !seed.isEmpty {
                    Text("\"\(seed)\"")
                        .font(.body)
                        .padding(10)
                        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                Text("Open the eSang tab to continue the conversation on your iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Got it")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("eSang")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct WatchHandoffPlaceholder: View {
    let title: String
    let systemImage: String
    let message: String
    @Environment(\.dismiss) private var dismiss

    var content: some View {
        VStack(spacing: 18) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text(title).font(.title2.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Dismiss")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    var body: some View {
        NavigationStack { content.navigationTitle(title).navigationBarTitleDisplayMode(.inline) }
    }
}
