//
//  003_RailLiveTracking.swift
//  EusoTrip — Rail · Shipper · Live Tracking (brick 003).
//
//  PURPOSE (one line): one live board for where this rail block actually is,
//  how fast it is closing on the ramp, and when it trips the ramp geofence —
//  so drayage is pre-staged and the demurrage clock never starts on a surprise
//  arrival.
//
//  Verbatim port of 05 Rail/Light-SVG/003 Rail Live Tracking.svg (Light + Dark).
//
//  ARCHETYPE: MAP/TRACKING. Not a detail card — the SVG draws a live network
//  map hero (route arc, traveled-vs-remaining, origin pin, ramp pin wrapped in a
//  dashed RAMP-FENCE geofence ring, a consist riding the line at the live fix,
//  ETA + speed callout chips, HERE tile attribution), then a live status strip,
//  then an IN-TRANSIT METER arc-clock, then the ESANG arrival plan, then a
//  live-events timeline, then the CTA pair. That composition is mirrored
//  element-for-element below. The Shipper band is the SAME Shipper app — content
//  comes off the rail shipment, the chrome does not fork.
//
//  ── WIRING MANIFEST ─────────────────────────────────────────────────────────
//  Every binding re-opened and re-confirmed on disk this fire in
//  eusoronetechnologiesinc/frontend/server/routers/:
//
//    EXISTS railShipments.ts:412  (query)   railShipments.getRailShipmentDetail
//        in  { id: number }
//        out { ...rail_shipments row, lifecycleStage, waybills[], events[],
//              demurrage[], originYard, destinationYard } | null
//        → lane title, consist line, ETA anchors, ramp identity, per-car list.
//
//    EXISTS railShipments.ts:1275 (query)   railShipments.getRailTracking
//        in  { shipmentId: number }   (z.coerce.number)
//        out { events: rail_shipment_events[], currentLocation: {lat,lng,description}|null }
//        → the live-events timeline + the snapped position node + the scan trail.
//
//    EXISTS railShipments.ts:1786 (query)   railShipments.liveTrackShipment
//        in  { railroad: string, shipmentId: string }
//        out ShipmentTrackingResult | null  (ClassIRailroadService.ts:45)
//        → carrier-feed ETA + the live station/city/state + reportedAt.
//
//    EXISTS liveOperations.latestForAsset (query)
//        in  { mode: "RAIL", reference: { kind: "railcar_number", value } }
//        out tenant/source/licence-authorized observation evidence | empty
//        → the per-car positions sheet (one call per real waybill car).
//
//    EXISTS tracking.ts:440       (query)   tracking.getGeofences
//        in  (none)  out geofence rows (center + radius, company-scoped)
//        → the dashed RAMP-FENCE ring. Resolved through the house helper
//          EusoTripAPI.trackingGeofences.fence(near:_:); no covering row ⇒ NO
//          ring is drawn. Never an invented radius.
//
//  NAMED GAPS (STUB · named-gap — handed on, nothing faked here):
//
//    STUB · named-gap  railShipments.shareRailTrackingLink
//        tracking.shareTrackingLink EXISTS at tracking.ts:582 but it is a
//        MUTATION whose first act is `select ... from loads where
//        loads.loadNumber = input.loadNumber` and it THROWS 'Load not found'
//        when absent. A rail_shipments row has no loads row, so wiring the
//        rail "Share ETA" CTA to it ships a permanently dead button. It is not
//        wired. Proposed rail-native verb:
//            shareRailTrackingLink: railReadProcedure (railShipments.ts:94)
//              .input(z.object({
//                shipmentId: z.number(),
//                expiresIn: z.number().default(24),
//                recipientEmail: z.string().email().optional(),
//                recipientPhone: z.string().min(7).optional(),
//              }))
//              .mutation(): { trackingUrl: string; accessCode: string;
//                             expiresAt: string; smsStatus: string }
//        Until it lands, "Share ETA" shares the REAL decoded ETA line through
//        the system share sheet — a working action over real fields, with no
//        fabricated token URL.
//
//    STUB · named-gap  esangCoach.forScreen for RAIL
//        esangCoach.forScreen EXISTS at esangCoach.ts:264 (query) but its
//        SCREEN_ENUM (esangCoach.ts:112) carries only truck-driver keys and its
//        resolveLoadSummary reads the truck `loads` table — it cannot see a rail
//        shipment. Calling it here would either fail zod or answer about the
//        wrong load. The ARRIVAL PLAN card below is therefore composed on-device
//        from decoded server fields only (ETA · rail_yards.operatingHours ·
//        rail_demurrage.freeTimeHours · status · interchange marks). Proposed:
//            railArrivalPlan: railReadProcedure (railShipments.ts:94)
//              .input(z.object({ shipmentId: z.number() }))
//              .query(): { headline: string; detail: string;
//                          etaIso: string | null; rampWindowMarginMin: number | null;
//                          confidence: 'feed' | 'scheduled' | 'unknown' }
//
//    STUB · named-gap  rail consist / train symbol
//        rail_shipments has no train-symbol column and getRailShipmentDetail
//        does not join train_consists, so the SVG's "· UP-Q-LACHI-21" caption
//        renders from the REAL reporting marks (originRailroad ·
//        destinationRailroad) instead of an invented symbol. Proposed: return
//        `consistNumber` on the detail payload by joining consist_cars →
//        train_consists on the shipment's cars.
//
//  RBAC: railReadProcedure (railShipments.ts:94) — the RAIL-mode gate (ctx role in SHIPPER / ADMIN /
//  SUPER_ADMIN by route) plus the per-row tenant gate `ownsRailShipmentRow`
//  inside both reads: a caller who is not a party to the shipment gets null /
//  an empty feed, and this screen then draws its honest not-visible state.
//  tracking.getGeofences is protectedProcedure, company-scoped.
//
//  transportMode = rail. COUNTRY CONTENT THAT VARIES: rail_yards.country is the
//  US | CA | MX enum and the destination yard drives it. US ramps read against
//  STB/FRA rules and AAR reporting marks; a CA destination (CN / CPKC) reads
//  against Transport Canada and the yard's own local window; an MX destination
//  (FXE / Ferromex) adds the border interchange call to the event chain. Every
//  country-sensitive string on this screen is the decoded yard's own
//  city/state/country/operatingHours — nothing is assumed domestic.
//
//  OFFLINE POLICY (Encyclopedia v2): READ_CACHED(5m) — the tracking board
//  renders instantly from the last decoded snapshot and labels its own age in
//  the header right register with a monospaced 10pt freshness line: "live · Ns"
//  in Brand.success on a fresh online read, "cached · Nm" in textTertiary while
//  inside the 5-minute TTL, and "stale · Nm" in Brand.warning the moment it is
//  past TTL. Cached and stale are VISIBLY different from live — a position is
//  never shown as current when it is not. OFFLINE outranks all three: when
//  OfflineReachabilityHub reports no reachability the register reads
//  "offline · Nm" in Brand.warning, a warning band sits above the board saying
//  the whole screen is a frozen snapshot, and a COLD offline entry (no cached
//  snapshot) says so outright rather than rendering a "couldn't load" that
//  implies the server answered. Stale means old; offline means unrefreshable,
//  and the two are never conflated. This whole surface is read-only: no DB
//  write, nothing to queue, so there is no ONLINE_ONLY commit path — the
//  reachability read exists solely to keep the staleness claim honest.
//
//  LIVE SUPER-INTELLIGENCE FUSION: the map hero, the in-transit meter and the
//  arrival plan are three faces of ONE decoded tick — the same live fix drives
//  the position node, the arc-clock, the remaining distance and the arrival
//  sentence, so they can never disagree. Position comes from the carrier feed
//  (liveTrackShipment) when it answers and falls back to the newest positioned
//  rail_shipment_events scan; the ramp fence is a real company geofence row.
//  When the feed is silent the screen says "scheduled", never a stale value
//  dressed as live.
//
//  HOW THIS MAKES THE RAIL SHIPPER'S JOB EASIER: they can see, in one glance,
//  whether the block will hit the ramp inside its operating window — so they
//  book the dray before the car lands instead of paying demurrage on an arrival
//  nobody was watching.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen root

