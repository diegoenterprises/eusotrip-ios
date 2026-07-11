//
//  003_RailLiveTracking.swift
//  EusoTrip — Rail · Shipper · Live Tracking (brick 003).
//
//  Verbatim SwiftUI port of "05 Rail/003 Rail Live Tracking · Dark" at the
//  golden design-authority bar. SHIPPER vantage on one live intermodal rail
//  block: a MAP/TRACKING hero (route polyline + origin pin + destination ramp
//  geofence + live consist marker) over an in-transit meter, an ESANG arrival
//  plan, and a live-events timeline. Distinct from 560 (carrier single-train
//  tracker) — this is the shipper's door-to-ramp picture.
//
//  Nav: canonical Shipper enum HOME · LOADS(current) · [orb] · WALLET · ME.
//  transportMode = rail · US (UP Sunset Route) · USD. Persona shipper-of-record
//  Diego Usoro (DU) / Eusorone Technologies (companyId 1).
//
//  WIRING (web parity client/src/pages/shipper/RailLiveTracking.tsx):
//    detail   → railShipments.getRailShipmentDetail  EXISTS · railShipments.ts:316
//               ({id}) → row + origin/destination yards + numberOfCars.
//    tracking → railShipments.getRailTracking        EXISTS · railShipments.ts:958
//               ({shipmentId}) → { events[], currentLocation{lat,lng,description} }.
//    Per-car positions → railShipments.getRailcars   EXISTS · railShipments.ts:703
//               (posts eusoRailcarPositions with the shipmentId for the drill-in).
//    Share ETA         → tracking.shareTrackingLink  EXISTS · tracking.ts:582
//               (returns a public token link the shipper hands the consignee).
//  Progress %, remaining miles, and ETA relative time are HONEST derivations from
//  the real origin/destination yard coords + live fix (haversine + projection);
//  where the payload carries no live coord the meter reads "awaiting position",
//  never a fabricated fraction. RBAC railProcedure (SHIPPER / ADMIN / SUPER_ADMIN).
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Data shapes (decoded from the REAL rail tracking payloads)

private struct RailCoord003: Decodable { let lat: Double?; let lng: Double? }

private struct RailYard003: Decodable {
    let id: Int?
    let name: String?
    let code: String?
    let city: String?
    let state: String?
    let coordinates: RailCoord003?
}

private struct RailLoc003: Decodable {
    let lat: Double?
    let lng: Double?
    let description: String?
}

private struct RailEvent003: Decodable, Identifiable {
    let id: Int?
    let eventType: String?
    let description: String?
    let location: RailLoc003?
    let timestamp: String?
    var rowId: Int { id ?? (timestamp?.hashValue ?? UUID().hashValue) }
}

/// railShipments.getRailShipmentDetail → the rail_shipments row + nested yards.
private struct RailDetail003: Decodable {
    let id: Int?
    let shipmentNumber: String?
    let status: String?
    let carType: String?
    let numberOfCars: Int?
    let commodity: String?
    let waybillNumber: String?
    let originRailroad: String?
    let destinationRailroad: String?
    let estimatedArrivalAt: String?
    let actualArrivalAt: String?
    let routeDescription: String?
    let originYard: RailYard003?
    let destinationYard: RailYard003?
}

/// railShipments.getRailTracking → live events + the current AEI fix.
private struct RailTracking003: Decodable {
    let events: [RailEvent003]?
    let currentLocation: RailLoc003?
}

// MARK: - Screen wrapper

struct RailLiveTrackingShipperScreen: View {
    let theme: Theme.Palette
    /// Real rail_shipments.id; defaults to the canonical wireframe block so the
    /// screen renders standalone. Real call-sites inject the route :id.
    var shipmentId: Int = 48217

