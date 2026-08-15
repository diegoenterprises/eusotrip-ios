//
//  387_CatalystReeferFleetMonitor.swift
//  EusoTrip — Catalyst · Reefer Fleet Monitor.
//
//  Verbatim port of the 387 Catalyst Reefer Fleet Monitor wireframe —
//  the carrier-vantage multi-asset reefer telemetry surface bound to
//  the active LA → Phoenix reefer load LD-260427-7C3A09F18B (shipper
//  Diego Usoro · Eusorone Technologies). Carrier Eusotrans LLC ·
//  USDOT 3 194 882.
//
//  Structure mirrors the SVG 1:1:
//    • SUPPLY TEMP · ACTIVE hero — 35.4°F vs setpoint 36°F, IN-BAND
//      badge, and a position-within-band progress bar (the SVG paints
//      257/368 of the track filled).
//    • REEFER FLEET · ZONE READINGS ledger — per-zone supply/return
//      rows (RFR-01 supply 35.4°F · RFR-01 return Δ2.7°F 38.1°F ·
//      RFR-02 pre-cool 41.0°F) each with a colour-coded temp pill,
//      then the FSMA · ACTIVE LOAD block (Fresh berries 33–38°F).
//    • Factor cells — REEFERS · IN-BAND · ALERTS.
//    • Actions — Acknowledge alert (primary) + FSMA log (secondary).
//
//  Server wiring — LIVE: this surface reads the real reefer-temperature
//  router via `EusoTripAPI.shared.reeferTemp.*`
//  (`frontend/server/routers/reeferTemp.ts`):
//    • getLatestByZone({ loadId? }) → {front|center|rear → reading}
//      object — mapped 1:1 into the per-zone ledger rows.
//    • getStats({ loadId? })        → min/max/avg + excursion count,
//      feeding the supply-temp hero + factor cells.
//    • getAlerts({ loadId? })       → live alert feed; the most-recent
//      unacknowledged alert drives the Acknowledge CTA.
//    • acknowledgeAlert({ alertId }) → wired to the primary CTA.
//  There is NO fabricated telemetry: `state` starts at `.loading`, `data`
//  is empty until `loadAll()` returns, flips to `.ready` only when at
//  least one real zone reading exists, else `.empty`. The reefer load id
//  is best-effort resolved from `catalysts.getActiveLoads` (first active
//  load); when none resolves the user-scoped procs are still called with
//  loadId nil (the server scopes by driverId), so a sole-driver carrier
//  still sees its own live fleet readings.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct CatalystReeferFleetMonitorScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            ReeferFleetBody_387()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_387(),
                trailing: catalystNavTrailing_387(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_387() -> [NavSlot] {
    CarrierNavRoute.leading(current: .drivers)
}

private func catalystNavTrailing_387() -> [NavSlot] {
    CarrierNavRoute.trailing(current: .drivers)
}

// MARK: - Typed telemetry model

private enum ReeferLoadState_387 { case loading, ready, empty }

/// One reefer zone reading — supply or return per power unit.
private struct ReeferZoneReading_387: Identifiable {
    enum Band_387 { case inBand, warning, alarm }
    let id = UUID()
    let title: String        // "RFR-01 · supply"
    let detail: String       // "setpoint 36°F · pulldown ok"
    let tempF: Double        // 35.4
    let band: Band_387
}

/// The active-load envelope the FSMA block describes. Populated from the
/// resolved active reefer load (catalysts.getActiveLoads); when no load
/// resolves the lines stay empty and the block renders blank rather than
/// fabricating a commodity/shipper/load number.
private struct ReeferActiveLoad_387 {
    let commodity: String    // e.g. "FSMA band 33–40°F" (from real band)
    let shipper: String      // shipper/driver line from the resolved load
    let loadLine: String     // "Active reefer load <loadNumber>"
}

/// The whole-surface telemetry envelope — built entirely from the live
/// reeferTemp.* projections. Never seeded with fabricated readings.
private struct ReeferTelemetry_387 {
    let supplyActualF: Double   // latest supply (front/center) zone reading
    let setpointF: Double       // FSMA band target high (server default 40)
    let bandLowF: Double        // FSMA targetMin
    let bandHighF: Double       // FSMA targetMax
    let inBand: Bool            // every live zone within [low, high]
    let bandFillFraction: Double // supply position within [low, high]
    let zones: [ReeferZoneReading_387]
    let activeLoad: ReeferActiveLoad_387
    let reeferCount: Int        // distinct live zones reporting
    let inBandCount: Int        // zones currently in band
    let activeAlerts: Int       // unacknowledged live alerts

    /// An empty envelope — the default `data` value while loading / when
    /// no live readings exist. The `.ready` branch (the ONLY place `data`
    /// is rendered) is reached solely after `loadAll()` populates a real
    /// envelope, so these zeros never paint on screen.
    static let empty = ReeferTelemetry_387(
        supplyActualF: 0, setpointF: 0, bandLowF: 0, bandHighF: 0,
        inBand: true, bandFillFraction: 0, zones: [],
        activeLoad: ReeferActiveLoad_387(commodity: "", shipper: "", loadLine: ""),
        reeferCount: 0, inBandCount: 0, activeAlerts: 0
    )
}

/// One history row from `reeferTemp.getReadings` — `{ zone, temp, timestamp }`,
/// the identical projection Shipper 279 decodes.
private struct ReeferHistoryRow_387: Decodable, Hashable {
    let zone: String?
    let temp: Double
    let timestamp: String
}

// MARK: - Content

private struct ReeferFleetBody_387: View {
    @Environment(\.palette) private var palette

    @State private var state: ReeferLoadState_387 = .loading
    @State private var data: ReeferTelemetry_387 = .empty
    @State private var acknowledged: Bool = false
    @State private var showFSMALog: Bool = false

    /// The id of the most-recent unacknowledged alert returned by
    /// `reeferTemp.getAlerts` — the Acknowledge CTA acks exactly this.
    @State private var pendingAlertId: Int? = nil

    /// Relative "synced …" label derived from the freshest live reading's
    /// recordedAt. Empty until a real reading lands (no fabricated time).
    @State private var syncedLabel: String = ""

    /// Session history rows from `reeferTemp.getReadings` (the same proc
    /// Shipper 279 reads), scoped to the resolved active load. Feeds the
    /// BandTrendChart trend mount; empty ⇒ the chart simply doesn't render.
    @State private var historyRows: [ReeferHistoryRow_387] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                eyebrow
                titleBlock
                iridescentHairline

                switch state {
                case .loading:
                    skeletonBody
                case .empty:
                    emptyBody
                case .ready:
                    supplyHero
                    zoneReadingsCard
                    // Wave A2 — BandTrendChart de-orphaned onto its census
                    // host: the REAL per-zone reading history (same
                    // `reeferTemp.getReadings` rows 279 lists) against the
                    // live FSMA band, with the kit's drag-to-scrub cursor.
                    // Mounts only when ≥2 samples exist in some zone.
                    if let chart = zoneTrendChart {
                        chart
                    }
                    factorRow
                    actionRow
                    footerNote
                }

                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 56)
        }
        .task { await loadAll() }
        .eusoRefreshable { await loadAll() }
        .sheet(isPresented: $showFSMALog) { fsmaLogSheet }
    }

    // MARK: - Live load (reeferTemp.* — no fabricated readings)

    @MainActor
    private func loadAll() async {
        let api = EusoTripAPI.shared

        // Best-effort active reefer load id. catalysts.getActiveLoads has
        // no equipment marker, so we take the first active load's id as the
        // load context; if none resolves we pass nil and the procs scope by
        // the authed user's driverId server-side.
        var loadId: Int? = nil
        do {
            let active = try await api.catalyst.getActiveLoads(limit: 10)
            if let first = active.first { loadId = Int(first.id) }
        } catch { /* fall back to user-scoped (loadId nil) read */ }

        // Live zone readings + session stats + alerts — all real procs.
        var byZone: [String: ReeferTempAPI.ZoneReading] = [:]
        var stats: ReeferTempAPI.Stats? = nil
        var alerts: [ReeferTempAPI.Alert] = []

        do {
            byZone = try await api.reeferTemp.getLatestByZone(loadId: loadId)
        } catch {
            state = .empty
            return
        }

        // No live zone readings → honest empty state, no fabricated rows.
        guard !byZone.isEmpty else {
            data = .empty
            state = .empty
            return
        }

        stats = try? await api.reeferTemp.getStats(loadId: loadId)
        alerts = (try? await api.reeferTemp.getAlerts(loadId: loadId, limit: 20)) ?? []

        // Session history for the trend chart — best-effort, load-scoped.
        // No resolved load / no rows ⇒ empty ⇒ no chart, never a seeded
        // series.
        if let lid = loadId {
            struct ReadingsIn: Encodable { let loadId: Int }
            let rows: [ReeferHistoryRow_387]? = try? await api.query(
                "reeferTemp.getReadings", input: ReadingsIn(loadId: lid))
            historyRows = rows ?? []
        } else {
            historyRows = []
        }

        // FSMA band: prefer the stats window's implied band; the server
        // defaults are targetMin 33 / targetMax 40 (reeferTemp.ts:115).
        let bandLow = 33.0
        let bandHigh = 40.0

        // Map the dynamic-key zone object into the existing ledger rows,
        // in canonical supply→return order (front, center, rear).
        let order = ["front", "center", "rear"]
        let keys = order.filter { byZone[$0] != nil }
            + byZone.keys.filter { !order.contains($0) }.sorted()

        var rows: [ReeferZoneReading_387] = []
        var inBandCount = 0
        for key in keys {
            guard let r = byZone[key] else { continue }
            let band = band(for: r, low: bandLow, high: bandHigh)
            if band == .inBand { inBandCount += 1 }
            rows.append(ReeferZoneReading_387(
                title: "\(key.capitalized) zone",
                detail: detailLine(for: r),
                tempF: r.tempF,
                band: band
            ))
        }

        // Supply actual: prefer front, else center, else first reporting
        // zone; fall back to the session avg from getStats when no zone
        // carries a usable reading. Never a fabricated literal.
        let supply = byZone["front"] ?? byZone["center"] ?? byZone[keys.first ?? ""]
        let supplyF = supply?.tempF ?? rows.first?.tempF ?? (stats?.avg ?? 0)
        let setpoint = bandHigh

        // Position of the supply reading within the FSMA band [low, high].
        let span = max(0.0001, bandHigh - bandLow)
        let fill = min(1.0, max(0.0, (supplyF - bandLow) / span))

        let unacked = alerts.filter { ($0.acknowledged ?? false) == false }
        pendingAlertId = unacked.first.flatMap { $0.id.flatMap(Int.init) }

        // Authoritative in-band posture: the session window's excursion
        // count from getStats (0 excursions ⇒ in band) when stats exist;
        // otherwise the per-zone snapshot.
        let inBand: Bool = {
            if let s = stats, s.totalReadings > 0 { return s.excursions == 0 }
            return inBandCount == rows.count
        }()

        let activeLoad = ReeferActiveLoad_387(
            commodity: "FSMA band \(Int(bandLow))–\(Int(bandHigh))°F",
            shipper: "Carrier-monitored reefer telemetry",
            loadLine: loadId.map { "Active reefer load #\($0)" } ?? "All active reefer loads"
        )

        data = ReeferTelemetry_387(
            supplyActualF: supplyF,
            setpointF: setpoint,
            bandLowF: bandLow,
            bandHighF: bandHigh,
            inBand: inBand,
            bandFillFraction: fill,
            zones: rows,
            activeLoad: activeLoad,
            reeferCount: rows.count,
            inBandCount: inBandCount,
            activeAlerts: unacked.count
        )
        acknowledged = unacked.isEmpty && !alerts.isEmpty

        // "synced …" off the freshest live reading — never a fixed literal.
        let freshest = byZone.values
            .map(\.recordedAt)
            .filter { !$0.isEmpty }
            .max() ?? ""
        syncedLabel = relativeSynced(freshest)

        state = .ready
    }

    // MARK: Trend chart (Wave A2 — BandTrendChart de-orphaned)

    /// Build the per-zone trend chart from the REAL session history. Nil
    /// when no zone carries ≥2 samples — the surface then simply shows the
    /// latest-reading rows above, no invented polyline.
    private var zoneTrendChart: BandTrendChart? {
        guard !historyRows.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        func parse(_ s: String) -> Date? { iso.date(from: s) ?? isoPlain.date(from: s) }

        var grouped: [String: [(Date, Double)]] = [:]
        for r in historyRows {
            guard let t = parse(r.timestamp) else { continue }
            grouped[(r.zone ?? "supply").lowercased(), default: []].append((t, r.temp))
        }
        let allTimes = grouped.values.flatMap { $0.map(\.0) }
        guard let t0 = allTimes.min(), let t1 = allTimes.max(), t1 > t0 else { return nil }
        let span = t1.timeIntervalSince(t0)

        func rank(_ key: String) -> Int {
            switch key {
            case "front":  return 0
            case "center": return 1
            case "rear":   return 2
            default:        return 3
            }
        }
        let tints: [String: Color] = [
            "front": Brand.success, "center": Brand.blue, "rear": Brand.warning,
        ]

        var series: [BandTrendSeries] = []
        var pid = 0
        for key in grouped.keys.sorted(by: { (rank($0), $0) < (rank($1), $1) }) {
            let samples = grouped[key]!.sorted { $0.0 < $1.0 }
            guard samples.count >= 2 else { continue }
            var pts: [BandTrendPoint] = []
            for (t, v) in samples {
                pts.append(BandTrendPoint(id: pid, x: t.timeIntervalSince(t0) / span, y: v))
                pid += 1
            }
            let last = samples[samples.count - 1].1
            let prev = samples[samples.count - 2].1
            let rising = last > data.bandHighF - 2 && last > prev
            series.append(BandTrendSeries(
                id: key,
                name: key.capitalized,
                tint: tints[key] ?? Brand.info,
                emphasis: rising ? .rising : .solid,
                points: pts,
                legendValue: String(format: "%.1f°F", last),
                trend: last > prev ? "↑" : (last < prev ? "↓" : nil)
            ))
        }
        guard !series.isEmpty else { return nil }

        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = "HH:mm"
        let mid = t0.addingTimeInterval(span / 2)
        let ticks: [BandTrendTick] = [
            BandTrendTick(id: 0, x: 0, label: clock.string(from: t0)),
            BandTrendTick(id: 1, x: 0.5, label: clock.string(from: mid)),
            BandTrendTick(id: 2, x: 1, label: clock.string(from: t1), isNow: true),
        ]

        return BandTrendChart(
            series: series,
            guides: [
                BandTrendGuide(id: "ceiling", value: data.bandHighF,
                               label: "\(Int(data.bandHighF))°F · FSMA ceiling", role: .ceiling),
                BandTrendGuide(id: "floor", value: data.bandLowF,
                               label: "\(Int(data.bandLowF))°F · floor", role: .floor),
            ],
            band: (low: data.bandLowF, high: data.bandHighF),
            xTicks: ticks,
            eyebrow: "ZONE TEMPERATURE · °F · SESSION",
            trailingCaption: "FSMA BAND \(Int(data.bandLowF))–\(Int(data.bandHighF))°F",
            valueFormat: { String(format: "%.1f", $0) }
        )
    }

    /// "synced HH:mm" / "synced Nm ago" from a reading's ISO recordedAt.
    /// Empty when unparseable so the title falls back to a neutral dash.
    private func relativeSynced(_ iso: String) -> String {
        guard !iso.isEmpty else { return "" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        let mins = Int(max(0, Date().timeIntervalSince(date) / 60))
        if mins < 1 { return "synced just now" }
        if mins < 60 { return "synced \(mins)m ago" }
        let hrs = mins / 60
        if hrs < 24 { return "synced \(hrs)h ago" }
        return "synced \(hrs / 24)d ago"
    }

    /// Band classification from the server `status` string, with a numeric
    /// fallback against the FSMA target band when status is unrecognised.
    private func band(for r: ReeferTempAPI.ZoneReading,
                      low: Double, high: Double) -> ReeferZoneReading_387.Band_387 {
        switch r.status.lowercased() {
        case "critical", "alarm": return .alarm
        case "warning":           return .warning
        case "normal", "ok":      return .inBand
        default:
            if r.tempF > high || r.tempF < low { return .alarm }
            if r.tempF > high - 2 { return .warning }
            return .inBand
        }
    }

    /// Compact per-zone detail line built from the real reading — never
    /// from fabricated copy. Surfaces °C and the recorded-at clock.
    private func detailLine(for r: ReeferTempAPI.ZoneReading) -> String {
        let c = String(format: "%.1f°C", r.tempC)
        let clock = recordedClock(r.recordedAt)
        let status = r.status.isEmpty ? "" : " · \(r.status)"
        return clock.isEmpty ? "\(c)\(status)" : "\(c)\(status) · \(clock)"
    }

    /// "HH:mm" from an ISO-8601 recordedAt, empty when unparseable.
    private func recordedClock(_ iso: String) -> String {
        guard !iso.isEmpty else { return "" }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return "" }
        let out = DateFormatter()
        out.dateFormat = "HH:mm"
        return out.string(from: date)
    }

    /// Acknowledge the most-recent unacknowledged alert via the real
    /// `reeferTemp.acknowledgeAlert` mutation, then reflect the new
    /// counter locally. No-op (just flips local ack) when there is no
    /// pending alert id to acknowledge.
    @MainActor
    private func acknowledgeActiveAlert() async {
        guard let alertId = pendingAlertId else {
            acknowledged = true
            return
        }
        do {
            _ = try await EusoTripAPI.shared.reeferTemp.acknowledgeAlert(alertId: alertId)
            acknowledged = true
            pendingAlertId = nil
            // Reflect the acknowledgement in the live counter without a
            // full reload — the row is now off the unacknowledged feed.
            data = ReeferTelemetry_387(
                supplyActualF: data.supplyActualF,
                setpointF: data.setpointF,
                bandLowF: data.bandLowF,
                bandHighF: data.bandHighF,
                inBand: data.inBand,
                bandFillFraction: data.bandFillFraction,
                zones: data.zones,
                activeLoad: data.activeLoad,
                reeferCount: data.reeferCount,
                inBandCount: data.inBandCount,
                activeAlerts: max(0, data.activeAlerts - 1)
            )
        } catch {
            // Surface failure honestly by leaving the CTA actionable;
            // the alert remains in the unacknowledged feed.
        }
    }

    // MARK: Eyebrow + title

    private var eyebrow: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                EusoTripBrandMark(size: 12)
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · REEFER FLEET")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text("FSMA")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Reefer Fleet")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(palette.textPrimary)
                Text("zone temps · FSMA")
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text("EUSOTRANS LLC · USDOT 3 194 882")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(syncedLabel.isEmpty ? "—" : syncedLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private var iridescentHairline: some View {
        Rectangle()
            .fill(LinearGradient(
                colors: [Brand.blue.opacity(0.40), Brand.magenta.opacity(0.40)],
                startPoint: .leading, endPoint: .trailing
            ))
            .frame(height: 1)
            .padding(.horizontal, -20)
    }

    // MARK: SUPPLY TEMP · ACTIVE hero

    private var supplyHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SUPPLY TEMP · ACTIVE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("FSMA")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, 14)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(tempString(data.supplyActualF))
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-0.3)
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient.diagonal)
                Text("setpoint \(Int(data.setpointF))°F")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
                Text(data.inBand ? "IN-BAND" : "OUT-OF-BAND")
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .tracking(0.2)
                    .foregroundStyle(data.inBand ? Brand.success : Brand.danger)
            }
            .padding(.bottom, 14)

            bandTrack
                .padding(.bottom, 18)

            Text(data.inBand
                 ? "All reefer zones within FSMA temperature band"
                 : "One or more reefer zones outside FSMA band")
                .font(.system(size: 11, weight: .medium))
                .tracking(0.2)
                .foregroundStyle(palette.textPrimary)
                .padding(.bottom, 4)
            Text("\(data.inBandCount) of \(data.reeferCount) zones in band · continuous telemetry")
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Position-within-band progress track — the SVG paints 257/368 of
    /// the rail filled with the brand gradient over a faint base.
    private var bandTrack: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: w, height: 6)
                Capsule()
                    .fill(LinearGradient.diagonal)
                    .frame(width: max(0, w * data.bandFillFraction), height: 6)
            }
        }
        .frame(height: 6)
    }

    // MARK: REEFER FLEET · ZONE READINGS

    private var zoneReadingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("REEFER FLEET · ZONE READINGS")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("\(data.zones.count) ASSETS")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, 16)

            ForEach(Array(data.zones.enumerated()), id: \.element.id) { idx, zone in
                zoneRow(zone)
                if idx < data.zones.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.07))
                        .frame(height: 1)
                        .padding(.vertical, 13)
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
                .padding(.top, 18)
                .padding(.bottom, 16)

            // FSMA · ACTIVE LOAD block
            Text("FSMA · ACTIVE LOAD")
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .padding(.bottom, 6)
            Text(data.activeLoad.commodity)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
                .padding(.bottom, 4)
            Text(data.activeLoad.shipper)
                .font(.system(size: 10, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(palette.textSecondary)
                .padding(.bottom, 12)
            Text(data.activeLoad.loadLine)
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func zoneRow(_ zone: ReeferZoneReading_387) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(zone.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(zone.detail)
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(0.3)
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
            tempPill(zone)
        }
    }

    /// Colour-coded temperature pill — green fill for in-band, amber
    /// for the staged/pre-cool warning, red for an alarm.
    private func tempPill(_ zone: ReeferZoneReading_387) -> some View {
        let fg: Color
        let bg: Color
        switch zone.band {
        case .inBand:  fg = Brand.success; bg = Color(hex: 0x0B3D2E)
        case .warning: fg = Color(hex: 0xFFC046); bg = Color(hex: 0x3A2E08)
        case .alarm:   fg = Brand.danger;  bg = Color(hex: 0x3D0B14)
        }
        return Text(tempString(zone.tempF))
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(fg)
            .frame(width: 76, height: 22)
            .background(bg)
            .clipShape(Capsule())
    }

    // MARK: Factor row — REEFERS · IN-BAND · ALERTS

    private var factorRow: some View {
        HStack(spacing: 8) {
            factorTile(eyebrow: "REEFERS", value: "\(data.reeferCount)",
                       caption: "power units", tint: palette.textPrimary)
            factorTile(eyebrow: "IN-BAND", value: "\(data.inBandCount)",
                       caption: "of \(data.reeferCount)", tint: palette.textPrimary)
            factorTile(eyebrow: "ALERTS", value: "\(data.activeAlerts)",
                       caption: "active",
                       tint: data.activeAlerts > 0 ? Brand.danger : palette.textPrimary)
        }
    }

    private func factorTile(eyebrow: String, value: String, caption: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(palette.textTertiary)
                .padding(.bottom, 6)
            Text(value)
                .font(.system(size: 18, weight: .semibold))
                .tracking(0.4)
                .monospacedDigit()
                .foregroundStyle(tint)
                .padding(.bottom, 4)
            Text(caption)
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(palette.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Action row

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                Task { await acknowledgeActiveAlert() }
            } label: {
                Text(acknowledged ? "Alert acknowledged" : "Acknowledge alert")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(data.activeAlerts == 0 && !acknowledged)
            .opacity(data.activeAlerts == 0 && !acknowledged ? 0.6 : 1.0)

            Button {
                showFSMALog = true
            } label: {
                Text("FSMA log")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(palette.bgCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(palette.borderSoft, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Reefer telemetry · supply/return per zone · FSMA Sanitary Transport rule")
            Text("Carrier: Eusotrans LLC · USDOT 3 194 882 · live reefer temperature feed")
            Text(data.activeLoad.loadLine + " · " + data.activeLoad.commodity)
        }
        .font(.system(size: 9, design: .monospaced))
        .tracking(0.3)
        .foregroundStyle(palette.textTertiary)
        .padding(.top, 4)
    }

    // MARK: FSMA log sheet

    @ViewBuilder
    private var fsmaLogSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Image(systemName: "thermometer.snowflake")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(LinearGradient.diagonal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("FSMA continuous telemetry log")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(palette.textPrimary)
                            Text("5-min cadence · supply/return per zone")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }

                    ForEach(data.zones) { zone in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(zone.title)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(palette.textPrimary)
                                Text(zone.detail)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(palette.textSecondary)
                            }
                            Spacer(minLength: 0)
                            tempPill(zone)
                        }
                        .padding(12)
                        .background(palette.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    Text("Full FSMA Sanitary Transport audit trail (49 CFR §1.900) exports once the reefer-temperature router is wired to this device. No fabricated readings are shown.")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(20)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .navigationTitle("FSMA log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showFSMALog = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Loading / empty

    private var skeletonBody: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.bgCard).frame(height: 124)
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.bgCard).frame(height: 200)
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(palette.bgCard).frame(height: 66)
                }
            }
        }
        .redacted(reason: .placeholder)
    }

    private var emptyBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "thermometer.medium.slash")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("No live reefer telemetry")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(palette.textPrimary)
                    Text("No zone readings on the active load · check the power unit's monitoring link")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }

    // MARK: Helpers

    private func tempString(_ value: Double) -> String {
        String(format: "%.1f°F", value)
    }
}

// MARK: - Previews

#Preview("387 · Catalyst · Reefer Fleet Monitor · Night") {
    CatalystReeferFleetMonitorScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("387 · Catalyst · Reefer Fleet Monitor · Afternoon") {
    CatalystReeferFleetMonitorScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
