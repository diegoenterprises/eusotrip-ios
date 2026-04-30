//
//  295_PaymentMethods.swift
//  EusoTrip — Shipper · Payment methods (Arc G).
//  Backed by `payments.getPaymentMethods`.
//

import SwiftUI

struct PaymentMethodsScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { PaymentMethodsBody() } nav: { shipperLifecycleNav() }
    }
}

private struct PaymentMethod: Decodable, Identifiable, Hashable {
    let id: String
    let type: String?      // card / ach / wallet
    let last4: String?
    let brand: String?
    let isDefault: Bool?
    let nickname: String?
}

private struct PaymentMethodsBody: View {
    @Environment(\.palette) private var palette
    @State private var methods: [PaymentMethod] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                addButton
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "creditcard.and.123").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("SHIPPER · PAYMENT METHODS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Payment methods").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            LifecycleCard { Text("Loading payment methods…").font(EType.caption).foregroundStyle(palette.textSecondary) }
        } else if let err = loadError {
            LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
        } else if methods.isEmpty {
            EusoEmptyState(systemImage: "creditcard", title: "No methods on file", subtitle: "Add a card or ACH method to enable wallet auto-pay.")
        } else {
            ForEach(methods) { m in
                LifecycleCard(accentGradient: m.isDefault == true) {
                    LifecycleSection(label: dashIfEmpty(m.brand?.uppercased() ?? m.type?.uppercased()), icon: "creditcard")
                    LifecycleRow(label: "Nickname",  value: dashIfEmpty(m.nickname))
                    LifecycleRow(label: "Last 4",    value: dashIfEmpty(m.last4))
                    LifecycleRow(label: "Default",   value: m.isDefault == true ? "Yes" : "No")
                }
            }
        }
    }

    private var addButton: some View {
        Button {
            NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "296"])
        } label: {
            Text("Add payment method").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [PaymentMethod] = try await EusoTripAPI.shared.queryNoInput("payments.getPaymentMethods")
            methods = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("295 · Payment methods · Night") {
    PaymentMethodsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("295 · Payment methods · Afternoon") {
    PaymentMethodsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
