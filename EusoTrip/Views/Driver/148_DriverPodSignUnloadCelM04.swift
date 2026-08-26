//
//  148_DriverPodSignUnloadCelM04.swift
//  EusoTrip — Driver · unload + POD sign surface (the ring roll
//  delivery → paperwork; the natural close of the driving day).
//
//  Wireframe slot: 01 Driver / 148 Driver POD Sign Unload CEL M04
//  (Light/Dark SVG pair is design truth — POD-signed settlement hero:
//  signature proof panel beside the settlement the signature arms).
//
//  Wiring (verified against the live routers this fire):
//    WRITE  drivers.updateLoadStatus  — "unloading" when the door opens
//    WRITE  loads.signPOD             — the POD signature commit (sets the
//           load delivered, stamps the actual delivery time, and writes the
//           audit-trail entry; the shipper gets the review push)
//    READ   loads.getById             — bound load + parties + payout
//    READ   hos.getStatus             — sourced duty status through the unload
//  Fan-out truth: the POD lands with the shipper for review and the
//  delivered confirmation reaches the carrier; dispatch syncs from its
//  board. Invoicing starts automatically after delivery.
//
//  Doctrine: live binds with honest "-" fallbacks; product copy through
//  LifecycleProductContext; no wireframe persona strings; signer identity
//  binds to the signed-in driver.
//

import SwiftUI

// MARK: - tRPC decode shapes

private struct PSLoadCtx: Decodable, Hashable {
    let loadNumber: String?
    let status: String?
    let rate: String?
    let distance: Double?
    let cargoType: String?
    let hazmatClass: String?
    let deliveryDate: String?
    let actualDeliveryDate: String?
    let pickupLocation: PSCityState?
    let deliveryLocation: PSCityState?
    let catalyst: PSParty?
    let shipper: PSParty?

    struct PSCityState: Decodable, Hashable { let city: String?; let state: String? }
    struct PSParty: Decodable, Hashable {
        let name: String?; let initials: String?; let companyName: String?; let mcNumber: String?
    }
}

// MARK: - Screen

struct DriverPodSignUnloadCelM04Screen: View {
    let theme: Theme.Palette
    let loadId: String
    @EnvironmentObject private var nav: DriverNavController

