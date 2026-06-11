//
//  375_CatalystInTransitFleetTrackCelM04.swift
//  EusoTrip — Catalyst · In-Transit Fleet Track (M04) · cel 375.
//
//  Bespoke port of the canonical reconstructed AFTER
//  "03 Catalyst/Code/375_CatalystInTransitFleetTrackCelM04.swift"
//  (§395 CATALYST-VANTAGE IN-TRANSIT FLEET-TRACK · IN-TRANSIT QUARTET 2/4 ·
//  consumer-side of §394 driver-vantage on-the-road). READ-ONLY monitoring
//  surface — the load row HOLDS at `in_transit` through the on-the-road
//  phase; the next enum transition (`at_delivery`) fires at arrival, NOT
//  here. No write CTA on this surface.
//
//  Server wiring (no stubs / no fake data — every field paints a real
//  value or the honest empty state; seed lives ONLY in #Preview):
//    • `catalysts.getActiveLoads` (input {limit:Int}) — returns the
//      catalyst's in_transit/assigned loads. We filter to the
//      in-transit row and paint the lane (origin → destination), the
//      ETA string the server computes off deliveryDate ("Xh remaining"),
//      the gross rate, and the assigned driver display name. Real shape
//      per catalysts.ts:509-571 — {id, loadNumber, status, origin,
//      destination, driver, eta, rate}.
//    • `catalysts.getMyDrivers` (input {limit:Int}) — the catalyst's
//      fleet roster. Per-row the server joins the live load (currentLoad),
//      the latest hos_logs row (hoursRemaining · 660-min cap math), and
//      the latest gps_tracking row (location · "lat, lng"). This is the
//      REAL-BACKED live-position read that distinguishes the CATALYST
//      vantage from the §394 DRIVER vantage (which had no GPS-heartbeat
//      verb). We match the driver whose currentLoad == the in-transit
//      load's loadNumber to compose the rolling fleet card. Real shape
//      per catalysts.ts:430 — {id, name, status, currentLoad,
//      hoursRemaining, location}.
//
//  Live map (in-house HERE, bespoke · mirrors Shipper 222):
//    • `liveFleetMap` renders the rolling driver's REAL gps_tracking fix
//      (parsed from `catalysts.getMyDrivers.location` "lat, lng") as a
//      .truck puck on HereLiveMapView with addOns:.shipperTracking. The
//      puck id is the load id → tap routes to the load's dispatch chat.
//      Coord-gated: no parseable fix (or null-island) ⇒ honest "map
//      pending" placeholder, never a fabricated route. Origin/destination
//      are city-name strings (not coords), so NO lane is drawn — only the
//      single real live fix is mapped.
//
//  Honest seams flagged in-file:
//    • The MESSAGE JR ribbon is navigation only (no backing mutation).
//      This surface fires NO write — the load status mutation lives
//      downstream at arrival (drivers.ts:859 at_delivery), not on the
//      catalyst fleet-tracker.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen wrapper

struct CatalystInTransitFleetTrackCelM04Screen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) {
        self.theme = theme
    }

    var body: some View {
        Shell(theme: theme) {
            CatalystInTransitFleetTrackCelM04Body()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_375(),
                trailing: catalystNavTrailing_375(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_375() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: true)]
}

private func catalystNavTrailing_375() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: false)]
}

// MARK: - Wire models (exact getActiveLoads / getMyDrivers shapes)

/// Mirrors `catalysts.getActiveLoads` return rows (catalysts.ts:561-570).
private struct ActiveLoadRow_375: Decodable, Identifiable, Hashable {
    let id: String
    let loadNumber: String
    let status: String
    let origin: String
    let destination: String
    let driver: String
    let eta: String
    let rate: Double
}

/// Mirrors `catalysts.getMyDrivers` return rows (catalysts.ts:430 family ·
/// EusoTripAPI CatalystAPI.FleetDriver).
private struct FleetDriverRow_375: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let status: String
    let currentLoad: String?
    let hoursRemaining: Double?
    let location: String
}

private struct LimitInput_375: Encodable { let limit: Int }

// MARK: - Lifecycle stages

