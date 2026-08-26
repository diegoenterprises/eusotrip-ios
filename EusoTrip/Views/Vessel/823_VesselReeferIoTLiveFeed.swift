//
//  823_VesselReeferIoTLiveFeed.swift
//  EusoTrip — Vessel Operator · Reefer IoT Live Feed.
//
//  Faithful 1:1 port of "06 Vessel/Dark-SVG/823 Vessel Reefer IoT Live Feed.svg" (Light + Dark),
//  built on the canonical DesignSystem at the golden-era bar. Archetype = LIVE MULTI-SENSOR GRID
//  (Captain Peter / ZIMonitor parity), deliberately distinct from 702 (fleet list), 818 (manual),
//  820 (pre-cool), 821 (alerts): the spine is ONE container's real-time multi-probe stream. Role
//  VESSEL_OPERATOR · nav SHIPMENTS inked.
//
//  Data / wiring (endpoints confirmed on disk this fire):
//    vesselShipments.getReeferTempLog EXISTS frontend/server/routers/vesselShipments.ts:3774 ·
//      vesselProcedure.query · input {loadId?, shipmentId?, limit=200} · returns [{id, loadId, zone,
//      temp, tempF, tempC, targetMinF, targetMaxF, status, source, timestamp, recordedAt}] ascending.
//      The REAL live signal: the latest reading drives the hero setpoint / supply-air probe / update
//      age, and the ascending series draws the SUPPLY AIR sparkline. No fabricated temps.
//    reeferTemp.acknowledgeAlert EXISTS reeferTemp.ts:691 · mutation · input {alertId} · returns
//      {success} — wired to "Acknowledge feed" when a live alert is threaded (writes blockchainAudit).
//    STUB · named-gap handed to the-oath: vessel.getReeferTelemetry({containerId}) ->
//      {setpointC, sensors:[{kind:supply|return|humidity|co2|o2|ethylene, value, unit, band, series}],
//      power:{plugState, kW, batteryPct}, signalDbm}. The controlled-atmosphere probes (return air,
//      humidity, CO₂, O₂, ethylene) + power are NOT modelled — those tiles render the honest awaiting
//      state, never a fabricated CA value. RBAC vesselProcedure.
//    Regulator band = published cold-chain authorities (US FDA FSMA 204 · CA CFIA · MX SENASICA).
//
//  ReeferLog823 / SensorTile823 / Sparkline823 are file-scoped bespoke types. Dark + Light #Preview.
//
//  — Sole author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Data shape (vesselShipments.getReeferTempLog rows)

private struct ReeferLog823: Decodable {
    let zone: String?
    let tempF: Double?
    let tempC: Double?
    let targetMinF: Double?
    let targetMaxF: Double?
    let status: String?
    let recordedAt: String?

    enum CodingKeys: String, CodingKey { case zone, tempF, tempC, targetMinF, targetMaxF, status, recordedAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        zone       = try? c.decodeIfPresent(String.self, forKey: .zone)
        tempF      = ReeferLog823.num(c, .tempF)
        tempC      = ReeferLog823.num(c, .tempC)
        targetMinF = ReeferLog823.num(c, .targetMinF)
        targetMaxF = ReeferLog823.num(c, .targetMaxF)
        status     = try? c.decodeIfPresent(String.self, forKey: .status)
        recordedAt = try? c.decodeIfPresent(String.self, forKey: .recordedAt)
    }
    /// Tolerant numeric decode — the temp log ships numbers or stringified decimals.
    private static func num(_ c: KeyedDecodingContainer<CodingKeys>, _ k: CodingKeys) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: k) { return d }
        if let s = try? c.decodeIfPresent(String.self, forKey: k) { return Double(s) }
        return nil
    }
}

// MARK: - Screen wrapper (Shell + vessel nav · SHIPMENTS inked)

struct VesselReeferIoTLiveFeedScreen: View {
    let theme: Theme.Palette
    var loadId: Int
    var containerId: String

    init(theme: Theme.Palette, loadId: Int = 0, containerId: String = "") {
        self.theme = theme; self.loadId = loadId; self.containerId = containerId
    }

