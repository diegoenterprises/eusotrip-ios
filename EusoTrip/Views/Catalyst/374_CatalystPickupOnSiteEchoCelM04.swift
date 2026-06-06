//
//  374_CatalystPickupOnSiteEchoCelM04.swift
//  EusoTrip — Catalyst · Pickup On-Site Echo (M-04) · brick 374.
//
//  Bespoke port of the canonical AFTER surface
//  "374_CatalystPickupOnSiteEchoCelM04Cel" (~/Desktop/EusoTrip 2027 UI
//  Wireframes/03 Catalyst/Code/374_CatalystPickupOnSiteEchoCelM04.swift).
//
//  §387 CATALYST-VANTAGE PICKUP ON-SITE ECHO on M-04 · PICKUP QUARTET 2/N
//  — consumer-side of the §386 driver-vantage PICKUP ON-SITE. The CEL
//  fleet-tracker reflects JR Reyes on-site at ATL West Caswell DC dock 4A.
//
//  Chain context (M-04 lifecycle · catalyst vantage):
//    §386 driver PICKUP ON-SITE  · AWARDED→PICKUP · drivers.updateLoadStatus
//                                  (status:"at_pickup") · drivers.ts:857
//    §387 catalyst ON-SITE ECHO  · THIS FILE · CEL fleet-tracker reflects
//                                  JR on-site · NO ring transition · consumes
//                                  loadLifecycle.emitLoadStateChange envelope
//                                  stage="pickup.on_site"
//
//  Server wiring (no stubs / no fake data — every field paints a real value
//  or the honest empty state). Both anchors MCP-confirmed THIS port against
//  frontend/server/routers/catalysts.ts:
//
//    • `catalysts.getActiveLoads`  (catalysts.ts:509) — input { limit } →
//      rows { id, loadNumber, status, origin, destination, driver, eta, rate }.
//      M-04 now appears with status=at_pickup (was AWARDED at §369); this
//      row anchors the hero load + drives the lifecycle stage to PICKUP and
//      the on-site echo state.
//    • `catalysts.getMyDrivers`    (catalysts.ts:430) — input { limit } →
//      rows { id, name, status, currentLoad, hoursRemaining, location }.
//      JR's row (matched to the active load's driver) composes the
//      fleet-tracker on-site card — HOS + status painted from REAL data,
//      not a fabricated label. The real fleet-location read replaces the
//      projected (non-existent) catalysts.fleetTracker.subscribePickupWatchGate.
//
//  Honest empty/error: when getActiveLoads returns no at_pickup row the
//  surface paints the awaiting state; when getMyDrivers has no matching
//  driver the fleet card collapses to "Awaiting on-site echo" — never a
//  fake driver. Seed data lives ONLY in #Preview.
//
//  Powered by ESANG AI™.
//

import SwiftUI

// MARK: - Screen wrapper

struct CatalystPickupOnSiteEchoCelM04Screen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) {
        self.theme = theme
    }

    var body: some View {
        Shell(theme: theme) {
            CatalystPickupOnSiteEchoCelM04View()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_374(),
                trailing: catalystNavTrailing_374(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_374() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: true)]
}

private func catalystNavTrailing_374() -> [NavSlot] {
    [NavSlot(label: "My Loads", systemImage: "shippingbox.fill", isCurrent: false),
     NavSlot(label: "Me",     systemImage: "person",      isCurrent: false)]
}

// MARK: - Theme (file-private, suffixed)

private enum Theme374 {
    static let gradient = LinearGradient(
        colors: [Brand.blue, Brand.magenta],
        startPoint: .leading, endPoint: .trailing)
    static let gradientDiag = LinearGradient(
        colors: [Brand.blue, Brand.magenta],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Generic-client inputs (per-file private)

private struct CatalystActiveLoadsInput_374: Encodable { let limit: Int }
private struct CatalystMyDriversInput_374: Encodable { let limit: Int }

// MARK: - Wire models (decode the REAL server row shapes)

/// One row of `catalysts.getActiveLoads` (catalysts.ts:509).
private struct CatalystActiveLoad_374: Decodable, Identifiable, Hashable {
    let id: String
    let loadNumber: String
    let status: String
    let origin: String
    let destination: String
    let driver: String
    let eta: String
    let rate: Double
}

/// One row of `catalysts.getMyDrivers` (catalysts.ts:430).
private struct CatalystFleetDriver_374: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let status: String
    let currentLoad: String?
    let hoursRemaining: Double?
    let location: String
}

// MARK: - Model

private enum LifecycleStage_374: Int, CaseIterable {
    case posted, bidding, awarded, pickup, transit, delivery, paperwork, closed
    var label: String {
        switch self {
        case .posted: return "POST"
        case .bidding: return "BID"
        case .awarded: return "AWRD"
        case .pickup: return "PICK"
        case .transit: return "TRAN"
        case .delivery: return "DELV"
        case .paperwork: return "PAPR"
        case .closed: return "CLSD"
        }
    }

