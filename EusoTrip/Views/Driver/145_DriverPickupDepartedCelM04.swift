//
//  145_DriverPickupDepartedCelM04.swift
//  EusoTrip — Driver · pickup departed / trip-launch surface.
//
//  Wireframe slot: 01 Driver / 145 Driver Pickup Departed CEL M04
//  (Light/Dark SVG pair is design truth — TripLaunch hero replaces the
//  generic KPI quartet; composition is a journey-line at its origin).
//
//  Wiring (verified against the live routers this fire):
//    WRITE  drivers.updateLoadStatus   — status "in_transit" (the departure
//           verb; the same mutation flips HOS duty to driving organically)
//    READ   loads.getById              — bound load (lane, payout, appt)
//    READ   drivers.getMyHOSStatus     — duty status + drive clock
//    READ   drivers.getAssignedVehicle — tractor / trailer identity
//    READ   drivers.lifecycle          — stops (pickup departedAt when stamped)
//  NAMED GAPS (honest): no GPS-heartbeat verb exists, so no live-position
//  claim is rendered; the route lane is anchored at the origin.
//
//  Doctrine: every visible value binds to a read with an honest "-"
//  fallback. Copy dispatches through LifecycleProductContext. No wireframe
//  persona strings ship.
//

import SwiftUI
import UIKit

// MARK: - tRPC decode shapes

private struct PDLoadCtx: Decodable, Hashable {
    let loadNumber: String?
    let status: String?
    let rate: String?
    let distance: Double?
    let cargoType: String?
    let hazmatClass: String?
    let deliveryDate: String?
    let pickupLocation: PDCityState?
    let deliveryLocation: PDCityState?
    let shipper: PDParty?
    let catalyst: PDParty?

    struct PDCityState: Decodable, Hashable { let city: String?; let state: String? }
    struct PDParty: Decodable, Hashable {
        let name: String?; let initials: String?; let companyName: String?; let mcNumber: String?
    }
}

private struct PDHos: Decodable, Hashable {
    let status: String?
    let drivingRemaining: String?    // display-ready "10h 14m"
    let onDutyRemaining: String?
    let canDrive: Bool?
}

private struct PDVehicle: Decodable, Hashable {
    let unitNumber: String?
    let make: String?
    let model: String?
    let trailer: PDTrailer?
    struct PDTrailer: Decodable, Hashable { let unitNumber: String? }
}

private struct PDLifecycle: Decodable, Hashable {
    let pickup: PDStop?
    let delivery: PDStop?
    struct PDStop: Decodable, Hashable {
        let facilityName: String?
        let city: String?
        let state: String?
        let departedAt: String?
        let arrivedAt: String?
    }
}

// MARK: - Screen

struct DriverPickupDepartedCelM04Screen: View {
    let theme: Theme.Palette
    let loadId: String
    @EnvironmentObject private var nav: DriverNavController

