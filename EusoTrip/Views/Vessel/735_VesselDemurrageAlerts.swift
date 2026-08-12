//
//  735_VesselDemurrageAlerts.swift
//  EusoTrip — Vessel Operator · Demurrage & Detention Watch.
//
//  Verbatim port of "735 Vessel Demurrage Alerts.svg" (Light + Dark) — reconstructed to a LIVE
//  D&D-watch archetype: a climbing exposure meter, an LFD arc-clock gauge for the worst container,
//  and a per-container free-time-vs-per-diem ledger. The exposure total, the arc gauge and the ESang
//  card are THREE FACES OF ONE LOAD — bound to a single live read, never three static values. Nav:
//  HOME · SHIPMENTS · [orb] · COMPLIANCE(current) · ME — the Shell + BottomNav wrapper the registered
//  vessel siblings (757/664/680) ship; D&D charges live in the COMPLIANCE domain so that slot is inked.
//
//  ROLE: VESSEL_OPERATOR (canonical header "VESSEL OPERATOR · D&D WATCH").
//
//  Data / wiring (endpoint confirmed via EUSOTRIP_PLATFORM MCP this fire):
//    demurrageAlerts.dashboard (EXISTS frontend/server/routers/demurrageAlerts.ts:19 · vesselProcedure,
//      NO input · returns {summary:{totalAccruing,criticalCount,warningCount,safeCount,
//      totalChargesAccruing,projected7dCharges}, critical:[{containerId,chargeType,freeTimeDays,
//      chargeableDays,ratePerDay,totalCharge,startDate,endDate,status}], warning:[…]}). The operator-wide
//      demurrage book scanned for free-time expiry — totalChargesAccruing feeds the exposure hero, the
//      critical/warning records feed the container watch ledger, the worst container's free-time
//      consumption drives the LFD arc gauge. Called via queryNoInput (the procedure has no .input(),
//      same shape sibling 001 uses for the demurrage domain). Empty ledger → honest empty state, never
//      a fabricated row or a frozen number.
//    CTA "Book pickup appt" -> vesselDrayage.bookAppointment (EXISTS server/routers/vesselDrayage.ts)
//      persists a terminal appointment for the selected live vessel_demurrage row, writes the audit row
//      and fan-outs the terminal appointment websocket event.
//    CTA "Dispute" -> vesselDrayage.disputeDemurrageCharge (EXISTS server/routers/vesselDrayage.ts)
//      marks the vessel_demurrage row disputed, opens the shared dispute thread and audits/fan-outs it.
//
//  All file-scoped helpers are suffixed 735 (DDState735 / WatchBox735 / DemurrageWatchModel735 /
//  LFDGauge735) so they never collide with another screen's private symbols. palette.card / orbState
//  .alert / StatusPill(tone:) from the canonical port do not resolve in-module — re-bound to
//  palette.bgCard / .idle / StatusPill(kind:) respectively.
//

import Foundation
import SwiftUI

private enum DDState735 { case atRisk, accruing, free
    var pill: String { self == .atRisk ? "AT RISK" : self == .accruing ? "ACCRUING" : "FREE TIME" }
    var tone: Color  { self == .atRisk ? Brand.danger : self == .accruing ? Brand.warning : Brand.success }
}

private struct WatchBox735: Identifiable {
    let id: String; let chargeId: Int?; let cid: String; let where_: String; let value: String; let state: DDState735
}

@MainActor private final class DemurrageWatchModel735: ObservableObject {
    @Published var loading = true
    @Published var loadError: String? = nil
    @Published var hasData = false

    @Published var exposure = 0.0           // climbing total — seeded from the live read, then ticks
    @Published var perDay = 0.0
    @Published var lfdFractionUsed = 0.0    // worst container free-time consumed → arc gauge
    @Published var lfdLabel = "-"
    @Published var esang = "No container is inside its per-diem window."
    @Published var degraded = false
    @Published var atRiskCount = 0
    @Published var freeCount = 0
    @Published var totalCount = 0
    @Published var boxes: [WatchBox735] = []
    @Published var primaryChargeId: Int? = nil
    @Published var actionMessage: String? = nil
    @Published var actionError: String? = nil
    @Published var actionInFlight = false

