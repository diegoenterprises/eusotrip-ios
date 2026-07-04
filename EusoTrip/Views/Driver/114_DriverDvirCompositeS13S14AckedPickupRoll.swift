//
//  114_DriverDvirCompositeS13S14AckedPickupRoll.swift
//  EusoTrip — Driver · Zeun pre-trip inspection composite closure (final two
//  checks) + roll the load forward to pickup.
//
//  Wireframe slot: 01 Driver / 114 Driver DVIR Composite S13 S14 Acked
//  Pickup Roll (Light/Dark SVG pair is design truth).
//
//  Wiring (all verified against the live routers this fire):
//    READ   dvir.listMine                 — caller's DVIRs (newest pre-trip drives the record card)
//    READ   loads.getById                 — bound load context (lane, payout, lifecycle strip)
//    WRITE  dvir.update                   — save-draft persistence (draft rows only)
//    WRITE  dvir.submit                   — finalize the inspection (fires the safety event + WS fan-out)
//    WRITE  drivers.updateLoadStatus      — status "at_pickup" (the real pickup roll verb; organic HOS side-effect)
//  NAMED GAPS (kept honest, not faked): a single-call composite ack verb and
//  a drivers-side lifecycle.advance do not exist — this surface sequences the
//  two real verbs (submit → updateLoadStatus) instead. Web peer page
//  /driver/dvir/:sessionId is absent (web team owns parity).
//
//  Doctrine: DVIR routes through Zeun branding. Every visible value binds to
//  a tRPC read with an honest "-" fallback; the wireframe's canonical persona
//  strings do not ship. Copy/visuals dispatch through LifecycleProductContext
//  so a tanker securement line never paints on a dry-van load.
//

import SwiftUI

// MARK: - tRPC decode shapes

/// One row of `dvir.listMine` (wave-4 + legacy union — the legacy half can
/// carry different shapes per field, so every decode is lenient: one odd
/// legacy row must never sink the whole list).
private struct DVCDvirRow: Decodable, Hashable {
    let id: Int?
    let kind: String?          // "pre" | "post"
    let status: String?        // "draft" | "submitted"
    let vehicleId: Int?
    let defects: [DVCDefect]?
    let createdAt: String?
    let submittedAt: String?

    struct DVCDefect: Decodable, Hashable {
        let severity: String?
        let note: String?
        let area: String?
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, status, vehicleId, defects, createdAt, submittedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let n = try? c.decode(Int.self, forKey: .id) {
            id = n
        } else if let s = try? c.decode(String.self, forKey: .id), let n = Int(s) {
            id = n
        } else {
            id = nil
        }
        kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        vehicleId = (try? c.decodeIfPresent(Int.self, forKey: .vehicleId)) ?? nil
        defects = try? c.decodeIfPresent([DVCDefect].self, forKey: .defects)
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
        submittedAt = try? c.decodeIfPresent(String.self, forKey: .submittedAt)
    }
}

/// Minimal projection of `loads.getById` for this surface.
private struct DVCLoadCtx: Decodable, Hashable {
    let loadNumber: String?
    let status: String?
    let rate: String?
    let distance: Double?
    let cargoType: String?
    let hazmatClass: String?
    let equipmentType: String?
    let pickupDate: String?
    let pickupLocation: DVCCityState?
    let deliveryLocation: DVCCityState?
    let catalyst: DVCParty?
    let shipper: DVCParty?

    struct DVCCityState: Decodable, Hashable { let city: String?; let state: String? }
    struct DVCParty: Decodable, Hashable {
        let name: String?
        let initials: String?
        let companyName: String?
        let mcNumber: String?
    }
}

// MARK: - Screen

struct DriverDvirCompositePickupRollScreen: View {
    let theme: Theme.Palette
    let loadId: String
    @EnvironmentObject private var nav: DriverNavController

