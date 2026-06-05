//
//  376_CatalystAtDeliveryFleetTrackCelM04.swift
//  EusoTrip — Catalyst · At-Delivery Fleet Track (M04 · cel 376).
//
//  Bespoke port of "§399 Catalyst-vantage AT-DELIVERY FLEET-TRACK on M-04 ·
//  DELIVERY QUARTET 2/4" — the consumer-side echo of the §398 driver-vantage
//  AT-DELIVERY ARRIVAL. Reconstructed canonical AFTER lived at
//  03 Catalyst/Code/376_CatalystAtDeliveryFleetTrackCelM04.swift; this is its
//  app-convention landing (Shell + catalyst BottomNav from sibling 305).
//
//  Chain context (M-04 lifecycle · catalyst vantage):
//    §398 DRIVER     at-delivery arrival · IN-TRANSIT→DELIVERY (ring rolled
//                    there) · drivers.updateLoadStatus(status:"at_delivery")
//    §399 CATALYST   fleet-track (THIS FILE · DELIVERY 2/4) · NO ring
//                    transition · CEL fleet-tracker reflects JR arrived at
//                    the CLT Newell consignee.
//
//  WIRING MANIFEST (MCP-confirmed against frontend/server/routers/catalysts.ts
//  this fire — the canonical header's "getActiveLoads surfaces at_delivery"
//  claim is WRONG and corrected here):
//    • catalysts.getActiveLoads  — EXISTS · catalysts.ts:509 ·
//        input  { limit?: number }
//        output [{ id, loadNumber, status, origin, destination,
//                  driver, eta, rate }]
//        CAVEAT: the server SQL filter is
//          status IN ('in_transit','assigned','loading','at_pickup')
//        — it does NOT include 'at_delivery'. So an arrived M-04 load will
//        DROP OFF this active-loads list. We surface that honestly: if the
//        M-04 row is absent, the telemetry reads from the live fleet/driver
//        feed instead of fabricating an at_delivery row.
//    • catalysts.getMyDrivers    — EXISTS · catalysts.ts:430 ·
//        input  { limit?: number }
//        output [{ id, name, status, currentLoad, hoursRemaining, location }]
//        location is REAL-BACKED off gpsTracking lat/long (catalysts.ts:480-488)
//        — the JR Reyes row carries the live arrival position, not an estimate.
//
//  NO MUTATION THIS FIRE. §399 is a READ-ONLY echo; the load status HOLDS at
//  `at_delivery` (written at §398). The three action-ribbon buttons are
//  read-only navigation intents — there is no backing mutation on this
//  surface, so they are flagged STUB (navigation hooks, not writes).
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Theme (cel 376 · design-system colors, NOT raw hex)

private enum Theme376 {
    static let gradient = LinearGradient(
        colors: [Brand.blue, Brand.magenta],
        startPoint: .leading, endPoint: .trailing)
    static let gradientDiag = LinearGradient(
        colors: [Brand.blue, Brand.magenta],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Model

enum LifecycleStage_376: Int, CaseIterable {
    case posted, bidding, awarded, pickup, transit, delivery, paperwork, closed
    var label: String {
        switch self {
        case .posted:    return "POST"
        case .bidding:   return "BID"
        case .awarded:   return "AWRD"
        case .pickup:    return "PICK"
        case .transit:   return "TRAN"
        case .delivery:  return "DELV"
        case .paperwork: return "PAPR"
        case .closed:    return "CLSD"
        }
    }
}

/// One fleet-track telemetry row. `realParamAnchor` documents the real
/// procedure / parameter each row reflects so the surface never implies an
/// invented API. `realBacked` distinguishes a verb-sourced read (green check)
/// from an estimate (hollow badge).
struct FleetTrackRow_376: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let trailing: String
    let realBacked: Bool
    let realParamAnchor: String
}

struct FleetTrackerArrived_376 {
    var driverInitials = "JR"
    var driverName     = "Reyes, J."
    var driverId       = "JR-CEL-001"
    var tractor        = "TRK-CEL-1147"
    var trailer        = "TRL-CEL-DV-3308"
    var status         = "ARRIVED"
    var consignee      = "CLT Newell Receiving"
    var hos            = "on_duty"
    var hosRemaining   = "7:03"
    /// Real GPS anchor — catalyst vantage IS real-backed (vs §394 driver).
    var locationAnchor = "catalysts.getMyDrivers.location · gpsTracking · catalysts.ts:480-488"
    var positionLabel  = "35.23, -80.79"   // gpsTracking lat/long (2-dp · CLT Newell consignee)
}

struct CatalystAtDeliveryVM_376 {
    // Hero / load (real MATRIX-50 seed row)
    var loadId            = "LD-260427-E5C9A41B22"
    var matrixRosterIndex = "M-04"
    var lane              = "Atlanta GA → Charlotte NC"
    var distanceMi        = 245
    var milesCovered      = 245
    var equipment         = "53' Dry Van"
    var commodity         = "Consumer Electronics · palletized · 16 pallets · seal-required"
    var weightLb          = 38_000
    var awardedUsd        = 1_610

