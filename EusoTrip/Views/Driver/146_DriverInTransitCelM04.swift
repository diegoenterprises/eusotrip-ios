//
//  146_DriverInTransitCelM04.swift
//  EusoTrip — Driver · in-transit / on-the-road monitoring surface.
//
//  Wireframe slot: 01 Driver / 146 Driver In Transit CEL M04
//  (Light/Dark SVG pair is design truth — Make-The-Dock headroom hero:
//  the one in-transit question is whether the wheels reach the dock
//  before the drive clock forces a stop).
//
//  Wiring (verified against the live routers this fire): READ-ONLY surface,
//  no mutation fires while the load status holds at in_transit.
//    READ   loads.getById              — bound load (lane, appt, payout)
//    READ   drivers.getMyHOSStatus     — duty status + drive clock remaining
//    READ   drivers.getAssignedVehicle — tractor / trailer identity
//    READ   drivers.lifecycle          — pickup departedAt (drives the
//           honest time-based route estimate, badged "est.")
//  NAMED GAP (honest): no GPS-heartbeat verb exists — the route lane is a
//  time-based ESTIMATE and is badged as such; it is never presented as a
//  live position.
//
//  Doctrine: every visible value binds to a read with an honest "-"
//  fallback. Copy dispatches through LifecycleProductContext.
//

import SwiftUI
import UIKit

// MARK: - tRPC decode shapes

private struct ITLoadCtx: Decodable, Hashable {
    let loadNumber: String?
    let status: String?
    let rate: String?
    let distance: Double?
    let cargoType: String?
    let hazmatClass: String?
    let deliveryDate: String?
    let pickupLocation: ITCityState?
    let deliveryLocation: ITCityState?
    let catalyst: ITParty?
    let shipper: ITParty?

    struct ITCityState: Decodable, Hashable { let city: String?; let state: String? }
    struct ITParty: Decodable, Hashable {
        let name: String?; let initials: String?; let companyName: String?; let mcNumber: String?
    }
}

private struct ITHos: Decodable, Hashable {
    let status: String?
    let drivingRemaining: String?   // display-ready "10h 14m"
    let onDutyRemaining: String?
    let canDrive: Bool?
}

private struct ITVehicle: Decodable, Hashable {
    let unitNumber: String?
    let trailer: ITTrailer?
    struct ITTrailer: Decodable, Hashable { let unitNumber: String? }
}

private struct ITLifecycle: Decodable, Hashable {
    let pickup: ITStop?
    let delivery: ITStop?
    struct ITStop: Decodable, Hashable {
        let facilityName: String?; let city: String?; let state: String?
        let departedAt: String?; let arrivedAt: String?
    }
}

// MARK: - Screen

struct DriverInTransitCelM04Screen: View {
    let theme: Theme.Palette
    let loadId: String
    @EnvironmentObject private var nav: DriverNavController

    var body: some View {
        Shell(theme: theme) {
            ITBody(loadId: loadId, onHosClock: { nav.currentTab = .me })
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

private struct ITBody: View {
    let loadId: String
    let onHosClock: () -> Void

    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @State private var load: ITLoadCtx?
    @State private var hos: ITHos?
    @State private var vehicle: ITVehicle?
    @State private var lifecycle: ITLifecycle?

    private var ctx: LifecycleProductContext {
        LifecycleProductContext.forCargo(
            cargoType: load?.cargoType, hazmatClass: load?.hazmatClass, role: session.user?.role)
    }

    private var loadNumberDisplay: String { load?.loadNumber ?? "-" }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                ITMakeTheDockHero(
                    spareAtDock: spareAtDockDisplay,
                    needToDock: needToDockDisplay,
                    milesNote: milesNote,
                    driveRemaining: hos?.drivingRemaining ?? "-",
                    etaDock: apptDisplay,
                    onSchedule: onScheduleVerdict,
                    estProgress: estProgress
                )
                onRoadCard
                nextStageCard
                ITLifecycleStripEight(status: load?.status)
                actionRibbon
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("DRIVER · TRIPS · \(ctx.headerKicker) · \(loadNumberDisplay)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
            }
            HStack {
                Text("In transit")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if (load?.status ?? "") == "in_transit" {
                    HStack(spacing: 5) {
                        Image(systemName: "location.north.fill").font(.system(size: 9, weight: .heavy))
                        Text("ON THE ROAD").font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(LinearGradient.diagonal))
                }
            }
            Text(laneDisplay ?? "Lane details are still syncing — pull to refresh.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: on-road telemetry rows

    private var onRoadCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("ON THE ROAD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                roadRow(label: "Duty status",
                        value: hos?.status?.replacingOccurrences(of: "_", with: " ") ?? "-",
                        live: (hos?.status ?? "") == "driving")
                roadRow(label: "Drive clock remaining",
                        value: hos?.drivingRemaining ?? "-",
                        live: false)
                roadRow(label: "On-duty window",
                        value: hos?.onDutyRemaining ?? "-",
                        live: false)
                roadRow(label: "Tractor · trailer",
                        value: vehicleLine,
                        live: false)
                // Honest estimate row — no live-position feed exists, so this
                // is time-based and badged as an estimate, never a claim.
                HStack(spacing: 10) {
                    ZStack {
                        Circle().stroke(palette.borderStrong, lineWidth: 1.5).frame(width: 16, height: 16)
                        Circle().fill(palette.textTertiary).frame(width: 4, height: 4)
                    }
                    Text("Route progress").font(.system(size: 11)).foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(estProgressLabel)
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textSecondary)
                    Text("est.")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .overlay(Capsule().stroke(palette.borderSoft, lineWidth: 1))
                }
            }
        }
    }

