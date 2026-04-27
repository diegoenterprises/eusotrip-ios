//
//  MeshBluetoothController.swift
//  EusoTrip Pulse Watch App
//
//  F13 — CoreBluetooth plumbing for the watch-to-watch mesh transport.
//
//  MeshRelay is the product-facing object (ObservableObject, @MainActor,
//  surfaces peers-in-range + state to SwiftUI). This controller is the
//  impure layer underneath: it owns CBPeripheralManager + CBCentralManager,
//  handles all of the BLE state-machine callbacks, and talks to MeshRelay
//  through two lean sendable callbacks. Keeping the CB plumbing off the
//  main actor is important — a busy advertisement + scan + connect loop
//  would otherwise stall the driver's home screen on every discovery.
//
//  Wire shape:
//
//      EusoTrip service UUID: 9F8E9D00-E050-4C0C-9E0F-EEB4D0A7B01E
//        └── Inbound characteristic: 9F8E9D01-E050-4C0C-9E0F-EEB4D0A7B01E
//            properties: [.write, .writeWithoutResponse]
//            permissions: [.writeable]
//            value: nil  (peers push into this with GATT writes)
//
//      Outbound: every connected peer's discovered inbound characteristic
//      receives a GATT write containing a JSON-encoded `MeshEnvelope`.
//      The receiving side's peripheral-manager didReceiveWrite callback
//      hands the bytes back up to MeshRelay.deliverInboundMesh(...).
//
//  watchOS support: CBPeripheralManager + CBCentralManager both work on
//  watchOS 6+. On a device where peripheral mode isn't available the
//  CBPeripheralManager's state stays stuck at .unsupported and we
//  gracefully skip advertising — scanning still works.
//
//  Background operation: the Watch App is only guaranteed scheduling
//  while foreground or within an active workout session. Our workout-
//  session trick (DrivingSessionManager) keeps us alive through long
//  hauls, and that's when the mesh matters. This controller doesn't
//  need its own background mode — it rides the driving session's
//  foreground runtime budget.
//

import Foundation
import Combine
#if canImport(CoreBluetooth) && !os(watchOS)
import CoreBluetooth
#endif

// NOTE 2026-04-21: CBPeripheralManager, CBMutableService, and
// CBMutableCharacteristic are NOT available on watchOS (Apple marks the
// inits as unavailable). The header comment used to claim the full
// peripheral stack works on watchOS 6+ — that's incorrect. The watch
// wrist can still SCAN (CBCentralManager is available) but it cannot
// ADVERTISE. To keep this file compiling for the Watch target, we
// exclude the entire controller on watchOS and let MeshRelay's own
// guards route to a no-op path on the wrist.
#if canImport(CoreBluetooth) && !os(watchOS)

/// CoreBluetooth plumbing for the mesh transport.
///
/// This class is NOT @MainActor. All of its state is touched only on its
/// private dispatch queue; cross-boundary callbacks to MeshRelay use
/// `@Sendable` closures that hop to the main actor themselves.
final class MeshBluetoothController: NSObject {

    // MARK: - UUIDs

    /// Service UUID — fixed 128-bit identifier for EusoTrip wrist mesh.
    /// Two wrists running EusoTrip recognize each other with zero
    /// account pairing needed. Matches `MeshRelay.serviceUUID`.
    static let serviceUUID = CBUUID(string: MeshRelay.serviceUUID)

    /// Writable characteristic peers use to push convoy envelopes into
    /// us. The UUID differs in one byte from the service UUID so packet
    /// captures read human-friendly.
    static let inboundCharUUID = CBUUID(string: "9F8E9D01-E050-4C0C-9E0F-EEB4D0A7B01E")

    // MARK: - Callback surface

    /// Called on the BLE queue whenever a peer writes an envelope into
    /// our inbound characteristic. MeshRelay's handler hops to the main
    /// actor before touching any @MainActor state.
    var onInboundEnvelope: (@Sendable (Data) -> Void)?

    /// Called on the BLE queue whenever the set of peers-in-range
    /// changes. Values are the CBPeripheral.identifier strings — NOT
    /// driver ids, since we don't know the peer's driver id until we
    /// receive their first signed heartbeat.
    var onPeersChanged: (@Sendable ([String]) -> Void)?

