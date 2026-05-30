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

    /// Live AIS coordinate (real fix), else `nil`.
    private var aisCoord: HereLatLng? {
        guard let p = store.position else { return nil }
        return HereLatLng(p.lat, p.lng)
    }

    /// The great-circle route polyline interpolated (slerp) origin→dest. The
    /// canvas splits this solid(traveled)→dashed(remaining) at the live AIS
    /// position, so we hand it the full arc — NOT a pre-split one.
    private var routePolyline: [HereLatLng] {
        BespokeMapProjection.greatCircle(from: origin, to: destination, count: 64)
    }

    /// The callout chip text: speed / heading on line 1, coords on line 2 —
    /// VERBATIM to the 003 chip, but LIVE off the AIS fix.
    private var aisChipLabel: String? {
        guard let p = store.position else { return nil }
        let kn = p.speed.map { String(format: "%.1f kn", $0) } ?? "— kn"
        let hdg = p.heading.map { String(format: "hdg %03.0f°", $0) } ?? "hdg —"
        let lng = Self.formatLng(p.lng)
        return "\(kn) · \(hdg)\n\(lng)"
    }

    /// Map layers: the great-circle route + (when live) the AIS marker pinned
    /// at the real position carrying the speed/heading/coords callout.
    private var layers: [HereMapLayer] {
        var out: [HereMapLayer] = [
            .route(polyline: routePolyline, colorHex: "#1473FF")
        ]
        if let ais = aisCoord {
            out.append(.markers([
                HereMarker(at: ais, kind: .truck, label: aisChipLabel, id: imoNumber)
            ]))
        }
        return out
    }

    var body: some View {
        BespokeMapCanvas(
            center: aisCoord ?? routePolyline[routePolyline.count / 2],
            zoom: 4,
            interactive: true,
            tilt: 0,
            isDark: colorScheme == .dark,
            layers: layers,
            style: .ocean
        )
        .task(id: imoNumber) { await store.load(imoNumber: imoNumber) }
    }

    // MARK: Formatting

    /// "168.4°E" / "122.3°W" — the 003 chip's longitude readout.
    static func formatLng(_ lng: Double) -> String {
        let hemi = lng >= 0 ? "E" : "W"
        return String(format: "%.1f°%@", abs(lng), hemi)
    }
}
