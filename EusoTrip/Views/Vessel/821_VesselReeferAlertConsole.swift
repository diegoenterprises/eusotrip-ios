//
//  821_VesselReeferAlertConsole.swift
//  EusoTrip — Vessel Operator · Reefer Alert Console.
//
//  Faithful port of "821 Vessel Reefer Alert Console.svg" (Light + Dark), adapted into the app on the
//  canonical DesignSystem (Shell · BottomNav · Theme.Palette · StatusPill · CTAButton · IridescentHairline)
//  matching the registered vessel sibling 757_VesselDetentionLetters element-for-element in idiom. Role
//  VESSEL_OPERATOR (carrier-side). Nav anchored to VesselOperatorNavController
//  (HOME · SHIPMENTS · [orb] · COMPLIANCE[current] · ME) — the same Shell + BottomNav wrapper the
//  registered vessel siblings ship, with the COMPLIANCE slot inked (reefer alerts = a compliance surface,
//  FDA FSMA 21 CFR 1.908).
//
//  LIVE FUSION: the reefer telemetry stream is the heartbeat — the hero open-count, the KPI strip, the
//  alert queue rows AND the escalation strip are four faces of the SAME `alerts` state. When a new
//  excursion lands or an ack clears, all four re-reason together off `load()`. Degraded provider state
//  surfaces an explicit error card, never a frozen number.
//
//  Data / wiring (endpoints confirmed via EUSOTRIP_PLATFORM MCP this fire):
//    reeferTemp.getAlerts (EXISTS frontend/server/routers/reeferTemp.ts:231 · protectedProcedure ·
//      input {loadId?:number, limit:number=20} · returns [{id:string, severity, message, zone,
//      tempF:number|null, acknowledged, createdAt:string}] scoped by reeferAlerts.driverId, ORDER BY
//      createdAt DESC LIMIT input.limit. Empty list when no alerts — the bespoke empty state renders
//      honestly, no fabricated rows).
//    reeferTemp.acknowledgeAlert (EXISTS reeferTemp.ts:336 · protectedProcedure · input {alertId:number} ·
//      returns {success:true} · writes acknowledged=true, acknowledgedAt, acknowledgedBy). Wired to the
//      "Acknowledge" CTA (real mutation · re-runs load() on success).
//    STUB · named-gap: vessel-container scope still rides driverId (operatorId/containerId scope not yet
//      wired server-side — surfaced by 799/702). Per-alert setpoint-DEVIATION typing on the row is derived
//      CLIENT-SIDE from tempF vs the FSMA setpoint (the wire ships absolute tempF only).
//
//  ZERO-FALLBACK (2026-06-09 · C1 fix): NO seed alerts anywhere — state starts empty, getAlerts
//  overwrites UNCONDITIONALLY (an honest zero-alert response renders the empty state, never three
//  fabricated excursions), and acknowledgeAlert only fires on a REAL positive alertId parsed from
//  a live row. ReeferAlert821 / AlertUnit821 are file-scoped bespoke types suffixed by the screen
//  number to avoid cross-file private collisions.
//

import SwiftUI

// MARK: - Screen wrapper (Shell + vessel nav · COMPLIANCE inked)

struct VesselReeferAlertConsoleScreen: View {
    let theme: Theme.Palette
    /// Active reefer FCL booking the console scopes to. 0 (registry/zero-arg use) means
    /// "no load threaded": getAlerts omits the loadId filter and returns the operator's
    /// own live alerts across loads — real rows or the honest empty state, never seeds.
    var loadId: Int = 0

    init(theme: Theme.Palette, loadId: Int = 0) {
        self.theme = theme; self.loadId = loadId
    }

