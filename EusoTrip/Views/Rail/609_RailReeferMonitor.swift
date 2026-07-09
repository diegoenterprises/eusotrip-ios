//
//  609_RailReeferMonitor.swift
//  EusoTrip — Rail Engineer · Reefer Cold-Chain Monitoring (carrier-side).
//
//  Reconstructed from the stamped gauge+3KPI+3row skeleton into a purpose-built
//  TIME-SERIES archetype: a cargo-temperature STRIP CHART hero (last-6h trace
//  from real reefer readings, shaded FSMA 33–38°F safe band, dashed band-center
//  line, excursion dots + a live now-dot) over per-zone reading rows and an
//  acknowledgeable cold-chain alert ledger. The engineer reads the cold chain as
//  a live line inside the safe band — so an excursion is seen as the line leaving
//  the band, not a stale number.
//
//  Live wiring (reeferTemp router):
//   • strip-chart trace         → reeferTemp.getReadings (last 6h)
//   • per-zone current readings → reeferTemp.getLatestByZone (front/center/rear)
//   • cold-chain alert ledger   → reeferTemp.getAlerts
//   • per-alert "Acknowledge"   → reeferTemp.acknowledgeAlert (mutation)
//  Honest: no reefer readings → an honest empty trace/rows, never a fabricated
//  line. FSMA 21 CFR 1.908 safe band context; transportMode = rail.
//

import SwiftUI

struct RailReeferMonitorScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { RailReeferMonitorBody() } nav: {
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

// MARK: - Decodable models (match reeferTemp router return shapes exactly)

/// reeferTemp.getLatestByZone → Record<zone, { tempF, tempC, status, recordedAt }>
private struct ZoneReading609: Decodable {
    let tempF: Double?
    let tempC: Double?
    let status: String?
    let recordedAt: String?
}

/// reeferTemp.getReadings → [{ id, zone, tempF, tempC, status, source, notes, recordedAt }]
private struct Reading609: Decodable, Identifiable {
    let id: String
    let zone: String?
    let tempF: Double?
    let tempC: Double?
    let status: String?
    let source: String?
    let notes: String?
    let recordedAt: String?
}

/// reeferTemp.getAlerts → [{ id, severity, message, zone, tempF, acknowledged, createdAt }]
private struct Alert609: Decodable, Identifiable {
    let id: String
    let severity: String?
    let message: String?
    let zone: String?
    let tempF: Double?
    let acknowledged: Bool?
    let createdAt: String?
}

/// reeferTemp.acknowledgeAlert → { success }
private struct AckResult609: Decodable { let success: Bool? }

/// A plotted trace sample derived from a real reading (temp + parsed timestamp).
private struct TracePoint609: Identifiable {
    let id: String
    let t: Double       // epoch seconds
    let tempF: Double
    let inBand: Bool
}

// FSMA refrigerated safe band (21 CFR 1.908 context).
private let kFsmaMin: Double = 33
private let kFsmaMax: Double = 38

// MARK: - Body

private struct RailReeferMonitorBody: View {
    @Environment(\.palette) private var palette

    @State private var readings: [Reading609] = []
    @State private var zones: [String: ZoneReading609] = [:]
    @State private var alerts: [Alert609] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    // Acknowledge flow (inline, per-row).
    @State private var ackingId: String? = nil
    @State private var toast: String? = nil

    private let zoneOrder = ["front", "center", "rear"]

    // MARK: Derived

    private var orderedZones: [(String, ZoneReading609)] {
        zoneOrder.compactMap { key in zones[key].map { (key, $0) } }
    }

    private var zoneTemps: [Double] { orderedZones.compactMap { $0.1.tempF } }

    private var avgNow: Double? {
        zoneTemps.isEmpty ? nil : zoneTemps.reduce(0, +) / Double(zoneTemps.count)
    }

    private var inBandCount: Int {
        zoneTemps.filter { $0 >= kFsmaMin && $0 <= kFsmaMax }.count
    }

    private var unackedCount: Int {
        alerts.filter { !($0.acknowledged ?? false) }.count
    }

    /// Real readings → ascending-by-time trace samples for the strip chart.
    private var tracePoints: [TracePoint609] {
        readings.compactMap { r -> TracePoint609? in
            guard let temp = r.tempF, let iso = r.recordedAt, let t = Self.epochSeconds(iso) else { return nil }
            return TracePoint609(id: r.id, t: t, tempF: temp, inBand: temp >= kFsmaMin && temp <= kFsmaMax)
        }.sorted { $0.t < $1.t }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                headline
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Loading cold-chain telemetry…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    traceHero
                    kpiStrip
                    zoneSection
                    alertSection
                    CTAButton(title: "FSMA cold-chain log", leadingIcon: "checkmark.seal")
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
        .overlay(alignment: .bottom) { toastView }
    }