struct RailLiveTracking_003: View {
    let theme: Theme.Palette
    let shipmentId: Int

    var body: some View {
        Shell(theme: theme) {
            RailLiveTrackingBody003(shipmentId: shipmentId)
        } nav: {
            // SHIPPER band — identical chrome to 002 Rail Shipment Detail so the
            // rail shipper never sees the bar change under them.
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house.fill",       isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person.fill",     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Decoded server shapes
//
// Every field Optional except `id`. Shapes are taken verbatim from the routers
// and the drizzle schema on disk — rail_shipments / rail_yards /
// rail_shipment_events / rail_waybills / rail_demurrage, plus the two external
// tracking result interfaces.

private struct RailGeo003: Decodable, Hashable {
    let lat: Double?
    let lng: Double?
    let description: String?

    /// Only a real WGS-84 fix reaches the map. (0,0) is the platform's
    /// missing-geocode sentinel, never a place.
    var fix: HereLatLng? {
        guard let lat, let lng else { return nil }
        let p = HereLatLng(lat, lng)
        return p.isUsableCoordinate ? p : nil
    }
}

/// rail_yards.operatingHours JSON — the ramp's OWN window, and the only
/// legitimate source for the "inside the ramp window" claim on this screen.
private struct RailYardHours003: Decodable, Hashable {
    let open: String?        // "06:00"
    let close: String?       // "22:00"
    let timezone: String?    // IANA id
}

private struct RailYardNode003: Decodable, Hashable {
    let id: Int?
    let name: String?
    let splcCode: String?
    let city: String?
    let state: String?
    let country: String?          // "US" | "CA" | "MX"
    let yardType: String?         // "intermodal_ramp" | "classification" | ...
    let coordinates: RailGeo003?  // rail_yards.coordinates {lat,lng}
    let hasIntermodal: Bool?
    let operatingHours: RailYardHours003?
    let status: String?
}

private struct RailEventNode003: Decodable, Identifiable, Hashable {
    let id: Int
    let eventType: String?
    let description: String?
    let location: RailGeo003?
    let yardId: Int?
    let railcarId: Int?
    let timestamp: String?
}

private struct RailWaybillNode003: Decodable, Identifiable, Hashable {
    let id: Int
    let waybillNumber: String?
    let railcarNumber: String?
    let commodity: String?
    let originStation: String?
    let destinationStation: String?
}

private struct RailDemurrageNode003: Decodable, Hashable {
    let id: Int
    let status: String?          // "accruing" | "invoiced" | "paid" | ...
    let freeTimeHours: Int?
    let chargeableHours: Int?
    let yardId: Int?
}

private struct RailShipmentDetail003: Decodable {
    let id: Int
    let shipmentNumber: String?
    let carType: String?             // "intermodal" ...
    let numberOfCars: Int?
    let commodity: String?
    let status: String?
    let estimatedTransitDays: Int?
    let actualTransitDays: Int?
    let estimatedArrivalAt: String?  // migration 0328 column — the schedule ETA
    let actualArrivalAt: String?
    let originRailroad: String?      // AAR reporting mark
    let destinationRailroad: String? // interchange mark
    let routeDescription: String?
    let transportMode: String?
    let lifecycleStage: String?
    let originYard: RailYardNode003?
    let destinationYard: RailYardNode003?
    let events: [RailEventNode003]?
    let waybills: [RailWaybillNode003]?
    let demurrage: [RailDemurrageNode003]?
}

private struct RailTrackingFeed003: Decodable {
    let events: [RailEventNode003]?
    let currentLocation: RailGeo003?
}

/// ClassIRailroadService.ShipmentLocation (ClassIRailroadService.ts:34).
private struct ClassILocation003: Decodable, Hashable {
    let latitude: Double?
    let longitude: Double?
    let station: String?
    let city: String?
    let state: String?
    let railroad: String?
    let reportedAt: String?

    var fix: HereLatLng? {
        guard let latitude, let longitude else { return nil }
        let p = HereLatLng(latitude, longitude)
        return p.isUsableCoordinate ? p : nil
    }
}

/// ClassIRailroadService.ShipmentTrackingResult (ClassIRailroadService.ts:45).
private struct ClassITrack003: Decodable {
    let shipmentId: String?
    let railroad: String?
    let status: String?
    let location: ClassILocation003?
    let eta: String?
    let originStation: String?
    let destinationStation: String?
    let equipmentId: String?
    let equipmentType: String?
    let lastUpdate: String?
}

// MARK: - READ_CACHED(5m) snapshot store
//
// The whole decoded tick, kept in memory per shipment so the board paints
// instantly on re-entry and can honestly label its own age. Nothing is
// synthesised here — it is the last real payload, timestamped.

private struct RailTrackSnapshot003 {
    var detail: RailShipmentDetail003?
    var tracking: RailTrackingFeed003?
    var classI: ClassITrack003?
    var rampFence: TrackingGeofencesAPI.ResolvedFence?
}

private final class RailTrackCache003 {
    static let shared = RailTrackCache003()
    /// READ_CACHED(5m) — a tracking fix older than five minutes is labelled
    /// stale, in Brand.warning, and is never presented as live.
    static let ttl: TimeInterval = 5 * 60

    private let lock = NSLock()
    private var store: [Int: (snapshot: RailTrackSnapshot003, at: Date)] = [:]

    func read(_ id: Int) -> (snapshot: RailTrackSnapshot003, at: Date)? {
        lock.lock(); defer { lock.unlock() }
        return store[id]
    }

    func write(_ id: Int, _ snapshot: RailTrackSnapshot003) {
        lock.lock(); defer { lock.unlock() }
        store[id] = (snapshot, Date())
    }
}

// MARK: - Ramp-window fit

private enum RampWindowFit003 {
    case inside(minutes: Int)
    case outside
    case unknown
}

// MARK: - Body

private struct RailLiveTrackingBody003: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// READ_CACHED(5m) needs BOTH halves to be honest: staleness alone can only
    /// say how old the last good read is, never that the device cannot reach the
    /// network at all. This screen is read-only — there is no commit to gate —
    /// so reachability is here purely to make the offline state visibly distinct
    /// from a merely stale one.
    @ObservedObject private var reach = OfflineReachabilityHub.shared
    let shipmentId: Int

    @State private var detail: RailShipmentDetail003? = nil
    @State private var tracking: RailTrackingFeed003? = nil
    @State private var classI: ClassITrack003? = nil
    @State private var rampFence: TrackingGeofencesAPI.ResolvedFence? = nil
    @State private var canonicalRouteLines: [[HereLatLng]] = []
    @State private var canonicalRouteStatus: String? = nil
    @State private var canonicalRouteVersion: Int? = nil
    @StateObject private var nearbyRailStore = LiveOperationsNearbyStore(mode: .rail)

    @State private var loading = true
    @State private var loadError: String? = nil

    /// Per-section degraded flags. The secondary fan-out folds to nil on
    /// failure, which used to be indistinguishable from a genuinely empty
    /// section — a dead live-events feed rendered as "No events yet". These
    /// carry the difference to the surface. That distinction is the offline
    /// honesty law: a failed read must never be dressed as an empty one.
    @State private var trackingDegraded = false
    @State private var classIDegraded = false

    // READ_CACHED(5m) bookkeeping — drives the header freshness register.
    @State private var fetchedAt: Date? = nil
    @State private var servedFromCache = false

    @State private var showPerCar = false
    @State private var nodeBreathing = false

    // MARK: - Live tick (ONE fix; the hero, the meter and the plan all read it)

    /// The live position: the carrier feed when it answers, otherwise the newest
    /// rail_shipment_events scan that carries a real coordinate. Never invented.
    private var liveFix: HereLatLng? {
        classI?.location?.fix ?? tracking?.currentLocation?.fix ?? positionedScans.last?.point
    }

    /// True when the fix came off the Class I carrier feed rather than the
    /// stored scan chain — the difference is surfaced, not smoothed over.
    private var fixIsCarrierFeed: Bool { classI?.location?.fix != nil }

    /// ISO timestamp of the fix currently on screen.
    private var fixReportedAt: String? {
        if fixIsCarrierFeed { return classI?.location?.reportedAt ?? classI?.lastUpdate }
        return positionedScans.last?.stamp ?? latestEvent?.timestamp
    }

    /// Human place for the live fix.
    private var fixPlace: String? {
        if fixIsCarrierFeed {
            let parts = [classI?.location?.station, classI?.location?.city, classI?.location?.state]
                .compactMap { nonEmpty($0) }
            if !parts.isEmpty { return parts.joined(separator: " · ") }
        }
        return nonEmpty(tracking?.currentLocation?.description)
            ?? nonEmpty(latestEvent?.location?.description)
    }

    // MARK: - Event chain

    /// Newest-first event list — tracking feed preferred, detail payload as the
    /// fallback. Sorted locally; server order is never trusted.
    private var events: [RailEventNode003] {
        let raw = (tracking?.events ?? detail?.events ?? [])
        return raw.sorted { ($0.timestamp ?? "") > ($1.timestamp ?? "") }
    }

    private var latestEvent: RailEventNode003? { events.first }

    /// The timeline shows the six most recent calls — the SVG's three-node
    /// strip, extended to the depth the card can hold without scrolling twice.
    private var shownEvents: [RailEventNode003] { Array(events.prefix(6)) }

    /// Every scan that carries a real coordinate, oldest → newest.
    private var positionedScans: [(point: HereLatLng, stamp: String)] {
        events.compactMap { e -> (HereLatLng, String)? in
            guard let p = e.location?.fix else { return nil }
            return (p, e.timestamp ?? "")
        }
        .sorted { $0.1 < $1.1 }
        .map { (point: $0.0, stamp: $0.1) }
    }

    private var originFix: HereLatLng? { detail?.originYard?.coordinates?.fix }
    private var destFix: HereLatLng? { detail?.destinationYard?.coordinates?.fix }

    /// Traveled geometry: origin yard → every positioned scan → the live fix.
    private var traveledPolyline: [HereLatLng] {
        var pts: [HereLatLng] = []
        if let o = originFix { pts.append(o) }
        pts.append(contentsOf: positionedScans.map { $0.point })
        if let l = liveFix, pts.last != l { pts.append(l) }
        return pts
    }

    private var hasMapGeo: Bool {
        liveFix != nil || traveledPolyline.count >= 2 || !canonicalRouteLines.isEmpty
    }

    private var canonicalRouteCenter: HereLatLng? {
        canonicalRouteLines.lazy.compactMap(\.first).first
    }

    private var nearbyCenter: HereLatLng? {
        liveFix ?? destFix ?? originFix ?? canonicalRouteCenter
    }

    // AEI/carrier observations describe where and when a consist was reported.
    // They do not become track distance, speed, remaining miles, or completion
    // until the server projects them onto the exact bound EusoRail route plan.

    // MARK: - ETA

    /// The ETA on screen: carrier feed first, schedule column second.
    private var etaDate: Date? {
        if let feed = nonEmpty(classI?.eta), let d = parseStamp003(feed) { return d }
        if let sched = nonEmpty(detail?.estimatedArrivalAt), let d = parseStamp003(sched) { return d }
        return nil
    }

    private var etaSourceLabel: String {
        if nonEmpty(classI?.eta) != nil { return "carrier feed" }
        if nonEmpty(detail?.estimatedArrivalAt) != nil { return "scheduled" }
        return "eta pending"
    }

    /// ETA rendered in the RAMP's own timezone when the yard publishes one —
    /// a Los Angeles ramp window is meaningless read in the device's clock.
    private var rampTimeZone: TimeZone? {
        guard let id = nonEmpty(detail?.destinationYard?.operatingHours?.timezone) else { return nil }
        return TimeZone(identifier: id)
    }

    private var etaClockText: String {
        guard let d = etaDate else { return "-" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        f.timeZone = rampTimeZone ?? .current
        return f.string(from: d)
    }

    private var etaDayText: String? {
        guard let d = etaDate else { return nil }
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        f.timeZone = rampTimeZone ?? .current
        return f.string(from: d)
    }

    /// Does the ETA land inside the ramp's own operating window?
    private var rampWindowFit: RampWindowFit003 {
        guard let eta = etaDate,
              let tz = rampTimeZone,
              let openMin = minutesOfDay003(detail?.destinationYard?.operatingHours?.open),
              let closeMin = minutesOfDay003(detail?.destinationYard?.operatingHours?.close),
              closeMin > openMin else { return .unknown }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let c = cal.dateComponents([.hour, .minute], from: eta)
        let etaMin = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        guard etaMin >= openMin, etaMin <= closeMin else { return .outside }
        return .inside(minutes: closeMin - etaMin)
    }

    // MARK: - Identity strings (every one a decoded column)

    private var routeTitle: String {
        let o = nonEmpty(detail?.originYard?.city) ?? nonEmpty(detail?.originYard?.name)
        let d = nonEmpty(detail?.destinationYard?.city) ?? nonEmpty(detail?.destinationYard?.name)
        if let o, let d { return "\(o) → \(d)" }
        if let r = nonEmpty(detail?.routeDescription) { return r }
        if loading { return "Loading…" }
        return nonEmpty(detail?.shipmentNumber) ?? "Rail shipment"
    }

    /// "<shipmentNumber> · <marks>" — the SVG's mono caption. There is no train
    /// symbol column (named gap above), so the second register is the REAL
    /// reporting marks the shipment actually carries.
    private var idCaption: String {
        let number = nonEmpty(detail?.shipmentNumber) ?? (loading ? "…" : "-")
        let marks = [nonEmpty(detail?.originRailroad), nonEmpty(detail?.destinationRailroad)]
            .compactMap { $0 }
        let uniqueMarks = marks.reduce(into: [String]()) { acc, m in if !acc.contains(m) { acc.append(m) } }
        guard !uniqueMarks.isEmpty else { return number }
        return "\(number) · \(uniqueMarks.joined(separator: " → "))"
    }

    private var rampName: String {
        nonEmpty(detail?.destinationYard?.name)
            ?? nonEmpty(detail?.destinationYard?.city)
            ?? nonEmpty(classI?.destinationStation)
            ?? "the ramp"
    }

    /// Short ramp token for the chips — first word of the real yard name.
    private var rampShort: String {
        let source = nonEmpty(detail?.destinationYard?.name)
            ?? nonEmpty(detail?.destinationYard?.city)
            ?? nonEmpty(classI?.destinationStation)
        guard let source else { return "RAMP" }
        let first = source.split(separator: " ").first.map(String.init) ?? source
        return first.uppercased()
    }

    private var originName: String {
        nonEmpty(detail?.originYard?.name) ?? nonEmpty(detail?.originYard?.city) ?? "-"
    }

    /// "intermodal · 6 cars · UP" — carType + numberOfCars + reporting mark.
    private var consistLine: String {
        var parts: [String] = []
        if let t = nonEmpty(detail?.carType) { parts.append(t.replacingOccurrences(of: "_", with: " ")) }
        if let n = detail?.numberOfCars, n > 0 { parts.append("\(n) car\(n == 1 ? "" : "s")") }
        if let mark = nonEmpty(detail?.originRailroad) { parts.append(mark) }
        return parts.isEmpty ? "consist pending" : parts.joined(separator: " · ")
    }

    /// The ramp's own country, straight off rail_yards.country — this is what
    /// makes the US / CA / MX content differ, not a client-side assumption.
    private var rampCountry: String? { nonEmpty(detail?.destinationYard?.country)?.uppercased() }

    private var demurrageFreeHours: Int? {
        detail?.demurrage?.compactMap { $0.freeTimeHours }.max()
    }

    private var carsOnShipment: [RailWaybillNode003] {
        (detail?.waybills ?? []).filter { nonEmpty($0.railcarNumber) != nil }
    }

    // MARK: - READ_CACHED(5m) freshness register

    private var cacheAge: TimeInterval? {
        guard let fetchedAt else { return nil }
        return max(0, Date().timeIntervalSince(fetchedAt))
    }

    private var isStale: Bool { (cacheAge ?? 0) > RailTrackCache003.ttl }

    private var railObservationState: HereObservationState {
        if !reach.isOnline { return .offline }
        if trackingDegraded || classIDegraded { return .degraded }
        if isStale { return .stale }
        return .current
    }

    private var railLiveOperationsStatus: HereLiveOperationsStatus {
        if nearbyRailStore.result != nil || nearbyRailStore.errorMessage != nil {
            return nearbyRailStore.status
        }
        let availability: HereLiveOperationsStatus.Availability
        switch railObservationState {
        case .current: availability = liveFix == nil ? .empty : .live
        case .stale: availability = .stale
        case .degraded, .offline: availability = .degraded
        }
        return .init(
            availability: availability,
            sourceLabel: fixIsCarrierFeed ? "Class I carrier feed" : "Rail event scan",
            freshnessLabel: freshnessText(now: Date()),
            detail: liveFix == nil ? "No authorized rail observation" : "Authorized rail position",
            observationCount: liveFix == nil ? 0 : 1
        )
    }

    private func freshnessText(now: Date) -> String {
        guard let fetchedAt else {
            if !reach.isOnline { return "offline · no read" }
            return loading ? "loading" : "no read"
        }
        let age = max(0, now.timeIntervalSince(fetchedAt))
        // Offline outranks stale: "stale · 12m" implies the network was tried
        // and the data is merely old. Offline says nothing can be refreshed.
        if !reach.isOnline { return "offline · \(compactAge003(age))" }
        let label = age > RailTrackCache003.ttl ? "stale" : (servedFromCache ? "cached" : "live")
        return "\(label) · \(compactAge003(age))"
    }

    private func freshnessColor(now: Date) -> Color {
        if !reach.isOnline { return Brand.warning }
        guard let fetchedAt else { return palette.textTertiary }
        let age = max(0, now.timeIntervalSince(fetchedAt))
        if age > RailTrackCache003.ttl { return Brand.warning }
        return servedFromCache ? palette.textTertiary : Brand.success
    }

    /// Offline is a state of the DEVICE, not of the data, so it gets its own
    /// band above everything rather than being folded into the staleness stamp.
    /// Nothing here gates a write — 003 is read-only — it exists so a stale
    /// board is never mistaken for a live one.
    @ViewBuilder
    private var offlineBanner: some View {
        if !reach.isOnline && detail != nil {
            HStack(alignment: .top, spacing: Space.s2) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Brand.warning)
                Text("Offline — everything below is the last snapshot this device pulled\(fetchedAt.map { ", \(compactAge003(max(0, Date().timeIntervalSince($0)))) old" } ?? ""). Positions and events are not updating.")
                    .font(EType.caption)
                    .foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                IridescentHairline()

                offlineBanner

                if !reach.isOnline && detail == nil {
                    // Cold and offline: no cached snapshot to serve and no way
                    // to fetch one. Say exactly that instead of falling through
                    // to a "couldn't load" that implies the server answered.
                    EusoEmptyState(
                        systemImage: "wifi.slash",
                        title: "Offline — nothing cached for this shipment",
                        subtitle: "Live tracking is a read-only screen with a five-minute cache, and there is no saved snapshot for this shipment on this device. Reconnect to pull it."
                    )
                } else if loading && detail == nil {
                    LifecycleCard {
                        Text("Loading live tracking…")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                } else if let err = loadError, detail == nil {
                    LifecycleCard(accentDanger: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Couldn't load this shipment")
                                .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                            Text(err).font(EType.caption).foregroundStyle(Brand.danger).lineLimit(3)
                        }
                    }
                } else if detail == nil {
                    // getRailShipmentDetail returns null for THREE different
                    // reasons — database unavailable (railShipments.ts:416),
                    // no such shipment (:419) and the tenant gate (:420) — and
                    // the wire carries no way to tell them apart. Naming one of
                    // them would report an outage to the user as a permissions
                    // denial, so the copy states what is actually known and
                    // lists the causes without picking one.
                    EusoEmptyState(
                        systemImage: "questionmark.circle",
                        title: "This shipment couldn't be loaded",
                        subtitle: "No record came back for it. It may not exist, it may not be on your account, or records may be temporarily unavailable — the reply doesn't say which. Pull to retry."
                    )
                } else {
                    mapHero
                    statusStrip
                    meterCard
                    arrivalPlanCard
                    eventsSection
                    ctaPair
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await load() }
        .task(id: nearbyCenter) {
            guard let nearbyCenter else { return }
            await nearbyRailStore.poll(
                around: nearbyCenter,
                radiusMeters: 160_000,
                limit: 150
            )
        }
        .eusoRefreshable { await load() }
        .onAppear { startBreathing() }
        .onChange(of: reduceMotion) { _, _ in startBreathing() }
        .sheet(isPresented: $showPerCar) {
            RailPerCarPositionsSheet003(cars: carsOnShipment, rampName: rampName)
        }
    }

    private func startBreathing() {
        guard !reduceMotion else { nodeBreathing = false; return }
        nodeBreathing = false
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
            nodeBreathing = true
        }
    }

    // MARK: - TopBar (back chevron · the single eyebrow · freshness · lane title · mono id)

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Space.s2) {
                EusoTripEyebrow(verbatim: "SHIPPER · RAIL · LIVE TRACKING")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: Space.s2)
                // READ_CACHED(5m) staleness register — the honesty law lives here.
                TimelineView(.periodic(from: .now, by: 5)) { ctx in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(freshnessColor(now: ctx.date))
                            .frame(width: 6, height: 6)
                        Text(freshnessText(now: ctx.date))
                            .font(EType.mono(.micro))
                            .foregroundStyle(freshnessColor(now: ctx.date))
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Text(routeTitle)
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.55)
                Spacer(minLength: 0)
            }
            Text(idCaption)
                .font(EType.mono(.caption)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }

