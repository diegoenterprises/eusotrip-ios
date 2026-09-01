//
//  695_RailAtInterchangeNotification.swift
//  EusoTrip — Rail Engineer · At-Interchange Consignee Notification.
//
//  TITLE: Notify consignee (at-interchange).
//  PURPOSE: the moment a car reaches the interchange, tell the consignee of
//  record — in their language, with a real ETA — instead of letting them find
//  out when the car hits the ramp.
//
//  Ported from "05 Rail/Light-SVG/695 Rail At-Interchange Notification.svg"
//  (Light + Dark): ✦ eyebrow + mono right register, back/title/ellipsis row,
//  shipment sub-line, three chips, iridescent hairline, gradient-rimmed EVENT
//  hero with the auto-fired badge, "RECIPIENTS · DELIVERY CHANNELS" section with
//  its N-of-M right register, the recipient card, the auto-localized message
//  preview, the three-country band, and the primary/secondary CTA pair.
//
//  ONE DELIBERATE DEPARTURE FROM THE SVG — this is NOT a verbatim port:
//  the SVG draws a THREE-recipient roster ("Consignee · primary", "Site ·
//  unloading", "Customs broker · MX") under a "3 of 4" register. The server
//  addresses exactly ONE — notifyConsigneeAtInterchange reads the single
//  `consigneeId` off the latest waybill (railShipments.ts:2408-2412) and has no
//  multi-recipient path, no site row and no broker row. Drawing three slots
//  would promise a fan-out that cannot happen and a "3 of 4" would be a count
//  of nothing, so the roster is reduced to the one recipient the mutation can
//  actually reach. The N-of-M register is derived from that roster, never from
//  a typed-in denominator. If the server ever grows a recipient list, widen
//  `recipientSlots` and the register follows on its own.
//
//  ARCHETYPE: NOTIFY / COMMIT SURFACE off the interchange spine — a recipient
//  preview, a confirm gate, and a delivery-result ledger. NOT a hero→3-KPI→list
//  board. The user is about to push a real counter-party, so the screen shows
//  WHO is about to be notified, WHAT the server will say, and — after the call —
//  exactly which channels came back and which failed. Nothing is claimed before
//  the send returns.
//
//  ── FIRST INITIATING SURFACE ────────────────────────────────────────────────
//  This screen is `railShipments.notifyConsigneeAtInterchange`'s FIRST
//  initiating surface anywhere in the product. The mutation — the richest
//  fan-out in rail (notification row + push/email + consignee-room socket emit
//  + immutable audit row) — was unreachable code until this file. 695 is what
//  fires it.
//
//  ── WIRING MANIFEST (re-confirmed first-hand this fire) ─────────────────────
//    EXISTS railShipments.ts:2304  (mutation) railShipments.notifyConsigneeAtInterchange
//        in  { shipmentId: number, interchangePointName?: string(max 255),
//              etaText?: string(max 120), country?: "US"|"CA"|"MX" }
//        out TWO shapes, both rendered here:
//          · honest-empty { sent:false, reason:"no_consignee_on_file",
//                           channels:[], consigneeId:null }  ← latest waybill
//                           carries no consigneeId (railShipments.ts:2327)
//          · result       { sent, notificationId, channels, errors:[], consigneeId }
//        NOTE: notificationService sets `sent = channels.length > 0`
//              (notificationService.ts:138), so `sent:false` WITH a consigneeId
//              and errors[] ("type disabled by user" / "quiet hours") is a third
//              real outcome — drawn as its own reached-nobody state.
//    EXISTS railShipments.ts:2434  (query)    railShipments.getInterchangeHandoff
//    EXISTS railShipments.ts:2789  (query)    railShipments.getWaybill
//    EXISTS railShipments.ts:2883  (query)    railShipments.getConsigneePreview
//    EXISTS railShipments.ts:2621  (query)    railShipments.getCrossBorderInterchangePoints
//        → server catalog (crossBorderRail.ts:34) supplying the REAL interchange
//          point name, customs office, roads and spanned countries. This is why
//          `interchangePointName` and `country` are never hardcoded here.
//    EMIT   rail:at_interchange → emitRailAtInterchange(socketService.ts:1082),
//           called at railShipments.ts:2351-2358 with `consigneeId` as an extra
//           target room (socketService.ts:1088 `user:<consigneeId>`).
//           Wire constant WS_EVENTS.RAIL_AT_INTERCHANGE (shared/websocket-events.ts:402).
//           iOS SUBSCRIBER CONFIRMED: Services/RealtimeService.swift:601-606
//           `case "rail:at_interchange", "rail:delivered":` → esangRefreshSurface
//           + eusoNotificationReceived + UnreadMessageStore.refresh() +
//           forwardToWatch. The emit this screen triggers genuinely lands.
//    AUDIT  blockchainAuditTrail eventType "rail.consignee_notified"
//           written at railShipments.ts:2364 with
//           { shipmentId, consigneeId, channels, actorUserId, notifiedAt }.
//
//  METHOD DISCIPLINE: query() = GET, mutation() = POST. The notify verb is a
//  MUTATION and is called with mutation(). There is no server method override —
//  GET-calling it is fault class S4 and kills the CTA silently.
//
//  RBAC: railProcedure + the per-shipment ownership gate
//  `assertOwnsRailShipment(db, ctx, shipmentId)` (railShipments.ts:2319) — only a
//  party to the shipment may notify its consignee, which also blocks
//  cross-tenant consigneeId disclosure. getWaybill / getConsigneePreview apply
//  the same tenant gate via ownsRailShipmentRow and return honest-empty rather
//  than throwing.
//
//  transportMode = rail. COUNTRY IS CONTENT, one screen, never a file fork: the
//  interchange-point catalog carries the real customs office per gateway (US CBP
//  · CA CBSA · MX SAT/Aduanas) and the three-country band picks the language the
//  server will localize into — MX branches to Spanish copy at
//  railShipments.ts:2335, US/CA fall through to English. The band marks which
//  countries the SELECTED gateway actually spans.
//
//  OFFLINE POLICY (Encyclopedia v2): notifying a counter-party has real-world
//  side effects and is NOT in the six-path offline eligibility table
//  (Services/EusoTripAPI.swift:1684).
//    · READ_CACHED(10m) — the recipient preview (shipment number, consignee of
//      record, destination, railcar, car count) is cached per shipment and
//      re-served on a cold, offline launch with a permanently visible
//      monospaced 10pt staleness line that flips to Brand.warning past TTL.
//    · ONLINE_ONLY — the send. The CTA is visibly disabled at 45% with an
//      explicit reason line; the send function refuses up front and records the
//      refusal instead of swallowing the offline error the way 566:622 does.
//      Both degraded states are drawn and visually distinct.
//
//  SIBLING BOUNDARY: 694 (RailInterchangeHandoffScreen) owns the EDI 322 custody
//  board and the acceptInterchange verb. 695 owns only the notify verb off the
//  same spine. No symbol, sheet or verb is duplicated between them.
//
//  NAMED GAPS (proposed TS shapes, nothing stubbed here):
//    1. `notifyConsigneeAtInterchange` builds the MX message as
//       `El envío ferroviario ${n} llegó at ${point}.` — the ` at ${name}` /
//       ` at the interchange` fragment (railShipments.ts:2333) is NOT localized,
//       so Spanish copy ships an English preposition. The preview below mirrors
//       the server byte-for-byte rather than silently fixing it. Proposed:
//         const at = input.interchangePointName
//           ? (country === "MX" ? ` en ${input.interchangePointName}` : ` at ${input.interchangePointName}`)
//           : (country === "MX" ? " en el punto de intercambio" : " at the interchange");
//         const eta = input.etaText
//           ? (country === "MX" ? ` Tiempo estimado de llegada: ${input.etaText}.` : ` ETA to you: ${input.etaText}.`)
//           : "";
//    2. The SVG's second CTA reads "Schedule". No scheduling verb exists on the
//       rail router, so this port ships the slot as a real "Delivery log" rather
//       than a dead button. Proposed:
//         scheduleConsigneeNotification: railProcedure
//           .input(z.object({ shipmentId: z.number(), sendAtISO: z.string().datetime(),
//                             interchangePointName: z.string().max(255).optional(),
//                             etaText: z.string().max(120).optional(),
//                             country: z.enum(["US","CA","MX"]).optional() }))
//           .mutation(...)  // → { scheduled: boolean, jobId: number|null, sendAt: string }
//    3. There is no `listConsigneeNotifications({shipmentId})` read, so the
//       delivery ledger is session-scoped. Proposed:
//         listConsigneeNotifications: railProcedure
//           .input(z.object({ shipmentId: z.number(), limit: z.number().max(50).default(10) }))
//           .query(...)  // → [{ notificationId, channels[], errors[], consigneeId, notifiedAt }]
//           reading blockchainAuditTrail where eventType = "rail.consignee_notified".
//
//  WHY THIS MAKES THE JOB EASIER, IN ONE SENTENCE: the engineer standing at the
//  interchange tells the consignee the car has arrived in two taps, from the
//  same board they just accepted custody on, instead of hunting for a phone
//  number and hoping someone picks up.
//
//  NAV (Rail Engineer): HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//  SHIPMENTS is current because this surface is scoped to one shipmentId, fires
//  off 694's shipment-scoped interchange board, and notifying a counter-party is
//  a shipment-lifecycle action — COMPLIANCE owns customs filings and inspection
//  records, not movement notifications.
//