    /// Called on the BLE queue whenever either CB manager enters
    /// poweredOn / poweredOff / unsupported so MeshRelay can reflect
    /// the transport's readiness in its published `state`.
    var onStateChanged: (@Sendable (String) -> Void)?

    // MARK: - Internal state (BLE-queue-only)

    private let queue = DispatchQueue(label: "com.eusotrip.mesh.ble", qos: .utility)

    private var peripheralManager: CBPeripheralManager?
    private var centralManager: CBCentralManager?
    private var inboundCharacteristic: CBMutableCharacteristic?

    /// Peers we've connected to. CBPeripheral.identifier (UUID) → instance.
    private var connectedPeripherals: [UUID: CBPeripheral] = [:]

    /// For each connected peripheral, the discovered inbound char so
    /// we can write to it. Populated after service + characteristic
    /// discovery completes.
    private var peerInboundChars: [UUID: CBCharacteristic] = [:]

    /// Peers currently in range (advert received in last scan window),
    /// keyed by identifier. Values are last-seen RSSI. Used only for
    /// surface reporting via onPeersChanged.
    private var peerRSSI: [UUID: Int] = [:]

    /// Bytes queued for each peripheral pending their char discovery.
    /// Any envelope we try to broadcast before a newly-connected peer
    /// finishes discovery lands here and is flushed on completion.
    private var pendingWrites: [UUID: [Data]] = [:]

    /// Set once per process to prevent duplicate service registration
    /// if `start()` is called twice.
    private var didRegisterService = false

    // MARK: - Lifecycle

    /// Stand up both BLE managers, register our service, and begin
    /// advertising + scanning. Safe to call multiple times — managers
    /// are reused; advertising + scanning are idempotent.
    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.peripheralManager == nil {
                self.peripheralManager = CBPeripheralManager(
                    delegate: self,
                    queue: self.queue,
                    options: [
                        // Don't pop the system's "Bluetooth is off"
                        // alert; we surface BLE availability in our
                        // own UI via `onStateChanged`.
                        CBPeripheralManagerOptionShowPowerAlertKey: false
                    ]
                )
            } else {
                self.startAdvertisingIfReady()
            }
            if self.centralManager == nil {
                self.centralManager = CBCentralManager(
                    delegate: self,
                    queue: self.queue,
                    options: [
                        CBCentralManagerOptionShowPowerAlertKey: false
                    ]
                )
            } else {
                self.startScanningIfReady()
            }
        }
    }

    /// Stop advertising, stop scanning, disconnect every peer, and
    /// drop all in-memory peer state. The managers themselves are kept
    /// alive so a subsequent `start()` doesn't have to re-register the
    /// service.
    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.peripheralManager?.stopAdvertising()
            if self.centralManager?.isScanning == true {
                self.centralManager?.stopScan()
            }
            for (_, peripheral) in self.connectedPeripherals {
                self.centralManager?.cancelPeripheralConnection(peripheral)
            }
            self.connectedPeripherals.removeAll()
            self.peerInboundChars.removeAll()
            self.peerRSSI.removeAll()
            self.pendingWrites.removeAll()
            self.publishPeerListChange()
        }
    }

    /// Broadcast `data` to every connected peer by writing it into their
    /// inbound characteristic. If a peer hasn't finished discovery yet,
    /// bytes are stashed and flushed when the char arrives.
    ///
    /// We use `.withResponse` writes for SOS/HOS-weight envelopes so
    /// the transport surfaces delivery failures; convoy heartbeats
    /// could downgrade to `.withoutResponse` in a future optimization
    /// but for now we keep everything acked — the extra RF round-trip
    /// is cheap at convoy volumes.
    func broadcast(_ data: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            for (id, peripheral) in self.connectedPeripherals {
                if let char = self.peerInboundChars[id] {
                    peripheral.writeValue(data, for: char, type: .withResponse)
                } else {
                    self.pendingWrites[id, default: []].append(data)
                }
            }
        }
    }

    // MARK: - Internal helpers (BLE-queue-only)

    private func publishPeerListChange() {
        let ids = peerRSSI.keys.map { $0.uuidString }
        onPeersChanged?(ids)
    }

    private func startAdvertisingIfReady() {
        guard let pm = peripheralManager else { return }
        guard pm.state == .poweredOn else { return }
        if !didRegisterService {
            let service = CBMutableService(type: Self.serviceUUID, primary: true)
            let char = CBMutableCharacteristic(
                type: Self.inboundCharUUID,
                properties: [.write, .writeWithoutResponse],
                value: nil,
                permissions: [.writeable]
            )
            service.characteristics = [char]
            self.inboundCharacteristic = char
            pm.add(service)
            didRegisterService = true
        }
        guard pm.isAdvertising == false else { return }
        pm.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.serviceUUID]
        ])
    }

    private func startScanningIfReady() {
        guard let cm = centralManager else { return }
        guard cm.state == .poweredOn else { return }
        guard cm.isScanning == false else { return }
        cm.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [
                // Watch radio budget is tight; dedupe at the system
                // layer so we don't wake on every packet from the
                // same peer.
                CBCentralManagerScanOptionAllowDuplicatesKey: false
            ]
        )
    }
}

