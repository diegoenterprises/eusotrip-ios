//
//  EusoWalletApplePayProvider.swift
//  EusoTrip — Apple Pay → Stripe SetupIntent → EusoWallet card-on-file.
//
//  Owns the Apple Pay flow that adds a card to the user's EusoWallet
//  *without* a Stripe SDK dependency. Stripe's REST API
//  (`POST https://api.stripe.com/v1/payment_methods`) accepts a
//  PassKit `PKPaymentToken` payload directly with the publishable key
//  in `Authorization: Bearer …`, returning a PaymentMethod id we
//  hand to the backend via `wallet.attachStripePaymentMethod`.
//
//  Why no SDK
//    The Stripe iOS SDK ships through SPM (`stripe-ios-spm`) and is
//    the canonical path. We chose the SDK-less path here because:
//      a. The package isn't yet in `Package.resolved`.
//      b. The SDK-less path is fully supported by Stripe and used in
//         production by lighter integrations that only need Apple Pay.
//      c. Switching to the SDK later is a 5-line refactor — replace
//         the URLSession call with `STPApi.shared.createPaymentMethod(...)`.
//    See `EUSO_WALLET_SETUP.md` for the SDK upgrade path.
//
//  Flow
//    1. App calls `EusoWalletApplePayProvider.shared.addCard(amount:)`
//       with a "verification charge" amount (Apple requires a non-zero
//       amount on the PKPaymentRequest even for SetupIntents — Stripe
//       documents using $0.01 or any amount; the backend SetupIntent
//       authorizes but doesn't capture).
//    2. PassKit shows the Apple Pay sheet. User authenticates with
//       Face ID / Touch Pay.
//    3. Apple Pay returns a `PKPayment` with `paymentData` (encrypted
//       PNGRT/EMV cryptogram).
//    4. We POST that data to Stripe → PaymentMethod id.
//    5. We POST the id to `wallet.attachStripePaymentMethod` so the
//       backend pins the method to the user's Stripe Customer.
//
//  Merchant identifier
//    Resolved from `EusoTrip.xcconfig`'s `APPLE_PAY_MERCHANT_ID`. Add
//    the key to xcconfig once the merchant ID is provisioned at
//    https://developer.apple.com/account/resources/identifiers/list/merchant.
//    Default fallback `merchant.com.app.eusotrip` matches the
//    project's bundle-id convention (verified against
//    `EusoTrip.xcodeproj/project.pbxproj` 2026-05-01).
//

import Foundation
import PassKit

// MARK: - Result envelope

public enum EusoWalletApplePayOutcome {
    /// Card was added successfully. `last4` is the brand-anonymized
    /// trailing digits (e.g. "4242"); `brand` is "visa", "amex", etc.
    case added(paymentMethodId: String, brand: String?, last4: String?)
    /// User cancelled the Apple Pay sheet.
    case cancelled
    /// User completed Apple Pay but Stripe / backend rejected the
    /// resulting card. `error` carries the surfaced error message.
    case failed(error: String)
}

// MARK: - Provider

@MainActor
public final class EusoWalletApplePayProvider: NSObject {
    public static let shared = EusoWalletApplePayProvider()

    /// Resolved at first use from Info.plist `APPLE_PAY_MERCHANT_ID`
    /// (which xcconfig substitutes from `APPLE_PAY_MERCHANT_ID =
    /// merchant.com.app.eusotrip`). Falls back to the bundle-id-
    /// matching default if the key isn't set so the provider still
    /// surfaces `unsupported` cleanly rather than crashing on a nil.
    public lazy var merchantIdentifier: String = {
        if let v = Bundle.main.object(forInfoDictionaryKey: "APPLE_PAY_MERCHANT_ID") as? String, !v.isEmpty {
            return v
        }
        return "merchant.com.app.eusotrip"
    }()

    /// Networks accepted. Discover/JCB intentionally omitted by
    /// default — most freight shippers' commercial cards are
    /// Visa/Mastercard/Amex; flip this to broaden coverage.
    public var supportedNetworks: [PKPaymentNetwork] = [.visa, .masterCard, .amex]

