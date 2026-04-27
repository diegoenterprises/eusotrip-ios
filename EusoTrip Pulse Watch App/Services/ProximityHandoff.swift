//
//  ProximityHandoff.swift
//  EusoTrip Pulse Watch App
//
//  F16 — Wrist-to-terminal Proximity Handoff over BLE.
//
//  Use cases:
//    • Driver arrives at a yard and the dockhand's iPad pulls up the
//      driver's active load without the driver typing the load number
//      or the dockhand scanning a paper placard.
//    • Dispatcher in a control tower walks up to a driver and taps
//      their own wrist to pick up the driver's load context for a
//      side-by-side conversation.
//    • Two drivers swap a load: the receiving driver's wrist scoops
//      the handoff beacon, the coordinator signs a FleetCRDT mutation
//      promoting them to "active driver of record" on that trailer.
//
//  Why not just WCSession or tRPC?
//    Neither WCSession (wrist ↔ own phone only) nor tRPC (requires
//    network) covers the wrist-to-unpaired-terminal case. BLE does —
//    and the range is naturally proximity-bounded, which is the
//    property we want for a "hand this load to whoever is standing
//    here" gesture.
//
//  Why a separate service UUID from MeshRelay?
//    MeshRelay is always-on (when enabled) and carries convoy traffic.
//    Handoff is on-demand + short-lived + carries a different trust
//    envelope. Sharing a UUID would force every scanner to decide
//    which layer gets a given payload; separate UUIDs keep the two
//    surfaces independent.
//
//  Wire shape:
//
//      Handoff service UUID: 9F8E9D20-E050-4C0C-9E0F-EEB4D0A7B01E
//        └── Context characteristic: 9F8E9D21-E050-4C0C-9E0F-EEB4D0A7B01E
//            properties: [.read]
//            permissions: [.readable]
//            value: JSON-encoded `HandoffPayload`
//
//      Advertising payload (watchOS strips every field except service
//      UUIDs from the adv packet, so the JSON lives in the readable
//      characteristic — peer discovers → connects → reads → decodes).
//
//  Trust envelope:
//    HMAC-SHA256 over `did|dn|lid|ts|exp` with a key derived from the
//    auth token. A legitimate peer carrying the same fleet secret
//    re-derives the key + verifies. A rogue listener that doesn't
//    have the secret still sees the payload but can't trust it.
//    Dispatchers + kiosks provisioned via the iOS companion app
//    receive the shared key through a tRPC call; unprovisioned
//    devices read the payload but show an "unsigned" badge in the UI.
//
//  Battery: advertising draws ~4 mW on the Watch S9 BLE radio. The
//  60s default window keeps any single activation under 300 mJ — a
//  rounding error against the driving session's ~180 mW budget.
//

import Foundation
import Combine
import CryptoKit
#if canImport(CoreBluetooth) && !os(watchOS)
import CoreBluetooth
#endif
#if canImport(WatchKit)
import WatchKit
#endif

/// Serializable payload advertised over BLE. `Codable` so the same
/// struct can be re-used on the iOS receiver side without a shim.
struct HandoffPayload: Codable, Equatable {
    /// Schema version. Bumps when we add fields incompatible with the
    /// v1 parser on a legacy fleet terminal.
    let v: Int
    /// Driver id (from AuthStore.userId).
    let did: String
    /// Driver display name — first-name only so we don't leak the
    /// driver's full name to whatever wrist happens to be scanning
    /// nearby. "Justice" is enough for a dockhand to confirm.
    let dn: String?
    /// Active load displayId ("LD-24421"), nil if the driver is
    /// deadheading.
    let lid: String?
    /// Issued-at timestamp, UNIX seconds.
    let ts: Int
    /// Validity window in seconds. Receiver must compute
    /// `now - ts <= exp` or drop the envelope.
    let exp: Int
    /// Base64 HMAC-SHA256 over `"\(v)|\(did)|\(dn ?? "")|\(lid ?? "")|\(ts)|\(exp)"`.
    let mac: String

    static func signingBytes(
        v: Int, did: String, dn: String?, lid: String?, ts: Int, exp: Int
    ) -> Data {
        let s = "\(v)|\(did)|\(dn ?? "")|\(lid ?? "")|\(ts)|\(exp)"
        return Data(s.utf8)
    }
}

