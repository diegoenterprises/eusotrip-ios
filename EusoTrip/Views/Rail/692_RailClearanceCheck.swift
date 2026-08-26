//
//  692_RailClearanceCheck.swift
//  EusoTrip — Rail Engineer · Clearance Check (dimensional gate).
//
//  Bespoke port of "05 Rail/Dark-SVG/692 Rail Clearance Check.svg".
//  ARCHETYPE = CLEARANCE-GATE — a vertical car-vs-envelope PROFILE diagram
//  hero (the regime's clearance plate drawn to scale with the consist profile
//  inside it) over a route-segment gate list, each segment carrying a
//  CLEARED / UNVERIFIED verdict chip. Deliberately a dimensional gate, NOT a
//  map (693 Slow Orders) and NOT a generic checklist.
//
//  Role: RAIL_ENGINEER (carrier/compliance). transportMode=rail.
//
//  WIRING MANIFEST (verified against frontend/server/routers/railShipments.ts):
//    railShipments.getRoutePlan  EXISTS railShipments.ts:2536 {shipmentId} →
//        {legs:[{road,from,to,miles,interchangeOut,ptcOk}], routeDescription,
//         ptcComplete, confirmed}. The route SEGMENTS below are these real
//        interline legs — the road, the lane, the miles.
//    railShipments.requestReroute EXISTS railShipments.ts:2606 {shipmentId} →
//        {legs} — a read-only re-solve. "Apply reroute" re-requests the routing.
//  PLATE ENVELOPE (real AAR/ARTF regulatory reference, not shipment data):
//    US/CA AAR Plate F (max 20'2" / 6.15 m) · MX ARTF Plate B (max 15'1" /
//    4.60 m). The envelope the consist is gated against swaps with the regime.
//  VERIFIED ABSENT (honest state, never fabricated):
//    A clearance.checkRoute feed with a measured car height per bridge is not on
//    disk. Each segment's clearance is therefore "UNVERIFIED" until a
//    dimensional check is filed — the screen never assumes a pass and never
//    invents a deficit. Degraded intent per the wireframe's "clearance
//    unverified" state, made honest.
//

import SwiftUI

struct RailClearanceCheckScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            RailClearanceCheckBody(shipmentId: shipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror railShipments.getRoutePlan)

private struct Leg692: Decodable {
    let road: String?
    let from: String?
    let to: String?
    let miles: Double?
    let interchangeOut: String?
    let ptcOk: Bool?
    var rowId: String { (road ?? "?") + "|" + (from ?? "") + "|" + (to ?? "") + "|" + (interchangeOut ?? "") }
}
private struct RoutePlan692: Decodable {
    let shipmentId: Int?
    let routeDescription: String?
    let legs: [Leg692]?
    let ptcComplete: Bool?
    let confirmed: Bool?
}
private struct RerouteResult692: Decodable { let shipmentId: Int?; let legs: [Leg692]? }
private struct ShipmentIdInput692: Encodable { let shipmentId: Int }

// Real AAR/ARTF clearance-plate reference.
private struct Plate692 {
    let name: String
    let heightImperial: String
    let heightMetric: String
    let width: String
    let ratio: CGFloat   // height : width, for drawing the envelope to scale
    static let byRegime: [Plate692] = [
        .init(name: "Plate F", heightImperial: "20 ft 2 in", heightMetric: "6.15 m", width: "10 ft 8 in", ratio: 1.89),
        .init(name: "Plate F", heightImperial: "20 ft 2 in", heightMetric: "6.15 m", width: "10 ft 8 in", ratio: 1.89),
        .init(name: "Plate B", heightImperial: "15 ft 1 in", heightMetric: "4.60 m", width: "10 ft 8 in", ratio: 1.41),
    ]
}

// MARK: - Body

private struct RailClearanceCheckBody: View {
    let shipmentId: Int

    @Environment(\.palette) private var palette
    @State private var plan: RoutePlan692? = nil
    @State private var loading = true
    @State private var rerouting = false
    @State private var rerouteMessage: String? = nil
    @State private var regime = 0
    @State private var showOverride = false