    /// True when the device + merchant ID can run Apple Pay. Call
    /// from the screen layer to gate the "Add via Apple Pay" CTA.
    public var canMakePayments: Bool {
        PKPaymentAuthorizationController.canMakePayments(usingNetworks: supportedNetworks)
    }

    private var setupIntentClientSecret: String?
    private var publishableKey: String?
    private var continuation: CheckedContinuation<EusoWalletApplePayOutcome, Never>?

    private override init() { super.init() }

    /// Top-level entry. Async so the call site can `await` the outcome
    /// and update its UI in one place. Always returns — never throws —
    /// because cancellation is a normal flow.
    public func addCard(verificationAmountUSD: Decimal = 0.01,
                        merchantDisplayName: String = "EusoWallet") async -> EusoWalletApplePayOutcome {
        guard canMakePayments else {
            return .failed(error: "Apple Pay isn't available on this device.")
        }

        // 1. Backend mints the SetupIntent and ships its publishable
        //    key + customer id. We treat both as opaque — Stripe
        //    rotates publishable keys per environment and our backend
        //    is the source of truth for which one applies.
        let intent: WalletAPI.StripeSetupIntent
        do {
            intent = try await EusoTripAPI.shared.wallet.createStripeSetupIntent()
        } catch {
            return .failed(error: "Couldn't reach EusoWallet. \(error.localizedDescription)")
        }
        self.setupIntentClientSecret = intent.clientSecret
        self.publishableKey = intent.publishableKey

        // 2. Build the PKPaymentRequest. Apple requires at least one
        //    line item; we use a $0.01 verification charge — Stripe's
        //    SetupIntent authorizes but doesn't capture, so the user
        //    is never billed.
        let request = PKPaymentRequest()
        request.merchantIdentifier   = merchantIdentifier
        request.supportedNetworks    = supportedNetworks
        request.merchantCapabilities = [.threeDSecure]
        request.countryCode          = "US"
        request.currencyCode         = "USD"
        request.paymentSummaryItems  = [
            PKPaymentSummaryItem(
                label: merchantDisplayName,
                amount: NSDecimalNumber(decimal: verificationAmountUSD)
            )
        ]

        // 3. Present Apple Pay. `withCheckedContinuation` bridges the
        //    classic delegate pattern into modern async/await.
        return await withCheckedContinuation { cont in
            self.continuation = cont
            let controller = PKPaymentAuthorizationController(paymentRequest: request)
            controller.delegate = self
            controller.present { presented in
                // controller.present completion is nonisolated; hop back
                // to the main actor before touching `resume(_:)`.
                if !presented {
                    Task { @MainActor [weak self] in
                        self?.resume(.failed(error: "Apple Pay sheet refused to present."))
                    }
                }
            }
        }
    }

    fileprivate func resume(_ outcome: EusoWalletApplePayOutcome) {
        let cont = continuation
        continuation = nil
        cont?.resume(returning: outcome)
    }
}

// MARK: - PassKit delegate

extension EusoWalletApplePayProvider: PKPaymentAuthorizationControllerDelegate {

    // 2026-05-17 — PKPaymentAuthorizationControllerDelegate methods are
    // declared `nonisolated` by the protocol but PassKit calls them on
    // the main thread (UIKit contract). Hopping back to @MainActor via
    // `Task { @MainActor in … }` lets us call the actor-isolated
    // `resume(_:)` without the Swift 6 strict-concurrency warning.

    nonisolated public func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss { [weak self] in
            // If `resume(_:)` already fired (success or backend
            // failure), this is a no-op. Cancellation lands here
            // when the user dismissed without authorizing.
            Task { @MainActor [weak self] in
                self?.resume(.cancelled)
            }
        }
    }

    nonisolated public func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let publishable = self.publishableKey else {
                completion(.init(status: .failure, errors: nil))
                self.resume(.failed(error: "EusoWallet returned no publishable key."))
                return
            }
            do {
                let pm = try await Self.createStripePaymentMethod(
                    publishableKey: publishable,
                    payment: payment
                )
                let attached = try await EusoTripAPI.shared.wallet.attachStripePaymentMethod(
                    paymentMethodId: pm.id
                )
                completion(.init(status: .success, errors: nil))
                self.resume(.added(
                    paymentMethodId: pm.id,
                    brand: attached.brand,
                    last4: attached.last4
                ))
            } catch {
                completion(.init(status: .failure, errors: [error]))
                self.resume(.failed(error: error.localizedDescription))
            }
        }
    }
}