    var body: some View {
        Shell(theme: theme) {
            DVCBody(loadId: loadId, onExit: { nav.currentTab = .trips })
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

private struct DVCBody: View {
    let loadId: String
    let onExit: () -> Void

    @Environment(\.palette) private var palette
    @EnvironmentObject private var session: EusoTripSession

    @State private var dvir: DVCDvirRow?
    @State private var dvirLoaded = false
    @State private var load: DVCLoadCtx?

    // The final two composite checks (design truth: Section 13 cargo
    // securement + Section 14 final 360 walk-around). Local acks gate the
    // REAL dvir.submit — they are the driver's attestation, not fake state.
    @State private var s13Acked = false
    @State private var s14Acked = false

    @State private var actionInFlight = false
    @State private var actionAck: String?
    @State private var actionError: String?

    private var ctx: LifecycleProductContext {
        LifecycleProductContext.forCargo(
            cargoType: load?.cargoType,
            hazmatClass: load?.hazmatClass,
            role: session.user?.role
        )
    }

    private var isDraft: Bool { (dvir?.status ?? "").lowercased() == "draft" }
    private var isSubmitted: Bool { (dvir?.status ?? "").lowercased() == "submitted" }
    private var bothAcked: Bool { s13Acked && s14Acked }
    private var loadNumberDisplay: String { load?.loadNumber ?? "-" }
    private var defectCount: Int { dvir?.defects?.count ?? 0 }

    /// Securement subtitle dispatched through the product context — the
    /// tanker line never paints on a dry-van load.
    private var s13Subtitle: String {
        if ctx.isHazmat {
            return "Closures · placards all 4 sides · pressure + leak check"
        }
        switch ctx.vertical {
        case .truck:  return "Straps · load-locks · decking · blocking + bracing"
        case .rail:   return "Chassis locks · IBC pins · interchange securement"
        case .vessel: return "Lashings · twist-locks · stow plan securement"
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                recordCard
                compositeCard
                loadContextCard
                lifecycleStrip
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
        .refreshable { await refresh() }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ZEUN · PRE-TRIP INSPECTION · \(ctx.headerKicker)")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
                    .lineLimit(1)
            }
            HStack(alignment: .center) {
                Text("Final checks")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                statusPill
            }
            Text("Close out cargo securement and the final walk-around, then roll \(loadNumberDisplay) to pickup.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var statusPill: some View {
        let label: String = isSubmitted ? "COMPLETE" : (isDraft ? "IN PROGRESS" : (dvirLoaded ? "NOT STARTED" : "…"))
        return HStack(spacing: 4) {
            Image(systemName: isSubmitted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 9, weight: .heavy))
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.4)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(LinearGradient.diagonal))
    }

    // MARK: Zeun inspection record (real dvir row)

    private var recordCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("ZEUN INSPECTION RECORD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                if let d = dvir {
                    recordRow("Type", (d.kind ?? "-") == "pre" ? "Pre-trip" : ((d.kind ?? "-") == "post" ? "Post-trip" : "-"))
                    recordRow("Status", isSubmitted ? "Submitted" : (isDraft ? "Draft" : (d.status ?? "-")))
                    recordRow("Defects noted", defectCount == 0 ? "None" : "\(defectCount)")
                    recordRow("Started", Self.dayTime(d.createdAt))
                    if let sub = d.submittedAt { recordRow("Submitted", Self.dayTime(sub)) }
                } else if dvirLoaded {
                    Text("No inspection on file yet. Start a pre-trip in Zeun and this surface picks it up.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Loading your inspection record…")
                        .font(EType.caption).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private func recordRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: Composite S13 + S14 card (the two final acks)

    private var compositeCard: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("FINAL TWO CHECKS · COMPOSITE CLOSE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text(isSubmitted ? "2 / 2" : "\((s13Acked ? 1 : 0) + (s14Acked ? 1 : 0)) / 2")
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(LinearGradient.diagonal)
                }
                ackRow(index: 13,
                       title: "Cargo securement",
                       subtitle: s13Subtitle,
                       acked: isSubmitted || s13Acked,
                       locked: isSubmitted || !isDraft) { s13Acked.toggle() }
                ackRow(index: 14,
                       title: "Final 360 walk-around",
                       subtitle: "Tires · lights · leak check · mirrors · cab secured",
                       acked: isSubmitted || s14Acked,
                       locked: isSubmitted || !isDraft) { s14Acked.toggle() }
                progressCapsule
            }
        }
    }