    private let regimeNames = ["US · AAR", "CA · TC", "MX · ARTF"]
    private var plate: Plate692 { Plate692.byRegime[regime] }
    private var legs: [Leg692] { plan?.legs ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("Clearance check")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text(plan?.routeDescription ?? "Dimensional gate · run-through consist")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4).lineLimit(1)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 64)
                } else {
                    envelopeHero
                    segmentHeader
                    segmentList
                    triBand
                    footerActions
                    if let m = rerouteMessage {
                        LifecycleCard { Text(m).font(EType.caption).foregroundStyle(palette.textSecondary) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .eusoRefreshable { await reload() }
        .alert("Override is an audited decision", isPresented: $showOverride) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Clearing a consist past its plate envelope without a filed dimensional check is an audited safety override, not one this screen can make. Measure the consist against \(plate.name) first.")
        }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            EusoTripEyebrow(verbatim: "CARRIER · RAIL · CLEARANCE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text(plate.name.uppercased().replacingOccurrences(of: " ", with: " · "))
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip(plate.name.lowercased(), Brand.blue)
            chip("\(legs.count) segment\(legs.count == 1 ? "" : "s")", palette.textSecondary)
            chip("unverified", Brand.warning)
        }
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Envelope hero — the plate drawn to scale with the consist profile.

    private var envelopeHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("DIMENSIONAL CLEARANCE · MEASURE TO CONFIRM")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Brand.warning)
                Spacer()
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(LinearGradient(colors: [Brand.warning.opacity(0.12), Brand.blue.opacity(0.06)],
                                       startPoint: .leading, endPoint: .trailing))
            HStack(alignment: .center, spacing: 18) {
                envelopeDiagram
                    .frame(width: 96, height: 150)
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(plate.name) ENVELOPE")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
                        Text(plate.heightImperial)
                            .font(.system(size: 24, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Text("\(plate.heightMetric) · width \(plate.width)")
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textSecondary)
                    }
                    Text("Gate the consist against \(plate.name) before assembly. A car over the envelope blocks the route — file a dimensional check to clear each segment.")
                        .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(LinearGradient.primary, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var envelopeDiagram: some View {
        GeometryReader { g in
            let w = g.size.width
            let h = g.size.height
            let envW = w * 0.82
            let envH = min(h * 0.96, envW * plate.ratio)
            let x = (w - envW) / 2
            let y = h - envH
            ZStack(alignment: .bottom) {
                // Rail baseline
                Rectangle().fill(palette.borderStrong).frame(height: 2).offset(y: -0.5)
                // Plate envelope outline (the clearance loading gauge)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Brand.blue.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: envW, height: envH)
                    .position(x: x + envW / 2, y: y + envH / 2)
                // Consist profile inside — reference silhouette, "measure to confirm"
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(LinearGradient(colors: [Brand.rail.opacity(0.30), Brand.rail.opacity(0.14)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Brand.rail.opacity(0.6), lineWidth: 1))
                    .frame(width: envW * 0.72, height: envH * 0.80)
                    .position(x: x + envW / 2, y: y + envH - (envH * 0.80) / 2)
            }
        }
    }

    private var segmentHeader: some View {
        HStack {
            Text("ROUTE SEGMENTS · INTERLINE LEGS")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text("ROAD · LANE · CLEARANCE")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.textTertiary)
        }
    }

    @ViewBuilder
    private var segmentList: some View {
        if legs.isEmpty {
            EusoEmptyState(systemImage: "arrow.triangle.branch",
                           title: "No route legs on file",
                           subtitle: "This shipment has no interline route plan yet. Once a routing is solved, each leg lists here to be cleared against the plate envelope.")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(legs.enumerated()), id: \.element.rowId) { i, leg in
                    segmentRow(leg)
                    if i < legs.count - 1 { Divider().overlay(palette.borderFaint) }
                }
            }
            .padding(.horizontal, 16)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func segmentRow(_ leg: Leg692) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(leg.road ?? "—")
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textPrimary)
                    if let m = leg.miles, m > 0 {
                        Text("· \(Int(m)) mi").font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textTertiary)
                    }
                }
                Text("\(leg.from ?? "origin") → \(leg.to ?? "destination")")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary).lineLimit(1)
                if let ic = leg.interchangeOut, !ic.isEmpty {
                    Text("interchange out · \(ic)").font(.system(size: 9, design: .monospaced)).foregroundStyle(palette.textTertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                clearanceChip
                Text(leg.ptcOk == true ? "PTC ok" : "PTC pend")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(leg.ptcOk == true ? Brand.success : Brand.warning)
            }
        }
        .padding(.vertical, 12)
    }

    private var clearanceChip: some View {
        Text("UNVERIFIED")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(Brand.warning)
            .padding(.horizontal, 10).frame(height: 22)
            .background(Capsule().fill(Brand.warning.opacity(0.12)))
    }

    private var triBand: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(regimeNames[i]).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    Text(Plate692.byRegime[i].name).font(.system(size: 9, weight: .heavy))
                }
                .foregroundStyle(i == regime ? Brand.blue : palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(i == regime ? Brand.blue.opacity(0.5) : palette.borderFaint))
                .onTapGesture { regime = i }
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: rerouting ? "Re-solving…" : "Apply reroute", action: { Task { await reroute() } })
                .frame(maxWidth: .infinity)
                .disabled(rerouting)
            Button(action: { showOverride = true }) {
                Text("Override")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 118)
                    .frame(minHeight: 48, maxHeight: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                                .strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func reload() async {
        loading = true
        let p: RoutePlan692? = try? await EusoTripAPI.shared.query(
            "railShipments.getRoutePlan", input: ShipmentIdInput692(shipmentId: shipmentId))
        self.plan = p
        loading = false
    }

    private func reroute() async {
        rerouting = true; rerouteMessage = nil
        do {
            let r: RerouteResult692 = try await EusoTripAPI.shared.query(
                "railShipments.requestReroute", input: ShipmentIdInput692(shipmentId: shipmentId))
            if let ls = r.legs { plan = RoutePlan692(shipmentId: shipmentId, routeDescription: plan?.routeDescription, legs: ls, ptcComplete: plan?.ptcComplete, confirmed: plan?.confirmed) }
            rerouteMessage = (r.legs?.isEmpty ?? true)
                ? "The re-solve returned no alternate legs. The route is unchanged — clearance still needs a dimensional check."
                : "Routing re-solved. Clear each new segment against \(plate.name) before assembly."
        } catch {
            rerouteMessage = "The reroute request didn't complete. Check your connection and try again."
        }
        rerouting = false
    }
}

#Preview("692 · Rail Clearance Check · Night") {
    RailClearanceCheckScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("692 · Rail Clearance Check · Light") {
    RailClearanceCheckScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