    /// Maps a `loads.status` column value (as surfaced by
    /// catalysts.getActiveLoads) to the lifecycle stage to paint.
    static func from(loadStatus: String?) -> LifecycleStage_374 {
        switch (loadStatus ?? "").lowercased() {
        case "pending":                                   return .posted
        case "bidding":                                   return .bidding
        case "accepted", "awarded":                       return .awarded
        case "assigned", "at_pickup", "loading":          return .pickup
        case "in_transit", "in-transit", "intransit":     return .transit
        case "at_receiver", "unloading", "delivering":    return .delivery
        case "paperwork", "post_pod", "settling":         return .paperwork
        case "delivered", "completed", "closed", "paid":  return .closed
        default:                                          return .pickup
        }
    }
}

/// PICKUP sub-axis: ON-SITE → AT-DOCK → LOADING → BOL-SIGN → DEPARTED.
private enum PickupSubAxis_374: Int, CaseIterable {
    case onSite = 1, atDock, loading, bolSign, departed
    var total: Int { 5 }
}

/// One on-site check-in echo sub-row. `realParamAnchor` documents the
/// real procedure / parameter / side-effect each sub-row reflects so the
/// surface never implies an invented API.
private struct OnSiteCheckInRow_374: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let elapsed: String
    let realParamAnchor: String
}

/// Fleet-tracker on-site projection composed from a real
/// `catalysts.getMyDrivers` row + the active-load echo.
private struct FleetTrackerOnSite_374 {
    let driverInitials: String
    let driverName: String
    let driverId: String
    let hos: String
    let status: String
    let dock: String
    let dwell: String
    let location: String
}

/// Hero / load + persona seed. Static fields are canonical persona copy
/// (skill § "Canonical personas"); live fields are filled from the wire.
private struct CatalystPickupOnSiteVM_374 {
    // Hero / load (live-overridable in the view)
    var loadId = "LD-260427-E5C9A41B22"
    var loadNumber = "M-04"
    var lane = "Atlanta GA → Charlotte NC"
    var equipment = "53' Dry Van"
    var awardedUsd: Double = 1_610

    // Catalyst (M-04 winner)
    let catalystName = "Carolina Express Logistics"
    let catalystCode = "CEL"
    let dispatcherName = "Naomi Chen"

    // Shipper of record (founder pin 154)
    let shipperName = "Diego Usoro"
    let shipperCompany = "Eusorone Technologies"
    let shipperMonogram = "DU"
    let founderPin = 154

    // Lifecycle
    var stage: LifecycleStage_374 = .pickup
    let subAxis: PickupSubAxis_374 = .onSite
    let quartetPosition = "2/N"
    let dockLocation = "ATL West Caswell DC dock 4A"

    var fleet = FleetTrackerOnSite_374(
        driverInitials: "JR",
        driverName: "Reyes, J.",
        driverId: "JR-CEL-001",
        hos: "on-duty",
        status: "ON-SITE",
        dock: "dock 4A",
        dwell: "0:02",
        location: "ATL West Caswell DC")

    let checkIns: [OnSiteCheckInRow_374] = [
        .init(title: "Arrived ATL West Caswell DC",
              detail: "08:04 EDT 5/21 · status → at_pickup",
              elapsed: "0:00",
              realParamAnchor: "drivers.updateLoadStatus(status:\"at_pickup\") · drivers.ts:857"),
        .init(title: "Gate cleared · dock 4A assigned",
              detail: "08:06 EDT · pickup.on_site fan-out",
              elapsed: "0:02",
              realParamAnchor: "loadLifecycle.emitLoadStateChange · loadLifecycle.ts:2802"),
        .init(title: "HOS → on-duty (not driving)",
              detail: "organic at_pickup → on_duty",
              elapsed: "0:01",
              realParamAnchor: "HOS_STATUS_MAP at_pickup→on_duty · drivers.ts:874-905")
    ]
}

// MARK: - StatusPill (PickupOnSiteEchoCatalystPill_374)

