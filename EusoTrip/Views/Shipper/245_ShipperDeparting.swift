//
//  245_ShipperDeparting.swift
//  EusoTrip — Shipper · Loads · In Transit · Departing (brick 245).
//
//  Faithful SwiftUI reconstruction of `02 Shipper/Dark-SVG/245 Shipper
//  Departing.svg` (canvas 440×956). §284 SHIPPER-TRACK DEPARTING /
//  IN_TRANSIT OPENS — within-track FIFTH-PORT pattern 2/3 (direct
//  lifecycle cousin of 244 At Dock). Shipper observer vantage on a load
//  that has just rolled out of the dock: §60.2 context callout banner
//  (BeamConverge glyph · POST-LOCK PORT 17), §272 Aurora dispatch recap,
//  KPI quartet (ETA PHX 5h 28m · MILES 372 · TEMP 35°F · PAYABLE $2,861),
//  8-stage lifecycle strip with IN_TRANSIT current + DEPARTING micro-chip,
//  route-progress map strip (I-10 EAST corridor · LA pin · Phoenix diamond
//  · ME tractor · Indio chain-stop · ETA meter), ROUTE TERM ROSTER (6
//  rows), shipper-economics footer, and a TRACK LIVE / NOTIFY CONSIGNEE
//  action ribbon.
//
//  Persona canon (§11): Diego Usoro (DU · shipper tracking) · Michael
//  Eusorone (ME · rolling) · Aurora Freight Lines / Renée Marquette (RM ·
//  senior dispatcher). Flagship lane LD-260427-7C3A09F18B · Los Angeles →
//  Phoenix · 53' Reefer · 33-38°F · I-10 EAST · 372mi · ETA 5h 28m ·
//  BOL #BOL-7C3A signed.
//
//  Wiring (honest — no mock data):
//    • loads.getDetail(id:)            EXISTS — full load record (lane,
//      cargo, equipment, rate, status, assigned driverId).
//    • appointments.getByLoad(loadId:) EXISTS — final dwell / gate-exit
//      context for the departed-from-dock recap.
//    • telemetry.getLiveLocation(driverId:) EXISTS — backs the TRACK LIVE
//      CTA (live carrier pin on the I-10 corridor).
//    • controlTower "pin to control tower"   STUB · named-gap — no
//      mutation has shipped on the controlTower.* namespace (read-only
//      overview/exceptions only). TRACK LIVE fetches the live pin then
//      flags the pin-write as a stub.
//    • "notify consignee"                     STUB · named-gap — no
//      shipper→consignee notify mutation has shipped. The secondary CTA
//      flags the gap rather than faking a send.
//
//  RBAC gate: SHIPPER (read-side observer · §284). transportMode: truck.
//  country: US.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Store

@MainActor
final class ShipperDepartingStore: ObservableObject {
    enum Phase {
        case idle
        case loading
        case loaded(LoadsAPI.LoadDetail, AppointmentsAPI.ByLoadAppointment?)
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle

    /// Track-live action state (TRACK LIVE · pin to control tower).
    @Published var trackingInFlight = false
    @Published var trackingResult: String? = nil

    /// Notify-consignee action state (secondary CTA · STUB-gated).
    @Published var notifyResult: String? = nil

    @Published var actionError: String? = nil

    private let api: EusoTripAPI
    let loadId: String
    init(loadId: String, api: EusoTripAPI = .shared) {
        self.loadId = loadId
        self.api = api
    }

    func load() async {
        phase = .loading
        do {
            // EXISTS · loads.getById — primary departing load record.
            guard let detail = try await api.loads.getDetail(id: loadId) else {
                phase = .error("Load \(loadId) not found.")
                return
            }
            // EXISTS · appointments.getByLoad — final dwell + gate-exit
            // context. A nil appointment is a legitimate empty state
            // (no dock record) — never faked.
            let appt = try await api.appointments.getByLoad(loadId: loadId)
            phase = .loaded(detail, appt)
        } catch {
            phase = .error("Couldn't reach the route feed.")
        }
    }

