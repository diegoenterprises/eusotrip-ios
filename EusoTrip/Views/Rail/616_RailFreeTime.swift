//
//  616_RailFreeTime.swift
//  EusoTrip — Rail Engineer · Free Time (demurrage / per-diem · LFD watch).
//
//  Verbatim port of wireframe "616 Rail Free Time · Dark".
//  CARRIER-SIDE · flagship DETAIL grammar (back chevron + eyebrow + mono
//  caption + 28/-0.4 title · gradient-rimmed hero ActiveCard with free-time
//  countdown + used progress + WARNING word · 3-cell KPI strip · itemized
//  container ListRow stack with 40x40 intermodal-container icon chip + short
//  severity pill + right tabular days · per-diem exposure context strip ·
//  Schedule-pickup / LFD-alerts CTA pair).
//
//  tRPC anchors (CONFIRMED in-repo):
//    multiModal.getLastFreeDayAlerts  — { alerts:[…], total, critical, urgent, warning }
//    multiModal.getFreeTimeManagement — { freeTimeSchedules:[…], portSpecific:[…] }
//

import SwiftUI

struct RailFreeTimeScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailFreeTimeBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",              isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",        isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror multiModal.getLastFreeDayAlerts / getFreeTimeManagement)

private struct LFDAlert: Decodable, Identifiable {
    let id: String
    let containerNumber: String?
    let shippingLine: String?
    let port: LFDPort?
    let terminal: String?
    let lastFreeDay: String?
    let daysUntilLFD: Int?
    let severity: String?          // "critical" | "urgent" | "warning"
    let estimatedPerDiem: Double?
    let bookingRef: String?
    let actionRequired: String?
}

private struct LFDPort: Decodable {
    let code: String?
    let name: String?
}

private struct LFDAlertsResponse: Decodable {
    let alerts: [LFDAlert]
    let total: Int
    let critical: Int
    let urgent: Int
    let warning: Int
}

private struct FreeTimeSchedule: Decodable {
    let shippingLine: String?
    let importLeg: FreeTimeLeg?
    let exportLeg: FreeTimeLeg?

    enum CodingKeys: String, CodingKey {
        case shippingLine
        case importLeg = "import"
        case exportLeg = "export"
    }
}

private struct FreeTimeLeg: Decodable {
    let demurrageFreeTime: Int?
    let detentionFreeTime: Int?
}

private struct FreeTimeResponse: Decodable {
    let freeTimeSchedules: [FreeTimeSchedule]
    let portSpecific: [FreeTimePortRow]
}

private struct FreeTimePortRow: Decodable {
    let terminalFreeTime: Int?
}

// MARK: - Body

private struct RailFreeTimeBody: View {
    @Environment(\.palette) private var palette

    @State private var alerts: [LFDAlert] = []
    @State private var totalContainers = 0
    @State private var criticalCount = 0
    @State private var urgentCount = 0
    @State private var warningCount = 0
    @State private var freeTimeHours: Int? = nil          // US free-time window (hours) from getFreeTimeManagement
    @State private var loading = true
    @State private var loadError: String? = nil

    // The single most-urgent alert drives the hero countdown.
    private var leadAlert: LFDAlert? {
        alerts.min { ($0.daysUntilLFD ?? 99) < ($1.daysUntilLFD ?? 99) }
    }

    // Free-time window in hours — default to the carrier-standard US 48h
    // intermodal window when the schedule endpoint is real-empty.
    private var freeWindowHours: Int { freeTimeHours ?? 48 }

    // Hours used = elapsed against the lead container's free-time window,
    // derived from days-until-LFD. (used = window − remaining)
    private var usedHours: Int {
        guard let days = leadAlert?.daysUntilLFD else { return 0 }
        let remaining = max(0, days) * 24
        return min(freeWindowHours, max(0, freeWindowHours - remaining))
    }

    private var atRiskCount: Int { criticalCount + urgentCount }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    LifecycleCard { Text("Loading free time…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    hero
                    kpiStrip
                    containerWatch
                    perDiemExposure
                    actions
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    // MARK: - Header (back chevron · eyebrow · mono caption · 28/-0.4 title)

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                Text("RAIL ENGINEER · FREE TIME")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("DEMURRAGE")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Free time")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(railLineLabel)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text("synced 4m ago")
                        .font(EType.mono(.caption)).tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            IridescentHairline()
        }
    }

    private var railLineLabel: String {
        (leadAlert?.shippingLine ?? "BNSF INTERMODAL").uppercased()
    }

    // MARK: - Hero (gradient-rimmed ActiveCard · countdown + used progress + WARNING word)