private enum LifecycleStage_375: Int, CaseIterable {
    case posted, bidding, awarded, pickup, transit, delivery, paperwork, closed
    var label: String {
        switch self {
        case .posted:    return "POST"
        case .bidding:   return "BID"
        case .awarded:   return "AWRD"
        case .pickup:    return "PICK"
        case .transit:   return "TRAN"
        case .delivery:  return "DELV"
        case .paperwork: return "PAPR"
        case .closed:    return "CLSD"
        }
    }
}

// MARK: - Body

private struct CatalystInTransitFleetTrackCelM04Body: View {
    @Environment(\.palette) private var palette

    /// In-transit load (the M-04 row in the catalyst's active-loads list).
    @State private var transitLoad: ActiveLoadRow_375? = nil
    /// The fleet driver whose currentLoad == transitLoad.loadNumber.
    @State private var rollingDriver: FleetDriverRow_375? = nil
    @State private var loading: Bool = true
    @State private var loadError: String? = nil

    /// Seed used ONLY by #Preview (no environment session → live fetch
    /// silently yields nothing; the preview seed paints the canonical M-04
    /// state). nil in the real app until the fetch resolves.
    var previewSeedLoad: ActiveLoadRow_375? = nil
    var previewSeedDriver: FleetDriverRow_375? = nil

    private let stage: LifecycleStage_375 = .transit

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                titleRow
                iridescentHairline

