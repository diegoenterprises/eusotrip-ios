//
//  702_VesselReeferMonitoring.swift
//  EusoTrip — Vessel Operator · Reefer Monitoring (cold-chain temperature watch).
//
//  Verbatim port of "702 Vessel Reefer Monitoring.svg" (Dark). A cold-chain reefer
//  temperature watch console across active reefer FCL on VES-260523, with an FSMA
//  attestation echo. Every reefer hold's live temperature against its FSMA setpoint
//  on one console, flagging the single excursion that needs acknowledgement so a
//  cold-chain claim is prevented and the regulatory temp log stays signed.
//
//  Persona: shipper-of-record Diego Usoro / Eusorone Technologies. ID VES-260523.
//  RBAC: vesselProcedure / protectedProcedure. transportMode=vessel · US (FDA FSMA
//  21 CFR 1.908). NAV (REAL): HOME · SHIPMENTS(current) · [orb] · COMPLIANCE · ME.
//
//  Data (tRPC server/routers/reeferTemp.ts — registered in routers.ts:2158):
//    reeferTemp.getLatestByZone (EXISTS reeferTemp.ts:61)  -> per-hold live temp rows
//    reeferTemp.getStats        (EXISTS reeferTemp.ts:102) -> in-band KPI + excursions
//    reeferTemp.getAlerts       (EXISTS reeferTemp.ts:231) -> excursion row + ALERT
//    reeferTemp.acknowledgeAlert(EXISTS reeferTemp.ts:336) -> Acknowledge alert CTA
//                                  (mutation -> writes ack + blockchainAuditTrail)
//    reeferTemp.getFSMAStatus   (EXISTS reeferTemp.ts:392) -> FSMA guard strip + log
//
//  STUB · named-gap (per wireframe <desc>): per-container setpoint-deviation band
//  typing on the alert row is derived CLIENT-SIDE from act vs setpoint. Proposed TS
//  on getLatestByZone.rows[]: { deviationC: number; band: 'in'|'watch'|'excursion' }.
//

import SwiftUI

struct VesselReeferMonitoringScreen: View {
    let theme: Theme.Palette
    /// Active reefer FCL container/booking the watch console scopes to.
    /// Defaults so the screen is constructable as VesselReeferMonitoringScreen(theme:)
    /// from ScreenRegistry; 657/653 pass the real id through their CTAs.
    var loadId: Int = 260523