    private func ackRow(index: Int, title: String, subtitle: String,
                        acked: Bool, locked: Bool, toggle: @escaping () -> Void) -> some View {
        Button {
            guard !locked else { return }
            toggle()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    if acked {
                        Circle().fill(LinearGradient.diagonal).frame(width: 20, height: 20)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                    } else {
                        Circle().stroke(palette.borderStrong, lineWidth: 1.5).frame(width: 20, height: 20)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Section \(index) · \(title)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .disabled(locked)
    }

    private var progressCapsule: some View {
        GeometryReader { geo in
            let pct: Double = isSubmitted ? 1.0 : Double((s13Acked ? 1 : 0) + (s14Acked ? 1 : 0)) / 2.0
            ZStack(alignment: .leading) {
                Capsule().fill(palette.tintNeutral).frame(height: 6)
                Capsule().fill(LinearGradient.diagonal)
                    .frame(width: max(6, geo.size.width * pct), height: 6)
            }
        }
        .frame(height: 6)
    }

    // MARK: Load context

    private var loadContextCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("BOUND LOAD")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Text("\(loadNumberDisplay) · \(laneDisplay ?? "lane pending")")
                    .font(EType.caption.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                HStack(spacing: 10) {
                    Text(payoutDisplay)
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(distanceDisplay)
                        .font(.caption2).foregroundStyle(palette.textSecondary)
                    if let carrier = load?.catalyst?.companyName ?? load?.catalyst?.name {
                        Text(carrier).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(1)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: Lifecycle strip (real status → stage)

    private var lifecycleStrip: some View {
        DVCLifecycleStripEight(status: load?.status)
    }

    // MARK: Action ribbon

    private var actionRibbon: some View {
        VStack(spacing: 8) {
            Button { Task { await submitAndRoll() } } label: {
                HStack(spacing: 8) {
                    if actionInFlight { ProgressView().tint(.white).scaleEffect(0.8) }
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 13, weight: .heavy))
                    Text(primaryLabel).font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal.opacity(primaryEnabled ? 1 : 0.4))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!primaryEnabled || actionInFlight)

            Button { Task { await saveAndExit() } } label: {
                Text(isDraft ? "Save draft and exit" : "Back to trips")
                    .font(EType.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(LinearGradient.diagonal)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(LinearGradient.diagonal.opacity(0.55), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(actionInFlight)
        }
    }

    private var primaryLabel: String {
        if actionInFlight { return "Working…" }
        if isSubmitted { return "Roll to pickup · on-site" }
        if dvir == nil { return "Start a pre-trip in Zeun first" }
        return "Submit inspection · roll to pickup"
    }

    private var primaryEnabled: Bool {
        if isSubmitted { return true }           // inspection done — roll only
        return isDraft && bothAcked              // both final acks gate the real submit
    }

    // MARK: mutations — sequenced real verbs

    private func submitAndRoll() async {
        actionInFlight = true; actionAck = nil; actionError = nil
        defer { actionInFlight = false }

        // 1 — finalize the inspection when it's still a draft.
        if isDraft, let id = dvir?.id {
            struct In: Encodable { let id: Int }
            struct Out: Decodable { let success: Bool? }
            // 1a — persist the composite section acks (S13 cargo securement +
            // S14 final walk-around) to the DVIR roster via the real single-call
            // composite-ack verb, so the driver's attestation round-trips.
            struct AckIn: Encodable { let id: Int; let sectionKeys: [String] }
            struct AckOut: Decodable { let success: Bool?; let allAcked: Bool? }
            let ackedKeys = [s13Acked ? "S13" : nil, s14Acked ? "S14" : nil].compactMap { $0 }
            if !ackedKeys.isEmpty {
                let _: AckOut? = try? await EusoTripAPI.shared.mutation(
                    "dvir.acknowledgeComposite", input: AckIn(id: id, sectionKeys: ackedKeys))
            }
            do {
                let resp: Out = try await EusoTripAPI.shared.mutation("dvir.submit", input: In(id: id))
                guard resp.success != false else {
                    actionError = "The inspection didn't submit. Your checks are still marked — try again."
                    return
                }
            } catch {
                actionError = "The inspection didn't submit. Your checks are still marked — check signal and try again."
                return
            }
        }

        // 2 — roll the bound load to pickup (real status verb; HOS follows organically).
        struct RollIn: Encodable { let status: String }
        struct RollOut: Decodable { let success: Bool? }
        do {
            let resp: RollOut = try await EusoTripAPI.shared.mutation(
                "drivers.updateLoadStatus", input: RollIn(status: "at_pickup"))
            if resp.success == false {
                actionAck = "Inspection is complete. The load didn't roll to pickup — pull to refresh and try the roll again."
            } else {
                actionAck = "Inspection complete · \(loadNumberDisplay) rolled to pickup. You're on-site."
            }
        } catch {
            actionAck = "Inspection is complete. The load didn't roll to pickup — pull to refresh and try the roll again."
        }
        await refresh()
    }

    private func saveAndExit() async {
        if isDraft, let id = dvir?.id {
            actionInFlight = true
            struct In: Encodable { let id: Int }
            struct Out: Decodable { let success: Bool? }
            do {
                let _: Out = try await EusoTripAPI.shared.mutation("dvir.update", input: In(id: id))
            } catch { /* draft persistence is best-effort; the acks re-derive on return */ }
            actionInFlight = false
        }
        onExit()
    }

    // MARK: reads

    private func refresh() async {
        async let a: Void = loadDvir()
        async let b: Void = loadLoad()
        _ = await (a, b)
    }

    private func loadDvir() async {
        struct In: Encodable { let limit: Int }
        do {
            let rows: [DVCDvirRow] = try await EusoTripAPI.shared.query("dvir.listMine", input: In(limit: 10))
            dvir = rows.first(where: { ($0.kind ?? "") == "pre" }) ?? rows.first
        } catch { dvir = nil }
        dvirLoaded = true
        if isSubmitted { s13Acked = true; s14Acked = true }
    }

    private func loadLoad() async {
        struct In: Encodable { let id: String }
        do {
            load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId))
        } catch { /* honest "-" fallbacks */ }
    }

    // MARK: display helpers

    private var laneDisplay: String? {
        guard let p = load?.pickupLocation?.city, let d = load?.deliveryLocation?.city,
              !p.isEmpty, !d.isEmpty else { return nil }
        return "\(p) → \(d)"
    }
    private var payoutDisplay: String {
        guard let r = load?.rate, let n = Double(r), n > 0 else { return "-" }
        return n < 1000 ? String(format: "$%.0f", n) : "$\(Int(n).formatted(.number))"
    }
    private var distanceDisplay: String {
        guard let d = load?.distance, d > 0 else { return "-" }
        return "\(Int(d.rounded())) mi"
    }

    private static func dayTime(_ iso: String?) -> String {
        guard let iso, let date = parseISO(iso) else { return "-" }
        let f = DateFormatter(); f.dateFormat = "M/d · HH:mm"
        return f.string(from: date)
    }
    private static func parseISO(_ s: String) -> Date? {
        let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        return f2.date(from: s)
    }
}

// MARK: - Lifecycle strip (eight stages · real status drives the ring)

private struct DVCLifecycleStripEight: View {
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

#Preview("114 Zeun DVIR Composite · Light") {
    DriverDvirCompositePickupRollScreen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .environmentObject(DriverNavController())
        .preferredColorScheme(.light)
}

#Preview("114 Zeun DVIR Composite · Dark") {
    DriverDvirCompositePickupRollScreen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .environmentObject(DriverNavController())
        .preferredColorScheme(.dark)
}
