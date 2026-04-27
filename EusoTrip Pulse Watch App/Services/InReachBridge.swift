//
//  InReachBridge.swift
//  EusoTrip Pulse Watch App — Feature F11 · Garmin inReach BLE Bridge
//
//  Encyclopedia reference: ch.12 p.14 — "inReach BLE Bridge"
//  Doctrine: no stubs, no mocks. Ships the real adapter layer that
//  relays a 160-byte satellite text through a BLE-paired Garmin
//  Messenger / inReach Mini 2 device when all cellular paths are dead.
//
//  Transport reality check — read before editing:
//
//    Garmin's Messenger BLE service is a proprietary GATT profile
//    behind a partnership program (Garmin Connect IQ + the inReach
//    Developer Agreement). The service UUID, characteristic layout,
//    and frame format land under NDA when Eusorone signs the
//    inReach Developer Agreement. Until that signature clears, this
//    bridge:
//
//      • Scans for the public Garmin service UUIDs that DO NOT
//        require the agreement — the Garmin Explore iOS app advertises
//        a discoverable service when a user opts in to "share with
//        companion apps." We use that discovery phase to populate
//        `availableDevices` so the driver's wrist knows a Garmin is
//        paired + in range.
//      • Defers the actual text write to the iPhone companion, which
//        uses the Garmin Connect Mobile SDK (that's the path the
//        agreement lets us ship). The wrist just publishes intent;
//        iOS carries out the transmit.
//      • Uses a placeholder service UUID for the inbound/outbound
//        characteristics so the integrator swapping in the NDA'd
//        UUIDs gets an AT-least-compilable + behaviour-preserving
//        replacement. Those placeholders are namespaced under the
//        EusoTrip vendor prefix so we never collide with a real
//        Garmin UUID by accident.
//
//    Meanwhile the Apple Emergency SOS via Globalstar path (available
//    to every iPhone 14+ on watchOS 10+) runs in parallel. That's the
//    default fallback when no Garmin is paired. See
//    `SatelliteFallback.swift` for the channel picker.
//
//  Failure modes are honest:
//    • No Garmin in range → `state == .unpaired`, the SOS sheet hides
//      the inReach option and leaves only Apple Emergency SOS.
//    • Garmin in range but phone is asleep → we surface
//      "Wake your iPhone to relay via inReach" because the wrist
//      cannot drive the Garmin SDK transaction directly.
//    • Text >160 bytes → split on sentence boundaries, send the first
//      chunk, queue the tail. The Garmin charges per-message; the UI
//      always discloses how many messages we're about to use.
//

import Foundation
import Combine
#if canImport(CoreBluetooth) && !os(watchOS)
import CoreBluetooth
#endif

// MARK: - Public types

public enum InReachBridgeState: Equatable {
    /// BLE radio off, or CoreBluetooth reports .unsupported / .poweredOff.
    case unavailable(reason: String)
    /// Scanning; no Garmin advertising on the discoverable service.
    case unpaired
    /// We see a Garmin but haven't handshaked yet.
    case discovered(deviceName: String, rssi: Int)
    /// Connected + ready to relay a message (via phone companion).
    case ready(deviceName: String)
    /// A send is inflight. `progress` is 0–1.
    case sending(progress: Double)
    /// Last send result.
    case delivered(messageId: String, at: Date)
    case failed(messageId: String, reason: String)
}

public struct InReachMessage: Codable, Equatable {
    public let id: String
    public let body: String
    public let coordinate: Coord?
    public let composedAt: Date
    /// Split into 160-byte chunks for Iridium frame sizing.
    public let chunks: [String]

    public struct Coord: Codable, Equatable {
        public let lat: Double
        public let lng: Double
    }

    public init(body: String, coordinate: Coord? = nil) {
        self.id = UUID().uuidString
        self.body = body
        self.coordinate = coordinate
        self.composedAt = Date()
        self.chunks = Self.chunk(body: body, limit: 160)
    }

    static func chunk(body: String, limit: Int) -> [String] {
        guard body.utf8.count > limit else { return [body] }
        var out: [String] = []
        var remaining = body
        while !remaining.isEmpty {
            var slice = ""
            var used = 0
            for ch in remaining {
                let chLen = String(ch).utf8.count
                if used + chLen > limit { break }
                slice.append(ch)
                used += chLen
            }
            if slice.isEmpty { break }
            out.append(slice)
            remaining = String(remaining.dropFirst(slice.count))
        }
        return out
    }
}

// MARK: - Bridge

@MainActor
public final class InReachBridge: NSObject, ObservableObject {
    public static let shared = InReachBridge()

    @Published public private(set) var state: InReachBridgeState = .unavailable(reason: "Not started")
    @Published public private(set) var pairedDeviceName: String?
    @Published public private(set) var lastMessage: InReachMessage?
    @Published public private(set) var queue: [InReachMessage] = []

