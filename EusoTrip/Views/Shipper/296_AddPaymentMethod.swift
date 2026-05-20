//
//  296_AddPaymentMethod.swift
//  EusoTrip — Shipper · Add payment method (Arc G).
//
//  Mobile-side, the canonical flow is Stripe SDK PaymentSheet —
//  iOS deferred ToolKit until the Stripe SDK target is added to the
//  Xcode project. Surface explicit "complete on web" path until then.
//

import SwiftUI
import SafariServices
import UIKit

struct AddPaymentMethodScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { AddPaymentMethodBody() } nav: { shipperLifecycleNav() }
    }
}

private struct AddPaymentMethodBody: View {
    @Environment(\.palette) private var palette
    @State private var setupUrl: String? = nil
    @State private var loading: Bool = true
    @State private var loadError: String? = nil
    /// In-app SFSafariViewController presentation for the
    /// Stripe-hosted secure session. PCI-DSS requires a real
    /// browser engine for card capture, but we surface it as an
    /// in-app modal (SFSafariViewController) so the user never
    /// leaves the EusoTrip app. The session cookie is namespaced
    /// to Stripe's domain, so no auth handoff is needed.
    private struct StripeSession: Identifiable, Hashable {
        let id: UUID
        let url: URL
    }
    @State private var stripeSession: StripeSession? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 56)
        }
        .task { await load() }
        .sheet(item: $stripeSession) { sess in
            StripeSecureSafariView(url: sess.url)
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "creditcard").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · ADD PAYMENT METHOD").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Add a payment method").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            LifecycleCard { Text("Preparing secure session…").font(EType.caption).foregroundStyle(palette.textSecondary) }
        } else if let err = loadError {
            LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
        } else if let url = setupUrl {
            LifecycleCard(accentGradient: true) {
                LifecycleSection(label: "STRIPE SECURE SESSION", icon: "checkmark.shield")
                Text("Tap to complete card or ACH setup in the Stripe-hosted secure flow. Returns here when the method is attached.")
                    .font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Button {
                    if let u = URL(string: url) {
                        stripeSession = StripeSession(id: UUID(), url: u)
                    }
                } label: {
                    Text("Open secure setup").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                }.buttonStyle(.plain)
            }
        } else {
            LifecycleCard(accentDanger: true) {
                Text("Couldn't reach Stripe. Check the connection and try again.")
                    .font(EType.caption).foregroundStyle(Brand.danger).fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await load() }
                } label: {
                    Text("Retry").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Brand.danger).clipShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct Out: Decodable { let url: String? }
        do {
            let r: Out = try await EusoTripAPI.shared.queryNoInput("payments.createSetupSession")
            setupUrl = r.url
        } catch {
            // Endpoint not yet wired in this deploy — surface clean state.
            setupUrl = nil
        }
        loading = false
    }
}

// MARK: - In-app SFSafariViewController bridge

/// Hosts the Stripe-hosted secure card-capture page in an in-app
/// SFSafariViewController modal. Mirrors the EusoTrip gradient via
/// the bar tint so the chrome doesn't feel like a Safari kick-out.
private struct StripeSecureSafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let cfg = SFSafariViewController.Configuration()
        cfg.entersReaderIfAvailable = false
        cfg.barCollapsingEnabled = true
        let vc = SFSafariViewController(url: url, configuration: cfg)
        // Tint chrome to brand magenta so the in-app browser reads
        // as part of EusoTrip, not a generic Safari sheet.
        vc.preferredBarTintColor = nil
        vc.preferredControlTintColor = UIColor(red: 0.745, green: 0.004, blue: 1.0, alpha: 1)
        vc.dismissButtonStyle = .done
        return vc
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

#Preview("296 · Add payment · Night") {
    AddPaymentMethodScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("296 · Add payment · Afternoon") {
    AddPaymentMethodScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