    var body: some View {
        Shell(theme: theme) {
            VesselReeferAlertConsoleBody821(loadId: loadId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill",        isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shape (mirrors reeferTemp.getAlerts return rows)

/// `reeferTemp.getAlerts` -> [{ id, severity, message, zone, tempF?, acknowledged, createdAt }].
private struct ReeferAlert821: Decodable, Identifiable {
    let id: String
    let severity: String?
    let message: String?
    let zone: String?
    let tempF: Double?
    let acknowledged: Bool?
    let createdAt: String?
}

/// `reeferTemp.ambient` -> the AMBIENT (deck/port) weather at the reefer
/// position. Here it powers a HEAT-PERIL banner: when the ambient is extreme
/// versus the FSMA setpoint, the excursion risk is external (a heat peril
/// closing on the box), not equipment — a different escalation than a
/// compressor fault. All fields nullable so an enterprise-gated payload
/// (available:false) decodes without throwing => the banner stays HIDDEN.
private struct ReeferAmbient821: Decodable {
    let available: Bool?
    let ambientTempF: Double?
    let weatherCode: Int?
}

// MARK: - Body

private struct VesselReeferAlertConsoleBody821: View {
    @Environment(\.palette) private var palette
    let loadId: Int

    @State private var alerts: [ReeferAlert821] = []   // live rows only — no seed excursions
    @State private var ambient: ReeferAmbient821? = nil // deck/port weather · null/available:false today
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var acking = false
    @State private var ackDone = false
    @State private var ackError: String? = nil
    @State private var showByUnit = false

    // FSMA setpoint the client-side deviation typing reads against (matches getStats default band).
    private let setpointF = 34.0

    // Derived counters — the four faces of one tick all read THIS state -----

    private var openAlerts: [ReeferAlert821] { alerts.filter { ($0.acknowledged ?? false) == false } }
    private var openCount: Int { openAlerts.count }
    private var criticalCount: Int { openAlerts.filter { sev($0) == .critical }.count }
    private var warningCount: Int { openAlerts.filter { sev($0) == .warning }.count }
    private var ackedCount: Int { alerts.filter { ($0.acknowledged ?? false) == true }.count }
    private var ackProgress: Double {
        let total = alerts.count
        return total == 0 ? 0 : Double(ackedCount) / Double(total)
    }
    private var firstOpenAlert: ReeferAlert821? { openAlerts.first }

    // Heat-peril read (ambient extreme vs setpoint) -------------------------
    // HONEST: only reads when the ambient feed is available with a real temp —
    // enterprise-gated (available:false / nil) hides the banner. The peril
    // verdict is derived strictly from the live ambient-over-setpoint spread,
    // never fabricated.

    private var ambientReady: Bool {
        (ambient?.available ?? false) && ambient?.ambientTempF != nil
    }

    /// Ambient deck/port temp minus the FSMA setpoint, in °F. Positive = the
    /// box is fighting external heat. nil until a real ambient lands.
    private var ambientOverSetpointF: Double? {
        ambient?.ambientTempF.map { $0 - setpointF }
    }

    /// Heat peril is flagged when the ambient runs extreme over the setpoint
    /// (≥ 60°F gap — e.g. a 34°F frozen setpoint under a 104°F deck): the
    /// excursion driver is external heat, not equipment, so the escalation is
    /// stow/shade/route — not a compressor swap.
    private var heatPeril: Bool {
        guard ambientReady, let over = ambientOverSetpointF else { return false }
        return over >= 60
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
                    heatPerilBanner
                    kpiStrip
                    alertQueueSection
                    escalationStrip
                    actionRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
        .sheet(isPresented: $showByUnit) {
            VesselReeferByUnitSheet821(alerts: alerts, setpointF: setpointF)
                .environment(\.palette, palette)
        }
    }

    // MARK: Eyebrow

    private var eyebrow: some View {
        HStack {
            HStack(spacing: 5) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.primary)
                Text("VESSEL OPERATOR · REEFER ALERTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
            }
            Spacer()
            // Honest scope chip: the real load when threaded, em-dash otherwise (no invented carrier/port).
            Text(loadId > 0 ? "LOAD \(loadId)" : "—")
                .font(EType.mono(.micro)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Title row

    private var titleRow: some View {
        HStack(alignment: .center) {
            Text("Reefer alerts")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Text("synced live")
                .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Loading / error / degraded

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
            Text("Telemetry degraded").font(EType.bodyStrong).foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Hero card (gradient-rim · live · open excursion alerts)

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.s2) {
                    chip("LIVE", color: Brand.success)
                    chip(openCount == 1 ? "1 OPEN" : "\(openCount) OPEN", color: Brand.danger)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("ACKED").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(palette.textTertiary)
                        Text("\(ackedCount)").font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(Brand.success)
                    }
                }
                HStack(alignment: .center, spacing: Space.s4) {
                    Text("\(openCount)")
                        .font(.system(size: 44, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("open excursion alerts")
                            .font(EType.bodyStrong).foregroundStyle(palette.textSecondary)
                        Text("\(criticalCount) critical · \(warningCount) warning\(warningCount == 1 ? "" : "s")")
                            .font(.system(size: 11)).foregroundStyle(criticalCount > 0 ? Brand.danger : palette.textTertiary)
                    }
                    Spacer()
                }
                .padding(.top, Space.s3)
                ProgressView(value: ackProgress).tint(Brand.magenta).padding(.top, Space.s2)
            }
            .padding(Space.s4)
        }
        .frame(height: 132)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(color.opacity(0.16)))
    }

    // MARK: Heat-peril banner (reeferTemp.ambient vs setpoint)

    /// Flags a HEAT PERIL when the deck/port ambient runs extreme over the
    /// FSMA setpoint — the excursion driver is external heat, not a
    /// compressor fault, so the escalation differs (stow/shade/route, not a
    /// unit swap). Bespoke: the live sky condition is the WeatherIcons glyph;
    /// the warning mark is the `.alert` utility glyph. HONEST: rendered ONLY
    /// when the ambient feed is available with a real temp — gated
    /// (available:false / nil) collapses it. No fabricated ambient/verdict.
    @ViewBuilder
    private var heatPerilBanner: some View {
        if ambientReady, let a = ambient, let aF = a.ambientTempF {
            let code = a.weatherCode ?? 0
            let peril = heatPeril
            let over = ambientOverSetpointF
            HStack(alignment: .top, spacing: Space.s3) {
                // Bespoke sky glyph for the live deck/port weatherCode.
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.06)).frame(width: 48, height: 48)
                    WeatherIcons.symbolView(for: code, size: 32)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        WeatherIcons.utility(.alert, size: 12,
                                             tint: peril ? Brand.danger : palette.textSecondary)
                        Text(peril ? "HEAT PERIL" : "AMBIENT OK")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                            .foregroundStyle(peril ? Brand.danger : Brand.success)
                        Text("· deck \(String(format: "%.0f°F", aF)) vs setpoint \(String(format: "%.0f°F", setpointF))")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Text(peril
                         ? "Ambient runs +\(over.map { String(format: "%.0f°F", $0) } ?? "—") over setpoint — an excursion here is external heat, not equipment. Escalate stow/shade/route, not a unit swap."
                         : "Ambient within range of setpoint — an excursion here points to equipment, not heat.")
                        .font(.system(size: 12))
                        .foregroundStyle(peril ? Brand.danger : palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
            .background(peril ? Brand.danger.opacity(0.07) : palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(peril ? Brand.danger.opacity(0.45) : palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
        // available:false / nil => hidden; lights up when the key lands.
    }

    // MARK: KPI strip (OPEN · CRITICAL · ACKED 24H)

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            VStack(alignment: .leading, spacing: Space.s1) {
                Text("OPEN").font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(.white.opacity(0.85))
                Text("\(openCount)").font(.system(size: 28, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.white)
                Text("excursions").font(.system(size: 11)).foregroundStyle(.white.opacity(0.85))
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            darkKpiTile(label: "CRITICAL", value: "\(criticalCount)",
                        caption: "ack required", danger: criticalCount > 0)
            darkKpiTile(label: "ACKED 24H", value: "\(ackedCount)",
                        caption: "closed", danger: false, success: true)
        }
    }

    private func darkKpiTile(label: String, value: String, caption: String, danger: Bool, success: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 28, weight: .semibold)).monospacedDigit()
                .foregroundStyle(danger ? Brand.danger : (success ? Brand.success : palette.textPrimary))
            Text(caption).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Alert queue · by unit

    private var alertQueueSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("ALERT QUEUE · BY UNIT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text("LIVE ALERT FEED").font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 0) {
                let rows = displayRows
                if rows.isEmpty {
                    EusoEmptyState(systemImage: "checkmark.seal",
                                   title: "No open alerts",
                                   subtitle: "Reefer excursions will appear here the moment a unit drifts out of band.")
                        .padding(Space.s4)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                        alertRow(row)
                        if idx < rows.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, 68)
                        }
                    }
                }
            }
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            Text("Telemetry tick · reefer temperature stream")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
        }
    }

