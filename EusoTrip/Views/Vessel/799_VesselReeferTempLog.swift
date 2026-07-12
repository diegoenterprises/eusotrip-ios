//
//  799_VesselReeferTempLog.swift
//  EusoTrip — Vessel Operator · Reefer Temp Log (COLD-CHAIN TREND archetype).
//
//  Faithful port of "799 Vessel Reefer Temp Log.svg" (Dark + Light). A 24h zone trace
//  over the FSMA band: three per-zone temperature polylines (front / center / rear) on
//  a shaded 33–40°F band with the 40°F ceiling + 34°F setpoint reference lines, a live
//  zone-status strip with per-zone deviation, a fused ESang airflow plan, and a Record-
//  FSMA-temp write — so a rising rear zone is caught on-slope before a logged excursion
//  voids the cold-chain attestation and the cargo.
//
//  Nav: Shell + BottomNav (HOME · SHIPMENTS · [orb] · COMPLIANCE · ME), COMPLIANCE inked.
//
//  REAL WIRING (tRPC · server/routers/reeferTemp.ts):
//    · reeferTemp.getReadings     {loadId?, hours, limit} -> [{id, zone, tempF, tempC,
//        status, source, notes, recordedAt}]  (:107) — draws the three per-zone polylines.
//    · reeferTemp.getLatestByZone {loadId?} -> {front:{tempF,tempC,status,recordedAt},
//        center:{…}, rear:{…}}  (:149) — the live zone-status strip.
//    · reeferTemp.getStats        {loadId?, hours, targetMin, targetMax} -> {min, max, avg,
//        totalReadings, excursions}  (:457) — the band caption (readings / excursions).
//    · reeferTemp.getHourlyAvgs   {loadId?, hours} -> [{hour, avg}]  (:501) — "Hourly avgs".
//    · reeferTemp.recordFSMATemp  {loadId, temperature, unit, eventType} -> FSMA status
//        (:734 · mutation · writes a reading + FSMA attestation) — "Record FSMA temp".
//
//  STUB · named-gap (honest, per wireframe <desc>): reeferTemp is driver/admin-scoped by
//  reeferReadings.driverId; vessel-container reuse needs an {operatorId, containerId}
//  scope — flagged to the web team. For a vessel operator with no driver readings the
//  trace renders its honest empty state over the band (never extrapolated); Record needs
//  a bound sailing (loadId>0) or it surfaces the scope gap honestly.
//
//  RBAC: protectedProcedure. transportMode=vessel. COUNTRY-DONE: a temp-standard strip by
//  discharge market — US FDA FSMA 21 CFR 1.908 (33–40°F · active) / CA CFIA SFCR (0.5–4.4°C)
//  / MX COFEPRIS NOM-251 (0–4°C). NO mock data — the trace + zones derive from live rows;
//  the band + reference lines + standards are regulatory constants.
//

import SwiftUI