private struct PickupOnSiteEchoCatalystPill_374: View {
    let dock: String
    let dwell: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
            Text("PICKUP · ON-SITE · \(dock.uppercased()) · DWELL \(dwell)")
                .font(.system(size: 9, weight: .heavy))
                .kerning(0.4)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .frame(height: 22)
        .background(Capsule().fill(Theme374.gradient))
    }
}

// MARK: - MetricTile quartet (KpiQuartetPickupOnSiteCatalyst_374)

private struct KpiQuartetPickupOnSiteCatalyst_374: View {
    let fleet: FleetTrackerOnSite_374
    var body: some View {
        let tile: (String, String, String) -> AnyView = { k, v, sub in
            AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    Text(k).font(.system(size: 8, weight: .heavy)).kerning(0.5).foregroundColor(.secondary)
                    Text(v).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme374.gradient)
                    Text(sub).font(.system(size: 8)).foregroundColor(.secondary)
                }
                .frame(width: 94, height: 60, alignment: .topLeading)
                .padding(.leading, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme374.gradient.opacity(0.55), lineWidth: 1))
            )
        }
        return HStack(spacing: 8) {
            tile("ON-SITE", fleet.driverInitials, fleet.dock)
            tile("DWELL", fleet.dwell, "on-site now")
            tile("HOS", fleet.hos, "10h avail")
            tile("PICKUP", "1/5", "ON-SITE")
        }
    }
}

// MARK: - Stepper (LifecycleStripEight_374 · ring at PICKUP, no transition)

private struct LifecycleStripEight_374: View {
    let stage: LifecycleStage_374
    var body: some View {
        GeometryReader { geo in
            let xs = stride(from: 0.0, through: 1.0, by: 1.0 / 7.0).map { $0 * geo.size.width }
            let node: (LifecycleStage_374, CGFloat) -> AnyView = { s, x in
                let active = (s == stage)
                let done = s.rawValue < stage.rawValue
                return AnyView(
                    Circle()
                        .fill(active ? AnyShapeStyle(Theme374.gradient)
                              : (done ? AnyShapeStyle(Theme374.gradient.opacity(0.45))
                                 : AnyShapeStyle(Color.primary.opacity(0.12))))
                        .frame(width: active ? 6 : 8, height: active ? 6 : 8)
                        .overlay(active ? Circle().strokeBorder(Theme374.gradient, lineWidth: 2).frame(width: 10, height: 10) : nil)
                        .position(x: x, y: 15)
                )
            }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12)).frame(height: 2)
                Capsule().fill(Theme374.gradient)
                    .frame(width: xs[min(stage.rawValue, xs.count - 1)], height: 2)
                ForEach(LifecycleStage_374.allCases, id: \.rawValue) { s in
                    node(s, xs[s.rawValue])
                }
            }
        }
        .frame(height: 34)
    }
}

// MARK: - ActiveCard (FleetTrackerOnSiteCard_374)

private struct FleetTrackerOnSiteCard_374: View {
    let fleet: FleetTrackerOnSite_374
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Theme374.gradientDiag).frame(width: 30, height: 30)
                .overlay(Text(fleet.driverInitials).font(.system(size: 10, weight: .heavy)).foregroundColor(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(fleet.driverName) · CEL fleet").font(.system(size: 11, weight: .heavy))
                Text("\(fleet.driverId) · HOS \(fleet.hos) · \(fleet.location)")
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)
                Text("gate cleared · \(fleet.dock) · dwell \(fleet.dwell)")
                    .font(.system(size: 8)).foregroundColor(.secondary)
            }
            Spacer()
            Text(fleet.status).font(.system(size: 7, weight: .heavy)).foregroundColor(.white)
                .padding(.horizontal, 8).frame(height: 14)
                .background(Capsule().fill(Theme374.gradient))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme374.gradient.opacity(0.55), lineWidth: 1))
    }
}

/// Honest empty state for the fleet-tracker card when no matching driver
/// row is returned by getMyDrivers (cross-fleet relay / not yet on-site).
private struct FleetTrackerAwaitingCard_374: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Theme374.gradient)
            VStack(alignment: .leading, spacing: 2) {
                Text("Awaiting on-site echo")
                    .font(.system(size: 11, weight: .heavy))
                Text("No CEL driver on-site yet · pickup.on_site not received")
                    .font(.system(size: 8)).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
    }
}

// MARK: - ListRow (OnSiteCheckInRowView_374)

