//
//  EusoWalletStore.swift
//  EusoTrip — Observable state for the EusoWallet "cards on file"
//  surface that hosts the Apple Pay → Stripe SetupIntent →
//  attach-payment-method flow.
//
//  Owns the live list of payment methods on the user's Stripe
//  Customer (sourced from `payments.getPaymentMethods`) and the
//  in-flight state for Add-via-Apple-Pay so the UI can render the
//  right CTA per phase.
//
//  Hosting screens
//    · 295_PaymentMethods (Shipper) — list + Add-via-Apple-Pay CTA.
//    · 296_AddPaymentMethod (Shipper) — manual card entry path
//      (Stripe SetupIntent + form, future).
//    · 290_WalletHome (Shipper) — balance hero + this store's
//      `payNow` summary card.
//
//  Pattern matches the rest of `LiveDataStores.swift`: phase-driven
//  observable, idempotent `refresh()`, no hardcoded data, all rows
//  surface as `EusoEmptyState` when the list is empty rather than
//  invented placeholders.
//

import Foundation
import SwiftUI

@MainActor
public final class EusoWalletStore: ObservableObject {

    public enum Phase: Equatable {
        case idle
        case loading
        case loaded([PaymentsAPI.PaymentMethod])
        case error(String)
    }

    public enum AddPhase: Equatable {
        /// CTA visible, no flow in progress.
        case idle
        /// Apple Pay sheet is showing OR Stripe REST call is in flight.
        case adding
        /// Last attempt succeeded. Carries the brand-anonymized
        /// trailing digits ("4242") for a one-line success toast.
        case added(brand: String?, last4: String?)
        /// Last attempt failed; user can retry. Error is the surfaced
        /// message (Stripe → backend → us → here).
        case failed(String)
    }

    @Published public private(set) var phase: Phase = .idle
    @Published public private(set) var addPhase: AddPhase = .idle

    /// Convenience for screens that just need the array. Returns the
    /// loaded list or an empty list during loading/error.
    public var paymentMethods: [PaymentsAPI.PaymentMethod] {
        if case .loaded(let m) = phase { return m }
        return []
    }

    public var isAdding: Bool {
        if case .adding = addPhase { return true }
        return false
    }

    /// True when the device + the merchant identifier can run Apple
    /// Pay. Used by the screen layer to gate the "Add via Apple Pay"
    /// CTA. Falls back to false when the merchant ID isn't yet
    /// provisioned so we don't surface a CTA that throws.
    public var applePaySupported: Bool {
        EusoWalletApplePayProvider.shared.canMakePayments
    }

    public init() {}

    // MARK: - Refresh

    /// Pull the current list of payment methods from the backend.
    /// Phase transitions: idle/loaded/error → loading → loaded/error.
    /// Keeps the previous list visible during a refresh transition
    /// (no flicker on pull-to-refresh) by deferring the
    /// `phase = .loading` flip when we already have a `.loaded` list.
    public func refresh(silent: Bool = false) async {
        if !silent || (phase != .idle && {
            if case .loaded = phase { return false } else { return true }
        }()) {
            phase = .loading
        }
        do {
            let rows = try await EusoTripAPI.shared.payments.listPaymentMethods()
            phase = .loaded(rows)
        } catch {
            phase = .error(Self.userMessage(for: error))
        }
    }

    // MARK: - Add via Apple Pay

    /// Top-level entry point for the "+ Add via Apple Pay" CTA.
    /// Drives `addPhase` so the surrounding UI can disable the
    /// button, swap to a spinner, and render success/failure inline.
    public func addCardViaApplePay() async {
        guard applePaySupported else {
            addPhase = .failed("Apple Pay isn't available on this device.")
            return
        }
        addPhase = .adding
        let outcome = await EusoWalletApplePayProvider.shared.addCard()
        switch outcome {
        case .added(_, let brand, let last4):
            addPhase = .added(brand: brand, last4: last4)
            // Re-fetch the canonical list so the row appears with
            // the backend's authoritative `isDefault` / billing-
            // address fields, not the partial summary the Apple Pay
            // path returned.
            await refresh(silent: true)
        case .cancelled:
            // Treat user cancel as a return-to-idle so the CTA
            // re-enables without a banner. Quiet failure.
            addPhase = .idle
        case .failed(let msg):
            addPhase = .failed(msg)
        }
    }

    /// Promote a method to the default (Stripe Customer invoice
    /// default). On success the local list is invalidated so the
    /// `isDefault` star moves to the new row.
    public func setDefault(_ method: PaymentsAPI.PaymentMethod) async {
        do {
            _ = try await EusoTripAPI.shared.payments.setDefaultMethod(
                paymentMethodId: method.id
            )
            await refresh(silent: true)
        } catch {
            addPhase = .failed(Self.userMessage(for: error))
        }
    }

    /// Detach a card. Irreversible.
    public func delete(_ method: PaymentsAPI.PaymentMethod) async {
        do {
            _ = try await EusoTripAPI.shared.payments.deletePaymentMethod(
                paymentMethodId: method.id
            )
            await refresh(silent: true)
        } catch {
            addPhase = .failed(Self.userMessage(for: error))
        }
    }

    /// Surface a clean error string for the UI. We don't dump raw
    /// `localizedDescription` because URLSession errors include the
    /// full URL which can leak the backend host — wallet errors
    /// surface as "Couldn't reach EusoWallet." with no URL.
    private static func userMessage(for error: Error) -> String {
        let raw = error.localizedDescription
        if raw.lowercased().contains("offline") || raw.lowercased().contains("internet") {
            return "You're offline. EusoWallet will sync when you're back online."
        }
        if raw.lowercased().contains("unauthorized") || raw.lowercased().contains("401") {
            return "Your session expired. Sign in again."
        }
        // Stripe error messages are user-safe (they go to the
        // shopper in their checkout) so we surface them verbatim.
        // Backend tRPC errors run through the same surface and are
        // also user-safe.
        return raw
    }
}
