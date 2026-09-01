//
//  276_ShipperInTransitEchoM05.swift
//  EusoTrip — Shipper · LIFECYCLE ECHO · IN-TRANSIT (M-05 chain).
//
//  Wireframe: 02 Shipper/Dark-SVG/276 Shipper In-Transit Echo M05.svg
//  Archetype: MAP/TRACKING. Diego watches his one awarded flatbed move on a
//  live map so "where is my steel and is it on time?" is answered in three
//  seconds without a carrier-portal login.
//
//  Web peer: frontend/client/src/pages/shipper/loads/:id (live-tracking).
//  Wiring (on-disk confirmed):
//    • shippers.getLifecycleSnapshot EXISTS shippers.ts → status, ETA
//      (estimatedDeliveryDate), distance, carrier/driver, live geofence
//      (last-ping age).
//    • LifecycleMapCard renders the REAL HERE route + truck puck (mode .full).
//    • Message      → messaging (310) via nav-swap.
//    • Share Live Link → live tracking (222) via nav-swap (the share surface).
//  RBAC: shipperProcedure. transportMode=truck · US (FMCSA 49 CFR 395 ELD).
//
//  Honest gap (mirrors 267_InTransitLive): the snapshot exposes no server
//  "miles completed / % progress / speed" scalar. TRIP PULSE therefore
//  renders ETA, TOTAL distance, LAST PING age, and STATUS from real fields
//  — it does NOT fabricate a 45% / 63 mph figure.
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct ShipperInTransitEchoM05Screen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            VStack(alignment: .leading, spacing: Space.s4) {
                ShipperEchoSnapshotView(loadId: loadId, eyebrow: "SHIPPER · LOAD · IN-TRANSIT") { live in
                    InTransitM05Body(live: live, loadId: loadId)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        } nav: {
            shipperLifecycleNav(currentSlot: .loads)
        }
    }
}

private struct InTransitM05Body: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String

    private var pingAge: String { echoPingAge(live.lastGeofence?.eventTimestamp) }
    private var isPinging: Bool { live.lastGeofence?.eventTimestamp != nil }
    private var etaLabel: String { humanISO(live.load.estimatedDeliveryDate ?? live.load.deliveryDate, format: "HH:mm") }
    private var onTime: Bool { live.load.status.lowercased() != "delayed" && live.load.status.lowercased() != "exception" }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            ShipperEchoHeader(
                eyebrow: "SHIPPER · LOAD · IN-TRANSIT",
                trailing: isPinging ? "PINGING · \(pingAge) AGO" : "AWAITING PING",
                trailingTone: isPinging ? .live : .tertiary,
                title: "In Transit",
                subtitle: "\(live.load.loadNumber) · \(echoLaneCities(live))"
            )
            statusPills
            LifecycleMapCard(live: live, loadId: loadId, label: "LIVE TRACK", mode: .full, height: 260)
            tripPulse
            ShipperEchoLifecycleStrip(active: .inTransit, sectionLabel: "LIFECYCLE", caption: nil, compact: true)
            carrierCard
            esangStrip
            ShipperEchoCTAPair(
                primaryTitle: "Share live link",
                primaryAction: { shipperEchoNavSwap("222", loadId: loadId) },
                secondaryTitle: "Message",
                secondaryAction: { shipperEchoNavSwap("310", loadId: loadId) }
            )
        }
    }

    private var statusPills: some View {
        HStack(spacing: Space.s2) {
            HStack(spacing: 6) {
                Circle().fill(onTime ? Brand.success : Brand.warning).frame(width: 7, height: 7)
                Text(onTime ? "ON TIME" : live.load.status.uppercased())
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(palette.textPrimary)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(palette.bgCardSoft).clipShape(Capsule())
            .overlay(Capsule().strokeBorder(palette.borderFaint, lineWidth: 1))

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Text("ETA").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white.opacity(0.85))
                Text(etaLabel).font(.system(size: 12, weight: .heavy)).monospacedDigit().foregroundStyle(.white)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(LinearGradient.primary))
        }
    }

    private var tripPulse: some View {
        HStack(spacing: 0) {
            ShipperEchoStatCell(label: "ETA", value: etaLabel, sub: "delivery", gradient: true)
            divider
            ShipperEchoStatCell(label: "DISTANCE", value: live.load.distance.map { "\(Int($0))" } ?? "—", sub: "mi total")
            divider
            ShipperEchoStatCell(label: "LAST PING", value: pingAge, sub: isPinging ? "live" : "—", valueColor: isPinging ? Brand.success : nil)
            divider
            ShipperEchoStatCell(label: "STATUS", value: live.load.status.uppercased(), sub: onTime ? "healthy" : "watch")
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var divider: some View {
        Rectangle().fill(palette.borderFaint).frame(width: 1, height: 34)
    }

    private var carrierCard: some View {
        ShipperEchoPartyRow(
            monogram: echoMonogram(live.carrier?.name),
            title: live.carrier?.name ?? "Awarded carrier",
            authority: echoAuthorityLine(dot: live.carrier?.dotNumber, mc: live.carrier?.mcNumber),
            detail: carrierDetail,
            pill: (onTime ? "ON TIME" : "WATCH", onTime ? .success : .warning),
            accent: Brand.escort
        )
    }

    private var esangStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 22, height: 22)
                    Text("E").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                }
                Text("ESANG LIVE").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(onTime ? "healthy · no reroute" : "watching").font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
            Text(esangLine)
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Brand.success.opacity(0.10), Brand.blue.opacity(0.08)], startPoint: .leading, endPoint: .trailing))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var carrierDetail: String {
        var parts: [String] = []
        if let d = live.driver?.name, !d.isEmpty { parts.append("Driver \(d)") }
        parts.append("linehaul \(usd(live.load.rate))")
        return parts.joined(separator: " · ")
    }

    private var esangLine: String {
        let eta = etaLabel
        if let dwin = live.load.deliveryDate, !dwin.isEmpty {
            return "Lands \(eta) — measured against the \(humanISO(dwin, format: "HH:mm")) dock window."
        }
        return "Tracking to \(eta) — last ping \(pingAge) ago, route healthy."
    }
}

#Preview("276 · In-transit · Night") {
    ShipperInTransitEchoM05Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("276 · In-transit · Afternoon") {
    ShipperInTransitEchoM05Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