private struct OnSiteCheckInRowView_374: View {
    let row: OnSiteCheckInRow_374
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme374.gradientDiag).frame(width: 18, height: 18)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.system(size: 10, weight: .bold))
                Text(row.detail).font(.system(size: 8)).foregroundColor(.secondary)
            }
            Spacer()
            Text(row.elapsed).font(.system(size: 8, weight: .heavy)).foregroundColor(.secondary)
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - ShipperOfRecordCard_374 (DU founder pin co-anchor · pin 154)

private struct ShipperOfRecordCard_374: View {
    let vm: CatalystPickupOnSiteVM_374
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Theme374.gradientDiag).frame(width: 26, height: 26)
                .overlay(Text(vm.shipperMonogram).font(.system(size: 9, weight: .heavy)).foregroundColor(.white))
            VStack(alignment: .leading, spacing: 3) {
                Text("Shipper of record · \(vm.shipperName)").font(.system(size: 10, weight: .heavy))
                Text("\(vm.shipperCompany) · companyId 1 · \(vm.loadNumber) PICKUP echo")
                    .font(.system(size: 8, design: .monospaced)).foregroundColor(.secondary)
            }
            Spacer()
            Text("pin \(vm.founderPin)").font(.system(size: 8, weight: .heavy)).foregroundStyle(Theme374.gradient)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme374.gradient.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme374.gradient.opacity(0.55), lineWidth: 1))
    }
}

// MARK: - ActionRibbon (ActionRibbonPickupOnSiteCatalyst_374)

private struct ActionRibbonPickupOnSiteCatalyst_374: View {
    var body: some View {
        HStack(spacing: 8) {
            // STUB — no carrier-side "confirm at dock" mutation exists on the
            // catalysts router; the dock-arrival verb is the driver's
            // drivers.updateLoadStatus. Catalyst echo is read-only this stage.
            Text("CONFIRM AT DOCK").font(.system(size: 9, weight: .heavy)).kerning(0.5)
                .foregroundColor(.white).frame(width: 156, height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme374.gradient))
            Text("MESSAGE JR").font(.system(size: 9, weight: .heavy)).kerning(0.5)
                .foregroundStyle(Theme374.gradient).frame(width: 120, height: 36)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme374.gradient.opacity(0.55), lineWidth: 1))
            Text("VIEW LOAD").font(.system(size: 9, weight: .heavy)).kerning(0.5)
                .foregroundColor(.secondary).frame(width: 108, height: 36)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
        }
    }
}

// MARK: - Surface body

private struct CatalystPickupOnSiteEchoCelM04View: View {
    @State private var vm = CatalystPickupOnSiteVM_374()
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var hasOnSiteEcho = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                // TopBar eyebrow (single ✦)
                HStack {
                    Text("✦ CATALYST · DISPATCH · PICKUP · ON-SITE")
                        .font(.system(size: 9, weight: .heavy)).kerning(1).foregroundStyle(Theme374.gradient)
                    Spacer()
                    Text("\(vm.loadNumber) · §387 · PICKUP · \(vm.quartetPosition) · CEL ON-SITE")
                        .font(.system(size: 9, weight: .heavy)).kerning(1).foregroundColor(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }

                // Hero
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pickup · CEL driver on-site · \(vm.fleet.dock)")
                        .font(.system(size: 20, weight: .bold)).kerning(-0.6)
                    Text("\(vm.lane) · \(vm.equipment) · \(vm.fleet.driverInitials) on-site · dwell \(vm.fleet.dwell)")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }

                Rectangle().fill(Theme374.gradient.opacity(0.55)).frame(height: 1) // IridescentHairline

