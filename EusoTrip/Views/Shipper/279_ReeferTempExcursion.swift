//
//  279_ReeferTempExcursion.swift
//  EusoTrip — Shipper · REEFER · temp excursion (refactored).
//
//  Pulls the same lifecycle snapshot + reefer-temp readings via the
//  existing `reeferTemp.getReadings` endpoint identified in the audit.
//

import SwiftUI

struct ReeferTempExcursionScreen: View {
    let theme: Theme.Palette
    let loadId: String
    var body: some View {
        Shell(theme: theme) {
            LifecycleScaffold(loadId: loadId, eyebrow: "SHIPPER · REEFER · TEMP EXCURSION", cycleStatus: "in_transit") { live in
                ReeferBody(live: live, loadId: loadId)
            }
        } nav: { shipperLifecycleNav() }
    }
}

private struct ReeferBody: View {
    @Environment(\.palette) private var palette
    @Environment(\.openURL) private var openURL
    let live: ShipperAPI.LifecycleSnapshot
    let loadId: String

    @State private var readings: [ReeferReading] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    /// Ambient (truck-position) weather temp · null / available:false today
    /// (enterprise-gated). Drives the AMBIENT-vs-CARGO overlay that separates
    /// an EQUIPMENT FAULT from a HEAT PERIL. Never fabricated.
    @State private var ambient: ReeferAmbient279? = nil

    /// Mirrors `reeferTemp.getReadings` EXACTLY:
    /// `{ id, zone, tempF, tempC, status, source, notes, recordedAt }`.
    /// Every field optional so a partial row decodes without throwing (the
    /// old `temp: Double` / `timestamp: String` non-optionals did NOT exist
    /// on the wire and broke decode). Hashable is preserved for the
    /// `ForEach(readings.suffix(8), id: \.self)` ledger.
    private struct ReeferReading: Decodable, Hashable {
        let id: String?
        let zone: String?
        let tempF: Double?
        let tempC: Double?
        let status: String?
        let source: String?
        let notes: String?
        let recordedAt: String?

        private enum CodingKeys: String, CodingKey {
            case id, zone, tempF, tempC, status, source, notes, recordedAt
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id)
            zone = try c.decodeIfPresent(String.self, forKey: .zone)
            tempF = Self.finiteDouble(c, .tempF)
            tempC = Self.finiteDouble(c, .tempC)
            status = try c.decodeIfPresent(String.self, forKey: .status)
            source = try c.decodeIfPresent(String.self, forKey: .source)
            notes = try c.decodeIfPresent(String.self, forKey: .notes)
            recordedAt = try c.decodeIfPresent(String.self, forKey: .recordedAt)
        }

