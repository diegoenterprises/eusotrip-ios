//
//  806_VesselTankContainerMonitor.swift
//  EusoTrip — Vessel Operator · Tank Container Monitor (LIVE INSTRUMENT archetype).
//
//  Faithful port of "806 Vessel Tank Container Monitor.svg" (Dark + Light). Live
//  pressure + lading temp on every ISO tank against its MAWP on one instrument dial —
//  a 270° pressure gauge with green/amber/red MAWP bands + a needle on the worst box,
//  a peak-pressure KPI strip, a per-tank readings ledger, a hazmat classification
//  strip, and a fused ESang vent plan — so a box trending toward its working-pressure
//  ceiling is flagged before the transship berth window and a relief-valve event.
//
//  Nav: Shell + BottomNav (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME), COMPLIANCE inked.
//
//  REAL WIRING (tRPC · server/routers/tankMonitor.ts):
//    · tankMonitor.getTankReadings  {terminalId} -> { readings:[{tankNumber, product,
//        pressurePsi, mawpPsi, temperatureF, status, percentFull, terminalName, …}],
//        summary }  (:25) — the dial value (psi→bar), KPI, and per-tank rows.
//    · tankMonitor.getTankAlerts    {terminalId?, severityFilter} -> [alerts]  (:137) —
//        the WATCH count + the alert "Log vent check" acknowledges.
//    · tankMonitor.acknowledgeTankAlert {confirm, terminalId, alertKey, tankNumber?,
//        severity?} -> ack  (:311 · mutation · writes the ack + blockchainAuditTrail).
//
//  STUB · named-gap (honest, per wireframe <desc>): tankMonitor is terminal-tank-farm
//  scoped (terminalId/tankNumber). Binding this generic tank-reading infra to an in-transit
//  ISO tank container on a vessel booking needs a {containerId, loadId} scope — flagged to
//  the web team. For a vessel operator with no bound terminal the dial holds its honest
//  "awaiting ISO-tank telemetry" state (no fabricated pressure); it lights up live the
//  instant a terminal/container scope is bound. Log vent check needs a bound terminal +
//  open alert, else it surfaces the scope gap honestly.
//
//  RBAC: protectedProcedure (vessel reuse needs a containerId scope · flagged). transportMode=
//  vessel · US (IMDG Class 8 · CBP/USCG). NO mock data — every bar, headroom and °F is a
//  live reading; the MAWP bands are the instrument scale.
//

import SwiftUI