// MARK: - Stripe REST helper

private extension EusoWalletApplePayProvider {

    /// Stripe `PaymentMethod` minimal decode — we only need the id.
    struct StripePaymentMethod: Decodable {
        let id: String
    }

    /// POSTs the Apple Pay token to Stripe's `/v1/payment_methods`
    /// endpoint with the publishable key in `Authorization: Bearer …`.
    /// The publishable key is not a secret (Stripe ships it client-
    /// side intentionally); only the secret key would be sensitive.
    static func createStripePaymentMethod(
        publishableKey: String,
        payment: PKPayment
    ) async throws -> StripePaymentMethod {
        // Stripe accepts the raw Apple Pay PNGRT JSON as the
        // `card[token]` form value, after we wrap it as a Stripe
        // Token. Two-step:
        //   a. POST /v1/tokens with type=apple_pay and the token data.
        //   b. POST /v1/payment_methods with type=card and the Token id.
        // (Newer Stripe API supports a one-shot `payment_method_data`,
        // but the two-step path is documented and stable.)

        // Step a — wrap the Apple Pay token in a Stripe Token.
        struct StripeToken: Decodable { let id: String }

        let tokenURL = URL(string: "https://api.stripe.com/v1/tokens")!
        var tokenReq = URLRequest(url: tokenURL)
        tokenReq.httpMethod = "POST"
        tokenReq.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")
        tokenReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let pkPaymentDataB64 = payment.token.paymentData.base64EncodedString()
        let pkPaymentDataString = String(data: payment.token.paymentData, encoding: .utf8) ?? ""
        // Stripe accepts the raw JSON string (preferred) — fall back
        // to base64 if the device returned a non-UTF8 token (rare).
        let stripeAppleData = pkPaymentDataString.isEmpty
            ? "pk_token[apple_pay]=\(pkPaymentDataB64.urlFormEncoded)"
            : "pk_token=\(pkPaymentDataString.urlFormEncoded)"
        let tokenBody = "card[apple_pay]=true&\(stripeAppleData)"
        tokenReq.httpBody = tokenBody.data(using: .utf8)

        let (tokenData, tokenResp) = try await URLSession.shared.data(for: tokenReq)
        try Self.throwIfStripeError(data: tokenData, response: tokenResp)
        let token = try JSONDecoder().decode(StripeToken.self, from: tokenData)

        // Step b — wrap the Token in a PaymentMethod.
        let pmURL = URL(string: "https://api.stripe.com/v1/payment_methods")!
        var pmReq = URLRequest(url: pmURL)
        pmReq.httpMethod = "POST"
        pmReq.setValue("Bearer \(publishableKey)", forHTTPHeaderField: "Authorization")
        pmReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        pmReq.httpBody = "type=card&card[token]=\(token.id)".data(using: .utf8)

        let (pmData, pmResp) = try await URLSession.shared.data(for: pmReq)
        try Self.throwIfStripeError(data: pmData, response: pmResp)
        return try JSONDecoder().decode(StripePaymentMethod.self, from: pmData)
    }

    /// Stripe error envelope: `{"error":{"message":"…","code":"…"}}`.
    /// We surface `message` if present so the UI shows actionable
    /// copy; falls back to the HTTP status when the body is empty.
    static func throwIfStripeError(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }

        struct Wrapper: Decodable {
            struct Inner: Decodable { let message: String? }
            let error: Inner?
        }
        if let parsed = try? JSONDecoder().decode(Wrapper.self, from: data),
           let m = parsed.error?.message {
            throw NSError(
                domain: "Stripe",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: m]
            )
        }
        throw NSError(
            domain: "Stripe",
            code: http.statusCode,
            userInfo: [NSLocalizedDescriptionKey: "Stripe returned HTTP \(http.statusCode)."]
        )
    }
}

// MARK: - Form-encoding helper

private extension String {
    /// `application/x-www-form-urlencoded` percent-encoding. The
    /// stdlib `addingPercentEncoding(.urlQueryAllowed)` leaves `+`
    /// and `&` untouched, both of which break Stripe's parser.
    var urlFormEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return self.addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
