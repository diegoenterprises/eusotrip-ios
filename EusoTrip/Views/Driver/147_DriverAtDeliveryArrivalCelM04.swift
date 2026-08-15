//
//  147_DriverAtDeliveryArrivalCelM04.swift
//  EusoTrip — Driver · at-delivery arrival surface (the ring roll
//  in-transit → delivery, then the natural next verb: start unloading).
//
//  Wireframe slot: 01 Driver / 147 Driver At Delivery Arrival CEL M04
//  (Light/Dark SVG pair is design truth — arrival fan-out hero: arrived
//  vs appointment, and the downstream parties the arrival reaches).
//
//  Wiring (verified against the live routers this fire):
//    WRITE  drivers.updateLoadStatus   — "at_delivery" (arrival verb; duty
//           flips driving → on-duty organically), then "unloading" once
//           the door opens
//    READ   loads.getById              — bound load + resolved parties
//    READ   drivers.getMyHOSStatus     — duty status + clocks
//    READ   drivers.lifecycle          — delivery stop arrivedAt
//  Fan-out truth: the arrival status write notifies the shipper and the
//  carrier directly; dispatch picks it up on its board sync. The hero
//  chips mirror exactly that — no invented recipients.
//
//  Doctrine: live binds with honest "-" fallbacks; product copy through
//  LifecycleProductContext; no wireframe persona strings.
//

import SwiftUI

// MARK: - tRPC decode shapes

private struct ADLoadCtx: Decodable, Hashable {
    let loadNumber: String?
    let status: String?
    let rate: String?
    let distance: Double?
    let cargoType: String?
    let hazmatClass: String?
    let deliveryDate: String?
    let pickupLocation: ADCityState?
    let deliveryLocation: ADCityState?
    let catalyst: ADParty?
    let shipper: ADParty?

    struct ADCityState: Decodable, Hashable { let city: String?; let state: String? }
    struct ADParty: Decodable, Hashable {
        let name: String?; let initials: String?; let companyName: String?; let mcNumber: String?
    }
}

private struct ADHos: Decodable, Hashable {
    let status: String?
    let drivingRemaining: String?
    let onDutyRemaining: String?
}

private struct ADLifecycle: Decodable, Hashable {
    let delivery: ADStop?
    struct ADStop: Decodable, Hashable {
        let facilityName: String?; let city: String?; let state: String?
        let arrivedAt: String?; let departedAt: String?
    }
}

// MARK: - Screen

struct DriverAtDeliveryArrivalCelM04Screen: View {
    let theme: Theme.Palette
    let loadId: String
    @EnvironmentObject private var nav: DriverNavController