    var body: some View {
        Shell(theme: theme) {
            PDBody(loadId: loadId, onHosClock: { nav.currentTab = .me })
        } nav: {
            BottomNav(
                leading: [NavSlot(label: DriverTab.home.label,  systemImage: DriverTab.home.systemImage,  isCurrent: false),
                          NavSlot(label: DriverTab.trips.label, systemImage: DriverTab.trips.systemImage, isCurrent: true)],
                trailing: [NavSlot(label: DriverTab.wallet.label, systemImage: DriverTab.wallet.systemImage, isCurrent: false),
                           NavSlot(label: DriverTab.me.label,     systemImage: DriverTab.me.systemImage,     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct PDBody: View {
    let loadId: String
    let onHosClock: () -> Void

    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var session: EusoTripSession

    @State private var load: PDLoadCtx?
    @State private var hos: PDHos?
    @State private var vehicle: PDVehicle?
    @State private var lifecycle: PDLifecycle?

    @State private var actionInFlight = false
    @State private var actionAck: String?
    @State private var actionError: String?

    private var ctx: LifecycleProductContext {
        LifecycleProductContext.forCargo(
            cargoType: load?.cargoType, hazmatClass: load?.hazmatClass, role: session.user?.role)
    }

    private var status: String { (load?.status ?? "").lowercased() }
    private var departed: Bool {
        ["in_transit", "at_delivery", "unloading", "delivered", "pod_pending", "paid", "completed"].contains(status)
    }
    private var canDepart: Bool {
        ["assigned", "en_route_pickup", "at_pickup", "loading", "accepted"].contains(status)
    }
    private var loadNumberDisplay: String { load?.loadNumber ?? "-" }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                PDTripLaunchHero(
                    launched: departed,
                    driveClock: hos?.drivingRemaining ?? "-",
                    dutyNote: hosDutyNote,
                    eta: etaDisplay,
                    apptNote: apptNote,
                    gateOut: gateOutDisplay,
                    originLabel: originLabel,
                    destLabel: destLabel
                )
                departCheckCard
                identityCard
                PDLifecycleStripEight(status: load?.status)
                if let ack = actionAck {
                    LifecycleCard(accentGradient: true) {
                        Text(ack).font(EType.caption).foregroundStyle(palette.textPrimary)
                    }
                }
                if let err = actionError {
                    LifecycleCard { Text(err).font(EType.caption).foregroundStyle(.red) }
                }
                actionRibbon
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await refresh() }
        .eusoRefreshable { await refresh() }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("DRIVER · TRIPS · \(ctx.headerKicker) · \(loadNumberDisplay)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
            }
            HStack(alignment: .center) {
                Text(departed ? "Departed" : "Ready to roll")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if departed {
                    HStack(spacing: 5) {
                        Image(systemName: "location.north.fill").font(.system(size: 9, weight: .heavy))
                        Text("DEPARTED · ROLLING").font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(LinearGradient.diagonal))
                }
            }
            Text(departed
                 ? "Pickup is closed out — your duty clock is running as driving."
                 : "Confirm departure the moment you pull off the dock. Your duty clock flips to driving automatically.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: depart-check roster (real-bound rows)

    private var departCheckCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("DEPARTURE CHECK")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                checkRow(label: "Pickup closed out",
                         done: departed || status == "loading",
                         detail: departed ? "closed" : (status.isEmpty ? "-" : status.replacingOccurrences(of: "_", with: " ")))
                checkRow(label: "Wheels rolling",
                         done: departed,
                         detail: departed ? "confirmed" : "awaiting your confirm")
                checkRow(label: "Duty status",
                         done: (hos?.status ?? "") == "driving",
                         detail: hos?.status?.replacingOccurrences(of: "_", with: " ") ?? "-")
            }
        }
    }

    private func checkRow(label: String, done: Bool, detail: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                if done {
                    Circle().fill(LinearGradient.diagonal).frame(width: 16, height: 16)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                } else {
                    Circle().stroke(palette.borderStrong, lineWidth: 1.5).frame(width: 16, height: 16)
                }
            }
            Text(label).font(.system(size: 11)).foregroundStyle(palette.textPrimary)
            Spacer()
            Text(detail)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(done ? palette.success : palette.textSecondary)
                .lineLimit(1)
        }
    }

    // MARK: identity (vehicle + parties · live-bound)

    private var identityCard: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(load?.shipper?.initials ?? "-")
                        .font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(load?.catalyst?.companyName ?? load?.catalyst?.name ?? "-") · \(load?.shipper?.name ?? "-") shipper")
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text(vehicleLine)
                        .font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(1)
                }
                Spacer()
            }
        }
    }

    private var vehicleLine: String {
        let truck = vehicle?.unitNumber.flatMap { $0.isEmpty ? nil : $0 } ?? "-"
        let trailer = vehicle?.trailer?.unitNumber.flatMap { $0.isEmpty ? nil : $0 } ?? "-"
        return "Tractor \(truck) · Trailer \(trailer)"
    }

    // MARK: action ribbon

    private var actionRibbon: some View {
        HStack(spacing: 8) {
            Button { Task { await confirmDeparture() } } label: {
                HStack(spacing: 8) {
                    if actionInFlight { ProgressView().tint(.white).scaleEffect(0.8) }
                    Image(systemName: "location.north.fill").font(.system(size: 13, weight: .heavy))
                    Text(primaryLabel).font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background { LinearGradient.diagonal.opacity(primaryEnabled ? 1 : 0.4) }
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!primaryEnabled || actionInFlight)

            Button(action: onHosClock) {
                Text("HOS clock").font(EType.caption.weight(.semibold))
                    .frame(maxWidth: 120, minHeight: 48)
                    .foregroundStyle(LinearGradient.diagonal)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(LinearGradient.diagonal.opacity(0.55), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var primaryLabel: String {
        if actionInFlight { return "Confirming…" }
        if departed { return "Open route" }
        if canDepart { return "Confirm departure" }
        return "No active pickup to depart"
    }
    private var primaryEnabled: Bool { departed ? destinationMapURL != nil : canDepart }

    private func confirmDeparture() async {
        if departed { openRoute(); return }
        actionInFlight = true; actionAck = nil; actionError = nil
        defer { actionInFlight = false }
        struct In: Encodable { let status: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "drivers.updateLoadStatus", input: In(status: "in_transit"))
            if resp.success == false {
                actionError = "Departure didn't record. Nothing changed — check signal and tap again."
            } else {
                actionAck = "Departure recorded · \(loadNumberDisplay) is in transit. Duty clock is running as driving."
            }
        } catch {
            actionError = "Departure didn't record. Nothing changed — check signal and tap again."
        }
        await refresh()
    }

    /// Real local effect: hand the destination to the system Maps app.
    private var destinationMapURL: URL? {
        guard let c = load?.deliveryLocation?.city, !c.isEmpty else { return nil }
        let s = load?.deliveryLocation?.state ?? ""
        let q = "\(c) \(s)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? c
        return URL(string: "maps://?daddr=\(q)")
    }
    private func openRoute() {
        guard let url = destinationMapURL else { return }
        openURL(url)
    }

    // MARK: reads

    private func refresh() async {
        async let a: Void = readLoad()
        async let b: Void = readHos()
        async let c: Void = readVehicle()
        async let d: Void = readLifecycle()
        _ = await (a, b, c, d)
    }

    private func readLoad() async {
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* "-" */ }
    }
    private func readHos() async {
        do { hos = try await EusoTripAPI.shared.queryNoInput("drivers.getMyHOSStatus") } catch { /* "-" */ }
    }
    private func readVehicle() async {
        do { vehicle = try await EusoTripAPI.shared.queryNoInput("drivers.getAssignedVehicle") } catch { /* "-" */ }
    }
    private func readLifecycle() async {
        struct In: Encodable { let loadId: String }
        do { lifecycle = try await EusoTripAPI.shared.query("drivers.lifecycle", input: In(loadId: loadId)) } catch { /* "-" */ }
    }

    // MARK: display derivations (honest — "-" when the read hasn't resolved)

    private var hosDutyNote: String {
        guard let s = hos?.status, !s.isEmpty else { return "duty status pending" }
        return "duty · \(s.replacingOccurrences(of: "_", with: " "))"
    }
    private var etaDisplay: String {
        guard let d = PDBody.parseISO(load?.deliveryDate) else { return "-" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
    private var apptNote: String {
        guard let d = PDBody.parseISO(load?.deliveryDate) else { return "appointment pending" }
        let f = DateFormatter(); f.dateFormat = "EEE HH:mm"
        return "appt \(f.string(from: d))"
    }
    private var gateOutDisplay: String {
        guard let d = PDBody.parseISO(lifecycle?.pickup?.departedAt) else { return "-" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
    private var originLabel: String {
        let c = lifecycle?.pickup?.city ?? load?.pickupLocation?.city ?? "-"
        return c.isEmpty ? "-" : c
    }
    private var destLabel: String {
        let c = lifecycle?.delivery?.city ?? load?.deliveryLocation?.city ?? "-"
        guard !c.isEmpty else { return "-" }
        if let mi = load?.distance, mi > 0 { return "\(c) · \(Int(mi.rounded())) mi" }
        return c
    }

    fileprivate static func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        return ISO8601DateFormatter().date(from: s)
    }
}

// MARK: - Trip-launch hero (journey line at its origin · palette-token twin
//         of the wireframe hero so both modes render)

private struct PDTripLaunchHero: View {
    let launched: Bool
    let driveClock: String
    let dutyNote: String
    let eta: String
    let apptNote: String
    let gateOut: String
    let originLabel: String
    let destLabel: String

    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: 18.5).fill(palette.bgCard).padding(1.5)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(launched ? "TRIP LAUNCHED · ROLLING" : "TRIP READY · AT ORIGIN")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(LinearGradient.diagonal)
                    Spacer()
                    Text(gateOut == "-" ? "GATE-OUT PENDING" : "GATE-OUT \(gateOut)")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                }
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DRIVE CLOCK").font(.system(size: 8.5, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(palette.textTertiary)
                        Text(driveClock).font(.system(size: 26, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(dutyNote).font(.system(size: 8)).foregroundStyle(palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(palette.borderFaint).frame(width: 1, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ETA").font(.system(size: 8.5, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(palette.textTertiary)
                        Text(eta).font(.system(size: 26, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(apptNote).font(.system(size: 8)).foregroundStyle(palette.textSecondary)
                    }
                    .padding(.leading, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 12)
                Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.top, 10)
                // Journey line — origin-anchored marker; no live-position claim
                // (no location feed exists, so the marker sits at the origin
                // until arrival events stamp real progress).
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(palette.tintNeutral).frame(height: 7)
                            Capsule().fill(LinearGradient.diagonal)
                                .frame(width: max(10, geo.size.width * (launched ? 0.04 : 0.0)), height: 7)
                            Circle().fill(palette.bgCard)
                                .overlay(Circle().stroke(LinearGradient.diagonal, lineWidth: 2))
                                .frame(width: 11, height: 11)
                                .offset(x: launched ? max(0, geo.size.width * 0.04 - 5.5) : 0)
                            Circle().fill(palette.success).frame(width: 6.4, height: 6.4)
                                .offset(x: geo.size.width - 6.4)
                        }
                    }
                    .frame(height: 11)
                }
                .padding(.top, 10)
                HStack {
                    Text(originLabel)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                    Text(destLabel)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.top, 4)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 148)
    }
}

// MARK: - Lifecycle strip

private struct PDLifecycleStripEight: View {
    let status: String?
    @Environment(\.palette) private var palette

    private static let stages = ["POSTED", "BIDDING", "AWARDED", "PICKUP", "TRANSIT", "DELIVERY", "PAPERWORK", "CLOSED"]

    private var activeIndex: Int? {
        switch (status ?? "").lowercased() {
        case "posted", "pending", "available":            return 0
        case "bidding":                                    return 1
        case "accepted", "awarded", "assigned":            return 2
        case "en_route_pickup", "at_pickup", "loading":    return 3
        case "in_transit":                                 return 4
        case "at_delivery", "unloading":                   return 5
        case "delivered", "pod_pending":                   return 6
        case "invoiced", "paid", "closed", "completed":    return 7
        default:                                            return nil
        }
    }

    var body: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("LIFECYCLE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                HStack(spacing: 4) {
                    ForEach(Array(Self.stages.enumerated()), id: \.offset) { idx, name in
                        VStack(spacing: 3) {
                            ZStack {
                                if let a = activeIndex, idx < a {
                                    Circle().fill(LinearGradient.diagonal).frame(width: 10, height: 10)
                                } else if let a = activeIndex, idx == a {
                                    Circle().stroke(LinearGradient.diagonal, lineWidth: 2).frame(width: 12, height: 12)
                                } else {
                                    Circle().fill(palette.tintNeutral).frame(width: 8, height: 8)
                                }
                            }
                            .frame(height: 12)
                            Text(name)
                                .font(.system(size: 5.5, weight: .heavy)).tracking(0.2)
                                .foregroundStyle(activeIndex == idx ? palette.textPrimary : palette.textTertiary)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("145 Pickup Departed · Light") {
    DriverPickupDepartedCelM04Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .environmentObject(DriverNavController())
        .preferredColorScheme(.light)
}

#Preview("145 Pickup Departed · Dark") {
    DriverPickupDepartedCelM04Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .environmentObject(DriverNavController())
        .preferredColorScheme(.dark)
}

#Preview("145 Trip-Launch Hero · Light") {
    PDTripLaunchHero(launched: true, driveClock: "11h 00m", dutyNote: "duty · driving",
                     eta: "12:46", apptNote: "appt Fri 14:00", gateOut: "08:46",
                     originLabel: "Atlanta", destLabel: "Charlotte · 245 mi")
        .environment(\.palette, Theme.light)
        .padding()
        .preferredColorScheme(.light)
}

#Preview("145 Trip-Launch Hero · Dark") {
    PDTripLaunchHero(launched: false, driveClock: "-", dutyNote: "duty status pending",
                     eta: "-", apptNote: "appointment pending", gateOut: "-",
                     originLabel: "-", destLabel: "-")
        .environment(\.palette, Theme.dark)
        .padding()
        .preferredColorScheme(.dark)
}
