//
//  BrokerNavController.swift
//  EusoTrip 2027 UI — broker-mode bottom-nav router.
//
//  Mirror of `ShipperNavController` / `CarrierNavController` for the
//  BROKER role. The canonical broker bottom-nav (sourced from
//  401_BrokerTenders.swift / 402_BrokerTenderDetail.swift) is:
//
//      Home (house) · Loads (shippingbox.fill) | Carriers (person.3.fill) · Me (person)
//
//  Slot routing strategy mirrors the Shipper + Carrier stacks: the
//  surface in `RoleSurfaceRouter` injects this handler; tap dispatches
//  through `BrokerNavDispatcher.handle(_:)` which posts an
//  `eusoBrokerNavSwap` notification; the surface listens and swaps
//  the rendered `ScreenRegistry` entry by id. RBAC is enforced
//  surface-side via `RoleAccess.canRender`.
//

import SwiftUI
import Combine

struct BrokerNavHandlerKey: EnvironmentKey {
    static let defaultValue: ((String) -> Void)? = nil
}

extension EnvironmentValues {
    var brokerNavHandler: ((String) -> Void)? {
        get { self[BrokerNavHandlerKey.self] }
        set { self[BrokerNavHandlerKey.self] = newValue }
    }
}

extension Notification.Name {
    static let eusoBrokerNavSwap     = Notification.Name("eusoBrokerNavSwap")
    static let eusoBrokereSangTapped = Notification.Name("eusoBrokereSangTapped")
}

enum BrokerNavTab {
    case home, tenders, carriers, me, none
}

/// Slot-label → screen-id map. `Loads` resolves to the canonical
/// Tenders board (401); `Carriers` resolves to 402 Tender Detail's
/// sibling Carrier Vet board (402b) which lists vetted carriers; `Me`
/// resolves to the dedicated 404B Broker Me hub.
enum BrokerNavRoute {
    enum Destination: String {
        case home = "400"
        case tenders = "401"
        case carriers = "402b"
        case me = "404B"
    }

    private static let map: [String: Destination] = [
        "home": .home,
        "loads": .tenders,
        "carriers": .carriers,
        "me": .me,
        // 2026-06-09 alias sweep (audit M23): the 2nd broker slot is
        // LABELED "Tenders" on all 3 broker chrome screens but the map
        // only keyed "loads" — the slot was a silent no-op since the
        // 2026-05-30 IA recon flagged it. Both labels resolve to the
        // canonical Tenders board 401 (a BrokerSurface tabRoot, so the
        // tap performs a proper tab reset).
        "tenders": .tenders,
    ]

    private static let orbLabels: Set<String> = ["esang", "orb"]

    static func screenId(for label: String) -> String? {
        map[normalize(label)]?.rawValue
    }

    static func isOrb(_ label: String) -> Bool {
        orbLabels.contains(normalize(label))
    }

    private static func normalize(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func leading(current: BrokerNavTab = .none) -> [NavSlot] {
        [NavSlot(label: "Home", systemImage: "house", isCurrent: current == .home),
         NavSlot(label: "Tenders", systemImage: "shippingbox.fill", isCurrent: current == .tenders)]
    }

    static func trailing(current: BrokerNavTab = .none) -> [NavSlot] {
        [NavSlot(label: "Carriers", systemImage: "person.3.fill", isCurrent: current == .carriers),
         NavSlot(label: "Me", systemImage: "person", isCurrent: current == .me)]
    }
}

/// Lightweight bridge for catalystId / loadId payloads on
/// `.eusoBrokerNavSwap`. Broker drill-down screens (403 Tender to
/// Carrier, 407 Catalyst Vetting Details, etc.) read from here
/// instead of taking the ID via init — the ScreenRegistry factory
/// signature is `(palette) -> AnyView` with no slot for extra args.
/// Updated by `BrokerSurface` on each navSwap that carries the
/// payload (2026-05-21).
@MainActor
enum BrokerNavContext {
    static var latestCatalystId: String = "0"
    static var latestLoadId: String = "0"
    static var latestLoadNumber: String = "0"
    static var latestDriverId: String = "0"
    static var latestShipperId: String = "0"
    static var latestVehicleId: String = "0"
}

@MainActor
enum BrokerNavDispatcher {
    static func handle(_ label: String) {
        if BrokerNavRoute.isOrb(label) {
            NotificationCenter.default.post(
                name: .eusoBrokereSangTapped,
                object: nil
            )
            return
        }

        guard let screenId = BrokerNavRoute.screenId(for: label) else { return }
        NotificationCenter.default.post(
            name: .eusoBrokerNavSwap,
            object: nil,
            userInfo: ["screenId": screenId]
        )
    }
}
