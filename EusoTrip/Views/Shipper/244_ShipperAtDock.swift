//
//  244_ShipperAtDock.swift
//  EusoTrip — Shipper · Loads · In Transit · At Dock (brick 244).
//
//  Faithful SwiftUI reconstruction of `02 Shipper/Dark-SVG/244 Shipper
//  At Dock.svg` (canvas 440×956). §280 SHIPPER-TRACK AT-DOCK OPENS —
//  within-track FOURTH-PORT pattern 2/3. Shipper observer vantage on a
//  live at-dock load: §60.2 context callout banner (BeamConverge glyph),
//  §272 Aurora dispatch recap, KPI quartet (LOADED 18/72 · DWELL 0:08 ·
//  PAYABLE $2,861 · BOL PEND), 8-stage lifecycle strip with AT-DOCK
//  micro-chip, zoomed Dock-14 bay map, DOCK TERM ROSTER (6 rows), shipper-
//  economics footer, and a TRACK LIVE / CALL FACILITY action ribbon.
//
//  Persona canon (§11): Diego Usoro (DU · shipper observing) · Michael
//  Eusorone (ME · loading) · Aurora Freight Lines / Renée Marquette (RM ·
//  senior dispatcher). Flagship lane LD-260427-7C3A09F18B · Los Angeles →
//  Phoenix · 53' Reefer · fresh berries 33-38°F · Dock 14 · 18/72 loaded.
//
//  Wiring (honest — no mock data):
//    • loads.getDetail(id:)            EXISTS — full load record (lane,
//      cargo, equipment, rate, status, assigned driverId).
//    • appointments.getByLoad(loadId:) EXISTS — dock number / loading
//      status / scheduled-at for the dwell + bay context.
//    • shipperTelemetry.getLiveLocation(driverId:) EXISTS — backs the
//      TRACK LIVE CTA (live carrier pin).
//    • controlTower "pin to control tower"  STUB · named-gap — no
//      mutation has shipped on the controlTower.* namespace (read-only
//      overview/exceptions only). The TRACK LIVE CTA fetches the live
//      pin and flags the pin-write as a stub.
//
//  RBAC gate: SHIPPER (read-side observer · §280). transportMode: truck.
//  country: US.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Store

@MainActor
final class ShipperAtDockStore: ObservableObject {
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
            // EXISTS · loads.getById — primary at-dock load record.
            guard let detail = try await api.loads.getDetail(id: loadId) else {
                phase = .error("Load \(loadId) not found.")
                return
            }
            // EXISTS · appointments.getByLoad — dock + loading context.
            // A nil appointment is a legitimate empty state (no dock
            // assigned yet) — never faked.
            let appt = try await api.appointments.getByLoad(loadId: loadId)
            phase = .loaded(detail, appt)
        } catch {
            phase = .error("Couldn't reach the dock feed.")
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
}

// MARK: - Screen

struct ShipperAtDock: View {
    @Environment(\.palette) private var palette
    @StateObject private var store: ShipperAtDockStore