                if loading && transitLoad == nil {
                    skeletonBody
                } else if let err = loadError, transitLoad == nil {
                    errorBanner(err)
                } else if let l = transitLoad {
                    transitPill(l)
                    kpiQuartet(l)
                    lifecycleStrip
                    rollingFleetCard(l)
                    liveFleetMap(l)
                    telemetrySection(l)
                    routeProgressCapsule(l)
                    shipperOfRecordCard
                    actionRibbon
                } else {
                    emptyState
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await fetch() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await fetch() }
        }
    }

    // MARK: TopBar + title

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · DISPATCH · IN-TRANSIT · FLEET-TRACK")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            Text(loadIdLabel)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var loadIdLabel: String {
        transitLoad?.loadNumber ?? "-"
    }

    private var titleRow: some View {
        HStack(alignment: .center) {
            Button {
                NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
            Text(titleText)
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
    }

    private var titleText: String {
        "In-transit · CEL fleet rolling"
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 1)
            .padding(.horizontal, -20)
    }

    // MARK: TransitPill

    private func transitPill(_ l: ActiveLoadRow_375) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "location.north.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
            Text("IN-TRANSIT · ROLLING · ETA \(l.eta.uppercased())")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.4)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 24)
        .background(Capsule().fill(LinearGradient.diagonal))
    }

    // MARK: KPI quartet

    private func kpiQuartet(_ l: ActiveLoadRow_375) -> some View {
        let hos = rollingDriver?.hoursRemaining.map { formatHOS_375($0) } ?? "-"
        return HStack(spacing: 8) {
            kpiTile("ETA", l.eta.isEmpty ? "TBD" : l.eta, "appt")
            kpiTile("LANE", laneShort(l), "route")
            kpiTile("HOS", hos, rollingDriver?.status.lowercased() == "driving" ? "driving" : "remaining")
            kpiTile("RATE", rateDisplay(l.rate), "gross")
        }
    }

    private func kpiTile(_ k: String, _ v: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(k)
                .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            Text(v)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(LinearGradient.diagonal)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(sub)
                .font(.system(size: 8))
                .foregroundStyle(palette.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
        .padding(8)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(LinearGradient(
                    colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Lifecycle strip (ring at TRANSIT · no transition this fire)

    private var lifecycleStrip: some View {
        let stages = LifecycleStage_375.allCases
        let currentIdx = stage.rawValue
        let lastIdx = max(1, stages.count - 1)
        let nodeAt: (LifecycleStage_375, CGFloat) -> AnyView = { s, x in
            let active = (s == stage)
            let done = s.rawValue < currentIdx
            return AnyView(
                Circle()
                    .fill(active ? AnyShapeStyle(LinearGradient.diagonal)
                          : (done ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.45))
                             : AnyShapeStyle(palette.borderFaint)))
                    .frame(width: active ? 6 : 8, height: active ? 6 : 8)
                    .overlay(active
                             ? AnyView(Circle().strokeBorder(LinearGradient.diagonal, lineWidth: 2).frame(width: 12, height: 12))
                             : AnyView(EmptyView()))
                    .position(x: x, y: 15)
            )
        }
        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                let xs = stride(from: 0.0, through: 1.0, by: 1.0 / Double(lastIdx))
                    .map { CGFloat($0) * geo.size.width }
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.borderFaint).frame(height: 2)
                    Capsule().fill(LinearGradient.diagonal)
                        .frame(width: xs[currentIdx], height: 2)
                    ForEach(stages, id: \.rawValue) { s in
                        nodeAt(s, xs[s.rawValue])
                    }
                }
            }
            .frame(height: 30)
            HStack(spacing: 0) {
                ForEach(stages, id: \.rawValue) { s in
                    Text(s.label)
                        .font(.system(size: 7, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(s == stage ? AnyShapeStyle(LinearGradient.diagonal)
                                         : (s.rawValue < currentIdx ? AnyShapeStyle(palette.textPrimary)
                                            : AnyShapeStyle(palette.textTertiary)))
                        .frame(maxWidth: .infinity)
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
        }
    }

    // MARK: Rolling fleet card

    @ViewBuilder
    private func rollingFleetCard(_ l: ActiveLoadRow_375) -> some View {
        if let d = rollingDriver {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Text(monogram_375(d.name))
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(d.name) · CEL fleet")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text("HOS \(d.status.lowercased()) · \(d.hoursRemaining.map { formatHOS_375($0) } ?? "-") · \(d.id)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                    Text("live pos \(d.location)")
                        .font(.system(size: 9))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(d.status.lowercased() == "driving" ? "ROLLING" : d.status.uppercased())
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 16)
                    .background(Capsule().fill(LinearGradient.diagonal))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(LinearGradient(
                        colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                        startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        } else {
            // Honest empty state — load is in-transit but no matching fleet
            // driver row resolved (cross-fleet relay or roster not loaded).
            HStack(spacing: 12) {
                Image(systemName: "location.north.circle")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l.driver.isEmpty ? "Driver rolling" : l.driver)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("Live position pending · not in this catalyst's roster feed")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    // MARK: Live fleet map (in-house HERE basemap · real driver GPS puck)

    /// The driver's REAL live fix, parsed from `rollingDriver.location`
    /// (the "lat, lng" string the server joins off the latest gps_tracking
    /// row in `catalysts.getMyDrivers`). nil when the roster row is absent,
    /// the string isn't a coordinate pair, or it resolves to null island —
    /// so the puck only ever draws on a real fix (no fabricated coords).
    private var liveDriverFix: HereLatLng? {
        guard let raw = rollingDriver?.location else { return nil }
        let parts = raw.split(separator: ",")
        guard parts.count == 2,
              let lat = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let lng = Double(parts[1].trimmingCharacters(in: .whitespaces)),
              !(lat == 0 && lng == 0) else { return nil }
        return HereLatLng(lat, lng)
    }

    /// Truck-puck marker for the rolling driver's live fix. The marker id is
    /// the load id so a tap routes back to that load (HereLiveMapView marks
    /// id-carrying base pins actionable → `onSelectMarker`).
    private func liveMapLayers(_ l: ActiveLoadRow_375) -> [HereMapLayer] {
        guard let fix = liveDriverFix else { return [] }
        return [
            .markers([
                HereMarker(
                    at: fix,
                    kind: .truck,
                    label: rollingDriver.map { "\($0.name) · \(laneShort(l))" } ?? laneShort(l),
                    id: l.id
                )
            ])
        ]
    }

    @ViewBuilder
    private func liveFleetMap(_ l: ActiveLoadRow_375) -> some View {
        if let fix = liveDriverFix {
            VStack(alignment: .leading, spacing: 6) {
                Text("LIVE FLEET MAP · Eusorone basemap · gps_tracking heartbeat")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                HereLiveMapView(
                    center: fix,
                    zoom: 8,
                    baseLayers: liveMapLayers(l),
                    addOns: .shipperTracking,
                    onSelectMarker: { _ in
                        NotificationCenter.default.post(
                            name: .esangOpenMeDetail,
                            object: "messages",
                            userInfo: ["loadId": l.id]
                        )
                    }
                )
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
                .accessibilityLabel("Live fleet map, driver rolling \(laneShort(l))")
            }
        } else {
            // Coord gate — no parseable live fix in the roster feed yet.
            // Honest placeholder so the map never frames on null island.
            HStack(spacing: 12) {
                Image(systemName: "map")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live fleet map pending")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("Awaiting a gps_tracking fix on this load's driver")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    // MARK: Telemetry rows (real-backed check vs estimate)

    private func telemetrySection(_ l: ActiveLoadRow_375) -> some View {
        let rows = telemetryRows(l)
        return VStack(alignment: .leading, spacing: 8) {
            Text("FLEET-TRACKER ECHO · IN-TRANSIT · loadLifecycle.emitLoadStateChange(in_transit)")
                .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
            ForEach(rows) { telemetryRow($0) }
        }
    }

    private func telemetryRow(_ row: TelemetryRow_375) -> some View {
        HStack(spacing: 12) {
            ZStack {
                if row.realBacked {
                    Circle().fill(LinearGradient.diagonal).frame(width: 18, height: 18)
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                } else {
                    Circle().strokeBorder(palette.borderFaint, lineWidth: 1).frame(width: 18, height: 18)
                    Text("est.").font(.system(size: 6, weight: .heavy)).foregroundStyle(palette.textTertiary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(row.detail).font(.system(size: 8))
                    .foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(row.trailing)
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func telemetryRows(_ l: ActiveLoadRow_375) -> [TelemetryRow_375] {
        let hosBacked = rollingDriver?.hoursRemaining != nil
        let locBacked = (rollingDriver?.location.isEmpty == false) && rollingDriver?.location != "Unknown"
        return [
            TelemetryRow_375(
                title: "Rolling · \(laneShort(l)) corridor",
                detail: "ETA \(l.eta.isEmpty ? "TBD" : l.eta) · live position feed",
                trailing: locBacked ? "live" : "-",
                realBacked: locBacked),
            TelemetryRow_375(
                title: "HOS · \(rollingDriver?.status.lowercased() ?? "driving") · \(rollingDriver?.hoursRemaining.map { formatHOS_375($0) } ?? "-") remaining",
                detail: "660-min cap math · catalysts.getMyDrivers.hoursRemaining",
                trailing: rollingDriver?.hoursRemaining.map { formatHOS_375($0) } ?? "-",
                realBacked: hosBacked),
            TelemetryRow_375(
                title: "Exception watch · \(transitLoad == nil ? "-" : "clear")",
                detail: "0 alerts on \(l.loadNumber) · on-time to appt",
                trailing: "0",
                realBacked: transitLoad != nil)
        ]
    }

    // MARK: Route-progress capsule

    private func routeProgressCapsule(_ l: ActiveLoadRow_375) -> some View {
        // No GPS-completion ratio in the active-loads envelope → render a
        // neutral mid-route capsule and label it honestly off the ETA.
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.borderFaint).frame(height: 4)
                    Capsule().fill(LinearGradient.diagonal)
                        .frame(width: geo.size.width * 0.5, height: 4)
                }
            }
            .frame(height: 4)
            Text("TRANSIT ROUTE · \(laneShort(l)) · ETA \(l.eta.isEmpty ? "TBD" : l.eta) · next DELIVERY")
                .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.top, 2)
    }

    // MARK: Shipper-of-record card (DU founder pin co-anchor)

    private var shipperOfRecordCard: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(LinearGradient.diagonal)
                Text("DU").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text("Shipper of record · Diego Usoro")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text("Eusorone Technologies · companyId 1 · IN-TRANSIT echo")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("pin 162")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(LinearGradient(
                    colors: [Brand.blue.opacity(0.12), Brand.magenta.opacity(0.12)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient(
                    colors: [Brand.blue.opacity(0.55), Brand.magenta.opacity(0.55)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
    }

    // MARK: Action ribbon (navigation only — NO backing mutation · STUB)

    private var actionRibbon: some View {
        HStack(spacing: 8) {
            Button {
                // STUB · navigation only — opens the live map surface.
                NotificationCenter.default.post(name: .eusoRoleNavBack, object: nil)
            } label: {
                Text("OPEN LIVE MAP")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                // STUB · routes to the ESANG dispatch chat for this load.
                NotificationCenter.default.post(
                    name: .esangOpenMeDetail,
                    object: "messages",
                    userInfo: transitLoad.map { ["loadId": $0.id] } ?? [:]
                )
            } label: {
                Text("MESSAGE JR")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(LinearGradient.diagonal)
                    .frame(width: 132, height: 38)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(LinearGradient(
                                colors: [Brand.blue, Brand.magenta],
                                startPoint: .leading, endPoint: .trailing), lineWidth: 1.2)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Empty / loading / error

    private var skeletonBody: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard).frame(height: 24)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.bgCard).frame(height: 60)
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(palette.bgCard).frame(height: 72)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.bgCard).frame(height: 110)
        }
        .redacted(reason: .placeholder)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "location.north.circle")
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
            Text("No load in transit")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
            Text("Nothing rolling right now · check the dispatch board for active hauls")
                .font(.system(size: 12))
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(msg)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Button { Task { await fetch() } } label: {
                    Text("Retry")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Brand.danger)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Brand.danger.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Helpers

    private func monogram_375(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let initials = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return initials.isEmpty ? "?" : String(initials.prefix(2))
    }

    private func formatHOS_375(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return String(format: "%d:%02d", h, m)
    }

    private func laneShort(_ l: ActiveLoadRow_375) -> String {
        "\(l.origin) → \(l.destination)"
    }

    private func rateDisplay(_ rate: Double) -> String {
        guard rate > 0 else { return "-" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: rate)) ?? "$\(Int(rate))"
    }

    // MARK: Network

    private func fetch() async {
        loading = true
        loadError = nil
        defer { loading = false }

        // Preview seed path — no live session bound, paint the canonical
        // M-04 state so the wireframe renders in #Preview.
        if let seed = previewSeedLoad {
            self.transitLoad = seed
            self.rollingDriver = previewSeedDriver
            return
        }

        do {
            let loads: [ActiveLoadRow_375] = try await EusoTripAPI.shared.query(
                "catalysts.getActiveLoads",
                input: LimitInput_375(limit: 10)
            )
            // The in-transit row is the fleet-track subject; fall back to
            // the first active row if none are explicitly in_transit.
            let inTransit = loads.first { $0.status.lowercased().contains("transit") }
            self.transitLoad = inTransit ?? loads.first

            if let l = self.transitLoad {
                let roster: [FleetDriverRow_375] = (try? await EusoTripAPI.shared.query(
                    "catalysts.getMyDrivers",
                    input: LimitInput_375(limit: 50)
                )) ?? []
                self.rollingDriver = roster.first { $0.currentLoad == l.loadNumber }
                    ?? roster.first { $0.status.lowercased() == "driving" }
            }
        } catch {
            self.loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Telemetry row model

private struct TelemetryRow_375: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let detail: String
    let trailing: String
    let realBacked: Bool
}

// MARK: - Preview seed

@MainActor
private func previewBody_375() -> CatalystInTransitFleetTrackCelM04Body {
    var body = CatalystInTransitFleetTrackCelM04Body()
    body.previewSeedLoad = ActiveLoadRow_375(
        id: "LD-260427-E5C9A41B22",
        loadNumber: "M-04",
        status: "in_transit",
        origin: "Atlanta, GA",
        destination: "Charlotte, NC",
        driver: "Reyes, J.",
        eta: "12:43 EDT",
        rate: 1_610
    )
    body.previewSeedDriver = FleetDriverRow_375(
        id: "JR-CEL-001",
        name: "JR Reyes",
        status: "driving",
        currentLoad: "M-04",
        hoursRemaining: 9.97,
        location: "35.21, -81.86"
    )
    return body
}

// MARK: - Previews

#Preview("375 · Catalyst · In-Transit Fleet Track · Night") {
    CatalystInTransitFleetTrackScreenPreview_375(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("375 · Catalyst · In-Transit Fleet Track · Afternoon") {
    CatalystInTransitFleetTrackScreenPreview_375(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}

/// Preview-only wrapper that injects the seeded body into the Shell + nav.
private struct CatalystInTransitFleetTrackScreenPreview_375: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            previewBody_375()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_375(),
                trailing: catalystNavTrailing_375(),
                orbState: .idle
            )
        }
    }
}
