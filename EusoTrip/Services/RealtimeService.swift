//
//  RealtimeService.swift
//  EusoTrip — WebSocket-backed realtime channel for live load updates.
//
//  Backend parity: `server/socket/index.ts` (or equivalent) binds a
//  Socket.IO-compatible endpoint at `<origin>/ws`. JWT auth happens via
//  the handshake `auth.token` field. On connect the server auto-joins
//  the socket to:
//      user:<userId>
//      role:<role.lowercased()>
//      company:<companyId>
//
//  This service uses a plain `URLSessionWebSocketTask` and speaks the
//  Socket.IO v4 wire protocol's subset we actually need:
//      40<JSON>           engine-io "message" + socket-io "connect"
//      42<JSON>           server-originated EVENT
//      41                 server disconnect
//      3 / 2              ping/pong
//  Server-to-client EVENTs we translate into NotificationCenter posts so
//  any visible surface can subscribe without knowing about the socket:
//      LOAD_STATE_CHANGED  → `.esangRefreshSurface`    (userInfo = payload)
//      LOAD_POD_SUBMITTED  → `.esangRefreshSurface`
//      DISPATCH_MESSAGE    → `.esangOpenMeDetail` with object = "messages"
//      HOS_WARNING         → `.esangOpenMeDetail` with object = "eld"
//      message:new         → `.eusoMessageReceived`    (userInfo = payload)
//
//  For the messaging surface the caller emits `conversation:join`/`leave`
//  frames via `joinConversation(_:)` / `leaveConversation(_:)` so the
//  Socket.IO server only fans out `message:new` to the rooms we care
//  about.  The iOS client defensively subscribes to `user:<id>`
//  automatically on connect so global fan-out also lands.
//
//  Reconnection is exponential-backoff capped at 30s. The service
//  silently drops when the session logs out (EusoTripApp calls
//  `disconnect()`).
//

import Foundation
import SwiftUI

@MainActor
final class RealtimeService: ObservableObject {

    static let shared = RealtimeService()

    enum Phase: Equatable {
        case idle
        case connecting
        case connected
        case disconnected(reason: String)
    }

    @Published private(set) var phase: Phase = .idle

