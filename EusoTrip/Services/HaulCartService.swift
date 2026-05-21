//
//  HaulCartService.swift
//  The Haul redemption cart — IO 2026 P0-13 (Scope B).
//
//  Multi-item wrapper around the existing single-item
//  `advancedGamification.purchaseReward`. Drivers queue rewards
//  (cosmetics, fuel-credit promos, PTO grants, merch) from the
//  Haul rewards store, see a running total against their Haul
//  miles balance, and check out in one atomic call.
//
//  Per the founder's call (2026-05-20): the cart lives in The
//  Haul branded system, NOT in EusoWallet. EusoWallet retains
//  the partner-deep-link recommendation strip shipped in P0-5.
//
//  Drop into: EusoTrip/Services/HaulCartService.swift
//

import Foundation

// MARK: - Wire types

public struct HaulRewardLine: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String?
    public let category: String?
    public let cost: Int?
    public let inStock: Bool?
    public let available: Bool?
    public let missing: Bool?
    public let addedAt: String

    /// Whether this line is still redeemable. `missing == true` means
    /// the item left the catalog after the user added it; the UI
    /// should prompt removal.
    public var isRedeemable: Bool {
        (missing == nil || missing == false) && (inStock ?? true) && (available ?? true)
    }
}

public struct HaulCartState: Decodable, Hashable, Sendable {
    public let items: [HaulRewardLine]
    public let totalCost: Int
    public let balance: Int
    public let sufficientFunds: Bool
    public let itemCount: Int
}

public struct HaulCheckoutReceiptLine: Decodable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let cost: Int
    public let category: String
}

public struct HaulCheckoutReceipt: Decodable, Hashable, Sendable {
    public let success: Bool
    public let itemsRedeemed: Int
    public let totalCost: Int
    public let remainingBalance: Int
    public let rewardIds: [Int]
    public let receipt: [HaulCheckoutReceiptLine]
}

// MARK: - Catalog types (existing `getRewardsStore` reuse)

public struct HaulRewardCatalogItem: Decodable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let description: String?
    public let category: String
    public let cost: Int
    public let inStock: Bool
    public let prestigeRequired: Int?
    public let icon: String?
}

public struct HaulRewardsStoreResponse: Decodable, Hashable, Sendable {
    public let items: [HaulRewardCatalogItem]
    public let userPoints: Int
    public let userPrestige: Int
    public let categories: [Category]
    public struct Category: Decodable, Hashable, Sendable {
        public let id: String
        public let name: String
        public let count: Int
    }
}

// MARK: - Service

@MainActor
public final class HaulCartService: ObservableObject {
    public static let shared = HaulCartService()

    @Published public private(set) var cart: HaulCartState = HaulCartState(
        items: [], totalCost: 0, balance: 0, sufficientFunds: true, itemCount: 0
    )
    @Published public private(set) var catalog: HaulRewardsStoreResponse? = nil
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isCheckingOut: Bool = false
    @Published public private(set) var lastError: String? = nil
    @Published public private(set) var lastReceipt: HaulCheckoutReceipt? = nil

    public init() {}

    // MARK: Cart operations

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        await loadCart()
    }

    public func loadCatalog(category: String = "all") async {
        struct In: Encodable { let category: String }
        do {
            let result: HaulRewardsStoreResponse = try await EusoTripAPI.shared.query(
                "advancedGamification.getRewardsStore", input: In(category: category)
            )
            catalog = result
        } catch {
            // Quiet — catalog stays nil; view shows empty state.
        }
    }

    public func add(_ rewardId: String) async {
        lastError = nil
        struct In: Encodable { let rewardId: String }
        struct Out: Decodable { let success: Bool; let alreadyInCart: Bool; let itemCount: Int }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "advancedGamification.cartAdd", input: In(rewardId: rewardId)
            )
            await loadCart()
        } catch {
            lastError = (error as NSError).localizedDescription
        }
    }

    public func remove(_ rewardId: String) async {
        struct In: Encodable { let rewardId: String }
        struct Out: Decodable { let success: Bool; let itemCount: Int }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "advancedGamification.cartRemove", input: In(rewardId: rewardId)
            )
            await loadCart()
        } catch { /* quiet */ }
    }

    public func clear() async {
        struct EmptyIn: Encodable {}
        struct Out: Decodable { let success: Bool }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "advancedGamification.cartClear", input: EmptyIn()
            )
            await loadCart()
        } catch { /* quiet */ }
    }

    /// Atomic checkout — server validates balance + stock, debits Haul
    /// miles once, writes one rewards row per item, clears cart.
    public func checkout() async -> HaulCheckoutReceipt? {
        isCheckingOut = true
        lastError = nil
        defer { isCheckingOut = false }
        struct EmptyIn: Encodable {}
        do {
            let receipt: HaulCheckoutReceipt = try await EusoTripAPI.shared.mutation(
                "advancedGamification.cartCheckout", input: EmptyIn()
            )
            lastReceipt = receipt
            await loadCart()
            return receipt
        } catch {
            lastError = (error as NSError).localizedDescription
            return nil
        }
    }

    // MARK: Private

    private func loadCart() async {
        struct EmptyIn: Encodable {}
        do {
            let result: HaulCartState = try await EusoTripAPI.shared.query(
                "advancedGamification.cartList", input: EmptyIn()
            )
            cart = result
        } catch {
            // Quiet — cart stays at empty; lastError already set by caller.
        }
    }
}