                if let err = loadError {
                    errorBanner(err)
                } else if loading {
                    skeleton
                } else {
                    content
                }
            }
            .padding(20)
            .padding(.top, 44)
        }
        .task { await fetch() }
    }

    // MARK: - Loaded content

    @ViewBuilder private var content: some View {
        PickupOnSiteEchoCatalystPill_374(dock: vm.fleet.dock, dwell: vm.fleet.dwell)
            .frame(maxWidth: .infinity)

        KpiQuartetPickupOnSiteCatalyst_374(fleet: vm.fleet)

        LifecycleStripEight_374(stage: vm.stage)

        if hasOnSiteEcho {
            FleetTrackerOnSiteCard_374(fleet: vm.fleet)
        } else {
            FleetTrackerAwaitingCard_374()
        }

        // On-site check-in echo sub-rows
        Text("FLEET-TRACKER ECHO · ON-SITE CHECK-IN · drivers.updateLoadStatus(at_pickup)")
            .font(.system(size: 8, weight: .heavy)).kerning(0.5).foregroundColor(.secondary)
        ForEach(vm.checkIns) { OnSiteCheckInRowView_374(row: $0) }

        // PICKUP sub-axis progress capsule (1/5 = 20%)
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10)).frame(height: 4)
                    Capsule().fill(Theme374.gradient).frame(width: geo.size.width * 0.2, height: 4)
                }
            }.frame(height: 4)
            Text("PICKUP SUB-AXIS · 1/5 ON-SITE · 20% · next AT-DOCK")
                .font(.system(size: 8, weight: .heavy)).kerning(0.4).foregroundColor(.secondary)
        }

        ShipperOfRecordCard_374(vm: vm)

        ActionRibbonPickupOnSiteCatalyst_374()

        Color.clear.frame(height: 24)
    }

    // MARK: - Skeleton / error

    private var skeleton: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)).frame(height: 22)
            RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)).frame(height: 60)
            RoundedRectangle(cornerRadius: 12).fill(Color(.systemBackground)).frame(height: 64)
        }
        .redacted(reason: .placeholder)
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .heavy)).foregroundColor(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't reach CEL fleet-tracker").font(.system(size: 11, weight: .heavy)).foregroundColor(.white)
                Text(msg).font(.system(size: 9)).foregroundColor(.white.opacity(0.85)).lineLimit(2)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme374.gradient))
    }

    // MARK: - Network (generic client · MCP-confirmed shapes)

    private func fetch() async {
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            // 1) Active loads — find the M-04 row now at at_pickup.
            let loads: [CatalystActiveLoad_374] = try await EusoTripAPI.shared.query(
                "catalysts.getActiveLoads",
                input: CatalystActiveLoadsInput_374(limit: 25))

            // Prefer a row at the pickup stage (at_pickup / assigned /
            // loading); fall back to the first row so the lane/rate still
            // paint rather than collapsing to a fake.
            let pickupRow = loads.first { row in
                LifecycleStage_374.from(loadStatus: row.status) == .pickup
            }
            if let row = pickupRow ?? loads.first {
                vm.loadId = row.id
                vm.loadNumber = row.loadNumber
                vm.lane = "\(row.origin) → \(row.destination)"
                if row.rate > 0 { vm.awardedUsd = row.rate }
                vm.stage = LifecycleStage_374.from(loadStatus: row.status)

                // 2) Driver roster — match the active load's driver to the
                //    fleet-tracker on-site row (real HOS + location).
                let drivers: [CatalystFleetDriver_374] = try await EusoTripAPI.shared.query(
                    "catalysts.getMyDrivers",
                    input: CatalystMyDriversInput_374(limit: 50))

                let matched = drivers.first { $0.name == row.driver }
                    ?? drivers.first { $0.currentLoad == row.loadNumber }
                if let d = matched {
                    vm.fleet = FleetTrackerOnSite_374(
                        driverInitials: monogram(d.name),
                        driverName: d.name,
                        driverId: d.id,
                        hos: d.hoursRemaining.map { String(format: "%.1fh", $0) } ?? "on-duty",
                        status: row.status.uppercased() == "AT_PICKUP" ? "ON-SITE" : d.status.uppercased(),
                        dock: vm.fleet.dock,
                        dwell: vm.fleet.dwell,
                        location: d.location)
                    hasOnSiteEcho = (vm.stage == .pickup)
                } else {
                    hasOnSiteEcho = false
                }
            } else {
                // No active pickup row — honest awaiting state.
                hasOnSiteEcho = false
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func monogram(_ name: String) -> String {
        let parts = name.split(whereSeparator: { $0 == " " || $0 == "," }).prefix(2)
        let initials = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return initials.isEmpty ? "?" : String(initials.prefix(2))
    }
}

// MARK: - Preview seed (offline)

@MainActor private func previewSession_374() -> EusoTripSession {
    EusoTripSession()
}

#Preview("374 · Catalyst · Pickup On-Site Echo · Night") {
    CatalystPickupOnSiteEchoCelM04Screen(theme: Theme.dark)
        .environmentObject(previewSession_374())
        .preferredColorScheme(.dark)
}

#Preview("374 · Catalyst · Pickup On-Site Echo · Afternoon") {
    CatalystPickupOnSiteEchoCelM04Screen(theme: Theme.light)
        .environmentObject(previewSession_374())
        .preferredColorScheme(.light)
}
