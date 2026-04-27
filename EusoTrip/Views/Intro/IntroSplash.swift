//
//  IntroSplash.swift
//  EusoTrip
//
//  EusoTrip by Eusorone Technologies, Inc.
//  Powered by ESANG AI™
//
//  First-launch intro. Plays the branded Lottie reveal (3.0s native
//  composition, slowed to 4.0s by a 0.75× playback speed) and then fades
//  into AppRoot.
//
//  Light/Dark animations are separate compositions chosen by colorScheme.
//

import SwiftUI
import Lottie

// MARK: - Public wrapper

/// Full-screen intro splash. Calls `onFinish` once the Lottie animation
/// reports complete, or falls back to a hard timeout so the app can never
/// get stuck on the intro.
struct IntroSplash: View {
    @Environment(\.colorScheme) private var colorScheme
    var onFinish: () -> Void

    /// Hard ceiling — if Lottie's completion handler never fires (e.g. bundle
    /// issue), we still advance to AppRoot after this many seconds.
    /// Tuned slightly above the 4.0s playback window so the animation can
    /// complete naturally when it fires correctly.
    private let hardTimeout: Double = 5.0

    @State private var didFinish = false

    var body: some View {
        ZStack {
            // Match the composition's outer stage — black on dark, white on light.
            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()

            LottieIntroView(
                animationName: colorScheme == .dark ? "intro_dark" : "intro_light",
                // 0.75× → stretches the 3.0s comp to ~4.0s wall-clock.
                speed: 0.75,
                onComplete: finishOnce
            )
            .ignoresSafeArea()
        }
        .transition(.opacity)
        .task {
            try? await Task.sleep(nanoseconds: UInt64(hardTimeout * 1_000_000_000))
            finishOnce()
        }
        // Uniform cafe-door entrance.
        .screenTileRoot()
    }

    private func finishOnce() {
        guard !didFinish else { return }
        didFinish = true
        onFinish()
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