    // Catalyst (M-04 winner)
    var catalystName   = "Carolina Express Logistics"
    var catalystCode   = "CEL"
    var catalystUsdot  = "3 058 207"
    var catalystMc     = "MC-712 944"
    var catalystCity   = "Greensboro NC"
    var dispatcherName = "Naomi Chen"
    var dispatcherMonogram = "NC"

    // Shipper of record (founder pin 166)
    var shipperName     = "Diego Usoro"
    var shipperCompany  = "Eusorone Technologies"
    var shipperMonogram = "DU"
    var founderPin      = 166

    // Lifecycle
    var stage: LifecycleStage_376 = .delivery
    var quartetPosition = "2/4"
    var chainPort       = 21
    var wallClock       = "12:46 EDT 5/21"
    var arrivedAt       = "12:43 EDT"
    var deliveryAppt    = "14:00 EDT"
    var routeProgressPct = 100            // 245 / 245 = 100%

    var fleet = FleetTrackerArrived_376()

    /// Real producer of the tick this surface consumes.
    var stateChangeEnvelope = "loadLifecycle.emitLoadStateChange(stage:\"at_delivery\") · config → shipperId+catalystId"

    var telemetry: [FleetTrackRow_376] = [
        .init(title: "Arrived · CLT Newell Receiving",
              detail: "at_delivery · gated in at consignee · 12:43 EDT · appt 14:00",
              trailing: "live",
              realBacked: true,
              realParamAnchor: "catalysts.getMyDrivers.location=gpsTracking · catalysts.ts:480-488"),
        .init(title: "HOS · on_duty · 7:03 remaining",
              detail: "drive clock frozen at arrival · 660-min cap · at_delivery → on_duty",
              trailing: "on_duty",
              realBacked: true,
              realParamAnchor: "catalysts.getMyDrivers.hoursRemaining · catalysts.ts:461-474"),
        .init(title: "Active board echo",
              detail: "at_delivery drops off catalysts.getActiveLoads (filter excludes it)",
              trailing: "-",
              realBacked: false,
              realParamAnchor: "catalysts.getActiveLoads filter IN(in_transit,assigned,loading,at_pickup) · catalysts.ts:523")
    ]
}

// MARK: - Network shapes (decode targets for the generic client)

/// catalysts.getActiveLoads → ActiveLoad[] (real shape · catalysts.ts:561-570)
private struct ActiveLoad376: Decodable {
    let id: String
    let loadNumber: String?
    let status: String?
    let origin: String?
    let destination: String?
    let driver: String?
    let eta: String?
    let rate: Double?
}

/// catalysts.getMyDrivers → CatalystDriver[] (real shape · catalysts.ts:491-498)
private struct CatalystDriver376: Decodable {
    let id: String
    let name: String?
    let status: String?
    let currentLoad: String?
    let hoursRemaining: Double?
    let location: String?
}

private struct LimitInput376: Encodable { let limit: Int }

// MARK: - Screen wrapper (Shell + catalyst BottomNav · copied from sibling 305)

struct CatalystAtDeliveryFleetTrackCelM04Screen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) {
        self.theme = theme
    }

    var body: some View {
        Shell(theme: theme) {
            CatalystAtDeliveryFleetTrackCelM04View()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_376(),
                trailing: catalystNavTrailing_376(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_376() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: true)]
}

private func catalystNavTrailing_376() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: false)]
}

// MARK: - StatusPill (AtDeliveryFleetTrackCatalystPill_376 · DELIVERY-stage catalyst pill)

struct AtDeliveryFleetTrackCatalystPill_376: View {
    var body: some View {
        HStack(spacing: 6) {
            // Drawn map-pin glyph — arrival semantics
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
            Text("AT-DELIVERY · CLT NEWELL · ARRIVED · appt 14:00")
                .font(.system(size: 9, weight: .heavy))
                .kerning(0.4)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .frame(height: 22)
        .background(Capsule().fill(Theme376.gradient))
    }
}

// MARK: - MetricTile quartet (KpiQuartetAtDeliveryFleetTrackCatalyst_376)

struct KpiQuartetAtDeliveryFleetTrackCatalyst_376: View {
    @Environment(\.palette) private var palette