    /// TRACK LIVE · pin to control tower. Fetches the live carrier pin
    /// (EXISTS) for the assigned driver, then flags the pin-to-control-
    /// tower write as a named stub.
    func trackLive(driverId: Int?) async {
        guard let driverId else {
            actionError = "No carrier assigned yet — nothing to track."
            return
        }
        trackingInFlight = true
        actionError = nil
        trackingResult = nil
        do {
            // EXISTS · telemetry.getLiveLocation — real live pin.
            let loc = try await api.shipperTelemetry.getLiveLocation(driverId: driverId)
            // STUB · named-gap — controlTower has no pin-write mutation.
            trackingResult = loc.stale
                ? "Live pin is stale · pin-to-control-tower not yet wired (STUB)"
                : "Live pin acquired · pin-to-control-tower not yet wired (STUB)"
            trackingInFlight = false
        } catch {
            trackingInFlight = false
            actionError = "Couldn't reach live tracking."
        }
    }

    /// NOTIFY CONSIGNEE · secondary CTA. No shipper→consignee notify
    /// mutation has shipped on any router — flag the named gap rather
    /// than faking a delivery-notify send.
    func notifyConsignee() {
        actionError = nil
        // STUB · named-gap — no consignee-notify mutation exists.
        notifyResult = "Consignee notify not yet wired (STUB)"
    }
}

// MARK: - Screen

struct ShipperDeparting: View {
    @Environment(\.palette) private var palette
    @StateObject private var store: ShipperDepartingStore