struct VesselReeferTempLogScreen: View {
    let theme: Theme.Palette
    /// Bound sailing/container the log scopes to. 0 = the operator's own readings
    /// (all loads); a specific booking is injected when opened from a sailing.
    var loadId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            VesselReeferTempLogBody(loadId: loadId)
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

private struct ReeferReading799: Decodable, Identifiable {
    let id: String
    let zone: String?
    let tempF: Double?
    let tempC: Double?
    let status: String?
    let recordedAt: String?
}

private struct ReeferZone799: Decodable {
    let tempF: Double?
    let tempC: Double?
    let status: String?
    let recordedAt: String?
}

private struct ReeferStats799: Decodable {
    let min: Double?
    let max: Double?
    let avg: Double?
    let totalReadings: Int?
    let excursions: Int?
}

private struct HourlyAvg799: Decodable, Identifiable {
    var id: Int { hour }
    let hour: Int
    let avg: Double?
}

// MARK: - Body

private struct VesselReeferTempLogBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.vesselOperatorNavHandler) private var navHandler
    let loadId: Int

    @State private var readings: [ReeferReading799] = []
    @State private var zones: [String: ReeferZone799] = [:]
    @State private var stats: ReeferStats799? = nil
    @State private var hourly: [HourlyAvg799] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    @State private var showRecorder = false
    @State private var recordTempText = ""
    @State private var recording = false
    @State private var recordAck: String? = nil
    @State private var recordError: String? = nil
    @State private var showHourly = false

    private let zoneOrder = ["front", "center", "rear"]
    private let ceilingF: Double = 40
    private let setpointF: Double = 34
    private let bandMinF: Double = 33
    private let bandMaxF: Double = 40

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
                        traceCard
                        zoneStrip
                        fsmaCaption
                        if showHourly { hourlyCard }
                        esangCard
                        if showRecorder { recorderCard }
                        ctaRow
                        standardStrip
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
                    Text("VESSEL OPERATOR · REEFER TEMP LOG")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                }
                Spacer()
                Text("FSMA").font(EType.mono(.micro)).tracking(0.8).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .center, spacing: Space.s3) {
                Button { navHandler?("Compliance") } label: {
                    Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }.buttonStyle(.plain)
                Text("Reefer temp log")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 17, weight: .bold)).foregroundStyle(palette.textPrimary)
            }
            .padding(.top, Space.s3)
        }
    }

    // MARK: Zone-temperature trace card (gradient-rim · band + 3 polylines)

    private var traceCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack {
                Text("ZONE TEMPERATURE · °F · 24H")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(Brand.success).frame(width: 5, height: 5)
                    Text("LIVE").font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(Brand.success)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Brand.success.opacity(0.14)))
            }

            if hasTrace {
                ZoneTraceChart799(
                    series: traceSeries, ceiling: ceilingF, setpoint: setpointF,
                    bandMin: bandMinF, bandMax: bandMaxF, yMin: 30, yMax: 42)
                    .frame(height: 200)
            } else {
                EusoEmptyState(systemImage: "thermometer.medium",
                               title: "No reefer telemetry",
                               subtitle: "The 24h zone trace draws once sensors report — vessel-container scope is a named gap; nothing is extrapolated.")
                    .frame(height: 200)
            }

            // Legend.
            HStack(spacing: Space.s4) {
                ForEach(zoneOrder, id: \.self) { z in
                    HStack(spacing: 5) {
                        Circle().fill(zoneColor(z)).frame(width: 8, height: 8)
                        Text("\(z.capitalized) \(latestZoneTempText(z))")
                            .font(.system(size: 10, weight: z == "rear" ? .heavy : .semibold))
                            .foregroundStyle(z == "rear" && rearWarn ? palette.textPrimary : palette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
    }

    // MARK: Zone status strip

    private var zoneStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ZONE STATUS · LIVE · DEVIATION FROM 34°F SETPOINT")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            HStack(spacing: Space.s2) {
                ForEach(zoneOrder, id: \.self) { z in zoneCell(z) }
            }
        }
    }

    private func zoneCell(_ z: String) -> some View {
        let temp = latestZoneF(z)
        let dev = temp.map { $0 - setpointF }
        let warn = (temp ?? 0) >= (bandMaxF - 2) && temp != nil
        let accent = zoneColor(z)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(z.uppercased()).font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(warn ? Brand.warning : palette.textTertiary)
                Spacer()
                Circle().fill(accent).frame(width: 5, height: 5)
            }
            Text(temp.map { String(format: "%.1f°F", $0) } ?? "—")
                .font(.system(size: 20, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(dev.map { String(format: "%+.1f dev", $0) } ?? "no reading")
                .font(.system(size: 9.5, weight: .heavy)).monospacedDigit()
                .foregroundStyle(warn ? Brand.danger : accent)
            Text(warn ? "WARN" : (temp != nil ? "IN RANGE" : "OFFLINE"))
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(warn ? Brand.warning : (temp != nil ? Brand.success : palette.textTertiary))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill((warn ? Brand.warning : (temp != nil ? Brand.success : palette.textTertiary)).opacity(0.18)))
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(warn ? Brand.warning.opacity(0.08) : palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(warn ? Brand.warning.opacity(0.5) : palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: FSMA caption

    private var fsmaCaption: some View {
        Text("FSMA 21 CFR 1.908 · band 33–40°F · \(stats?.totalReadings ?? readings.count) readings · \(stats?.excursions ?? 0) excursions / 24h")
            .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
    }

    // MARK: Hourly averages (toggle)

    private var hourlyCard: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("HOURLY AVERAGES · °F").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if hourly.isEmpty {
                Text("No hourly averages for this window.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(hourly) { h in
                        HStack {
                            Text(String(format: "%02d:00", h.hour))
                                .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                            Spacer()
                            Text(h.avg.map { String(format: "%.1f°F", $0) } ?? "—")
                                .font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: ESang airflow plan

    private var esangCard: some View {
        HStack(spacing: Space.s3) {
            OrbeSang(state: .idle, diameter: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text("ESANG · AIRFLOW PLAN").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
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

    // MARK: Record FSMA temp recorder

    private var recorderCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("RECORD FSMA TEMP · °F").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            if loadId <= 0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.warning)
                    Text("Open this log from a sailing to record an FSMA temp against its booking.")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
            } else {
                HStack(spacing: Space.s2) {
                    HStack(spacing: 2) {
                        TextField("38.0", text: $recordTempText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.textPrimary)
                        Text("°F").font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textSecondary)
                    }
                    .padding(.horizontal, Space.s3).padding(.vertical, Space.s2)
                    .background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    Button { Task { await recordTemp() } } label: {
                        HStack(spacing: 6) {
                            if recording { ProgressView().tint(.white).scaleEffect(0.8) }
                            Text(recording ? "Recording…" : "Record")
                                .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(LinearGradient.primary).clipShape(Capsule())
                    }
                    .buttonStyle(.plain).disabled(recording || Double(recordTempText) == nil)
                    .opacity(Double(recordTempText) == nil ? 0.6 : 1.0)
                }
            }
            if let ack = recordAck { Text(ack).font(EType.caption).foregroundStyle(Brand.success) }
            if let err = recordError { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
        }
        .padding(Space.s4)
        .background(palette.bgCardSoft)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: CTA row

    private var ctaRow: some View {
        HStack(spacing: Space.s2) {
            Button { withAnimation(.easeOut(duration: 0.18)) { showRecorder.toggle() } } label: {
                Text(showRecorder ? "Close recorder" : "Record FSMA temp")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary).clipShape(Capsule())
            }.buttonStyle(.plain)

            Button {
                withAnimation(.easeOut(duration: 0.18)) { showHourly.toggle() }
                if showHourly { Task { await loadHourly() } }
            } label: {
                Text("Hourly avgs").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(minWidth: 128, minHeight: 48).padding(.horizontal, Space.s3)
                    .background(palette.bgCard).overlay(Capsule().strokeBorder(palette.borderFaint)).clipShape(Capsule())
            }.buttonStyle(.plain)
        }
    }

    // MARK: Temp-standard strip (tri-country)

    private var standardStrip: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("TEMP STANDARD · BY DISCHARGE MARKET")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            HStack(spacing: 0) {
                standardCell("US · FDA FSMA", "33–40°F · active", active: true)
                Divider().frame(height: 30).overlay(palette.borderFaint)
                standardCell("CA · CFIA", "0.5–4.4°C", active: false)
                Divider().frame(height: 30).overlay(palette.borderFaint)
                standardCell("MX · COFEPRIS", "0–4°C frío", active: false)
            }
            .background(palette.bgCardSoft)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    private func standardCell(_ title: String, _ value: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 9, weight: .heavy)).foregroundStyle(active ? Brand.info : palette.textSecondary)
            Text(value).font(EType.mono(.micro)).foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
        }
        .padding(.horizontal, Space.s3).padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? Brand.info.opacity(0.12) : Color.clear)
    }

    // MARK: Loading / error

    private var loadingState: some View {
        VStack(spacing: Space.s3) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft).frame(height: 260)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft).frame(height: 90)
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

    // MARK: - Derived / helpers

    private var hasTrace: Bool { traceSeries.contains { $0.points.count >= 2 } }

    /// Per-zone time series, x normalized over the last 24h, y in °F.
    private var traceSeries: [ZoneSeries799] {
        let now = Date()
        let windowStart = now.addingTimeInterval(-24 * 3600)
        return zoneOrder.map { zone in
            let zr = readings
                .filter { ($0.zone ?? "").lowercased() == zone }
                .compactMap { r -> (Date, Double)? in
                    guard let f = tempFor(r) else { return nil }
                    let d = parseDate(r.recordedAt) ?? now
                    return (d, f)
                }
                .sorted { $0.0 < $1.0 }
            let pts = zr.map { (d, f) -> CGPoint in
                let x = CGFloat(max(0, min(1, d.timeIntervalSince(windowStart) / (24 * 3600))))
                return CGPoint(x: x, y: CGFloat(f))
            }
            return ZoneSeries799(color: zoneColor(zone), points: pts)
        }
    }

    private func tempFor(_ r: ReeferReading799) -> Double? {
        if let f = r.tempF, f != 0 { return f }
        if let c = r.tempC, c != 0 { return c * 9 / 5 + 32 }
        return r.tempF
    }
    private func latestZoneF(_ z: String) -> Double? {
        if let zr = zones[z] {
            if let f = zr.tempF, f != 0 { return f }
            if let c = zr.tempC, c != 0 { return c * 9 / 5 + 32 }
        }
        // Fall back to the most recent reading in that zone.
        let latest = readings.filter { ($0.zone ?? "").lowercased() == z }
            .sorted { (parseDate($0.recordedAt) ?? .distantPast) > (parseDate($1.recordedAt) ?? .distantPast) }
            .first
        return latest.flatMap(tempFor)
    }
    private func latestZoneTempText(_ z: String) -> String {
        latestZoneF(z).map { String(format: "%.1f°", $0) } ?? "—"
    }
    private var rearWarn: Bool { (latestZoneF("rear") ?? 0) >= bandMaxF - 2 }

    private var esangHeadline: String {
        if let rear = latestZoneF("rear"), rear >= bandMaxF - 2 {
            return "Rear zone \(String(format: "%.1f°F", rear)) — verify airflow now"
        }
        if !hasTrace { return "Awaiting live reefer telemetry to build an airflow plan" }
        return "Zones tracking within the FSMA band"
    }
    private var esangSub: String {
        if let rear = latestZoneF("rear"), rear >= bandMaxF - 2 {
            let head = String(format: "%.1f°F", bandMaxF - rear)
            return "\(head) to the 40°F ceiling · verify or claim before discharge"
        }
        return "band 33–40°F · \(stats?.excursions ?? 0) excursions logged this window"
    }

    private func zoneColor(_ z: String) -> Color {
        switch z {
        case "front": return Brand.success
        case "center": return Brand.info
        case "rear": return Brand.danger
        default: return palette.textSecondary
        }
    }

    private func parseDate(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    // MARK: - Actions

    private func load() async {
        loading = true; loadError = nil
        struct ReadingsIn: Encodable { let loadId: Int?; let hours: Int; let limit: Int }
        struct ZoneIn: Encodable { let loadId: Int? }
        struct StatsIn: Encodable { let loadId: Int?; let hours: Int; let targetMin: Double; let targetMax: Double }
        let lid: Int? = loadId > 0 ? loadId : nil
        do {
            async let rd: [ReeferReading799] = EusoTripAPI.shared.query(
                "reeferTemp.getReadings", input: ReadingsIn(loadId: lid, hours: 24, limit: 200))
            async let zn: [String: ReeferZone799] = EusoTripAPI.shared.query(
                "reeferTemp.getLatestByZone", input: ZoneIn(loadId: lid))
            async let st: ReeferStats799 = EusoTripAPI.shared.query(
                "reeferTemp.getStats", input: StatsIn(loadId: lid, hours: 24, targetMin: bandMinF, targetMax: bandMaxF))
            let (r, z, s) = try await (rd, zn, st)
            self.readings = r
            self.zones = z
            self.stats = s
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func loadHourly() async {
        struct HourlyIn: Encodable { let loadId: Int?; let hours: Int }
        let lid: Int? = loadId > 0 ? loadId : nil
        hourly = (try? await EusoTripAPI.shared.query(
            "reeferTemp.getHourlyAvgs", input: HourlyIn(loadId: lid, hours: 24))) ?? []
    }

    private func recordTemp() async {
        guard loadId > 0, let t = Double(recordTempText) else { return }
        recording = true; recordAck = nil; recordError = nil
        struct RecordIn: Encodable { let loadId: Int; let temperature: Double; let unit: String; let eventType: String }
        struct RecordOut: Decodable { let compliant: Bool? }
        do {
            let _: RecordOut = try await EusoTripAPI.shared.mutation(
                "reeferTemp.recordFSMATemp",
                input: RecordIn(loadId: loadId, temperature: t, unit: "F", eventType: "manual"))
            recordAck = "Recorded \(String(format: "%.1f°F", t)) · FSMA attestation signed."
            recordTempText = ""
            await load()
        } catch {
            recordError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        recording = false
    }
}

// MARK: - Zone trace chart

private struct ZoneSeries799 { let color: Color; let points: [CGPoint] }  // points: x in [0,1], y in °F

private struct ZoneTraceChart799: View {
    let series: [ZoneSeries799]
    let ceiling: Double
    let setpoint: Double
    let bandMin: Double
    let bandMax: Double
    let yMin: Double
    let yMax: Double
    @Environment(\.palette) private var palette

    private func yPos(_ t: Double, in h: CGFloat) -> CGFloat {
        let span = max(yMax - yMin, 0.001)
        return h - CGFloat((t - yMin) / span) * h
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                // FSMA band shading.
                Rectangle().fill(Brand.success.opacity(0.09))
                    .frame(height: max(0, yPos(bandMin, in: h) - yPos(bandMax, in: h)))
                    .position(x: w / 2, y: (yPos(bandMax, in: h) + yPos(bandMin, in: h)) / 2)
                // Ceiling (40°F, dashed red).
                dashLine(y: yPos(ceiling, in: h), w: w, color: Brand.danger.opacity(0.7), dash: [4, 3])
                Text("40°F · FSMA ceiling").font(.system(size: 8.5, weight: .heavy)).foregroundStyle(Brand.danger)
                    .position(x: 60, y: yPos(ceiling, in: h) - 8)
                // Setpoint (34°F, dashed blue).
                dashLine(y: yPos(setpoint, in: h), w: w, color: Brand.info.opacity(0.6), dash: [2, 3])
                Text("34°F setpoint").font(.system(size: 8.5, weight: .bold)).foregroundStyle(Brand.info)
                    .position(x: 48, y: yPos(setpoint, in: h) - 8)
                // Now marker.
                dashLine2(x: w, h: h, color: Brand.blue.opacity(0.4), dash: [2, 3])

                // Zone polylines.
                ForEach(Array(series.enumerated()), id: \.offset) { _, s in
                    if s.points.count >= 2 {
                        Path { p in
                            let pts = s.points.map { CGPoint(x: $0.x * w, y: yPos(Double($0.y), in: h)) }
                            p.move(to: pts[0])
                            for pt in pts.dropFirst() { p.addLine(to: pt) }
                        }
                        .stroke(s.color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        if let last = s.points.last {
                            Circle().fill(s.color).frame(width: 6, height: 6)
                                .position(x: last.x * w, y: yPos(Double(last.y), in: h))
                        }
                    }
                }
            }
        }
    }

    private func dashLine(y: CGFloat, w: CGFloat, color: Color, dash: [CGFloat]) -> some View {
        Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y)) }
            .stroke(color, style: StrokeStyle(lineWidth: 1.1, dash: dash))
    }
    private func dashLine2(x: CGFloat, h: CGFloat, color: Color, dash: [CGFloat]) -> some View {
        Path { p in p.move(to: CGPoint(x: x - 1, y: 0)); p.addLine(to: CGPoint(x: x - 1, y: h)) }
            .stroke(color, style: StrokeStyle(lineWidth: 1, dash: dash))
    }
}

#Preview("799 · Vessel Reefer Temp Log · Night") {
    VesselReeferTempLogScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("799 · Vessel Reefer Temp Log · Light") {
    VesselReeferTempLogScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
