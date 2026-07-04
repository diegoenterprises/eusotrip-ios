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

    private let minimumDisplayDuration: Double = 1.5
    private let maximumDisplayDuration: Double = 3.0

    @State private var didFinish = false
    @State private var canSkip = false

    var body: some View {
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
        .contentShape(Rectangle())
        .onTapGesture {
            if canSkip { finishOnce() }
        }
        .task {
            async let skipGate: Void = {
                try? await Task.sleep(nanoseconds: UInt64(minimumDisplayDuration * 1_000_000_000))
                await MainActor.run { canSkip = true }
            }()

            async let ceiling: Void = {
                try? await Task.sleep(nanoseconds: UInt64(maximumDisplayDuration * 1_000_000_000))
                await MainActor.run { finishOnce() }
            }()

            _ = await (skipGate, ceiling)
        }
        .transition(.opacity)
        .screenTileRoot()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("EusoTrip")
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

#Preview("Intro Splash") {
    IntroSplash(onFinish: {})
        .preferredColorScheme(.dark)
}