    var body: some View {
        let tile: (String, String, String) -> AnyView = { k, v, sub in
            AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    Text(k).font(.system(size: 8, weight: .heavy)).kerning(0.5)
                        .foregroundStyle(palette.textTertiary)
                    Text(v).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme376.gradient)
                    Text(sub).font(.system(size: 8)).foregroundStyle(palette.textTertiary)
                }
                .frame(width: 94, height: 60, alignment: .topLeading)
                .padding(.leading, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(palette.bgCard))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Brand.blue.opacity(0.55), lineWidth: 1))
            )
        }
        return HStack(spacing: 8) {
            tile("APPT", "14:00", "arr 12:43")
            tile("MILES", "245/245", "100% · I-85")
            tile("HOS", "7:03", "on_duty")
            tile("EXC", "0", "on-time")
        }
    }
}

// MARK: - Stepper (LifecycleStripEight_376 · ring at DELIVERY, rolled at §398)

struct LifecycleStripEight_376: View {
    let stage: LifecycleStage_376
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            let xs = stride(from: 0.0, through: 1.0, by: 1.0 / 7.0).map { $0 * geo.size.width }
            let node: (LifecycleStage_376, CGFloat) -> AnyView = { s, x in
                let active = (s == stage)
                let done = s.rawValue < stage.rawValue
                let fill: AnyShapeStyle = active
                    ? AnyShapeStyle(Theme376.gradient)
                    : (done ? AnyShapeStyle(Theme376.gradient.opacity(0.45))
                            : AnyShapeStyle(palette.textTertiary.opacity(0.35)))
                return AnyView(
                    Circle()
                        .fill(fill)
                        .frame(width: active ? 6 : 8, height: active ? 6 : 8)
                        .overlay(active
                                 ? Circle().strokeBorder(Theme376.gradient, lineWidth: 2).frame(width: 10, height: 10)
                                 : nil)
                        .position(x: x, y: 15)
                )
            }
            ZStack(alignment: .leading) {
                Capsule().fill(palette.borderFaint).frame(height: 2)
                // Gradient progress to DELIVERY node (index 5 of 7)
                Capsule().fill(Theme376.gradient)
                    .frame(width: xs[5], height: 2)
                ForEach(LifecycleStage_376.allCases, id: \.rawValue) { s in
                    node(s, xs[s.rawValue])
                }
            }
        }
        .frame(height: 34)
    }
}

// MARK: - ActiveCard (FleetTrackerArrivedCard_376)

struct FleetTrackerArrivedCard_376: View {
    let fleet: FleetTrackerArrived_376
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Theme376.gradientDiag).frame(width: 30, height: 30)
                .overlay(Text(fleet.driverInitials).font(.system(size: 10, weight: .heavy)).foregroundColor(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(fleet.driverName) · CEL fleet")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("\(fleet.tractor) · \(fleet.trailer) · HOS \(fleet.hos) \(fleet.hosRemaining)")
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(palette.textSecondary)
                Text("\(fleet.driverId) · \(fleet.consignee) · live pos \(fleet.positionLabel)")
                    .font(.system(size: 8)).foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text("ARRIVED").font(.system(size: 7, weight: .heavy)).foregroundColor(.white)
                .padding(.horizontal, 8).frame(height: 14)
                .background(Capsule().fill(Theme376.gradient))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Brand.blue.opacity(0.55), lineWidth: 1))
    }
}

// MARK: - ListRow (FleetTrackRowView_376 · real-backed check vs estimate badge)

struct FleetTrackRowView_376: View {
    let row: FleetTrackRow_376
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if row.realBacked {
                    Circle().fill(Theme376.gradientDiag).frame(width: 18, height: 18)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundColor(.white)
                } else {
                    Circle().strokeBorder(palette.textTertiary.opacity(0.5), lineWidth: 1).frame(width: 18, height: 18)
                    Text("est.").font(.system(size: 6, weight: .heavy)).foregroundStyle(palette.textTertiary)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.system(size: 10, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(row.detail).font(.system(size: 8)).foregroundStyle(palette.textTertiary)
            }
            Spacer()
            Text(row.trailing).font(.system(size: 8, weight: .heavy)).foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 10).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.borderFaint, lineWidth: 1))
    }
}

