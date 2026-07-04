//
//  520_DispatcherBhAtDeliveryCard.swift
//  EusoTrip — Dispatcher · BH lifecycle 520 · At delivery (detention clock).
//
//  Wireframe slot: 04 Dispatcher / 520 Dispatcher BH At Delivery Card (Light+Dark SVG,
//  golden re-port 2026-06-21 — replaces the stamped Dpch800 duodecet body for this id).
//  Composition (SVG-verbatim): running detention-clock meter hero (dwell readout +
//  accruing-charge box + free-time bar) → HOS / DOCK QUEUE / APPOINTMENT KPI triple →
//  gate check-in checklist → detention exposure ledger → CTA pair (Start unload /
//  Flag detention).
//
//  Wiring manifest (code-traced against frontend/server/routers):
//    READ  loads.getById                              — load + appointment + parties.
//    READ  location.tracking.getLoadTracking          — detention records + geofences + ETA.
//    READ  dispatch.getDriverStatuses                 — driver HOS hours.
//    WRITE dispatch.updateLoadStatus                  — Start unload (status → unloading).
//    READ  detentionAccessorials.calculateDetention   — Flag detention (live exposure calc).
//  Honest gaps (no server proc — rendered as data-absence states, never faked):
//    · dock-assignment + gate-PIN + queue rollup on the dispatch board
//    · facility rate card on the detention record (charge fields bind when posted)
//
//  Dispatcher nav HOME·BOARD·[orb]·COMMS·ME, BOARD active. Light+Dark palette tokens only.
//

import SwiftUI

// MARK: - Screen

struct DispatcherBHAtDelivery520Screen: View {
    let theme: Theme.Palette
    let loadId: String