    var body: some View {
        Shell(theme: theme) { RailLiveTrackingShipperBody(shipmentId: shipmentId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct RailLiveTrackingShipperBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let shipmentId: Int

    @State private var detail: RailDetail003? = nil
    @State private var tracking: RailTracking003? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Action state
    @State private var actionBanner: String? = nil
    @State private var actionIsError = false
    @State private var sharing = false

    // MARK: Derived, honest values

    private var events: [RailEvent003] { tracking?.events ?? [] }

    private var originCoord: RailCoord003? { detail?.originYard?.coordinates }
    private var destCoord: RailCoord003? { detail?.destinationYard?.coordinates }

    private var liveCoord: RailCoord003? {
        guard let c = tracking?.currentLocation, let la = c.lat, let lo = c.lng,
              !(la == 0 && lo == 0) else { return nil }
        return RailCoord003(lat: la, lng: lo)
    }

    /// 0…1 fraction of the origin→destination line the live fix projects onto.
    private var progress: Double? {
        guard let o = originCoord, let d = destCoord, let l = liveCoord,
              let oy = o.lat, let ox = o.lng, let dy = d.lat, let dx = d.lng,
              let ly = l.lat, let lx = l.lng else { return nil }
        let vx = dx - ox, vy = dy - oy
        let denom = vx * vx + vy * vy
        guard denom > 0 else { return nil }
        let t = ((lx - ox) * vx + (ly - oy) * vy) / denom
        return min(max(t, 0), 1)
    }

    /// Great-circle miles between two lat/lng points.
    private func miles(_ a: RailCoord003?, _ b: RailCoord003?) -> Double? {
        guard let a, let b, let la1 = a.lat, let lo1 = a.lng, let la2 = b.lat, let lo2 = b.lng else { return nil }
        let R = 3958.8
        let dLat = (la2 - la1) * .pi / 180, dLon = (lo2 - lo1) * .pi / 180
        let s = sin(dLat/2)*sin(dLat/2) + cos(la1 * .pi/180)*cos(la2 * .pi/180)*sin(dLon/2)*sin(dLon/2)
        return R * 2 * atan2(sqrt(s), sqrt(1-s))
    }

    private var remainingMiles: Double? { miles(liveCoord ?? originCoord, destCoord) }

    private var routeTitle: String {
        let o = detail?.originYard?.city ?? detail?.originYard?.name
        let d = detail?.destinationYard?.city ?? detail?.destinationYard?.name
        if let o, let d { return "\(o) → \(d)" }
        return "Rail block \(shipmentId)"
    }

    private var idLine: String {
        let num = detail?.shipmentNumber ?? "RAIL-\(shipmentId)"
        let road = [detail?.originRailroad, detail?.destinationRailroad].compactMap { $0 }.first
        return road.map { "\(num) · \($0)" } ?? num
    }

    private var carSummary: String {
        let n = detail?.numberOfCars
        let type = (detail?.carType ?? "intermodal").replacingOccurrences(of: "_", with: " ")
        if let n { return "\(type) · \(n) car\(n == 1 ? "" : "s")" }
        return type
    }

    private var lastEvent: RailEvent003? { events.first }

    private var updatedAgo: String {
        guard let ts = lastEvent?.timestamp else { return "awaiting position" }
        return "updated " + Self.relative(ts)
    }

    static func relative(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return "recently" }
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "\(max(s,1))s ago" }
        if s < 3600 { return "\(s/60)m ago" }
        if s < 86400 { return "\(s/3600)h ago" }
        return "\(s/86400)d ago"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                topBar
                backRow
                titleBlock
                IridescentHairline().padding(.top, Space.s3)

                if loading {
                    skeleton.padding(.top, Space.s4)
                } else if let err = loadError {
                    errorCard(err).padding(.top, Space.s4)
                } else {
                    mapHero.padding(.top, Space.s4)
                    liveStatusStrip.padding(.top, Space.s3)
                    meterCard.padding(.top, Space.s3)
                    arrivalPlanCard.padding(.top, Space.s4)
                    eventsSection.padding(.top, Space.s5)
                    if let banner = actionBanner {
                        actionBannerView(banner).padding(.top, Space.s3)
                    }
                    ctaPair.padding(.top, Space.s5)
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Top bar / back / title

    private var topBar: some View {
        HStack {
            Text("✦ SHIPPER · RAIL · LIVE TRACKING")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(Brand.success).frame(width: 6, height: 6)
                    .opacity(reduceMotion ? 1 : (pulse ? 0.3 : 1))
                Text("LIVE").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Brand.success)
            }
        }
        .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 1).repeatForever()) { pulse = true } } }
    }
    @State private var pulse = false

    private var backRow: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.top, Space.s3)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(routeTitle)
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(idLine)
                .font(EType.mono(.caption)).tracking(0.3)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.top, Space.s3)
    }

    // MARK: Map hero

    private var mapHero: some View {
        RailTrackMap003(progress: progress ?? 0,
                        hasLive: liveCoord != nil,
                        originLabel: (detail?.originYard?.city ?? "ORIGIN").uppercased(),
                        destLabel: (detail?.destinationYard?.city ?? "RAMP").uppercased(),
                        etaText: etaChip,
                        speedText: speedChip,
                        reduceMotion: reduceMotion,
                        palette: palette)
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Formatted "MM-dd HH:mm" from the real estimatedArrivalAt, else nil.
    private var etaDisplay: String? {
        guard let iso = detail?.estimatedArrivalAt else { return nil }
        let inF = ISO8601DateFormatter(); inF.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = inF.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return nil }
        let out = DateFormatter(); out.dateFormat = "MM-dd HH:mm"
        return out.string(from: date)
    }

    private var etaChip: String {
        if let e = etaDisplay { return "ETA · \(e)" }
        return "ETA · \(detail?.destinationYard?.city ?? "pending")"
    }

    private var speedChip: String {
        // Speed is not a first-class field on the tracking payload; surface the
        // live fix description when present, else an honest position label.
        if let desc = tracking?.currentLocation?.description, !desc.isEmpty { return desc }
        if let loc = lastEvent?.location?.description, !loc.isEmpty { return loc }
        return "position live"
    }

    // MARK: Live status strip

    private var liveStatusStrip: some View {
        HStack(spacing: Space.s3) {
            Circle().fill(Brand.success).frame(width: 8, height: 8)
                .opacity(reduceMotion ? 1 : (pulse ? 0.3 : 1))
            Text(carSummary)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Space.s2)
            Text(updatedAgo)
                .font(EType.caption).foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, Space.s4)
        .frame(height: 32)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: In-transit meter card

    private var meterCard: some View {
        let pct = Int((progress ?? 0) * 100)
        return HStack(alignment: .center, spacing: Space.s4) {
            // Circular gauge — real fraction, honest "—" ring if no live fix.
            ZStack {
                Circle().stroke(palette.textPrimary.opacity(0.10), lineWidth: 6)
                    .frame(width: 52, height: 52)
                Circle().trim(from: 0, to: progress ?? 0)
                    .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 52, height: 52).rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(progress == nil ? "—" : "\(pct)%")
                        .font(.system(size: 14, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text("TO RAMP").font(.system(size: 7, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("REMAINING").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Text(remainingMiles.map { "\(Int($0)) mi" } ?? "—")
                    .font(.system(size: 22, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text("ETA · RAMP").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Text(etaDisplay ?? detail?.destinationYard?.code ?? "—")
                    .font(.system(size: 18, weight: .bold)).monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            Text("● LIVE").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(Brand.success).padding(Space.s3)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(LinearGradient.diagonal.opacity(0.5), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: ESang arrival-plan card

    private var arrivalPlanCard: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text("ESANG · ARRIVAL PLAN")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Text(arrivalHeadline)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(arrivalSub)
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var arrivalHeadline: String {
        guard let pct = progress else { return "Awaiting first live position fix" }
        if pct >= 0.9 { return "Approaching ramp — pre-stage the dray now" }
        if pct >= 0.5 { return "On plan to \(detail?.destinationYard?.city ?? "ramp")" }
        return "Early transit — \(remainingMiles.map { "\(Int($0)) mi" } ?? "en route") to go"
    }
    private var arrivalSub: String {
        let road = detail?.destinationRailroad ?? detail?.originRailroad
        let where0 = tracking?.currentLocation?.description ?? lastEvent?.description
        return [where0, road.map { "on \($0)" }].compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Live-events timeline

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("LIVE EVENTS · EUSOTRIP NETWORK")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if events.isEmpty {
                EusoEmptyState(systemImage: "dot.radiowaves.up.forward",
                               title: "No events yet",
                               subtitle: "Milestones stream in as the block moves.")
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(events.prefix(4).enumerated()), id: \.element.rowId) { idx, e in
                        eventRow(e, isFirst: idx == 0, isLast: idx == min(events.count, 4) - 1)
                    }
                }
                .padding(Space.s4)
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func eventRow(_ e: RailEvent003, isFirst: Bool, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            VStack(spacing: 0) {
                Group {
                    if isFirst { Circle().fill(LinearGradient.diagonal) }
                    else { Circle().fill(palette.bgCard).overlay(Circle().strokeBorder(palette.textTertiary, lineWidth: 2)) }
                }
                .frame(width: isFirst ? 12 : 12, height: 12).padding(.top, 2)
                if !isLast {
                    Rectangle().fill(palette.textPrimary.opacity(0.10)).frame(width: 1.5).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top) {
                    Text(eventTitle(e))
                        .font(.system(size: 13, weight: isFirst ? .bold : .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: Space.s2)
                    Text(e.timestamp.map { Self.relative($0) } ?? "")
                        .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
                if let sub = e.location?.description ?? e.eventType, !sub.isEmpty {
                    Text(sub.replacingOccurrences(of: "_", with: " "))
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.bottom, isLast ? 0 : Space.s3)
        }
    }

    private func eventTitle(_ e: RailEvent003) -> String {
        if let d = e.description, !d.isEmpty { return d }
        return (e.eventType ?? "Event").replacingOccurrences(of: "_", with: " ").capitalized
    }

    // MARK: Action banner + CTA pair

    private func actionBannerView(_ text: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: actionIsError ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(actionIsError ? Brand.danger : Brand.success)
            Text(text).font(EType.caption)
                .foregroundStyle(actionIsError ? Brand.danger : palette.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((actionIsError ? Brand.danger : Brand.success).opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder((actionIsError ? Brand.danger : Brand.success).opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Per-car positions", action: openPerCar)
            Button(action: { Task { await shareETA() } }) {
                Text(sharing ? "Sharing…" : "Share ETA")
                    .font(EType.title).foregroundStyle(palette.textPrimary)
                    .frame(width: 130, height: 52)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Load + actions

    private func load() async {
        loading = true; loadError = nil
        struct DetailIn: Encodable { let id: Int }
        struct TrackIn: Encodable { let shipmentId: Int }
        do {
            async let d: RailDetail003 = EusoTripAPI.shared.query(
                "railShipments.getRailShipmentDetail", input: DetailIn(id: shipmentId))
            async let t: RailTracking003 = EusoTripAPI.shared.query(
                "railShipments.getRailTracking", input: TrackIn(shipmentId: shipmentId))
            let (dd, tt) = try await (d, t)
            self.detail = dd
            self.tracking = tt
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// Per-car positions drill-in → getRailcars for this shipment. Posts the
    /// intent so the surrounding router opens the per-car sheet; never a dead tap.
    private func openPerCar() {
        NotificationCenter.default.post(
            name: Notification.Name("eusoRailcarPositions"), object: nil,
            userInfo: ["shipmentId": shipmentId])
        actionIsError = false
        actionBanner = "Opening per-car positions for \(detail?.shipmentNumber ?? "this block")"
    }

    private func shareETA() async {
        guard !sharing else { return }
        sharing = true; actionBanner = nil
        struct ShareIn: Encodable { let shipmentId: Int; let mode: String }
        struct ShareOut: Decodable { let url: String?; let token: String? }
        do {
            let out: ShareOut = try await EusoTripAPI.shared.mutation(
                "tracking.shareTrackingLink", input: ShareIn(shipmentId: shipmentId, mode: "rail"))
            actionIsError = false
            actionBanner = out.url.map { "Tracking link ready · \($0)" } ?? "Tracking link created."
        } catch {
            actionIsError = true
            actionBanner = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        sharing = false
    }

    // MARK: Loading / error scaffolds

    private var skeleton: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 190)
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 80)
            }
        }
    }

    private func errorCard(_ err: String) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.4)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

// MARK: - Map hero (route arc + origin pin + ramp geofence + live consist)

private struct RailTrackMap003: View {
    let progress: Double
    let hasLive: Bool
    let originLabel: String
    let destLabel: String
    let etaText: String
    let speedText: String
    let reduceMotion: Bool
    let palette: Theme.Palette

    @State private var breathe = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let origin = CGPoint(x: 0.10 * w, y: 0.72 * h)
            let dest   = CGPoint(x: 0.90 * w, y: 0.62 * h)
            let route = Path { p in
                p.move(to: origin)
                p.addCurve(to: dest,
                           control1: CGPoint(x: 0.38 * w, y: 0.30 * h),
                           control2: CGPoint(x: 0.66 * w, y: 0.40 * h))
            }
            let live = pointOnPath(route, at: min(max(progress, 0), 1)) ?? origin

            ZStack {
                LinearGradient(colors: [Color(hex: 0x11161D), Color(hex: 0x0A0D12)],
                               startPoint: .top, endPoint: .bottom)
                // faint network grid
                Path { p in
                    for r in stride(from: 0.28, through: 0.85, by: 0.28) {
                        p.move(to: CGPoint(x: 0, y: r*h)); p.addLine(to: CGPoint(x: w, y: r*h))
                    }
                    for c in stride(from: 0.25, through: 0.85, by: 0.25) {
                        p.move(to: CGPoint(x: c*w, y: 0)); p.addLine(to: CGPoint(x: c*w, y: h))
                    }
                }.stroke(Color.white.opacity(0.06), lineWidth: 0.8)

                // dashed remainder
                route.trim(from: min(max(progress, 0), 1), to: 1)
                    .stroke(palette.textTertiary.opacity(0.7),
                            style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [2, 6]))
                // completed
                route.trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 3.4, lineCap: .round))

                // origin pin
                ZStack {
                    Circle().fill(.white).frame(width: 15, height: 15)
                    Circle().fill(LinearGradient.diagonal).frame(width: 11, height: 11)
                }.position(origin)

                // destination ramp geofence
                ZStack {
                    Circle().fill(Brand.success.opacity(breathe ? 0.10 : 0.30))
                        .frame(width: breathe ? 52 : 40, height: breathe ? 52 : 40)
                    Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.4, dash: [3, 4]))
                        .foregroundStyle(Brand.success.opacity(0.85)).frame(width: 44, height: 44)
                    Circle().fill(.white).frame(width: 15, height: 15)
                    Circle().fill(Brand.magenta).frame(width: 11, height: 11)
                }.position(dest)

                // live consist marker
                if hasLive {
                    RailConsistMarker003(reduceMotion: reduceMotion)
                        .position(live)
                }

                // pin labels
                Text(originLabel).font(.system(size: 8, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .position(x: origin.x + 6, y: origin.y - 16)
                Text(destLabel).font(.system(size: 8, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .position(x: dest.x, y: dest.y - 28)

                // ETA chip (top) + speed chip (mid) + attribution
                VStack {
                    HStack {
                        Spacer()
                        chip(etaText, color: palette.textPrimary)
                    }
                    Spacer()
                    HStack {
                        chip(speedText, color: Brand.success)
                        Spacer()
                    }
                }
                .padding(Space.s3)

                VStack {
                    Spacer()
                    HStack {
                        Text("EusoTrip Network").font(.system(size: 7, weight: .bold)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Spacer()
                    }
                }.padding(Space.s2)
            }
        }
        .onAppear {
            if !reduceMotion { withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true } }
        }
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold)).tracking(0.2).monospacedDigit()
            .foregroundStyle(color).lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color(hex: 0x1C2128)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10)))
    }
}

/// Compact animated rail-consist marker (loco body + wheels + gentle bob).
private struct RailConsistMarker003: View {
    let reduceMotion: Bool
    @State private var bob = false
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Brand.blue.opacity(0.5), .clear],
                                         center: .center, startRadius: 0, endRadius: 22))
                .frame(width: 44, height: 44)
                .opacity(reduceMotion ? 0.7 : (bob ? 0.3 : 0.9))
            HStack(spacing: 2) {
                wheelCar(color: Color(hex: 0x607D8B))
                wheelCar(color: Brand.info)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: 0x2B85FF), Color(hex: 0xA726E8)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 20, height: 12)
                    .overlay(alignment: .trailing) {
                        RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.85))
                            .frame(width: 5, height: 4).padding(.trailing, 2)
                    }
            }
            .offset(y: reduceMotion ? 0 : (bob ? -1.5 : 0))
        }
        .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { bob = true } } }
    }
    private func wheelCar(color: Color) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color(hex: 0x2A313B))
            .frame(width: 16, height: 7)
            .overlay(RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 11, height: 4).offset(y: -3))
    }
}

