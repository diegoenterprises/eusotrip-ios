//
//  283_ShipperPickupOnSiteEchoM06.swift
//  EusoTrip — Shipper · LIFECYCLE ECHO · PICKUP · ON-SITE (M-06 chain).
//
//  Wireframe: 02 Shipper/Dark-SVG/283 Shipper Pickup On-Site Echo M06.svg
//  Archetype: MAP/TRACKING + on-site status. The M-06 dialect of 275 (a
//  reefer produce lane at the origin dock). Shows Diego the moment his
//  awarded carrier reaches the origin dock so he can confirm pickup is on
//  time at a glance. (The SVG's §-marker / snapshot-source dev copy is not
//  reproduced — it renders through the clean golden echo atoms.)
//
//  Web peer: frontend/client/src/pages/shipper/loads/:id.
//  Wiring (on-disk confirmed):
//    • shippers.getLifecycleSnapshot EXISTS shippers.ts → carrier/driver,
//      origin geofence (truck-at-pickup pin + dwell), lane, rate.
//    • LifecycleMapCard renders the REAL HERE basemap (truck + pickup pins).
//    • View tracking → live tracking (222) via nav-swap.
//    • Message      → messaging (310) via nav-swap.
//  RBAC: shipperProcedure. transportMode=truck · US (reefer · FSMA cold-chain).
//
//  Honest: dwell + on-time read from the real origin geofence; the document
//  chip states are derived from the load's lifecycle position (awarded ⇒
//  rate-con signed / insurance on file; BOL awaits loading), not a
//  per-document endpoint the snapshot doesn't carry.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct ShipperPickupOnSiteEchoM06Screen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            VStack(alignment: .leading, spacing: Space.s4) {
                ShipperEchoSnapshotView(loadId: loadId, eyebrow: "SHIPPER · LOAD · PICKUP · ON-SITE") { live in
                    PickupOnSiteM06Body(live: live, loadId: loadId)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        } nav: {
            shipperLifecycleNav(currentSlot: .loads)
        }
    }
}

private struct PickupOnSiteM06Body: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String

    private var dwell: String {
        guard let s = live.lastGeofence?.dwellSeconds, s >= 0 else { return "—" }
        return String(format: "%d:%02d", s / 3600 > 0 ? s / 3600 : s / 60, s / 3600 > 0 ? (s % 3600) / 60 : s % 60)
    }
    private var isOnSite: Bool { live.lastGeofence != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            ShipperEchoHeader(
                eyebrow: "SHIPPER · LOAD · PICKUP · ON-SITE",
                trailing: live.load.loadNumber,
                title: echoLaneCities(live)
            )
            LifecycleMapCard(live: live, loadId: loadId, label: "ON-SITE", mode: .truckAtPickup, height: 200)
            ShipperEchoLifecycleStrip(active: .pickup, caption: ribbonCaption)
            statusCard
            carrierSection
            documentsSection
            ShipperEchoCTAPair(
                primaryTitle: "View tracking",
                primaryAction: { shipperEchoNavSwap("222", loadId: loadId) },
                secondaryTitle: "Message",
                secondaryAction: { shipperEchoNavSwap("310", loadId: loadId) }
            )
        }
    }

    private var statusCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(spacing: Space.s2) {
                    StatusPill(text: isOnSite ? "ON SITE" : "EN ROUTE", kind: isOnSite ? .success : .info)
                    Text("\(dashIfEmpty(live.load.equipmentType))")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(palette.bgCardSoft))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .bottom) {
                    ShipperEchoStatCell(
                        label: "LINEHAUL",
                        value: usd(live.load.rate),
                        sub: "\(echoRatePerMile(rate: live.load.rate, distance: live.load.distance)) · \(distanceLabel)",
                        gradient: true
                    )
                    ShipperEchoStatCell(
                        label: "DWELL",
                        value: dwell,
                        sub: isOnSite ? "on site" : "not yet"
                    )
                    .frame(maxWidth: 110)
                }
            }
        }
    }

    private var carrierSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ShipperEchoSectionLabel(text: "CATALYST · CARRIER · ON-SITE")
            ShipperEchoPartyRow(
                monogram: echoMonogram(live.carrier?.name),
                title: live.carrier?.name ?? "Awarded carrier",
                authority: echoAuthorityLine(dot: live.carrier?.dotNumber, mc: live.carrier?.mcNumber),
                detail: driverDetail,
                pill: (isOnSite ? "ON TIME" : "EN ROUTE", isOnSite ? .success : .info),
                accent: Brand.escort
            )
        }
    }

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ShipperEchoSectionLabel(text: "DOCUMENTS")
            HStack(spacing: Space.s2) {
                ShipperEchoDocChip(icon: "doc.text", title: "BOL", state: "awaiting load", tone: .pending)
                ShipperEchoDocChip(icon: "doc.text.fill", title: "Rate-con", state: carrierAssigned ? "signed" : "pending", tone: carrierAssigned ? .done : .pending)
                ShipperEchoDocChip(icon: "checkmark.shield.fill", title: "Insurance", state: carrierAssigned ? "on file" : "pending", tone: carrierAssigned ? .verified : .pending)
            }
        }
    }

    private var carrierAssigned: Bool { live.carrier != nil }
    private var distanceLabel: String { live.load.distance.map { "\(Int($0)) mi" } ?? "— mi" }
    private var driverDetail: String {
        var parts: [String] = []
        if let d = live.driver?.name, !d.isEmpty { parts.append("Driver \(d)") }
        if let arr = live.pickup?.arrivedAt, !arr.isEmpty { parts.append("on site \(humanISO(arr, format: "HH:mm"))") }
        return parts.isEmpty ? "Driver assignment pending" : parts.joined(separator: " · ")
    }
    private var ribbonCaption: String {
        let facility = live.pickup?.facilityName ?? live.pickup?.city ?? "origin"
        return isOnSite ? "On site at \(facility) · dwell \(dwell)" : "En route to \(facility)"
    }
}

#Preview("283 · Pickup on-site M06 · Night") {
    ShipperPickupOnSiteEchoM06Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("283 · Pickup on-site M06 · Afternoon") {
    ShipperPickupOnSiteEchoM06Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