struct VesselTankContainerMonitorScreen: View {
    let theme: Theme.Palette
    /// Terminal / tank-farm the readings scope to. 0 = unbound (vessel-container
    /// scope is a named gap) → the honest awaiting-telemetry state.
    var terminalId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            VesselTankContainerMonitorBody(terminalId: terminalId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",            isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct TankReadingsResult806: Decodable {
    let readings: [TankReading806]
}

private struct TankReading806: Decodable, Identifiable {
    var id: Int { tankNumber ?? 0 }
    let tankNumber: Int?
    let product: String?
    let pressurePsi: Double?
    let mawpPsi: Double?
    let temperatureF: Double?
    let status: String?
    let percentFull: Double?
    let terminalName: String?
}

private struct TankAlert806: Decodable, Identifiable {
    var id: String { alertKey ?? "\(tankNumber ?? "")-\(metric ?? "")" }
    let alertKey: String?
    let tankNumber: String?
    let severity: String?
    let metric: String?
    let message: String?
}

// MARK: - Body

private struct VesselTankContainerMonitorBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.vesselOperatorNavHandler) private var navHandler
    let terminalId: Int

    @State private var readings: [TankReading806] = []
    @State private var alerts: [TankAlert806] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var acking = false
    @State private var ackDone = false
    @State private var ackError: String? = nil
    @State private var showDG = false

    private let psiPerBar = 14.5037738

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                IridescentHairline().padding(.top, Space.s3)

                VStack(alignment: .leading, spacing: Space.s5) {
                    if loading {
                        loadingState
                    } else if let err = loadError {
                        errorCard(err)
                    } else {
                        instrumentCard
                        kpiStrip
                        readingsSection
                        hazmatStrip
                        if showDG { dgCard }
                        esangCard
                        if ackDone { banner("Vent check logged · alert acknowledged.", danger: false) }
                        if let err = ackError { banner(err, danger: true) }
                        ctaRow
                    }
                    Color.clear.frame(height: 96)
                }
                .padding(.top, Space.s5)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s5)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 5) {
                    Text("✦").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                    Text("VESSEL OPERATOR · TANK MONITOR")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text("IMDG 8").font(EType.mono(.micro)).tracking(0.8).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Button { navHandler?("Compliance") } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }.buttonStyle(.plain)
                Text("Tank monitor")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s3)
        }
    }

    // MARK: Instrument card (gradient-rim · gauge + worst-box panel)

    private var instrumentCard: some View {
        HStack(alignment: .center, spacing: Space.s4) {
            PressureGauge806(valueBar: worstPressureBar, mawpBar: worstMawpBar, live: hasReadings)
                .frame(width: 132, height: 132)
            VStack(alignment: .leading, spacing: 6) {
                Text("WORST BOX · vs MAWP").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                if let w = worstBox {
                    Text(tankTitle(w)).font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.7)
                    Text(statusLine(w)).font(.system(size: 11, weight: .bold))
                        .foregroundStyle(statusTone(w)).lineLimit(1).minimumScaleFactor(0.7)
                    Text("MAWP \(barText(worstMawpBar)) · headroom")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textTertiary)
                    Text(barText(max(0, worstMawpBar - worstPressureBar)))
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(LinearGradient.diagonal)
                } else {
                    Text("Awaiting ISO-tank telemetry")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textSecondary)
                    Text("Vessel-container scope is a named gap — the dial lights up when a tank feed is bound.")
                        .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            gradientKpi(label: "PEAK PRESS", value: barText(worstPressureBar, unitless: true),
                        caption: "bar · of \(barText(worstMawpBar, unitless: true))")
            darkKpi(label: "ISO TANKS", value: "\(readings.count)", caption: "on this sailing")
            darkKpi(label: "WATCH", value: "\(watchCount)", caption: watchCount > 0 ? "venting ok" : "nominal",
                    tone: watchCount > 0 ? Brand.warning : palette.textPrimary)
        }
    }

    private func gradientKpi(label: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(.white.opacity(0.85))
            Text(value).font(.system(size: 26, weight: .semibold, design: .monospaced)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.system(size: 10)).foregroundStyle(.white.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .background(LinearGradient.diagonal)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func darkKpi(label: String, value: String, caption: String, tone: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 26, weight: .semibold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.system(size: 10)).foregroundStyle(tone ?? palette.textSecondary).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Tank readings ledger

    private var readingsSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ISO TANK READINGS · PRESSURE / LADING TEMP")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            if readings.isEmpty {
                EusoEmptyState(systemImage: "gauge.with.dots.needle.bottom.50percent",
                               title: "No tank telemetry",
                               subtitle: "Live pressure + lading temp per ISO tank appear here once a tank feed is bound — vessel-container scope is a named gap.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(readings.enumerated()), id: \.element.id) { idx, r in
                        readingRow(r)
                        if idx < readings.count - 1 {
                            Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                        }
                    }
                }
                .background(palette.bgCardSoft)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
            }
        }
    }

    private func readingRow(_ r: TankReading806) -> some View {
        let watch = isWatch(r)
        let accent = watch ? Brand.warning : Brand.info
        let pBar = bar(r.pressurePsi)
        let mBar = bar(r.mawpPsi)
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(accent.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: "gauge.with.needle").font(.system(size: 16, weight: .semibold)).foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(tankTitle(r)).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(readingSub(r)).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 4) {
                Text(watch ? "WATCH" : "NOMINAL").font(.system(size: 9, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(watch ? Brand.warning : Brand.success)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill((watch ? Brand.warning : Brand.success).opacity(0.16)))
                Text(barText(pBar)).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                Text("headroom \(barText(max(0, mBar - pBar), unitless: true))")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
    }

    // MARK: Hazmat classification strip

    private var hazmatStrip: some View {
        HStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: 3).fill(Brand.danger).frame(width: 6, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(hazmatTitle).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text("\(readings.count) ISO tank\(readings.count == 1 ? "" : "s") · IMDG dangerous goods watch")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            Text("CLASS 8").font(.system(size: 10, weight: .heavy)).foregroundStyle(Brand.danger)
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: DG manifest detail (toggle)

    private var dgCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("DG MANIFEST · BY TANK").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if readings.isEmpty {
                Text("The IMDG declaration lists each tank's UN class here once a tank feed is bound.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                ForEach(readings) { r in
                    HStack {
                        Text(tankTitle(r)).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text(r.product ?? "—").font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: ESang vent plan

    private var esangCard: some View {
        HStack(spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG · VENT PLAN").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                Text(esangHeadline).font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                    .lineLimit(2).minimumScaleFactor(0.85)
                Text(esangSub).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: CTA row

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button { Task { await logVentCheck() } } label: {
                HStack(spacing: 6) {
                    if acking { ProgressView().tint(.white).scaleEffect(0.8) }
                    Text(acking ? "Logging…" : "Log vent check")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient.primary).clipShape(Capsule())
            }
            .buttonStyle(.plain).disabled(acking).opacity(acking ? 0.7 : 1.0)

            Button { withAnimation(.easeOut(duration: 0.18)) { showDG.toggle() } } label: {
                Text(showDG ? "Hide DG" : "DG manifest").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(minWidth: 130, minHeight: 48).padding(.horizontal, Space.s3)
                    .background(palette.bgCard).overlay(Capsule().strokeBorder(palette.borderFaint)).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
    }

    // MARK: Loading / error / banners

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 160)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        }
    }

    private func errorCard(_ err: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(Brand.danger)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func banner(_ msg: String, danger: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: danger ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(danger ? AnyShapeStyle(Brand.danger) : AnyShapeStyle(LinearGradient.diagonal))
            Text(msg).font(EType.caption).foregroundStyle(danger ? Brand.danger : palette.textPrimary)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading)
        .background((danger ? Brand.danger : Brand.success).opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder((danger ? Brand.danger : Brand.success).opacity(0.30)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - Derived

    private var hasReadings: Bool { !readings.isEmpty && worstMawpBar > 0 }

    /// The box with the least headroom (highest pressure / MAWP ratio).
    private var worstBox: TankReading806? {
        readings
            .filter { bar($0.mawpPsi) > 0 }
            .max { headroomRatio($0) > headroomRatio($1) }
            ?? readings.first
    }
    private func headroomRatio(_ r: TankReading806) -> Double {
        let m = bar(r.mawpPsi); return m > 0 ? bar(r.pressurePsi) / m : 0
    }
    private var worstPressureBar: Double { worstBox.map { bar($0.pressurePsi) } ?? 0 }
    private var worstMawpBar: Double { worstBox.map { bar($0.mawpPsi) } ?? 0 }
    private var watchCount: Int { readings.filter { isWatch($0) }.count }

    private func isWatch(_ r: TankReading806) -> Bool {
        let s = (r.status ?? "").lowercased()
        if s.contains("warn") || s.contains("watch") || s.contains("critical") || s.contains("alarm") { return true }
        let m = bar(r.mawpPsi)
        return m > 0 && bar(r.pressurePsi) / m >= 0.6
    }
    private func statusTone(_ r: TankReading806) -> Color { isWatch(r) ? Brand.warning : Brand.success }
    private func statusLine(_ r: TankReading806) -> String {
        let hr = max(0, bar(r.mawpPsi) - bar(r.pressurePsi))
        return isWatch(r) ? "watch · headroom \(barText(hr, unitless: true)) bar" : "nominal · headroom \(barText(hr, unitless: true)) bar"
    }

    private func tankTitle(_ r: TankReading806) -> String {
        let n = r.tankNumber.map { "Tank \($0)" } ?? "Tank"
        if let p = r.product, !p.isEmpty { return "\(n) · \(p)" }
        if let t = r.terminalName, !t.isEmpty { return "\(t) \(n)" }
        return n
    }
    private func readingSub(_ r: TankReading806) -> String {
        var parts: [String] = []
        if let p = r.product, !p.isEmpty { parts.append(p) }
        if let t = r.temperatureF, t != 0 { parts.append("lading \(String(format: "%.0f°F", t))") }
        if let pf = r.percentFull, pf > 0 { parts.append("\(Int(pf))% full") }
        return parts.isEmpty ? "ISO tank" : parts.joined(separator: " · ")
    }

    private var hazmatTitle: String {
        if let p = readings.compactMap({ $0.product }).first, !p.isEmpty {
            return "\(p) · IMDG dangerous goods"
        }
        return "IMDG dangerous goods · tank watch"
    }
    private var esangHeadline: String {
        guard let w = worstBox, hasReadings else { return "Awaiting tank telemetry to build a vent plan" }
        return isWatch(w) ? "\(tankTitle(w)) on watch — plan a vent at transship"
                          : "All ISO tanks within working pressure"
    }
    private var esangSub: String {
        guard hasReadings else { return "vessel-container scope is a named gap" }
        return "headroom \(barText(max(0, worstMawpBar - worstPressureBar), unitless: true)) bar · check at the berth window"
    }

    private func bar(_ psi: Double?) -> Double { (psi ?? 0) / psiPerBar }
    private func barText(_ v: Double, unitless: Bool = false) -> String {
        let s = String(format: "%.1f", v)
        return unitless ? s : "\(s) bar"
    }

    // MARK: - Actions

    private func load() async {
        loading = true; loadError = nil
        struct ReadingsIn: Encodable { let terminalId: Int }
        struct AlertsIn: Encodable { let terminalId: Int?; let severityFilter: String }
        do {
            async let rd: TankReadingsResult806 = EusoTripAPI.shared.query(
                "tankMonitor.getTankReadings", input: ReadingsIn(terminalId: terminalId))
            // Alerts is best-effort — a failure never blocks the instrument.
            let readingsResp = try await rd
            self.readings = readingsResp.readings
            self.alerts = (try? await EusoTripAPI.shared.query(
                "tankMonitor.getTankAlerts",
                input: AlertsIn(terminalId: terminalId > 0 ? terminalId : nil, severityFilter: "all"))) ?? []
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func logVentCheck() async {
        ackDone = false; ackError = nil
        guard terminalId > 0 else {
            ackError = "Bind a terminal/container to log a vent check against a live tank alert."
            return
        }
        guard let alert = alerts.first, let key = alert.alertKey else {
            ackError = "No open tank alert to log a vent check against."
            return
        }
        acking = true
        struct AckIn: Encodable {
            let confirm: Bool; let terminalId: Int; let alertKey: String
            let tankNumber: String?; let severity: String?; let metric: String?
            let note: String
        }
        struct AckOut: Decodable { let ok: Bool? }
        do {
            let _: AckOut = try await EusoTripAPI.shared.mutation(
                "tankMonitor.acknowledgeTankAlert",
                input: AckIn(confirm: true, terminalId: terminalId, alertKey: key,
                             tankNumber: alert.tankNumber, severity: alert.severity, metric: alert.metric,
                             note: "Vent check logged from Tank Monitor"))
            ackDone = true
            await load()
        } catch {
            ackError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        acking = false
    }
}

// MARK: - Pressure gauge (270° arc with MAWP bands + needle)

private struct PressureGauge806: View {
    let valueBar: Double
    let mawpBar: Double
    let live: Bool
    @Environment(\.palette) private var palette

    private let sweep: CGFloat = 0.75            // 270° of a full circle
    private let rotation: Angle = .degrees(135)  // start at lower-left

    var body: some View {
        ZStack {
            // Track.
            Circle().trim(from: 0, to: sweep)
                .stroke(palette.borderFaint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(rotation)
            // Bands: green (0–65%) · amber (65–90%) · red (90–100%) of MAWP.
            bandArc(from: 0.0, to: 0.65, color: Brand.success)
            bandArc(from: 0.65, to: 0.90, color: Brand.warning)
            bandArc(from: 0.90, to: 1.0, color: Brand.danger)
            // Needle.
            if live && mawpBar > 0 {
                needle
                Circle().fill(palette.textPrimary).frame(width: 9, height: 9)
                Circle().fill(.white).frame(width: 3, height: 3)
            }
            // Center readout.
            VStack(spacing: 0) {
                Text(live && mawpBar > 0 ? String(format: "%.1f", valueBar) : "—")
                    .font(.system(size: 24, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                Text(live ? "bar · live" : "no feed")
                    .font(.system(size: 8.5, weight: .semibold)).foregroundStyle(palette.textTertiary)
            }
            .offset(y: 6)
        }
    }

    private func bandArc(from: Double, to: Double, color: Color) -> some View {
        Circle()
            .trim(from: sweep * CGFloat(from), to: sweep * CGFloat(to))
            .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .butt))
            .rotationEffect(rotation)
    }

    private var needle: some View {
        GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height) / 2
            let frac = min(max(mawpBar > 0 ? valueBar / mawpBar : 0, 0), 1)
            let angle = Angle.degrees(135 + Double(frac) * 270)
            Path { p in
                p.move(to: CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
                p.addLine(to: CGPoint(x: geo.size.width / 2 + cos(angle.radians) * (r - 14),
                                      y: geo.size.height / 2 + sin(angle.radians) * (r - 14)))
            }
            .stroke(palette.textPrimary, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        }
    }
}

#Preview("806 · Vessel Tank Container Monitor · Night") {
    VesselTankContainerMonitorScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("806 · Vessel Tank Container Monitor · Light") {
    VesselTankContainerMonitorScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
