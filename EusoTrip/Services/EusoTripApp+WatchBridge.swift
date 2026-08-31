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
#if canImport(UIKit)
import UIKit
#endif

struct WatchESangHandoffRequest: Codable, Equatable, Identifiable {
    let id: UUID
    let prompt: String
    let autoSubmit: Bool
    let beginListening: Bool
    let receivedAt: Date
}

@MainActor
final class WatchESangHandoffCenter: ObservableObject {
    static let shared = WatchESangHandoffCenter()

    @Published private(set) var pending: WatchESangHandoffRequest?

    private let defaultsKey = "com.eusorone.EusoTrip.watch.esangHandoff"
    private let maximumAge: TimeInterval = 30 * 60

    private init() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let request = try? JSONDecoder().decode(WatchESangHandoffRequest.self, from: data),
              Date().timeIntervalSince(request.receivedAt) <= maximumAge else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            return
        }
        pending = request
    }

    var hasPendingRequest: Bool {
        guard let pending else { return false }
        return Date().timeIntervalSince(pending.receivedAt) <= maximumAge
    }

    func stage(prompt: String?, autoSubmit: Bool, beginListening: Bool) {
        let request = WatchESangHandoffRequest(
            id: UUID(),
            prompt: prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            autoSubmit: autoSubmit,
            beginListening: beginListening,
            receivedAt: Date()
        )
        pending = request
        if let data = try? JSONEncoder().encode(request) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        NotificationCenter.default.post(name: .eusoWatchESangRequested, object: request.id)
    }

    func consume() -> WatchESangHandoffRequest? {
        guard hasPendingRequest else {
            clear()
            return nil
        }
        let request = pending
        clear()
        return request
    }

    private func clear() {
        pending = nil
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

extension Notification.Name {
    static let eusoWatchESangRequested = Notification.Name("eusoWatchESangRequested")
    static let eusoWatchDestinationRequested = Notification.Name("eusoWatchDestinationRequested")
}

extension View {
    /// Attach once on the iOS app's root view.
    func withEusoTripWatchBridge() -> some View {
        self.modifier(EusoTripWatchBridgeModifier())
    }
}

private struct EusoTripWatchBridgeModifier: ViewModifier {
    @StateObject private var handler = WatchCommandHandler.shared

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
                let destination = activity.userInfo?["destination"] as? String
                let transcript = activity.userInfo?["transcript"] as? String ?? ""
                if destination == "esang" || !transcript.isEmpty {
                    WatchESangHandoffCenter.shared.stage(
                        prompt: transcript,
                        autoSubmit: activity.userInfo?["autoSubmit"] as? Bool ?? false,
                        beginListening: activity.userInfo?["beginListening"] as? Bool ?? transcript.isEmpty
                    )
                }
            }
    }

    private func route(_ link: WatchDeeplink) {
        switch link {
        case .wallet:
            postDestination("wallet")
        case .hos:
            postDestination("hos")
        case .esangChat(let seed, let autoSubmit, let beginListening):
            WatchESangHandoffCenter.shared.stage(
                prompt: seed,
                autoSubmit: autoSubmit,
                beginListening: beginListening
            )
        case .maps(let query):
            openMaps(query: query)
        case .dispatchCall:
            postDestination("dispatch")
        case .hazmatEscort:
            postDestination("hazmat")
        case .emergency(let relay):
            postDestination("emergency", object: relay)
        }
    }

    private func postDestination(
        _ destination: String,
        object: Any? = nil,
        userInfo: [AnyHashable: Any] = [:]
    ) {
        var payload = userInfo
        payload["destination"] = destination
        NotificationCenter.default.post(
            name: .eusoWatchDestinationRequested,
            object: object,
            userInfo: payload
        )
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

private struct WatchESangPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { presentIfPending() }
            .onReceive(NotificationCenter.default.publisher(for: .eusoWatchESangRequested)) { _ in
                presentIfPending()
            }
    }

    private func presentIfPending() {
        guard WatchESangHandoffCenter.shared.hasPendingRequest else { return }
        isPresented = true
    }
}

extension View {
    func watchESangHandoff(isPresented: Binding<Bool>) -> some View {
        modifier(WatchESangPresentationModifier(isPresented: isPresented))
    }
}

struct WatchEmergencyRelaySheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let relay: WatchEmergencyRelay

    @State private var retriedCallOpened: Bool?
    @State private var isOpeningCall = false

    private var callHandoffOpened: Bool? {
        retriedCallOpened ?? relay.callHandoffOpened
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(palette.borderFaint)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    relaySummary
                    evidenceRows

                    if !relay.silent, callHandoffOpened != true {
                        callEmergencyButton
                    }
                }
                .padding(20)
            }
        }
        .background(palette.bgPage.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: relay.silent ? "lock.shield.fill" : "sos.circle.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(relay.silent ? palette.tintWarning : Color.red)

            VStack(alignment: .leading, spacing: 2) {
                Text(relay.silent ? "Silent SOS relay" : "SOS relay")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text("EusoTrip Pulse evidence")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.textPrimary)
            .accessibilityLabel("Close SOS relay")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var relaySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(relay.serverAcknowledged ? palette.tintSuccess : Color.red)
                    .frame(width: 9, height: 9)
                Text(relay.serverAcknowledged ? "SERVER ACKNOWLEDGED" : "NO SERVER RECEIPT")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(relay.serverAcknowledged ? palette.tintSuccess : Color.red)
            }

            Text(relay.reason.isEmpty ? "Driver-initiated emergency" : relay.reason)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(palette.textPrimary)

            Text(relay.serverAcknowledged
                 ? "The emergency service returned a confirmation reference."
                 : "The phone did not receive a confirmation from the emergency service.")
                .font(.system(size: 14))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(relay.serverAcknowledged ? palette.tintSuccess : Color.red, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var evidenceRows: some View {
        VStack(spacing: 0) {
            evidenceRow(
                icon: "number",
                label: "Event reference",
                value: relay.emergencyId ?? relay.id
            )
            Divider().overlay(palette.borderFaint)
            evidenceRow(
                icon: "iphone.radiowaves.left.and.right",
                label: "Emergency Call",
                value: emergencyCallStatus
            )
            Divider().overlay(palette.borderFaint)
            evidenceRow(
                icon: "location.fill",
                label: "Location evidence",
                value: locationEvidence
            )
            Divider().overlay(palette.borderFaint)
            evidenceRow(
                icon: "clock.fill",
                label: "Received on iPhone",
                value: relay.receivedAt.formatted(date: .abbreviated, time: .standard)
            )
        }
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func evidenceRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.tintInfo)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                Text(value)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private var callEmergencyButton: some View {
        Button {
            guard let url = URL(string: "tel://911") else { return }
            isOpeningCall = true
            Task {
                retriedCallOpened = await UIApplication.shared.open(url)
                isOpeningCall = false
            }
        } label: {
            HStack(spacing: 10) {
                if isOpeningCall {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "phone.fill")
                }
                Text("Call 911")
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.red)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isOpeningCall)
    }

    private var emergencyCallStatus: String {
        if relay.silent { return "Not requested in silent mode" }
        switch callHandoffOpened {
        case true: return "Opened on iPhone"
        case false: return "Could not open"
        case nil: return "No outcome received"
        }
    }

    private var locationEvidence: String {
        guard let latitude = relay.latitude, let longitude = relay.longitude else {
            return "Unavailable"
        }
        return String(format: "%.5f, %.5f", latitude, longitude)
    }
}
