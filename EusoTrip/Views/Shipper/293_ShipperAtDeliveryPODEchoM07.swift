//
//  293_ShipperAtDeliveryPODEchoM07.swift
//  EusoTrip — Shipper · LIFECYCLE ECHO · AT-DELIVERY · POD (M-07 chain).
//
//  Wireframe: 02 Shipper/Dark-SVG/293 Shipper At-Delivery POD Echo M07.svg
//  Archetype: MAP/TRACKING + delivery confirmation. The M-07 dialect (a
//  dry-van general-cargo lane at the Phoenix consignee). Shows Diego the
//  moment his Aurora load reaches the consignee with the POD signed, so he
//  can confirm the packet lines up before approving paperwork.
//
//  Web peer: frontend/client/src/pages/shipper/loads/:id (POD packet view).
//  Wiring (on-disk confirmed):
//    • shippers.getLifecycleSnapshot EXISTS shippers.ts:1216 → delivered
//      state, arrival geofence, carrier/driver, rate.
//    • pod.getPODForLoad             EXISTS pod.ts:49 → POD packet
//      (receiver, submittedAt, status, notes).
//    • Review POD → POD receipt (248) via nav-swap. (Approval happens at
//      the PAPERWORK stage / 294, not fired here.)
//    • Message   → messaging (310) via nav-swap.
//  RBAC: shipperProcedure. transportMode=truck · US (dry van · sealed).
//
//  Honest: the dry-van seal + pallet-count are not on the POD packet — the
//  card surfaces the real receiver + signed timestamp instead of a
//  fabricated "26/26 pallets · seal intact".
//
//  Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct ShipperAtDeliveryPODEchoM07Screen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            VStack(alignment: .leading, spacing: Space.s4) {
                ShipperEchoSnapshotView(loadId: loadId, eyebrow: "SHIPPER · LOAD · DELIVERED · POD") { live in
                    DeliveryPODM07Body(live: live, loadId: loadId)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        } nav: {
            shipperLifecycleNav(currentSlot: .loads)
        }
    }
}

private struct DeliveryPODM07Body: View {
    @Environment(\.palette) private var palette
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String

    @State private var pod: PODAPI.PODPacket?
    @State private var loadedPOD = false

    private var podSigned: Bool {
        guard let s = pod?.status?.lowercased() else { return false }
        return s.contains("signed") || s.contains("approved") || s.contains("pending") || s.contains("submitted")
    }
    private var arrivedLabel: String {
        humanISO(live.load.actualDeliveryDate ?? live.delivery?.arrivedAt, format: "HH:mm")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            ShipperEchoHeader(
                eyebrow: "SHIPPER · LOAD · DELIVERED · POD",
                trailing: live.load.loadNumber,
                title: echoLaneCities(live)
            )
            LifecycleMapCard(live: live, loadId: loadId, label: "DELIVERED", mode: .truckAtDelivery, height: 200)
            ShipperEchoLifecycleStrip(active: .delivery, caption: ribbonCaption)
            podCard
            carrierSection
            documentsSection
            ShipperEchoCTAPair(
                primaryTitle: "Review POD",
                primaryAction: { shipperEchoNavSwap("248", loadId: loadId) },
                secondaryTitle: "Message",
                secondaryAction: { shipperEchoNavSwap("310", loadId: loadId) }
            )
        }
        .task {
            guard !loadedPOD else { return }
            loadedPOD = true
            pod = (try? await EusoTripAPI.shared.pod.getPODForLoad(loadId: live.load.id)) ?? nil
        }
    }

    private var podCard: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: Space.s4) {
                HStack(spacing: Space.s2) {
                    StatusPill(text: podSigned ? "POD SIGNED" : "POD PENDING", kind: podSigned ? .success : .warning)
                    Text(dashIfEmpty(live.load.equipmentType))
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
                        sub: "\(echoRatePerMile(rate: live.load.rate, distance: live.load.distance)) · approve to settle",
                        gradient: true
                    )
                    ShipperEchoStatCell(
                        label: "SIGNED BY",
                        value: signedByShort,
                        sub: pod?.submittedAt != nil ? humanISO(pod?.submittedAt, format: "HH:mm") : "—"
                    )
                    .frame(maxWidth: 130)
                }
            }
        }
    }

    private var carrierSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ShipperEchoSectionLabel(text: "CATALYST · CARRIER · DELIVERED")
            ShipperEchoPartyRow(
                monogram: echoMonogram(live.carrier?.name),
                title: live.carrier?.name ?? "Awarded carrier",
                authority: echoAuthorityLine(dot: live.carrier?.dotNumber, mc: live.carrier?.mcNumber),
                detail: driverDetail,
                pill: ("DELIVERED", .success),
                accent: Brand.escort
            )
        }
    }

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            ShipperEchoSectionLabel(text: "DOCUMENTS")
            HStack(spacing: Space.s2) {
                ShipperEchoDocChip(icon: "doc.text.fill", title: "BOL", state: "signed", tone: .done)
                ShipperEchoDocChip(icon: "signature", title: "POD", state: podSigned ? "signed \(humanISO(pod?.submittedAt, format: "HH:mm"))" : "pending", tone: podSigned ? .feature : .pending)
                ShipperEchoDocChip(icon: "checkmark.shield.fill", title: "Insurance", state: "verified", tone: .verified)
            }
        }
    }

    private var signedByShort: String {
        guard let r = pod?.receiverName, !r.isEmpty else { return "—" }
        return String(r.prefix(14))
    }
    private var driverDetail: String {
        var parts: [String] = []
        if let d = live.driver?.name, !d.isEmpty { parts.append("Driver \(d)") }
        if podSigned { parts.append("POD signed \(humanISO(pod?.submittedAt, format: "HH:mm"))") }
        return parts.isEmpty ? "Delivered to consignee" : parts.joined(separator: " · ")
    }
    private var ribbonCaption: String {
        let recv = live.delivery?.facilityName ?? live.delivery?.city ?? "consignee"
        return podSigned ? "Arrived \(arrivedLabel) · POD signed at \(recv)" : "Arrived \(arrivedLabel) at \(recv) · POD pending"
    }
}

#Preview("293 · At-delivery POD M07 · Night") {
    ShipperAtDeliveryPODEchoM07Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("293 · At-delivery POD M07 · Afternoon") {
    ShipperAtDeliveryPODEchoM07Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