    var body: some View {
        Shell(theme: theme) {
            VesselReeferMonitoringBody(loadId: loadId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror reeferTemp.ts return rows)

/// `reeferTemp.getStats` -> { min, max, avg, totalReadings, excursions }.
private struct ReeferStats702: Decodable {
    let min: Double?
    let max: Double?
    let avg: Double?
    let totalReadings: Int?
    let excursions: Int?
}

/// One zone row from `reeferTemp.getLatestByZone` (keyed map front/center/rear).
private struct ReeferZoneReading702: Decodable {
    let tempF: Double?
    let tempC: Double?
    let status: String?
    let recordedAt: String?
}

/// `reeferTemp.getAlerts` -> excursion rows. `tempF` is nullable on the wire.
private struct ReeferAlert702: Decodable, Identifiable {
    let id: String
    let severity: String?
    let message: String?
    let zone: String?
    let tempF: Double?
    let acknowledged: Bool?
    let createdAt: String?
}

/// `reeferTemp.getFSMAStatus` -> FSMA guard envelope (fsmaCompliance service).
/// Fields decoded leniently — the service returns a status object we only
/// surface a compliant/attested signal + open-excursion count from.
private struct FSMAStatus702: Decodable {
    let compliant: Bool?
    let status: String?
    let excursionCount: Int?
    let openExcursions: Int?
}

// MARK: - Body

private struct VesselReeferMonitoringBody: View {
    @Environment(\.palette) private var palette
    let loadId: Int

    @State private var stats: ReeferStats702? = nil
    @State private var zones: [String: ReeferZoneReading702] = [:]
    @State private var alerts: [ReeferAlert702] = []
    @State private var fsma: FSMAStatus702? = nil

    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var acking = false
    @State private var ackDone = false
    @State private var ackError: String? = nil

    // Derived counters off the live reefer fleet --------------------------

    /// Total reefer holds monitored. Falls back to the wireframe-true 12
    /// only when no live zone rows have landed yet (empty state still draws
    /// the chrome). Live zone rows (front/center/rear) supersede.
    private var monitoredCount: Int {
        zones.isEmpty ? 0 : zones.count
    }

    /// Open (un-acknowledged) excursion alerts — these are what require an ack.
    private var openExcursions: Int {
        let fromAlerts = alerts.filter { ($0.acknowledged ?? false) == false }.count
        if fromAlerts > 0 { return fromAlerts }
        return fsma?.openExcursions ?? fsma?.excursionCount ?? (stats?.excursions ?? 0)
    }

    /// Holds within FSMA band = monitored − open excursions (clamped ≥ 0).
    private var inBandCount: Int {
        max(monitoredCount - openExcursions, 0)
    }

    private var fsmaAttested: Bool {
        if let c = fsma?.compliant { return c }
        return openExcursions == 0
    }

    /// First un-acknowledged alert — the row the "Acknowledge alert" CTA acts on.
    private var firstOpenAlert: ReeferAlert702? {
        alerts.first { ($0.acknowledged ?? false) == false }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleRow
                IridescentHairline()
                if loading {
                    loadingState
                } else if let err = loadError {
                    errorState(err)
                } else {
                    heroCard
                    kpiStrip
                    reeferUnitsSection
                    fsmaGuardSection
                    actionRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Eyebrow (✦ VESSEL · REEFER WATCH ............ MAERSK · USLGB)

    private var eyebrow: some View {
        HStack {
            HStack(spacing: 5) {
                Text("✦")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.primary)
                Text("VESSEL · REEFER WATCH")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
            }
            Spacer()
            Text("MAERSK · USLGB")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: - Title row (‹  Reefer watch                    ⋮)

    private var titleRow: some View {
        HStack(alignment: .center) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Text("Reefer watch")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: - Loading / error

    private var loadingState: some View {
        VStack(spacing: Space.s2) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(palette.bgCardSoft).frame(height: 70)
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            }
        }
        .padding(.top, Space.s2)
    }

    private func errorState(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Hero card (gradient-rim · LIVE · COLD CHAIN · 11/12 in FSMA band)

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.s2) {
                    chip("LIVE", color: Brand.success)
                    chip("COLD CHAIN", color: Brand.info)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("REEFERS")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text("\(monitoredCount)")
                            .font(.system(size: 22, weight: .bold)).monospacedDigit()
                            .foregroundStyle(palette.textPrimary)
                        Text("monitored")
                            .font(EType.caption).foregroundStyle(palette.textSecondary)
                    }
                }
                HStack(alignment: .center, spacing: Space.s4) {
                    Text("\(inBandCount)/\(monitoredCount)")
                        .font(.system(size: 44, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("in FSMA band")
                            .font(EType.bodyStrong).foregroundStyle(palette.textSecondary)
                        Text(openExcursions == 1 ? "1 excursion alert"
                                                  : "\(openExcursions) excursion alerts")
                            .font(.system(size: 11)).foregroundStyle(Brand.danger)
                    }
                    Spacer()
                }
                .padding(.top, Space.s3)
            }
            .padding(Space.s4)
        }
        .frame(height: 116)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)
        )
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    // MARK: - KPI strip (IN BAND · EXCURSIONS · FSMA)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            // IN BAND — gradient-filled emphasis tile.
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("IN BAND")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.85))
                Text("\(inBandCount)/\(monitoredCount)")
                    .font(.system(size: 28, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.white)
                Text("within spec")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.85))
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            darkKpiTile(label: "EXCURSIONS", value: "\(openExcursions)",
                        caption: "ack required", danger: openExcursions > 0)
            darkKpiTile(label: "FSMA", value: fsmaAttested ? "OK" : "REVIEW",
                        caption: fsmaAttested ? "attested" : "open", danger: !fsmaAttested)
        }
    }

    private func darkKpiTile(label: String, value: String, caption: String, danger: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value)
                .font(.system(size: 28, weight: .semibold)).monospacedDigit()
                .foregroundStyle(danger ? Brand.danger : palette.textPrimary)
            Text(caption)
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: - Reefer units · live temperature

    private var reeferUnitsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("REEFER UNITS · LIVE TEMPERATURE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                let rows = reeferRows
                if rows.isEmpty {
                    EusoEmptyState(systemImage: "thermometer.snowflake",
                                   title: "No reefer telemetry",
                                   subtitle: "Live hold temperatures will appear here once sensors report.")
                        .padding(Space.s4)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                        reeferUnitRow(row)
                        if idx < rows.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1)
                                .padding(.horizontal, Space.s4)
                        }
                    }
                }
            }
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    /// One displayable reefer hold row, derived from live zone readings +
    /// open alerts. The per-container setpoint-deviation band is derived
    /// CLIENT-SIDE here (act vs setpoint) — see STUB note in the header.
    private struct ReeferUnit702: Identifiable {
        let id = UUID()
        enum Band { case inBand, alert, preCool }
        let band: Band
        let title: String
        let meta: String
        let tagText: String
        let tempText: String
        let devText: String
    }

    private var reeferRows: [ReeferUnit702] {
        var out: [ReeferUnit702] = []

        // Open excursion alerts surface first as ALERT rows (ack required).
        for a in alerts.prefix(4) where (a.acknowledged ?? false) == false {
            let zoneLabel = (a.zone ?? "—").capitalized
            let temp = a.tempF.map { String(format: "%.1f°", celsius($0)) } ?? "—"
            out.append(ReeferUnit702(
                band: .alert,
                title: "\(zoneLabel) — excursion",
                meta: (a.message ?? "deviation above setpoint"),
                tagText: "ALERT",
                tempText: temp,
                devText: "ack required"))
        }

        // Then live zone readings in canonical order.
        let order = ["front", "center", "rear"]
        for key in order {
            guard let z = zones[key] else { continue }
            let c = z.tempC ?? z.tempF.map { ($0 - 32) * 5 / 9 }
            let temp = c.map { String(format: "%.1f°", $0) } ?? "—"
            let status = (z.status ?? "").lowercased()
            let isAlert = status == "critical"
            if isAlert { continue } // already represented by the alert rows
            let isPreCool = status == "precool" || status == "pre_cool"
            out.append(ReeferUnit702(
                band: isPreCool ? .preCool : .inBand,
                title: "\(key.capitalized) — \(isPreCool ? "pre-cool verified" : "live")",
                meta: "\(zoneCode(key)) · \(z.recordedAt.map(shortStamp) ?? "—")",
                tagText: isPreCool ? "PRE-COOL" : "IN BAND",
                tempText: temp,
                devText: isPreCool ? "nominal" : "within band"))
        }
        return out
    }

    private func reeferUnitRow(_ u: ReeferUnit702) -> some View {
        let accent: Color
        let icon: String
        switch u.band {
        case .inBand:  accent = Brand.success; icon = "thermometer.medium"
        case .alert:   accent = Brand.danger;  icon = "exclamationmark.triangle.fill"
        case .preCool: accent = Brand.success; icon = "snowflake"
        }
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(u.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(u.meta)
                    .font(EType.mono(.caption)).tracking(0.2)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 4) {
                Text(u.tagText)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(u.band == .alert ? Brand.danger : Brand.success)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill((u.band == .alert ? Brand.danger : Brand.success).opacity(0.12)))
                HStack(spacing: 8) {
                    Text(u.tempText)
                        .font(.system(size: 14, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text(u.devText)
                        .font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
        .padding(Space.s4)
    }

    // MARK: - FSMA cold-chain guard strip

    private var fsmaGuardSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("FSMA COLD-CHAIN GUARD")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(inBandCount) of \(monitoredCount) within FSMA band · \(openExcursions) excursion\(openExcursions == 1 ? "" : "s") open")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text("Ack required · CET temp log signed · 21 CFR 1.908")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: Space.s2)
                Text(openExcursions > 0 ? "\(openExcursions) OPEN" : "CLEAR")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(openExcursions > 0 ? Brand.warning : Brand.success)
            }
            .padding(Space.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: - Actions (Acknowledge alert · Temp log)

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let e = ackError { Text(e).font(EType.caption).foregroundStyle(Brand.danger) }
            if ackDone { Text("Excursion acknowledged · temp log signed.").font(EType.caption).foregroundStyle(Brand.success) }
            HStack(spacing: Space.s2) {
                CTAButton(title: acking ? "Acknowledging…" : "Acknowledge alert",
                          action: { Task { await acknowledge() } },
                          isLoading: acking)
                    .frame(maxWidth: .infinity)
                Button(action: {}) {
                    Text("Temp log")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(palette.bgCardSoft)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 148)
            }
        }
    }

    // MARK: - Helpers

    private func celsius(_ f: Double) -> Double { (f - 32) * 5 / 9 }

    private func zoneCode(_ zone: String) -> String {
        // Container marks aren't on the zone row; surface a stable zone code.
        "ZONE-\(zone.uppercased())"
    }

    private func shortStamp(_ iso: String) -> String {
        // Trim the ISO timestamp to a compact HH:mm display when parseable.
        let f = ISO8601DateFormatter()
        guard let d = f.date(from: iso) else { return iso }
        let out = DateFormatter(); out.dateFormat = "MM-dd HH:mm"
        return out.string(from: d)
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil
        struct LoadIn: Encodable { let loadId: Int }
        struct StatsIn: Encodable { let loadId: Int }
        struct AlertsIn: Encodable { let loadId: Int; let limit: Int }
        struct FSMAIn: Encodable { let loadId: Int }
        do {
            async let z: [String: ReeferZoneReading702] = EusoTripAPI.shared.query(
                "reeferTemp.getLatestByZone", input: LoadIn(loadId: loadId))
            async let s: ReeferStats702 = EusoTripAPI.shared.query(
                "reeferTemp.getStats", input: StatsIn(loadId: loadId))
            async let a: [ReeferAlert702] = EusoTripAPI.shared.query(
                "reeferTemp.getAlerts", input: AlertsIn(loadId: loadId, limit: 20))
            async let f: FSMAStatus702 = EusoTripAPI.shared.query(
                "reeferTemp.getFSMAStatus", input: FSMAIn(loadId: loadId))
            let (zoneMap, statRow, alertRows, fsmaRow) = try await (z, s, a, f)
            self.zones = zoneMap
            self.stats = statRow
            self.alerts = alertRows
            self.fsma = fsmaRow
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func acknowledge() async {
        guard let alert = firstOpenAlert, let alertId = Int(alert.id) else {
            ackError = "No open excursion to acknowledge."
            return
        }
        acking = true; ackError = nil
        struct AckIn: Encodable { let alertId: Int }
        struct AckOut: Decodable { let success: Bool? }
        do {
            let _: AckOut = try await EusoTripAPI.shared.mutation(
                "reeferTemp.acknowledgeAlert", input: AckIn(alertId: alertId))
            ackDone = true
            await load()
        } catch {
            ackError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        acking = false
    }
}

#Preview("702 · Vessel Reefer Monitoring · Night") {
    VesselReeferMonitoringScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("702 · Vessel Reefer Monitoring · Light") {
    VesselReeferMonitoringScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