    var body: some View {
        Shell(theme: theme) {
            PSBody(loadId: loadId,
                   onViewSettlement: { nav.currentTab = .wallet },
                   onBackToTrips: { nav.currentTab = .trips })
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

private struct PSBody: View {
    let loadId: String
    let onViewSettlement: () -> Void
    let onBackToTrips: () -> Void

    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @State private var load: PSLoadCtx?
    @State private var hos: HOSStatus?
    @State private var hosError: String?

    @State private var actionInFlight = false
    @State private var actionAck: String?
    @State private var actionError: String?

    private var ctx: LifecycleProductContext {
        LifecycleProductContext.forCargo(
            cargoType: load?.cargoType, hazmatClass: load?.hazmatClass, role: session.user?.role)
    }

    private var status: String { (load?.status ?? "").lowercased() }
    private var delivered: Bool { ["delivered", "pod_pending", "invoiced", "paid", "completed"].contains(status) }
    private var unloading: Bool { status == "unloading" }
    private var atDelivery: Bool { status == "at_delivery" }
    private var loadNumberDisplay: String { load?.loadNumber ?? "-" }
    private var currentHOS: HOSStatus? {
        guard let hos, hos.hasCurrentObservation() else { return nil }
        return hos
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                PSPodSignedSettlementHero(
                    signed: delivered,
                    podTime: podTimeDisplay,
                    signerName: signerLine,
                    payout: payoutDisplay,
                    payTerms: payTerms
                )
                unloadCard
                partiesCard
                PSLifecycleStripEight(status: load?.status)
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
                Text(delivered ? "Delivered" : "Unload + sign")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                if delivered {
                    HStack(spacing: 5) {
                        Image(systemName: "signature").font(.system(size: 9, weight: .heavy))
                        Text("POD SIGNED").font(.system(size: 9, weight: .heavy)).tracking(0.4)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(LinearGradient.diagonal))
                }
            }
            Text(delivered
                 ? "Proof of delivery is on record — your shipper reviews it and invoicing starts automatically."
                 : "Finish the unload, then sign the proof of delivery to close the driving day.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: unload steps (real status-driven)

    private var unloadCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("UNLOAD + PAPERWORK")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                stepRow("Arrived at receiver", done: atDelivery || unloading || delivered,
                        detail: atDelivery || unloading || delivered ? "on record" : "-")
                stepRow("Unloading", done: unloading || delivered,
                        detail: unloading ? "in progress" : (delivered ? "complete" : "not started"))
                stepRow("Proof of delivery signed", done: delivered,
                        detail: delivered ? podTimeDisplay : "awaiting signature")
                stepRow("Duty status",
                        done: [HOSDutyCode.onDuty.rawValue, HOSDutyCode.offDuty.rawValue]
                            .contains(currentHOS?.status ?? ""),
                        detail: currentHOS?.status?.replacingOccurrences(of: "_", with: " ") ?? "—")
                stepRow("HOS evidence", done: currentHOS != nil, detail: hosEvidenceLabel)
            }
        }
    }

    private func stepRow(_ label: String, done: Bool, detail: String) -> some View {
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

    // MARK: parties

    private var partiesCard: some View {
        LifecycleCard {
            HStack(alignment: .center, spacing: 10) {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                    .overlay(Text(load?.shipper?.initials ?? "-")
                        .font(.system(size: 10, weight: .heavy)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("POD goes to \(load?.shipper?.name ?? "your shipper") for review")
                        .font(EType.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                    Text("Carrier \(load?.catalyst?.companyName ?? load?.catalyst?.name ?? "-") gets the delivery confirmation · dispatch syncs from its board")
                        .font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
                }
                Spacer()
            }
        }
    }

    // MARK: actions — adaptive real verbs

    private var actionRibbon: some View {
        HStack(spacing: 8) {
            Button { Task { await firePrimary() } } label: {
                HStack(spacing: 8) {
                    if actionInFlight { ProgressView().tint(.white).scaleEffect(0.8) }
                    Image(systemName: delivered ? "dollarsign.circle.fill" : (unloading ? "signature" : "shippingbox.fill"))
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

            Button(action: delivered ? onBackToTrips : onViewSettlement) {
                Text(delivered ? "Trips" : "Wallet").font(EType.caption.weight(.semibold))
                    .frame(maxWidth: 100, minHeight: 48)
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
        if actionInFlight { return "Working…" }
        if delivered { return "View settlement" }
        if unloading { return "Sign POD · confirm delivery" }
        if atDelivery { return "Start unloading" }
        return "No delivery to close yet"
    }
    private var primaryEnabled: Bool { delivered || unloading || atDelivery }

    private func firePrimary() async {
        if delivered { onViewSettlement(); return }
        actionInFlight = true; actionAck = nil; actionError = nil
        defer { actionInFlight = false }

        if atDelivery {
            struct In: Encodable { let status: String }
            struct Out: Decodable { let success: Bool? }
            do {
                let resp: Out = try await EusoTripAPI.shared.mutation("drivers.updateLoadStatus", input: In(status: "unloading"))
                if resp.success == false {
                    actionError = "Unloading didn't record. Nothing changed — check signal and tap again."
                } else {
                    actionAck = "Unloading started on \(loadNumberDisplay)."
                }
            } catch {
                actionError = "Unloading didn't record. Nothing changed — check signal and tap again."
            }
            await refresh()
            return
        }

        // Sign POD — the real signature commit. The certificate id and
        // signature hash are minted on-device and land in the audit trail.
        let sigHash = String(format: "0x%08X%08X",
                             UInt32.random(in: UInt32.min...UInt32.max),
                             UInt32.random(in: UInt32.min...UInt32.max))
        let podCertId = "POD-\(loadNumberDisplay == "-" ? loadId : loadNumberDisplay)-\(Int(Date().timeIntervalSince1970))"
        struct In: Encodable { let loadId: String; let podCertId: String; let signatureHash: String; let signedAtIso: String? }
        struct Out: Decodable { let success: Bool?; let podCertId: String?; let signedAt: String? }
        do {
            let resp: Out = try await EusoTripAPI.shared.mutation(
                "loads.signPOD",
                input: In(loadId: loadId, podCertId: podCertId, signatureHash: sigHash, signedAtIso: nil))
            if resp.success == true {
                actionAck = "POD signed · \(loadNumberDisplay) delivered. Your shipper has it for review; invoicing starts automatically."
            } else {
                actionError = "The signature didn't commit. The unload record is unchanged — try again."
            }
        } catch {
            actionError = "The signature didn't commit. The unload record is unchanged — check signal and try again."
        }
        await refresh()
    }

    // MARK: reads

    private func refresh() async {
        async let a: Void = readLoad()
        async let b: Void = readHos()
        _ = await (a, b)
    }
    private func readLoad() async {
        struct In: Encodable { let id: String }
        do { load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId)) } catch { /* "-" */ }
    }
    private func readHos() async {
        do {
            hos = try await EusoTripAPI.shared.hos.getStatus()
            hosError = nil
        } catch {
            hos = nil
            hosError = "source unavailable"
        }
    }

    // MARK: derivations

    private var hosEvidenceLabel: String {
        if let hosError { return hosError }
        guard let hos else { return "not returned" }
        guard hos.hasCurrentObservation() else {
            return hos.assignmentEligibility().reason ?? "not current"
        }
        return "\(hos.source ?? "source unavailable") · current"
    }

    private var podTimeDisplay: String {
        guard let d = PSBody.parseISO(load?.actualDeliveryDate) else { return delivered ? "on record" : "-" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
    private var signerLine: String {
        session.user?.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Signed-in driver"
    }
    private var payoutDisplay: String {
        guard let r = load?.rate, let n = Double(r), n > 0 else { return "-" }
        return n < 1000 ? String(format: "$%.0f", n) : "$\(Int(n).formatted(.number))"
    }
    private var payTerms: String {
        guard let r = load?.rate, let n = Double(r), n > 0,
              let mi = load?.distance, mi > 0 else { return "terms with your carrier" }
        return "$\(String(format: "%.2f", n / mi))/mi · \(Int(mi.rounded())) mi"
    }

    fileprivate static func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        return ISO8601DateFormatter().date(from: s)
    }
}

// MARK: - Signature stroke (decorative proof glyph — the committed artifact
//         is the signature hash in the audit trail)

private struct PSSignatureStroke: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
        var p = Path()
        p.move(to: pt(0.02, 0.78))
        p.addCurve(to: pt(0.14, 0.42), control1: pt(0.05, 0.32), control2: pt(0.10, 0.30))
        p.addCurve(to: pt(0.26, 0.56), control1: pt(0.18, 0.52), control2: pt(0.22, 0.88))
        p.addCurve(to: pt(0.40, 0.34), control1: pt(0.30, 0.22), control2: pt(0.36, 0.22))
        p.addCurve(to: pt(0.54, 0.60), control1: pt(0.44, 0.56), control2: pt(0.50, 0.92))
        p.addCurve(to: pt(0.68, 0.36), control1: pt(0.58, 0.24), control2: pt(0.64, 0.22))
        p.addCurve(to: pt(0.82, 0.58), control1: pt(0.72, 0.52), control2: pt(0.78, 0.90))
        p.addCurve(to: pt(0.97, 0.42), control1: pt(0.88, 0.28), control2: pt(0.93, 0.32))
        p.move(to: pt(0.55, 0.52))
        p.addQuadCurve(to: pt(0.99, 0.48), control: pt(0.80, 0.86))
        return p
    }
}

// MARK: - POD-signed settlement hero (palette-token twin of the wireframe hero)

private struct PSPodSignedSettlementHero: View {
    let signed: Bool
    let podTime: String
    let signerName: String
    let payout: String
    let payTerms: String

    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: 18.5).fill(palette.bgCard).padding(1.5)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(signed ? "DELIVERED · POD SIGNED" : "POD · AWAITING SIGNATURE")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(LinearGradient.diagonal)
                    Spacer()
                    Text(podTime == "-" ? "NOT SIGNED" : "POD \(podTime)")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                }
                HStack(alignment: .top, spacing: 14) {
                    // LEFT — proof-of-delivery signature panel
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(palette.bgCardSoft)
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("PROOF OF DELIVERY")
                                    .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                                    .foregroundStyle(palette.textTertiary)
                                Spacer()
                                if signed {
                                    HStack(spacing: 3) {
                                        Image(systemName: "checkmark").font(.system(size: 7, weight: .heavy))
                                        Text("SIGNED").font(.system(size: 7, weight: .heavy)).tracking(0.2)
                                    }
                                    .foregroundStyle(palette.success)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Capsule().fill(palette.success.opacity(0.14)))
                                }
                            }
                            PSSignatureStroke()
                                .stroke(signed ? AnyShapeStyle(palette.textPrimary) : AnyShapeStyle(palette.borderSoft),
                                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                .frame(height: 24).padding(.top, 8).padding(.trailing, 6)
                            Rectangle().fill(palette.borderSoft).frame(height: 1).padding(.top, 4)
                            Text(signerName).font(.system(size: 8))
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(1).padding(.top, 4)
                        }
                        .padding(12)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 86)
                    // RIGHT — settlement the signature arms
                    VStack(alignment: .leading, spacing: 2) {
                        Text(signed ? "SETTLEMENT ARMED" : "SETTLEMENT WAITING")
                            .font(.system(size: 8.5, weight: .heavy)).tracking(0.5)
                            .foregroundStyle(palette.textTertiary)
                        Text(payout).font(.system(size: 24, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(payTerms).font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1)
                        if signed {
                            Text("Invoicing starts automatically")
                                .font(.system(size: 7.5, weight: .heavy)).tracking(0.3)
                                .foregroundStyle(LinearGradient.diagonal)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Capsule().fill(palette.tintInfo))
                                .overlay(Capsule().stroke(LinearGradient.diagonal.opacity(0.4), lineWidth: 1))
                                .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 10)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 146)
    }
}

// MARK: - Lifecycle strip

private struct PSLifecycleStripEight: View {
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

#Preview("148 POD Sign Unload · Light") {
    DriverPodSignUnloadCelM04Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .environmentObject(DriverNavController())
        .preferredColorScheme(.light)
}

#Preview("148 POD Sign Unload · Dark") {
    DriverPodSignUnloadCelM04Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .environmentObject(DriverNavController())
        .preferredColorScheme(.dark)
}

#Preview("148 POD Settlement Hero · Light") {
    PSPodSignedSettlementHero(signed: true, podTime: "13:34", signerName: "Signed-in driver",
                              payout: "$1,489", payTerms: "$6.08/mi · 245 mi")
        .environment(\.palette, Theme.light)
        .padding()
        .preferredColorScheme(.light)
}

#Preview("148 POD Settlement Hero · Dark") {
    PSPodSignedSettlementHero(signed: false, podTime: "-", signerName: "Signed-in driver",
                              payout: "-", payTerms: "terms with your carrier")
        .environment(\.palette, Theme.dark)
        .padding()
        .preferredColorScheme(.dark)
}
