//
//  EusoTripWatchApp.swift
//  EusoTrip Watch App
//
//  watchOS 10+ app entry point. Boots WatchConnectivity so the phone side
//  can observe Esang sessions started from the wrist. Registers the
//  HOS / active-load complications and the background workout session
//  that keeps us alive for long-haul HOS monitoring.
//
//  Powered by ESANG AI™ — part of EusoTrip by Eusorone Technologies, Inc.
//

import SwiftUI
import WatchKit

@main
struct EusoTripWatchApp: App {
    @StateObject private var auth = AuthStore()
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @StateObject private var esang = EsangSession()
    @StateObject private var driving = DrivingSessionManager.shared
    @StateObject private var hos = HOSStore.shared
    @StateObject private var loads = LoadStore.shared
    @StateObject private var ergo = ErgoMonitor.shared
    @StateObject private var offline = OfflineQueue.shared

    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Expose the live AuthStore to WCSession delegate callbacks
        // (which can't cross the main actor).
        AuthStore.shared = nil
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(connectivity)
                .environmentObject(esang)
                .environmentObject(driving)
                .environmentObject(hos)
                .environmentObject(loads)
                .environmentObject(ergo)
                .environmentObject(offline)
                .onAppear {
                    AuthStore.shared = auth
                    connectivity.activate()
                    auth.restore()
                    hos.restore()
                    loads.restore()
                    offline.restore()
                    // Register App Intents so Siri can say "Ask Esang".
                    AskEsangIntentRegistrar.register()
                    // Kick off a lightweight background workout session so
                    // we stay alive for long-haul HOS + voice sessions.
                    driving.begin()
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        Task { await loads.refresh(auth: auth) }
                        Task { await hos.refresh(auth: auth) }
                        Task { await offline.flush(auth: auth) }
                    case .background:
                        // Don't tear down the workout session — we want to
                        // stay alive until the driver explicitly ends it.
                        break
                    default:
                        break
                    }
                }
        }
    }
}
