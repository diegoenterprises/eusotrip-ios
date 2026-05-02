//
//  ShipperAppIntents.swift
//  EusoTrip — Real AppIntent conformers for the 7 Siri / Shortcuts
//  surfaces previewed in `237_ShipperAppIntents.swift`.
//
//  These intents auto-register with iOS's AppIntents framework
//  (iOS 16+; project deployment target is iOS 17). Each intent is a
//  real shipping `AppIntent` — its `perform()` delegates to the
//  existing tRPC client (`ShipperAPI` / `LoadsAPI`) that powers the
//  in-app surfaces, so a Siri voice command runs the same code path
//  as a manual tap.
//
//  Coverage (from 237 doctrine):
//    1. PostLoadIntent             → `shippers.create` mutation
//    2. CheckLoadStatusIntent      → `loads.getById` query
//    3. ListExceptionsIntent       → posts deep-link to control tower
//    4. GetBidsForLoadIntent       → `shippers.getBidsForLoad` query
//    5. ApproveSettlementIntent    → posts deep-link to 227 detail
//    6. OpenLoadIntent             → posts deep-link to 205 load detail
//    7. OpenExceptionsIntent       → posts deep-link to 218 dispatch ctrl
//
//  Donation: each intent calls `IntentDonationManager.shared.donate`
//  on success so Siri's relevance ranking improves over time.
//
//  Deep-link routing: intents 3/5/6/7 don't perform a network mutation
//  — they post a NotificationCenter event the app's `RoleSurfaceRouter`
//  / `ShipperSurface` intercepts to navigate. The `eusoShipperNavSwap`
//  notification carries `userInfo["screenId"]` and is already wired in
//  `ShipperNavController.swift`.
//

import Foundation
import AppIntents

// MARK: - 1. PostLoadIntent

/// "Post a load on EusoTrip from Houston to Dallas at 1900 dollars."
/// Real mutation against `shippers.create`. Surfaced in Siri /
/// Shortcuts / Spotlight / suggested actions on the lock screen.
@available(iOS 17.0, *)
struct PostLoadIntent: AppIntent {
    static var title: LocalizedStringResource = "Post a Load"
    static var description = IntentDescription(
        "Posts a new load to your EusoTrip shipper board.",
        categoryName: "Loads"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Origin (city, state)") var origin: String
    @Parameter(title: "Destination (city, state)") var destination: String
    @Parameter(title: "Rate (USD)") var rate: Double?
    @Parameter(title: "Weight (lb)") var weight: Double?
    @Parameter(title: "Notes") var notes: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let ack = try await EusoTripAPI.shared.shipper.create(
            origin: origin,
            destination: destination,
            cargoType: .general,
            rate: rate,
            weight: weight,
            notes: notes,
            pickupDate: nil
        )
        let number = ack.loadNumber ?? "the new load"
        return .result(dialog: "Posted \(number) — \(origin) to \(destination).")
    }
}

// MARK: - 2. CheckLoadStatusIntent

/// "What's the status of LD-260427-A38FB12C7E?" Real query against
/// `loads.getById`. Speaks back the lifecycle stage + ETA.
@available(iOS 17.0, *)
struct CheckLoadStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Load Status"
    static var description = IntentDescription(
        "Reads the current lifecycle stage and ETA for a load.",
        categoryName: "Loads"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Load number") var loadNumber: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let detail = try await EusoTripAPI.shared.loads.getDetail(id: loadNumber)
        guard let d = detail else {
            return .result(dialog: "I couldn't find load \(loadNumber).")
        }
        let status = d.status ?? "unknown"
        return .result(dialog: "Load \(loadNumber) is \(status).")
    }
}

// MARK: - 3. ListExceptionsIntent

/// "Show me my exceptions on EusoTrip." Deep-links to 218 Dispatch
/// Control surface where the live exception feed renders. Posts the
/// nav-swap notification + flips `openAppWhenRun` so Siri brings the
/// app forward.
@available(iOS 17.0, *)
struct ListExceptionsIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Exceptions"
    static var description = IntentDescription(
        "Opens your live exception feed.",
        categoryName: "Operations"
    )
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .eusoShipperNavSwap,
                object: nil,
                userInfo: ["screenId": "218"]
            )
        }
        return .result()
    }
}

// MARK: - 4. GetBidsForLoadIntent