/// Coarse state surface for the view layer.
enum ProximityHandoffState: Equatable {
    case unsupported                   // No BLE radio or not peripheralCapable.
    case idle                          // Ready; no broadcast + no capture pending.
    case broadcasting(expiresAt: Date) // Beacon advertising; auto-stops at `expiresAt`.
    case receiving                     // Actively scanning for inbound handoffs.
    case captured(HandoffPayload, verified: Bool)
    case error(String)
}

@MainActor
final class ProximityHandoff: ObservableObject {
    static let shared = ProximityHandoff()

    @Published private(set) var state: ProximityHandoffState = .idle
    @Published private(set) var lastPayload: HandoffPayload?
    @Published private(set) var lastCapturedAt: Date?

    /// Service + characteristic UUIDs. Exposed to the iOS side via
    /// ProximityHandoffConstants.swift when that file lands on the
    /// phone target; redeclaring the raw strings here avoids a
    /// cross-target import cycle.
    static let serviceUUIDString  = "9F8E9D20-E050-4C0C-9E0F-EEB4D0A7B01E"
    static let contextUUIDString  = "9F8E9D21-E050-4C0C-9E0F-EEB4D0A7B01E"

    #if canImport(CoreBluetooth) && !os(watchOS)
    private var controller: ProximityHandoffController?
    #endif

    /// Timer that auto-stops a broadcast after the configured window.
    /// Nilled when we stop early.
    private var expiryTask: Task<Void, Never>?