        /// Lenient °F/°C resolver aligned to the `{ min, max, current }`
        /// assignment-temperature contract (web PR #144). Over tRPC the
        /// value arrives as a finite number, `null`, a missing key, or —
        /// when the server emitted a non-finite reading (superjson encodes
        /// NaN/Infinity as the strings `"NaN"`/`"Infinity"`, and the iOS
        /// transport decodes the raw `json` block without rehydrating
        /// superjson meta) — a non-numeric string. Every non-finite / absent
        /// form collapses to nil so the caller renders "—", never a
        /// fabricated 0.0 and never a decode throw that drops the whole row.
        private static func finiteDouble<K: CodingKey>(
            _ c: KeyedDecodingContainer<K>,
            _ key: K
        ) -> Double? {
            if let d = try? c.decodeIfPresent(Double.self, forKey: key), d.isFinite { return d }
            if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return Double(i) }
            // `Double("NaN")` / `Double("Infinity")` parse to non-finite
            // values, so the `.isFinite` gate maps the superjson special-
            // number strings to nil rather than a fabricated reading.
            if let s = try? c.decodeIfPresent(String.self, forKey: key),
               let d = Double(s), d.isFinite { return d }
            return nil
        }

        /// Display temperature in °F, or nil when the row carries no finite
        /// reading (missing / null / NaN / non-finite `current`). Renders as
        /// "—" everywhere it surfaces — never a fabricated 0.0°F.
        var displayTempF: Double? {
            guard let t = tempF, t.isFinite else { return nil }
            return t
        }
    }
    private struct ReadingsInput: Encodable { let loadId: Int }
    private struct AmbientInput: Encodable { let loadId: Int }

    /// `reeferTemp.ambient` -> the AMBIENT (outside-air) temperature at the
    /// reefer's live position, used to prove an EQUIPMENT FAULT (cargo drifts
    /// while ambient is benign) vs a HEAT PERIL (cargo + ambient both high,
    /// e.g. "cargo 47°F vs ambient 104°F"). All fields nullable so a partial /
    /// enterprise-gated payload decodes without throwing. `available:false`
    /// (today's reality) => the ambient line is HIDDEN, never fabricated.
    /// `preCool` decodes leniently (a bool flag or {recommended} object) so a
    /// shape change is safe.
    /// Mirrors the real `reeferTemp.ambient` envelope EXACTLY. Top-level
    /// `available`/`reason` gate the overlay; the outside-air reading lives
    /// in the nested `ambient` block (`temp`/`weatherCode`/…), NOT flat on
    /// the root (the old flat `ambientTempF`/`weatherCode` never existed on
    /// the wire). `cargo`/`delta`/`preCool` decode leniently so the
    /// enterprise-gated `available:false` envelope (or a partial payload)
    /// decodes without throwing.
    private struct ReeferAmbient279: Decodable {
        let available: Bool?
        let reason: String?
        let ambient: Ambient?
        let cargo: Cargo?
        let delta: Delta?
        let preCool: PreCool279?

        /// The outside-air block: `{ temp, apparent, unit, weatherCode, condition, observedAt }`.
        struct Ambient: Decodable {
            let temp: Double?
            let apparent: Double?
            let unit: String?
            let weatherCode: Int?
            let condition: String?
            let observedAt: String?
        }
        /// The worst live cargo zone the server contrasted ambient against.
        struct Cargo: Decodable {
            let tempF: Double?
            let tempC: Double?
            let zone: String?
            let status: String?
            let recordedAt: String?
        }
        /// ambient − cargo delta (the equipment-fault-vs-heat-peril proof).
        struct Delta: Decodable {
            let value: Double?
            let unit: String?
            let ambientHotter: Bool?
            let summary: String?
        }
        /// Pre-cool recommendation keyed to the forecast ambient peak.
        struct PreCool279: Decodable {
            let forecastPeak: Double?
            let forecastPeakAt: String?
            let rising: Bool?
            let text: String?
            let action: String?
            let protects: String?
        }
    }

    // Ambient overlay readiness ------------------------------------------
    // HONEST: the ambient line only reads when the feed is available AND
    // carries a real ambient temperature. enterprise-gated (available:false /
    // nil) => no ambient line, designed to light up the instant the key
    // lands. Never a fabricated ambient / spread / peril verdict.

    private var ambientReady: Bool {
        (ambient?.available ?? false) && ambient?.ambient?.temp != nil
    }

    /// The warmest live cargo-zone temperature in °F — the trace the ambient
    /// is contrasted against, taken from the SAME live `reeferTemp.getReadings`
    /// rows the chart plots. nil until a zone reports.
    private var cargoZonePeakF: Double? {
        // `displayTempF` is finite-guarded, so a NaN / non-finite `current`
        // can never inflate (or NaN-poison) the peak the ambient contrasts.
        readings.compactMap(\.displayTempF).max()
    }

    /// Ambient − cargo spread in °F. Positive = ambient hotter than cargo (the
    /// classic heat-peril signature). nil until BOTH sides have a real reading.
    private var ambientSpreadF: Double? {
        guard let a = ambient?.ambient?.temp, let c = cargoZonePeakF else { return nil }
        return a - c
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s4) {
            cargoCard
            LifecycleMapCard(live: live, label: "TRUCK POSITION", icon: "thermometer.high", mode: .full)
            // 799-class probe chart over the SAME live `reeferTemp.getReadings`
            // rows the ledger below lists — grouped by zone, chronological.
            // Only mounts when ≥2 samples exist in some zone (a single point
            // is not a trace); the FSMA 40°F ceiling is a regulatory constant
            // and no commanded-setpoint column ships on this proc, so the SET
            // rail is honestly omitted.
            if !chartZones.isEmpty {
                ReeferTempLogChart(
                    zones: chartZones,
                    setpointF: nil,
                    ceilingF: 40,
                    title: "REEFER TEMP LOG · LIVE"
                )
            }
            // AMBIENT (outside-air) overlay vs the cargo-zone trace — the read
            // that separates an EQUIPMENT FAULT from a HEAT PERIL. HONEST: only
            // mounts when the enterprise-gated feed returns a real ambient temp.
            ambientOverlaySection
            tempCard
            ctaRow
        }
        .eusoRefreshTask { await loadReadings() }
    }

    /// Group the live readings by zone → chart traces. Mirrors the 652
    /// vessel grouping; canonical front/center/rear first, then extras.
    private var chartZones: [TempZone] {
        guard !readings.isEmpty else { return [] }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        func parse(_ s: String) -> Date? {
            iso.date(from: s) ?? isoPlain.date(from: s)
        }
        var grouped: [String: [TempZone.Reading]] = [:]
        for r in readings {
            guard let ts = r.recordedAt, let t = parse(ts) else { continue }
            // Skip rows with no finite reading — plotting a fabricated 0.0
            // point would drag the trace to the floor and read as a fault.
            guard let tf = r.displayTempF else { continue }
            let key = (r.zone ?? "center").lowercased()
            grouped[key, default: []].append(.init(t: t, tempF: tf))
        }
        func zone(_ key: String, _ name: String, _ pos: TempZone.Position, _ color: Color) -> TempZone? {
            guard let rs = grouped[key]?.sorted(by: { $0.t < $1.t }), rs.count >= 2 else { return nil }
            return TempZone(name: name, position: pos, color: color, readings: rs)
        }
        var zones: [TempZone] = []
        if let z = zone("front",  "Front",  .front,  Brand.success) { zones.append(z) }
        if let z = zone("center", "Center", .center, Brand.blue)    { zones.append(z) }
        if let z = zone("rear",   "Rear",   .rear,   Brand.warning) { zones.append(z) }
        let extras = grouped.keys
            .filter { !["front", "center", "rear"].contains($0) }
            .sorted().prefix(3)
        for key in extras {
            if let z = zone(key, key.capitalized, .center, Brand.info) { zones.append(z) }
        }
        return zones
    }

    private var cargoCard: some View {
        LifecycleCard(accentDanger: true) {
            LifecycleSection(label: "CARGO", icon: "shippingbox")
            LifecycleRow(label: "Cargo type", value: dashIfEmpty(live.load.cargoType))
            LifecycleRow(label: "Equipment",  value: dashIfEmpty(live.load.equipmentType))
            LifecycleRow(label: "Lane",       value: laneDisplay(live))
            LifecycleRow(label: "Driver",     value: dashIfEmpty(live.driver?.name))
            LifecycleRow(label: "Carrier",    value: dashIfEmpty(live.carrier?.name))
        }
    }

    private var tempCard: some View {
        LifecycleCard {
            LifecycleSection(label: "TEMP READINGS", icon: "thermometer")
            if loading {
                Text("Loading reefer log…").font(EType.caption).foregroundStyle(palette.textSecondary)
            } else if let err = loadError {
                Text(err).font(EType.caption).foregroundStyle(Brand.danger)
            } else if readings.isEmpty {
                Text("No reefer log entries on file for this load.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
            } else {
                ForEach(readings.suffix(8), id: \.self) { r in
                    HStack {
                        Text(humanISO(r.recordedAt, format: "HH:mm")).font(EType.mono(.micro)).tracking(0.4).foregroundStyle(palette.textTertiary)
                        Text(r.zone ?? "-").font(EType.caption).foregroundStyle(palette.textSecondary)
                        Spacer(minLength: 0)
                        if let t = r.displayTempF {
                            Text(String(format: "%.1f°F", t))
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(t > 38 || t < 33 ? Brand.danger : palette.textPrimary)
                                .monospacedDigit()
                        } else {
                            // Honest "—": no finite reading logged for this row
                            // (missing / NaN `current`), never a fabricated 0.0°F.
                            Text("—")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(palette.textTertiary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Ambient overlay (outside-air weather vs cargo-zone trace)

    /// Overlays the AMBIENT (outside-air) temperature at the reefer's live
    /// position against the warmest live cargo zone — the read that separates
    /// an EQUIPMENT FAULT (cargo drifts while ambient is benign) from a HEAT
    /// PERIL (ambient + cargo both climbing, e.g. "cargo 47°F vs ambient
    /// 104°F"). Bespoke: the sky condition is the WeatherIcons glyph for the
    /// live weatherCode; the verdict marker is a utility glyph — ZERO SF
    /// Symbols. HONEST: rendered ONLY when the ambient feed is available with a
    /// real temperature; enterprise-gated (available:false / nil) collapses it
    /// entirely — no ambient line, no fabricated spread / verdict.
    @ViewBuilder
    private var ambientOverlaySection: some View {
        if ambientReady, let a = ambient, let aF = a.ambient?.temp {
            let code = a.ambient?.weatherCode ?? 0
            let spread = ambientSpreadF
            // Heat-peril read is honest: only asserted once we have BOTH the
            // ambient and a live cargo zone to contrast. Without the cargo
            // side we still show ambient but stay silent on the verdict.
            let peril = (spread ?? 0) >= 40 && cargoZonePeakF != nil
            LifecycleCard(accentDanger: peril) {
                // Bespoke section header — WeatherIcons glyph, never an SF Symbol on a weather element.
                HStack(spacing: 6) {
                    WeatherIcons.utility(.alert, size: 9, tint: Brand.warning)
                    Text("AMBIENT vs CARGO · REEFERTEMP.AMBIENT")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                HStack(alignment: .top, spacing: Space.s3) {
                    // Bespoke sky glyph for the live outside-air weatherCode.
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(palette.bgCardSoft)
                            .frame(width: 52, height: 52)
                        WeatherIcons.symbolView(for: code, size: 34)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        // The contrast line — cargo trace vs outside-air temp.
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            ambientStat(label: "CARGO",
                                        value: cargoZonePeakF.map { String(format: "%.0f°F", $0) } ?? "—",
                                        tone: Brand.info)
                            Text("vs").font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(palette.textTertiary)
                            ambientStat(label: "AMBIENT",
                                        value: String(format: "%.0f°F", aF),
                                        tone: peril ? Brand.danger : palette.textPrimary)
                        }
                        // Spread + the equipment-fault vs heat-peril read.
                        if let s = spread, cargoZonePeakF != nil {
                            HStack(spacing: 6) {
                                WeatherIcons.utility(peril ? .alert : .eye, size: 12,
                                                     tint: peril ? Brand.danger : palette.textSecondary)
                                Text(spreadVerdict(spread: s, peril: peril))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(peril ? Brand.danger : palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            // Ambient is live but no cargo zone to contrast yet —
                            // honest about what we can and can't yet assert.
                            Text("Outside-air temp live · awaiting a cargo-zone reading to contrast")
                                .font(.system(size: 11)).foregroundStyle(palette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        // available:false / nil => nothing renders. The line lights the instant
        // the enterprise key lands and the feed returns a real ambient temp.
    }

    private func ambientStat(label: String, value: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 8.5, weight: .heavy)).tracking(0.5)
                .foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 22, weight: .bold)).monospacedDigit()
                .foregroundStyle(tone)
        }
    }

    /// The equipment-fault vs heat-peril read. Honest, derived strictly from
    /// the live spread — never a fabricated verdict.
    private func spreadVerdict(spread: Double, peril: Bool) -> String {
        let mag = String(format: "%.0f°F", abs(spread))
        if peril {
            return "Heat peril · ambient +\(mag) over cargo — external load, not equipment"
        }
        if spread >= 15 {
            return "Ambient +\(mag) over cargo · within reefer pull-down capacity"
        }
        if spread <= -5 {
            return "Cargo warmer than ambient · a drift here reads as equipment, not heat"
        }
        return "Ambient near cargo · a drift here reads as equipment, not heat"
    }

    private var ctaRow: some View {
        HStack(spacing: 10) {
            Button {
                NotificationCenter.default.post(name: .eusoShipperNavSwap, object: nil, userInfo: ["screenId": "219", "loadId": loadId, "mode": "create", "claimType": "reefer_excursion"])
            } label: {
                Text("File freight claim").font(.system(size: 13, weight: .heavy)).tracking(0.4).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(LinearGradient.diagonal)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
            Button {
                if let p = live.driver?.phone, let url = URL(string: "tel://\(p.filter(\.isNumber))") {
                    openURL(url)
                }
            } label: {
                Image(systemName: "phone.fill").font(.system(size: 13, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    .frame(width: 44, height: 44).background(palette.bgCard)
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain).disabled(live.driver?.phone?.isEmpty != false)
        }
    }

    private func loadReadings() async {
        loading = true; loadError = nil
        let intId = Int(loadId.replacingOccurrences(of: "load_", with: "")) ?? Int(loadId) ?? -1
        guard intId > 0 else { loading = false; return }
        do {
            let rs: [ReeferReading] = try await EusoTripAPI.shared.query(
                "reeferTemp.getReadings",
                input: ReadingsInput(loadId: intId)
            )
            readings = rs
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        // Ambient (outside-air weather) is a best-effort overlay — its feed is
        // enterprise-gated and may return available:false or be unreachable. A
        // failure here NEVER degrades the core reefer log: the ambient line
        // just stays hidden until the key lands.
        ambient = try? await EusoTripAPI.shared.query(
            "reeferTemp.ambient", input: AmbientInput(loadId: intId))
        loading = false
    }
}

#Preview("279 · Reefer · Temp excursion · Night") {
    ReeferTempExcursionScreen(theme: Theme.dark, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("279 · Reefer · Temp excursion · Afternoon") {
    ReeferTempExcursionScreen(theme: Theme.light, loadId: "0").environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