    var body: some View {
        Shell(theme: theme) {
            BH520Body(loadId: loadId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house",                    isCurrent: false),
                          NavSlot(label: "Board", systemImage: "rectangle.split.3x1.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Comms", systemImage: "bubble.left.and.bubble.right.fill", isCurrent: false),
                           NavSlot(label: "Me",    systemImage: "person",                  isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Body

private struct BH520Body: View {
    let loadId: String

    @Environment(\.palette) private var palette
    @Environment(\.dispatchNavHandler) private var navHandler

    @State private var load: LoadsAPI.LoadDetail?
    @State private var tracking: BH520Tracking?
    @State private var loadFailed = false
    @State private var driverRow: BH520DriverRow?
    @State private var unloadInFlight = false
    @State private var flagInFlight = false
    @State private var actionAck: String?
    @State private var actionError: String?
    @State private var exposure: BH520Exposure?
    @State private var showExposureSheet = false
    @State private var now = Date()

    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s3) {
                eyebrowRow
                titleRow
                Rectangle().fill(palette.iridescentHairline).frame(height: 1)
                heroCard
                kpiTriple
                sectionLabel("GATE CHECK-IN")
                gateChecklist
                sectionLabel("DETENTION EXPOSURE")
                exposureLedger
                if let ack = actionAck {
                    LifecycleCard { Text(ack).font(EType.caption).foregroundStyle(Brand.success) }
                }
                if let err = actionError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                }
                if loadFailed {
                    LifecycleCard(accentWarning: true) {
                        Text("Couldn't reach the board for this load. Everything shown is the last loaded state — pull to refresh.")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
                ctaPair
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await refresh() }
        .refreshable { await refresh() }
        .onReceive(clock) { now = $0 }
        .sheet(isPresented: $showExposureSheet) { BH520ExposureSheet(exposure: exposure) }
    }

    // MARK: Header

    private var eyebrowRow: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("DISPATCHER · BACKHAUL · AT DELIVERY")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Spacer()
            Text("\(load?.loadNumber ?? "—") · \(load?.rateDisplay ?? "—")")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary).monospacedDigit()
        }
    }

    private var titleRow: some View {
        HStack(spacing: Space.s3) {
            Button { navHandler?("board") } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(palette.textPrimary)
            }
            .buttonStyle(.plain)
            Text("At delivery").font(.system(size: 26, weight: .bold)).foregroundStyle(palette.textPrimary)
            Spacer()
            Menu {
                Button("Refresh") { Task { await refresh() } }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: Hero — detention meter

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(insideGeofence ? Brand.warning : Brand.neutral).frame(width: 6, height: 6)
                    Text(insideGeofence ? "INSIDE GEOFENCE · CLOCK RUNNING" : "NO GATE-IN RECORDED")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(insideGeofence ? Brand.warning : palette.textTertiary)
                }
                Spacer()
                Text(facilityLabel)
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            if let rec = activeDetention {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dwellText(rec))
                            .font(.system(size: 40, weight: .heavy).monospacedDigit())
                            .foregroundStyle(palette.textPrimary)
                        Text(freeCaption(rec))
                            .font(.caption2).foregroundStyle(palette.textTertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(chargeText(rec))
                            .font(.system(size: 20, weight: .heavy).monospacedDigit())
                            .foregroundStyle(rec.isBillable == true ? Brand.danger : Brand.success)
                        Text(rec.isBillable == true ? "accruing · billable" : "accruing · free")
                            .font(.caption2).foregroundStyle(palette.textTertiary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(rec.isBillable == true ? palette.tintDanger : palette.tintSuccess))
                }
                freeTimeBar(rec)
                HStack {
                    Text(freeLeftLine(rec)).font(EType.mono(.micro))
                        .foregroundStyle(rec.isBillable == true ? Brand.danger : Brand.success)
                    Spacer()
                    Text(billableAtLine(rec)).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
                if let enter = bh520ISODate(rec.enterAt) {
                    Text("Auto-clock armed on geofence enter · \(clockText(enter))")
                        .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
                }
            } else {
                Text("The detention clock starts the moment the truck crosses the receiver geofence. No gate-in has been recorded for this load yet.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .padding(.vertical, Space.s2)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.5), Brand.magenta.opacity(0.5)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
    }

    private func freeTimeBar(_ rec: BH520Tracking.Detention) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.borderSoft).frame(height: 6)
                if let frac = dwellFraction(rec) {
                    Capsule()
                        .fill(rec.isBillable == true ? AnyShapeStyle(Brand.danger) : AnyShapeStyle(LinearGradient.primary))
                        .frame(width: max(8, geo.size.width * frac), height: 6)
                    Circle().fill(palette.textPrimary).frame(width: 10, height: 10)
                        .offset(x: max(0, geo.size.width * frac - 5))
                }
            }
        }
        .frame(height: 12)
    }

    // MARK: KPI triple — HOS / DOCK QUEUE / APPOINTMENT

    private var kpiTriple: some View {
        HStack(spacing: Space.s2) {
            BH520Kpi(label: "HOS LEFT",
                     value: hosText,
                     sub: hosText == "—" ? "not on the live driver board" : "drive window",
                     tint: nil)
            BH520Kpi(label: "DOCK QUEUE",
                     value: "—",
                     sub: "queue not shared to this board",
                     tint: nil)
            BH520Kpi(label: "APPOINTMENT",
                     value: appointmentStateText,
                     sub: appointmentSubText,
                     tint: appointmentTint)
        }
    }

    // MARK: Gate checklist

    private var gateChecklist: some View {
        LifecycleCard {
            VStack(spacing: 0) {
                BH520CheckRow(state: activeDetention != nil ? .done : .pending,
                              title: "Geofence enter · auto",
                              sub: activeDetention.flatMap { rec in bh520ISODate(rec.enterAt).map { "\(clockText($0)) · detention clock started" } }
                                   ?? "arms on the receiver geofence",
                              trail: activeDetention != nil ? "done" : "pending")
                Divider().overlay(palette.borderFaint)
                BH520CheckRow(state: .pending,
                              title: "Gate-in acknowledgment",
                              sub: "gate acknowledgments aren't shared to this board for this facility",
                              trail: "—")
                Divider().overlay(palette.borderFaint)
                BH520CheckRow(state: isUnloadingStage ? .active : .pending,
                              title: "Dock assigned",
                              sub: isUnloadingStage ? "unload is under way" : "dock assignments aren't shared to this board for this facility",
                              trail: isUnloadingStage ? "active" : "—")
            }
        }
    }

    // MARK: Exposure ledger

    private var exposureLedger: some View {
        LifecycleCard {
            HStack {
                BH520LedgerCell(label: "Free time", value: activeDetention?.freeTimeMinutes.map { "\($0) min" } ?? "—")
                BH520LedgerCell(label: "Billable", value: activeDetention?.detentionMinutes.map { "\($0) min" } ?? "0 min")
                BH520LedgerCell(label: "Charge", value: activeDetention?.detentionCharge.map { String(format: "$%.0f", $0) } ?? "$0")
                BH520LedgerCell(label: "Status", value: activeDetention?.isBillable == true ? "billable" : "free")
            }
        }
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button { Task { await startUnload() } } label: {
                HStack(spacing: 6) {
                    if unloadInFlight { ProgressView().tint(.white).scaleEffect(0.8) }
                    else { Image(systemName: "shippingbox").font(.system(size: 13, weight: .bold)) }
                    Text(unloadInFlight ? "Posting…" : "Start unload").font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white)
                .background(LinearGradient.diagonal)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(unloadInFlight)

            Button { Task { await flagDetention() } } label: {
                HStack(spacing: 6) {
                    if flagInFlight { ProgressView().scaleEffect(0.8) }
                    Text(flagInFlight ? "Calculating…" : "Flag detention").font(EType.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(Brand.danger)
                .background(Capsule().fill(palette.bgCard))
                .overlay(Capsule().strokeBorder(Brand.danger.opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(flagInFlight)
        }
        .padding(.top, Space.s2)
    }

    // MARK: Derived display

    private var activeDetention: BH520Tracking.Detention? {
        (tracking?.detention ?? []).last(where: { $0.exitAt == nil }) ?? (tracking?.detention ?? []).last
    }

    private var insideGeofence: Bool {
        (tracking?.detention ?? []).contains(where: { $0.enterAt != nil && $0.exitAt == nil })
    }

    private var isUnloadingStage: Bool {
        ["unloading", "unloading_exception", "unloaded"].contains(load?.status ?? "")
    }

    private var facilityLabel: String {
        let c = load?.deliveryLocation?.city ?? "receiver"
        if let s = load?.deliveryLocation?.state { return "\(c.uppercased()), \(s.uppercased())" }
        return c.uppercased()
    }

    private func dwellMinutes(_ rec: BH520Tracking.Detention) -> Int? {
        if rec.exitAt == nil, let enter = bh520ISODate(rec.enterAt) {
            return max(0, Int(now.timeIntervalSince(enter) / 60))
        }
        return rec.totalDwellMinutes
    }

    private func dwellText(_ rec: BH520Tracking.Detention) -> String {
        guard let m = dwellMinutes(rec) else { return "—" }
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    private func freeCaption(_ rec: BH520Tracking.Detention) -> String {
        guard let free = rec.freeTimeMinutes else { return "DWELL · free time not on this record" }
        return "DWELL · of \(String(format: "%d:%02d", free / 60, free % 60)) free time"
    }

    private func chargeText(_ rec: BH520Tracking.Detention) -> String {
        String(format: "$%.0f", rec.detentionCharge ?? 0)
    }

    private func dwellFraction(_ rec: BH520Tracking.Detention) -> CGFloat? {
        guard let m = dwellMinutes(rec), let free = rec.freeTimeMinutes, free > 0 else { return nil }
        return CGFloat(min(1.0, Double(m) / Double(free)))
    }

    private func freeLeftLine(_ rec: BH520Tracking.Detention) -> String {
        guard let m = dwellMinutes(rec), let free = rec.freeTimeMinutes else { return "free time not on this record" }
        let left = free - m
        if left >= 0 { return "FREE · \(left) min left" }
        return "BILLABLE · \(-left) min over"
    }

    private func billableAtLine(_ rec: BH520Tracking.Detention) -> String {
        guard let enter = bh520ISODate(rec.enterAt), let free = rec.freeTimeMinutes else { return "" }
        let at = enter.addingTimeInterval(Double(free) * 60)
        return "billable at \(clockText(at))"
    }

    private var hosText: String {
        guard let h = driverRow?.hoursRemaining else { return "—" }
        let whole = Int(h)
        let mins = Int((h - Double(whole)) * 60)
        return "\(whole)h \(String(format: "%02d", mins))"
    }

    private var appointmentOnTime: Bool? {
        guard let w = bh520ISODate(load?.deliveryDate) else { return nil }
        if let rec = activeDetention, let enter = bh520ISODate(rec.enterAt) { return enter <= w }
        return nil
    }

    private var appointmentStateText: String {
        switch appointmentOnTime {
        case true: return "ON TIME"
        case false: return "LATE"
        default: return "—"
        }
    }

    private var appointmentSubText: String {
        guard let w = bh520ISODate(load?.deliveryDate) else { return "no appointment on this record" }
        return "window \(clockText(w))"
    }

    private var appointmentTint: Color? {
        switch appointmentOnTime {
        case true: return Brand.success
        case false: return Brand.danger
        default: return nil
        }
    }

    private func clockText(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: d)
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            .padding(.top, Space.s1)
    }

    // MARK: Data

    private func refresh() async {
        struct In: Encodable { let id: String }
        do {
            load = try await EusoTripAPI.shared.query("loads.getById", input: In(id: loadId))
            loadFailed = false
        } catch { loadFailed = load == nil }
        await fetchTracking()
        await fetchDriverRow()
        now = Date()
    }

    private func fetchTracking() async {
        struct In: Encodable { let loadId: Int }
        guard let numeric = Int((load?.id ?? loadId).replacingOccurrences(of: "load_", with: "")) else { return }
        do {
            tracking = try await EusoTripAPI.shared.query("location.tracking.getLoadTracking", input: In(loadId: numeric))
        } catch { tracking = nil }
    }

    private func fetchDriverRow() async {
        struct In: Encodable { let limit: Int }
        do {
            let rows: [BH520DriverRow] = try await EusoTripAPI.shared.query("dispatch.getDriverStatuses", input: In(limit: 50))
            let ln = load?.loadNumber
            let dn = load?.driver?.name
            driverRow = rows.first(where: { $0.load != nil && $0.load == ln })
                ?? rows.first(where: { dn != nil && $0.name == dn })
        } catch { driverRow = nil }
    }

    private func startUnload() async {
        guard !unloadInFlight else { return }
        unloadInFlight = true; actionAck = nil; actionError = nil
        defer { unloadInFlight = false }
        struct In: Encodable { let loadId: String; let status: String }
        struct Out: Decodable { let success: Bool?; let newStatus: String? }
        do {
            let out: Out = try await EusoTripAPI.shared.mutation("dispatch.updateLoadStatus",
                                                                 input: In(loadId: loadId, status: "unloading"))
            if out.success == true {
                actionAck = "Unload is live on the board — the stage advanced to unloading."
                await refresh()
            } else {
                actionError = "The stage didn't advance. The board still shows the last saved stage — try again."
            }
        } catch {
            actionError = "The stage didn't post. The board still shows the last saved stage — check the connection and try again."
        }
    }

    private func flagDetention() async {
        guard !flagInFlight else { return }
        flagInFlight = true; actionAck = nil; actionError = nil
        defer { flagInFlight = false }
        guard let rec = activeDetention, let enter = rec.enterAt else {
            actionError = "No gate-in is recorded for this load, so there's no detention window to flag yet."
            return
        }
        struct In: Encodable {
            let arrivalTime: String
            let departureTime: String?
            let freeTimeMinutes: Int
            let cargoType: String
        }
        do {
            let out: BH520Exposure = try await EusoTripAPI.shared.query(
                "detentionAccessorials.calculateDetention",
                input: In(arrivalTime: enter,
                          departureTime: rec.exitAt,
                          freeTimeMinutes: rec.freeTimeMinutes ?? 120,
                          cargoType: load?.cargoType ?? "general"))
            exposure = out
            showExposureSheet = true
        } catch {
            actionError = "The exposure calculation didn't run. The dwell clock above stays live — try again."
        }
    }
}

// MARK: - Exposure sheet

private struct BH520ExposureSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let exposure: BH520Exposure?

    var body: some View {
        ZStack {
            palette.bgPrimary.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s3) {
                    HStack {
                        Text("Detention exposure").font(EType.h2).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(palette.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    if let e = exposure {
                        LifecycleCard {
                            row("Total dwell", e.totalMinutes.map { "\($0) min" } ?? "—")
                            row("Free time", e.freeTimeMinutes.map { "\($0) min" } ?? "—")
                            row("Billable", e.billableMinutes.map { "\($0) min" } ?? "—")
                            row("Total charge", e.totalCharge.map { String(format: "$%.2f", $0) } ?? "—")
                        }
                        if let tiers = e.tierBreakdown, !tiers.isEmpty {
                            LifecycleCard {
                                ForEach(Array(tiers.enumerated()), id: \.offset) { _, t in
                                    row(t.tier ?? "Tier",
                                        String(format: "%.1fh @ $%.0f/hr → $%.2f", t.hours ?? 0, t.rate ?? 0, t.subtotal ?? 0))
                                }
                            }
                        } else {
                            LifecycleCard {
                                Text("Nothing is billable yet — the dwell is still inside the free window.")
                                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                            }
                        }
                    }
                    Spacer(minLength: 24)
                }
                .padding(Space.s4)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(EType.caption).foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value).font(EType.mono(.caption)).foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Small primitives

private struct BH520Kpi: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    let sub: String
    let tint: Color?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 20, weight: .heavy).monospacedDigit())
                .foregroundStyle(tint ?? palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
    }
}

private struct BH520CheckRow: View {
    @Environment(\.palette) private var palette
    enum RowState { case done, active, pending }
    let state: RowState
    let title: String
    let sub: String
    let trail: String

    var body: some View {
        HStack(alignment: .center, spacing: Space.s2) {
            Group {
                switch state {
                case .done:
                    Circle().fill(Brand.success).frame(width: 20, height: 20)
                        .overlay(Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white))
                case .active:
                    Circle().strokeBorder(LinearGradient.diagonal, lineWidth: 2).frame(width: 20, height: 20)
                        .overlay(Circle().fill(LinearGradient.diagonal).frame(width: 8, height: 8))
                case .pending:
                    Circle().strokeBorder(palette.borderStrong, lineWidth: 1.5).frame(width: 20, height: 20)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(EType.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                Text(sub).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            Text(trail)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(state == .done ? Brand.success : (state == .active ? Brand.info : palette.textTertiary))
        }
        .padding(.vertical, 8)
    }
}

private struct BH520LedgerCell: View {
    @Environment(\.palette) private var palette
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(palette.textTertiary)
            Text(value).font(EType.mono(.caption)).foregroundStyle(palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - File-local decode + helpers

private struct BH520Tracking: Decodable {
    struct Geofence: Decodable { let id: Int?; let name: String?; let type: String? }
    struct Detention: Decodable {
        let id: Int?
        let locationType: String?
        let enterAt: String?
        let exitAt: String?
        let totalDwellMinutes: Int?
        let detentionMinutes: Int?
        let detentionCharge: Double?
        let isBillable: Bool?
        let freeTimeMinutes: Int?
    }
    struct Eta: Decodable { let predictedEta: String?; let remainingMiles: Double?; let remainingMinutes: Int? }
    let loadId: Int?
    let status: String?
    let geofences: [Geofence]?
    let detention: [Detention]?
    let eta: Eta?
}

private struct BH520Exposure: Decodable {
    struct Tier: Decodable { let tier: String?; let hours: Double?; let rate: Double?; let subtotal: Double? }
    let arrivalTime: String?
    let departureTime: String?
    let totalMinutes: Int?
    let freeTimeMinutes: Int?
    let billableMinutes: Int?
    let billableHours: Double?
    let totalCharge: Double?
    let tierBreakdown: [Tier]?
}

private struct BH520DriverRow: Decodable {
    let id: String?
    let name: String?
    let status: String?
    let load: String?
    let hoursRemaining: Double?
}

private func bh520ISODate(_ s: String?) -> Date? {
    guard let s else { return nil }
    let f1 = ISO8601DateFormatter()
    f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f1.date(from: s) { return d }
    return ISO8601DateFormatter().date(from: s)
}

// MARK: - Previews

#Preview("520 At Delivery · Dark") {
    DispatcherBHAtDelivery520Screen(theme: Theme.dark, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("520 At Delivery · Light") {
    DispatcherBHAtDelivery520Screen(theme: Theme.light, loadId: "0")
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
