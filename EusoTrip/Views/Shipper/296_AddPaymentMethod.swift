//
//  296_AddPaymentMethod.swift
//  EusoTrip — Shipper · Add payment method (Arc G).
//
//  Mobile-side, the canonical flow is Stripe SDK PaymentSheet —
//  iOS deferred ToolKit until the Stripe SDK target is added to the
//  Xcode project. Surface explicit "complete on web" path until then.
//

import SwiftUI

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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
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
                Text("Tap to complete card setup in the Stripe-hosted secure flow. iOS-native PaymentSheet ships in a follow-up round.")
                    .font(EType.body).foregroundStyle(palette.textPrimary).fixedSize(horizontal: false, vertical: true)
                Button {
                    if let u = URL(string: url) { UIApplication.shared.open(u) }
                } label: {
                    Text("Open secure setup").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(LinearGradient.diagonal).clipShape(Capsule())
                }.buttonStyle(.plain)
            }
        } else {
            LifecycleCard {
                Text("Setup endpoint not yet wired. Manage payment methods from the web shipper page until iOS PaymentSheet ships.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        struct Out: Decodable { let url: String? }
        do {
            let r: Out = try await EusoTripAPI.shared.api.queryNoInput("payments.createSetupSession")
            setupUrl = r.url
        } catch {
            // Endpoint not yet wired in this deploy — surface clean state.
            setupUrl = nil
        }
        loading = false
    }
}

#Preview("296 · Add payment · Night") {
    AddPaymentMethodScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("296 · Add payment · Afternoon") {
    AddPaymentMethodScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
