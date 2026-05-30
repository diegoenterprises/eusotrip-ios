//
//  582_RailRampSchedule.swift
//  EusoTrip — Rail Engineer · Ramp Schedule (train windows, dock compliance).
//
//  Verbatim port of "582 Rail Ramp Schedule.svg" (Light + Dark).
//  Next-window hero (time-to-arrival + track), 3-cell KPI (inbound/outbound/on-time%),
//  train windows list from dock appointments, window-compliance + gate-log context strip.
//  Nav anchored to RailEngineerNavController (HOME · SHIPMENTS[current] · [orb] · COMPLIANCE · ME).
//
//  Data:
//    yardManagement.getDockSchedule          (EXISTS yardManagement.ts:563)  → docks + appointments
//    yardManagement.getAppointmentCompliance (EXISTS yardManagement.ts:2198) → adherence%
//    yardManagement.getGateLog               (EXISTS yardManagement.ts:1615) → last gate move
//

import SwiftUI

struct RailRampScheduleScreen: View {
    let theme: Theme.Palette
    let locationId: String

    var body: some View {
        Shell(theme: theme) { RailRampScheduleBody(locationId: locationId) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct DockSchedule582: Decodable {
    let locationId: String?
    let date: String?
    let docks: [Dock582]?
}

private struct Dock582: Decodable, Identifiable {
    var id: String { dockId }
    let dockId: String
    let dockName: String?
    let type: String?
    let status: String?
    let appointments: [TrainWindow582]?
}

private struct TrainWindow582: Decodable, Identifiable {
    let id: String
    let dockId: String?
    let carrierId: String?
    let type: String?
    let scheduledAt: String?
    let status: String?
    let trailerNumber: String?
    let estimatedDurationMin: Int?
}

private struct AppointmentCompliance582: Decodable {
    let overallCompliancePct: Double?
    let totalScheduled: Int?
    let totalOnTime: Int?
    let totalLate: Int?
    let totalNoShow: Int?
}

private struct GateLog582: Decodable {
    let entries: [GateEntry582]?
    let summary: GateSummary582?
}

private struct GateEntry582: Decodable, Identifiable {
    let id: Int
    let loadNumber: String?
    let trailerNumber: String?
    let status: String?
    let updatedAt: String?
}

private struct GateSummary582: Decodable {
    let totalEntries: Int?
    let totalExits: Int?
    let uniqueCarriers: Int?
    let peakHour: String?
}

// MARK: - Body

private struct RailRampScheduleBody: View {
    @Environment(\.palette) private var palette
    let locationId: String

    @State private var schedule: DockSchedule582? = nil
    @State private var compliance: AppointmentCompliance582? = nil
    @State private var gateLog: GateLog582? = nil
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var isScheduling = false

    private static let iso = ISO8601DateFormatter()

    // MARK: Derived

    private var allWindows: [TrainWindow582] {
        (schedule?.docks ?? []).flatMap { $0.appointments ?? [] }
            .sorted { a, b in
                let da = Self.iso.date(from: a.scheduledAt ?? "") ?? .distantFuture
                let db = Self.iso.date(from: b.scheduledAt ?? "") ?? .distantFuture
                return da < db
            }
    }

    private var nextWindow: TrainWindow582? {
        allWindows.first { minutesUntil($0.scheduledAt) != nil }
    }

    private var inboundCount: Int  {
        (schedule?.docks ?? []).filter { ($0.type ?? "").lowercased() == "inbound" }.count
    }
    private var outboundCount: Int {
        (schedule?.docks ?? []).filter { ($0.type ?? "").lowercased() == "outbound" }.count
    }
    private var totalToday: Int   { allWindows.count }
    private var onTimePct: String {
        if let p = compliance?.overallCompliancePct { return "\(Int(p))%" }
        return "—"
    }
    private var missedCount: Int  { compliance?.totalNoShow ?? 0 }

    private var rampStatusLabel: String {
        guard let docks = schedule?.docks, !docks.isEmpty else { return "RAMP" }
        let occupied = docks.filter { $0.status == "occupied" }.count
        return occupied < docks.count ? "RAMP OPEN" : "RAMP FULL"
    }
    private var rampStatusColor: Color {
        rampStatusLabel == "RAMP OPEN" ? Brand.success : Brand.warning
    }
    private var nextTrackLabel: String { nextWindow?.dockId?.replacingOccurrences(of: "D", with: "track ") ?? "—" }
    private var nextWindowLabel: String {
        if let m = minutesUntil(nextWindow?.scheduledAt) { return "in \(m)m" }
        return "—"
    }
    private var nextWindowDetail: String {
        "\(nextWindow?.carrierId ?? "—") · \(timeLabel(nextWindow?.scheduledAt)) arrival"
    }

    private var lastGateLabel: String {
        guard let entry = gateLog?.entries?.first else { return "—" }
        let num = entry.trailerNumber ?? entry.loadNumber ?? "—"
        let t = timeLabel(entry.updatedAt)
        return "last gate \(String(num.prefix(14))) in \(t)"
    }
    private var adherenceLabel: String {
        let pct = compliance?.overallCompliancePct.map { "\(Int($0))%" } ?? "—"
        let missed = missedCount > 0 ? " · \(missedCount) missed window" : ""
        return "adherence \(pct)\(missed)"
    }

    private func minutesUntil(_ isoString: String?) -> Int? {
        guard let s = isoString, let d = Self.iso.date(from: s) else { return nil }
        let diff = d.timeIntervalSince(Date())
        guard diff > 0 else { return nil }
        return Int(diff / 60)
    }

    private func timeLabel(_ isoString: String?) -> String {
        guard let s = isoString, let d = Self.iso.date(from: s) else { return "—" }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: d)
    }

    // MARK: Body

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading ramp schedule…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    kpiStrip
                    trainWindowsList
                    complianceStrip
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("RAIL ENGINEER · RAMP SCHEDULE")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text(String(locationId.prefix(16)).uppercased())
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Ramp schedule")
                    .font(.system(size: 28, weight: .heavy))
                    .kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
        }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(rampStatusLabel)
                    .font(.system(size: 11, weight: .bold)).kerning(0.5)
                    .foregroundStyle(rampStatusColor)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(rampStatusColor.opacity(0.14)))
                Text(nextTrackLabel)
                    .font(.system(size: 11, weight: .bold)).kerning(0.5)
                    .foregroundStyle(palette.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(palette.textPrimary.opacity(0.06)))
                Spacer()
            }
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(nextWindowLabel)
                            .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                        Text("next window")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Text(nextWindowDetail)
                        .font(EType.caption)
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("TODAY")
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("\(totalToday)")
                        .font(.system(size: 22, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text("\(inboundCount) in · \(outboundCount) out")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    // MARK: - KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "INBOUND",  value: "\(inboundCount)")
            MetricTile(label: "OUTBOUND", value: "\(outboundCount)")
            MetricTile(label: "ON-TIME",  value: onTimePct, accent: compliance?.overallCompliancePct ?? 0 >= 90 ? Brand.success : nil)
        }
    }

    // MARK: - Train windows list

    private var trainWindowsList: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("TRAIN WINDOWS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getDockSchedule")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            if allWindows.isEmpty {
                EusoEmptyState(systemImage: "tram.fill",
                               title: "No windows today",
                               subtitle: "No train appointments scheduled at this ramp.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(allWindows.prefix(6).enumerated()), id: \.element.id) { idx, window in
                        trainWindowRow(window)
                        if idx < min(allWindows.count, 6) - 1 {
                            Divider().padding(.leading, 68).overlay(palette.borderFaint)
                        }
                    }
                }
                .background(palette.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint))
            }
        }
    }

    private func trainWindowRow(_ window: TrainWindow582) -> some View {
        let (pillLabel, pillColor) = windowPillInfo(window.status ?? "")
        let trackLabel = window.dockId.map { "track \($0.replacingOccurrences(of: "D", with: ""))" } ?? "—"
        let carrierCode = String((window.carrierId ?? "—").prefix(12))
        let dirLabel = (window.type ?? "").lowercased() == "outbound" ? "outbound" : "inbound"
        let title = "\(carrierCode) · \(dirLabel)"
        let sub = "\(trackLabel) · \(window.estimatedDurationMin.map { "\($0) min est." } ?? "—")"

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.info.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "tram.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Brand.info)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(sub)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(pillLabel)
                    .font(.system(size: 10, weight: .bold)).kerning(0.4)
                    .foregroundStyle(pillColor)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(pillColor.opacity(0.12)))
                Text(timeLabel(window.scheduledAt))
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(16)
    }

    private func windowPillInfo(_ status: String) -> (String, Color) {
        switch status.lowercased() {
        case "checked_in", "arrived":   return ("ON TIME", Brand.success)
        case "completed":               return ("DONE",    Brand.success)
        case "late":                    return ("LATE",    Brand.danger)
        case "cancelled":               return ("CANCEL",  Brand.danger)
        case "no_show":                 return ("NO SHOW", Brand.danger)
        default:                        return ("SCHED",   Brand.blue)
        }
    }

    // MARK: - Compliance strip

    private var complianceStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("WINDOW COMPLIANCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("getAppointmentCompliance")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.textTertiary)
            }
            Text(adherenceLabel)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text(lastGateLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(palette.borderFaint))
    }

    // MARK: - CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Schedule slot",
                      action: { Task { await scheduleSlot() } },
                      leadingIcon: "plus",
                      isLoading: isScheduling)
            Button {} label: {
                Text("Gate log")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
                    .background(palette.bgCard)
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load / Actions

    private func load() async {
        loading = true; loadError = nil
        struct ScheduleIn: Encodable { let locationId: String }
        struct ComplianceIn: Encodable { let locationId: String; let period: String }
        struct GateIn: Encodable { let locationId: String; let type: String; let limit: Int }
        do {
            async let schedResult:  DockSchedule582          = EusoTripAPI.shared.query(
                "yardManagement.getDockSchedule", input: ScheduleIn(locationId: locationId))
            async let compResult:   AppointmentCompliance582 = EusoTripAPI.shared.query(
                "yardManagement.getAppointmentCompliance", input: ComplianceIn(locationId: locationId, period: "today"))
            async let gateResult:   GateLog582               = EusoTripAPI.shared.query(
                "yardManagement.getGateLog", input: GateIn(locationId: locationId, type: "all", limit: 5))
            let (sc, cp, gl) = try await (schedResult, compResult, gateResult)
            self.schedule   = sc
            self.compliance = cp
            self.gateLog    = gl
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func scheduleSlot() async {
        isScheduling = true
        try? await Task.sleep(nanoseconds: 600_000_000)
        isScheduling = false
    }
}

#Preview("582 · Rail Ramp Schedule · Night") { RailRampScheduleScreen(theme: Theme.dark, locationId: "CHI-1").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("582 · Rail Ramp Schedule · Light") { RailRampScheduleScreen(theme: Theme.light, locationId: "CHI-1").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