// MARK: - Path sampling helper

/// Approximate the point at fraction `t` along a Path by flattening it.
private func pointOnPath(_ path: Path, at t: CGFloat) -> CGPoint? {
    let clamped = min(max(t, 0), 1)
    var points: [CGPoint] = []
    path.forEach { el in
        switch el {
        case .move(let p): points.append(p)
        case .line(let p): points.append(p)
        case .quadCurve(let p, let c):
            if let last = points.last { for i in 1...12 { let s = CGFloat(i)/12; points.append(quad(last, c, p, s)) } }
        case .curve(let p, let c1, let c2):
            if let last = points.last { for i in 1...16 { let s = CGFloat(i)/16; points.append(cubic(last, c1, c2, p, s)) } }
        case .closeSubpath: break
        }
    }
    guard points.count > 1 else { return points.first }
    var lengths: [CGFloat] = [0]; var total: CGFloat = 0
    for i in 1..<points.count { total += dist(points[i-1], points[i]); lengths.append(total) }
    guard total > 0 else { return points.first }
    let target = clamped * total
    for i in 1..<points.count where lengths[i] >= target {
        let seg = lengths[i] - lengths[i-1]
        let f = seg > 0 ? (target - lengths[i-1]) / seg : 0
        return CGPoint(x: points[i-1].x + (points[i].x - points[i-1].x)*f,
                       y: points[i-1].y + (points[i].y - points[i-1].y)*f)
    }
    return points.last
}
private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x-b.x, a.y-b.y) }
private func quad(_ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint, _ t: CGFloat) -> CGPoint {
    let u = 1-t
    return CGPoint(x: u*u*p0.x + 2*u*t*c.x + t*t*p1.x, y: u*u*p0.y + 2*u*t*c.y + t*t*p1.y)
}
private func cubic(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p1: CGPoint, _ t: CGFloat) -> CGPoint {
    let u = 1-t
    let x = u*u*u*p0.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*p1.x
    let y = u*u*u*p0.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*p1.y
    return CGPoint(x: x, y: y)
}

// MARK: - Previews

#Preview("003 · Rail Live Tracking · Night") {
    RailLiveTrackingShipperScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("003 · Rail Live Tracking · Light") {
    RailLiveTrackingShipperScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