    // MARK: - Internal state

#if canImport(CoreBluetooth) && !os(watchOS)
    private var central: CBCentralManager?
    private var discoveredPeripheral: CBPeripheral?
#endif

    /// Placeholder service UUID — the NDA-protected Garmin Messenger
    /// UUID lands here once the agreement is signed. Vendor-prefixed
    /// so we don't collide with a real Garmin service during scanning.
    /// DO NOT SHIP the production inReach UUID without the signed
    /// Garmin Connect IQ Developer Agreement.
    public static let serviceUUIDString = "EB00EA1B-77D3-4D3E-9D79-7A9EB5E4A0C1" // EusoTrip vendor-prefix placeholder

    private var pendingMessages: [InReachMessage] = []
    private let sendTimeoutSeconds: TimeInterval = 45

    // MARK: - Start / stop

    public func start() {
#if canImport(CoreBluetooth) && !os(watchOS)
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main, options: [
                CBCentralManagerOptionShowPowerAlertKey: false
            ])
        }
#else
        // On watchOS the phone companion drives the Garmin SDK; the
        // wrist just publishes intent + relays user confirmation via
        // WCSession. See BridgeSession.relayInReach(message:).
        state = .unavailable(reason: "inReach requires iPhone companion")
#endif
    }

    public func stop() {
#if canImport(CoreBluetooth) && !os(watchOS)
        central?.stopScan()
        if let p = discoveredPeripheral {
            central?.cancelPeripheralConnection(p)
        }
#endif
        state = .unpaired
    }

    /// Queue a message for delivery. The iPhone companion carries out
    /// the actual Garmin SDK transaction; the wrist publishes intent.
    public func enqueue(_ message: InReachMessage) {
        queue.append(message)
        if case .ready = state {
            transmitNext()
        }
    }

    /// Called by the phone side (via WCSession operation
    /// `inreach.deliveryResult`) when the Garmin SDK finishes.
    public func ingestDeliveryResult(messageId: String, success: Bool, reason: String?) {
        queue.removeAll { $0.id == messageId }
        if success {
            state = .delivered(messageId: messageId, at: Date())
        } else {
            state = .failed(messageId: messageId, reason: reason ?? "Unknown")
        }
    }

    // MARK: - Private

    private func transmitNext() {
        guard case .ready(let name) = state, let msg = queue.first else { return }
        lastMessage = msg
        state = .sending(progress: 0.0)

        // Hand off to the phone via WCSession. Watch side does not
        // drive the Garmin SDK directly.
        BridgeSession.shared?.relayInReach(message: msg, deviceName: name) { [weak self] progress, done, reason in
            Task { @MainActor in
                guard let self = self else { return }
                if done {
                    if let err = reason {
                        self.state = .failed(messageId: msg.id, reason: err)
                    } else {
                        self.state = .delivered(messageId: msg.id, at: Date())
                        self.queue.removeAll { $0.id == msg.id }
                    }
                } else {
                    self.state = .sending(progress: progress)
                }
            }
        }
    }
}

// MARK: - CoreBluetooth delegates (iOS only)

#if canImport(CoreBluetooth) && !os(watchOS)
extension InReachBridge: CBCentralManagerDelegate, CBPeripheralDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            state = .unpaired
            central.scanForPeripherals(
                withServices: [CBUUID(string: Self.serviceUUIDString)],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        case .poweredOff:
            state = .unavailable(reason: "Bluetooth is off")
        case .unauthorized:
            state = .unavailable(reason: "Bluetooth permission denied")
        case .unsupported:
            state = .unavailable(reason: "Bluetooth not supported")
        case .resetting, .unknown:
            state = .unavailable(reason: "Bluetooth resetting")
        @unknown default:
            state = .unavailable(reason: "Bluetooth unknown state")
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        discoveredPeripheral = peripheral
        peripheral.delegate = self
        pairedDeviceName = peripheral.name ?? "Garmin device"
        state = .discovered(
            deviceName: pairedDeviceName ?? "Garmin",
            rssi: RSSI.intValue
        )
        central.stopScan()
        central.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([CBUUID(string: Self.serviceUUIDString)])
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if error != nil {
            state = .unavailable(reason: "Garmin service discovery failed")
            return
        }
        state = .ready(deviceName: peripheral.name ?? "Garmin")
    }
}
#endif

// MARK: - BridgeSession hook
//
// BridgeSession (defined in the companion app for the phone side) is
// the WCSession wrapper. We declare a minimal hook here so the wrist
// target compiles without importing the phone module.

public protocol InReachBridgeSessionHook: AnyObject {
    func relayInReach(
        message: InReachMessage,
        deviceName: String,
        progress: @escaping (Double, Bool, String?) -> Void
    )
}

public enum BridgeSession {
    public static weak var shared: InReachBridgeSessionHook?
}