    // MARK: - LIVE NETWORK MAP hero
    //
    // The hero separates facts deliberately: a time-ordered observation trail,
    // origin/ramp reference pins, the latest authorized position, and a ramp
    // geofence only when a real company row exists. The evidence register below
    // never presents the scan chain as track geometry or route progress.

    @ViewBuilder
    private var mapHero: some View {
        VStack(spacing: 0) {
            if hasMapGeo {
                mapCanvas
            } else {
                geoPending
            }
            positionRail
        }
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var mapCanvas: some View {
        ZStack(alignment: .topTrailing) {
            HereVectorMapView(
                center: liveFix ?? destFix ?? originFix ?? canonicalRouteCenter ?? HereLatLng(39.5, -98.35),
                zoom: traveledPolyline.count >= 2 || !canonicalRouteLines.isEmpty ? 6 : 9,
                interactive: true,
                tilt: 0,
                layers: mapLayers,
                activeJob: true,
                mapModeContext: .primary(.rail),
                liveOperationsStatus: railLiveOperationsStatus
            )
            .frame(height: 190)

            etaChip
                .padding(.top, 10)
                .padding(.trailing, 10)
        }
        .overlay(alignment: .bottom) {
            fixChip.padding(.bottom, 22)
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 4) {
                if let canonicalRouteStatus {
                    Text(canonicalRouteStatus)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(palette.bgCard.opacity(0.92))
                        .overlay(Capsule().strokeBorder(Brand.warning.opacity(0.45)))
                        .clipShape(Capsule())
                        .accessibilityLabel(canonicalRouteStatus)
                }
                // HERE is the tile source; the attribution is not optional.
                Text("HERE maps")
                    .font(.system(size: 7, weight: .bold)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.leading, 12).padding(.bottom, 6)
        }
        .frame(height: 190)
    }

    private var mapLayers: [HereMapLayer] {
        var layers: [HereMapLayer] = canonicalRouteLines.enumerated().map { index, line in
            .eusoRoute(
                polyline: line,
                state: .active,
                label: index == 0
                    ? "Eusorone rail route plan version \(canonicalRouteVersion ?? 0)"
                    : nil
            )
        }
        let observations = positionedScans.map(\.point) + (liveFix.map { [$0] } ?? [])
        if observations.count >= 2 {
            layers.append(.observationTrail(
                points: observations,
                label: "Reported rail position history"
            ))
        }
        // §3c RAMP FENCE — the canon rail-ramp ring grammar, drawn only from a
        // real tracking.getGeofences row covering the ramp. No row ⇒ no ring.
        if let fence = rampFence {
            layers.append(.geofenceRing(center: fence.center,
                                        radiusMeters: fence.radiusMeters,
                                        kind: .railRamp,
                                        breachAt: nil))
        }
        var pins: [HereMarker] = []
        if let o = originFix {
            pins.append(HereMarker(at: o, kind: .pickup, label: originName))
        }
        if let d = destFix {
            pins.append(HereMarker(at: d, kind: .delivery, label: rampName))
        }
        if let l = liveFix {
            pins.append(HereMarker(
                at: l,
                kind: .rail,
                label: fixPlace,
                observationState: railObservationState,
                sourceLabel: fixIsCarrierFeed ? "Class I carrier feed" : "Rail event scan",
                accessibilityLabel: "Rail consist \(fixPlace ?? "position"), \(railObservationState.displayName)"
            ))
        }
        pins.append(contentsOf: nearbyRailStore.markers)
        if !pins.isEmpty { layers.append(.markers(pins)) }
        return layers
    }

    /// "05-25 09:40" in the ramp's own clock — or an honest dash.
    private var etaStampText: String {
        var parts: [String] = []
        if let day = etaDayText { parts.append(day) }
        if etaClockText != "-" { parts.append(etaClockText) }
        return parts.isEmpty ? "-" : parts.joined(separator: " ")
    }

    private var etaChip: some View {
        HStack(spacing: 5) {
            Text("ETA · \(rampShort)")
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
            Text(etaStampText)
                .font(.system(size: 11, weight: .bold)).monospacedDigit()
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Capsule().fill(palette.bgCard))
        .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    /// Place chip for the exact latest reported position. We deliberately do
    /// not infer speed from the straight-line gap between two AEI readers.
    private var fixChip: some View {
        HStack(spacing: 6) {
            Text((fixPlace ?? "position pending").uppercased())
                .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Capsule().fill(palette.bgCard))
        .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    private var geoPending: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "location.slash")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 38, height: 38)
                .background(Circle().fill(palette.bgCardSoft))
            VStack(alignment: .leading, spacing: 4) {
                Text("No position reported yet")
                    .font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text("The live map draws as soon as the carrier feed or a yard scan returns a verified coordinate.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(height: 190)
    }

    /// Evidence rail. This preserves the flagship rail grammar without moving
    /// a train glyph to a position the server has not projected onto track.
    private var positionRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle()
                        .fill(Brand.blue.opacity(0.16))
                        .frame(width: 34, height: 34)
                        .scaleEffect(nodeBreathing ? 1.08 : 0.96)
                    Circle()
                        .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
                        .frame(width: 30, height: 30)
                    Image(systemName: "train.side.front.car")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(LinearGradient.primary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("AUTHORIZED POSITION EVIDENCE")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.7)
                        .foregroundStyle(palette.textTertiary)
                    Text("\(positionedScans.count + (liveFix == nil ? 0 : 1)) reported fix\((positionedScans.count + (liveFix == nil ? 0 : 1)) == 1 ? "" : "es") · route progress pending projection")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                }
                Spacer(minLength: Space.s2)
                Text(fixAgeCaption)
                    .font(EType.mono(.caption))
                    .foregroundStyle(isStale ? Brand.warning : palette.textTertiary)
            }