    private init() {
        #if canImport(CoreBluetooth) && !os(watchOS)
        self.controller = ProximityHandoffController()
        self.controller?.onInboundPayload = { [weak self] data in
            Task { @MainActor [weak self] in
                self?.ingestInbound(data)
            }
        }
        self.controller?.onStateChanged = { [weak self] str in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // `.unsupported` is the only controller state that
                // demotes the feature; everything else (powering up,
                // powering down, resetting) is transient and the
                // service-layer state machine handles it via the
                // broadcast/capture guards below.
                if str.contains("unsupported") {
                    self.state = .unsupported
                }
            }
        }
        #else
        self.state = .unsupported
        #endif
    }

    // MARK: - Broadcast (sender)

    /// Begin advertising a handoff beacon carrying the current driver +
    /// active load context. HMAC-keyed on the auth token so dispatchers
    /// + kiosks provisioned through the iOS companion can verify the
    /// envelope. No-ops if the feature flag is off, the radio is down,
    /// or the driver isn't signed in.
    func startBroadcast(auth: AuthStore, loads: LoadStore) {
        guard EusoTripConfig.proximityHandoffEnabled else { return }
        #if canImport(CoreBluetooth) && !os(watchOS)
        guard state != .unsupported else { return }
        guard let driverId = auth.userId, let token = auth.token else {
            state = .error("Sign in on the phone first.")
            return
        }

        let now = Int(Date().timeIntervalSince1970)
        let exp = Int(EusoTripConfig.proximityHandoffWindowSeconds)
        let payload = makePayload(
            driverId: driverId,
            driverFirst: auth.firstName,
            loadDisplay: loads.active?.displayId,
            ts: now,
            exp: exp,
            sharedKey: key(from: token)
        )
        lastPayload = payload

        guard let data = encode(payload) else {
            state = .error("Encode failed.")
            return
        }
        controller?.start(advertising: data,
                          service: Self.serviceUUIDString,
                          characteristic: Self.contextUUIDString)

        // Mirror the broadcast up to the iOS companion so the phone
        // can continue the beacon if the wrist's BLE radio goes down
        // mid-handoff. Fire-and-forget; a missed mirror is harmless
        // because the primary advertisement is already live on the
        // wrist.
        WatchConnectivityManager.shared.forwardProximityHandoff(payload)

        let expiresAt = Date().addingTimeInterval(TimeInterval(exp))
        state = .broadcasting(expiresAt: expiresAt)

        // Haptic confirms to the driver that the beacon is live —
        // important because there's no visible radio indicator on
        // watchOS and the driver needs to know when to hold the wrist
        // close to the kiosk.
        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(.start)
        #endif

        // Auto-stop when the window elapses. The receiver task cancels
        // this if `stopBroadcast()` fires early.
        expiryTask?.cancel()
        expiryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(exp) * 1_000_000_000)
            guard let self else { return }
            if case .broadcasting = self.state {
                self.stopBroadcast()
            }
        }
        #endif
    }

    func stopBroadcast() {
        #if canImport(CoreBluetooth) && !os(watchOS)
        controller?.stopAdvertising()
        #endif
        expiryTask?.cancel()
        expiryTask = nil
        if case .broadcasting = state {
            state = .idle
            #if canImport(WatchKit)
            WKInterfaceDevice.current().play(.stop)
            #endif
        }
    }

    // MARK: - Capture (receiver)

    /// Begin scanning for a nearby handoff beacon. Typically used by
    /// dispatchers / kiosks running this app, or by a second driver
    /// picking up a load the first driver is dropping. The scan auto-
    /// stops once a verified payload lands, or after 20s of silence.
    func startCapture() {
        guard EusoTripConfig.proximityHandoffEnabled else { return }
        #if canImport(CoreBluetooth) && !os(watchOS)
        guard state != .unsupported else { return }
        controller?.startScanning(
            service: Self.serviceUUIDString,
            characteristic: Self.contextUUIDString
        )
        state = .receiving

        // Time-boxed scan. A wrist-radio scan burning for minutes
        // would be a noticeable battery hit; 20s is long enough to
        // walk across the truck and short enough that a forgotten
        // session doesn't drain the wrist overnight.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard let self else { return }
            if case .receiving = self.state {
                self.stopCapture()
            }
        }
        #endif
    }

    func stopCapture() {
        #if canImport(CoreBluetooth) && !os(watchOS)
        controller?.stopScanning()
        #endif
        if case .receiving = state {
            state = .idle
        }
    }

    /// Apply an inbound handoff payload. Verifies the HMAC against the
    /// local auth token (fleet secret). Unsigned or mis-signed envelopes
    /// still surface to the UI — but with `verified: false` so the UI
    /// can paint a warning banner.
    private func ingestInbound(_ data: Data) {
        guard let payload = decode(data) else {
            state = .error("Bad handoff payload.")
            return
        }
        applyCapturedPayload(payload)
    }

    /// Apply a payload forwarded over WCSession from the iOS companion
    /// (phone-side capture → wrist-side display). Same verification
    /// path as a direct BLE capture — the phone does NOT get to mark
    /// an envelope verified on the wrist's behalf.
    func ingestRemoteCapture(_ payload: HandoffPayload) {
        applyCapturedPayload(payload)
    }

    private func applyCapturedPayload(_ payload: HandoffPayload) {
        // Expiry check first — a stale beacon that someone replayed
        // from the parking lot shouldn't advance the UI at all.
        let age = Int(Date().timeIntervalSince1970) - payload.ts
        if age < 0 || age > payload.exp + 30 {
            state = .error("Expired handoff.")
            return
        }

        var verified = false
        // Resolve auth off the singleton (we're already on the main
        // actor so `AuthStore.shared` is safe to read).
        if let token = AuthStore.shared?.token {
            let sig = HandoffPayload.signingBytes(
                v: payload.v, did: payload.did, dn: payload.dn,
                lid: payload.lid, ts: payload.ts, exp: payload.exp
            )
            let expected = Self.hmacB64(sig, key: key(from: token))
            verified = (expected == payload.mac)
        }

        lastPayload = payload
        lastCapturedAt = Date()
        state = .captured(payload, verified: verified)

        #if canImport(WatchKit)
        WKInterfaceDevice.current().play(verified ? .success : .notification)
        #endif

        // Stop scanning the moment we have a result — saves radio
        // time and keeps the state machine from racing a late second
        // advertisement into another `.captured` transition.
        stopCapture()

        // Audit: only the verified captures go to the chain. An
        // unverified read is interesting for UI + QA but it's not a
        // chain-of-custody event.
        if EusoTripConfig.blockchainAuditEnabled && verified {
            BlockchainAudit.shared.append(
                kind: .hazmatHandoff,
                payload: [
                    "flow": "proximity",
                    "did": payload.did,
                    "lid": payload.lid ?? "",
                    "age": "\(age)"
                ]
            )
        }
    }

    // MARK: - Payload helpers

    private func makePayload(
        driverId: String,
        driverFirst: String?,
        loadDisplay: String?,
        ts: Int,
        exp: Int,
        sharedKey: SymmetricKey
    ) -> HandoffPayload {
        let bytes = HandoffPayload.signingBytes(
            v: 1, did: driverId, dn: driverFirst, lid: loadDisplay,
            ts: ts, exp: exp
        )
        let mac = Self.hmacB64(bytes, key: sharedKey)
        return HandoffPayload(
            v: 1,
            did: driverId,
            dn: driverFirst,
            lid: loadDisplay,
            ts: ts,
            exp: exp,
            mac: mac
        )
    }

    /// Derive the HMAC key from the auth token. A fleet-wide secret
    /// would ship through the iOS companion for true cross-wrist
    /// trust; until then, drivers signed into the same tenant share
    /// the per-driver key only (still good enough for wrist-to-own-
    /// phone handoff, which is the most common flow).
    private func key(from token: String) -> SymmetricKey {
        let digest = SHA256.hash(data: Data(token.utf8))
        return SymmetricKey(data: Data(digest))
    }

    private static func hmacB64(_ data: Data, key: SymmetricKey) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return Data(mac).base64EncodedString()
    }

    private func encode(_ payload: HandoffPayload) -> Data? {
        let enc = JSONEncoder()
        // Sorted keys keeps the byte layout deterministic so anyone
        // diffing packet captures can read two consecutive beacons
        // without the key order jittering.
        enc.outputFormatting = [.sortedKeys]
        return try? enc.encode(payload)
    }

    private func decode(_ data: Data) -> HandoffPayload? {
        try? JSONDecoder().decode(HandoffPayload.self, from: data)
    }
}

