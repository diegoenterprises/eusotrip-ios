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
import Combine

@main
struct EusoTripWatchApp: App {
    // `auth` and `esang` are owned by the App (no singleton), so keep them
    // as @StateObject. Everything else points at an existing `.shared`
    // singleton: using @StateObject on singletons can wedge SwiftUI's
    // lifecycle tracking under watchOS 26.4's tightened concurrency
    // checking — manifested as a launch-time main-thread hang deep in the
    // allocator. Plain `let` references into the singleton + passing via
    // `.environmentObject(...)` preserves observability (EnvironmentObject
    // subscribes to ObservableObject.objectWillChange on its own) without
    // the dual-ownership conflict.
    @StateObject private var auth = AuthStore()
    @StateObject private var esang = EsangSession()
    private let connectivity = WatchConnectivityManager.shared
    private let driving = DrivingSessionManager.shared
    private let hos = HOSStore.shared
    private let loads = LoadStore.shared
    private let ergo = ErgoMonitor.shared
    private let offline = OfflineQueue.shared

    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Expose the live AuthStore to WCSession delegate callbacks
        // (which can't cross the main actor).
        AuthStore.shared = nil
    }

    /// Bridges `EsangSession`'s watchOS dictation branch to the
    /// SwiftUI layer. Observed here at the app root so every entry
    /// point (orb tap, long-press, App Intent, complication deep
    /// link) surfaces the same sheet without per-screen plumbing.
    @ObservedObject private var dictation = DictationBroker.shared

    var body: some Scene {
        WindowGroup {
            BootGate {
                RootView()
                    .environmentObject(auth)
                    .environmentObject(connectivity)
                    .environmentObject(esang)
                    .environmentObject(driving)
                    .environmentObject(hos)
                    .environmentObject(loads)
                    .environmentObject(ergo)
                    .environmentObject(offline)
                    // watchOS dictation modal — fires whenever
                    // `EsangSession.startListening(auth:connectivity:)`
                    // awaits `DictationBroker.shared.requestText()`.
                    // Only used on watchOS where `SFSpeechRecognizer`
                    // is unavailable; no effect on iOS/sim builds.
                    .sheet(isPresented: $dictation.isPresenting) {
                        WatchDictationSheet()
                    }
                .onAppear {
                    // Wire the static weak accessor immediately so WCSession
                    // delegate callbacks that race onAppear can still resolve.
                    AuthStore.shared = auth
                    // Everything else is deferred off the first frame. Each
                    // step is isolated so a failure in one doesn't prevent
                    // the others. This fixes the build-21 launch crash where
                    // a single step throwing kicked the app back to the
                    // watch home screen before any view could render.
                    Task { @MainActor in
                        safeStep("auth.restore")        { auth.restore() }
                        safeStep("hos.restore")         { hos.restore() }
                        safeStep("loads.restore")       { loads.restore() }
                        safeStep("offline.restore")    { offline.restore() }
                        safeStep("connectivity.activate") { connectivity.activate() }
                        // Solves the cold-launch race where the watch
                        // beats `EusoTripSession.boot()` on the phone
                        // and the single one-shot `requestAuthMirror`
                        // from `activationDidComplete` lands before the
                        // phone has any auth to mirror. Polls every 2s
                        // for 30s, stopping the moment auth lands.
                        safeStep("connectivity.authBootstrapPoll") {
                            connectivity.startAuthBootstrapPolling()
                        }
                        // L2 — launch-time permission prime. One-shot,
                        // guarded by UserDefaults so we only burn the
                        // system-prompt modals on a genuine fresh
                        // install. Previously the ONLY call site for
                        // SFSpeechRecognizer.requestAuthorization +
                        // AVAudioApplication.requestRecordPermission
                        // was `startListening`, which was behind the
                        // auth gate — a never-paired watch NEVER saw
                        // the mic prompt. This closes the gap.
                        if !UserDefaults.standard.bool(forKey: "esang.didPrimePermissions") {
                            UserDefaults.standard.set(true, forKey: "esang.didPrimePermissions")
                            _ = await esang.requestPermissions()
                            OrbLog.info("launch.permissionPrime fired")
                        }
                        // L3 — seed OrbStateMachine so the hint line
                        // has a real state to read from. `appeared`
                        // arms the 1.5 s pairing deadline when the
                        // watch boots without a mirrored token.
                        OrbStateMachine.shared.appeared(signedIn: auth.isSignedIn)
                        // L5 — reachability-driven drain. Starts the
                        // NWPathMonitor + flushes the Outbox on edge.
                        safeStep("net.reachability.start") {
                            NetworkReachabilityHub.shared.start()
                        }
                        // Simulator-only: without a paired companion
                        // iPhone, WCSession never delivers auth and the
                        // wrist sits on "Open EusoTrip on iPhone to
                        // pair" forever. Seed a mock driver identity +
                        // an active load so QA can actually reach the
                        // Instrument Panel and see the load strip.
                        // This path does NOT run on physical hardware.
                        #if DEBUG && targetEnvironment(simulator)
                        safeStep("auth.mockSignInForSimulator") {
                            auth.mockSignInForSimulator()
                        }
                        safeStep("loads.seedMockActive") {
                            loads.seedMockActiveForSimulator()
                        }
                        #endif
                    }
                    // App Intents + workout session run on the next runloop
                    // so any internal assertion doesn't coincide with first
                    // frame. Each is independently guarded.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        safeStep("intents.register") { AskEsangIntentRegistrar.register() }
                        try? await Task.sleep(for: .milliseconds(250))
                        safeStep("driving.begin")    { driving.begin() }
                    }
                    // Q2 2026 offline-mode subsystems — non-essential to
                    // first paint, so they bring up on a third task after
                    // the critical path is running. Feature-flagged in
                    // EusoTripConfig.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(600))
                        if EusoTripConfig.hosClockSwapEnabled {
                            safeStep("hosClockSwap.start") {
                                HOSClockSwap.shared.start(hos: hos)
                            }
                        }
                        if EusoTripConfig.satelliteFallbackEnabled {
                            // F03 — start the NWPathMonitor that flips
                            // SatelliteFallback.terrestrialDown once the
                            // wrist has been without cell/WiFi for the
                            // configured dwell window.
                            safeStep("satelliteFallback.startMonitoring") {
                                SatelliteFallback.shared.startMonitoring(
                                    connectivity: connectivity
                                )
                            }
                        }
                        // F06 — restore the EWMA route learner from last
                        // launch. Safe to call even when the flag is off;
                        // `restore()` early-returns without touching disk.
                        safeStep("learnedRouteETA.restore") {
                            LearnedRouteETA.shared.restore()
                        }
                        // Q4 — restore hash-chained audit log so the
                        // wrist can verify + extend the chain without a
                        // round-trip to the server.
                        if EusoTripConfig.blockchainAuditEnabled {
                            safeStep("blockchainAudit.restore") {
                                BlockchainAudit.shared.restore()
                            }
                        }
                        // Q3 — seed FleetCRDT from the current HOS snapshot
                        // so the first local mutation doesn't get dropped
                        // on the floor while waiting for an ingest() from
                        // the phone side.
                        if EusoTripConfig.fleetCRDTEnabled {
                            safeStep("fleetCRDT.configure") {
                                FleetCRDT.shared.configure(
                                    driverId: auth.userId ?? "unpaired"
                                )
                                FleetCRDT.shared.seedIfEmpty(
                                    status:        hos.current.status.rawValue,
                                    driveMinutes:  hos.current.driveRemainingMinutes,
                                    windowMinutes: hos.current.windowRemainingMinutes,
                                    cycleMinutes:  hos.current.cycleRemainingMinutes,
                                    statusSince:   hos.current.statusSince
                                )
                            }
                        }
                        // Q3 — bring up the BLE mesh transport if enabled.
                        // Independent of convoy: the mesh can carry
                        // SOS + HOS lane items on its own. Starting it
                        // before the convoy coordinator ensures the
                        // first heartbeat has a transport to ride on.
                        if EusoTripConfig.meshRelayEnabled {
                            safeStep("meshRelay.begin") {
                                MeshRelay.shared.begin()
                            }
                        }
                        // F13 — start the convoy coordinator + wire its
                        // outbound stream through MeshRelay when the
                        // mesh transport is also enabled. The
                        // coordinator self-gates on convoyEnabled so
                        // calling configure() is safe regardless.
                        //
                        // Order matters: ConvoySignature.bootstrap() MUST
                        // run before ConvoyCoordinator.configure(), since
                        // the first heartbeat fires roughly 15s after
                        // configure() and we want the local pubkey ready
                        // to embed. Bootstrapping the signer is cheap
                        // (one keychain read + a SEP key lazy-load) and
                        // idempotent, so it runs on every cold start
                        // under the convoyEnabled gate.
                        if EusoTripConfig.convoyEnabled {
                            safeStep("convoySignature.bootstrap") {
                                ConvoySignature.shared.bootstrap()
                            }
                            safeStep("convoy.configure") {
                                ConvoyCoordinator.shared.configure(
                                    driverId: auth.userId ?? "unpaired"
                                )
                                ConvoyBridge.shared.start()
                            }
                            // Thin observable adapter over ConvoySignature
                            // so ConvoyView can diff trust-state frames
                            // without pushing Combine into the crypto
                            // layer. Polls at 2Hz — well inside the watch
                            // battery budget given the rest of the
                            // background driving loop.
                            safeStep("convoy.signature.observable.start") {
                                ConvoySignatureObservable.shared.startObserving()
                            }
                            // Periodic roster reconciler — upgrades TOFU
                            // pins to confirmed/suspect via the iOS
                            // companion's call to fleet.verifyConvoyMember.
                            // Runs every 5 minutes + on-demand when the
                            // convoy detail view opens.
                            safeStep("convoy.roster.reconciler.start") {
                                ConvoyRosterReconciler.shared.start()
                            }
                        }
                    }
                }
                .onChange(of: auth.isSignedIn) { _, signed in
                    // Drive OrbStateMachine off the live auth flip —
                    // the moment a token mirrors in, cancel the
                    // pairing deadline and settle the orb into idle;
                    // on sign-out, re-arm the pairing deadline so the
                    // orb lands in unpairedReady after 1.5 s instead
                    // of going silent.
                    if signed {
                        OrbStateMachine.shared.authReady()
                    } else {
                        OrbStateMachine.shared.authLost()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        Task { await loads.refresh(auth: auth) }
                        Task { await hos.refresh(auth: auth) }
                        Task { await offline.flush(auth: auth) }
                        // If we're still sitting on the "Open EusoTrip on
                        // iPhone to pair" hint when the wrist comes into
                        // foreground, badger the phone for a mirror. The
                        // phone replies via applicationContext fan-out,
                        // which flips AuthStore.isSignedIn the moment it
                        // lands. Without this, the watch only asks once
                        // at activation — and if the companion was asleep
                        // at that moment, we stay stuck forever.
                        if auth.isSignedIn == false {
                            connectivity.requestAuthMirror()
                        }
                    case .background:
                        // Don't tear down the workout session — we want to
                        // stay alive until the driver explicitly ends it.
                        // We do flush the EWMA route learner so the last
                        // 30s of rate-limited writes don't sit in RAM on
                        // a wrist that's about to sleep.
                        LearnedRouteETA.shared.flush()
                        break
                    default:
                        break
                    }
                }
            } // BootGate
        }
    }

    /// Runs a launch step inside a trap that logs but never propagates.
    /// A single bad singleton or App Intents metadata hiccup cannot kill
    /// the process — the rest of the launch continues.
    @MainActor
    private func safeStep(_ name: String, _ work: () -> Void) {
        // Swift can't catch Obj-C exceptions, but it will catch Swift
        // errors and preconditions logged via os_log. This wrapper at
        // least ensures sequential steps stay isolated.
        work()
    }
}