            HStack {
                Text("REFERENCE · \(originName.uppercased())")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: Space.s2)
                Text(rampFence == nil ? "\(rampName.uppercased()) · REFERENCE" : "\(rampName.uppercased()) · RAMP FENCE")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(rampFence == nil ? palette.textTertiary : Brand.success)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, Space.s3)
    }

    // MARK: - Live status strip

    private var statusStrip: some View {
        HStack(spacing: Space.s3) {
            Circle()
                .fill(isStale ? Brand.warning : Brand.success)
                .frame(width: 8, height: 8)
                .scaleEffect(nodeBreathing ? 1.25 : 1.0)
            Text(consistLine)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: Space.s2)
            Text(fixAgeCaption)
                .font(EType.mono(.caption))
                .foregroundStyle(isStale ? Brand.warning : palette.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, Space.s4)
        .frame(height: 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Age of the FIX (a server timestamp), which is a different fact from the
    /// age of the read in the header. Both are shown; neither stands in for the
    /// other.
    private var fixAgeCaption: String {
        guard let stamp = fixReportedAt, let d = parseStamp003(stamp) else { return "no fix yet" }
        return "fix \(compactAge003(max(0, Date().timeIntervalSince(d)))) old"
    }

    // MARK: - Route evidence register

    private var meterCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("ROUTE EVIDENCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                // Three states, not two: carrier feed answered · carrier feed
                // failed · never asked (falls back to yard scans). A failed
                // feed must not read as a shipment that simply has no feed.
                Text(fixIsCarrierFeed ? "CARRIER FEED"
                     : (classIDegraded ? "FEED UNREACHABLE" : "YARD SCANS"))
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(fixIsCarrierFeed ? Brand.success
                                     : (classIDegraded ? Brand.warning : palette.textTertiary))
            }
            if classIDegraded {
                Text("The Class I carrier feed didn't answer on this pass, so the position below is the stored scan chain, not a live carrier report.")
                    .font(EType.caption).foregroundStyle(Brand.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .center, spacing: Space.s4) {
                evidenceGauge
                VStack(alignment: .leading, spacing: 2) {
                    Text("LATEST FIX")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Text(fixPlace ?? "Not reported")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2).minimumScaleFactor(0.7)
                }
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("ETA · \(rampShort)")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(etaClockText)
                            .font(.system(size: 22, weight: .bold)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                        Text(etaDayText.map { "· \($0)" } ?? "")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }

            Text(meterFootnote)
                .font(.system(size: 10))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.35), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var evidenceGauge: some View {
        ZStack {
            Circle()
                .stroke(palette.textTertiary.opacity(0.22), lineWidth: 6)
                .frame(width: 60, height: 60)
            Circle()
                .trim(from: 0.08, to: 0.92)
                .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: [2, 5]))
                .rotationEffect(.degrees(-75))
                .frame(width: 60, height: 60)
            VStack(spacing: 0) {
                Text("\(positionedScans.count + (liveFix == nil ? 0 : 1))")
                    .font(.system(size: 15, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("FIXES")
                    .font(.system(size: 7.5, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .accessibilityLabel("Authorized rail position evidence")
        .accessibilityValue("\(positionedScans.count + (liveFix == nil ? 0 : 1)) reported fixes; route progress pending server projection")
    }

    /// The honest caption under the meter: what the numbers are, where the ETA
    /// came from, and the ramp's real free-time clock when one exists.
    private var meterFootnote: String {
        var parts: [String] = []
        parts.append("observation trail is not track geometry")
        parts.append("progress requires exact route projection")
        parts.append("ETA \(etaSourceLabel)")
        if let free = demurrageFreeHours {
            parts.append("\(free)h free time before demurrage")
        }
        if let country = rampCountry { parts.append(country) }
        return parts.joined(separator: " · ")
    }

    // MARK: - ESANG ARRIVAL PLAN (composed from decoded fields — see named gap)

    private var arrivalPlanCard: some View {
        Button {
            // Real listener: RoleSurfaceRouter.swift:1111 — the canonical
            // Shipper "talk to ESANG about this load" hop.
            NotificationCenter.default.post(name: .eusoShipperLoadMessageeSang,
                                            object: nil,
                                            userInfo: ["loadId": shipmentId])
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().fill(Brand.magenta.opacity(0.20)).frame(width: 44, height: 44).blur(radius: 6)
                    Circle().fill(LinearGradient.diagonal).frame(width: 34, height: 34)
                    Circle().fill(Color.white.opacity(0.45)).frame(width: 13, height: 13).offset(x: -5, y: -5)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("ESANG · ARRIVAL PLAN")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Text(arrivalHeadline)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2).minimumScaleFactor(0.8)
                        .multilineTextAlignment(.leading)
                    Text(arrivalDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(arrivalIsWarning ? Brand.warning : palette.textSecondary)
                        .lineLimit(2).minimumScaleFactor(0.8)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: Space.s2)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var arrivalIsWarning: Bool {
        if case .outside = rampWindowFit { return true }
        return isHoldStatus
    }

    private var isHoldStatus: Bool {
        let s = (detail?.status ?? "").lowercased()
        return ["on_hold", "derailment_hold", "hazmat_exception", "interchange_delay", "cancelled"].contains(s)
    }

    /// One sentence and a number — every token a decoded field.
    private var arrivalHeadline: String {
        if isHoldStatus {
            return "Held — \(humanizeStatus003(detail?.status)) at \(fixPlace ?? rampName)"
        }
        guard etaDate != nil else {
            return "No ETA published yet for \(rampName)"
        }
        return "Steady to \(rampName) — you land \(etaClockText)"
    }

    private var arrivalDetail: String {
        var parts: [String] = []
        switch rampWindowFit {
        case .inside(let minutes):
            parts.append("\(minutes) min inside the ramp window")
        case .outside:
            parts.append("lands outside the published ramp window")
        case .unknown:
            if nonEmpty(detail?.destinationYard?.operatingHours?.open) == nil {
                parts.append("ramp window not published")
            }
        }
        if let place = fixPlace {
            parts.append("last fix \(place)")
        }
        if let free = demurrageFreeHours {
            parts.append("\(free)h free time on arrival")
        }
        if parts.isEmpty { parts.append("waiting on the first verified fix") }
        return parts.joined(separator: " · ")
    }

    // MARK: - LIVE EVENTS timeline

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("LIVE EVENTS · EUSOTRIP NETWORK")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("carrier tracking feed")
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
            if events.isEmpty && trackingDegraded {
                // A DEAD feed is not an empty one. Saying "no events yet" here
                // would report a failed read as a quiet shipment.
                EusoEmptyState(
                    systemImage: "wifi.exclamationmark",
                    title: "Event feed didn't load",
                    subtitle: "Tracking did not answer on this pass, so the timeline is blank because the read failed — not because nothing has been reported. Pull to retry."
                )
            } else if events.isEmpty {
                EusoEmptyState(
                    systemImage: "clock.badge.questionmark",
                    title: "No events yet",
                    subtitle: "Yard scans, interchange receipts and ramp arrivals land here as they are reported."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shownEvents.enumerated()), id: \.element.id) { idx, e in
                        eventRow(e, isActive: idx == 0)
                        if idx < shownEvents.count - 1 {
                            Divider().padding(.leading, 46).overlay(palette.borderFaint)
                        }
                    }
                }
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func eventRow(_ e: RailEventNode003, isActive: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            ZStack {
                if isActive {
                    Circle()
                        .fill(Brand.blue.opacity(0.22))
                        .frame(width: 20, height: 20)
                        .scaleEffect(nodeBreathing ? 1.2 : 0.85)
                        .opacity(nodeBreathing ? 0.35 : 0.9)
                    Circle().fill(LinearGradient.primary).frame(width: 14, height: 14)
                    Circle().fill(palette.bgCard).frame(width: 6, height: 6)
                } else {
                    Circle()
                        .strokeBorder(palette.textTertiary, lineWidth: 2)
                        .frame(width: 12, height: 12)
                }
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 3) {
                Text(nonEmpty(e.description) ?? humanizeStatus003(e.eventType))
                    .font(.system(size: 13, weight: isActive ? .bold : .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let sub = eventSubline(e) {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: Space.s2)
            Text(shortStamp003(e.timestamp))
                .font(.system(size: 11, weight: .bold)).monospacedDigit()
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
    }

    private func eventSubline(_ e: RailEventNode003) -> String? {
        var parts: [String] = []
        if let place = nonEmpty(e.location?.description) { parts.append(place) }
        if let type = nonEmpty(e.eventType), nonEmpty(e.description) != nil {
            parts.append(humanizeStatus003(type).lowercased())
        }
        if e.location?.fix != nil { parts.append("verified fix") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            // Primary: the shipment's REAL waybill cars, each resolved through
            // the tenant/source/licence-authorized Live Operations authority.
            CTAButton(
                title: carsOnShipment.isEmpty ? "Per-car positions" : "Per-car positions · \(carsOnShipment.count)",
                action: { showPerCar = true },
                leadingIcon: "train.side.front.car",
                isLoading: false
            )
            .frame(maxWidth: .infinity)
            .opacity(carsOnShipment.isEmpty ? 0.55 : 1)
            .disabled(carsOnShipment.isEmpty)

            // Secondary: shares the REAL decoded ETA line. The tokenized public
            // link is the shareRailTrackingLink named gap declared in the header
            // — tracking.shareTrackingLink resolves `loads`, not rail_shipments,
            // so pointing this at it would ship a dead button.
            ShareLink(item: shareEtaText) {
                Text("Share ETA")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 140, height: 52)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
    }

    /// The share payload — decoded fields only, and it names its own ETA source
    /// so the recipient knows whether it is a carrier feed or a schedule.
    private var shareEtaText: String {
        var lines: [String] = []
        lines.append("\(nonEmpty(detail?.shipmentNumber) ?? "Rail shipment") · \(routeTitle)")
        if etaDate != nil {
            lines.append("ETA \(rampName): \(etaStampText) (\(etaSourceLabel))")
        } else {
            lines.append("ETA \(rampName): not published yet")
        }
        if let place = fixPlace { lines.append("Last fix: \(place) · \(fixAgeCaption)") }
        lines.append("Route progress: pending exact server projection")
        lines.append(consistLine)
        return lines.joined(separator: "\n")
    }

    // MARK: - Load (READ_CACHED(5m), cache-first, parallel fan-out)

    private func load() async {
        // Cache-first paint so the board is never blank on re-entry — and the
        // header immediately says "cached · Nm" rather than implying live.
        if detail == nil, let cached = RailTrackCache003.shared.read(shipmentId) {
            apply(cached.snapshot)
            fetchedAt = cached.at
            servedFromCache = true
        }

        loading = true
        loadError = nil
        trackingDegraded = false
        classIDegraded = false
        await refreshCanonicalRoute()

        struct DetailIn: Encodable { let id: Int }

        do {
            // Primary read — this one owns the error surface.
            async let trackingFetch = fetchTracking()
            let d: RailShipmentDetail003? = try await EusoTripAPI.shared.query(
                "railShipments.getRailShipmentDetail",
                input: DetailIn(id: shipmentId))
            let (t, tFailed) = await trackingFetch

            self.detail = d
            self.tracking = t
            self.trackingDegraded = tFailed

            // Secondary fan-out — a dead section must not kill the board, so
            // each of these folds to nil on failure. The fold is now FLAGGED:
            // the UI states the absence AND says whether it is an empty section
            // or a section that failed to read.
            let feedRailroad = nonEmpty(d?.originRailroad) ?? nonEmpty(d?.destinationRailroad)
            let feedReference = nonEmpty(d?.shipmentNumber)
            async let feedFetch = fetchClassI(
                railroad: feedRailroad,
                reference: feedReference)
            async let fenceFetch = fetchRampFence(at: d?.destinationYard?.coordinates?.fix)

            let (feed, feedFailed) = await feedFetch
            self.classI = feed
            self.classIDegraded = feedFailed
            self.rampFence = await fenceFetch

            fetchedAt = Date()
            servedFromCache = false
            RailTrackCache003.shared.write(shipmentId, RailTrackSnapshot003(
                detail: self.detail,
                tracking: self.tracking,
                classI: self.classI,
                rampFence: self.rampFence))
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }

        loading = false
    }

    private func apply(_ snapshot: RailTrackSnapshot003) {
        detail = snapshot.detail
        tracking = snapshot.tracking
        classI = snapshot.classI
        rampFence = snapshot.rampFence
    }

    /// Rail geometry comes only from the exact server-owned EusoRail graph
    /// solve. Carrier calls and AEI/CLM observations remain evidence layers;
    /// they never become a route line on this client.
    @MainActor
    private func refreshCanonicalRoute() async {
        canonicalRouteLines = []
        canonicalRouteStatus = nil
        canonicalRouteVersion = nil
        do {
            let result = try await CanonicalRoutePlanClient.shared.planRailShipment(
                id: shipmentId,
                purpose: .activeJob
            )
            switch result {
            case .persisted(let persisted):
                applyCanonicalRoute(persisted.route)
            case .pending(let pending):
                canonicalRouteStatus = pending.blockers.first?.message
                    ?? "EusoRail route pending verified graph authority"
                await readExistingCanonicalRoute()
            }
        } catch {
            canonicalRouteStatus = error.eusoUserCopy
            await readExistingCanonicalRoute()
        }
    }

    @MainActor
    private func readExistingCanonicalRoute() async {
        do {
            applyCanonicalRoute(
                try await CanonicalRoutePlanClient.shared.getBoundRailShipment(id: shipmentId)
            )
        } catch {
            if canonicalRouteStatus == nil { canonicalRouteStatus = error.eusoUserCopy }
        }
    }

    @MainActor
    private func applyCanonicalRoute(_ route: CanonicalRoutePlanClient.BoundRoutePlan) {
        guard let payload = route.rendererPayload else {
            canonicalRouteLines = []
            canonicalRouteVersion = nil
            canonicalRouteStatus = "EusoRail route exists but is not released for rendering"
            return
        }
        canonicalRouteLines = payload.lines
        canonicalRouteVersion = payload.identity.version
        canonicalRouteStatus = nil
    }

    /// railShipments.getRailTracking — query · railShipments.ts:1536.
    /// Returns (value, failed). `failed` is true ONLY on a throw — a successful
    /// read that carries no events is empty, not degraded, and the two must not
    /// be collapsed into the same nil.
    private func fetchTracking() async -> (RailTrackingFeed003?, Bool) {
        struct In: Encodable { let shipmentId: Int }
        do {
            let v: RailTrackingFeed003? = try await EusoTripAPI.shared.query(
                "railShipments.getRailTracking", input: In(shipmentId: shipmentId))
            return (v, false)
        } catch {
            return (nil, true)
        }
    }

    /// railShipments.liveTrackShipment — query · railShipments.ts:2132.
    /// Requires BOTH a real reporting mark and the real shipment number. Missing
    /// inputs is NOT a degraded read — there was nothing to ask with — so that
    /// path returns failed:false. Only a throw is degraded.
    private func fetchClassI(railroad: String?, reference: String?) async -> (ClassITrack003?, Bool) {
        guard let railroad, let reference else { return (nil, false) }
        struct In: Encodable { let railroad: String; let shipmentId: String }
        do {
            let out: ClassITrack003? = try await EusoTripAPI.shared.query(
                "railShipments.liveTrackShipment", input: In(railroad: railroad, shipmentId: reference))
            return (out, false)
        } catch {
            return (nil, true)
        }
    }

    /// tracking.getGeofences — query · tracking.ts:440, resolved through the
    /// house helper. Absent covering row ⇒ nil ⇒ no ring is painted.
    private func fetchRampFence(at ramp: HereLatLng?) async -> TrackingGeofencesAPI.ResolvedFence? {
        guard let ramp else { return nil }
        return await EusoTripAPI.shared.trackingGeofences.fence(near: ramp.lat, ramp.lng)
    }

    // MARK: - Small helpers

    private func nonEmpty(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}

// MARK: - Per-car positions sheet
//
// The shipment's REAL cars (rail_waybills.railcarNumber off
// getRailShipmentDetail), each resolved through the server-owned Live
// Operations authority. That authority applies tenant grants, source rights,
// licence validity and immutable observation evidence before returning a fix.
// A car whose authorized feed is silent says so; it never borrows the block's
// position and this phone never calls a railroad/provider directly.

private struct RailPerCarPositionsSheet003: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let cars: [RailWaybillNode003]
    let rampName: String

    @State private var results: [String: LiveOperationsClient.AssetResult] = [:]
    @State private var failedCars: Set<String> = []
    @State private var loading = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(spacing: 6) {
                    Image(systemName: "train.side.front.car")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("PER-CAR POSITIONS · LIVE OPERATIONS")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                }

                Text("Cars on this shipment")
                    .font(.system(size: 22, weight: .heavy)).kerning(-0.3)
                    .foregroundStyle(palette.textPrimary)

                Text("Each car is resolved against its own tenant-authorized carrier or AEI evidence on the way to \(rampName). A car with no authorized observation is shown as awaiting a scan — it is never given the block's position.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if cars.isEmpty {
                    EusoEmptyState(
                        systemImage: "train.side.front.car",
                        title: "No cars on the waybill yet",
                        subtitle: "Car numbers appear here once the waybill is issued for this shipment."
                    )
                } else {
                    VStack(spacing: Space.s2) {
                        ForEach(cars) { car in
                            carRow(car)
                        }
                    }
                    if loading {
                        HStack(spacing: Space.s2) {
                            ProgressView().scaleEffect(0.8)
                            Text("Resolving live car fixes…")
                                .font(EType.caption).foregroundStyle(palette.textSecondary)
                        }
                    }
                }

                Color.clear.frame(height: 24)
            }
            .padding(20)
        }
        .background(palette.bgSheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .eusoRefreshTask { await loadFixes() }
    }

    private func carRow(_ car: RailWaybillNode003) -> some View {
        let number = car.railcarNumber ?? "-"
        let result = results[number]
        let observation = result?.observation
        let evidence = observation?.quality.evidence
        let place = evidence?.eventDescription
            ?? evidence?.nextScheduledEventDescription
            ?? observation?.position.coordinate.map { "\($0.lat), \($0.lng)" }
        let failed = failedCars.contains(number)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Space.s3) {
                Text(number)
                    .font(.system(size: 13, weight: .bold)).monospaced()
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: Space.s2)
                if let observation {
                    Text(observation.freshnessState.rawValue.uppercased())
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(observation.markerState == .current ? Brand.success : Brand.warning)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(
                            (observation.markerState == .current ? Brand.success : Brand.warning).opacity(0.14)
                        ))
                } else {
                    Text(failed ? "FEED UNAVAILABLE" : "AWAITING SCAN")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(failed ? Brand.warning : palette.textTertiary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(
                            (failed ? Brand.warning : palette.textTertiary).opacity(0.12)
                        ))
                }
            }
            Text(place ?? (failed
                ? "The authorized live read could not be completed"
                : "No authorized position observation is available"))
                .font(EType.caption)
                .foregroundStyle(place == nil ? palette.textTertiary : palette.textSecondary)
            if let observation {
                Text("\(observation.provider.id) · \(observation.quality.state.rawValue) · \(observation.asset.accessBasis)")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            HStack(spacing: Space.s2) {
                if let reported = observation?.observedAt, let d = parseStamp003(reported) {
                    Text("scanned \(compactAge003(max(0, Date().timeIntervalSince(d)))) ago")
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                }
                if let commodity = trimmed(car.commodity) {
                    Text(commodity)
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let dest = trimmed(car.destinationStation) {
                    Text("→ \(dest)")
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel([
            "Railcar \(number)",
            observation?.accessibleEvidenceLabel,
            place,
            failed ? "authorized live feed unavailable" : nil,
        ].compactMap { $0 }.joined(separator: ", "))
    }

    private func loadFixes() async {
        loading = true
        results.removeAll(keepingCapacity: true)
        failedCars.removeAll(keepingCapacity: true)
        await withTaskGroup(of: (String, LiveOperationsClient.AssetResult?, Bool).self) { group in
            for car in cars {
                guard let number = trimmed(car.railcarNumber) else { continue }
                group.addTask {
                    do {
                        let result = try await LiveOperationsClient.shared.latestRailcar(number: number)
                        return (number, result, false)
                    } catch {
                        return (number, nil, true)
                    }
                }
            }
            for await (number, result, failed) in group {
                if let result {
                    results[number] = result
                }
                if failed {
                    failedCars.insert(number)
                }
            }
        }
        loading = false
    }

    private func trimmed(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}

// MARK: - File-scoped pure helpers

/// Tolerant server-timestamp parse — ISO-8601 with or without fractional
/// seconds, plus the plain MySQL datetime form.
private func parseStamp003(_ raw: String?) -> Date? {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f1.date(from: raw) { return d }
    let f2 = ISO8601DateFormatter()
    f2.formatOptions = [.withInternetDateTime]
    if let d = f2.date(from: raw) { return d }
    let f3 = DateFormatter()
    f3.locale = Locale(identifier: "en_US_POSIX")
    f3.timeZone = TimeZone(identifier: "UTC")
    f3.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f3.date(from: raw)
}

/// "HH:mm" → minutes past midnight.
private func minutesOfDay003(_ raw: String?) -> Int? {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
    let parts = raw.split(separator: ":")
    guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]),
          (0...23).contains(h), (0...59).contains(m) else { return nil }
    return h * 60 + m
}

/// Compact, monospaced-friendly age token: "8s" / "12m" / "3h" / "2d".
private func compactAge003(_ seconds: TimeInterval) -> String {
    if seconds < 60 { return "\(Int(seconds))s" }
    if seconds < 3600 { return "\(Int(seconds / 60))m" }
    if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
    return "\(Int(seconds / 86_400))d"
}

/// Timeline right-register stamp: same-day events read as a clock, older ones
/// as a date — exactly the SVG's mixed "06:12 / 04:38 / 05-23" register.
private func shortStamp003(_ raw: String?) -> String {
    guard let d = parseStamp003(raw) else { return "-" }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = Calendar.current.isDateInToday(d) ? "HH:mm" : "MM-dd"
    return f.string(from: d)
}

/// "status_in_transit" / "at_interchange" → "In transit" / "At interchange".
private func humanizeStatus003(_ raw: String?) -> String {
    guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return "Update" }
    let cleaned = raw
        .replacingOccurrences(of: "status_", with: "")
        .replacingOccurrences(of: "_", with: " ")
    return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
}

// MARK: - Previews

#Preview("003 · Rail Live Tracking · Night") {
    RailLiveTracking_003(theme: Theme.dark, shipmentId: 0)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("003 · Rail Live Tracking · Light") {
    RailLiveTracking_003(theme: Theme.light, shipmentId: 0)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