    /// Default-initializable — calibrated against the §11 flagship lane.
    init(loadId: String = "7C3A09F18B") {
        _store = StateObject(wrappedValue: ShipperDepartingStore(loadId: loadId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                topBar
                headline
                IridescentHairline()
                calloutBanner
                dispatchRecapCard
                kpiQuartet
                lifecycleStrip
                routeMap
                rosterHeader
                rosterRows
                economicsFooter
                actionRibbon
                statusFeedback
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
        }
        .background(palette.bgPage.ignoresSafeArea())
        .task { await store.load() }
        .refreshable { await store.load() }
    }

    // MARK: TopBar (SVG y=72)

    private var topBar: some View {
        HStack(alignment: .top) {
            Text("✦ SHIPPER · LOADS · IN TRANSIT · DEPARTING")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("I-10 EAST · ETA 5H 28M")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .monospacedDigit().multilineTextAlignment(.trailing)
        }
    }

    // MARK: Headline + sub + DU disc (SVG y=116/140 + disc @ 364,86)

    private var headline: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Rolling to Phoenix")
                    .font(.system(size: 34, weight: .bold)).tracking(-0.6)
                    .foregroundStyle(palette.textPrimary)
                Text("I-10 EAST · 372mi · ETA 5h 28m · BOL #BOL-7C3A signed")
                    .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 8)
            personaDisc("DU", diameter: 56, font: 14)
                .offset(y: -2)
        }
    }

    // MARK: §60.2 callout banner (SVG y=172)

    private var calloutBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            beamConvergeGlyph
                .frame(width: 22, height: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("SHIPPER DEPARTING · §284 · WITHIN-TRACK FIFTH-PORT 2/3")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(LinearGradient.primary)
                Text("LD-7C3A LA→Phoenix · Reefer 33-38°F · I-10 EAST · ETA 5H 28M · ME rolling · DU tracking")
                    .font(.system(size: 10)).foregroundStyle(palette.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13).padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.16), Brand.magenta.opacity(0.16)],
                                     startPoint: .leading, endPoint: .trailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.40), lineWidth: 1)
        )
    }

    private var beamConvergeGlyph: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let left: CGFloat = 0, mid = w * 0.82, midY = h * 0.5
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: left, y: h * 0.1));  p.addLine(to: CGPoint(x: mid, y: midY))
                    p.move(to: CGPoint(x: left, y: midY));     p.addLine(to: CGPoint(x: mid, y: midY))
                    p.move(to: CGPoint(x: left, y: h * 0.9));  p.addLine(to: CGPoint(x: mid, y: midY))
                }
                .stroke(LinearGradient.primary, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                Circle().fill(LinearGradient.primary).frame(width: 5, height: 5).position(x: mid, y: midY)
            }
        }
    }

    // MARK: §272 Aurora dispatch recap (SVG y=224)

    private var dispatchRecapCard: some View {
        HStack(alignment: .top, spacing: 10) {
            personaDisc("RM", diameter: 32, font: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text("§272 AURORA DISPATCHED ME · 0:01 DEPARTED · DWELL 1:42 FINAL · NO DETENTION")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(LinearGradient.primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("Aurora Freight Lines · Renée Marquette · senior dispatcher")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("USDOT 3 482 119 · MC-942 008 · Cedar Rapids IA")
                    .font(EType.mono(.caption)).tracking(0.3).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .background(palette.bgCard)
        .overlay(alignment: .leading) {
            Rectangle().fill(LinearGradient.diagonal).frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
        }
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: KPI quartet hero · gradient rim (SVG y=290)

    private var kpiQuartet: some View {
        HStack(spacing: 0) {
            kpi(label: "ETA PHX", value: "5h 28m", sub: "live · OTA", valueStyle: .gradient)
            kpiDivider
            kpi(label: "MILES",  value: "372",    sub: "to delivery", valueStyle: .solid(Brand.blue))
            kpiDivider
            kpi(label: "TEMP",   value: "35°F",   sub: "REEFER LOG", valueStyle: .solid(Brand.blue))
            kpiDivider
            kpi(label: "PAYABLE", value: "$2,861", sub: "NET-30", valueStyle: .solid(Brand.blue))
        }
        .padding(.vertical, 12).padding(.horizontal, 16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    private enum KPIValueStyle { case gradient; case solid(Color) }

    private func kpi(label: String, value: String, sub: String, valueStyle: KPIValueStyle) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textSecondary)
            Group {
                switch valueStyle {
                case .gradient: Text(value).foregroundStyle(LinearGradient.diagonal)
                case .solid(let c): Text(value).foregroundStyle(c)
                }
            }
            .font(.system(size: 18, weight: .heavy)).monospacedDigit().tracking(-0.4)
            .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.system(size: 10)).foregroundStyle(palette.textSecondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kpiDivider: some View {
        Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1, height: 32)
    }

    // MARK: 8-stage lifecycle strip · IN_TRANSIT current (SVG y=376)

    private var lifecycleStrip: some View {
        ZStack {
            GeometryReader { geo in
                let w = geo.size.width
                let inset: CGFloat = 22
                let span = w - inset * 2
                let count = 8
                let step = span / CGFloat(count - 1)
                let currentIndex = 4
                let y = geo.size.height / 2
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.white.opacity(0.12)).frame(width: span, height: 2)
                        .offset(x: inset, y: y - 1)
                    Rectangle().fill(LinearGradient.primary)
                        .frame(width: step * CGFloat(currentIndex), height: 2)
                        .offset(x: inset, y: y - 1)
                    ForEach(0..<count, id: \.self) { i in
                        lifecycleNode(state: i < currentIndex ? .done : (i == currentIndex ? .current : .future))
                            .position(x: inset + step * CGFloat(i), y: y)
                    }
                    // DEPARTING micro-chip pinning the IN_TRANSIT node.
                    Text("DEPARTING")
                        .font(.system(size: 6.4, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(LinearGradient.primary))
                        .position(x: inset + step * CGFloat(currentIndex), y: y - 13)
                }
            }
        }
        .frame(height: 38)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private enum NodeState { case done, current, future }

    @ViewBuilder
    private func lifecycleNode(state: NodeState) -> some View {
        switch state {
        case .done:
            Circle().fill(LinearGradient.primary).frame(width: 10, height: 10)
        case .current:
            ZStack {
                Circle().strokeBorder(LinearGradient.primary, lineWidth: 2).frame(width: 18, height: 18)
                Circle().fill(LinearGradient.primary).frame(width: 12, height: 12)
                Circle().fill(palette.bgCard).frame(width: 4, height: 4)
            }
        case .future:
            Circle().fill(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderStrong, lineWidth: 1))
                .frame(width: 8, height: 8)
        }
    }

    // MARK: Route-progress map strip · 96h (SVG y=424)

    private var routeMap: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                // SVG corridor spans x=40..360 on a 400-wide card; map to
                // the live width so the route line scales responsively.
                let leftX = w * (40.0 / 400.0)
                let rightX = w * (360.0 / 400.0)
                let lineY = h * (50.0 / 96.0)
                let span = rightX - leftX
                ZStack(alignment: .topLeading) {
                    // Inner panel.
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color(hex: 0x10131A))
                        .padding(1)

                    // Corridor title.
                    Text("I-10 EAST · LA · NATURIPE RDC → PHOENIX")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: w, alignment: .center)
                        .position(x: w / 2, y: h * (20.0 / 96.0))

                    // Base corridor line + progress segment.
                    Capsule().fill(Color.white.opacity(0.16))
                        .frame(width: span, height: 3)
                        .position(x: leftX + span / 2, y: lineY)
                    Capsule().fill(LinearGradient.primary)
                        .frame(width: w * (10.0 / 400.0), height: 3)
                        .position(x: leftX + w * (5.0 / 400.0), y: lineY)

                    // LA · NATURIPE RDC origin pin (DU disc).
                    personaDisc("DU", diameter: 14, font: 6)
                        .position(x: leftX, y: lineY)
                    Text("LA · NATURIPE RDC")
                        .font(.system(size: 6.5, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize()
                        .position(x: leftX + 30, y: lineY + 18)

                    // Phoenix destination diamond.
                    Rectangle()
                        .fill(Color(hex: 0x10131A))
                        .frame(width: 10, height: 10)
                        .overlay(Rectangle().strokeBorder(LinearGradient.primary, lineWidth: 1.4))
                        .rotationEffect(.degrees(45))
                        .position(x: rightX, y: lineY)
                    Text("PHOENIX")
                        .font(.system(size: 6.5, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(LinearGradient.primary)
                        .fixedSize()
                        .position(x: rightX - 18, y: lineY + 18)

                    // ME tractor (just departed origin).
                    HStack(spacing: 0) {
                        Text("ME").font(.system(size: 7, weight: .heavy)).tracking(0.3)
                            .foregroundStyle(.white)
                        Text("→").font(.system(size: 7, weight: .heavy))
                            .foregroundStyle(.white).padding(.leading, 4)
                    }
                    .frame(width: 28, height: 14)
                    .background(RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.diagonal))
                    .position(x: leftX + w * (10.0 / 400.0), y: lineY)

                    // Indio chain-stop marker + label.
                    Circle()
                        .fill(Color(hex: 0x10131A))
                        .overlay(Circle().strokeBorder(Brand.blue.opacity(0.65), lineWidth: 1.0))
                        .frame(width: 6, height: 6)
                        .position(x: w * (155.0 / 400.0), y: lineY)
                    Text("INDIO 132mi")
                        .font(.system(size: 6, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(Brand.blue)
                        .fixedSize()
                        .position(x: w * (155.0 / 400.0), y: lineY - 10)

                    // ETA meter chip (top-right).
                    HStack(spacing: 4) {
                        Text("ETA").font(.system(size: 6, weight: .heavy)).tracking(0.3)
                            .foregroundStyle(palette.textSecondary)
                        Spacer(minLength: 4)
                        Text("5H 28M").font(.system(size: 8, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(LinearGradient.primary)
                    }
                    .padding(.horizontal, 8)
                    .frame(width: 60, height: 18)
                    .background(RoundedRectangle(cornerRadius: 2).fill(palette.bgCard))
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Brand.blue.opacity(0.65), lineWidth: 0.8))
                    .position(x: w * (350.0 / 400.0), y: h * (28.0 / 96.0))

                    // Footer route line.
                    Text("ROUTE · I-10 EAST · NEXT Indio CA · 132mi")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(LinearGradient.primary)
                        .fixedSize()
                        .position(x: leftX - 26 + 100, y: h * (86.0 / 96.0))
                    Text("ETA 5H 28M")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5).monospacedDigit()
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize()
                        .frame(width: w - 28, alignment: .trailing)
                        .position(x: w / 2 - 7, y: h * (86.0 / 96.0))
                }
            }
        }
        .frame(height: 96)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: ROUTE TERM ROSTER header (SVG y=536)

    private var rosterHeader: some View {
        HStack {
            Text("ROUTE TERM ROSTER · 6")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("SHIPPER READ-SIDE · §284")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(.top, 4)
    }

    // MARK: Roster rows 1-6 (SVG y=546…806)

    private var rosterRows: some View {
        VStack(spacing: 4) {
            // Row 1 · LINE HAUL · gradient rim · §11.4 founder pin 57th.
            rosterRow(
                eyebrow: "§11.4 LINE HAUL · EUSORONE FOUNDER PIN · 57TH",
                detail: "DU paid · ME drives · NET-30 due to AUR-MC942008",
                amount: "$2,425", tag: "PAYABLE",
                rim: .gradient, eyebrowGradient: true, amountGradient: true)
            // Row 2 · FUEL SURCHARGE · info rim.
            rosterRow(
                eyebrow: "Fuel surcharge",
                detail: "18% of line-haul · DOE diesel-2 weekly",
                amount: "$436", tag: "FSC 18%",
                rim: .solid(Brand.blue), eyebrowGradient: false, amountGradient: false,
                titleStyle: true)
            // Row 3 · DETENTION · info rim · NO DETENTION.
            rosterRow(
                eyebrow: "Detention · final",
                detail: "2h free window · DWELL 1:42 FINAL · stopped at gate exit",
                amount: "$0", tag: "NO DETENTION",
                rim: .solid(Brand.blue), eyebrowGradient: false, amountGradient: false,
                titleStyle: true)
            // Row 4 · LUMPER · info rim · SETTLED.
            rosterRow(
                eyebrow: "Lumper · settled",
                detail: "OTR Solutions ticket #LMP-7C3A · receipt to Diego · pass-through",
                amount: "$185", tag: "SETTLED",
                rim: .solid(Brand.blue), eyebrowGradient: false, amountGradient: false,
                titleStyle: true, amountColor: Brand.blue)
            // Row 5 · ESCORT · default rim · N/A.
            rosterRow(
                eyebrow: "Escort",
                detail: "N/A · ambient reefer · no escort required",
                amount: "NONE", tag: "NOT REQ",
                rim: .solid(Brand.neutral.opacity(0.55)), eyebrowGradient: false, amountGradient: false,
                titleStyle: true, amountColor: palette.textSecondary, tagColor: palette.textSecondary)
            // Row 6 · LANE TRACE · gradient rim · §284.1 substitution.
            rosterRow(
                eyebrow: "LANE TRACE · §284.1 SHIPPER-DEPARTING FORWARD-FLIP",
                detail: "I-10 E · 372mi · ME ROLLING · TEMP 35°F LOGGED · BOL #BOL-7C3A",
                amount: "5H 28M", tag: "LIVE",
                rim: .gradient, eyebrowGradient: true, amountGradient: true)
        }
    }

    private enum RowRim { case gradient; case solid(Color) }

    private func rosterRow(
        eyebrow: String, detail: String, amount: String, tag: String,
        rim: RowRim,
        eyebrowGradient: Bool, amountGradient: Bool,
        titleStyle: Bool = false,
        amountColor: Color? = nil, tagColor: Color? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Group {
                    if eyebrowGradient {
                        Text(eyebrow).font(.system(size: 9, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(LinearGradient.primary)
                    } else {
                        Text(eyebrow).font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                    }
                }.lineLimit(1).minimumScaleFactor(0.8)
                Text(detail).font(EType.mono(.caption)).tracking(0.3)
                    .foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                Group {
                    if amountGradient {
                        Text(amount).foregroundStyle(LinearGradient.diagonal)
                    } else {
                        Text(amount).foregroundStyle(amountColor ?? palette.textPrimary)
                    }
                }.font(.system(size: 13, weight: .heavy)).monospacedDigit()
                Group {
                    if amountGradient {
                        Text(tag).foregroundStyle(LinearGradient.primary)
                    } else {
                        Text(tag).foregroundStyle(tagColor ?? Brand.blue)
                    }
                }.font(.system(size: 9, weight: .heavy)).tracking(0.5).monospacedDigit()
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 14)
        .background(palette.bgCard)
        .overlay(alignment: .leading) {
            accentBar(rim)
        }
        .overlay(rimOverlay(rim))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    @ViewBuilder
    private func accentBar(_ rim: RowRim) -> some View {
        switch rim {
        case .gradient:
            Rectangle().fill(LinearGradient.diagonal).frame(width: 3)
        case .solid(let c):
            Rectangle().fill(c).frame(width: 3)
        }
    }

    @ViewBuilder
    private func rimOverlay(_ rim: RowRim) -> some View {
        switch rim {
        case .gradient:
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.55), lineWidth: 1)
        case .solid:
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        }
    }

    // MARK: Shipper-economics footer (SVG y=818)

    private var economicsFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SHIPPER ECONOMICS · NET-30 · 57TH FOUNDER PIN · 5TH-PORT 2/3")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(LinearGradient.primary)
            Text("$2,861 total payable · BeamConverge POST-LOCK PORT 17 · WITHIN-TRACK FIFTH-PORT 2/3")
                .font(.system(size: 10)).foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.16), Brand.magenta.opacity(0.16)],
                                     startPoint: .leading, endPoint: .trailing))
        )
    }

    // MARK: Action ribbon · TRACK LIVE + NOTIFY CONSIGNEE (SVG y=860)

    private var actionRibbon: some View {
        HStack(spacing: 8) {
            // Primary · TRACK LIVE · gradient pill (armed).
            Button { Task { await store.trackLive(driverId: assignedDriverId) } } label: {
                HStack(spacing: 10) {
                    if store.trackingInFlight {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "scope").font(.system(size: 13, weight: .heavy))
                    }
                    Text("Track live · pin to control tower")
                        .font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(LinearGradient.primary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(store.trackingInFlight)

            // Secondary · NOTIFY CONSIGNEE · glass-rim pill.
            Button { store.notifyConsignee() } label: {
                Text("Notify consignee")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LinearGradient.primary)
                    .frame(width: 144, height: 44)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(LinearGradient.diagonal.opacity(0.55), lineWidth: 1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var statusFeedback: some View {
        if let result = store.trackingResult {
            Label(result, systemImage: "dot.radiowaves.left.and.right")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 2)
        }
        if let notify = store.notifyResult {
            Label(notify, systemImage: "bell.badge")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 2)
        }
        if let err = store.actionError {
            Label(err, systemImage: "exclamationmark.triangle.fill")
                .font(EType.caption).foregroundStyle(Brand.warning)
                .padding(.horizontal, 2)
        }
        if case .error(let m) = store.phase {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
                Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
                Spacer()
                Button("Retry") { Task { await store.load() } }
                    .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.info)
            }
            .padding(Space.s3).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        if case .loading = store.phase {
            HStack {
                ProgressView()
                Text("Loading route feed…").font(EType.caption).foregroundStyle(palette.textSecondary)
                Spacer()
            }.padding(.horizontal, 2)
        }
    }

    // MARK: Helpers

    private var assignedDriverId: Int? {
        guard case .loaded(let detail, _) = store.phase else { return nil }
        return detail.driverId
    }

    private func personaDisc(_ initials: String, diameter: CGFloat, font: CGFloat) -> some View {
        ZStack {
            Circle().fill(LinearGradient.diagonal)
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.55), .white.opacity(0)],
                                     center: .init(x: 0.35, y: 0.30),
                                     startRadius: 0, endRadius: diameter * 0.55))
                .frame(width: diameter * 0.72, height: diameter * 0.72)
            Text(initials).font(.system(size: font, weight: .heavy)).tracking(0.6)
                .foregroundStyle(.white)
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Previews

#Preview("245 · Shipper Departing · Night") {
    ShipperDeparting()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("245 · Shipper Departing · Afternoon") {
    ShipperDeparting()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
}
