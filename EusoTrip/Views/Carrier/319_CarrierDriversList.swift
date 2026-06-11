//
//  319_CarrierDriversList.swift
//  EusoTrip — Carrier · Drivers list.
//

import SwiftUI

struct CarrierDriversListScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { DriversListBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Bids", systemImage: "hand.raised.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

private struct CarrierDriver: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let cdlClass: String?
    let cdlState: String?
    let cdlExpires: String?
    let medicalExpires: String?
    let hazmatEndorsement: Bool?
    let safetyScore: Double?
    let isActive: Bool
    /// "lat, lng" string the server joins off the latest gps_tracking row in
    /// `catalysts.getMyDrivers` ("Unknown"/null-island gated server-side). The
    /// roster proc has always returned this; the old decode dropped it. Optional
    /// because legacy/empty rows may omit it entirely.
    let location: String?
    /// Load number of the driver's active haul (in_transit/assigned), for the
    /// puck label. Server field is `currentLoad`.
    let currentLoad: String?

    /// The driver's REAL live fix, parsed from `location`. nil when the field is
    /// absent, isn't a coordinate pair, or resolves to null island — so a puck
    /// only ever drops on a real fix (no fabricated coords). Mirrors Catalyst 375.
    var liveFix: HereLatLng? {
        guard let raw = location else { return nil }
        let parts = raw.split(separator: ",")
        guard parts.count == 2,
              let lat = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let lng = Double(parts[1].trimmingCharacters(in: .whitespaces)),
              !(lat == 0 && lng == 0) else { return nil }
        return HereLatLng(lat, lng)
    }
}

private struct DriversListBody: View {
    @Environment(\.palette) private var palette
    @State private var drivers: [CarrierDriver] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                fleetMap
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.3.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · DRIVERS").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("My drivers").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: Live fleet map (in-house HERE basemap · real driver GPS pucks)

    /// Drivers that currently have a parseable live fix off the roster feed.
    private var locatedDrivers: [CarrierDriver] { drivers.filter { $0.liveFix != nil } }

    /// One `.truck` puck per located driver. Marker id = driver id (actionable).
    /// Label = driver name + active load number when present. Real coords only —
    /// `liveFix` already null-island-gates, so no fabricated points enter here.
    private var fleetMarkers: [HereMarker] {
        locatedDrivers.compactMap { d in
            guard let fix = d.liveFix else { return nil }
            let haul = d.currentLoad.map { " · \($0)" } ?? ""
            return HereMarker(at: fix, kind: .truck, label: "\(d.name)\(haul)", id: d.id)
        }
    }

    /// Camera center = first located driver's fix, else CONUS centroid sentinel.
    private var mapCenter: HereLatLng {
        locatedDrivers.first?.liveFix ?? HereLatLng(39.5, -98.35)
    }

    @ViewBuilder
    private var fleetMap: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LIVE FLEET MAP · Eusorone basemap · gps_tracking heartbeat")
                .font(.system(size: 8, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.6)

            if fleetMarkers.isEmpty {
                // Seam empty state — no driver has a parseable live fix yet. The
                // map + decode path are wired and light up the moment a real
                // gps_tracking row populates; never frames on null island.
                HStack(spacing: 12) {
                    Image(systemName: "map")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live fleet map pending")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                        Text("Awaiting a gps_tracking fix on a fleet driver")
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
            } else {
                HereLiveMapView(
                    center: mapCenter,
                    zoom: locatedDrivers.count == 1 ? 8 : 5,
                    baseLayers: [.markers(fleetMarkers)],
                    addOns: .shipperTracking,
                    onSelectMarker: { driverId in
                        // Tap a puck → route to that driver's Me detail.
                        NotificationCenter.default.post(
                            name: .esangOpenMeDetail,
                            object: "messages",
                            userInfo: ["driverId": driverId]
                        )
                    }
                )
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderFaint)
                )
                .accessibilityLabel("Live fleet map, \(fleetMarkers.count) drivers tracked")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading { LifecycleCard { Text("Loading drivers…").font(EType.caption).foregroundStyle(palette.textSecondary) } }
        else if let err = loadError { LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) } }
        else if drivers.isEmpty { EusoEmptyState(systemImage: "person.3", title: "No drivers", subtitle: "Hire drivers via /authority or invite via /referrals.") }
        else {
            ForEach(drivers) { d in
                LifecycleCard(accentGradient: d.isActive) {
                    LifecycleSection(label: d.name.uppercased(), icon: "person")
                    LifecycleRow(label: "CDL",         value: "\(dashIfEmpty(d.cdlClass)) · \(dashIfEmpty(d.cdlState))")
                    LifecycleRow(label: "CDL expires", value: humanISO(d.cdlExpires, format: "MMM d, yyyy"))
                    LifecycleRow(label: "Medical",     value: humanISO(d.medicalExpires, format: "MMM d, yyyy"))
                    LifecycleRow(label: "Hazmat",      value: d.hazmatEndorsement == true ? "Endorsed" : "-")
                    LifecycleRow(label: "Safety score", value: d.safetyScore.map { String(format: "%.2f", $0) } ?? "-")
                }
            }
        }
    }

    private func load() async {
        loading = true; loadError = nil
        do {
            let r: [CarrierDriver] = try await EusoTripAPI.shared.queryNoInput("catalysts.getMyDrivers")
            drivers = r
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("319 · Drivers · Night") { CarrierDriversListScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("319 · Drivers · Afternoon") { CarrierDriversListScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
