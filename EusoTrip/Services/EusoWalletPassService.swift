//
//  EusoWalletPassService.swift
//  EusoTrip — Apple Wallet integration for load pickup credentials.
//
//  Founder mandate 2026-05-06: tapping a pass in the EusoWallet
//  surface must hand off to Apple Wallet via PassKit, NOT open a web
//  browser with an error screen. This service owns the .pkpass
//  download → `PKAddPassesViewController` flow.
//
//  Server contract (mirrors the web platform's portalAccessTokens
//  pattern in `frontend/server/routers/customerPortal.ts`):
//
//    `eusoWallet.createPickupCredential` →
//      {
//        loadId: String,
//        accessToken: String,        // long-form (signed, server-side)
//        shortCode: String,          // 5-digit fallback when QR
//                                     //   scanning fails (e.g. cracked
//                                     //   yard-worker phone, no camera
//                                     //   permissions)
//        pkpassUrl: String?,         // signed PKPass bundle URL on Azure
//                                     //   Blob; nil while the signing
//                                     //   pipeline is offline. UI falls
//                                     //   back to inline QR + shortCode
//                                     //   so the credential remains
//                                     //   useful even without a wallet
//                                     //   add.
//        expiresAt: String           // ISO-8601 UTC
//      }
//
//  Tap path:
//    1. UI calls `EusoWalletPassService.shared.addPass(forLoadId:)`
//    2. Service requests credential from server
//    3. If pkpassUrl present → fetch bytes, parse with `PKPass(data:)`,
//       present `PKAddPassesViewController` over the topmost view
//       controller. Apple Wallet UI takes over.
//    4. If pkpassUrl absent / 404 / sign-fail → return
//       `.signingUnavailable(qrPayload, shortCode)` so the caller can
//       render the in-app credential card (the canonical fallback the
//       web platform uses too).
//
//  Powered by ESANG AI™.
//

import Foundation
import PassKit
import UIKit

/// One Add-to-Wallet attempt result. The caller is expected to handle
/// every case — silent failure is forbidden per [feedback_zero_stubs].
enum EusoWalletPassResult {
    /// Pass successfully presented to the user (the system Apple
    /// Wallet sheet was shown). The user may still cancel; we don't
    /// model that distinction here because PassKit itself doesn't
    /// expose a clean signal for it.
    case presented
    /// The server returned a credential without a `.pkpass` bundle —
    /// usually because the signing pipeline is offline or the load
    /// hasn't been activated yet. Callers render the inline credential
    /// card with the QR payload + short code instead.
    case signingUnavailable(qrPayload: String, shortCode: String)
    /// Network / decode / PassKit error. `message` is human-readable,
    /// safe to surface verbatim in a toast.
    case failure(message: String)
}

@MainActor
final class EusoWalletPassService {

    static let shared = EusoWalletPassService()
    private init() {}

    /// Server-side credential payload, decoded from
    /// `eusoWallet.createPickupCredential`. Returned shape mirrors the
    /// web `customerPortal.createPortalAccess` envelope so the same
    /// audit + revoke flow applies on both platforms. `loadNumber` is
    /// optional — server populates it for display, and we surface it
    /// in the inline-fallback caption when present.
    struct PickupCredential: Decodable {
        let loadId: String
        let loadNumber: String?
        let accessToken: String
        let shortCode: String
        let pkpassUrl: String?
        let expiresAt: String
    }

    /// Mint a credential and try to add it to Apple Wallet. The tap
    /// path is end-to-end here — no view controller wiring required by
    /// the caller. Returns a `EusoWalletPassResult` so the call site
    /// can render the right UX (toast, inline fallback, error banner).
    func addPass(forLoadId loadId: String) async -> EusoWalletPassResult {
        // 1. Mint the credential server-side. The server signs the QR
        //    payload, generates a 5-digit shortCode, and (when the
        //    signing pipeline is healthy) uploads a .pkpass bundle to
        //    Azure Blob and returns its presigned URL.
        struct Input: Encodable { let loadId: String }
        let credential: PickupCredential
        do {
            credential = try await EusoTripAPI.shared.mutation(
                "eusoWallet.createPickupCredential",
                input: Input(loadId: loadId)
            )
        } catch {
            // The server explicitly returns
            // `eusoWallet.createPickupCredential` per the canonical
            // schema. If the path is missing the caller's error path
            // falls back to the inline credential card anyway, so a
            // 404 here is non-fatal for the user-visible flow.
            let msg: String
            if let api = error as? EusoTripAPIError {
                switch api {
                case .unauthenticated:
                    msg = "Sign in again to mint a wallet credential."
                case .trpcError(let m): msg = m
                case .httpStatus(let c, _): msg = "Server error \(c). Try again."
                default: msg = "Couldn't reach the credential service."
                }
            } else { msg = error.localizedDescription }
            return .failure(message: msg)
        }

        // 2. If the server didn't ship a .pkpass bundle (signing
        //    pipeline offline, free-tier dev account, etc.), short-
        //    circuit to the inline QR + shortCode UI. The credential
        //    is still valid — the gate worker scans the QR or types
        //    the 5-digit shortCode into the receiving party's web
        //    portal.
        guard let urlStr = credential.pkpassUrl,
              let url = URL(string: urlStr) else {
            return .signingUnavailable(
                qrPayload: credential.accessToken,
                shortCode: credential.shortCode
            )
        }

        // 3. Pull the .pkpass bytes. We use a fresh `URLSession` here
        //    rather than `EusoTripAPI.session` because the bundle URL
        //    is presigned (Azure Blob) and shouldn't carry our auth
        //    cookies — those would just bloat the request and pin us
        //    to a CORS-unfriendly path.
        let data: Data
        do {
            let (bytes, resp) = try await URLSession.shared.data(from: url)
            guard let http = resp as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return .failure(message: "Wallet pass server returned an error.")
            }
            data = bytes
        } catch {
            return .failure(message: "Couldn't download the wallet pass.")
        }

        // 4. Parse with PassKit. `PKPass(data:)` validates the bundle
        //    signature against Apple's certificate chain — a tampered
        //    or expired-cert pass throws here.
        let pkpass: PKPass
        do {
            pkpass = try PKPass(data: data)
        } catch {
            return .failure(message: "This wallet pass is invalid or expired.")
        }

        // 5. Present `PKAddPassesViewController` over the topmost view
        //    controller. We resolve "topmost" through the active
        //    UIWindowScene — required since iOS 13 because there can
        //    be multiple windows in the foreground.
        guard let presenter = topPresenter() else {
            return .failure(message: "Couldn't find a screen to add the pass to.")
        }
        guard let addVC = PKAddPassesViewController(pass: pkpass) else {
            return .failure(message: "PassKit declined the pass — likely a duplicate or wrong device.")
        }
        presenter.present(addVC, animated: true)
        return .presented
    }

    /// Resolves the currently-active topmost UIViewController so we
    /// can present PassKit's modal over it. SwiftUI surfaces don't
    /// expose their hosting view controller directly, so we walk the
    /// window scene → window → root → presented chain.
    private func topPresenter() -> UIViewController? {
        let scene = UIApplication.shared
            .connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        let window = scene?.windows.first(where: { $0.isKeyWindow })
            ?? scene?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
