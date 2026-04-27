//
//  BootGate.swift
//  EusoTrip Pulse Watch App
//
//  A one-runloop placeholder that guarantees SwiftUI commits a first
//  frame before the real RootView body evaluates. Under watchOS 26.4
//  with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, we were seeing the
//  main thread wedged deep in the allocator during launch — symptom was
//  the EusoTrip splash logo showing indefinitely while the debugger
//  reported Thread 1 parked inside `_xzm_free` at 41+ frames from
//  `start`. Root cause: every @StateObject-bound `.shared` singleton in
//  the App struct was initialised synchronously on the main thread
//  BEFORE SwiftUI got a chance to render anything. On device the
//  watchdog then killed the app at the ~20s launch timeout — "loads the
//  logo then boots out".
//
//  BootGate fixes that by rendering a trivial placeholder synchronously
//  on the first pass, then flipping to `content()` after a short .task
//  sleep. .task fires only AFTER the first frame has been committed, so
//  no matter how heavy RootView's body is, the launch screen transition
//  is already complete by the time we evaluate it.
//

import SwiftUI

struct BootGate<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @State private var ready = false

    var body: some View {
        Group {
            if ready {
                content()
                    .transition(.opacity)
            } else {
                // Match the asset launch-image background so the swap is
                // imperceptible. Black works for both the watch face
                // launch image and the EusoTrip logo backdrop.
                Color.black
                    .ignoresSafeArea()
                    .task {
                        // A single runloop tick is enough for SwiftUI to
                        // commit the first frame. 50ms gives HealthKit,
                        // WCSession + CoreMotion permission prompts a
                        // window to settle on cold start without
                        // blocking the main actor.
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        ready = true
                    }
            }
        }
        .animation(.easeOut(duration: 0.15), value: ready)
    }
}