// MARK: - CoreBluetooth controller

#if canImport(CoreBluetooth) && !os(watchOS)

/// Dedicated CB manager pair that only serves the handoff service.
/// Lives off the main actor on its own BLE queue and calls back via
/// `@Sendable` closures that hop to the main actor themselves.
final class ProximityHandoffController: NSObject {

    // MARK: Callback surface
    var onInboundPayload: (@Sendable (Data) -> Void)?
    var onStateChanged: (@Sendable (String) -> Void)?

    // MARK: CB state (BLE-queue-only)
    private let queue = DispatchQueue(label: "com.eusotrip.proximity.ble", qos: .utility)
    private var peripheralManager: CBPeripheralManager?
    private var centralManager: CBCentralManager?
    private var serviceRegistered = false
    private var pendingValue: Data?
    private var mutableChar: CBMutableCharacteristic?
    private var advertiseServiceUUID: CBUUID?
    private var advertiseCharUUID: CBUUID?
    private var scanServiceUUID: CBUUID?
    private var scanCharUUID: CBUUID?
    private var pendingReads: [UUID: CBPeripheral] = [:]

    // MARK: - Advertise side

    func start(advertising data: Data, service: String, characteristic: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.advertiseServiceUUID = CBUUID(string: service)
            self.advertiseCharUUID = CBUUID(string: characteristic)
            self.pendingValue = data
            if self.peripheralManager == nil {
                self.peripheralManager = CBPeripheralManager(
                    delegate: self,
                    queue: self.queue,
                    options: [
                        CBPeripheralManagerOptionShowPowerAlertKey: false
                    ]
                )
            } else {
                self.registerAndAdvertiseIfReady()
            }
        }
    }

    func stopAdvertising() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.peripheralManager?.isAdvertising == true {
                self.peripheralManager?.stopAdvertising()
            }
        }
    }

    private func registerAndAdvertiseIfReady() {
        guard let pm = peripheralManager else { return }
        guard pm.state == .poweredOn else { return }
        guard let serviceUUID = advertiseServiceUUID,
              let charUUID = advertiseCharUUID else { return }
        if !serviceRegistered {
            let service = CBMutableService(type: serviceUUID, primary: true)
            let char = CBMutableCharacteristic(
                type: charUUID,
                properties: [.read],
                value: nil, // dynamic value so we can rotate beacons
                permissions: [.readable]
            )
            service.characteristics = [char]
            self.mutableChar = char
            pm.add(service)
            serviceRegistered = true
        }
        if pm.isAdvertising == false {
            pm.startAdvertising([
                CBAdvertisementDataServiceUUIDsKey: [serviceUUID]
            ])
        }
    }

    // MARK: - Scan side

    func startScanning(service: String, characteristic: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.scanServiceUUID = CBUUID(string: service)
            self.scanCharUUID = CBUUID(string: characteristic)
            if self.centralManager == nil {
                self.centralManager = CBCentralManager(
                    delegate: self,
                    queue: self.queue,
                    options: [
                        CBCentralManagerOptionShowPowerAlertKey: false
                    ]
                )
            } else {
                self.startScanIfReady()
            }
        }
    }

    func stopScanning() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.centralManager?.isScanning == true {
                self.centralManager?.stopScan()
            }
            // Drop any mid-flight reads — the service layer already
            // accepted a result, so we don't want a late second read
            // synthesizing a duplicate capture.
            self.pendingReads.removeAll()
        }
    }

    private func startScanIfReady() {
        guard let cm = centralManager else { return }
        guard cm.state == .poweredOn else { return }
        guard let serviceUUID = scanServiceUUID else { return }
        if cm.isScanning == false {
            cm.scanForPeripherals(
                withServices: [serviceUUID],
                options: [
                    CBCentralManagerScanOptionAllowDuplicatesKey: false
                ]
            )
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

// MARK: - CBPeripheralManagerDelegate

extension ProximityHandoffController: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        onStateChanged?("peripheral:\(stateString(peripheral.state))")
        if peripheral.state == .poweredOn {
            registerAndAdvertiseIfReady()
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didAdd service: CBService,
        error: Error?
    ) {
        if error == nil {
            registerAndAdvertiseIfReady()
        }
    }

    func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveRead request: CBATTRequest
    ) {
        // Serve the current beacon value. `pendingValue` is the JSON
        // bytes ProximityHandoff handed us; if a second broadcast is
        // started before a read arrives, the newer payload overwrites
        // the older one — the reader always sees the most recent
        // context, which is the property we want for handoff.
        guard let value = pendingValue else {
            peripheral.respond(to: request, withResult: .unlikelyError)
            return
        }
        if request.offset > value.count {
            peripheral.respond(to: request, withResult: .invalidOffset)
            return
        }
        request.value = value.subdata(in: request.offset..<value.count)
        peripheral.respond(to: request, withResult: .success)
    }
}

