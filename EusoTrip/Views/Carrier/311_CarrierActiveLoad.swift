//
//  311_CarrierActiveLoad.swift
//  EusoTrip — Carrier · Active load detail (mid-haul carrier view).
//

import SwiftUI

struct CarrierActiveLoadScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) { ActiveLoadBody(loadId: loadId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home", systemImage: "house", isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Bids", systemImage: "hand.raised.fill", isCurrent: false),
                           NavSlot(label: "Me", systemImage: "person", isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct ActiveLoadBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    let loadId: String
    @StateObject private var snap = ShipperLifecycleSnapshotStore()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                content
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { snap.loadId = loadId; await snap.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "shippingbox.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CARRIER · ACTIVE LOAD").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text(snap.state.value??.load.loadNumber ?? "-").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch snap.state {
        case .loading: LifecycleCard { Text("Loading…").font(EType.caption).foregroundStyle(palette.textSecondary) }
        case .empty: EusoEmptyState(systemImage: "doc.text", title: "Load not found", subtitle: "Pull to refresh.")
        case .error(let err): LifecycleCard(accentDanger: true) { Text(err.eusoUserCopy).font(EType.caption).foregroundStyle(Brand.danger) }
        case .loaded(let opt):
            if let live = opt {
                LifecycleCard(accentGradient: true) {
                    LifecycleSection(label: "STATUS", icon: "flag")
                    LifecycleRow(label: "Status",  value: live.load.status.uppercased())
                    LifecycleRow(label: "Lane",    value: laneDisplay(live))
                    LifecycleRow(label: "Rate",    value: usd(live.load.rate))
                    LifecycleRow(label: "Pickup",  value: humanISO(live.load.pickupDate))
                    LifecycleRow(label: "ETA",     value: humanISO(live.load.estimatedDeliveryDate))
                }
                LifecycleCard {
                    LifecycleSection(label: "DRIVER", icon: "person")
                    LifecycleRow(label: "Name",  value: dashIfEmpty(live.driver?.name))
                    LifecycleRow(label: "Phone", value: dashIfEmpty(live.driver?.phone))
                    if live.vehicle != nil {
                        LifecycleRow(label: "Truck", value: dashIfEmpty(live.vehicle?.vehicleNumber))
                    }
                }
                if let g = live.lastGeofence {
                    LifecycleCard {
                        LifecycleSection(label: "LATEST GEOFENCE", icon: "dot.radiowaves.left.and.right")
                        liveLoadMap(live, g)
                        LifecycleRow(label: "Type",      value: g.type.uppercased())
                        LifecycleRow(label: "Recorded",  value: humanISO(g.eventTimestamp))
                        LifecycleRow(label: "GPS",       value: String(format: "%.4f, %.4f", g.latitude, g.longitude))
                    }
                }
                actionRow(live)
            }
        }
    }

    // MARK: Live load map (in-house HERE basemap · real geofence fix)

    /// The load's REAL last-known fix, taken straight off the snapshot's
    /// `lastGeofence` (the `latitude`/`longitude` Double pair the server
    /// returns from `shippers.getLifecycleSnapshot` — the same value this
    /// card already prints as text). nil when the fix resolves to null
    /// island, so the truck puck only ever draws on a real fix (no
    /// fabricated coordinates).
    private func liveLoadFix(_ g: ShipperAPI.LifecycleSnapshot.Geofence) -> HereLatLng? {
        guard !(g.latitude == 0 && g.longitude == 0) else { return nil }
        return HereLatLng(g.latitude, g.longitude)
    }

    /// Truck-puck marker for the load's live geofence fix. The marker id is
    /// the load id so a tap routes back to that load (HereLiveMapView marks
    /// id-carrying base pins actionable → `onSelectMarker`).
    private func liveLoadLayers(_ live: ShipperAPI.LifecycleSnapshot,
                                _ fix: HereLatLng) -> [HereMapLayer] {
        [
            .markers([
                HereMarker(
                    at: fix,
                    kind: .truck,
                    label: live.load.loadNumber.isEmpty ? laneDisplay(live) : live.load.loadNumber,
                    id: loadId
                )
            ])
        ]
    }

    @ViewBuilder
    private func liveLoadMap(_ live: ShipperAPI.LifecycleSnapshot,
                             _ g: ShipperAPI.LifecycleSnapshot.Geofence) -> some View {
        if let fix = liveLoadFix(g) {
            HereLiveMapView(
                center: fix,
                zoom: 8,
                baseLayers: liveLoadLayers(live, fix),
                addOns: .shipperTracking,
                onSelectMarker: { _ in
                    NotificationCenter.default.post(
                        name: .esangOpenMeDetail,
                        object: "messages",
                        userInfo: ["loadId": loadId]
                    )
                }
            )
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint)
            )
            .padding(.bottom, 4)
        }
    }

    private func actionRow(_ live: ShipperAPI.LifecycleSnapshot) -> some View {
        HStack(spacing: 10) {
            Button {
                if let p = live.driver?.phone, let url = URL(string: "tel://\(p.filter(\.isNumber))") { openURL(url) }
            } label: {
                Text("Call driver").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(LinearGradient.diagonal).clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain).disabled(live.driver?.phone?.isEmpty != false)
        }
    }
}

#Preview("311 · Active load · Night") { CarrierActiveLoadScreen(theme: Theme.dark, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("311 · Active load · Afternoon") { CarrierActiveLoadScreen(theme: Theme.light, loadId: "1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
