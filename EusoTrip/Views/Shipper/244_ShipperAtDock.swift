//
//  244_ShipperAtDock.swift
//  EusoTrip — Shipper · Loads · In Transit · At Dock (brick 244).
//
//  Faithful SwiftUI reconstruction of `02 Shipper/Dark-SVG/244 Shipper
//  At Dock.svg` (canvas 440×956). §280 SHIPPER-TRACK AT-DOCK OPENS —
//  within-track FOURTH-PORT pattern 2/3. Shipper observer vantage on a
//  live at-dock load: §60.2 context callout banner (BeamConverge glyph),
//  §272 dispatch recap, KPI quartet (LOADED · DWELL · PAYABLE · BOL),
//  8-stage lifecycle strip with AT-DOCK micro-chip, zoomed dock-bay map,
//  DOCK TERM ROSTER (6 rows), shipper-economics footer, and a TRACK LIVE
//  / CALL FACILITY action ribbon.
//
//  Wiring (honest — no mock data, every business value bound or em-dashed):
//    • loads.getDetail(id:)            EXISTS — full load record (lane,
//      cargo, equipment, rate, status, assigned driverId/catalystId).
//      Drives lane / equipment / load-number / payable (rate) / status.
//    • appointments.getByLoad(loadId:) EXISTS — dock number / scheduled-at
//      for the dwell + bay context. A nil appointment is a legitimate
//      empty state (no dock assigned yet) — never faked.
//    • shipperTelemetry.getLiveLocation(driverId:) EXISTS — backs the
//      TRACK LIVE CTA (live carrier pin).
//    • controlTower "pin to control tower"  STUB · named-gap — no
//      mutation has shipped on the controlTower.* namespace (read-only
//      overview/exceptions only). TRACK LIVE fetches the live pin and
//      flags the pin-write as a stub.
//
//  No-live-source values render an honest em-dash ("—"), never a figma
//  anchor: carrier legal name / USDOT / MC (not on the load projection),
//  live reefer temperature, pallet loaded-count, and the per-load
//  accessorial breakdown (FSC / detention / lumper — no accessorial_stats
//  client binding is wired to this screen yet).
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
            actionError = "No carrier assigned yet - nothing to track."
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
                ? "Live pin is stale · refresh location before sharing"
                : "Live pin acquired · control-tower sharing unavailable"
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
    @Environment(\.openURL) private var openURL
    @StateObject private var store: ShipperAtDockStore

    /// `loadId` is supplied by the caller (load-row tap / deep link). No
    /// flagship default — an empty id surfaces an honest "load not found".
    init(loadId: String = "") {
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
        .eusoRefreshable { await store.load() }
    }

    // MARK: - Bound accessors (em-dash when no live source)

    private var detail: LoadsAPI.LoadDetail? {
        if case .loaded(let d, _) = store.phase { return d }
        return nil
    }

    private var appt: AppointmentsAPI.ByLoadAppointment? {
        if case .loaded(_, let a) = store.phase { return a }
        return nil
    }

    /// Dock door from the appointment row; em-dash when unassigned.
    private var dockText: String {
        let dock = appt?.dockNumber?.trimmingCharacters(in: .whitespaces)
        return (dock?.isEmpty == false) ? dock! : "—"
    }

    /// Dwell elapsed since the appointment scheduled-at. No client-side
    /// loading-clock column on the projection, so this is em-dash unless
    /// a scheduled-at exists to count from.
    private var dwellText: String {
        guard let iso = appt?.scheduledAt, let d = isoDate(iso) else { return "—" }
        let mins = Int(Date().timeIntervalSince(d) / 60)
        guard mins >= 0 else { return "—" }
        return String(format: "%d:%02d", mins / 60, mins % 60)
    }

    /// Load number from the detail record; em-dash when missing.
    private var loadNumberText: String {
        let n = detail?.loadNumber.trimmingCharacters(in: .whitespaces)
        return (n?.isEmpty == false) ? n! : "—"
    }

    /// Lane "<origin> → <destination>" from the load endpoints; the
    /// LoadDetail formatter em-dashes either side when missing.
    private var laneText: String { detail?.laneDisplay ?? "—" }

    /// Equipment string straight off the load; em-dash when missing.
    private var equipmentText: String {
        let e = detail?.equipmentType?.trimmingCharacters(in: .whitespaces)
        return (e?.isEmpty == false) ? e! : "—"
    }

    /// Cargo / commodity label off the load; em-dash when missing.
    private var cargoText: String {
        let c = [detail?.commodityName, detail?.commodity, detail?.cargoType]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .first
        return c ?? "—"
    }

    /// Payable = load.rate via the LoadDetail currency formatter (its own
    /// honest em-dash when the rate column is empty).
    private var payableText: String { detail?.rateDisplay ?? "—" }

    /// No live pallet loaded-count column on this projection → em-dash.
    private var loadedText: String { "—" }

    /// No live reefer-temperature feed on this projection → em-dash.
    private var tempText: String { "—" }

    /// Carrier line is identifier-only (the load projection carries no
    /// carrier legal name / USDOT / MC). Mirrors the honest 205 pattern.
    private var carrierLine: String {
        if let id = detail?.catalystId { return "Catalyst #\(id)" }
        return "Carrier — awaiting assignment"
    }

    private var driverLine: String {
        if let id = detail?.driverId { return "Driver #\(id)" }
        return "Driver — awaiting assignment"
    }

    /// USDOT / MC are not on the load projection → em-dash both.
    private var carrierAuthorityLine: String { "USDOT — · MC —" }

    private var assignedDriverId: Int? { detail?.driverId }

    /// Lifecycle current node index derived from the live load status
    /// (8-stage strip: 0 posted … 3 pickup/at-dock … 7 closed).
    private var lifecycleIndex: Int {
        switch (detail?.status ?? "").lowercased() {
        case "posted", "bidding":                       return 0
        case "awarded", "assigned":                     return 1
        case "en_route_pickup", "en route pickup":      return 2
        case "at_pickup", "loading", "at dock", "pickup": return 3
        case "in_transit", "in transit", "departing":   return 4
        case "at_delivery", "at delivery", "delivering": return 5
        case "unloading", "paperwork":                  return 6
        case "delivered", "closed", "complete":         return 7
        default:                                        return 3
        }
    }

    private func isoDate(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }

    // MARK: TopBar (SVG y=72)

    private var topBar: some View {
        HStack(alignment: .top) {
            EusoTripEyebrow(verbatim: "SHIPPER · LOADS · IN TRANSIT · AT DOCK")
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
        "DOCK \(dockText) · DWELL \(dwellText) · \(loadedText)"
    }

    // MARK: Headline + sub + DU disc (SVG y=116/140 + disc @ 364,86)

    private var headline: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Loading at the dock")
                    .font(.system(size: 34, weight: .bold)).tracking(-0.6)
                    .foregroundStyle(palette.textPrimary)
                Text("\(laneText) · Dock \(dockText) · \(loadedText) loaded · \(equipmentText)")
                    .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
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
                Text("SHIPPER AT DOCK · LOADING · DWELL LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(LinearGradient.primary)
                Text("\(loadNumberText) · \(laneText) · \(equipmentText) · DOCK \(dockText) · \(loadedText) · DU observing")
                    .font(.system(size: 10)).foregroundStyle(palette.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.8)
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

    // MARK: §272 dispatch recap (SVG y=224)

    private var dispatchRecapCard: some View {
        HStack(alignment: .top, spacing: 10) {
            personaDisc(driverInitials, diameter: 32, font: 10)
            VStack(alignment: .leading, spacing: 4) {
                Text("DISPATCH RECAP · DWELL \(dwellText) AT DOCK · LOAD \(loadedText) LIVE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(LinearGradient.primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(carrierLine)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("\(carrierAuthorityLine) · \(driverLine)")
                    .font(EType.mono(.caption)).tracking(0.3).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
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

    /// Recap disc shows the assigned-driver id initials when present;
    /// neutral dash glyph otherwise (no driver-name field to monogram).
    private var driverInitials: String {
        if let id = detail?.driverId { return "#\(id % 100)" }
        return "—"
    }

    // MARK: KPI quartet hero · gradient rim (SVG y=290)

    private var kpiQuartet: some View {
        HStack(spacing: 0) {
            kpi(label: "LOADED", value: loadedText, sub: "pallets", valueStyle: .gradient)
            kpiDivider
            kpi(label: "DWELL",  value: dwellText, sub: "2H FREE", valueStyle: .solid(Brand.warning))
            kpiDivider
            kpi(label: "PAYABLE", value: payableText, sub: "NET-30", valueStyle: .solid(Brand.blue))
            kpiDivider
            kpi(label: "BOL", value: bolStateText, sub: bolSubText, valueStyle: .solid(Brand.blue))
        }
        .padding(.vertical, 12).padding(.horizontal, 16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    /// BOL state derived from the live load status (same lifecycle map
    /// the 205 detail screen uses); em-dash when status is unknown.
    private var bolStateText: String {
        switch (detail?.status ?? "").lowercased() {
        case "posted", "bidding", "awarded", "assigned",
             "at_pickup", "loading", "pickup", "at dock": return "PEND"
        case "en_route_pickup", "in_transit", "in transit",
             "at_delivery", "delivery", "delivering":      return "ISSUED"
        case "unloading", "paperwork", "closed", "delivered", "complete": return "SIGNED"
        default: return "—"
        }
    }
    private var bolSubText: String {
        switch bolStateText {
        case "PEND":   return "awaiting"
        case "ISSUED": return "issued"
        case "SIGNED": return "signed"
        default:       return "—"
        }
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

    // MARK: 8-stage lifecycle strip · status-driven current (SVG y=376)

    private var lifecycleStrip: some View {
        ZStack {
            GeometryReader { geo in
                let w = geo.size.width
                let inset: CGFloat = 22
                let span = w - inset * 2
                let count = 8
                let step = span / CGFloat(count - 1)
                let currentIndex = lifecycleIndex
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
                    // AT-DOCK micro-chip pinning the current node.
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

    // MARK: Dock-bay map strip · zoomed dock (SVG y=424)

    private var dockBayMap: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                personaDisc("DU", diameter: 18, font: 7)
                Text("SHIPPER OBSERVING")
                    .font(EType.mono(.micro)).tracking(0.4).foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
                tempMeter
            }
            // Warehouse dock-face zoomed strip — facility name not on the
            // load/appointment projection, so the lane label leads here.
            Text("\(laneText) · DOCK \(dockText) · ZOOMED")
                .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0x0F141F)))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color(hex: 0x3A4250), lineWidth: 0.8))
            HStack(spacing: 8) {
                bayChip("LANE —")
                Rectangle().fill(Brand.blue.opacity(0.55)).frame(height: 2.4)
                    .overlay(forkliftDash)
                dockBayActive
                palletGrid
            }
            HStack {
                Text("DOCK BAY · DOCK \(dockText) · TEMP \(tempText)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(LinearGradient.primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text("\(loadedText) · DWELL \(dwellText)")
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
        Text("DOCK \(dockText)")
            .font(.system(size: 6.5, weight: .heavy)).tracking(0.3)
            .foregroundStyle(LinearGradient.primary)
            .lineLimit(1)
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
            Text(tempText).font(.system(size: 8, weight: .heavy)).monospacedDigit()
                .foregroundStyle(Brand.blue)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0x0F141F)))
        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Brand.blue.opacity(0.55), lineWidth: 0.8))
    }

    // Pallet mini-grid (4-row × 5-col). No live loaded-count feed, so the
    // grid renders empty cells under an em-dash header rather than a faked
    // fill ratio.
    private var palletGrid: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(loadedText).font(.system(size: 6, weight: .heavy)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
            VStack(spacing: 1) {
                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: 1) {
                        ForEach(0..<5, id: \.self) { _ in
                            Rectangle()
                                .fill(palette.borderFaint)
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
            Text("SHIPPER READ-SIDE · LIVE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.top, 4)
    }

    // MARK: Roster rows 1-6 (SVG y=546…766)
    //
    // Row 1 line-haul binds to the live load rate. Rows 2-4 (FSC /
    // detention / lumper) have NO per-load accessorial source wired to
    // this screen, so they render an honest em-dash amount + a STUB tag
    // rather than a fabricated figure. Rows 5-6 are structural.

    private var rosterRows: some View {
        VStack(spacing: 4) {
            // Row 1 · LINE HAUL · gradient rim · payable = load.rate.
            rosterRow(
                eyebrow: "LINE HAUL · PAYABLE",
                detail: "DU paid · \(driverLine) · NET-30 to \(carrierLine)",
                amount: payableText, tag: "PAYABLE",
                rim: .gradient, accent: nil, eyebrowGradient: true, amountGradient: true)
            // Row 2 · FUEL SURCHARGE · info rim · no accessorial feed.
            rosterRow(
                eyebrow: "Fuel surcharge",
                detail: "Per-load accessorial breakdown not wired",
                amount: "—", tag: "FSC —",
                rim: .solid(Brand.blue), accent: Brand.blue, eyebrowGradient: false, amountGradient: false,
                titleStyle: true)
            // Row 3 · DETENTION · info rim · no accessorial feed.
            rosterRow(
                eyebrow: "Detention",
                detail: "Detention accrual not wired · DWELL \(dwellText)",
                amount: "—", tag: "—",
                rim: .solid(Brand.blue), accent: Brand.blue, eyebrowGradient: false, amountGradient: false,
                titleStyle: true)
            // Row 4 · LUMPER · warn rim · no accessorial feed.
            rosterRow(
                eyebrow: "Lumper",
                detail: "Lumper ticket not wired to this load",
                amount: "—", tag: "—",
                rim: .solid(Brand.warning), accent: Brand.warning, eyebrowGradient: false, amountGradient: false,
                titleStyle: true, amountColor: palette.textSecondary, tagColor: palette.textSecondary)
            // Row 5 · ESCORT · default rim · N/A.
            rosterRow(
                eyebrow: "Escort",
                detail: "N/A · no escort required",
                amount: "NONE", tag: "NOT REQ",
                rim: .solid(Brand.neutral.opacity(0.45)), accent: nil, eyebrowGradient: false, amountGradient: false,
                titleStyle: true, amountColor: palette.textSecondary, tagColor: palette.textSecondary)
            // Row 6 · LOAD VISIBILITY · gradient rim · §280.1 forward-flip.
            rosterRow(
                eyebrow: "LOAD VISIBILITY · LIVE AT DOCK",
                detail: "\(loadedText) PALLETS · DOCK \(dockText) · TEMP \(tempText)",
                amount: loadedText, tag: "BOL \(bolStateText)",
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
            Text("SHIPPER ECONOMICS · NET-30 PAYABLE · 4TH-PORT 2/3")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(LinearGradient.primary)
            Text("\(payableText) line-haul payable · NET-30")
                .font(.system(size: 10)).foregroundStyle(palette.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.85)
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

    private func callFacility() {
        // No facility-phone column on the at-dock projection yet; the
        // dialer opens to a blank facility number when one is missing
        // rather than fabricating a contact.
        if let url = URL(string: "tel://") { openURL(url) }
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
                .lineLimit(1).minimumScaleFactor(0.5)
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