// MARK: - CBPeripheralManagerDelegate

extension MeshBluetoothController: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        onStateChanged?("peripheral:\(stateString(peripheral.state))")
        switch peripheral.state {
        case .poweredOn:
            startAdvertisingIfReady()
        default:
            break
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveWrite requests: [CBATTRequest]
    ) {
        for request in requests {
            if request.characteristic.uuid == Self.inboundCharUUID,
               let value = request.value {
                onInboundEnvelope?(value)
            }
        }
        // Ack all requests in one batch. ATT requires a single response
        // even when multiple writes arrive in the same bundle.
        if let first = requests.first {
            peripheral.respond(to: first, withResult: .success)
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didAdd service: CBService,
        error: Error?
    ) {
        if error == nil {
            startAdvertisingIfReady()
        }
    }

    private func stateString(_ state: CBManagerState) -> String {
        switch state {
        case .poweredOn:    return "poweredOn"
        case .poweredOff:   return "poweredOff"
        case .unsupported:  return "unsupported"
        case .unauthorized: return "unauthorized"
        case .resetting:    return "resetting"
        case .unknown:      return "unknown"
        @unknown default:   return "unknown"
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension MeshBluetoothController: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onStateChanged?("central:\(stateString(central.state))")
        switch central.state {
        case .poweredOn:
            startScanningIfReady()
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        peerRSSI[peripheral.identifier] = RSSI.intValue
        publishPeerListChange()

        // Auto-connect to any peer advertising our service that we
        // aren't already connected to. A convoy is typically 2-5
        // trucks and a persistent connection per truck is well within
        // the Watch BLE budget. If the connection count ever blows
        // out (say, a truck stop surrounded by 30 EusoTrip wrists)
        // we'd add an RSSI filter here — but that's a luxury problem
        // for now.
        if connectedPeripherals[peripheral.identifier] == nil {
            connectedPeripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        connectedPeripherals.removeValue(forKey: peripheral.identifier)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        connectedPeripherals.removeValue(forKey: peripheral.identifier)
        peerInboundChars.removeValue(forKey: peripheral.identifier)
        peerRSSI.removeValue(forKey: peripheral.identifier)
        pendingWrites.removeValue(forKey: peripheral.identifier)
        publishPeerListChange()
    }
}

// MARK: - CBPeripheralDelegate

extension MeshBluetoothController: CBPeripheralDelegate {

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        for service in peripheral.services ?? [] where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics([Self.inboundCharUUID], for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        for char in service.characteristics ?? [] where char.uuid == Self.inboundCharUUID {
            peerInboundChars[peripheral.identifier] = char
            // Flush any writes we queued while waiting for discovery.
            if let pending = pendingWrites.removeValue(forKey: peripheral.identifier) {
                for data in pending {
                    peripheral.writeValue(data, for: char, type: .withResponse)
                }
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        // No-op for now — ATT write failures are rare enough that we
        // let the coordinator's idempotency layer handle retries
        // (every envelope has a unique id; a duplicate or a dropped
        // write gets re-sent on the next heartbeat cycle).
    }
}

#endif