    /// One displayable alert row, derived from the live `alerts` feed.
    private struct AlertUnit821: Identifiable {
        let id = UUID()
        enum Band { case critical, warning, recovered }
        let band: Band
        let title: String
        let meta: String
        let pill: String
        let valText: String
    }

    private var displayRows: [AlertUnit821] {
        alerts.prefix(4).map { a in
            let band: AlertUnit821.Band = (a.acknowledged ?? false) ? .recovered : sev(a).band
            let zoneLabel = (a.zone.map { $0.capitalized }) ?? "Hold"
            let val: String
            if let t = a.tempF {
                let dev = celsius(t) - celsius(setpointF)
                val = band == .recovered ? String(format: "%.1f°", celsius(t))
                                         : String(format: "%@%.1f°", dev >= 0 ? "+" : "", dev)
            } else {
                val = band == .warning ? "ajar" : "-"
            }
            return AlertUnit821(
                band: band,
                title: a.message ?? "\(zoneLabel) · excursion",
                meta: "\(zoneLabel) · \(a.createdAt.map(shortAge) ?? "open")",
                pill: band == .critical ? "CRITICAL" : (band == .warning ? "WARNING" : "ACKED"),
                valText: val)
        }
    }

    private func alertRow(_ u: AlertUnit821) -> some View {
        let accent: Color
        let icon: String
        switch u.band {
        case .critical:  accent = Brand.danger;  icon = "exclamationmark.triangle.fill"
        case .warning:   accent = Brand.warning; icon = "exclamationmark.triangle"
        case .recovered: accent = Brand.success; icon = "checkmark.circle"
        }
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent.opacity(0.18)).frame(width: 40, height: 40)
                Image(systemName: icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(u.title).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(u.meta).font(EType.mono(.caption)).tracking(0.2).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 6) {
                StatusPill(text: u.pill, kind: u.band == .critical ? .danger : (u.band == .warning ? .warning : .success))
                Text(u.valText).font(.system(size: 13, weight: .bold)).monospacedDigit()
                    .foregroundStyle(u.band == .recovered ? palette.textPrimary : accent)
            }
        }
        .padding(Space.s4)
    }

    // MARK: Escalation strip

    private var escalationStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("ESCALATION · CET ON CALL")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(openCount == 1 ? "1 open" : "\(openCount) open")
                    .font(EType.mono(.caption)).foregroundStyle(openCount > 0 ? Brand.warning : Brand.success)
            }
            Text("Acknowledging closes the loop · CET temp log signed · 21 CFR 1.908")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            // Honest scope line — real load ref or em-dash; never an invented carrier/booking string.
            Text(loadId > 0 ? "LOAD \(loadId) · live alert feed" : "— · all loads · live alert feed")
                .font(EType.mono(.caption)).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Actions

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let e = ackError { Text(e).font(EType.caption).foregroundStyle(Brand.danger) }
            if ackDone { Text("Excursion acknowledged · temp log signed.").font(EType.caption).foregroundStyle(Brand.success) }
            HStack(spacing: Space.s2) {
                CTAButton(title: acking ? "Acknowledging…" : "Acknowledge",
                          action: { Task { await acknowledge() } },
                          isLoading: acking)
                    .frame(maxWidth: .infinity)
                Button(action: { showByUnit = true }) {
                    Text("By unit")
                        .font(EType.title).foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(palette.bgCardSoft)
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                }
                .buttonStyle(.plain).frame(maxWidth: 148)
            }
        }
    }

    // MARK: Severity / helpers

    private enum Sev { case critical, warning, recovered
        var band: AlertUnit821.Band {
            switch self { case .critical: return .critical; case .warning: return .warning; case .recovered: return .recovered }
        }
    }
    private func sev(_ a: ReeferAlert821) -> Sev {
        switch (a.severity ?? "").lowercased() {
        case "critical", "high", "danger": return .critical
        case "warning", "medium", "warn":  return .warning
        default:                            return (a.acknowledged ?? false) ? .recovered : .warning
        }
    }
    private func celsius(_ f: Double) -> Double { (f - 32) * 5 / 9 }
    private func shortAge(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        guard let d = f.date(from: iso) else { return iso }
        let mins = max(0, Int(Date().timeIntervalSince(d) / 60))
        return mins < 60 ? "\(mins)m open" : "\(mins / 60)h open"
    }

    // MARK: Load (one tick · all faces re-reason together)

    private func load() async {
        loading = true; loadError = nil
        struct AlertsIn821: Encodable { let loadId: Int?; let limit: Int }
        struct AmbientIn821: Encodable { let loadId: Int? }
        do {
            // loadId is optional on the wire — omitted (nil) when no load is threaded.
            let rows: [ReeferAlert821] = try await EusoTripAPI.shared.query(
                "reeferTemp.getAlerts", input: AlertsIn821(loadId: loadId > 0 ? loadId : nil, limit: 20))
            // UNCONDITIONAL overwrite: an honest zero-alert response clears the queue.
            alerts = rows
        } catch {
            loadError = error.eusoUserCopy
        }
        // Ambient (deck/port weather) is a best-effort overlay — its feed is
        // enterprise-gated and may return available:false or be unreachable.
        // A failure NEVER degrades the alert console: the heat-peril banner
        // just stays hidden until the key lands. loadId is optional on the wire.
        self.ambient = try? await EusoTripAPI.shared.query(
            "reeferTemp.ambient", input: AmbientIn821(loadId: loadId > 0 ? loadId : nil))
        loading = false
    }

    private func acknowledge() async {
        // C1 gate: only a REAL server-minted alert id (positive int) may be acknowledged.
        guard let alert = firstOpenAlert, let alertId = Int(alert.id), alertId > 0 else {
            ackError = "No open excursion to acknowledge."
            return
        }
        acking = true; ackError = nil
        struct AckIn821: Encodable { let alertId: Int }
        struct AckOut821: Decodable { let success: Bool? }
        do {
            let _: AckOut821 = try await EusoTripAPI.shared.mutation(
                "reeferTemp.acknowledgeAlert", input: AckIn821(alertId: alertId))
            ackDone = true
            await load()
        } catch {
            ackError = error.eusoUserCopy
        }
        acking = false
    }
}