    private func roadRow(label: String, value: String, live: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                if live {
                    Circle().fill(LinearGradient.diagonal).frame(width: 16, height: 16)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                } else {
                    Circle().fill(palette.tintNeutral).frame(width: 16, height: 16)
                }
            }
            Text(label).font(.system(size: 11)).foregroundStyle(palette.textPrimary)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(live ? palette.success : palette.textSecondary)
                .lineLimit(1)
        }
    }

    // MARK: next stage preview

    private var nextStageCard: some View {
        LifecycleCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEXT · DELIVERY")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(palette.textTertiary)
                    Text(deliveryPreview)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
        }
    }

    private var deliveryPreview: String {
        let fac = lifecycle?.delivery?.facilityName ?? ""
        let city = lifecycle?.delivery?.city ?? load?.deliveryLocation?.city ?? ""
        if !fac.isEmpty { return "\(fac) · \(city)" }
        if !city.isEmpty { return "Receiver · \(city)" }
        return "Receiver details pending"
    }

    // MARK: actions — Open route (real Maps hand-off) + HOS clock

    private var actionRibbon: some View {
        HStack(spacing: 8) {
            Button { openRoute() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "location.north.fill").font(.system(size: 13, weight: .heavy))
                    Text("Open route").font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal.opacity(destinationMapURL != nil ? 1 : 0.4))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(destinationMapURL == nil)

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

    private var destinationMapURL: URL? {
        guard let c = load?.deliveryLocation?.city, !c.isEmpty else { return nil }
        let s = load?.deliveryLocation?.state ?? ""
        let q = "\(c) \(s)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? c
        return URL(string: "maps://?daddr=\(q)")
    }
    private func openRoute() {
        guard let url = destinationMapURL else { return }
        UIApplication.shared.open(url)
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

    // MARK: derivations (all honest — nil/"-" collapse when reads are missing)

    private var laneDisplay: String? {
        guard let p = load?.pickupLocation?.city, let d = load?.deliveryLocation?.city,
              !p.isEmpty, !d.isEmpty else { return nil }
        var line = "\(p) → \(d)"
        if let mi = load?.distance, mi > 0 { line += " · \(Int(mi.rounded())) mi" }
        return line
    }
    private var vehicleLine: String {
        let truck = vehicle?.unitNumber.flatMap { $0.isEmpty ? nil : $0 } ?? "-"
        let trailer = vehicle?.trailer?.unitNumber.flatMap { $0.isEmpty ? nil : $0 } ?? "-"
        return "\(truck) · \(trailer)"
    }
    private var apptDisplay: String {
        guard let d = ITBody.parseISO(load?.deliveryDate) else { return "-" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    /// Minutes the driver still needs to reach the dock — derived from the
    /// committed appointment, not a position claim.
    private var minutesToAppt: Int? {
        guard let appt = ITBody.parseISO(load?.deliveryDate) else { return nil }
        let mins = Int(appt.timeIntervalSinceNow / 60)
        return mins > 0 ? mins : 0
    }
    private var driveRemainingMinutes: Int? { ITBody.parseHM(hos?.drivingRemaining) }

    private var needToDockDisplay: String {
        guard let m = minutesToAppt else { return "-" }
        return ITBody.formatHM(m)
    }
    private var spareAtDockDisplay: String {
        guard let drive = driveRemainingMinutes, let need = minutesToAppt else { return "-" }
        return ITBody.formatHM(drive - need)
    }
    private var onScheduleVerdict: Bool? {
        guard let drive = driveRemainingMinutes, let need = minutesToAppt else { return nil }
        return drive >= need
    }
    private var milesNote: String {
        guard let mi = load?.distance, mi > 0 else { return "distance pending" }
        return "\(Int(mi.rounded())) mi lane"
    }

    /// Time-based route estimate: elapsed share of the departure→appointment
    /// window. nil (lane hidden) when either anchor is missing.
    private var estProgress: Double? {
        guard let dep = ITBody.parseISO(lifecycle?.pickup?.departedAt),
              let appt = ITBody.parseISO(load?.deliveryDate),
              appt > dep else { return nil }
        let p = Date().timeIntervalSince(dep) / appt.timeIntervalSince(dep)
        return min(max(p, 0), 1)
    }
    private var estProgressLabel: String {
        guard let p = estProgress else { return "unavailable" }
        return "\(Int((p * 100).rounded()))%"
    }

    fileprivate static func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        return ISO8601DateFormatter().date(from: s)
    }
    /// Parse the server's display clock ("10h 14m") back to minutes for the
    /// headroom derivation. Lenient — nil on any surprise shape.
    fileprivate static func parseHM(_ s: String?) -> Int? {
        guard let s else { return nil }
        let parts = s.lowercased().replacingOccurrences(of: "m", with: "")
            .split(separator: "h").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) { return h * 60 + m }
        if parts.count == 1, let h = Int(parts[0]) { return h * 60 }
        return nil
    }
    fileprivate static func formatHM(_ minutes: Int) -> String {
        let sign = minutes < 0 ? "-" : ""
        let m = abs(minutes)
        return "\(sign)\(m / 60)h \(String(format: "%02d", m % 60))m"
    }
}

// MARK: - Make-The-Dock hero (headroom race · palette-token twin of the
//         wireframe hero so both modes render)

private struct ITMakeTheDockHero: View {
    let spareAtDock: String
    let needToDock: String
    let milesNote: String
    let driveRemaining: String
    let etaDock: String
    let onSchedule: Bool?          // nil → verdict withheld (missing anchor)
    let estProgress: Double?       // nil → lane hidden honestly

    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: 18.5).fill(palette.bgCard).padding(1.5)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("WILL YOU MAKE THE DOCK?")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(LinearGradient.diagonal)
                    Spacer()
                    if let ok = onSchedule {
                        HStack(spacing: 4) {
                            Image(systemName: ok ? "checkmark" : "exclamationmark.triangle.fill")
                                .font(.system(size: 9, weight: .heavy))
                            Text(ok ? "ON SCHEDULE" : "CLOCK TIGHT")
                                .font(.system(size: 9, weight: .heavy)).tracking(0.2)
                        }
                        .foregroundStyle(ok ? palette.success : palette.warning)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill((ok ? palette.success : palette.warning).opacity(0.14)))
                    }
                }
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CLOCK SPARE AT DOCK").font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                        Text(spareAtDock).font(.system(size: 24, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(palette.borderFaint).frame(width: 1, height: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NEED TO DOCK").font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                        Text(needToDock).font(.system(size: 15, weight: .heavy, design: .monospaced))
                            .foregroundStyle(palette.textPrimary)
                        Text(milesNote).font(.system(size: 8)).foregroundStyle(palette.textSecondary)
                    }
                    .padding(.leading, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ON THE CLOCK").font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary)
                        Text(driveRemaining).font(.system(size: 15, weight: .heavy, design: .monospaced))
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("dock \(etaDock)").font(.system(size: 8)).foregroundStyle(palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 12)
                Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.top, 10)
                if let p = estProgress {
                    HStack(spacing: 8) {
                        Text("ROAD").font(.system(size: 7.5, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(palette.textTertiary).frame(width: 32, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(palette.tintNeutral).frame(height: 7)
                                Capsule().fill(LinearGradient.diagonal)
                                    .frame(width: max(7, geo.size.width * p), height: 7)
                                Circle().fill(palette.success).frame(width: 6.4, height: 6.4)
                                    .offset(x: geo.size.width - 6.4)
                            }
                        }
                        .frame(height: 11)
                        Text("est.")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .padding(.top, 8)
                } else {
                    Text("Route estimate unavailable until departure is stamped.")
                        .font(.system(size: 8)).foregroundStyle(palette.textTertiary)
                        .padding(.top, 8)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
    }
}

// MARK: - Lifecycle strip

private struct ITLifecycleStripEight: View {
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

#Preview("146 In Transit · Light") {
    DriverInTransitCelM04Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .environmentObject(DriverNavController())
        .preferredColorScheme(.light)
}

#Preview("146 In Transit · Dark") {
    DriverInTransitCelM04Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .environmentObject(DriverNavController())
        .preferredColorScheme(.dark)
}

#Preview("146 Make-The-Dock Hero · Light") {
    ITMakeTheDockHero(spareAtDock: "7h 02m", needToDock: "3h 12m", milesNote: "245 mi lane",
                      driveRemaining: "10h 14m", etaDock: "14:00", onSchedule: true, estProgress: 0.19)
        .environment(\.palette, Theme.light)
        .padding()
        .preferredColorScheme(.light)
}

#Preview("146 Make-The-Dock Hero · Dark") {
    ITMakeTheDockHero(spareAtDock: "-", needToDock: "-", milesNote: "distance pending",
                      driveRemaining: "-", etaDock: "-", onSchedule: nil, estProgress: nil)
        .environment(\.palette, Theme.dark)
        .padding()
        .preferredColorScheme(.dark)
}