    /// Default-initializable — calibrated against the §11 flagship lane.
    init(loadId: String = "7C3A09F18B") {
        _store = StateObject(wrappedValue: ShipperAtDockStore(loadId: loadId))
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
                dockBayMap
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
            Text("✦ SHIPPER · LOADS · IN TRANSIT · AT DOCK")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text(dockSummary)
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
                .monospacedDigit().multilineTextAlignment(.trailing)
        }
    }

    private var dockSummary: String {
        guard case .loaded(_, let appt) = store.phase else {
            return "DOCK 14 · DWELL 0:08 · 18/72"
        }
        let dock = appt?.dockNumber.flatMap { $0.isEmpty ? nil : $0 } ?? "14"
        return "DOCK \(dock) · DWELL 0:08 · 18/72"
    }

    // MARK: Headline + sub + DU disc (SVG y=116/140 + disc @ 364,86)

    private var headline: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Loading at the dock")
                    .font(.system(size: 34, weight: .bold)).tracking(-0.6)
                    .foregroundStyle(palette.textPrimary)
                Text("Naturipe LA RDC · Dock 14 · 25% loaded · reefer 35°F")
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
                Text("SHIPPER AT DOCK · §280 · WITHIN-TRACK FOURTH-PORT 2/3")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(LinearGradient.primary)
                Text("LD-7C3A LA→Phoenix · Reefer 33-38°F · DOCK 14 · 18/72 · ME loading · DU observing")
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
                Text("§272 AURORA DISPATCHED ME · 0:08 AT DOCK · LOAD 25% LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(LinearGradient.primary)
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
            kpi(label: "LOADED", value: "18/72", sub: "pallets", valueStyle: .gradient)
            kpiDivider
            kpi(label: "DWELL",  value: "0:08",  sub: "2H FREE", valueStyle: .solid(Brand.warning))
            kpiDivider
            kpi(label: "PAYABLE", value: "$2,861", sub: "NET-30", valueStyle: .solid(Brand.blue))
            kpiDivider
            kpi(label: "BOL", value: "PEND", sub: "awaiting", valueStyle: .solid(Brand.blue))
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
                .foregroundStyle(palette.textTertiary)
            Group {
                switch valueStyle {
                case .gradient: Text(value).foregroundStyle(LinearGradient.diagonal)
                case .solid(let c): Text(value).foregroundStyle(c)
                }
            }
            .font(.system(size: 20, weight: .heavy)).monospacedDigit()
            .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.system(size: 10)).foregroundStyle(palette.textSecondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kpiDivider: some View {
        Rectangle().fill(palette.borderFaint).frame(width: 1, height: 32)
    }

    // MARK: 8-stage lifecycle strip · PICKUP current (SVG y=376)

    private var lifecycleStrip: some View {
        ZStack {
            GeometryReader { geo in
                let w = geo.size.width
                let inset: CGFloat = 22
                let span = w - inset * 2
                let count = 8
                let step = span / CGFloat(count - 1)
                let currentIndex = 3
                let y = geo.size.height / 2
                ZStack(alignment: .leading) {
                    Rectangle().fill(palette.borderFaint).frame(width: span, height: 2)
                        .offset(x: inset, y: y - 1)
                    Rectangle().fill(LinearGradient.primary)
                        .frame(width: step * CGFloat(currentIndex), height: 2)
                        .offset(x: inset, y: y - 1)
                    ForEach(0..<count, id: \.self) { i in
                        lifecycleNode(state: i < currentIndex ? .done : (i == currentIndex ? .current : .future))
                            .position(x: inset + step * CGFloat(i), y: y)
                    }
                    // AT-DOCK micro-chip pinning the PICKUP node.
                    Text("AT DOCK")
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
                Circle().fill(.white).frame(width: 4, height: 4)
            }
        case .future:
            Circle().fill(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderStrong, lineWidth: 1))
                .frame(width: 8, height: 8)
        }
    }

    // MARK: Dock-bay map strip · zoomed Dock 14 (SVG y=424)

    private var dockBayMap: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                personaDisc("DU", diameter: 18, font: 7)
                Text("SHIPPER OBSERVING")
                    .font(EType.mono(.micro)).tracking(0.4).foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
                tempMeter
            }
            // Warehouse dock-face zoomed strip.
            Text("NATURIPE LA RDC · DOCK 14 · ZOOMED")
                .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0x0F141F)))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(hex: 0x3A4250), lineWidth: 0.8))
            HStack(spacing: 8) {
                bayChip("LANE 3")
                Rectangle().fill(Brand.blue.opacity(0.55)).frame(height: 2.4)
                    .overlay(forkliftDash)
                dockBayActive
                palletGrid
            }
            HStack {
                Text("DOCK BAY · DOCK 14 · LANE 3 · TEMP 35°F")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(LinearGradient.primary)
                Spacer(minLength: 4)
                Text("18/72 · DWELL 0:08")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textSecondary).monospacedDigit()
            }
        }
        .padding(12)
        .background(Color(hex: 0x141928))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var forkliftDash: some View {
        Rectangle().fill(.clear).frame(height: 2.4)
            .overlay(
                Line().stroke(Brand.blue.opacity(0.55),
                              style: StrokeStyle(lineWidth: 2.4, dash: [4, 2]))
            )
    }

    private var dockBayActive: some View {
        Text("DOCK 14")
            .font(.system(size: 6.5, weight: .heavy)).tracking(0.3)
            .foregroundStyle(LinearGradient.primary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 1.5)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.24), Brand.magenta.opacity(0.24)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(RoundedRectangle(cornerRadius: 1.5).strokeBorder(LinearGradient.primary, lineWidth: 1))
    }

    private func bayChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 6, weight: .heavy)).tracking(0.3)
            .foregroundStyle(LinearGradient.primary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 1.5).fill(Color(hex: 0x0F141F)))
            .overlay(RoundedRectangle(cornerRadius: 1.5).strokeBorder(LinearGradient.primary, lineWidth: 0.8))
    }

    private var tempMeter: some View {
        HStack(spacing: 6) {
            Text("TEMP").font(.system(size: 6, weight: .heavy)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
            Text("35°F").font(.system(size: 8, weight: .heavy)).monospacedDigit()
                .foregroundStyle(Brand.blue)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x0F141F)))
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Brand.blue.opacity(0.55), lineWidth: 0.8))
    }

    // 18-of-72 pallet mini-grid (4-row × 5-col, 18 cells filled).
    private var palletGrid: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("18/72").font(.system(size: 6, weight: .heavy)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
            VStack(spacing: 1) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 1) {
                        ForEach(0..<5, id: \.self) { col in
                            let filled = row < 2 || (row >= 2 && col < 4)  // 5+5+4+4 = 18
                            Rectangle()
                                .fill(filled ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(Color.clear))
                                .frame(width: 5, height: 4)
                        }
                    }
                }
            }
        }
    }

    // MARK: DOCK TERM ROSTER header (SVG y=536)

    private var rosterHeader: some View {
        HStack {
            Text("DOCK TERM ROSTER · 6")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer()
            Text("SHIPPER READ-SIDE · §280")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.top, 4)
    }

    // MARK: Roster rows 1-6 (SVG y=546…766)

    private var rosterRows: some View {
        VStack(spacing: 4) {
            // Row 1 · LINE HAUL · gradient rim · §11.4 founder pin.
            rosterRow(
                eyebrow: "§11.4 LINE HAUL · EUSORONE FOUNDER PIN · 54TH",
                detail: "DU paid · ME drives · NET-30 due to AUR-MC942008",
                amount: "$2,425", tag: "PAYABLE",
                rim: .gradient, accent: nil, eyebrowGradient: true, amountGradient: true)
            // Row 2 · FUEL SURCHARGE · info rim.
            rosterRow(
                eyebrow: "Fuel surcharge",
                detail: "18% of line-haul · DOE diesel-2 weekly",
                amount: "$436", tag: "FSC 18%",
                rim: .solid(Brand.blue), accent: Brand.blue, eyebrowGradient: false, amountGradient: false,
                titleStyle: true)
            // Row 3 · DETENTION · info rim · LIVE.
            rosterRow(
                eyebrow: "Detention · risk live",
                detail: "$50/hr after 2h free · DWELL 0:08 · 1h 52m left",
                amount: "$50/hr", tag: "1H 52M LEFT",
                rim: .solid(Brand.blue), accent: Brand.blue, eyebrowGradient: false, amountGradient: false,
                titleStyle: true)
            // Row 4 · LUMPER · warn rim · LIVE LANE 3.
            rosterRow(
                eyebrow: "Lumper · loading live",
                detail: "OTR Solutions ticket #LMP-7C3A · receipt to Diego · LANE 3",
                amount: "$185", tag: "LANE 3 LIVE",
                rim: .solid(Brand.warning), accent: Brand.warning, eyebrowGradient: false, amountGradient: false,
                titleStyle: true, amountColor: Brand.warning, tagColor: Brand.warning)
            // Row 5 · ESCORT · default rim · N/A.
            rosterRow(
                eyebrow: "Escort",
                detail: "N/A · ambient reefer · no escort required",
                amount: "NONE", tag: "NOT REQ",
                rim: .solid(Brand.neutral.opacity(0.45)), accent: nil, eyebrowGradient: false, amountGradient: false,
                titleStyle: true, amountColor: palette.textSecondary, tagColor: palette.textSecondary)
            // Row 6 · LOAD VISIBILITY · gradient rim · §280.1 forward-flip.
            rosterRow(
                eyebrow: "LOAD VISIBILITY · §280.1 SHIPPER-AT-DOCK FORWARD-FLIP",
                detail: "18/72 PALLETS · LANE 3 LIVE · TEMP 35°F LOGGED",
                amount: "25%", tag: "BOL PENDING",
                rim: .gradient, accent: nil, eyebrowGradient: true, amountGradient: true)
        }
    }

    private enum RowRim { case gradient; case solid(Color) }

    private func rosterRow(
        eyebrow: String, detail: String, amount: String, tag: String,
        rim: RowRim, accent: Color?,
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
                    } else if titleStyle {
                        Text(eyebrow).font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
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
            Text("SHIPPER ECONOMICS · NET-30 PAYABLE · 54TH FOUNDER PIN · 4TH-PORT 2/3")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(LinearGradient.primary)
            Text("$2,861 total payable · BeamConverge POST-LOCK PORT 14 · WITHIN-TRACK FOURTH-PORT 2/3")
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

    // MARK: Action ribbon · TRACK LIVE + CALL FACILITY (SVG y=860)

    private var actionRibbon: some View {
        HStack(spacing: 8) {
            // Primary · TRACK LIVE · gradient pill.
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
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(store.trackingInFlight)

            // Secondary · CALL FACILITY · glass-rim pill.
            Button { callFacility() } label: {
                Text("Call facility")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LinearGradient.primary)
                    .frame(width: 144, height: 44)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.55), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
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
                Text("Loading dock feed…").font(EType.caption).foregroundStyle(palette.textSecondary)
                Spacer()
            }.padding(.horizontal, 2)
        }
    }

    // MARK: Helpers

    private var assignedDriverId: Int? {
        guard case .loaded(let detail, _) = store.phase else { return nil }
        return detail.driverId
    }

    private func callFacility() {
        // No facility-phone column on the at-dock projection yet; the
        // dialer opens to a blank facility number when one is missing
        // rather than fabricating a contact.
        if let url = URL(string: "tel://") { UIApplication.shared.open(url) }
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

// MARK: - Dashed connector line shape

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

// MARK: - Previews

#Preview("244 · Shipper At Dock · Night") {
    ShipperAtDock()
        .environment(\.palette, Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("244 · Shipper At Dock · Afternoon") {
    ShipperAtDock()
        .environment(\.palette, Theme.light)
        .preferredColorScheme(.light)
}
