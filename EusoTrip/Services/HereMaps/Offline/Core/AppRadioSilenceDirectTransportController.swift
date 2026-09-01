//
//  AppRadioSilenceDirectTransportController.swift
//  EusoTrip
//
//  Owns app-initiated transports that are not visible to URLSession task
//  cancellation: WebKit subresources/WebRTC, AVPlayer HLS, Safari sheets,
//  MapKit searches, and similar provider objects with explicit stop hooks.
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif
#if canImport(WebKit)
import WebKit
#endif
#if canImport(SafariServices)
import SafariServices
#endif
#if canImport(AVKit)
import AVKit
#endif

@MainActor
final class AppRadioSilenceDirectTransportController {
    struct Registration: Hashable, Sendable {
        fileprivate let id = UUID()
    }

    static let shared = AppRadioSilenceDirectTransportController()

    private struct RegisteredTransport {
        let stop: @MainActor () -> Void
        let resume: (@MainActor () -> Void)?
    }

    #if canImport(SafariServices)
    private final class WeakSafariController {
        weak var value: SFSafariViewController?
        init(_ value: SFSafariViewController) { self.value = value }
    }
    #endif

    private var transports: [Registration: RegisteredTransport] = [:]
    private var isSuspended = false
    #if canImport(SafariServices)
    private var pendingSafariControllers: [ObjectIdentifier: WeakSafariController] = [:]
    #endif

    private init() {}

    var transportAllowed: Bool {
        !EusoTripAPI.shared.isAppRadioSilenceEnforced
    }

    /// Register before starting the provider. Registration and coordinator
    /// acquisition both run on the main actor, so no start can interleave
    /// between this preflight and insertion.
    func register(
        stop: @escaping @MainActor () -> Void,
        resume: (@MainActor () -> Void)? = nil
    ) -> Registration? {
        let registration = Registration()
        transports[registration] = RegisteredTransport(stop: stop, resume: resume)
        if isSuspended || EusoTripAPI.shared.isAppRadioSilenceEnforced {
            stop()
        }
        return registration
    }

    func unregister(_ registration: Registration?) {
        guard let registration else { return }
        transports[registration] = nil
    }

    #if canImport(WebKit)
    func register(
        webView: WKWebView,
        resume: (@MainActor () -> Void)? = nil
    ) -> Registration? {
        register(
            stop: { [weak webView] in
                guard let webView else { return }
                webView.stopLoading()
                // Navigating away tears down WebRTC, JavaScript fetches, and
                // subresource loaders. Keep installed message handlers: the
                // same mounted wrapper must be able to reload after release.
                webView.loadHTMLString("", baseURL: nil)
            },
            resume: resume
        )
    }

    @discardableResult
    func loadRemote(_ request: URLRequest, into webView: WKWebView) -> Bool {
        guard transportAllowed else {
            webView.stopLoading()
            webView.loadHTMLString("", baseURL: nil)
            return false
        }
        webView.load(request)
        return true
    }

    @discardableResult
    func loadRemoteHTML(
        _ html: String,
        baseURL: URL,
        into webView: WKWebView
    ) -> Bool {
        guard transportAllowed else {
            webView.stopLoading()
            webView.loadHTMLString("", baseURL: nil)
            return false
        }
        webView.loadHTMLString(html, baseURL: baseURL)
        return true
    }
    #endif

    #if canImport(SafariServices)
    func gatedRemoteURL(_ url: URL) -> URL {
        transportAllowed ? url : URL(string: "about:blank")!
    }

    /// Track from construction time, before SwiftUI presents the controller.
    /// This closes the make-to-present race that a mounted-tree sweep alone
    /// cannot see. Safari sheets are intentionally dismissed, not reopened,
    /// after release because their login/payment navigation is not replayable.
    func track(safariController: SFSafariViewController) {
        pendingSafariControllers = pendingSafariControllers.filter { $0.value.value != nil }
        guard transportAllowed, !isSuspended else {
            safariController.dismiss(animated: false)
            return
        }
        pendingSafariControllers[ObjectIdentifier(safariController)] =
            WeakSafariController(safariController)
    }
    #endif

    #if canImport(AVKit)
    func register(
        playerController: AVPlayerViewController,
        resume: (@MainActor () -> Void)? = nil
    ) -> Registration? {
        register(
            stop: { [weak playerController] in
                playerController?.player?.pause()
                playerController?.player?.replaceCurrentItem(with: nil)
            },
            resume: resume
        )
    }
    #endif

    /// Called synchronously after the central gate closes. Registered
    /// provider objects are canceled first; then mounted UIKit trees are
    /// swept so legacy/private wrappers cannot keep hidden WebKit, HLS, or
    /// Safari traffic alive behind the full-screen offline journey.
    func suspendAll() {
        isSuspended = true
        let registered = Array(transports.values)
        for transport in registered { transport.stop() }

        #if canImport(SafariServices)
        let safariControllers = pendingSafariControllers.values.compactMap(\.value)
        pendingSafariControllers.removeAll()
        for controller in safariControllers {
            controller.dismiss(animated: false)
        }
        #endif

        #if canImport(UIKit)
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                suspend(viewController: window.rootViewController)
            }
        }
        #endif
    }

    /// Recreate only transports whose still-mounted owner explicitly supplied
    /// a release callback. Registrations survive suspension so WebKit bridges
    /// and AVPlayer views do not remain permanently blank after the final
    /// radio-silence lease releases.
    func resumeAll() {
        guard !EusoTripAPI.shared.isAppRadioSilenceEnforced else { return }
        isSuspended = false
        let registered = Array(transports.values)
        for transport in registered { transport.resume?() }
    }

    #if canImport(UIKit)
    private func suspend(viewController: UIViewController?) {
        guard let viewController else { return }

        #if canImport(SafariServices)
        if viewController is SFSafariViewController {
            viewController.dismiss(animated: false)
        }
        #endif

        #if canImport(AVKit)
        if let playerController = viewController as? AVPlayerViewController {
            playerController.player?.pause()
            playerController.player?.replaceCurrentItem(with: nil)
        }
        #endif

        suspend(view: viewController.viewIfLoaded)
        for child in viewController.children {
            suspend(viewController: child)
        }
        suspend(viewController: viewController.presentedViewController)
    }

    private func suspend(view: UIView?) {
        guard let view else { return }
        #if canImport(WebKit)
        if let webView = view as? WKWebView {
            webView.stopLoading()
            webView.loadHTMLString("", baseURL: nil)
        }
        #endif
        for child in view.subviews {
            suspend(view: child)
        }
    }
    #endif
}
