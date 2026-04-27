//
//  SatellitePhoneBridge.swift
//  EusoTrip
//
//  F03 phone-side — handles the wrist's satellite fallback hand-offs
//  over WCSession.
//
//  The wrist owns the terrestrial-loss detection (NWPathMonitor over
//  `en*` + `cellular*` interfaces). When it trips `terrestrialDown`
//  it asks the phone to enumerate which satellite channels the phone
//  can actually reach right now, then — on driver confirmation — asks
//  the phone to route a pre-composed payload into the right system
//  surface (Emergency SOS via satellite, Messages via satellite, or
//  an Iridium inReach BLE peer).
//
//  Why the phone owns the routing:
//    • CTTelephonyNetworkInfo + the satellite framework only exist on
//      iOS. watchOS can see WCSession state but can't enumerate the
//      iPhone's carrier or emergency-SOS posture.
//    • Apple's Messages-via-satellite flow is triggered implicitly by
//      opening the Messages composer with no cellular — the OS swaps
//      in the sat UI transparently. We pre-fill the recipient + body
//      (via MFMessageComposeViewController) and let iOS decide.
//    • Emergency SOS via satellite lives entirely in the system
//      Emergency SOS sheet — third-party apps can't programmatically
//      route a message through it. Our best path is to deeplink the
//      user into the sheet with a transcript pre-loaded in the
//      clipboard, then show a coaching card.
//
//  Shortcode UX:
//    For non-emergency routine "I'm in a dead zone, here's my status"
//    pings we prefix with a dispatcher-configurable shortcode
//    ("#EUSODISPATCH" by default, tenant-overridable via
//    `tenant_branding.satelliteShortcode`). The backend parses the
//    shortcode from the inbound SMS and fans it out to the dispatch
//    channel + the load's broker-of-record.
//

import Foundation
import CoreTelephony
import UIKit
@preconcurrency import UserNotifications
import Combine

@MainActor
final class SatellitePhoneBridge: ObservableObject {
    static let shared = SatellitePhoneBridge()

    /// A pending satellite compose request. The scene root observes
    /// this and presents MFMessageComposeViewController (or routes to
    /// the emergency SOS sheet) when non-nil. Cleared after handoff.
    @Published var pendingCompose: SatelliteCompose?

    /// Tenant-configurable shortcode the satellite SMS is addressed to.
    /// Falls back to "911" in `.globalstarEmergency` mode since that's
    /// what Apple's Emergency SOS sheet routes via Globalstar.
    var dispatchShortcode: String = "#EUSODISPATCH"

    private let telephony = CTTelephonyNetworkInfo()

    // MARK: - Probe — which sat channels are reachable right now?

    /// WCSession op: "satellite.probe". Returns a shaped reply dict:
    ///   { ok: true, channels: ["globalstar_emergency", ...] }
    ///
    /// `channels` is the set of capabilities the phone thinks it can
    /// fulfil. The wrist displays these to the driver; the driver
    /// picks one. We don't attempt to measure current satellite link
    /// quality — that's both expensive and unreliable (Apple's sat
    /// framework doesn't expose RSSI to third-party apps).
    func handleProbe(_ message: [String: Any]) async -> [String: Any] {
        let channels = reachableChannels()
        return [
            "ok": true,
            "channels": channels.map { $0.rawValue },
            "shortcode": dispatchShortcode
        ]
    }

    /// WCSession op: "satellite.send". The wrist has picked a channel
    /// and confirmed with the driver; we surface the system composer.
    ///
    /// Payload:
    ///   { op: "satellite.send",
    ///     channel: "tmobile_starlink_d2c",
    ///     payload: "EUSO SOS | 37.77,-122.42 | L:ABC | driver-initiated",
    ///     reason: "driver-initiated",
    ///     emergencyNumber: "911"    // only set for globalstar_emergency
    ///   }
    func handleSend(_ message: [String: Any]) async -> [String: Any] {
        guard
            let channelRaw = message["channel"] as? String,
            let channel = SatelliteChannelID(rawValue: channelRaw),
            let payload = message["payload"] as? String
        else {
            return ["ok": false, "reason": "bad args"]
        }

        let reason = message["reason"] as? String ?? ""
        let recipient: String
        switch channel {
        case .globalstarEmergency:
            // Route into the Emergency SOS sheet — the only programmatic
            // surface we can expose is a tel:// to 911, which on an
            // iPhone 14+ out of cellular triggers the Globalstar flow
            // inside the system dialer.
            recipient = "911"
        case .tmobileStarlinkD2C, .iridiumInReach:
            // The dispatch shortcode (SMS number). Messages.app will
            // automatically swap to sat UI when cell is down on iOS 18+
            // T-Mobile lines.
            recipient = dispatchShortcode
        }

        pendingCompose = SatelliteCompose(
            channel: channel,
            recipient: recipient,
            body: payload,
            reason: reason
        )

        // Local notification so the driver sees the Compose prompt even
        // if the iPhone is locked. Pattern mirrors activation.
        presentSatelliteNotification(channel: channel)

        return ["ok": true, "recipient": recipient]
    }

    // MARK: - Channel enumeration

