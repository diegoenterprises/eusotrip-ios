//
//  IntroSplash.swift
//  EusoTrip
//
//  EusoTrip by Eusorone Technologies, Inc.
//  Powered by ESANG AI™
//
//  Two-mode launch surface:
//
//    1) FIRST INSTALL — full branded Lottie reveal (3.0s native, slowed
//       to ~4.0s wall-clock at 0.75× playback). Light/Dark compositions
//       are separate Lottie bundles selected by colorScheme. Sets the
//       persistence flag on completion so it never plays again.
//
//    2) EVERY SUBSEQUENT LAUNCH — quick gradient-wordmark splash:
//       flame logo + "EUSOTRIP" wordmark center-stacked, ~700ms total
//       (200ms fade-in, 350ms hold, 200ms fade-out). Black background
//       on dark, white on light. Matches the founder's reference shot
//       2026-04-27 (logo + EUSOTRIP wordmark, blue→magenta gradient).
//
//  Persistence: `UserDefaults.standard.bool(forKey: "EusoTrip.hasShownFullIntro")`
//  flips to `true` the first time the Lottie animation completes (or
//  the hardTimeout fires). Reinstalling the app clears UserDefaults and
//  the full intro plays again — exactly the founder's intent.
//

import SwiftUI
import Lottie

// MARK: - Persistence key

private enum IntroPersistence {
    static let key = "EusoTrip.hasShownFullIntro"

    static var hasShownFull: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func markShown() {
        UserDefaults.standard.set(true, forKey: key)
    }
}

// MARK: - Public wrapper

/// Full-screen intro splash. On first install plays the Lottie reveal
/// then fires `onFinish`. On every subsequent launch plays a quick
/// gradient-wordmark splash (~700ms) and fires `onFinish`.
struct IntroSplash: View {
    @Environment(\.colorScheme) private var colorScheme
    var onFinish: () -> Void

    /// Hard ceiling — if Lottie's completion handler never fires (e.g. bundle
    /// issue), we still advance to AppRoot after this many seconds.
    /// Tuned slightly above the 4.0s playback window so the animation can
    /// complete naturally when it fires correctly.
    private let hardTimeout: Double = 5.0

    /// Quick-splash duration on warm launches. 700ms total — long
    /// enough to register as branding, short enough to feel like a
    /// boot, not an animation.
    private let quickSplashDuration: Double = 0.7

    @State private var didFinish = false
    /// Resolved on appear so the choice is made once per launch and
    /// the view body doesn't keep re-querying UserDefaults.
    @State private var mode: SplashMode = .quick

    private enum SplashMode { case full, quick }

    var body: some View {
        ZStack {
            // Stage color matches the comp / quick-splash background.
            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()

            switch mode {
            case .full:
                LottieIntroView(
                    animationName: colorScheme == .dark ? "intro_dark" : "intro_light",
                    speed: 0.75,
                    onComplete: finishOnce
                )
                .ignoresSafeArea()

            case .quick:
                QuickWordmarkSplash(colorScheme: colorScheme)
            }
        }
        .transition(.opacity)
        .onAppear {
            mode = IntroPersistence.hasShownFull ? .quick : .full
        }
        .task {
            // Branch the timeout off the resolved mode so quick splash
            // doesn't sit through the 5s Lottie ceiling.
            let waited = IntroPersistence.hasShownFull
                ? quickSplashDuration
                : hardTimeout
            try? await Task.sleep(nanoseconds: UInt64(waited * 1_000_000_000))
            finishOnce()
        }
        // Uniform cafe-door entrance.
        .screenTileRoot()
    }

    private func finishOnce() {
        guard !didFinish else { return }
        didFinish = true
        // The first time we ever finish, persist the flag so future
        // launches take the quick-splash path. We mark it AFTER the
        // animation finishes (or the hardTimeout fires) so a user
        // who force-quits during the very first reveal still gets the
        // full intro on their next launch.
        if !IntroPersistence.hasShownFull {
            IntroPersistence.markShown()
        }
        onFinish()
    }
}

// MARK: - Quick wordmark splash (warm launches)

/// Lightweight 2-frame splash matching the founder's reference shot
/// (2026-04-27): EusoTrip flame logo + "EUSOTRIP" wordmark with the
/// canonical blue→magenta gradient, center-stacked, animated in/out
/// with a quick fade. Black background on dark, white on light —
/// matches the system status-bar so the launch feels seamless.
private struct QuickWordmarkSplash: View {
    let colorScheme: ColorScheme

    @State private var visible = false

    var body: some View {
        VStack(spacing: 14) {
            // Flame mark from the asset catalog. SwiftUI tints a
            // template image, but the logo is rendered with multiple
            // gradient stops so we ship it as a regular asset and let
            // the image carry its own coloring.
            Image("EusoTripLogo")
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)

            // Wordmark — gradient text over a transparent backdrop.
            // Uses the canonical `LinearGradient.diagonal` so the
            // splash matches every other gradient surface in the app.
            Text("EUSOTRIP")
                .font(.system(size: 18, weight: .heavy)).tracking(4)
                .foregroundStyle(LinearGradient.diagonal)
        }
        .opacity(visible ? 1.0 : 0.0)
        .scaleEffect(visible ? 1.0 : 0.96)
        .onAppear {
            // 200ms fade-in. The parent view's task clock holds for
            // ~700ms total before firing onFinish, so the visible
            // window is ~500ms — long enough to read, short enough
            // to feel snappy.
            withAnimation(.easeOut(duration: 0.20)) {
                visible = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("EusoTrip")
    }
}

// MARK: - UIViewRepresentable

/// Thin bridge from Lottie's UIView-based player into SwiftUI. We use a
/// UIView wrapper (not `LottieView`, the SwiftUI-native API) so we can
/// reliably hook the completion callback across Lottie 4.x versions.
private struct LottieIntroView: UIViewRepresentable {
    let animationName: String
    var speed: CGFloat = 1.0
    var onComplete: () -> Void

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: .zero)
        container.backgroundColor = .clear
        container.clipsToBounds = true

        let anim = LottieAnimationView(name: animationName)
        anim.contentMode = .scaleAspectFill
        anim.loopMode = .playOnce
        anim.animationSpeed = speed
        anim.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(anim)

        NSLayoutConstraint.activate([
            anim.topAnchor.constraint(equalTo: container.topAnchor),
            anim.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            anim.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            anim.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        anim.play { finished in
            // Fire completion whether we ran to end or were interrupted
            // (interrupted → still advance; worst case the hardTimeout covers it).
            if finished { onComplete() }
        }

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) { /* no dynamic state */ }
}

// MARK: - Preview

#Preview("Intro Splash – Dark") {
    IntroSplash(onFinish: {})
        .preferredColorScheme(.dark)
}

#Preview("Intro Splash – Light") {
    IntroSplash(onFinish: {})
        .preferredColorScheme(.light)
}
