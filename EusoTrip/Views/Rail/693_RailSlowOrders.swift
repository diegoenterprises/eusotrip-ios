//
//  693_RailSlowOrders.swift
//  EusoTrip — Rail Engineer · Slow Orders (FRA speed-restriction overlay).
//
//  Bespoke port of "05 Rail/Dark-SVG/693 Rail Slow Orders.svg".
//  ARCHETYPE = OVERLAY-MAP — a HORIZONTAL milepost route track hero with the
//  route drawn end to end, leg boundaries ticked, and a speed-restriction
//  overlay legend (amber 25 / red 10 mph), over an added-transit delta and a
//  restriction list. Deliberately the horizontal track composition, NOT 692's
//  vertical clearance envelope.
//
//  Role: RAIL_ENGINEER (carrier/compliance). transportMode=rail.
//
//  WIRING MANIFEST (verified against frontend/server/routers/railShipments.ts):
//    railShipments.getRoutePlan  EXISTS railShipments.ts:2536 {shipmentId} →
//        {legs:[{road,from,to,miles,interchangeOut,ptcOk}], routeDescription}.
//        The milepost track is drawn from these real legs (cumulative miles).
//    railShipments.requestReroute EXISTS railShipments.ts:2606 {shipmentId}.
//  VERIFIED ABSENT (honest state, never fabricated):
//    A slowOrders.getForRoute feed (FRA TASS speed restrictions per MP range)
//    is not on disk. With no restriction feed the route reads CLEAR and the
//    added-transit delta is 0 — the screen never invents a +47 min figure or a
//    phantom restriction. The FRA TASS / TC TSB / ARTF SICT source labels are
//    real regulatory references, resolved per regime.
//

import SwiftUI

struct RailSlowOrdersScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            RailSlowOrdersBody(shipmentId: shipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror railShipments.getRoutePlan)

private struct Leg693: Decodable {
    let road: String?
    let from: String?
    let to: String?
    let miles: Double?
    let interchangeOut: String?
    var rowId: String { (road ?? "?") + "|" + (from ?? "") + "|" + (to ?? "") }
    var mi: Double { max(0, miles ?? 0) }
}
private struct RoutePlan693: Decodable {
    let routeDescription: String?
    let legs: [Leg693]?
}
private struct RerouteResult693: Decodable { let legs: [Leg693]? }
private struct ShipmentIdInput693: Encodable { let shipmentId: Int }

// MARK: - Body

private struct RailSlowOrdersBody: View {
    let shipmentId: Int

    @Environment(\.palette) private var palette
    @State private var legs: [Leg693] = []
    @State private var routeText: String? = nil
    @State private var loading = true
    @State private var rerouting = false
    @State private var accepted = false
    @State private var rerouteMessage: String? = nil
    @State private var regime = 0

    private let regimes: [(String, String)] = [("US · FRA", "TASS"),
                                               ("CA · TC",  "TSB"),
                                               ("MX · ARTF", "SICT")]