    private var tickTask: Task<Void, Never>? = nil

    // Live shapes — demurrageAlerts.dashboard (vesselProcedure, no input).
    private struct Summary735: Decodable {
        let totalAccruing: Int?
        let criticalCount: Int?
        let warningCount: Int?
        let safeCount: Int?
        let totalChargesAccruing: Double?
        let projected7dCharges: Double?
    }
    private struct Record735: Decodable {
        let id: Int?
        let shipmentId: Int?
        let containerId: Int?
        let portId: Int?
        let chargeType: String?
        let freeTimeDays: Int?
        let chargeableDays: Int?
        let ratePerDay: String?
        let totalCharge: String?
        let status: String?
    }
    private struct DashOut735: Decodable {
        let summary: Summary735?
        let critical: [Record735]?
        let warning: [Record735]?
    }
    private struct BookAppointmentIn735: Encodable {
        let demurrageId: Int
        let scheduledAt: String
        let notes: String
    }
    private struct BookAppointmentOut735: Decodable {
        let success: Bool
        let appointmentId: String?
        let confirmationNumber: String?
        let terminalName: String?
        let scheduledAt: String?
    }
    private struct DisputeIn735: Encodable {
        let demurrageId: Int
        let reason: String
    }
    private struct DisputeOut735: Decodable {
        let success: Bool
        let disputeId: String?
        let status: String?
        let demurrageStatus: String?
    }

    func load() async {
        loading = true; loadError = nil
        do {
            let o: DashOut735 = try await EusoTripAPI.shared.queryNoInput("demurrageAlerts.dashboard")
            apply(o)
            hasData = !boxes.isEmpty || (o.summary?.totalAccruing ?? 0) > 0
            loading = false
            startTick()
        } catch {
            loadError = error.eusoUserCopy
            loading = false
        }
    }

    private func apply(_ o: DashOut735) {
        let s = o.summary
        exposure = s?.totalChargesAccruing ?? 0
        // projected 7d charges → a per-day accrual estimate for the hero sub line.
        if let p7 = s?.projected7dCharges, p7 > 0 { perDay = p7 / 7.0 }
        atRiskCount = s?.criticalCount ?? 0
        freeCount = s?.safeCount ?? 0
        totalCount = s?.totalAccruing ?? 0

        // Worst container = the highest-charge critical record; its free-time
        // consumption drives the LFD arc gauge (chargeableDays / freeTimeDays).
        let crit = o.critical ?? []
        let warn = o.warning ?? []
        let worst = crit.max { (Double($0.totalCharge ?? "0") ?? 0) < (Double($1.totalCharge ?? "0") ?? 0) }
        primaryChargeId = worst?.id ?? crit.first?.id ?? warn.first?.id
        if let w = worst, let free = w.freeTimeDays, free > 0 {
            let used = Double(w.chargeableDays ?? 0) + Double(w.freeTimeDays ?? 0)
            lfdFractionUsed = min(1, max(0, used / Double(free)))
            lfdLabel = (w.chargeableDays ?? 0) > 0 ? "OVER" : "\(free)d"
        } else {
            lfdFractionUsed = 0; lfdLabel = "-"
        }

        let formatCharge: (String?) -> String = { raw in
            let v = Double(raw ?? "0") ?? 0
            return "$\(Int(v))"
        }
        let portFor: (Record735) -> String = { r in
            let kind = (r.status ?? "").lowercased() == "accruing" ? "per-diem accruing" : (r.status ?? "watch")
            let days = r.chargeableDays ?? 0
            return "Container #\(r.containerId.map(String.init) ?? "-") · \(kind)\(days > 0 ? " +\(days)d" : "")"
        }
        let critBoxes: [WatchBox735] = crit.map { r in
            WatchBox735(id: r.id.map { "vd_\($0)" } ?? UUID().uuidString,
                        chargeId: r.id,
                        cid: r.chargeType?.capitalized ?? "Demurrage",
                        where_: portFor(r),
                        value: r.ratePerDay.flatMap { Double($0) }.map { "$\(Int($0))/day" } ?? formatCharge(r.totalCharge),
                        state: .atRisk)
        }
        let warnBoxes: [WatchBox735] = warn.map { r in
            WatchBox735(id: r.id.map { "vd_\($0)" } ?? UUID().uuidString,
                        chargeId: r.id,
                        cid: r.chargeType?.capitalized ?? "Demurrage",
                        where_: portFor(r),
                        value: formatCharge(r.totalCharge),
                        state: .accruing)
        }
        boxes = critBoxes + warnBoxes

        if let w = worst {
            esang = "Pull container #\(w.containerId.map(String.init) ?? "-") today · \(w.ratePerDay.flatMap { Double($0) }.map { "$\(Int($0))/day" } ?? "per-diem") at LFD"
        } else if boxes.isEmpty {
            esang = "No container is inside its per-diem window."
        }
    }