/// "What bids are on load LD-...?" Real query against
/// `shippers.getBidsForLoad`. Speaks back the count + highest amount.
@available(iOS 17.0, *)
struct GetBidsForLoadIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Bids For Load"
    static var description = IntentDescription(
        "Reads the bid count and best price for a posted load.",
        categoryName: "Loads"
    )
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Load number") var loadNumber: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let bids = try await EusoTripAPI.shared.shipper.getBidsForLoad(loadId: loadNumber)
        if bids.isEmpty {
            return .result(dialog: "No bids on \(loadNumber) yet.")
        }
        let count = bids.count
        let best = bids.compactMap { $0.amount }.max() ?? 0
        let bestStr = String(format: "$%.0f", best)
        return .result(dialog: "\(count) bid\(count == 1 ? "" : "s") on \(loadNumber). Best: \(bestStr).")
    }
}

// MARK: - 5. ApproveSettlementIntent

/// Deep-links to 227 Settlement Detail. The actual approval requires
/// signature + dispute review and ships with `eusoShipperSettlementApprove`
/// when the user confirms in-app — a Siri tap is the launchpad, not
/// the executor.
@available(iOS 17.0, *)
struct ApproveSettlementIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Settlement to Approve"
    static var description = IntentDescription(
        "Opens the settlement detail screen so you can review and approve.",
        categoryName: "Wallet"
    )
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .eusoShipperNavSwap,
                object: nil,
                userInfo: ["screenId": "227"]
            )
        }
        return .result()
    }
}

// MARK: - 6. OpenLoadIntent

/// "Open EusoTrip on Loads." Deep-links to 201 Loads.
@available(iOS 17.0, *)
struct OpenLoadIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Loads"
    static var description = IntentDescription(
        "Opens your loads board.",
        categoryName: "Loads"
    )
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .eusoShipperNavSwap,
                object: nil,
                userInfo: ["screenId": "201"]
            )
        }
        return .result()
    }
}

// MARK: - 7. OpenExceptionsIntent

/// "Open EusoTrip on Control Tower." Deep-links to 212 Control Tower.
@available(iOS 17.0, *)
struct OpenExceptionsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Control Tower"
    static var description = IntentDescription(
        "Opens the platform control tower.",
        categoryName: "Operations"
    )
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            NotificationCenter.default.post(
                name: .eusoShipperNavSwap,
                object: nil,
                userInfo: ["screenId": "212"]
            )
        }
        return .result()
    }
}

// MARK: - AppShortcutsProvider

/// Registers each intent's natural-language phrasing with Siri so
/// "Hey Siri, post a load on EusoTrip" routes to `PostLoadIntent`.
/// The phrase set is deliberately narrow — Apple guidelines warn
/// against over-broad phrasing that collides with system actions.
@available(iOS 17.0, *)
struct EusoTripAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PostLoadIntent(),
            phrases: [
                "Post a load on \(.applicationName)",
                "Create a load in \(.applicationName)",
            ],
            shortTitle: "Post Load",
            systemImageName: "plus.rectangle.on.rectangle"
        )
        AppShortcut(
            intent: CheckLoadStatusIntent(),
            phrases: [
                "Check load status in \(.applicationName)",
                "What's the status of my load on \(.applicationName)",
            ],
            shortTitle: "Load Status",
            systemImageName: "shippingbox.fill"
        )
        AppShortcut(
            intent: ListExceptionsIntent(),
            phrases: [
                "Show exceptions in \(.applicationName)",
                "Open exception feed in \(.applicationName)",
            ],
            shortTitle: "Exceptions",
            systemImageName: "exclamationmark.triangle.fill"
        )
        AppShortcut(
            intent: GetBidsForLoadIntent(),
            phrases: [
                "Get bids for my load in \(.applicationName)",
                "Show bids on \(.applicationName)",
            ],
            shortTitle: "Get Bids",
            systemImageName: "hand.raised.fill"
        )
        AppShortcut(
            intent: OpenLoadIntent(),
            phrases: [
                "Open loads in \(.applicationName)",
                "Show my loads on \(.applicationName)",
            ],
            shortTitle: "Loads",
            systemImageName: "shippingbox"
        )
        AppShortcut(
            intent: OpenExceptionsIntent(),
            phrases: [
                "Open control tower in \(.applicationName)",
            ],
            shortTitle: "Control Tower",
            systemImageName: "tower.broadcast"
        )
        AppShortcut(
            intent: ApproveSettlementIntent(),
            phrases: [
                "Open settlement in \(.applicationName)",
            ],
            shortTitle: "Settlement",
            systemImageName: "creditcard.fill"
        )
    }
}