    // MARK: Eyebrow + headline

    private var eyebrow: some View {
        HStack(spacing: 6) {
            Image(systemName: "thermometer.snowflake").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            Text("RAIL ENGINEER · REEFER COLD-CHAIN").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
        }
    }

    private var headline: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Reefer monitor")
                .font(.system(size: 28, weight: .heavy)).kerning(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Trace hero — last-6h cargo temperature inside the FSMA safe band

    private var traceHero: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard)
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5)

            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("COLD-CHAIN TRACE")
                        .font(.system(size: 10, weight: .heavy)).kerning(0.6)
                        .foregroundStyle(palette.textTertiary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(palette.textTertiary.opacity(0.10)))
                    Spacer()
                    Text("FSMA safe 33–38°F")
                        .font(.system(size: 11, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(Brand.success)
                }
                ReeferTraceChart609(points: tracePoints, palette: palette)
                    .frame(height: 112)
                    .overlay {
                        if tracePoints.isEmpty {
                            Text("No trace in the last 6h")
                                .font(EType.caption).foregroundStyle(palette.textTertiary)
                        }
                    }
                HStack {
                    Text("6h ago").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    Spacer()
                    if let last = tracePoints.last {
                        Text("now \(fmtTemp(last.tempF))°F")
                            .font(.system(size: 12, weight: .heavy)).monospacedDigit()
                            .foregroundStyle(last.inBand ? Brand.success : Brand.danger)
                    } else {
                        Text("awaiting telemetry").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.textTertiary)
                    }
                }
            }
            .padding(Space.s4)
        }
        .frame(height: 196)
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            MetricTile(label: "AVG °F", value: avgNow != nil ? fmtTemp(avgNow!) : "—", gradientNumeral: true)
            MetricTile(label: "IN BAND", value: "\(inBandCount)/\(zoneTemps.count)", accent: (zoneTemps.isEmpty || inBandCount == zoneTemps.count) ? Brand.success : Brand.warning)
            MetricTile(label: "ALERTS", value: "\(unackedCount)", accent: unackedCount > 0 ? Brand.danger : Brand.success)
        }
    }

    // MARK: Zone section

    private var zoneSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            Text("ZONE READINGS · live cold-chain")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
            if orderedZones.isEmpty {
                LifecycleCard { Text("No zone readings yet. Telemetry appears as the reefer reports in.").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(orderedZones, id: \.0) { pair in zoneRow(pair.0, pair.1) }
                }
            }
        }
    }

    private func zoneRow(_ key: String, _ z: ZoneReading609) -> some View {
        let color = bandColor(z.tempF, status: z.status)
        let label = bandLabel(z.tempF, status: z.status)
        let stamp = Self.clock(z.recordedAt)
        return HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(color.opacity(0.14)).frame(width: 40, height: 40)
                Image(systemName: "thermometer.medium").font(.system(size: 16, weight: .bold)).foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(key.capitalized) zone")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(stamp.isEmpty ? "no timestamp" : "updated \(stamp)")
                    .font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(z.tempF != nil ? "\(fmtTemp(z.tempF!))°F" : "—")
                    .font(.system(size: 16, weight: .heavy)).monospacedDigit().foregroundStyle(color)
                Text(label)
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(color.opacity(0.14)))
            }
        }
        .padding(Space.s3)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: Alert section

    private var alertSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("COLD-CHAIN ALERTS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                if unackedCount > 0 {
                    Text("\(unackedCount) OPEN")
                        .font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.danger)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Brand.danger.opacity(0.14)))
                }
            }
            if alerts.isEmpty {
                LifecycleCard { Text("No cold-chain alerts. The chain is holding inside the FSMA band.").font(EType.caption).foregroundStyle(palette.textSecondary) }
            } else {
                VStack(spacing: Space.s2) {
                    ForEach(alerts) { a in alertRow(a) }
                }
            }
        }
    }

    private func alertRow(_ a: Alert609) -> some View {
        let color = severityColor(a.severity)
        let acked = a.acknowledged ?? false
        let stamp = Self.clock(a.createdAt)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Space.s3) {
                Image(systemName: acked ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(acked ? Brand.success : color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(a.message ?? "Cold-chain alert")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(2)
                    HStack(spacing: 6) {
                        if let zone = a.zone { Text(zone.capitalized).font(EType.caption).foregroundStyle(palette.textTertiary) }
                        if let t = a.tempF { Text("· \(fmtTemp(t))°F").font(EType.caption).foregroundStyle(color) }
                        if !stamp.isEmpty { Text("· \(stamp)").font(EType.caption).foregroundStyle(palette.textTertiary) }
                    }
                }
                Spacer()
            }
            HStack {
                Text((a.severity ?? "info").uppercased())
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(color.opacity(0.14)))
                Spacer()
                if acked {
                    Text("ACKNOWLEDGED")
                        .font(.system(size: 10, weight: .heavy)).foregroundStyle(Brand.success)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Brand.success.opacity(0.14)))
                } else {
                    Button {
                        Task { await acknowledge(a) }
                    } label: {
                        HStack(spacing: 5) {
                            if ackingId == a.id {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy))
                            }
                            Text("Acknowledge").font(.system(size: 11, weight: .heavy))
                        }
                        .foregroundStyle(color)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Capsule().fill(color.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                    .disabled(ackingId != nil)
                }
            }
        }
        .padding(Space.s3)
        .background(acked ? palette.bgCard : color.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(acked ? palette.borderFaint : color.opacity(0.30))
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private var toastView: some View {
        Group {
            if let t = toast {
                Text(t)
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Brand.success))
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: Band classification

    private func bandColor(_ temp: Double?, status: String?) -> Color {
        guard let t = temp else { return palette.textTertiary }
        if t > kFsmaMax || t < kFsmaMin || status == "critical" { return Brand.danger }
        if t > (kFsmaMax - 2) || status == "warning" { return Brand.warning }
        return Brand.success
    }

    private func bandLabel(_ temp: Double?, status: String?) -> String {
        guard let t = temp else { return "NO DATA" }
        if t > kFsmaMax || t < kFsmaMin || status == "critical" { return "EXCURSION" }
        if t > (kFsmaMax - 2) || status == "warning" { return "WARNING" }
        return "IN BAND"
    }

    private func severityColor(_ s: String?) -> Color {
        switch (s ?? "").lowercased() {
        case "critical": return Brand.danger
        case "warning":  return Brand.warning
        default:         return Brand.info
        }
    }

    private func fmtTemp(_ v: Double) -> String { String(format: "%.1f", v) }

    // MARK: Timestamp helpers

    private static func epochSeconds(_ iso: String) -> Double? {
        let withFrac = ISO8601DateFormatter(); withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: iso) { return d.timeIntervalSince1970 }
        let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: iso) { return d.timeIntervalSince1970 }
        return nil
    }

    private static func clock(_ iso: String?) -> String {
        guard let iso, let secs = epochSeconds(iso) else { return "" }
        let d = Date(timeIntervalSince1970: secs)
        let fmt = DateFormatter(); fmt.dateFormat = "h:mm a"
        return fmt.string(from: d)
    }

    // MARK: Data

    private func load() async {
        loading = true; loadError = nil
        struct Empty: Encodable {}
        struct ReadingsInput: Encodable { let hours: Int; let limit: Int }
        struct AlertsInput: Encodable { let limit: Int }
        do {
            async let zonesR: [String: ZoneReading609] = EusoTripAPI.shared.query("reeferTemp.getLatestByZone", input: Empty())
            async let readingsR: [Reading609]          = EusoTripAPI.shared.query("reeferTemp.getReadings", input: ReadingsInput(hours: 6, limit: 200))
            async let alertsR: [Alert609]              = EusoTripAPI.shared.query("reeferTemp.getAlerts", input: AlertsInput(limit: 20))
            self.zones    = try await zonesR
            self.readings = try await readingsR
            self.alerts   = try await alertsR
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func acknowledge(_ alert: Alert609) async {
        struct AckInput: Encodable { let alertId: Int }
        guard let aid = Int(alert.id) else { return }
        ackingId = alert.id
        do {
            let _: AckResult609 = try await EusoTripAPI.shared.mutation(
                "reeferTemp.acknowledgeAlert",
                input: AckInput(alertId: aid)
            )
            withAnimation(.easeOut(duration: 0.18)) { toast = "Alert acknowledged" }
            await load()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeOut(duration: 0.18)) { toast = nil }
        } catch {
            withAnimation(.easeOut(duration: 0.18)) { toast = (error as? EusoTripAPIError)?.errorDescription ?? "Acknowledge failed" }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeOut(duration: 0.18)) { toast = nil }
        }
        ackingId = nil
    }
}