    var body: some View {
        Shell(theme: theme) {
            ADBody(loadId: loadId, onHosClock: { nav.currentTab = .me })
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

private struct ADBody: View {
    let loadId: String
    let onHosClock: () -> Void

    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @State private var load: ADLoadCtx?
    @State private var hos: ADHos?
    @State private var lifecycle: ADLifecycle?

    @State private var actionInFlight = false
    @State private var actionAck: String?
    @State private var actionError: String?

    private var ctx: LifecycleProductContext {
        LifecycleProductContext.forCargo(
            cargoType: load?.cargoType, hazmatClass: load?.hazmatClass, role: session.user?.role)
    }

    private var status: String { (load?.status ?? "").lowercased() }
    private var arrived: Bool {
        ["at_delivery", "unloading", "delivered", "pod_pending", "paid", "completed"].contains(status)
    }
    private var canArrive: Bool { status == "in_transit" }
    private var loadNumberDisplay: String { load?.loadNumber ?? "-" }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                ADArrivalFanOutHero(
                    arrived: arrived,
                    arrivedTime: arrivedTimeDisplay,
                    appt: apptDisplay,
                    apptDelta: apptDelta,
                    payoutMicro: payoutMicro,
                    shipperInitials: load?.shipper?.initials ?? "-",
                    carrierInitials: load?.catalyst?.initials ?? "-"
                )
                arrivalCard
                receiverCard
                ADLifecycleStripEight(status: load?.status)
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
            HStack {
                Text(arrived ? "At the receiver" : "Approaching receiver")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if arrived {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy))
                        Text("ARRIVED").font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(LinearGradient.diagonal))
                }
            }
            Text(arrived
                 ? "Arrival is on record — your shipper and carrier already see it."
                 : "Confirm arrival when you gate in. Your duty clock flips off driving automatically.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: arrival record rows

    private var arrivalCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("ARRIVAL RECORD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                row("Gate-in", arrived ? "confirmed" : "awaiting your confirm", done: arrived)
                row("Duty status", hos?.status?.replacingOccurrences(of: "_", with: " ") ?? "-",
                    done: ["on_duty", "off_duty"].contains(hos?.status ?? ""))
                row("Drive clock held", hos?.drivingRemaining ?? "-", done: false)
                row("Unloading", status == "unloading" ? "in progress"
                        : (["delivered", "pod_pending", "paid", "completed"].contains(status) ? "complete" : "not started"),
                    done: status == "unloading" || ["delivered", "pod_pending", "paid", "completed"].contains(status))
            }
        }
    }

    private func row(_ label: String, _ value: String, done: Bool) -> some View {
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
            Text(value)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(done ? palette.success : palette.textSecondary)
                .lineLimit(1)
        }
    }

    // MARK: receiver card

    private var receiverCard: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Image(systemName: "building.2.fill")
                        .font(.system(size: 12, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(receiverLine)
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text("Shipper \(load?.shipper?.name ?? "-") · Carrier \(load?.catalyst?.companyName ?? load?.catalyst?.name ?? "-")")
                        .font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(1)
                }
                Spacer()
            }
        }
    }

    private var receiverLine: String {
        let fac = lifecycle?.delivery?.facilityName ?? ""
        let city = lifecycle?.delivery?.city ?? load?.deliveryLocation?.city ?? ""
        if !fac.isEmpty { return "\(fac) · \(city)" }
        if !city.isEmpty { return "Receiver · \(city)" }
        return "Receiver details pending"
    }

    // MARK: actions — adaptive real verbs

    private var actionRibbon: some View {
        HStack(spacing: 8) {
            Button { Task { await firePrimary() } } label: {
                HStack(spacing: 8) {
                    if actionInFlight { ProgressView().tint(.white).scaleEffect(0.8) }
                    Image(systemName: canArrive ? "checkmark.seal.fill" : "shippingbox.fill")
                        .font(.system(size: 13, weight: .heavy))
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
        if actionInFlight { return "Recording…" }
        if canArrive { return "Confirm arrival · gate in" }
        if status == "at_delivery" { return "Start unloading" }
        if status == "unloading" { return "Unloading in progress" }
        if arrived { return "Arrival on record" }
        return "No arrival to record yet"
    }
    private var primaryEnabled: Bool { canArrive || status == "at_delivery" }

    private func firePrimary() async {
        let next = canArrive ? "at_delivery" : (status == "at_delivery" ? "unloading" : nil)
        guard let next else { return }
        actionInFlight = true; actionAck = nil; actionError = nil
        defer { actionInFlight = false }
        struct In: Encodable { let status: String }
        struct Out: Decodable { let success: Bool? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation("drivers.updateLoadStatus", input: In(status: next))
            if resp.success == false {
                actionError = "That didn't record. Nothing changed — check signal and tap again."
            } else {
                actionAck = next == "at_delivery"
                    ? "Arrival recorded · \(loadNumberDisplay). Your shipper and carrier are notified."
                    : "Unloading started on \(loadNumberDisplay)."
            }
        } catch {
            actionError = "That didn't record. Nothing changed — check signal and tap again."
        }
        await refresh()
    }

    // MARK: reads

    private func refresh() async {
        async let a: Void = readLoad()
        async let b: Void = readHos()
        async let c: Void = readLifecycle()
        _ = await (a, b, c)
    }
    private func readLoad() async {
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* "-" */ }
    }
    private func readHos() async {
        do { hos = try await EusoTripAPI.shared.queryNoInput("drivers.getMyHOSStatus") } catch { /* "-" */ }
    }
    private func readLifecycle() async {
        struct In: Encodable { let loadId: String }
        do { lifecycle = try await EusoTripAPI.shared.query("drivers.lifecycle", input: In(loadId: loadId)) } catch { /* "-" */ }
    }

    // MARK: derivations

    private var arrivedTimeDisplay: String {
        guard let d = ADBody.parseISO(lifecycle?.delivery?.arrivedAt) else { return arrived ? "now" : "-" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
    private var apptDisplay: String {
        guard let d = ADBody.parseISO(load?.deliveryDate) else { return "-" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
    private var apptDelta: String? {
        guard let appt = ADBody.parseISO(load?.deliveryDate),
              let at = ADBody.parseISO(lifecycle?.delivery?.arrivedAt) else { return nil }
        let mins = Int(appt.timeIntervalSince(at) / 60)
        if mins >= 0 { return "ON-TIME · \(mins / 60)h \(String(format: "%02d", mins % 60))m early" }
        let late = -mins
        return "LATE · \(late / 60)h \(String(format: "%02d", late % 60))m"
    }
    private var payoutMicro: String {
        guard let r = load?.rate, let n = Double(r), n > 0 else { return "payout pending" }
        let base = n < 1000 ? String(format: "$%.0f", n) : "$\(Int(n).formatted(.number))"
        if let mi = load?.distance, mi > 0 {
            return "\(base) · $\(String(format: "%.2f", n / mi))/mi"
        }
        return base
    }

    fileprivate static func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        return ISO8601DateFormatter().date(from: s)
    }
}

// MARK: - Arrival fan-out hero (palette-token twin of the wireframe hero)

private struct ADArrivalFanOutHero: View {
    let arrived: Bool
    let arrivedTime: String
    let appt: String
    let apptDelta: String?
    let payoutMicro: String
    let shipperInitials: String
    let carrierInitials: String

    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: 18.5).fill(palette.bgCard).padding(1.5)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(arrived ? "ARRIVAL CONFIRMED" : "ARRIVAL PENDING")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(LinearGradient.diagonal)
                    Spacer()
                    Text(payoutMicro)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ARRIVED").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(arrivedTime).font(.system(size: 28, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Rectangle().fill(palette.borderFaint).frame(width: 1, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("APPT WINDOW").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(appt).font(.system(size: 28, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Spacer()
                    if let delta = apptDelta {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy))
                            Text(delta).font(.system(size: 9, weight: .heavy))
                        }
                        .foregroundStyle(delta.hasPrefix("LATE") ? palette.warning : palette.success)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(
                            (delta.hasPrefix("LATE") ? palette.warning : palette.success).opacity(0.14)))
                    }
                }
                .padding(.top, 10)
                Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.vertical, 10)
                Text(arrived ? "ARRIVAL SHARED WITH YOUR CHAIN" : "WHO SEES IT THE MOMENT YOU CONFIRM")
                    .font(.system(size: 8.5, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                HStack(spacing: 7) {
                    chip(initials: shipperInitials, role: "Shipper",
                         status: arrived ? "notified" : "will be notified", live: arrived)
                    chip(initials: carrierInitials, role: "Carrier",
                         status: arrived ? "notified" : "will be notified", live: arrived)
                    chip(initials: "·", role: "Dispatch",
                         status: "board sync", live: false)
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 146)
    }

    private func chip(initials: String, role: String, status: String, live: Bool) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 16, height: 16)
                Text(initials).font(.system(size: 7, weight: .heavy)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(role).font(.system(size: 8, weight: .bold)).foregroundStyle(palette.textPrimary)
                HStack(spacing: 3) {
                    Circle().fill(live ? palette.success : palette.info).frame(width: 4, height: 4)
                    Text(status).font(.system(size: 7)).foregroundStyle(live ? palette.success : palette.info)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 10).fill(palette.bgCardSoft))
    }
}