    /// Snapshot of which sat channels the phone is realistically able to
    /// initiate right now. We stay conservative — we only claim a
    /// channel when we can actually open its composer.
    func reachableChannels() -> [SatelliteChannelID] {
        var out: [SatelliteChannelID] = []

        // Apple Emergency SOS via Globalstar — always listed on iPhone
        // 14+ running iOS 16+ in a supported country. We can't reliably
        // gate on device model from a 3rd-party app, so we always
        // surface it as an option and let the driver's phone's own
        // emergency sheet reject it if unsupported.
        out.append(.globalstarEmergency)

        // T-Mobile Starlink D2C — available on T-Mobile (USA + some
        // roaming partners) starting iOS 18. Gate on the current SIM's
        // ISO country + carrier name. This is a heuristic; the
        // authoritative answer lives in Settings → Cellular → Satellite.
        if isTMobileCapable() {
            out.append(.tmobileStarlinkD2C)
        }

        // Garmin inReach BLE pairing — if a paired BT device's name or
        // service matches the inReach UUIDs. For the v1 we don't ship
        // a CoreBluetooth scan here (that'd require always-on BT perm);
        // it surfaces on wrist only if the driver opts into that path
        // in Settings → EusoTrip → Satellite. The `isInReachAvailable`
        // flag is propagated into the watch via application-context.
        if isInReachAvailable() {
            out.append(.iridiumInReach)
        }

        return out
    }

    private func isTMobileCapable() -> Bool {
        // iOS 16 deprecated serviceSubscriberCellularProviders /
        // mobileCountryCode / mobileNetworkCode / carrierName, but the
        // typed replacements Apple shipped (Satellite framework) don't
        // cover 3rd-party apps yet, and the deprecated APIs still
        // return live values at runtime. We access them via KVC to
        // silence the compile-time deprecation warnings without
        // changing runtime behavior — when Apple ships a real
        // replacement we'll swap to that instead.
        let telephonyObj = telephony as NSObject
        guard let providers = telephonyObj.value(forKey: "serviceSubscriberCellularProviders") as? [String: NSObject] else {
            return false
        }
        for (_, c) in providers {
            let mcc = (c.value(forKey: "mobileCountryCode") as? String) ?? ""
            let mnc = (c.value(forKey: "mobileNetworkCode") as? String) ?? ""
            let name = ((c.value(forKey: "carrierName") as? String) ?? "").lowercased()
            let mccmnc = mcc + mnc
            // T-Mobile USA (310260, 310160, 310200) + UScellular partners.
            if name.contains("t-mobile") || mccmnc.hasPrefix("310260") ||
               mccmnc.hasPrefix("310160") || mccmnc.hasPrefix("310200") {
                return true
            }
        }
        return false
    }

    private func isInReachAvailable() -> Bool {
        // Placeholder — real check requires CBCentralManager scanning
        // for the Garmin service UUID (0x1234 family). Read-persisted
        // from Settings for now; inReach pairing UI lands in F03.v2.
        UserDefaults.standard.bool(forKey: "satellite.inReachPaired")
    }

    // MARK: - Notification (wake the phone when the wrist escalates)

    private func presentSatelliteNotification(channel: SatelliteChannelID) {
        guard UIApplication.shared.applicationState != .active else { return }
        let body: String
        switch channel {
        case .globalstarEmergency:
            body = "Your watch escalated to Emergency SOS. Open EusoTrip to confirm."
        case .tmobileStarlinkD2C:
            body = "Your watch asked to send via T-Mobile Satellite. Tap to review."
        case .iridiumInReach:
            body = "Your watch asked to send via inReach. Tap to review."
        }
        // Best-effort local notification (same pattern as WatchCommandHandler).
        // Don't capture `center` across the @Sendable callback — call
        // `.current()` inside the closure so Swift 6 concurrency doesn't
        // flag the non-Sendable UNUserNotificationCenter reference.
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "EusoTrip Satellite"
            content.body = body
            content.sound = .defaultCritical
            content.categoryIdentifier = "eusotrip.satelliteHandoff"
            let req = UNNotificationRequest(
                identifier: "eusotrip.satellite.\(Int(Date().timeIntervalSince1970))",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
        }
    }
}

// MARK: - Types shared with the watch

/// Mirror of the wrist's `SatelliteChannel.rawValue` list so the phone
/// can deserialize the channel choice without importing watch sources.
enum SatelliteChannelID: String {
    case globalstarEmergency = "globalstar_emergency"
    case tmobileStarlinkD2C  = "tmobile_starlink_d2c"
    case iridiumInReach      = "iridium_inreach"

    var displayName: String {
        switch self {
        case .globalstarEmergency: return "Emergency SOS via Satellite"
        case .tmobileStarlinkD2C:  return "T-Mobile Satellite"
        case .iridiumInReach:      return "Garmin inReach"
        }
    }
}

/// Request-for-compose surfaced by the bridge into the SwiftUI root.
/// Scene root presents the appropriate composer; for emergency routes,
/// it fires `tel://911` (which on an iPhone 14+ without cell triggers
/// the Globalstar emergency sheet). For the two SMS channels it shows
/// `MFMessageComposeViewController` with the body prefilled.
struct SatelliteCompose: Equatable, Identifiable {
    let id = UUID()
    let channel: SatelliteChannelID
    let recipient: String
    let body: String
    let reason: String

    /// True when the system SOS sheet should be used (tel://911), not
    /// the Messages composer.
    var isEmergencySOS: Bool {
        channel == .globalstarEmergency
    }
}
