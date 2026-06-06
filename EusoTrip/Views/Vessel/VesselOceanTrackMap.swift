//
//  VesselOceanTrackMap.swift
//  EusoTrip — the live great-circle ocean-tracking map for 003 Vessel Live
//  Tracking. Renders the native bespoke OCEAN register (`BespokeMapCanvas`
//  style: .ocean / .lightOcean) over a LIVE AIS track:
//
//    • great-circle polyline interpolated (slerp) origin → destination, so the
//      ocean route arcs correctly under Mercator,
//    • the live AIS vessel marker dropped at the real position from
//      `vesselShipments.liveVesselPosition` (the route splits solid/traveled →
//      dashed/remaining at THIS coordinate inside the canvas),
//    • origin / destination port pins,
//    • the speed / heading / coords callout chip + ETA — driven by the live
//      AIS fix, NOT static.
//
//  Data: `EusoTripAPI.shared.vesselTrack` →
//    liveVesselPosition(imoNumber)  (the AIS orb + chip + ETA)
//    getVesselTrack(imoNumber)      (historical track; used to bias the live
//                                    split when the AIS fix is momentarily nil)
//
//  When the AIS feed is unavailable (server returns null), the map still draws
//  the authored origin→dest great circle so the lane is never blank; the orb +
//  chip simply omit until a fix arrives.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Live store

@MainActor
final class VesselOceanTrackStore: ObservableObject {
    @Published var position: VesselTrackAPI.VesselPosition?
    @Published var track: [VesselTrackAPI.RoutePosition] = []
    @Published var loadError: String?
    @Published var loading = true

    /// Pull the live AIS fix + historical track. Both procs `return null` on a
    /// caught error server-side, so each result is independently optional.
    func load(imoNumber: String) async {
        loading = true; loadError = nil
        let api = EusoTripAPI.shared.vesselTrack
        do {
            async let posTask = api.liveVesselPosition(imoNumber: imoNumber)
            async let trackTask = api.getVesselTrack(imoNumber: imoNumber)
            let (pos, trk) = try await (posTask, trackTask)
            self.position = pos
            self.track = trk ?? []
        } catch {
            self.loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        self.loading = false
    }
}

// MARK: - Live ocean-track map

struct VesselOceanTrackMap: View {
    /// Vessel IMO that keys the AIS feed.
    let imoNumber: String
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

    init(
        imoNumber: String,
        origin: HereLatLng,
        destination: HereLatLng,
        originLabel: String,
        destinationLabel: String
    ) {
        self.imoNumber = imoNumber
        self.origin = origin
        self.destination = destination
        self.originLabel = originLabel
        self.destinationLabel = destinationLabel
    }

    /// True only for a finite, non-null-island fix. The (0,0) gate per
    /// D-maps-basemap — matches Escort 602's `validFix`. A reusable map surface
    /// must not trust its caller's coordinate validity blindly.
    private func validFix(_ lat: Double, _ lng: Double) -> Bool {
        lat.isFinite && lng.isFinite && !(lat == 0 && lng == 0)
    }

    /// Whether BOTH authored endpoints are real fixes. When false the component
    /// draws an honest 'awaiting port coordinates' seam instead of a
    /// great-circle arc across null island.
    private var endpointsValid: Bool {
        validFix(origin.lat, origin.lng) && validFix(destination.lat, destination.lng)
    }

    /// Live AIS coordinate (real fix), else `nil`. Coord-gated so a null-island
    /// AIS fix can't drop an orb on (0,0).
    private var aisCoord: HereLatLng? {
        guard let p = store.position, validFix(p.lat, p.lng) else { return nil }
        return HereLatLng(p.lat, p.lng)
    }

    /// The great-circle route polyline interpolated (slerp) origin→dest. The
    /// canvas splits this solid(traveled)→dashed(remaining) at the live AIS
    /// position, so we hand it the full arc — NOT a pre-split one. Empty when
    /// the authored endpoints aren't real coordinates (null-island gate).
    private var routePolyline: [HereLatLng] {
        guard endpointsValid else { return [] }
        return BespokeMapProjection.greatCircle(from: origin, to: destination, count: 64)
    }

    /// The callout chip text: speed / heading on line 1, coords on line 2 —
    /// VERBATIM to the 003 chip, but LIVE off the AIS fix.
    private var aisChipLabel: String? {
        guard let p = store.position else { return nil }
        let kn = p.speed.map { String(format: "%.1f kn", $0) } ?? "- kn"
        let hdg = p.heading.map { String(format: "hdg %03.0f°", $0) } ?? "hdg -"
        let coords = "\(Self.formatLat(p.lat)) \(Self.formatLng(p.lng))"
        return "\(kn) · \(hdg)\n\(coords)"
    }

    /// Map layers: the great-circle route + (when live) the AIS marker pinned
    /// at the real position carrying the speed/heading/coords callout.
    private var layers: [HereMapLayer] {
        var out: [HereMapLayer] = []
        let poly = routePolyline
        if !poly.isEmpty {
            out.append(.route(polyline: poly, colorHex: "#1473FF"))
        }
        if let ais = aisCoord {
            out.append(.markers([
                HereMarker(at: ais, kind: .truck, label: aisChipLabel, id: imoNumber)
            ]))
        }
        return out
    }

    /// Camera center: the live AIS fix when present, else the midpoint of the
    /// authored great-circle arc. Index-safe (D-maps-basemap 2026-06-01): the
    /// polyline is `greatCircle(count:64)` which guarantees ≥2 points, but we
    /// guard the subscript rather than trust the producer — falls back to the
    /// origin if the arc is ever degenerate so the canvas never crashes.
    private var cameraCenter: HereLatLng {
        if let ais = aisCoord { return ais }
        let poly = routePolyline
        guard !poly.isEmpty else { return origin }
        return poly[poly.count / 2]
    }

    var body: some View {
        Group {
            if endpointsValid {
                BespokeMapCanvas(
                    center: cameraCenter,
                    zoom: 4,
                    interactive: true,
                    tilt: 0,
                    isDark: colorScheme == .dark,
                    layers: layers,
                    style: .ocean
                )
            } else {
                // Honest seam (matches Escort 602's `mapAwaitingSeam`): when the
                // authored origin/destination aren't real coordinates — non-finite
                // or null-island (0,0) — we DON'T paint a great circle across null
                // island with port pins on (0,0). REAL coords only.
                mapAwaitingSeam
            }
        }
        // Frame guard (D-maps-basemap 2026-06-01): give the canvas a real
        // minimum height so a parent that lays it out with 0 height (the
        // historical frame.zero blank-bug trap) can't collapse it to nothing.
        // Callers that want a specific height still override with `.frame`.
        .frame(minHeight: 220)
        .task(id: imoNumber) { await store.load(imoNumber: imoNumber) }
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
                Text("The ocean route draws the origin→destination great circle and the live AIS vessel position once the booking's ports are geocoded and a fix arrives. Pull to refresh.")
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

    // MARK: Formatting

    /// "37.8°N" / "33.9°S" — the 003 chip's latitude readout (paired with the
    /// longitude so the position line is a complete fix, not lng-only).
    static func formatLat(_ lat: Double) -> String {
        let hemi = lat >= 0 ? "N" : "S"
        return String(format: "%.1f°%@", abs(lat), hemi)
    }

    /// "168.4°E" / "122.3°W" — the 003 chip's longitude readout.
    static func formatLng(_ lng: Double) -> String {
        let hemi = lng >= 0 ? "E" : "W"
        return String(format: "%.1f°%@", abs(lng), hemi)
    }
}