// MARK: - Lifecycle strip

private struct ADLifecycleStripEight: View {
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

#Preview("147 At Delivery Arrival · Light") {
    DriverAtDeliveryArrivalCelM04Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .environmentObject(DriverNavController())
        .preferredColorScheme(.light)
}

#Preview("147 At Delivery Arrival · Dark") {
    DriverAtDeliveryArrivalCelM04Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .environmentObject(DriverNavController())
        .preferredColorScheme(.dark)
}

#Preview("147 Arrival Fan-Out Hero · Light") {
    ADArrivalFanOutHero(arrived: true, arrivedTime: "12:43", appt: "14:00",
                        apptDelta: "ON-TIME · 1h 17m early", payoutMicro: "$1,489 · $6.08/mi",
                        shipperInitials: "DU", carrierInitials: "CE")
        .environment(\.palette, Theme.light)
        .padding()
        .preferredColorScheme(.light)
}

#Preview("147 Arrival Fan-Out Hero · Dark") {
    ADArrivalFanOutHero(arrived: false, arrivedTime: "-", appt: "-",
                        apptDelta: nil, payoutMicro: "payout pending",
                        shipperInitials: "-", carrierInitials: "-")
        .environment(\.palette, Theme.dark)
        .padding()
        .preferredColorScheme(.dark)
}
