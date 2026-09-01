//
//  VesselOceanTrackMap.swift
//  EusoTrip — live AIS ocean-tracking map for 003 Vessel Live Tracking.
//
//    • the latest authorized AIS/terminal observation from
//      `liveOperations.latestForAsset`,
//    • origin / destination port pins,
//    • the speed / heading / coords callout chip + ETA — driven by the live
//      AIS fix, NOT static.
//
//  The old direct MarineTraffic reads are deliberately not used here. The
//  server resolves the exact vessel through tenant access, provider licence,
//  consent, freshness, and immutable evidence before returning a position.
//
//  When the AIS feed is unavailable, the labeled basemap and real booking-port
//  markers remain visible without inventing a marine route.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Live store

@MainActor
final class VesselOceanTrackStore: ObservableObject {
    @Published var result: LiveOperationsClient.AssetResult?
    @Published var loadError: String?
    @Published var loading = true

    func load(imoNumber: String) async {
        loading = true; loadError = nil
        do {
            result = try await LiveOperationsClient.shared.latestVessel(
                imoNumber: imoNumber
            )
        } catch {
            self.loadError = error.eusoUserCopy
            result = nil
        }
        self.loading = false
    }

    func clear() {
        result = nil
        loadError = nil
        loading = false
    }

    var position: LiveOperationsClient.Observation? { result?.observation }
}

// MARK: - Live ocean-track map