import SwiftUI

struct RailAtInterchangeNotification_695: View {
    let theme: Theme.Palette
    let shipmentId: Int

    var body: some View {
        Shell(theme: theme) {
            RailAtInterchangeNotificationBody695(shipmentId: shipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Decodable wire shapes (field-for-field, every field Optional but `id`)

/// `railShipments.getWaybill` → destinationYard / originYard sub-object.
private struct NotifyYard695: Decodable {
    let name: String?
    let city: String?
    let state: String?
}

/// `railShipments.getWaybill` (railShipments.ts:2789). Top level is nullable —
/// no db, no row, or a tenant miss all return `null`, which decodes to nil.
/// `id` is the shipment id; everything else is optional.
private struct NotifyWaybill695: Decodable, Identifiable {
    let id: Int
    let shipmentNumber: String?
    let carType: String?
    let numberOfCars: Int?
    let status: String?
    let commodity: String?
    let originRailroad: String?
    let destinationRailroad: String?
    let shipperName: String?
    let consigneeName: String?
    let originYard: NotifyYard695?
    let destinationYard: NotifyYard695?
    let issued: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "shipmentId"
        case shipmentNumber, carType, numberOfCars, status, commodity
        case originRailroad, destinationRailroad, shipperName, consigneeName
        case originYard, destinationYard, issued
    }
}

/// One car on `railShipments.getInterchangeHandoff` (railShipments.ts:2434).
/// 694 owns the custody verbs; 695 reads this board only for the honest car
/// count and road pair that the hero line quotes.
private struct BoardCar695: Decodable, Identifiable {
    let id: Int
    let railcarNumber: String?
    let status: String?
    let deliveringRoad: String?
    let receivingRoad: String?
}

private struct InterchangeBoard695: Decodable {
    let shipmentId: Int?
    let cars: [BoardCar695]?
    let counts: [String: Int]?
}

/// `railShipments.getCrossBorderInterchangePoints` (railShipments.ts:2621) →
/// `RailInterchangePoint` (crossBorderRail.ts:9). This is where the REAL
/// interchange-point name, the customs office (CBP / CBSA / SAT) and the
/// spanned countries come from — none of it is authored on the client.
private struct InterchangePoint695: Decodable, Identifiable {
    let id: String
    let name: String?
    let countryA: String?
    let countryB: String?
    let stateProvinceA: String?
    let stateProvinceB: String?
    let railroadsA: [String]?
    let railroadsB: [String]?
    let interchangeType: String?
    let customsOffice: String?
    let annualVolume: String?
    let hasIntermodal: Bool?
    let hazmatAllowed: Bool?
    let notes: String?
}

/// `railShipments.notifyConsigneeAtInterchange` — decodes BOTH documented
/// return shapes losslessly. `reason` is present only on the honest-empty
/// `no_consignee_on_file` path; `notificationId` only on the result path.
private struct NotifyResult695: Decodable {
    let sent: Bool?
    let reason: String?
    let notificationId: Int?
    let channels: [String]?
    let errors: [String]?
    let consigneeId: Int?
}

// MARK: - Local shapes (not server-decoded)

/// One send attempt made in this session — the delivery-result ledger. There is
/// no server read for past consignee notifications yet (NAMED GAP 3), so this
/// is honestly labelled session-scoped and never presented as history.
private struct NotifySendLog695: Identifiable {
    let id = UUID()
    let at: Date
    let countryCode: String
    let pointName: String?
    let result: NotifyResult695
}

/// The three notification-language regimes the server branches on
/// (railShipments.ts:2332-2337). MX → Spanish; US and CA → English.
private enum NotifyCountry695: String, CaseIterable, Identifiable {
    case us = "US"
    case ca = "CA"
    case mx = "MX"

    var id: String { rawValue }

    /// Language the SERVER will compose in — not a client preference.
    var serverLanguage: String {
        switch self {
        case .mx: return "ES"
        default:  return "EN"
        }
    }

    /// Customs authority naming for the country band. Regime content, not data.
    var authority: String {
        switch self {
        case .us: return "CBP"
        case .ca: return "CBSA"
        case .mx: return "SAT · Aduanas"
        }
    }
}

/// READ_CACHED(10m) envelope for the recipient preview. Persisted per shipment
/// so a cold, offline launch still shows WHO would be notified — with its age
/// on screen — instead of an empty card.
private struct NotifyCacheEnvelope695: Codable {
    let savedAt: Date
    let shipmentNumber: String?
    let consigneeName: String?
    let consigneeEmail: String?
    let destinationName: String?
    let destinationCity: String?
    let destinationState: String?
    let railcarNumber: String?
    let status: String?
    let carCount: Int?
}

private enum NotifyPreviewCache695 {
    /// READ_CACHED(10m). Who the consignee of record is moves slowly; the car's
    /// position does not — ten minutes is the window in which "who am I about to
    /// push" is still trustworthy without a network hit.
    static let ttl: TimeInterval = 10 * 60

    private static func key(_ shipmentId: Int) -> String {
        "eusotrip.rail695.notifyPreview.\(shipmentId)"
    }

    static func save(_ envelope: NotifyCacheEnvelope695, shipmentId: Int) {
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        UserDefaults.standard.set(data, forKey: key(shipmentId))
    }

    static func load(shipmentId: Int) -> NotifyCacheEnvelope695? {
        guard let data = UserDefaults.standard.data(forKey: key(shipmentId)) else { return nil }
        return try? JSONDecoder().decode(NotifyCacheEnvelope695.self, from: data)
    }
}

// MARK: - Body

private struct RailAtInterchangeNotificationBody695: View {
    @Environment(\.palette) private var palette
    /// ONLINE_ONLY gate for the send + the offline serve for the cached preview.
    @ObservedObject private var reach = OfflineReachabilityHub.shared

    let shipmentId: Int

    // Reads
    @State private var waybill: NotifyWaybill695? = nil
    @State private var board: InterchangeBoard695? = nil
    @State private var preview: RailConsigneePreview? = nil
    @State private var points: [InterchangePoint695] = []
    @State private var cached: NotifyCacheEnvelope695? = nil
    @State private var lastSyncedAt: Date? = nil
    @State private var servedFromCache = false
    @State private var loading = true
    @State private var loadError: String? = nil

    // Compose
    @State private var selectedPointId: String? = nil
    @State private var etaText: String = ""
    @State private var country: NotifyCountry695 = .us
    @State private var showPointPicker = false

    // Commit
    @State private var showConfirm = false
    @State private var sending = false
    @State private var sendLog: [NotifySendLog695] = []
    @State private var refusal: String? = nil
    @State private var toast: String? = nil

    // MARK: Derived — every value below resolves to a decoded server field

    private var cars: [BoardCar695] { board?.cars ?? [] }

    private var carCount: Int? {
        if !cars.isEmpty { return cars.count }
        if let n = waybill?.numberOfCars { return n }
        return cached?.carCount
    }

    private var shipmentNumber: String? {
        waybill?.shipmentNumber ?? preview?.shipmentNumber ?? cached?.shipmentNumber
    }

    private var consigneeName: String? {
        let live = preview?.consigneeName ?? waybill?.consigneeName
        if let live, !live.isEmpty { return live }
        if let c = cached?.consigneeName, !c.isEmpty { return c }
        return nil
    }

    private var consigneeEmail: String? {
        if let e = preview?.consigneeEmail, !e.isEmpty { return e }
        if let e = cached?.consigneeEmail, !e.isEmpty { return e }
        return nil
    }

    /// The most recent authoritative server verdict, when one exists.
    private var lastResult: NotifyResult695? { sendLog.first?.result }

    private var serverSaysNoConsignee: Bool {
        lastResult?.reason == "no_consignee_on_file"
    }

    /// The read says the latest waybill resolved no consignee. This is a strong
    /// signal, not proof — `getWaybill` also nulls the name when the users row
    /// is unresolvable — so the CTA stays live and the server gets the last word.
    private var readSaysNoConsignee: Bool {
        !loading && consigneeName == nil
    }

    private var selectedPoint: InterchangePoint695? {
        guard let selectedPointId else { return nil }
        return points.first { $0.id == selectedPointId }
    }

    private var pointName: String {
        (selectedPoint?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEta: String {
        String(etaText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
    }

    private var destinationLabel: String? {
        let city = preview?.destinationCity ?? cached?.destinationCity
        let state = preview?.destinationState ?? cached?.destinationState
        let name = preview?.destinationName ?? waybill?.destinationYard?.name ?? cached?.destinationName
        if let city, let state, !city.isEmpty, !state.isEmpty { return "\(city), \(state)" }
        if let name, !name.isEmpty { return name }
        return nil
    }

    private var roadPair: String? {
        let delivering = cars.compactMap { $0.deliveringRoad }.first ?? waybill?.originRailroad
        let receiving = cars.compactMap { $0.receivingRoad }.first ?? waybill?.destinationRailroad
        guard let delivering, let receiving, !delivering.isEmpty, !receiving.isEmpty else { return nil }
        return "\(delivering) → \(receiving)"
    }

    /// Chip 3 / hero ETA register. The typed ETA wins because that is what the
    /// server will actually put in the message; otherwise the shipment's last
    /// real event timestamp stands in, and failing that we say so.
    private var etaLabel: String {
        if !trimmedEta.isEmpty { return trimmedEta }
        if let eta = preview?.eta, !eta.isEmpty { return shortStamp(eta) }
        if let at = preview?.lastEventAt, !at.isEmpty { return shortStamp(at) }
        return "not set"
    }

    private var statusWord: String {
        let raw = waybill?.status ?? preview?.status ?? cached?.status
        guard let raw, !raw.isEmpty else { return "status pending" }
        return raw.replacingOccurrences(of: "_", with: " ")
    }

    /// The hero badge. Occupies the SVG's "auto-fired" slot but never claims a
    /// send that has not happened.
    private var heroBadge: (String, Color) {
        if sending { return ("sending", Brand.info) }
        if serverSaysNoConsignee { return ("no consignee", Brand.warning) }
        if let r = lastResult {
            if r.sent == true { return ("notified", Brand.success) }
            return ("not delivered", Brand.warning)
        }
        if !reach.isOnline { return ("offline", Brand.warning) }
        if readSaysNoConsignee { return ("no consignee", Brand.warning) }
        return ("ready to send", Brand.success)
    }

    /// The server notifies exactly ONE party — the `consigneeId` carried on the
    /// latest waybill (railShipments.ts:2408-2412). The addressable roster is
    /// therefore a single slot, and BOTH halves of the N-of-M register are read
    /// off that roster rather than typed in as a literal.
    private var recipientSlots: [String?] { [consigneeName] }
    private var recipientTotal: Int { recipientSlots.count }
    private var recipientCount: Int { recipientSlots.compactMap { $0 }.count }

    // MARK: READ_CACHED(10m) staleness

    private var cacheAge: TimeInterval? {
        guard let stamp = lastSyncedAt ?? cached?.savedAt else { return nil }
        return Date().timeIntervalSince(stamp)
    }

    private var cacheIsStale: Bool {
        guard let age = cacheAge else { return true }
        return age > NotifyPreviewCache695.ttl
    }

    private var stalenessLine: String {
        guard let age = cacheAge else { return "no cached preview" }
        let prefix = servedFromCache ? "cached" : "live"
        if age < 60 { return "\(prefix) · just now" }
        if age < 3600 { return "\(prefix) · \(Int(age / 60))m ago" }
        return "\(prefix) · \(Int(age / 3600))h ago"
    }

    // MARK: ONLINE_ONLY gate

    private var canSend: Bool {
        reach.isOnline && !sending && shipmentId > 0
    }

    private var blockedReason: String? {
        if shipmentId <= 0 { return "No shipment in scope — open this from an interchange board." }
        if !reach.isOnline {
            return "Offline · notifying a counter-party is ONLINE_ONLY. It pushes a real person, so it is never queued for silent replay."
        }
        return nil
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header

                if loading && waybill == nil && cached == nil {
                    LifecycleCard {
                        Text("Loading interchange notification…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if shipmentId <= 0 {
                    EusoEmptyState(
                        systemImage: "bell.slash",
                        title: "No shipment in scope",
                        subtitle: "Open this from an interchange handoff board so the consignee, waybill and car count resolve against a real shipment."
                    )
                } else {
                    eventHero
                    composeCard
                    recipientSection
                    messagePreviewCard
                    deliveryLedger
                    countryBand
                    ctaPair
                    if let err = loadError {
                        LifecycleCard(accentDanger: true) {
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                        }
                    }
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
        // The emit this screen fires lands on RealtimeService.swift:601 and
        // re-broadcasts as .esangRefreshSurface — so the board self-heals.
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await load() }
        }
        .overlay(alignment: .bottom) { toastView }
        .sheet(isPresented: $showPointPicker) { pointPickerSheet }
        .sheet(isPresented: $showConfirm) { confirmSheet }
    }

    // MARK: - Header (SVG 72…192)

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                // The single ✦ eyebrow for this screen.
                EusoTripEyebrow(verbatim: "CARRIER · RAIL · NOTIFY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                Spacer(minLength: 8)
                Text("AT-INTERCHANGE")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text("Notify consignee")
                    .font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(subLine)
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                // READ_CACHED(10m) staleness — always visible, warns past TTL.
                Text(stalenessLine)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(cacheIsStale ? Brand.warning : palette.textTertiary)
                    .fixedSize()
                    .accessibilityLabel("Recipient preview \(stalenessLine)")
            }

            chipRow.padding(.top, 2)
            IridescentHairline().padding(.top, 4)
        }
    }

    /// SVG 136 — "<shipment> · <interchange point> · <N> cars", all server-resolved.
    private var subLine: String {
        var parts: [String] = []
        parts.append(shipmentNumber ?? "shipment pending")
        if !pointName.isEmpty { parts.append(pointName) }
        if let n = carCount { parts.append("\(n) car\(n == 1 ? "" : "s")") }
        if let d = destinationLabel, pointName.isEmpty { parts.append(d) }
        return parts.joined(separator: " · ")
    }

    /// SVG 150 — three chips. Every one reads a real field.
    private var chipRow: some View {
        HStack(spacing: 8) {
            chip(statusWord, Brand.info)
            chip(consigneeName == nil ? "no consignee" : "consignee on file",
                 consigneeName == nil ? Brand.warning : palette.textSecondary)
            chip("ETA \(etaLabel)", trimmedEta.isEmpty ? palette.textTertiary : Brand.success)
        }
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy)).tracking(0.3)
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 12).frame(height: 26)
            .background(palette.bgCard)
            .overlay(Capsule().strokeBorder(palette.borderFaint))
            .clipShape(Capsule())
    }

    // MARK: - Event hero (SVG 206…326)

    private var eventHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.info)
                Text("EVENT · At interchange")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.info)
                Spacer(minLength: 8)
                Text(heroBadge.0)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(heroBadge.1)
                    .padding(.horizontal, 10).frame(height: 22)
                    .background(Capsule().fill(heroBadge.1.opacity(0.14)))
            }
            .padding(.bottom, 14)

            Text("Car at interchange")
                .font(.system(size: 22, weight: .heavy)).kerning(-0.3)
                .foregroundStyle(palette.textPrimary)

            Text(heroMetaLine)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            Text("rail:at_interchange → consignee room · rail.consignee_notified audit")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 8)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    /// SVG 98 — "<N> cars · <point> · <roads> · ETA ramp <eta>".
    private var heroMetaLine: String {
        var parts: [String] = []
        if let n = carCount { parts.append("\(n) car\(n == 1 ? "" : "s")") }
        if !pointName.isEmpty { parts.append(pointName) }
        if let roads = roadPair { parts.append(roads) }
        if let office = selectedPoint?.customsOffice, !office.isEmpty { parts.append(office) }
        parts.append("ETA ramp \(etaLabel)")
        return parts.joined(separator: " · ")
    }

    // MARK: - Compose card (the mutation's real inputs)

    private var composeCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("INTERCHANGE POINT · ETA TO CONSIGNEE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)

            Button { showPointPicker = true } label: {
                HStack(spacing: Space.s3) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Brand.info)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(pointName.isEmpty ? "Choose interchange point" : pointName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(pointName.isEmpty ? palette.textSecondary : palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Text(pointSubLine)
                            .font(EType.caption)
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(Space.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(spacing: Space.s3) {
                Image(systemName: "clock")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                TextField("ETA to the consignee, e.g. 19h", text: $etaText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .submitLabel(.done)
                    .onChange(of: etaText) { _, newValue in
                        // Server bound: etaText max 120 (railShipments.ts:2308).
                        if newValue.count > 120 { etaText = String(newValue.prefix(120)) }
                    }
                Text("\(trimmedEta.count)/120")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s3)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

            Text("Both fields are optional. Left blank, the message reads “at the interchange” with no ETA line.")
                .font(.system(size: 10))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var pointSubLine: String {
        guard let p = selectedPoint else {
            return points.isEmpty ? "gateway catalog unavailable" : "\(points.count) gateways on file"
        }
        var parts: [String] = []
        if let office = p.customsOffice, !office.isEmpty { parts.append(office) }
        if let a = p.countryA, let b = p.countryB { parts.append("\(a)–\(b)") }
        if let type = p.interchangeType, !type.isEmpty { parts.append(type) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Recipient section (SVG 342…554)

    private var recipientSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text("RECIPIENT · DELIVERY CHANNELS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 8)
                Text("\(recipientCount) of \(recipientTotal)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textTertiary)
            }
            Rectangle().fill(palette.borderFaint).frame(height: 1)
            recipientCard
        }
    }

    @ViewBuilder
    private var recipientCard: some View {
        if serverSaysNoConsignee || readSaysNoConsignee {
            noConsigneeCard
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text(consigneeName ?? "Consignee")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("Consignee of record · latest waybill")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary)
                if let email = consigneeEmail {
                    Text(email)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                if let railcar = preview?.railcarNumber ?? cached?.railcarNumber, !railcar.isEmpty {
                    Text("Railcar \(railcar)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                }

                channelStrip.padding(.top, 4)

                Text(channelCaption)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    /// The SVG's channel pill strip. Before a send there are NO channels to
    /// claim — the server decides them from the consignee's own preferences —
    /// so the strip renders as unresolved outlines. After a send it renders
    /// exactly what came back in `channels[]`.
    private var channelStrip: some View {
        HStack(spacing: 8) {
            if let delivered = lastResult?.channels, !delivered.isEmpty {
                ForEach(delivered, id: \.self) { channel in
                    channelPill695(channel.uppercased(), delivered: true)
                }
            } else {
                ForEach(["IN APP", "PUSH", "EMAIL"], id: \.self) { channel in
                    channelPill695(channel, delivered: false)
                }
            }
        }
    }

    private func channelPill695(_ label: String, delivered: Bool) -> some View {
        Text(label)
            .font(.system(size: 8.5, weight: .heavy))
            .foregroundStyle(delivered ? Brand.success : palette.textTertiary)
            .frame(minWidth: 52, minHeight: 18)
            .padding(.horizontal, 6)
            .background(Capsule().fill(delivered ? Brand.success.opacity(0.14) : Color.clear))
            .overlay(Capsule().strokeBorder(delivered ? Brand.success.opacity(0.5) : palette.borderFaint))
    }

    private var channelCaption: String {
        if let delivered = lastResult?.channels, !delivered.isEmpty {
            return "Channels returned by the send. Nothing else was attempted."
        }
        return "Channels are decided by the consignee's own notification preferences and returned by the send — nothing is claimed here before it runs. SMS is only attempted at urgent priority; this event sends at high."
    }

    /// THE `no_consignee_on_file` STATE. Not an error — a common, real outcome:
    /// the latest rail_waybills row for this shipment carries no consigneeId, so
    /// there is literally no one to push. Says what is wrong and what fixes it.
    private var noConsigneeCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Brand.warning)
                Text(serverSaysNoConsignee ? "No consignee on file" : "No consignee resolved yet")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
            }
            Text(serverSaysNoConsignee
                 ? "The latest waybill for this shipment was checked and carries no consignee. Nothing was sent and nothing was faked — the notification never left."
                 : "The latest waybill for this shipment resolves no consignee name. The send will refuse with “no consignee on file” until one is on the paper.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Fix it on the waybill: re-issue the AAR Rule 11 waybill with a consignee party. The consignee lives on the waybill alone — a rail shipment carries no consignee of its own, so nothing else on this shipment can supply one.")
                .font(.system(size: 11))
                .foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text("reason: no consignee on file")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Brand.warning)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.warning.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Brand.warning.opacity(0.34)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Message preview (SVG 566…644)

    /// Mirrors `notifyConsigneeAtInterchange`'s own composition byte-for-byte
    /// (railShipments.ts:2333-2337) using the exact inputs this screen will
    /// send. MX branches to Spanish server-side, and so does this preview —
    /// including the un-localized " at <point>" fragment, which is a real
    /// server quirk filed as NAMED GAP 1 rather than quietly corrected here.
    private var messagePreviewCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("MESSAGE PREVIEW · auto-localized")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.info)
                Spacer(minLength: 8)
                Text("\(country.rawValue) · \(country.serverLanguage)")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Brand.info)
            }
            Text(composedTitle)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(composedMessage)
                .font(.system(size: 11))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Composed at send time · load update · high priority")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 2)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.info.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Brand.info.opacity(0.26)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var composedTitle: String {
        country == .mx
            ? "Su vagón llegó al punto de intercambio"
            : "Your rail car has reached the interchange"
    }

    private var composedMessage: String {
        let number = shipmentNumber ?? ""
        let at = pointName.isEmpty ? " at the interchange" : " at \(pointName)"
        let eta = trimmedEta.isEmpty ? "" : " ETA to you: \(trimmedEta)."
        return country == .mx
            ? "El envío ferroviario \(number) llegó\(at).\(eta)"
            : "Rail shipment \(number) arrived\(at).\(eta)"
    }

    // MARK: - Delivery-result ledger

    @ViewBuilder
    private var deliveryLedger: some View {
        if !sendLog.isEmpty {
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(alignment: .firstTextBaseline) {
                    Text("DELIVERY RESULT")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: 8)
                    Text("this session")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                }
                VStack(spacing: Space.s2) {
                    ForEach(sendLog) { entry in ledgerRow(entry) }
                }
            }
        }
    }

    private func ledgerRow(_ entry: NotifySendLog695) -> some View {
        let result = entry.result
        let noConsignee = result.reason == "no_consignee_on_file"
        let delivered = result.sent == true
        let accent: Color = noConsignee ? Brand.warning : (delivered ? Brand.success : Brand.warning)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: noConsignee ? "person.crop.circle.badge.xmark"
                                              : (delivered ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(accent)
                Text(noConsignee ? "No consignee on file"
                                 : (delivered ? "Notified" : "Reached nobody"))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Text(clockStamp(entry.at))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }

            Text(ledgerSubLine(entry))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let channels = result.channels, !channels.isEmpty {
                HStack(spacing: 8) {
                    ForEach(channels, id: \.self) { channel in
                        channelPill695(channel.uppercased(), delivered: true)
                    }
                    Spacer(minLength: 0)
                }
            }

            if let errors = result.errors, !errors.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(errors, id: \.self) { message in
                        Text("· \(message)")
                            .font(.system(size: 10))
                            .foregroundStyle(Brand.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if delivered {
                Text("Emitted rail:at_interchange to the consignee's room · audited as rail.consignee_notified")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(accent.opacity(0.30)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func ledgerSubLine(_ entry: NotifySendLog695) -> String {
        let regime = NotifyCountry695(rawValue: entry.countryCode)
        let language: String = regime?.serverLanguage ?? "EN"
        var parts: [String] = []
        parts.append(entry.countryCode + " · " + language)
        if let name = entry.pointName, !name.isEmpty { parts.append(name) }
        if let id = entry.result.consigneeId { parts.append("consignee #\(id)") }
        if let id = entry.result.notificationId { parts.append("notification #\(id)") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Country band (SVG 760…790)

    /// Picks the language the SERVER will localize into. The marker under each
    /// code says whether the SELECTED gateway actually spans that country, read
    /// straight off the interchange-point catalog.
    private var countryBand: some View {
        HStack(spacing: 8) {
            ForEach(NotifyCountry695.allCases) { regime in
                Button { country = regime } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(regime.rawValue) · \(regime.serverLanguage)")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.3)
                        Text(regime.authority)
                            .font(.system(size: 9, weight: .heavy))
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Text(gatewayMarker(regime))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(country == regime ? Brand.info : palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(country == regime ? Brand.info.opacity(0.12) : palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(country == regime ? Brand.info.opacity(0.45) : palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func gatewayMarker(_ regime: NotifyCountry695) -> String {
        guard let p = selectedPoint else { return "no gateway" }
        if p.countryA == regime.rawValue { return p.stateProvinceA ?? "at gateway" }
        if p.countryB == regime.rawValue { return p.stateProvinceB ?? "at gateway" }
        return "off gateway"
    }

    // MARK: - CTA pair (SVG 798…846)

    private var ctaPair: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                CTAButton(
                    title: "Send notification",
                    action: { showConfirm = true },
                    leadingIcon: "paperplane.fill",
                    isLoading: sending
                )
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.45)

                RailSecondaryActionButton(
                    title: "Delivery log",
                    sheetTitle: "At-interchange notify log",
                    lines: deliveryLogLines,
                    width: 148,
                    systemImage: "list.bullet.rectangle"
                )
            }

            // ONLINE_ONLY refusal — always says WHY, never fails silently.
            if let reason = refusal ?? blockedReason {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Brand.warning)
                    Text(reason)
                        .font(.system(size: 10))
                        .foregroundStyle(Brand.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var deliveryLogLines: [String] {
        var lines: [String] = []
        lines.append("Shipment \(shipmentNumber ?? "pending") · id \(shipmentId)")
        lines.append("Consignee of record · \(consigneeName ?? "none on the latest waybill")")
        if let email = consigneeEmail { lines.append("Contact · \(email)") }
        lines.append("Gateway · \(pointName.isEmpty ? "not selected" : pointName)")
        if let office = selectedPoint?.customsOffice, !office.isEmpty { lines.append("Customs · \(office)") }
        lines.append("Language · \(country.rawValue) · \(country.serverLanguage) (composed at send)")
        lines.append("ETA to consignee · \(trimmedEta.isEmpty ? "not set" : trimmedEta)")
        if sendLog.isEmpty {
            lines.append("No send made from this device in this session.")
        } else {
            for entry in sendLog {
                let channels = (entry.result.channels ?? []).joined(separator: "+")
                let delivered: String = entry.result.sent == true ? "sent" : "not delivered"
                let verdict: String = entry.result.reason ?? delivered
                var line = clockStamp(entry.at) + " · " + verdict
                if !channels.isEmpty { line += " · " + channels }
                lines.append(line)
            }
        }
        lines.append("Every send writes a rail.consignee_notified row to the immutable audit trail.")
        lines.append("No verified notification history is available for this interchange.")
        return lines
    }

    // MARK: - Interchange-point picker sheet

    private var pointPickerSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s2) {
                    Text("Every gateway below comes from EusoTrip's cross-border interchange catalog. Picking one puts that gateway's real name into the notification.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, Space.s2)

                    if points.isEmpty {
                        EusoEmptyState(
                            systemImage: "mappin.slash",
                            title: "Gateway catalog unavailable",
                            subtitle: "The gateway catalog answered with no interchange points. The notification can still send — it reads “at the interchange” with no point name."
                        )
                    } else {
                        ForEach(points) { point in
                            Button {
                                selectedPointId = point.id
                                showPointPicker = false
                            } label: {
                                pointRow(point)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(Space.s4)
            }
            .background(palette.bgPage.ignoresSafeArea())
            .navigationTitle("Interchange point")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showPointPicker = false }
                }
            }
        }
    }

    private func pointRow(_ point: InterchangePoint695) -> some View {
        let selected = point.id == selectedPointId
        let roads = ((point.railroadsA ?? []) + (point.railroadsB ?? [])).joined(separator: " · ")

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(point.name ?? point.id)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if let a = point.countryA, let b = point.countryB {
                    Text("\(a)–\(b)")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Brand.info)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Brand.info.opacity(0.14)))
                }
            }
            if let office = point.customsOffice, !office.isEmpty {
                Text(office)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
            }
            if !roads.isEmpty {
                Text(roads)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            HStack(spacing: 8) {
                if let type = point.interchangeType, !type.isEmpty { pointTag(type) }
                if let volume = point.annualVolume, !volume.isEmpty { pointTag(volume) }
                if point.hasIntermodal == true { pointTag("intermodal") }
                if point.hazmatAllowed == false { pointTag("no hazmat") }
            }
            .padding(.top, 2)
            if let notes = point.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Brand.info.opacity(0.08) : palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(selected ? Brand.info.opacity(0.45) : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func pointTag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(palette.textTertiary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(palette.tintNeutral))
    }

    // MARK: - Confirm gate (this pushes a real counter-party)

    private var confirmSheet: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            HStack(spacing: 6) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("NOTIFY CONSIGNEE · AT INTERCHANGE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }

            Text(consigneeName.map { "Notify \($0)" } ?? "Notify the consignee")
                .font(.system(size: 22, weight: .heavy)).kerning(-0.3)
                .foregroundStyle(palette.textPrimary)

            Text("This pushes a real counter-party. It writes a notification row, sends on whichever channels their preferences allow, emits rail:at_interchange to their own room, and records rail.consignee_notified on the immutable audit trail. It cannot be recalled.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                confirmRow("To", consigneeName ?? "not resolved on the waybill")
                confirmRow("Shipment", shipmentNumber ?? "pending")
                confirmRow("Gateway", pointName.isEmpty ? "the interchange (no point name)" : pointName)
                confirmRow("ETA line", trimmedEta.isEmpty ? "omitted" : trimmedEta)
                confirmRow("Language", "\(country.rawValue) · \(country.serverLanguage)")
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

            if readSaysNoConsignee {
                Text("Heads up: the latest waybill resolves no consignee. This send will come back “no consignee on file” and nothing will be delivered.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await send() }
            } label: {
                HStack {
                    Spacer()
                    if sending {
                        ProgressView().tint(.white)
                    } else {
                        Text("Confirm and notify")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(LinearGradient.diagonal)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(sending || !reach.isOnline)
            .opacity(reach.isOnline ? 1 : 0.45)

            if !reach.isOnline {
                Text("Offline · ONLINE_ONLY. This is never queued for replay — a push that lands hours late is worse than no push.")
                    .font(.system(size: 10))
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(20)
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func confirmRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Toast

    private var toastView: some View {
        Group {
            if let message = toast {
                Text(message)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Brand.success))
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func showToast(_ message: String) {
        withAnimation(.easeOut(duration: 0.18)) { toast = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.easeOut(duration: 0.18)) { toast = nil }
        }
    }

    // MARK: - Formatting

    private func shortStamp(_ iso: String) -> String {
        let out = DateFormatter()
        out.dateFormat = "MMM d · HH:mm"
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: iso) { return out.string(from: date) }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: iso) { return out.string(from: date) }
        return String(iso.prefix(16))
    }

    private func clockStamp(_ date: Date) -> String {
        let out = DateFormatter()
        out.dateFormat = "HH:mm:ss"
        return out.string(from: date)
    }

    // MARK: - Read (READ_CACHED(10m))

    private func load() async {
        loading = true
        loadError = nil

        // Cache-first so the recipient preview is on screen immediately, and
        // survives a cold offline launch. The staleness line stays honest about
        // which of the two the user is looking at.
        if cached == nil { cached = NotifyPreviewCache695.load(shipmentId: shipmentId) }
        if waybill == nil && cached != nil { servedFromCache = true }

        guard shipmentId > 0 else {
            loading = false
            return
        }

        struct ShipmentIn: Encodable { let shipmentId: Int }

        do {
            let doc: NotifyWaybill695? = try await EusoTripAPI.shared.query(
                "railShipments.getWaybill", input: ShipmentIn(shipmentId: shipmentId))
            self.waybill = doc
            self.servedFromCache = false
            self.lastSyncedAt = Date()
        } catch {
            // Degraded, and visibly so: the cached preview stays on screen with
            // its age in the header. We do not blank the card and we do not
            // pretend the read succeeded.
            if cached == nil {
                loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            }
            servedFromCache = cached != nil
        }

        // Board — the custody board this action fires from (694 owns its verbs).
        if let board: InterchangeBoard695 = try? await EusoTripAPI.shared.query(
            "railShipments.getInterchangeHandoff", input: ShipmentIn(shipmentId: shipmentId)) {
            self.board = board
        }

        // Consignee preview — WHO is about to be pushed, before committing.
        if let number = waybill?.shipmentNumber ?? cached?.shipmentNumber, !number.isEmpty {
            self.preview = try? await EusoTripAPI.shared.railShipments
                .getConsigneePreview(shipmentNumber: number)
        }

        // Gateway catalog — the real interchangePointName + customs office.
        // Input is `z.object({country?, railroad?}).optional()`, so the
        // no-input envelope returns the full catalog.
        if points.isEmpty {
            if let catalog: [InterchangePoint695] = try? await EusoTripAPI.shared.queryNoInput(
                "railShipments.getCrossBorderInterchangePoints") {
                self.points = catalog
            }
        }

        persistCache()
        loading = false
    }

    private func persistCache() {
        guard shipmentId > 0, waybill != nil || preview != nil else { return }
        let envelope = NotifyCacheEnvelope695(
            savedAt: Date(),
            shipmentNumber: shipmentNumber,
            consigneeName: consigneeName,
            consigneeEmail: consigneeEmail,
            destinationName: preview?.destinationName ?? waybill?.destinationYard?.name,
            destinationCity: preview?.destinationCity ?? waybill?.destinationYard?.city,
            destinationState: preview?.destinationState ?? waybill?.destinationYard?.state,
            railcarNumber: preview?.railcarNumber,
            status: waybill?.status ?? preview?.status,
            carCount: carCount
        )
        NotifyPreviewCache695.save(envelope, shipmentId: shipmentId)
        cached = envelope
    }

    // MARK: - Commit (ONLINE_ONLY · MUTATION, never query())

    private func send() async {
        refusal = nil

        // ONLINE_ONLY, enforced and not merely declared. Notifying a
        // counter-party is absent from the six-path offline eligibility table
        // (EusoTripAPI.swift:1684) by design — it is a real-world side effect,
        // so it refuses loudly rather than queueing or being swallowed.
        guard reach.isOnline else {
            refusal = "Offline · the notification was NOT sent and NOT queued. Reconnect and send again."
            showConfirm = false
            return
        }
        guard shipmentId > 0 else {
            refusal = "No shipment in scope — nothing to notify against."
            showConfirm = false
            return
        }

        struct NotifyIn: Encodable {
            let shipmentId: Int
            let interchangePointName: String?
            let etaText: String?
            let country: String?
        }

        let name = pointName.isEmpty ? nil : String(pointName.prefix(255))
        let eta = trimmedEta.isEmpty ? nil : trimmedEta
        let input = NotifyIn(shipmentId: shipmentId,
                             interchangePointName: name,
                             etaText: eta,
                             country: country.rawValue)

        sending = true
        do {
            // MUTATION → POST. This verb is `.mutation` at railShipments.ts:2314;
            // calling it through query() would issue a GET, and the server has no
            // method override — that is the S4 class that killed three rail CTAs.
            let result: NotifyResult695 = try await EusoTripAPI.shared.mutation(
                "railShipments.notifyConsigneeAtInterchange", input: input)

            let entry = NotifySendLog695(at: Date(),
                                         countryCode: country.rawValue,
                                         pointName: name,
                                         result: result)
            sendLog.insert(entry, at: 0)
            showConfirm = false

            if result.reason == "no_consignee_on_file" {
                showToast("No consignee on file — nothing sent")
            } else if result.sent == true {
                let channels = (result.channels ?? []).joined(separator: " + ")
                showToast(channels.isEmpty ? "Consignee notified" : "Notified via \(channels)")
            } else {
                showToast("Reached nobody — see the delivery result")
            }

            await load()
        } catch {
            // Surfaced, never silent. 566:622 swallowed its failure; this does not.
            refusal = (error as? EusoTripAPIError)?.errorDescription
                ?? "Send failed — \(error.localizedDescription)"
            showConfirm = false
        }
        sending = false
    }
}

#Preview("695 · Rail At-Interchange Notification · Night") {
    RailAtInterchangeNotification_695(theme: Theme.dark, shipmentId: 0)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("695 · Rail At-Interchange Notification · Light") {
    RailAtInterchangeNotification_695(theme: Theme.light, shipmentId: 0)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