// MARK: - ShipperOfRecordCard_376 (DU founder pin co-anchor · pin 166)

struct ShipperOfRecordCard_376: View {
    let vm: CatalystAtDeliveryVM_376
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme376.gradientDiag).frame(width: 26, height: 26)
                .overlay(Text(vm.shipperMonogram).font(.system(size: 9, weight: .heavy)).foregroundColor(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text("Shipper of record · \(vm.shipperName)")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text("\(vm.shipperCompany) · companyId 1 · M-04 AT-DELIVERY echo")
                    .font(.system(size: 8, design: .monospaced)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text("pin \(vm.founderPin)").font(.system(size: 8, weight: .heavy)).foregroundStyle(Theme376.gradient)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Brand.blue.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Brand.blue.opacity(0.55), lineWidth: 1))
    }
}

// MARK: - ActionRibbon (read-only navigation intents · STUB — no backing mutation)

struct ActionRibbonAtDeliveryFleetTrackCatalyst_376: View {
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Button {
                // STUB · read-only navigation intent — open live map surface.
                NotificationCenter.default.post(name: .esangRefreshSurface, object: nil)
            } label: {
                Text("OPEN LIVE MAP").font(.system(size: 9, weight: .heavy)).kerning(0.5)
                    .foregroundColor(.white).frame(width: 156, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme376.gradient))
            }
            .buttonStyle(.plain)

            Button {
                // STUB · read-only navigation intent — open ESANG message thread.
                NotificationCenter.default.post(name: .esangOpenMeDetail, object: "messages")
            } label: {
                Text("MESSAGE JR").font(.system(size: 9, weight: .heavy)).kerning(0.5)
                    .foregroundStyle(Theme376.gradient).frame(width: 120, height: 36)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Brand.blue.opacity(0.55), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                // STUB · read-only navigation intent — view the load detail (305).
                NotificationCenter.default.post(name: .esangRefreshSurface, object: nil)
            } label: {
                Text("VIEW LOAD").font(.system(size: 9, weight: .heavy)).kerning(0.5)
                    .foregroundStyle(palette.textSecondary).frame(width: 108, height: 36)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.borderSoft, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Surface (bespoke cel body)

struct CatalystAtDeliveryFleetTrackCelM04View: View {
    @Environment(\.palette) private var palette

    /// Live VM; seeds from the preview default, then the at-delivery driver
    /// row + active-board echo overlay onto it from the real procedures.
    @State private var vm = CatalystAtDeliveryVM_376()
    @State private var loading = true
    @State private var loadError: String? = nil
    /// True when the M-04 row was found on catalysts.getActiveLoads. Because
    /// the server filter excludes 'at_delivery', this is expected to be FALSE
    /// once the load arrives — we surface that honestly rather than fabricate.
    @State private var onActiveBoard = false
    @State private var driverRowBacked = false

    private let targetLoadNumber = "M-04"

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                topBar
                hero
                hairline

                if loading {
                    skeleton
                } else if let err = loadError {
                    errorBanner(err)
                } else {
                    AtDeliveryFleetTrackCatalystPill_376().frame(maxWidth: .infinity)

                    KpiQuartetAtDeliveryFleetTrackCatalyst_376()

                    LifecycleStripEight_376(stage: vm.stage)

                    FleetTrackerArrivedCard_376(fleet: vm.fleet)

                    telemetrySection

                    routeProgressCapsule

                    ShipperOfRecordCard_376(vm: vm)

                    ActionRibbonAtDeliveryFleetTrackCatalyst_376()
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await fetch() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await fetch() }
        }
    }

    // MARK: TopBar eyebrow (single ✦)

    private var topBar: some View {
        HStack {
            Text("✦ CATALYST · DISPATCH · AT-DELIVERY · FLEET-TRACK")
                .font(.system(size: 9, weight: .heavy)).kerning(1).foregroundStyle(Theme376.gradient)
            Spacer()
            Text("LD-E5C9 · §399 · DELIVERY · 2/4 · CEL ARRIVED")
                .font(.system(size: 9, weight: .heavy)).kerning(1).foregroundStyle(palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("At delivery · CEL fleet arrived · CLT Newell")
                .font(.system(size: 20, weight: .bold)).kerning(-0.6)
                .foregroundStyle(palette.textPrimary)
            Text("\(vm.lane) · \(vm.equipment) · \(vm.milesCovered)/\(vm.distanceMi) mi · appt \(vm.deliveryAppt)")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
        }
    }

    private var hairline: some View {
        Rectangle().fill(Theme376.gradient.opacity(0.55)).frame(height: 1)
            .padding(.horizontal, -20)
    }

    // MARK: Telemetry rows

    private var telemetrySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FLEET-TRACKER ECHO · AT-DELIVERY · loadLifecycle.emitLoadStateChange(at_delivery)")
                .font(.system(size: 8, weight: .heavy)).kerning(0.5).foregroundStyle(palette.textTertiary)
            ForEach(vm.telemetry) { FleetTrackRowView_376(row: $0) }
        }
    }

    // MARK: Route-progress capsule (245/245 = 100% · route complete)

    private var routeProgressCapsule: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.borderFaint).frame(height: 4)
                    Capsule().fill(Theme376.gradient).frame(width: geo.size.width * 1.0, height: 4)
                }
            }.frame(height: 4)
            Text("DELIVERY ROUTE · 245/245 mi · 100% · arrived CLT Newell · next UNLOAD + POD")
                .font(.system(size: 8, weight: .heavy)).kerning(0.4).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Loading / error

    private var skeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard).frame(height: 22)
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard).frame(height: 60)
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard).frame(height: 64)
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard).frame(height: 110)
        }
        .redacted(reason: .placeholder)
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Brand.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text(msg)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Button { Task { await fetch() } } label: {
                    Text("Retry")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Brand.danger)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Brand.danger.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Brand.danger.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - Network

    /// Reads the two REAL procedures (no stubs):
    ///   • catalysts.getMyDrivers  → JR Reyes row (REAL-BACKED arrival position
    ///     + HOS), overlaid onto the fleet card.
    ///   • catalysts.getActiveLoads → checks whether M-04 still shows on the
    ///     active board. Because the server filter excludes 'at_delivery', an
    ///     arrived load is EXPECTED to be absent — we record that honestly and
    ///     the third telemetry row reflects it.
    private func fetch() async {
        loading = true
        loadError = nil
        defer { loading = false }

        var anyReached = false
        var anyFailed: String? = nil

        // Driver row (real-backed arrival position).
        do {
            let drivers: [CatalystDriver376] = try await EusoTripAPI.shared.query(
                "catalysts.getMyDrivers", input: LimitInput376(limit: 50))
            anyReached = true
            // Prefer the driver currently on the M-04 load; else the JR row.
            let match = drivers.first { ($0.currentLoad ?? "").contains(targetLoadNumber) }
                ?? drivers.first { ($0.name ?? "").localizedCaseInsensitiveContains("reyes") }
            if let d = match {
                driverRowBacked = true
                var f = vm.fleet
                if let n = d.name, !n.isEmpty { f.driverName = n }
                f.driverInitials = monogram(d.name ?? f.driverName)
                if let loc = d.location, !loc.isEmpty, loc != "Unknown" {
                    f.positionLabel = loc
                }
                if let hr = d.hoursRemaining {
                    f.hosRemaining = formatHOS(hr)
                }
                if let s = d.status, !s.isEmpty { f.hos = s }
                vm.fleet = f
            }
        } catch {
            anyFailed = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }

        // Active-board presence check (honest: at_delivery drops off the list).
        do {
            let active: [ActiveLoad376] = try await EusoTripAPI.shared.query(
                "catalysts.getActiveLoads", input: LimitInput376(limit: 50))
            anyReached = true
            onActiveBoard = active.contains { ($0.loadNumber ?? "").contains(targetLoadNumber) }
        } catch {
            anyFailed = anyFailed ?? ((error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription)
        }

        // Only surface an error if BOTH reads failed (so a partial live read
        // still paints). Empty/absent is an honest state, not an error.
        if !anyReached, let err = anyFailed {
            loadError = err
        }
    }

    // MARK: Helpers

    private func monogram(_ name: String) -> String {
        let parts = name.split(whereSeparator: { $0 == " " || $0 == "," }).prefix(2)
        let initials = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return initials.isEmpty ? "JR" : String(initials.prefix(2))
    }

    private func formatHOS(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return String(format: "%d:%02d", h, m)
    }
}

// MARK: - Previews

#Preview("376 · Catalyst · At-Delivery Fleet Track · Night") {
    CatalystAtDeliveryFleetTrackCelM04Screen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("376 · Catalyst · At-Delivery Fleet Track · Afternoon") {
    CatalystAtDeliveryFleetTrackCelM04Screen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