// MARK: - CBCentralManagerDelegate

extension ProximityHandoffController: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onStateChanged?("central:\(stateString(central.state))")
        if central.state == .poweredOn {
            startScanIfReady()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String : Any],
        rssi RSSI: NSNumber
    ) {
        // Only proceed with reasonably close peers. Handoff is a
        // proximity gesture; a -90 dBm hit from across the truck yard
        // is almost certainly a stale beacon we don't want to pick up.
        guard RSSI.intValue > -80 else { return }
        if pendingReads[peripheral.identifier] != nil { return }
        pendingReads[peripheral.identifier] = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        guard let serviceUUID = scanServiceUUID else { return }
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        pendingReads.removeValue(forKey: peripheral.identifier)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        pendingReads.removeValue(forKey: peripheral.identifier)
    }
}

// MARK: - CBPeripheralDelegate (read flow)

extension ProximityHandoffController: CBPeripheralDelegate {

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard let charUUID = scanCharUUID else { return }
        for service in peripheral.services ?? [] where service.uuid == scanServiceUUID {
            peripheral.discoverCharacteristics([charUUID], for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        for char in service.characteristics ?? [] where char.uuid == scanCharUUID {
            peripheral.readValue(for: char)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == scanCharUUID else { return }
        guard let data = characteristic.value, !data.isEmpty else { return }
        onInboundPayload?(data)
        // Disconnect — handoff is a one-shot capture, and holding the
        // connection open wastes the peer's radio budget too.
        if let cm = centralManager {
            cm.cancelPeripheralConnection(peripheral)
        }
    }
}

#endif