// MARK: - Reefer strip chart (cargo temperature over the last 6h)
//
// A cargo-temperature trace drawn from real reeferTemp readings, laid over the
// shaded FSMA 33–38°F safe band with a dashed band-center reference line. Points
// that fall outside the band render as danger dots (excursion markers); the
// latest reading carries a live now-dot coloured by whether it is in-band. The
// line draws on appear (trim 0→1) with a decelerating ease; Reduce Motion snaps
// it straight to full. Honest: an empty series renders just the band — never a
// fabricated line.
private struct ReeferTraceChart609: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let points: [TracePoint609]
    let palette: Theme.Palette
    @State private var drawn: CGFloat = 0

    // Geometry math hoisted to methods (never local funcs inside the ViewBuilder).
    private func xFor(_ t: Double, tMin: Double, tMax: Double, w: CGFloat) -> CGFloat {
        let span = tMax - tMin
        return span > 0 ? CGFloat((t - tMin) / span) * w : w
    }

    private func yFor(_ temp: Double, lo: Double, hi: Double, h: CGFloat) -> CGFloat {
        let span = hi - lo
        let frac = span > 0 ? (temp - lo) / span : 0.5
        return h - CGFloat(frac) * h
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let sorted = points
            let temps = sorted.map { $0.tempF }
            let dataMin = temps.min() ?? kFsmaMin
            let dataMax = temps.max() ?? kFsmaMax
            let lo = min(kFsmaMin - 2, dataMin - 2)
            let hi = max(kFsmaMax + 2, dataMax + 2)
            let tMin = sorted.first?.t ?? 0
            let tMax = sorted.last?.t ?? 1
            let bandTop = yFor(kFsmaMax, lo: lo, hi: hi, h: h)
            let bandBot = yFor(kFsmaMin, lo: lo, hi: hi, h: h)
            let centerY = yFor((kFsmaMin + kFsmaMax) / 2, lo: lo, hi: hi, h: h)

            ZStack {
                // Shaded FSMA safe band
                Path { p in p.addRect(CGRect(x: 0, y: bandTop, width: w, height: max(0, bandBot - bandTop))) }
                    .fill(Brand.success.opacity(0.12))
                // Band edges
                Path { p in
                    p.move(to: CGPoint(x: 0, y: bandTop)); p.addLine(to: CGPoint(x: w, y: bandTop))
                    p.move(to: CGPoint(x: 0, y: bandBot)); p.addLine(to: CGPoint(x: w, y: bandBot))
                }
                .stroke(Brand.success.opacity(0.35), lineWidth: 1)
                // Dashed band-center reference
                Path { p in p.move(to: CGPoint(x: 0, y: centerY)); p.addLine(to: CGPoint(x: w, y: centerY)) }
                    .stroke(palette.textTertiary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                // Trace line
                if sorted.count >= 2 {
                    Path { p in
                        for (i, pt) in sorted.enumerated() {
                            let x = xFor(pt.t, tMin: tMin, tMax: tMax, w: w)
                            let y = yFor(pt.tempF, lo: lo, hi: hi, h: h)
                            if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .trim(from: 0, to: drawn)
                    .stroke(Brand.info, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                }

                // Excursion markers (out-of-band samples)
                ForEach(sorted.filter { !$0.inBand }) { pt in
                    Circle().fill(Brand.danger).frame(width: 7, height: 7)
                        .position(x: xFor(pt.t, tMin: tMin, tMax: tMax, w: w),
                                  y: yFor(pt.tempF, lo: lo, hi: hi, h: h))
                }

                // Live now-dot (latest reading)
                if let last = sorted.last {
                    Circle().fill(last.inBand ? Brand.success : Brand.danger)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().strokeBorder(palette.bgCard, lineWidth: 2))
                        .position(x: xFor(last.t, tMin: tMin, tMax: tMax, w: w),
                                  y: yFor(last.tempF, lo: lo, hi: hi, h: h))
                }
            }
            .onAppear {
                if reduceMotion { drawn = 1 }
                else { withAnimation(.easeOut(duration: 0.6)) { drawn = 1 } }
            }
        }
    }
}

#Preview("609 · Rail Reefer Monitor · Night") { RailReeferMonitorScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("609 · Rail Reefer Monitor · Light") { RailReeferMonitorScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