private struct VesselReeferByUnitSheet821: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let alerts: [ReeferAlert821]
    let setpointF: Double

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    LifecycleCard(accentGradient: true) {
                        LifecycleSection(label: "BY UNIT", icon: "shippingbox")
                        LifecycleRow(label: "Open units", value: String(alerts.filter { ($0.acknowledged ?? false) == false }.count))
                        LifecycleRow(label: "Setpoint", value: String(format: "%.0f°F", setpointF))
                    }

                    LifecycleCard {
                        LifecycleSection(label: "REEFER ALERTS", icon: "thermometer.snowflake")
                        if alerts.isEmpty {
                            Text("No reefer alerts in the live feed.")
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        } else {
                            ForEach(alerts) { alert in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(alert.zone?.uppercased() ?? "UNIT")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(palette.textPrimary)
                                    Text(unitLine(alert))
                                        .font(EType.caption)
                                        .foregroundStyle(palette.textSecondary)
                                    Text(alert.acknowledged == true ? "ACKNOWLEDGED" : severity(alert).uppercased())
                                        .font(EType.mono(.caption))
                                        .foregroundStyle(alert.acknowledged == true ? Brand.success : Brand.warning)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                }
                .padding(Space.s4)
            }
            .navigationTitle("By unit")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func unitLine(_ alert: ReeferAlert821) -> String {
        var parts: [String] = []
        if let temp = alert.tempF {
            parts.append(String(format: "%.1f°F", temp))
            parts.append(String(format: "%+.1f°F vs setpoint", temp - setpointF))
        }
        if let message = alert.message, !message.isEmpty { parts.append(message) }
        if let created = alert.createdAt, !created.isEmpty { parts.append(created) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func severity(_ alert: ReeferAlert821) -> String {
        alert.severity?.isEmpty == false ? alert.severity! : "open"
    }
}

#Preview("821 · Vessel Reefer Alert Console · Night") {
    VesselReeferAlertConsoleScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("821 · Vessel Reefer Alert Console · Light") {
    VesselReeferAlertConsoleScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