struct VesselOceanTrackMap: View {
    /// Vessel IMO that keys the AIS feed.
    let imoNumber: String
    /// Exact canonical freight subject. Without it the map can show licensed
    /// observations and ports, but it cannot request or render voyage geometry.
    let vesselShipmentId: Int?
    /// Exact server purpose expected by this surface. Active tracking defaults
    /// to active_job; planning/weather previews may explicitly request planning.
    let routePurpose: CanonicalRoutePlanClient.Purpose
    /// Authored booking origin (port of loading).
    let origin: HereLatLng
    /// Authored booking destination (port of discharge).
    let destination: HereLatLng
    /// Origin / destination labels for the port pins.
    let originLabel: String
    let destinationLabel: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.palette) private var palette
    @StateObject private var store = VesselOceanTrackStore()
    @StateObject private var nearbyVesselStore = LiveOperationsNearbyStore(mode: .vessel)
    @State private var canonicalRoute: CanonicalRoutePlanClient.BoundRoutePlan?
    @State private var canonicalRouteStatus: String?

    init(
        imoNumber: String,
        vesselShipmentId: Int? = nil,
        routePurpose: CanonicalRoutePlanClient.Purpose = .activeJob,
        origin: HereLatLng,
        destination: HereLatLng,
        originLabel: String,
        destinationLabel: String
    ) {
        self.imoNumber = imoNumber
        self.vesselShipmentId = vesselShipmentId
        self.routePurpose = routePurpose
        self.origin = origin
        self.destination = destination
        self.originLabel = originLabel
        self.destinationLabel = destinationLabel
    }

    /// True only for a finite, non-null-island fix. The (0,0) gate per
    /// D-maps-basemap — matches Escort 602's `validFix`. A reusable map surface
    /// must not trust its caller's coordinate validity blindly.
    private func validFix(_ lat: Double, _ lng: Double) -> Bool {
        LatLongParser.validatedCoordinate(latitude: lat, longitude: lng) != nil
    }

    /// Whether BOTH authored endpoint markers are real fixes. When false the
    /// component draws an honest awaiting seam and requests no route repair.
    private var endpointsValid: Bool {
        validFix(origin.lat, origin.lng) && validFix(destination.lat, destination.lng)
    }

    /// Live AIS coordinate (real fix), else `nil`. Coord-gated so a null-island
    /// AIS fix can't drop an orb on (0,0).
    private var aisCoord: HereLatLng? {
        store.position?.position.coordinate
    }

    private var aisObservationState: HereObservationState {
        if store.loadError != nil { return .degraded }
        return store.position?.markerState ?? .offline
    }

    private var aisLiveOperationsStatus: HereLiveOperationsStatus {
        if nearbyVesselStore.result != nil || nearbyVesselStore.errorMessage != nil {
            return nearbyVesselStore.status
        }
        guard aisCoord != nil else {
            return .init(
                availability: store.loadError == nil ? .empty : .degraded,
                sourceLabel: "AIS",
                detail: store.loadError == nil
                    ? "No authorized live feed"
                    : "AIS feed unavailable",
                observationCount: 0
            )
        }
        let observation = store.position
        let availability: HereLiveOperationsStatus.Availability
        if aisObservationState == .current,
           observation?.operationalUseAllowed == true {
            availability = .live
        } else if aisObservationState == .stale {
            availability = .stale
        } else {
            availability = .degraded
        }
        return .init(
            availability: availability,
            sourceLabel: observation?.provider.id ?? "Authorized vessel feed",
            freshnessLabel: observation?.freshnessState.rawValue ?? "unknown",
            detail: observation.map {
                "\($0.quality.state.rawValue) · \($0.asset.accessBasis) · area coverage not claimed"
            } ?? "No authorized live feed",
            observationCount: 1
        )
    }

    /// The callout chip text: speed / heading on line 1, coords on line 2 —
    /// VERBATIM to the 003 chip, but LIVE off the AIS fix.
    private var aisChipLabel: String? {
        guard let p = store.position,
              let coordinate = LatLongParser.validatedCoordinate(
                  latitude: p.position.latitude,
                  longitude: p.position.longitude
              ) else { return nil }
        let kn = p.position.speedMetersPerSecond
            .map { String(format: "%.1f kn", $0 / 0.5144444444) } ?? "- kn"
        let hdg = p.position.courseDegrees
            .map { String(format: "course %03.0f°", $0) } ?? "course -"
        let coords = LatLongParser.displayString(coordinate)
        return "\(kn) · \(hdg)\n\(coords)"
    }

    /// Map layers: real booking ports and the authorized reported position.
    /// Historical lines remain absent until an authorized observation-history
    /// contract exists; a sequence of raw AIS dots is not voyage route truth.
    private var layers: [HereMapLayer] {
        var out: [HereMapLayer] = []
        if let payload = canonicalRoute?.rendererPayload {
            for (index, line) in payload.lines.enumerated() {
                out.append(.eusoRoute(
                    polyline: line,
                    state: .active,
                    label: index == 0
                        ? "EusoMarine route plan version \(payload.identity.version)"
                        : nil
                ))
            }
        }
        out.append(
            .markers([
                HereMarker(at: origin, kind: .pickup, label: originLabel),
                HereMarker(at: destination, kind: .delivery, label: destinationLabel)
            ])
        )
        if let ais = aisCoord {
            out.append(.markers([
                HereMarker(
                    at: ais,
                    kind: .vessel,
                    label: aisChipLabel,
                    id: imoNumber,
                    observationState: aisObservationState,
                    sourceLabel: store.position?.provider.id ?? "Authorized vessel feed",
                    accessibilityLabel: "Vessel \(imoNumber), \(aisObservationState.displayName), \(store.position?.accessibleEvidenceLabel ?? "authorized observation evidence unavailable")"
                )
            ]))
        }
        if !nearbyVesselStore.markers.isEmpty {
            out.append(.markers(nearbyVesselStore.markers))
        }
        return out
    }

    /// Camera center: authorized observation, then endpoint midpoint. The
    /// midpoint is camera framing only, never route data.
    private var cameraCenter: HereLatLng {
        if let ais = aisCoord { return ais }
        if let routePoint = canonicalRoute?.rendererPayload?.lines.lazy.compactMap(\.first).first {
            return routePoint
        }
        let longitudeDelta = ((destination.lng - origin.lng + 540)
            .truncatingRemainder(dividingBy: 360)) - 180
        let midpointLongitude = ((origin.lng + longitudeDelta / 2 + 540)
            .truncatingRemainder(dividingBy: 360)) - 180
        return HereLatLng(
            (origin.lat + destination.lat) / 2,
            midpointLongitude
        )
    }

    var body: some View {
        Group {
            if endpointsValid {
                HereVectorMapView(
                    center: cameraCenter,
                    zoom: 4,
                    interactive: true,
                    tilt: 0,
                    layers: layers,
                    styleHint: .ocean,
                    mapModeContext: .primary(.vessel),
                    liveOperationsStatus: aisLiveOperationsStatus
                )
            } else {
                // Honest seam (matches Escort 602's `mapAwaitingSeam`): when the
                // authored origin/destination aren't real coordinates — non-finite
                // or null-island (0,0) — we render no route repair or invalid
                // port pins. Real coordinates only.
                mapAwaitingSeam
            }
        }
        // Frame guard (D-maps-basemap 2026-06-01): give the canvas a real
        // minimum height so a parent that lays it out with 0 height (the
        // historical frame.zero blank-bug trap) can't collapse it to nothing.
        // Callers that want a specific height still override with `.frame`.
        .frame(minHeight: 220)
        .task(id: imoNumber) {
            guard !imoNumber.isEmpty else {
                store.clear()
                return
            }
            while !Task.isCancelled {
                await store.load(imoNumber: imoNumber)
                do {
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                } catch {
                    break
                }
            }
        }
        .task(id: "\(vesselShipmentId ?? 0):\(routePurpose.rawValue)") {
            await loadCanonicalRoute()
        }
        .task(id: "vessel-nearby-\(cameraCenter.lat)-\(cameraCenter.lng)") {
            await nearbyVesselStore.poll(
                around: cameraCenter,
                radiusMeters: 200_000,
                limit: 150
            )
        }
        .overlay(alignment: .bottomLeading) {
            if let canonicalRouteStatus {
                Text(canonicalRouteStatus)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(palette.bgCard.opacity(0.92))
                    .overlay(Capsule().strokeBorder(Brand.warning.opacity(0.45)))
                    .clipShape(Capsule())
                    .padding(10)
                    .accessibilityLabel(canonicalRouteStatus)
            }
        }
    }

    @MainActor
    private func loadCanonicalRoute() async {
        canonicalRoute = nil
        canonicalRouteStatus = nil
        guard let vesselShipmentId, vesselShipmentId > 0 else {
            canonicalRouteStatus = "Canonical voyage subject unavailable · ports and authorized position only"
            return
        }

        do {
            let result = try await CanonicalRoutePlanClient.shared.planVesselShipment(
                id: vesselShipmentId,
                purpose: routePurpose
            )
            switch result {
            case .persisted(let persisted):
                applyCanonicalRoute(persisted.route)
            case .pending(let pending):
                canonicalRouteStatus = pending.blockers.first?.message
                    ?? "Canonical EusoMarine route pending verified profile and graph authority"
                await readExistingCanonicalRoute(vesselShipmentId: vesselShipmentId)
            }
        } catch {
            canonicalRouteStatus = error.eusoUserCopy
            await readExistingCanonicalRoute(vesselShipmentId: vesselShipmentId)
        }
    }

    @MainActor
    private func readExistingCanonicalRoute(vesselShipmentId: Int) async {
        do {
            let existing = try await CanonicalRoutePlanClient.shared.getBoundVesselShipment(
                id: vesselShipmentId
            )
            applyCanonicalRoute(existing)
        } catch {
            // Preserve a more specific planning blocker when one exists; when
            // it does not, expose the exact binding read failure.
            if canonicalRouteStatus == nil {
                canonicalRouteStatus = error.eusoUserCopy
            }
        }
    }

    @MainActor
    private func applyCanonicalRoute(_ route: CanonicalRoutePlanClient.BoundRoutePlan) {
        guard route.plan.purpose == routePurpose,
              route.plan.identity.mode == .vessel,
              route.rendererPayload != nil else {
            canonicalRoute = nil
            canonicalRouteStatus = "Canonical \(routePurpose.rawValue) voyage plan is present but not released for rendering"
            return
        }
        canonicalRoute = route
        canonicalRouteStatus = nil
    }

    /// Honest seam shown until the caller supplies real port coordinates. No
    /// map is drawn — the surface never fabricates a route across null island.
    private var mapAwaitingSeam: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "scope")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text("Awaiting port coordinates")
                    .font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("The map appears once the booking's ports are geocoded. Voyage geometry appears only after the route is verified; AIS observations remain position evidence.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

}
