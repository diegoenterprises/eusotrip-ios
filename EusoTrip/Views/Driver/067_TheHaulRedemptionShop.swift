//
//  067_TheHaulRedemptionShop.swift
//  The Haul · Redemption Shop — IO 2026 P0-13 (Scope B).
//
//  Driver's full-screen rewards store with multi-item cart. Replaces
//  the single-tap purchaseReward UX with a queue + atomic checkout:
//
//    1. Browse catalog (filtered by category: all / fuel / pay /
//       pto / merch / cosmetic).
//    2. Tap items to add to cart; cart drawer at the bottom shows
//       running total against the driver's Haul miles balance.
//    3. Tap "Redeem" — server validates balance + stock atomically,
//       debits points once, writes one rewards row per item.
//
//  Surfaces in The Haul sub-navigation:
//    060L Lobby · 061 Missions · 062 Badges · 063 Crates ·
//    064 Leaderboard · 065 Streaks · 066 Cosmetics · 067 Shop ←
//
//  Drop into: EusoTrip/Views/Driver/067_TheHaulRedemptionShop.swift
//

import SwiftUI

public struct TheHaulRedemptionShopView: View {
    @StateObject private var svc = HaulCartService.shared
    @State private var selectedCategory: String = "all"
    @State private var showCart: Bool = false
    @State private var showReceipt: HaulCheckoutReceipt? = nil

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    categoryStrip
                    catalogGrid
                    Color.clear.frame(height: 130)  // breathing room above cart drawer
                }
                .padding(16)
            }
            cartDrawer
        }
        .navigationTitle("The Haul · Shop")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await svc.loadCatalog(category: selectedCategory)
            await svc.refresh()
        }
        .sheet(item: $showReceipt) { receipt in
            receiptSheet(receipt)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "cart.fill")
                    .foregroundStyle(LinearGradient(
                        colors: [.cyan, .green],
                        startPoint: .leading, endPoint: .trailing
                    ))
                Text("THE HAUL · REDEMPTION SHOP")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                pointsBadge
            }
            Text("Spend your Haul miles on perks, gear, and time off.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var pointsBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
            Text("\(svc.catalog?.userPoints ?? svc.cart.balance)")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
            Text("MI")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .opacity(0.7)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(LinearGradient(
            colors: [.cyan, .green],
            startPoint: .leading, endPoint: .trailing
        ), in: Capsule())
    }

    // MARK: - Categories

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(svc.catalog?.categories ?? [], id: \.id) { cat in
                    Button {
                        selectedCategory = cat.id
                        Task { await svc.loadCatalog(category: cat.id) }
                    } label: {
                        HStack(spacing: 4) {
                            Text(cat.name)
                                .font(.system(size: 12, weight: .semibold))
                            Text("(\(cat.count))")
                                .font(.system(size: 10))
                                .opacity(0.6)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(
                            selectedCategory == cat.id
                                ? AnyShapeStyle(LinearGradient(colors: [.cyan, .green], startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(Color.gray.opacity(0.12))
                        )
                        .foregroundStyle(selectedCategory == cat.id ? Color.white : Color.primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Catalog grid

    @ViewBuilder
    private var catalogGrid: some View {
        if let items = svc.catalog?.items, !items.isEmpty {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(items) { item in
                    catalogCard(item)
                }
            }
        } else if svc.catalog == nil {
            HStack {
                ProgressView().controlSize(.small)
                Text("Loading shop…").foregroundStyle(.secondary).font(.callout)
            }
        } else {
            Text("No items in this category.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 24)
        }
    }

    @ViewBuilder
    private func catalogCard(_ item: HaulRewardCatalogItem) -> some View {
        let isInCart = svc.cart.items.contains(where: { $0.id == item.id })
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconForCategory(item.category))
                    .font(.system(size: 18))
                    .foregroundStyle(.tint)
                Spacer(minLength: 0)
                Text("\(item.cost) mi")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.tint.opacity(0.12), in: Capsule())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                if let desc = item.description {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Button {
                if isInCart {
                    Task { await svc.remove(item.id) }
                } else {
                    Task { await svc.add(item.id) }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isInCart ? "checkmark" : "plus")
                    Text(isInCart ? "In cart" : "Add")
                }
                .font(.system(size: 12, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(isInCart ? AnyShapeStyle(Color.green.opacity(0.18))
                                     : AnyShapeStyle(LinearGradient(
                                            colors: [.cyan, .green],
                                            startPoint: .leading, endPoint: .trailing)))
                .foregroundStyle(isInCart ? Color.green : Color.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!item.inStock)
        }
        .padding(12)
        .background(.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .opacity(item.inStock ? 1.0 : 0.5)
    }

    private func iconForCategory(_ cat: String) -> String {
        switch cat {
        case "fuel":     return "fuelpump.fill"
        case "pay":      return "banknote.fill"
        case "pto":      return "calendar"
        case "merch":    return "tshirt.fill"
        case "cosmetic": return "sparkles"
        default:         return "gift.fill"
        }
    }

    // MARK: - Cart drawer

    @ViewBuilder
    private var cartDrawer: some View {
        if svc.cart.itemCount > 0 {
            VStack(spacing: 0) {
                if showCart { cartDrawerExpanded }
                cartDrawerCollapsed
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .shadow(radius: 8)
        }
    }

    private var cartDrawerCollapsed: some View {
        Button {
            showCart.toggle()
        } label: {
            HStack {
                Image(systemName: showCart ? "chevron.down" : "chevron.up")
                    .font(.system(size: 12, weight: .bold))
                Text("\(svc.cart.itemCount) item\(svc.cart.itemCount == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                Text("\(svc.cart.totalCost) mi")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundStyle(svc.cart.sufficientFunds ? Color.primary : Color.red)
                checkoutButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var cartDrawerExpanded: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(svc.cart.items) { line in
                cartLineRow(line)
            }
            if !svc.cart.sufficientFunds {
                Text("You're short \(svc.cart.totalCost - svc.cart.balance) miles. Drop an item or earn more before redeeming.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let err = svc.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.gray.opacity(0.05))
    }

    @ViewBuilder
    private func cartLineRow(_ line: HaulRewardLine) -> some View {
        HStack(spacing: 8) {
            if let name = line.name {
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            } else {
                Text(line.id)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            if line.missing == true {
                Text("REMOVED")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(.red)
            }
            Spacer(minLength: 0)
            if let cost = line.cost {
                Text("\(cost) mi")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
            }
            Button {
                Task { await svc.remove(line.id) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
        }
    }

    private var checkoutButton: some View {
        Button {
            Task {
                if let receipt = await svc.checkout() {
                    showReceipt = receipt
                }
            }
        } label: {
            HStack(spacing: 4) {
                if svc.isCheckingOut {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                }
                Text("Redeem")
                    .font(.system(size: 12, weight: .bold))
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(svc.cart.sufficientFunds
                        ? AnyShapeStyle(LinearGradient(
                            colors: [.cyan, .green],
                            startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Color.gray.opacity(0.4)))
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!svc.cart.sufficientFunds || svc.isCheckingOut || svc.cart.itemCount == 0)
    }

    // MARK: - Receipt

    @ViewBuilder
    private func receiptSheet(_ r: HaulCheckoutReceipt) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                VStack(alignment: .leading) {
                    Text("Redeemed").font(.title3.bold())
                    Text("\(r.itemsRedeemed) item\(r.itemsRedeemed == 1 ? "" : "s") · \(r.totalCost) miles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            ForEach(r.receipt, id: \.id) { line in
                HStack {
                    Image(systemName: iconForCategory(line.category))
                        .foregroundStyle(.tint)
                    Text(line.name)
                        .font(.callout)
                    Spacer(minLength: 0)
                    Text("\(line.cost) mi")
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                }
            }
            Divider()
            HStack {
                Text("Remaining balance")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("\(r.remainingBalance) mi")
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
            }
            Button {
                showReceipt = nil
            } label: {
                Text("Done")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(LinearGradient(
                        colors: [.cyan, .green],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(20)
        // Visible, working close at the top-trailing (drag-to-dismiss was
        // the only top affordance; the inline "Done" stays as the primary).
        .overlay(alignment: .topTrailing) {
            SheetCloseButton { showReceipt = nil }
                .padding(16)
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Identifiable conformance for sheet(item:)

extension HaulCheckoutReceipt: Identifiable {
    public var id: Int { rewardIds.first ?? Int.random(in: 0..<Int.max) }
}

// MARK: - Previews

#Preview("The Haul · Shop · Dark") {
    NavigationStack { TheHaulRedemptionShopView() }
        .preferredColorScheme(.dark)
}

#Preview("The Haul · Shop · Light") {
    NavigationStack { TheHaulRedemptionShopView() }
        .preferredColorScheme(.light)
}
