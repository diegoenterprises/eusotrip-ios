//
//  CartView.swift
//  Universal Cart — IO 2026 P0-5 (EusoWallet).
//
//  Full-screen Universal Cart view hosted under the wallet tab.
//  Lists every cart recommendation surfaced by
//  `esangBrief.getUniversalCart` (fuel cards / permits / tolls /
//  insurance / factoring / compliance modules) with one-flow
//  enrollment per item. The Daily Brief widget on Home shows a
//  horizontal strip teaser; this view is the full surface.
//
//  Drop into: EusoTrip/Views/Wallet/CartView.swift
//

import SwiftUI

public struct CartView: View {
    @State private var items: [CartRecommendation] = []
    @State private var isLoading: Bool = false
    @State private var loadError: String? = nil
    let onCtaTap: ((String) -> Void)?

    public init(onCtaTap: ((String) -> Void)? = nil) {
        self.onCtaTap = onCtaTap
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if isLoading && items.isEmpty {
                    ProgressView().padding(.top, 24)
                } else if items.isEmpty {
                    Text(loadError ?? "Nothing in your cart right now.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.top, 24)
                } else {
                    ForEach(items) { item in
                        CartRow(item: item, onCta: { path in onCtaTap?(path) })
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Universal Cart")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "cart.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LinearGradient(
                        colors: [.cyan, .green],
                        startPoint: .leading, endPoint: .trailing
                    ))
                Text("ESANG · UNIVERSAL CART")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)
            }
            Text("Bundle fuel, permits, tolls, insurance, and compliance in one EusoWallet flow.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        struct Out: Decodable { let cart: [CartRecommendation]; let sampledAt: String? }
        do {
            let result: Out = try await EusoTripAPI.shared.query(
                "esangBrief.getUniversalCart",
                input: EmptyInput()
            )
            items = result.cart
        } catch {
            loadError = "Couldn't load cart: \((error as NSError).localizedDescription)"
        }
    }
}

/// File-scope empty-input marker (parameterless tRPC queries encode
/// to `{}` over the wire — Swift requires the type, not a literal).
private struct EmptyInput: Encodable, Sendable {}

private struct CartRow: View {
    let item: CartRecommendation
    let onCta: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let est = item.estValueUsd {
                        Text("~$\(Int(est)) estimated value")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tint)
                    }
                }
                Spacer(minLength: 0)
            }
            Text(item.rationale)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { onCta(item.ctaPath) } label: {
                Text("Add to cart")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.tint, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(.gray.opacity(0.08))
        )
    }
}

// MARK: - Previews

#Preview("Cart View · Dark") {
    NavigationStack {
        CartView()
    }
    .preferredColorScheme(.dark)
}

#Preview("Cart View · Light") {
    NavigationStack {
        CartView()
    }
    .preferredColorScheme(.light)
}