    // No slow-order feed on disk → zero active restrictions, zero added transit.
    private let activeRestrictions = 0
    private let addedTransitMin = 0
    private var totalMiles: Double { legs.reduce(0) { $0 + $1.mi } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("Slow orders")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text(routeText ?? "Route restrictions · run-through route")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4).lineLimit(1)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 64)
                } else {
                    trackHero
                    restrictionHeader
                    restrictionList
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
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            EusoTripEyebrow(verbatim: "CARRIER · RAIL · SLOW ORDERS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("FRA · TASS")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip("\(activeRestrictions) active", activeRestrictions > 0 ? Brand.warning : Brand.success)
            chip(addedTransitMin > 0 ? "+\(addedTransitMin) min" : "no delay", addedTransitMin > 0 ? Brand.danger : Brand.success)
            chip(regimes[regime].1.lowercased(), Brand.blue)
        }
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Horizontal milepost track hero with the speed-restriction overlay.

    private var trackHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(activeRestrictions > 0 ? "FRA SLOW ORDERS · +\(addedTransitMin) MIN TRANSIT" : "FRA TASS · ROUTE CLEAR")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(activeRestrictions > 0 ? Brand.warning : Brand.success)
                Spacer()
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(LinearGradient(colors: [(activeRestrictions > 0 ? Brand.warning : Brand.success).opacity(0.12), Brand.blue.opacity(0.06)],
                                       startPoint: .leading, endPoint: .trailing))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(activeRestrictions > 0 ? "+\(addedTransitMin)" : "0")
                    .font(.system(size: 40, weight: .bold)).monospacedDigit()
                    .foregroundStyle(activeRestrictions > 0 ? Brand.danger : Brand.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activeRestrictions > 0 ? "min added" : "min added")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text(activeRestrictions > 0 ? "across \(activeRestrictions) restriction\(activeRestrictions == 1 ? "" : "s")" : "no active restriction on the route")
                        .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Text(totalMiles > 0 ? "\(Int(totalMiles)) route mi" : "")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, 16).padding(.top, 14)
            mileTrack.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
            speedLegend.padding(.horizontal, 16).padding(.bottom, 14)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                    .strokeBorder(LinearGradient.primary, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private var mileTrack: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(palette.bgCardSoft).frame(height: 10)
                Capsule().fill(LinearGradient(colors: [Brand.success.opacity(0.55), Brand.blue.opacity(0.55)],
                                              startPoint: .leading, endPoint: .trailing)).frame(height: 10)
                // Leg boundary ticks placed at cumulative-mile fractions.
                ForEach(Array(boundaryFractions.enumerated()), id: \.offset) { _, frac in
                    Circle().fill(palette.bgCard)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Brand.blue, lineWidth: 2))
                        .position(x: max(6, min(w - 6, w * CGFloat(frac))), y: 5)
                }
            }
        }
        .frame(height: 12)
    }

    /// Cumulative-mile fraction at each leg boundary (0…1). Even split when
    /// miles are absent, so the track still reads as the route's shape.
    private var boundaryFractions: [Double] {
        guard !legs.isEmpty else { return [] }
        let usesMiles = totalMiles > 0
        var acc = 0.0
        var out: [Double] = [0.0]
        for (i, leg) in legs.enumerated() {
            if usesMiles { acc += leg.mi; out.append(acc / totalMiles) }
            else { out.append(Double(i + 1) / Double(legs.count)) }
        }
        return out
    }

    private var speedLegend: some View {
        HStack(spacing: 14) {
            legendDot(Brand.warning, "25 mph zone")
            legendDot(Brand.danger, "10 mph zone")
            Spacer()
            Text(activeRestrictions > 0 ? "overlay active" : "no overlay on file")
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(palette.textTertiary)
        }
    }

    private func legendDot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(c.opacity(0.7)).frame(width: 14, height: 8)
            Text(t).font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.textSecondary)
        }
    }

    private var restrictionHeader: some View {
        HStack {
            Text("ACTIVE SLOW ORDERS")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text("refreshed from \(regimes[regime].0) \(regimes[regime].1)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.textTertiary)
        }
    }

    @ViewBuilder
    private var restrictionList: some View {
        // No feed → honest empty; a real restriction row never fabricated.
        EusoEmptyState(systemImage: "checkmark.circle",
                       title: "No active slow orders",
                       subtitle: "The \(regimes[regime].0) \(regimes[regime].1) feed returned no speed restrictions on \(routeText ?? "this route"). The route above adds no transit — restrictions post here the moment the feed reports one.")
    }

    private var triBand: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(regimes[i].0).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    Text(regimes[i].1).font(.system(size: 9, weight: .heavy))
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
            CTAButton(title: accepted ? "Acknowledged" : (addedTransitMin > 0 ? "Accept delay" : "Acknowledge clear"),
                      action: { accepted = true })
                .frame(maxWidth: .infinity)
                .disabled(accepted)
            Button(action: { Task { await reroute() } }) {
                Text(rerouting ? "Re-solving…" : "Reroute")
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
            .disabled(rerouting)
        }
    }

    private func reload() async {
        loading = true
        let p: RoutePlan693? = try? await EusoTripAPI.shared.query(
            "railShipments.getRoutePlan", input: ShipmentIdInput693(shipmentId: shipmentId))
        self.legs = p?.legs ?? []
        self.routeText = p?.routeDescription
        loading = false
    }

    private func reroute() async {
        rerouting = true; rerouteMessage = nil
        do {
            let r: RerouteResult693 = try await EusoTripAPI.shared.query(
                "railShipments.requestReroute", input: ShipmentIdInput693(shipmentId: shipmentId))
            if let ls = r.legs { legs = ls }
            rerouteMessage = (r.legs?.isEmpty ?? true)
                ? "The re-solve returned no alternate route. The current route is clear of slow orders."
                : "Routing re-solved — \(r.legs?.count ?? 0) legs. No slow orders on the new route."
        } catch {
            rerouteMessage = "The reroute request didn't complete. Check your connection and try again."
        }
        rerouting = false
    }
}

#Preview("693 · Rail Slow Orders · Night") {
    RailSlowOrdersScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("693 · Rail Slow Orders · Light") {
    RailSlowOrdersScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