    private var task: URLSessionWebSocketTask?
    private var retryAttempt: Int = 0
    private var connectTask: Task<Void, Never>?

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.timeoutIntervalForRequest = 30
        return URLSession(configuration: cfg)
    }()

    // MARK: Lifecycle

    func connect() {
        guard connectTask == nil else { return }
        connectTask = Task { [weak self] in
            await self?.runConnectionLoop()
        }
    }

    func disconnect() {
        connectTask?.cancel()
        connectTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        phase = .disconnected(reason: "signed out")
    }

    // MARK: Connection loop — reconnects with exponential backoff.

    private func runConnectionLoop() async {
        while !Task.isCancelled {
            do {
                try await openOnce()
                try await readLoop()
            } catch is CancellationError {
                return
            } catch {
                let reason = error.localizedDescription
                phase = .disconnected(reason: reason)
                #if DEBUG
                print("[Realtime] drop · \(reason)")
                #endif
            }
            // Backoff: 1, 2, 4, 8, 16, 30, 30, ...
            retryAttempt = min(retryAttempt + 1, 6)
            let delay = UInt64(min(30.0, pow(2.0, Double(retryAttempt - 1))) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
        }
    }

    private func openOnce() async throws {
        phase = .connecting
        guard let baseURL = EusoTripAPI.shared.baseURL else {
            throw EusoTripAPIError.notConfigured
        }
        // Swap https → wss, append /ws + polling-upgrade query. The
        // backend accepts the same auth JWT via `?token=` if the cookie
        // isn't present (handy when HTTPCookieStorage is cold).
        var comps = URLComponents()
        comps.scheme = (baseURL.scheme == "https") ? "wss" : "ws"
        comps.host = baseURL.host
        comps.port = baseURL.port
        comps.path = "/ws"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "EIO",       value: "4"),
            URLQueryItem(name: "transport", value: "websocket"),
        ]
        if let token = EusoTripAPI.shared.authToken {
            items.append(URLQueryItem(name: "token", value: token))
        }
        comps.queryItems = items
        guard let url = comps.url else { throw EusoTripAPIError.badURL }

        var req = URLRequest(url: url)
        if let token = EusoTripAPI.shared.authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let ws = session.webSocketTask(with: req)
        task = ws
        ws.resume()

        // Socket.IO v4 handshake: the server sends "0{sid,...}" first,
        // then we emit "40" to register with the default namespace.
        _ = try await ws.receive() // consume engine.io OPEN frame
        try await ws.send(.string("40"))
        phase = .connected
        retryAttempt = 0
        #if DEBUG
        print("[Realtime] connected · \(url.absoluteString)")
        #endif
        // Subscribe to the global marketplace channel so every load a
        // shipper posts on web fans out to this client's load board in
        // real time. Idempotent server-side — safe to send on every
        // reconnect (covers the wake-from-background path where the
        // socket re-handshakes and the prior subscription is gone).
        joinMarketplace()
    }

    private func readLoop() async throws {
        guard let ws = task else { return }
        while !Task.isCancelled {
            let message = try await ws.receive()
            switch message {
            case .string(let s):
                handleFrame(s)
            case .data(let d):
                if let s = String(data: d, encoding: .utf8) { handleFrame(s) }
            @unknown default:
                break
            }
        }
    }

    // MARK: Frame parsing

    private func handleFrame(_ raw: String) {
        // Engine.IO ping → reply with "3".
        if raw == "2" {
            Task { try? await task?.send(.string("3")) }
            return
        }
        // Socket.IO EVENT frames start with "42" — the payload is a
        // JSON array like `["LOAD_STATE_CHANGED", {loadId: 42, ...}]`.
        guard raw.hasPrefix("42") else { return }
        let jsonStr = String(raw.dropFirst(2))
        guard let data = jsonStr.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let event = arr.first as? String
        else { return }
        let payload = arr.count > 1 ? arr[1] : [:]
        dispatch(event: event, payload: payload)
    }

    private func dispatch(event: String, payload: Any) {
        let info: [AnyHashable: Any]
        if let dict = payload as? [String: Any] {
            info = dict
        } else {
            info = ["payload": payload]
        }
        let nc = NotificationCenter.default
        switch event {
        case "LOAD_STATE_CHANGED",
             "LOAD_POD_SUBMITTED",
             "LOAD_ASSIGNED",
             "LOAD_UPDATED",
             "load:status_changed":
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
        case "DISPATCH_MESSAGE":
            nc.post(name: .esangOpenMeDetail, object: "messages", userInfo: info)
        case "HOS_WARNING":
            nc.post(name: .esangOpenMeDetail, object: "eld", userInfo: info)
        case "message:new",
             "MESSAGE_NEW",
             "message_new":
            // Backend emits `message:new` on `conversation:<id>` rooms
            // via Socket.IO. Forward verbatim — the active conversation
            // view appends the message, the inbox bumps the preview +
            // unread count, and UnreadMessageStore re-fetches the total.
            nc.post(name: .eusoMessageReceived, object: nil, userInfo: info)
        case "escort:convoy_envelope",
             "CONVOY_ENVELOPE":
            // F13 — backend fans out signed convoy envelopes here.
            // ConvoyPhoneBridge observes `.eusoConvoyInbound`, pushes
            // the raw signed bytes to the wrist over WCSession with
            // op "convoy.ingest", and the wrist verifies the P-256
            // signature before mutating convoy state. The phone is
            // a pure pass-through — it NEVER decodes or trusts the
            // envelope itself.
            nc.post(name: .eusoConvoyInbound, object: nil, userInfo: info)

        // ─── Inbound user notifications (USER_NOTIFICATIONS channel) ───
        // Backend `emitNotification(userId, payload)` fans these out
        // through `user:<id>` (see server/socket/index.ts emitToUser).
        // The payload is `{ type, title, message, data?, actionUrl? }`.
        // UnreadMessageStore re-fetches the badge total + the whole
        // app reacts via .eusoNotificationReceived (toast layer + Me >
        // Notifications hub auto-prepend).
        case "notification:new",
             "NOTIFICATION_NEW",
             "user:notification":
            nc.post(name: .eusoNotificationReceived, object: nil, userInfo: info)
            UnreadMessageStore.shared.refresh()

        // ─── Inbound profile updates (USER channel) ────────────────
        // Backend `profile.updateProfile` and `profile.updateAvatar`
        // broadcast on `user:<id>` after every write so any other
        // device (web, iPad, Watch) refreshes without a manual reload.
        // Listeners (DriverProfileStore, shipper Me hero) re-fetch
        // via `profile.getMyProfile`.
        case "profile:updated",
             "PROFILE_UPDATED":
            nc.post(name: .eusoProfileUpdated, object: nil, userInfo: info)

        // ─── Dispatcher assignment events (DISPATCH channel) ───
        // The cross-role audit gap #4: a dispatcher hand-assigning a
        // load to me used to land only via push (which can be silenced).
        // Now we mirror it through Socket.IO so the driver app reacts
        // even when push is throttled. Drives both:
        //   • `.eusoLoadAssigned` — for in-app banners + load list
        //     refetch on Eusoboards / My Loads / Home.
        //   • `.esangRefreshSurface` — generic re-poll trigger so any
        //     visible store re-runs its loader without bespoke wiring.
        case "dispatch:assignment_new",
             "DISPATCH_ASSIGNMENT_NEW",
             "load_assigned_by_dispatcher":
            nc.post(name: .eusoLoadAssigned, object: nil, userInfo: info)
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
            UnreadMessageStore.shared.refresh()
        case "dispatch:assignment_changed",
             "DISPATCH_ASSIGNMENT_CHANGED":
            // Reassignment / rescind — drop me out of the load detail
            // if it was the active one, and refresh the queue.
            nc.post(name: .eusoLoadReassigned, object: nil, userInfo: info)
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
        case "dispatch:exception",
             "dispatch:delay_reported",
             "dispatch:reschedule",
             "dispatch:check_call_due":
            // Generic dispatcher escalation — surface as a refresh +
            // notification toast so the driver's surfaces re-poll.
            nc.post(name: .eusoNotificationReceived, object: nil, userInfo: info)
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)

        // ─── Bid lifecycle (LOAD_BIDS + COMPANY channels) ───
        // The web shipper accepts/rejects/awards a driver's bid →
        // server fans out via emitBidReceived / emitBidAwarded. The
        // catalyst's COMPANY room (which iOS auto-joins) carries the
        // award event so the driver sees the win in real time. Without
        // these cases the driver app silently dropped the events and
        // only saw bid changes on next poll, which broke the
        // "if it says X on web it should say X on app" parity rule.
        case "bid:awarded",
             "BID_AWARDED",
             "bid_awarded":
            nc.post(name: .eusoBidAwarded, object: nil, userInfo: info)
            nc.post(name: .eusoNotificationReceived, object: nil, userInfo: info)
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
            UnreadMessageStore.shared.refresh()
            forwardToWatch(event: event, info: info)
        case "bid:received",
             "BID_RECEIVED",
             "bid:declined",
             "BID_DECLINED",
             "bid:withdrawn",
             "BID_WITHDRAWN",
             "bid:expired",
             "BID_EXPIRED",
             "bid:countered",
             "BID_COUNTERED":
            // Generic refresh for any bid status flip — viewing
            // surface (My Bids, Load Detail bid list) re-polls.
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)

        // ─── Marketplace fan-out (MARKETPLACE channel) ───
        // When a shipper posts a new load on web, the backend now
        // broadcasts to this channel (server/routers/loads.ts:create).
        // Drivers are subscribed via `joinMarketplace()` at app launch
        // so a freshly-posted load lands on the load board within a
        // socket-frame round-trip — no polling delay. Payload carries
        // origin/dest/equipment hints so a future client-side filter
        // can suppress out-of-region toasts; for now every event
        // triggers a generic load-board re-poll.
        case "load:created",
             "load:posted",
             "LOAD_CREATED",
             "LOAD_POSTED":
            nc.post(name: .eusoLoadPosted, object: nil, userInfo: info)
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)

        // Driver-initiated transitions echoed back to the shipper /
        // dispatcher web surfaces — also relevant on iOS for the
        // currently-viewed load detail. `load:status_changed` and its
        // ALL-CAPS variant are already handled by the
        // LOAD_STATE_CHANGED branch at the top of this switch — listing
        // them again here triggers Swift's "literal value already
        // handled by previous pattern" diagnostic.
        case "load:bol_signed",
             "load:pod_submitted",
             "load:exception_raised":
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)

        // ─── POD lifecycle ───
        // Shipper just approved or rejected a POD on web / iOS.
        // The driver app needs to refresh 024 / 025 + surface a
        // toast or notification immediately. Backend emits these
        // from `pod.approvePOD` / `pod.rejectPOD` (Phase 81
        // cross-cutting closure of the 8000-scenario parity audit).
        case "pod:approved",
             "POD_APPROVED":
            nc.post(name: .eusoNotificationReceived, object: nil, userInfo: info)
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
            UnreadMessageStore.shared.refresh()
        case "pod:rejected",
             "POD_REJECTED":
            nc.post(name: .eusoNotificationReceived, object: nil, userInfo: info)
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
            UnreadMessageStore.shared.refresh()
            forwardToWatch(event: event, info: info)

        // ─── Dispute lifecycle ───
        // Either party responded to or escalated a dispute. The
        // counterparty's DisputeListView / DisputeDetailView reloads
        // via the generic refresh notification. Fired by
        // `disputes.respond` / `disputes.escalate` server-side.
        case "dispute:responded",
             "DISPUTE_RESPONDED",
             "dispute:escalated",
             "DISPUTE_ESCALATED":
            nc.post(name: .eusoNotificationReceived, object: nil, userInfo: info)
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
            UnreadMessageStore.shared.refresh()

        // ─── ETA + safety + financial fan-outs ───
        case "eta:update":
            // Active-load ETA recomputed (HERE Routing or the dispatcher
            // pushed a manual override). Trigger a generic refresh so
            // route preview + map sheet pick up the new arrival time.
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
        case "safety:incident:new",
             "emergency:alert":
            // Safety / emergency near me — surface in Notifications hub
            // immediately. (Drivers in the same convoy / company room
            // also get the SAFETY_MANAGER fanout through this path.)
            nc.post(name: .eusoNotificationReceived, object: nil, userInfo: info)
        case "financial:payment_received",
             "financial:payment_sent",
             "financial:settlement_approved",
             "financial:settlement_paid":
            // Wallet got debited / credited / settlement approved /
            // settlement paid → re-poll wallet balance + settlements
            // list. Without this the driver only saw status changes
            // on next tab-back refresh, breaking the
            // "if web says paid, app says paid" parity rule.
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
            nc.post(name: .eusoNotificationReceived, object: nil, userInfo: info)
            forwardToWatch(event: event, info: info)
        case "document:expiry:alert":
            nc.post(name: .eusoNotificationReceived, object: nil, userInfo: info)
        case "load:document_uploaded",
             "LOAD_DOCUMENT_UPLOADED",
             "document:uploaded":
            // A document landed in the company vault — driver's own
            // Documents Hub + compliance surface re-poll so the new
            // file is visible immediately on every signed-in client.
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
            forwardToWatch(event: event, info: info)

        // ─── Vehicle / DVIR / notification-read / stop-status ───
        // Round-2 parity sweep: every state change a driver triggers
        // (assign vehicle, submit DVIR, flip stop status, mark
        // notification read) now fans out so the OTHER device sees
        // it immediately. Generic refresh — the affected store
        // re-pulls when it observes `.esangRefreshSurface`.
        case "vehicle:status_changed",
             "VEHICLE_STATUS_CHANGED":
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
        case "safety:dvir_submitted",
             "DVIR_SUBMITTED":
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
            nc.post(name: .eusoNotificationReceived, object: nil, userInfo: info)
        case "notification:read",
             "NOTIFICATION_READ":
            // Cross-device read sync — clear the unread badge on the
            // OTHER signed-in client (iOS reads → web/watch clears,
            // and vice versa). UnreadMessageStore re-fetches the
            // canonical total.
            UnreadMessageStore.shared.refresh()
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)

        // ─── Round-3 parity (agreements / escort jobs / support / safety) ───
        case "agreement:signed",
             "AGREEMENT_SIGNED":
            // Counter-party signed; drop into Me·Agreements re-fetch.
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
            nc.post(name: .eusoNotificationReceived, object: nil, userInfo: info)
            forwardToWatch(event: event, info: info)
        case "escort:job_applied",
             "ESCORT_JOB_APPLIED",
             "escort:job_assigned",
             "ESCORT_JOB_ASSIGNED",
             "escort:job_started",
             "ESCORT_JOB_STARTED",
             "escort:job_completed",
             "ESCORT_JOB_COMPLETED":
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
            forwardToWatch(event: event, info: info)
        case "support:ticket_new",
             "SUPPORT_TICKET_NEW",
             "support:ticket_reply",
             "SUPPORT_TICKET_REPLY",
             "support:ticket_closed",
             "SUPPORT_TICKET_CLOSED":
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
            nc.post(name: .eusoNotificationReceived, object: nil, userInfo: info)
        case "safety:incident_reported",
             "SAFETY_INCIDENT_REPORTED",
             "safety:incident_updated",
             "SAFETY_INCIDENT_UPDATED",
             "safety:incident_closed",
             "SAFETY_INCIDENT_CLOSED":
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
            nc.post(name: .eusoNotificationReceived, object: nil, userInfo: info)
            forwardToWatch(event: event, info: info)

        // ─── Round-4 parity (broker / terminal / compliance / factoring / customer portal) ───
        // Each of these mirrors a state change a counter-party
        // operator makes on web. The owning user surface (broker
        // tendered list, driver Me·Appointments, driver Me·Compliance,
        // wallet, admin portal access list) re-polls so the iPhone +
        // wrist match the web cell within a socket frame. Watch
        // forwarding is reserved for events the wrist actually surfaces
        // (appointment status, training assignment, factoring accept).
        case "broker:tender_matched",
             "BROKER_TENDER_MATCHED",
             "broker:catalyst_vetted",
             "BROKER_CATALYST_VETTED",
             "broker:catalyst_tier_updated",
             "BROKER_CATALYST_TIER_UPDATED":
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
            nc.post(name: .eusoNotificationReceived, object: nil, userInfo: info)
        case "terminal:appointment_new",
             "TERMINAL_APPOINTMENT_NEW",
             "terminal:appointment_status_changed",
             "TERMINAL_APPOINTMENT_STATUS_CHANGED":
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
            nc.post(name: .eusoNotificationReceived, object: nil, userInfo: info)
            forwardToWatch(event: event, info: info)
        case "compliance:document_status_updated",
             "COMPLIANCE_DOCUMENT_STATUS_UPDATED",
             "compliance:violation_resolved",
             "COMPLIANCE_VIOLATION_RESOLVED",
             "compliance:audit_scheduled",
             "COMPLIANCE_AUDIT_SCHEDULED",
             "compliance:background_check_initiated",
             "COMPLIANCE_BACKGROUND_CHECK_INITIATED":
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
            nc.post(name: .eusoNotificationReceived, object: nil, userInfo: info)
        case "compliance:training_assigned",
             "COMPLIANCE_TRAINING_ASSIGNED":
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
            nc.post(name: .eusoNotificationReceived, object: nil, userInfo: info)
            forwardToWatch(event: event, info: info)
        case "factoring:offer_accepted",
             "FACTORING_OFFER_ACCEPTED":
            // Driver-facing wallet surface + Me·Earnings re-pull;
            // wrist mirrors the new advance balance.
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
            nc.post(name: .eusoNotificationReceived, object: nil, userInfo: info)
            forwardToWatch(event: event, info: info)
        case "customer_portal:access_created",
             "CUSTOMER_PORTAL_ACCESS_CREATED",
             "customer_portal:access_revoked",
             "CUSTOMER_PORTAL_ACCESS_REVOKED":
            // Admin / dispatcher only — no watch surface.
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
        case "customs:declaration_generated",
             "CUSTOMS_DECLARATION_GENERATED",
             "customs:carta_porte_created",
             "CUSTOMS_CARTA_PORTE_CREATED",
             "customs:pedimento_created",
             "CUSTOMS_PEDIMENTO_CREATED":
            // Cross-border customs document landed. Driver Me · Documents,
            // shipper-side load detail, and customs-broker portal all
            // re-pull. Forward to wrist because the driver needs to know
            // the paperwork is ready before they hit the port of entry —
            // a missing CFDI or pedimento blocks them at the bridge.
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
            nc.post(name: .eusoNotificationReceived, object: nil, userInfo: info)
            forwardToWatch(event: event, info: info)
        case "customs:broker_assigned",
             "CUSTOMS_BROKER_ASSIGNED":
            // Customs broker now owns clearance for this load. Driver +
            // dispatcher need to know who to call; broker company gets
            // a new clearance task on their portal. Watch mirrors so
            // the wrist can show "Cleared by ACME Brokers" near the POE.
            nc.post(name: .esangRefreshSurface, object: event, userInfo: info)
            nc.post(name: .eusoNotificationReceived, object: nil, userInfo: info)
            forwardToWatch(event: event, info: info)

        case "presence:online", "presence:offline":
            // Debug-only — too chatty to surface.
            #if DEBUG
            print("[Realtime] presence · \(event)")
            #endif
        default:
            #if DEBUG
            print("[Realtime] unhandled event · \(event) · \(info)")
            #endif
        }
    }

    // MARK: Outbound

    /// Join a per-load broadcast room. Dispatch does this automatically
    /// when a load is assigned; manual calls are for screens that want
    /// extra granularity (e.g. convoy detail).
    func joinLoad(_ loadId: Int) {
        let frame = "42[\"load:join\",{\"loadId\":\"\(loadId)\"}]"
        Task { try? await task?.send(.string(frame)) }
    }

    func leaveLoad(_ loadId: Int) {
        let frame = "42[\"load:leave\",{\"loadId\":\"\(loadId)\"}]"
        Task { try? await task?.send(.string(frame)) }
    }

    /// Join a per-conversation broadcast room so `message:new` events
    /// for that thread fan out to this client. The server (`socket/
    /// index.ts` → `sock.on("conversation:join", ...)`) expects either
    /// a raw conversation id or the string form. We send the string
    /// form — matches the room-name convention `conversation:<id>`
    /// the backend uses for the room.join + emitMessage broadcast.
    func joinConversation(_ conversationId: String) {
        let sanitized = conversationId
            .replacingOccurrences(of: "\"", with: "")
        let frame = "42[\"conversation:join\",\"\(sanitized)\"]"
        Task { try? await task?.send(.string(frame)) }
    }

    func leaveConversation(_ conversationId: String) {
        let sanitized = conversationId
            .replacingOccurrences(of: "\"", with: "")
        let frame = "42[\"conversation:leave\",\"\(sanitized)\"]"
        Task { try? await task?.send(.string(frame)) }
    }

    /// Join the global marketplace channel so this client receives every
    /// `load:posted` event the backend fans out (see
    /// `server/routers/loads.ts:create` MARKETPLACE broadcast). Called
    /// once after sign-in so the driver's load board updates in real
    /// time when shippers post new loads on web.
    func joinMarketplace() {
        let frame = "42[\"channel:join\",\"marketplace\"]"
        Task { try? await task?.send(.string(frame)) }
    }

    func leaveMarketplace() {
        let frame = "42[\"channel:leave\",\"marketplace\"]"
        Task { try? await task?.send(.string(frame)) }
    }

    /// Forward a realtime event from iPhone → paired Apple Watch via
    /// WCSession applicationContext. Lets the watch react to bid
    /// awards, settlement payments, document uploads, etc. that
    /// originate on the server's WebSocket fan-out without making the
    /// watch maintain its own socket. The watch's
    /// `WatchConnectivityManager.applyContext` routes the event by
    /// `op` field; we wrap the payload in a stable shape the wrist
    /// can dispatch on.
    private func forwardToWatch(event: String, info: [AnyHashable: Any]) {
        // JSONSerialization can't encode AnyHashable → coerce to
        // [String: Any] first, dropping anything that isn't string-
        // keyed. WCSession's plist-shaped applicationContext is
        // happy with primitives + arrays + dicts.
        var sanitized: [String: Any] = [:]
        for (k, v) in info {
            if let key = k as? String { sanitized[key] = v }
        }
        let payload: [String: Any] = [
            "op": "realtime.event",
            "event": event,
            "info": sanitized,
            "ts": Date().timeIntervalSince1970,
        ]
        // Send via the WatchAuthBridge that already owns WCSession on
        // the iPhone side. Falls back to a no-op when no watch is
        // paired or session isn't activated.
        WatchAuthBridge.shared.relayRealtimeEvent(payload)
    }
}