    private var hero: some View {
        ActiveCard {
            VStack(alignment: .leading, spacing: 0) {
                // Tag row: intermodal · warning
                HStack(spacing: 10) {
                    Text("intermodal")
                        .font(.system(size: 11, weight: .bold)).tracking(0.5)
                        .foregroundStyle(palette.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Color.white.opacity(0.08)).clipShape(Capsule())
                    if let sev = heroSeverityWord {
                        Text(sev.lowercased())
                            .font(.system(size: 11, weight: .bold)).tracking(0.5)
                            .foregroundStyle(heroSeverityColor)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(heroSeverityColor.opacity(0.22)).clipShape(Capsule())
                    }
                    Spacer()
                }
                .padding(.bottom, 18)

                // Countdown + LFD context · right-side US window status
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(countdownText)
                            .font(.system(size: 30, weight: .bold)).monospacedDigit()
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("to last free day")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.textSecondary)
                        Text(lfdContextText)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.textTertiary)
                    }
                    .padding(.leading, 14)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("US \(freeWindowHours)H FREE")
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text(heroSeverityWord ?? "OK")
                            .font(EType.mono(.body)).tracking(0.2)
                            .foregroundStyle(heroSeverityColor)
                    }
                }
                .padding(.bottom, 16)

                // Used progress bar (used / window)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(LinearGradient.diagonal)
                            .frame(width: geo.size.width * usedFraction)
                    }
                }
                .frame(height: 6)
            }
        }
    }

    private var usedFraction: CGFloat {
        guard freeWindowHours > 0 else { return 0 }
        return min(1.0, max(0.0, CGFloat(usedHours) / CGFloat(freeWindowHours)))
    }

    private var countdownText: String {
        guard let days = leadAlert?.daysUntilLFD else { return "—" }
        if days < 0 { return "PAST" }
        let remHours = max(0, freeWindowHours - usedHours)
        let d = remHours / 24
        let h = remHours % 24
        if d > 0 { return "\(d)d \(h)h" }
        return "\(h)h"
    }

    private var lfdContextText: String {
        guard let a = leadAlert else { return "no spotted cars" }
        let lfd = a.lastFreeDay.map { humanDate($0) } ?? "—"
        let where_ = a.port?.name ?? a.terminal ?? "—"
        return "LFD \(lfd) · \(where_)"
    }

    private var heroSeverityWord: String? {
        guard let sev = leadAlert?.severity?.lowercased() else { return nil }
        switch sev {
        case "critical": return "PAST"
        case "urgent":   return "WARNING"
        case "warning":  return "WATCH"
        default:         return sev.uppercased()
        }
    }

    private var heroSeverityColor: Color {
        switch leadAlert?.severity?.lowercased() {
        case "critical": return Brand.danger
        case "urgent":   return Brand.warning
        case "warning":  return Brand.info
        default:         return palette.textSecondary
        }
    }

    // MARK: - KPI strip (cell-1 eusoDiagonal · FREE TIME / USED / AT RISK)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            // Cell 1 — gradient-filled (eusoDiagonal)
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("FREE TIME")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(Color.white.opacity(0.85))
                Text("\(freeWindowHours)h")
                    .font(.system(size: 22, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.white)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            MetricTile(label: "USED",    value: "\(usedHours)h")
            MetricTile(label: "AT RISK", value: "\(atRiskCount)", accent: atRiskCount > 0 ? Brand.warning : nil)
        }
    }

    // MARK: - Container watch (CONTAINERS · LFD WATCH · itemized list)

    private var containerWatch: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("CONTAINERS · LFD WATCH")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("\(totalContainers) cars")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textTertiary)
            }
            if alerts.isEmpty {
                EusoEmptyState(systemImage: "shippingbox",
                               title: "No containers on LFD watch",
                               subtitle: "Spotted intermodal cars approaching last free day will appear here.")
            } else {
                VStack(spacing: 0) {
                    let shown = Array(alerts.prefix(3))
                    ForEach(Array(shown.enumerated()), id: \.element.id) { idx, a in
                        containerRow(a)
                        if idx < shown.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.leading, 16)
                        }
                    }
                    if alerts.count > 3, let extra = alerts.dropFirst(3).first {
                        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, 16)
                        Text(overflowLine(extra))
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                }
                .background(palette.bgCard)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func containerRow(_ a: LFDAlert) -> some View {
        let color = severityColor(a.severity)
        return HStack(spacing: 12) {
            // 40x40 intermodal-container icon chip
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.20))
                    .frame(width: 40, height: 40)
                Image(systemName: "shippingbox")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(rowTitle(a))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(rowSub(a))
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                Text(severityPillText(a.severity))
                    .font(.system(size: 11, weight: .bold)).tracking(0.5)
                    .foregroundStyle(color)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(color.opacity(0.22)).clipShape(Capsule())
                Text(daysText(a.daysUntilLFD))
                    .font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
            }
        }
        .padding(16)
    }

    private func rowTitle(_ a: LFDAlert) -> String {
        let cn = a.containerNumber ?? "—"
        let where_ = a.port?.name ?? a.terminal ?? "—"
        return "\(cn) · \(where_)"
    }

    private func rowSub(_ a: LFDAlert) -> String {
        // Prefer the server-supplied action; fall back to a derived
        // spotted/LFD descriptor from real fields.
        if let action = a.actionRequired, !action.isEmpty { return action }
        let days = a.daysUntilLFD ?? 0
        if days < 0 { return "LFD passed · per-diem accruing" }
        if days == 0 { return "spotted · LFD today · pull now" }
        return "spotted · LFD \(a.lastFreeDay.map { humanDate($0) } ?? "—")"
    }

    private func overflowLine(_ a: LFDAlert) -> String {
        let cn = a.containerNumber ?? "—"
        let lfd = a.lastFreeDay.map { humanDate($0) } ?? "—"
        return "+ \(cn) · LFD \(lfd) · ample · \(totalContainers) cars total"
    }

    private func severityColor(_ sev: String?) -> Color {
        switch sev?.lowercased() {
        case "critical": return Brand.danger
        case "urgent":   return Brand.warning
        case "warning":  return Brand.info
        default:         return Brand.info
        }
    }

    private func severityPillText(_ sev: String?) -> String {
        switch sev?.lowercased() {
        case "critical": return "PAST"
        case "urgent":   return "DUE"
        case "warning":  return "WATCH"
        default:         return "WATCH"
        }
    }

    private func daysText(_ days: Int?) -> String {
        guard let d = days else { return "—" }
        if d < 0 { return "+\(abs(d))d" }
        return "\(d)d"
    }

    // MARK: - Per-diem exposure context strip

    private var perDiemExposure: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PER-DIEM EXPOSURE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("US \(freeWindowHours)h free")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textTertiary)
            }
            Text(exposureLine)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
            Text(exposureRef)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var exposureLine: String {
        let exposed = alerts.first { ($0.estimatedPerDiem ?? 0) > 0 } ?? leadAlert
        if let a = exposed, let perDiem = a.estimatedPerDiem, perDiem > 0 {
            let cn = a.containerNumber ?? "—"
            let lfd = a.lastFreeDay.map { humanDate($0) } ?? "—"
            return "Projected \(currency(perDiem)) if \(cn) not pulled by LFD \(lfd)"
        }
        let total = alerts.reduce(into: 0.0) { acc, a in acc += a.estimatedPerDiem ?? 0 }
        if total > 0 {
            return "Projected \(currency(total)) across \(atRiskCount) at-risk cars"
        }
        return "No per-diem accruing · all spotted cars inside free time"
    }

    private var exposureRef: String {
        let ref = leadAlert?.bookingRef ?? "—"
        return "Eusorone Technologies (DU) · \(ref) · US \(freeWindowHours)h"
    }

    // MARK: - Actions (Schedule pickup · LFD alerts)

    private var actions: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: "Schedule pickup", action: {})
                .frame(maxWidth: .infinity)
            Button(action: {}) {
                Text("LFD alerts")
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color(hex: 0x232932))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(width: 148)
        }
    }

    // MARK: - Helpers

    private func currency(_ v: Double) -> String {
        if v >= 1000 { return String(format: "$%.0f", v) }
        return String(format: "$%.0f", v)
    }

    private func humanDate(_ iso: String) -> String {
        // Input arrives as "yyyy-MM-dd" (from lfdDate.toISOString().split("T")[0]).
        let inFmt = DateFormatter(); inFmt.dateFormat = "yyyy-MM-dd"
        guard let date = inFmt.date(from: iso) else { return iso }
        let outFmt = DateFormatter(); outFmt.dateFormat = "MMM d"
        return outFmt.string(from: date)
    }

    // MARK: - Load

    private func reload() async {
        loading = true; loadError = nil
        struct AlertsIn: Encodable { let daysAhead: Int }
        struct FreeTimeIn: Encodable { let portCode: String? }
        do {
            async let alertsResp: LFDAlertsResponse = EusoTripAPI.shared.query(
                "multiModal.getLastFreeDayAlerts", input: AlertsIn(daysAhead: 7))
            async let freeResp: FreeTimeResponse = EusoTripAPI.shared.query(
                "multiModal.getFreeTimeManagement", input: FreeTimeIn(portCode: nil))
            let (a, f) = try await (alertsResp, freeResp)
            self.alerts = a.alerts
            self.totalContainers = a.total
            self.criticalCount = a.critical
            self.urgentCount = a.urgent
            self.warningCount = a.warning
            // Derive the US free-time window (hours) from the first schedule's
            // import demurrage free-time (days → hours). Real-empty endpoints
            // leave this nil → hero falls back to the carrier-standard 48h.
            if let leg = f.freeTimeSchedules.first?.importLeg,
               let days = leg.demurrageFreeTime, days > 0 {
                self.freeTimeHours = days * 24
            } else if let portFree = f.portSpecific.first?.terminalFreeTime, portFree > 0 {
                self.freeTimeHours = portFree * 24
            } else {
                self.freeTimeHours = nil
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

#Preview("616 · Rail Free Time · Night") { RailFreeTimeScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("616 · Rail Free Time · Light") { RailFreeTimeScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
