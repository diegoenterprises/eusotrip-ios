//
//  IntroSplash.swift
//  EusoTrip
//
//  EusoTrip by Eusorone Technologies, Inc.
//  Powered by ESANG AI
//
//  Full-screen launch splash driven by
//  EusoTrip_Splash_iOS_3s_1080x1920.mp4.
//

import AVFoundation
import SwiftUI
import UIKit

// MARK: - Public wrapper

/// Full-screen intro splash. Plays the bundled 3-second EusoTrip launch
/// film once per app process, aspect-filled edge to edge, then hands off
/// to AppRoot.
struct IntroSplash: View {
    var onFinish: () -> Void

    /// Set the first time the splash is ever shown, and never cleared. The
    /// launch film is the app's introduction: on the very first open it plays
    /// through with nothing offering to cut it short. Every open after that,
    /// the user has already seen it and is entitled to leave.
    private static let hasOpenedBeforeKey = "com.eusorone.EusoTrip.intro.hasOpenedBefore"

    private let minimumDisplayDuration: Double = 1.5
    private let maximumDisplayDuration: Double = 3.0
    /// Long enough that Skip fades in rather than appearing bolted to frame
    /// one, short enough that a returning user is never left waiting for it.
    private let skipRevealDelay: Double = 0.4

    @AppStorage(IntroSplash.hasOpenedBeforeKey) private var hasOpenedBefore = false

    @State private var didFinish = false
    @State private var canSkip = false
    @State private var showsSkip = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Color(red: 0.039, green: 0.039, blue: 0.078)
                    .ignoresSafeArea()

                SplashVideoView(
                    resourceName: "EusoTrip_Splash_iOS_3s_1080x1920",
                    resourceExtension: "mp4",
                    onComplete: finishOnce
                )
                .ignoresSafeArea()
            }
            // Grouped HERE rather than on the outer stack. Collapsing the whole
            // screen into one "EusoTrip" element would swallow the Skip control
            // below it and leave VoiceOver users with no way to reach it.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("EusoTrip")

            if showsSkip {
                skipButton
                    .padding(.trailing, Space.s6)
                    .padding(.bottom, Space.s7)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if canSkip { finishOnce() }
        }
        .task {
            // Read the flag as it stood at launch, then immediately record this
            // open. Deciding off `hasOpenedBefore` later would race that write
            // and pop the button into the one run it exists to stay out of.
            let isReturning = hasOpenedBefore
            hasOpenedBefore = true

            async let skipGate: Void = {
                try? await Task.sleep(nanoseconds: UInt64(minimumDisplayDuration * 1_000_000_000))
                await MainActor.run { canSkip = true }
            }()

            async let skipReveal: Void = {
                guard isReturning else { return }
                try? await Task.sleep(nanoseconds: UInt64(skipRevealDelay * 1_000_000_000))
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.28)) { showsSkip = true }
                }
            }()

            async let ceiling: Void = {
                try? await Task.sleep(nanoseconds: UInt64(maximumDisplayDuration * 1_000_000_000))
                await MainActor.run { finishOnce() }
            }()

            _ = await (skipGate, skipReveal, ceiling)
        }
        .transition(.opacity)
        .screenTileRoot()
    }

    /// Deliberately NOT gated on `canSkip`. That gate exists to stop a stray
    /// tap on the video from cutting the film short; pressing a button labelled
    /// Skip is unambiguous, and making it inert for its first 1.5s on screen
    /// would read as a broken control.
    private var skipButton: some View {
        Button(action: finishOnce) {
            HStack(spacing: Space.s1 + 2) {
                Text("Skip")
                    .font(EType.bodyStrong)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Space.s5)
            // The house minimum touch target. The label alone lands near 40pt.
            .frame(minWidth: 88, minHeight: 44)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(LinearGradient.iridescentHairlineDark, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Skip intro")
        .accessibilityHint("Goes straight to EusoTrip")
    }

    private func finishOnce() {
        guard !didFinish else { return }
        didFinish = true
        onFinish()
    }
}

// MARK: - Video bridge

private struct SplashVideoView: UIViewRepresentable {
    let resourceName: String
    let resourceExtension: String
    var onComplete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIView(context: Context) -> SplashVideoContainerView {
        let view = SplashVideoContainerView()
        view.backgroundColor = UIColor(red: 0.039, green: 0.039, blue: 0.078, alpha: 1.0)

        guard let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension) else {
            DispatchQueue.main.async { onComplete() }
            return view
        }

        context.coordinator.play(url: url, in: view)
        return view
    }

    func updateUIView(_ uiView: SplashVideoContainerView, context: Context) {}

    static func dismantleUIView(_ uiView: SplashVideoContainerView, coordinator: Coordinator) {
        coordinator.stop()
        uiView.detachPlayer()
    }

    final class Coordinator {
        private var player: AVPlayer?
        private var playbackObserver: NSObjectProtocol?
        private let onComplete: () -> Void

        init(onComplete: @escaping () -> Void) {
            self.onComplete = onComplete
        }

        func play(url: URL, in view: SplashVideoContainerView) {
            let item = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: item)
            player.isMuted = true
            player.actionAtItemEnd = .pause
            self.player = player

            playbackObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                self?.onComplete()
            }

            view.attach(player: player)
            player.play()
        }

        func stop() {
            player?.pause()
            player = nil

            if let playbackObserver {
                NotificationCenter.default.removeObserver(playbackObserver)
                self.playbackObserver = nil
            }
        }

        deinit {
            stop()
        }
    }
}

private final class SplashVideoContainerView: UIView {
    private let playerLayer = AVPlayerLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }

    func attach(player: AVPlayer) {
        playerLayer.player = player
        setNeedsLayout()
    }

    func detachPlayer() {
        playerLayer.player = nil
    }
}

// MARK: - Preview

// Both states are worth seeing, and only one of them is reachable on a device
// without deleting the app. The key is repeated as a literal because the macro
// expands into its own type, outside the private member's reach.
#Preview("Intro Splash — first ever open, no Skip") {
    UserDefaults.standard.removeObject(forKey: "com.eusorone.EusoTrip.intro.hasOpenedBefore")
    return IntroSplash(onFinish: {})
        .preferredColorScheme(.dark)
}

#Preview("Intro Splash — returning, Skip") {
    UserDefaults.standard.set(true, forKey: "com.eusorone.EusoTrip.intro.hasOpenedBefore")
    return IntroSplash(onFinish: {})
        .preferredColorScheme(.dark)
}