    // Accrual continues minute-over-minute so the hero never looks frozen between reads.
    private func startTick() {
        tickTask?.cancel()
        guard perDay > 0 else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                await MainActor.run {
                    guard let self else { return }
                    self.exposure += self.perDay / (24 * 60)
                }
            }
        }
    }

    func stop() { tickTask?.cancel(); tickTask = nil }

    func bookPickupAppointment() async {
        guard !actionInFlight else { return }
        guard let demurrageId = primaryChargeId else {
            actionMessage = nil
            actionError = "No live demurrage charge is available for pickup booking."
            return
        }
        actionInFlight = true
        actionMessage = nil
        actionError = nil
        defer { actionInFlight = false }
        do {
            let formatter = ISO8601DateFormatter()
            let scheduledAt = formatter.string(from: Date().addingTimeInterval(6 * 60 * 60))
            let out: BookAppointmentOut735 = try await EusoTripAPI.shared.mutation(
                "vesselDrayage.bookAppointment",
                input: BookAppointmentIn735(
                    demurrageId: demurrageId,
                    scheduledAt: scheduledAt,
                    notes: "Booked from Vessel Demurrage Watch"
                )
            )
            actionMessage = out.confirmationNumber.map {
                "Pickup appointment \($0) booked\(out.terminalName.map { " at \($0)" } ?? "")."
            } ?? (out.success ? "Pickup appointment booked." : "Pickup appointment submitted.")
            await load()
        } catch {
            actionError = error.eusoUserCopy
        }
    }

    func disputePrimaryCharge() async {
        guard !actionInFlight else { return }
        guard let demurrageId = primaryChargeId else {
            actionMessage = nil
            actionError = "No live demurrage charge is available to dispute."
            return
        }
        actionInFlight = true
        actionMessage = nil
        actionError = nil
        defer { actionInFlight = false }
        do {
            let out: DisputeOut735 = try await EusoTripAPI.shared.mutation(
                "vesselDrayage.disputeDemurrageCharge",
                input: DisputeIn735(
                    demurrageId: demurrageId,
                    reason: "Opened from Vessel Demurrage Watch for the primary at-risk container."
                )
            )
            actionMessage = out.disputeId.map { "Dispute \($0) opened · \(out.demurrageStatus ?? out.status ?? "open")." }
                ?? (out.success ? "Demurrage dispute opened." : "Demurrage dispute submitted.")
            await load()
        } catch {
            actionError = error.eusoUserCopy
        }
    }
}

struct VesselDemurrageAlertsScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselDemurrageAlertsBody735()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",                isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselDemurrageAlertsBody735: View {
    @Environment(\.palette) private var palette
    @StateObject private var model = DemurrageWatchModel735()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()

                if model.loading {
                    LifecycleCard { Text("Loading demurrage watch…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = model.loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if !model.hasData {
                    EusoEmptyState(systemImage: "shippingbox",
                                   title: "No demurrage accruing",
                                   subtitle: "demurrageAlerts.dashboard returned no at-risk containers. Nothing is inside its per-diem window, no exposure to watch.")
                } else {
                    heroCard
                    actionStatus
                    Text("CONTAINER WATCH · FREE TIME vs PER-DIEM")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    watchCard
                    esangRow
                    HStack(spacing: 12) {
                        CTAButton(title: model.actionInFlight ? "Working..." : "Book pickup appt",
                                  action: { Task { await model.bookPickupAppointment() } },
                                  trailingIcon: "calendar.badge.clock")
                        .disabled(model.actionInFlight)
                        Button { Task { await model.disputePrimaryCharge() } } label: {
                            Text(model.actionInFlight ? "Working..." : "Dispute")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                                .frame(maxWidth: 144, minHeight: 52)
                                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard)
                                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(palette.borderFaint, lineWidth: 1)))
                        }
                        .buttonStyle(.plain)
                        .disabled(model.actionInFlight)
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await model.load() }
        .refreshable { await model.load() }
        .onDisappear { model.stop() }
    }

    private var actionStatus: some View {
        Group {
            if let err = model.actionError {
                LifecycleCard(accentDanger: true) {
                    Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                }
            } else if let message = model.actionMessage {
                LifecycleCard {
                    Text(message).font(EType.caption).foregroundStyle(Brand.success)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · D&D WATCH").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text(model.degraded ? "DEGRADED" : "LIVE · USD").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Demurrage watch").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
                Spacer()
                if model.atRiskCount > 0 {
                    StatusPill(text: "\(model.atRiskCount) At risk", kind: .danger)
                }
            }
        }
    }

    private var heroCard: some View {
        LifecycleCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("EXPOSURE NOW · ALL CONTAINERS").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    Text("$\(Int(model.exposure))").font(.system(size: 40, weight: .bold)).foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                    HStack(spacing: 6) {
                        Image(systemName: "triangle.fill").font(.system(size: 8)).foregroundStyle(Brand.danger)
                        Text(model.degraded ? "rough estimate (degraded)" : (model.perDay > 0 ? "accruing $\(Int(model.perDay)) / day" : "no active per-diem"))
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.warning).monospacedDigit()
                    }
                    Text("\(model.totalCount) containers · \(model.atRiskCount) at risk · \(model.freeCount) free")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
                }
                Spacer()
                LFDGauge735(fractionUsed: model.lfdFractionUsed, centerLabel: model.lfdLabel)
                    .frame(width: 78, height: 92)
            }
        }
    }

    private var watchCard: some View {
        LifecycleCard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.boxes.enumerated()), id: \.element.id) { idx, b in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 15)).foregroundStyle(b.state.tone)
                            .frame(width: 40, height: 40)
                            .background(RoundedRectangle(cornerRadius: 10).fill(b.state.tone.opacity(0.12)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(b.cid).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                            Text(b.where_).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(b.state.pill).font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(b.state.tone)
                            Text(b.value).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary).monospacedDigit()
                        }
                    }
                    .padding(.vertical, 12)
                    if idx < model.boxes.count - 1 { Divider().overlay(palette.borderFaint) }
                }
            }
        }
    }

    private var esangRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 28, height: 28)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear], center: .topLeading, startRadius: 0, endRadius: 14)).frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.esang).font(.system(size: 12.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text("ESang · gate-out clock armed · book the next free slot").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(palette.bgCard).overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.borderFaint, lineWidth: 1)))
    }
}

// LFD arc-clock gauge — mirrors the SVG dasharray ring (worst container's free-time consumed).
private struct LFDGauge735: View {
    @Environment(\.palette) private var palette
    let fractionUsed: Double; let centerLabel: String
    var body: some View {
        VStack(spacing: 4) {
            Text("WORST · LFD").font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            ZStack {
                Circle().stroke(palette.textPrimary.opacity(0.08), lineWidth: 7)
                Circle().trim(from: 0, to: CGFloat(min(1, max(0, fractionUsed))))
                    .stroke(LinearGradient(colors: [Brand.warning, Brand.danger], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(centerLabel).font(.system(size: 16, weight: .bold)).foregroundStyle(palette.textPrimary).monospacedDigit()
                    Text("TO LFD").font(.system(size: 8, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                }
            }
            .frame(width: 60, height: 60)
        }
    }
}

#Preview("735 · Vessel Demurrage Watch · Night") { VesselDemurrageAlertsScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("735 · Vessel Demurrage Watch · Light") { VesselDemurrageAlertsScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