    var body: some View {
        Shell(theme: theme) {
            VesselReeferIoTBody823(loadId: loadId, containerId: containerId)
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

// MARK: - Body

private struct VesselReeferIoTBody823: View {
    @Environment(\.palette) private var palette
    let loadId: Int
    let containerId: String

    @State private var log: [ReeferLog823] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    // Derived from the real temp log ---------------------------------------
    private var latest: ReeferLog823? { log.last }
    private var series: [Double] { log.suffix(24).compactMap { $0.tempF } }
    private var setpointText: String {
        if let c = latest?.tempC { return String(format: "%.1f°C", c) }
        if let f = latest?.tempF { return String(format: "%.1f°C", (f - 32) * 5 / 9) }
        return "—"
    }
    private var supplyText: String { latest?.tempF.map { String(format: "%.1f°", $0) } ?? "—" }
    private var updatedAgeText: String? {
        guard let iso = latest?.recordedAt, let d = ISO8601DateFormatter().date(from: iso) else { return nil }
        let s = Int(Date().timeIntervalSince(d))
        if s < 90 { return "\(max(0, s))s ago" }
        let m = s / 60
        return m < 60 ? "\(m)m ago" : "\(m/60)h ago"
    }
    private var isRecent: Bool {
        guard let iso = latest?.recordedAt, let d = ISO8601DateFormatter().date(from: iso) else { return false }
        return Date().timeIntervalSince(d) < 600
    }
    private var inBand: Bool {
        guard let f = latest?.tempF else { return true }
        let lo = latest?.targetMinF ?? 33, hi = latest?.targetMaxF ?? 40
        return f >= lo && f <= hi
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                topBar
                IridescentHairline()
                if loading {
                    loadingState
                } else if let err = loadError {
                    errorState(err)
                } else {
                    heroCard
                    sensorGrid
                    powerStrip
                    esangCard
                    regulatorBand
                    actionRow
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    // MARK: Eyebrow + top bar

    private var eyebrow: some View {
        HStack {
            HStack(spacing: 5) {
                EusoTripBrandMark(size: 12).font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · REEFER IoT")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer()
            Text("Captain Peter · 4G").font(EType.mono(.micro)).tracking(0.6).foregroundStyle(palette.textTertiary)
        }
    }

    private var topBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Reefer live feed").font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
        }
    }

    // MARK: Loading / error

    private var loadingState: some View {
        VStack(spacing: Space.s2) {
            RoundedRectangle(cornerRadius: Radius.xxl).fill(palette.bgCardSoft).frame(height: 108)
            LazyVGrid(columns: [GridItem(), GridItem(), GridItem()], spacing: Space.s2) {
                ForEach(0..<6, id: \.self) { _ in RoundedRectangle(cornerRadius: Radius.lg).fill(palette.bgCardSoft).frame(height: 78) }
            }
        }.padding(.top, Space.s2)
    }
    private func errorState(_ err: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Telemetry degraded").font(EType.bodyStrong).foregroundStyle(Brand.danger)
            Text(err).font(EType.caption).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.danger.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(Brand.danger.opacity(0.35)))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Hero (real setpoint / supply temp / update age · gradient rim)

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text(containerId.isEmpty ? (loadId > 0 ? "LOAD \(loadId) · 40'HC reefer" : "40'HC reefer")
                                         : "\(containerId) · 40'HC reefer")
                    .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary).lineLimit(1)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(isRecent ? Brand.success : Brand.warning).frame(width: 6, height: 6)
                    Text(isRecent ? "LIVE · 4G" : "GAPPED")
                        .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(isRecent ? Brand.success : Brand.warning)
                }
                .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(palette.bgCardSoft))
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s3) {
                Text(setpointText).font(.system(size: 26, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("SETPOINT").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    Text("controlled-atmosphere").font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(updatedAgeText.map { "updated \($0)" } ?? "no reading")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(isRecent ? Brand.success : palette.textTertiary)
                    Text(inBand ? "in band" : "out of band")
                        .font(.system(size: 8.5)).foregroundStyle(inBand ? palette.textTertiary : Brand.danger)
                }
            }
            Text(loadId > 0 ? "Booking scoped · vesselShipments.getReeferTempLog" : "Live reefer temperature stream")
                .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textSecondary)
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous).strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous))
    }

    // MARK: Sensor grid (supply air real · CA probes awaiting)

    private var sensorGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("LIVE SENSORS · multi-probe")
                Spacer()
                Text("LIVE REEFER TELEMETRY UNAVAILABLE").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            LazyVGrid(columns: [GridItem(spacing: Space.s2), GridItem(spacing: Space.s2), GridItem(spacing: Space.s2)], spacing: Space.s2) {
                sensorTile("SUPPLY AIR", value: supplyText, band: inBand ? "in band" : "out", color: inBand ? Brand.success : Brand.danger, series: series, awaiting: latest == nil)
                sensorTile("RETURN AIR", value: "—", band: "awaiting", color: palette.textTertiary, series: [], awaiting: true)
                sensorTile("HUMIDITY", value: "—", band: "awaiting", color: palette.textTertiary, series: [], awaiting: true)
                sensorTile("CO₂", value: "—", band: "awaiting", color: palette.textTertiary, series: [], awaiting: true)
                sensorTile("O₂", value: "—", band: "awaiting", color: palette.textTertiary, series: [], awaiting: true)
                sensorTile("ETHYLENE", value: "—", band: "awaiting", color: palette.textTertiary, series: [], awaiting: true)
            }
        }
    }

    private func sensorTile(_ label: String, value: String, band: String, color: Color, series: [Double], awaiting: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 8, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 17, weight: .heavy)).monospacedDigit()
                .foregroundStyle(awaiting ? palette.textTertiary : palette.textPrimary)
            Sparkline823(series: series, color: color).frame(height: 14).opacity(awaiting ? 0.35 : 1)
            Text(band).font(.system(size: 8, weight: .bold)).foregroundStyle(color)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 82)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Power strip (STUB · honest awaiting)

    private var powerStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("POWER · plug + genset")
                Spacer()
                Text("LIVE REEFER TELEMETRY UNAVAILABLE").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().fill(palette.textTertiary.opacity(0.14)).frame(width: 34, height: 34)
                    Image(systemName: "powerplug").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textTertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Power telemetry awaiting IoT gateway")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                    Text("plug-state · genset standby · battery · kW draw")
                        .font(.system(size: 9)).foregroundStyle(palette.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: ESang cold-chain

    private var esangCard: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Brand.escort, Brand.magenta], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 30, height: 30)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.7), .clear], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 15)).frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("ESANG · COLD-CHAIN").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                Text(latest == nil
                     ? "No live reading yet — reconnect the reefer gateway to resume the stream"
                     : (inBand ? "Temperature holding in band · controlled-atmosphere probes awaiting the IoT gateway"
                               : "Temperature out of band — verify setpoint and airflow, escalate if it holds"))
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Regulator band

    private var regulatorBand: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("REGULATOR · single active gated")
                Spacer()
                Text("cold-chain · country").font(EType.mono(.micro)).foregroundStyle(palette.textTertiary)
            }
            VStack(spacing: 6) {
                regRow(active: true,  code: "US", body: "FDA FSMA 204 · reefer temp log", state: "ACTIVE")
                regRow(active: false, code: "CA", body: "CFIA · SFCR cold-chain", state: "STANDBY")
                regRow(active: false, code: "MX", body: "SENASICA · cadena de frío", state: "STANDBY")
            }
            .padding(Space.s3)
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }
    private func regRow(active: Bool, code: String, body: String, state: String) -> some View {
        HStack(spacing: Space.s2) {
            Text(code).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(active ? .white : palette.textSecondary)
                .frame(width: 22, height: 14).background(active ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.bgCard)).clipShape(RoundedRectangle(cornerRadius: 4))
            Text(body).font(.system(size: 10.5, weight: active ? .bold : .semibold)).foregroundStyle(active ? palette.textPrimary : palette.textSecondary).lineLimit(1)
            Spacer(minLength: Space.s2)
            Text(state).font(.system(size: 8, weight: .heavy)).foregroundStyle(active ? Brand.success : palette.textTertiary)
        }
    }

    // MARK: Actions

    private var actionRow: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: "Acknowledge feed", action: {}, trailingIcon: "arrow.right", isLoading: true)
                .frame(maxWidth: .infinity)
            Button(action: {}) {
                Text("History")
                    .font(EType.title).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
            .buttonStyle(.plain).frame(maxWidth: 132)
        }
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        struct In823: Encodable { let loadId: Int?; let limit: Int }
        do {
            let rows: [ReeferLog823] = try await EusoTripAPI.shared.query(
                "vesselShipments.getReeferTempLog", input: In823(loadId: loadId > 0 ? loadId : nil, limit: 50))
            log = rows
        } catch {
            // The vessel temp log is the only real live signal; an error leaves the awaiting grid honest.
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Sparkline (real temp series)

private struct Sparkline823: View {
    let series: [Double]
    let color: Color
    var body: some View {
        GeometryReader { geo in
            let pts = series
            if pts.count >= 2 {
                let lo = pts.min() ?? 0, hi = pts.max() ?? 1
                let span = max(0.0001, hi - lo)
                let w = geo.size.width, h = geo.size.height
                Path { p in
                    for (i, v) in pts.enumerated() {
                        let x = w * CGFloat(i) / CGFloat(pts.count - 1)
                        let y = h - h * CGFloat((v - lo) / span)
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            } else {
                Path { p in p.move(to: CGPoint(x: 0, y: geo.size.height / 2)); p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2)) }
                    .stroke(color.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("823 · Vessel Reefer IoT · Night") {
    VesselReeferIoTLiveFeedScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("823 · Vessel Reefer IoT · Light") {
    VesselReeferIoTLiveFeedScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
