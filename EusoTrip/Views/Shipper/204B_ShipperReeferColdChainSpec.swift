//
//  204B_ShipperReeferColdChainSpec.swift
//  EusoTrip 2027 - Shipper reefer cold-chain spec (drill-down of 204 Post a Load).
//
//  ARCHETYPE: TELEMETRY. Reads the FSMA continuous temperature record that
//  the server actually holds for this load, plus the USDA/FSMA setpoint for
//  the recorded commodity. It renders a tolerance-band verdict ONLY when a
//  real reading AND a real setpoint both exist; an empty record is shown as
//  an empty record, never as "0 excursions, band held".
//
//  SwiftUI twin of:
//    02 Shipper/Light-SVG/204B Shipper Reefer Cold-Chain Spec.svg
//    02 Shipper/Dark-SVG/204B Shipper Reefer Cold-Chain Spec.svg
//
//  ── WIRING MANIFEST (line-confirmed on disk frontend/server/routers/) ──
//    loads.getById                 EXISTS · loads.ts:1225
//    commodity.searchReefer        EXISTS · commodity.ts:565   (USDA/FSMA setpoint band)
//    reeferTemp.getLatestByZone    EXISTS · reeferTemp.ts:187   (front/center/rear probe)
//    reeferTemp.getStats           EXISTS · reeferTemp.ts:495   (min/max/avg/count/excursions)
//    reeferTemp.getHourlyAvgs      EXISTS · reeferTemp.ts:539   (trace points)
//  NOT CALLED — no such procedure exists tree-wide:
//    insurance.bindCargoEndorsement  MISSING · the spoilage-endorsement chip
//      the SVG carries has no backing procedure, so it is not rendered at all
//      rather than painted from a literal.
//
//  HONEST-ABSENCE NOTES (these are contract, not decoration):
//    · reeferTemp.getStats / getLatestByZone / getHourlyAvgs scope their rows
//      to `reeferReadings.driverId = ctx.user.id`. A shipper caller is not the
//      driver of record, so these can legitimately return an EMPTY record.
//      getStats' no-row envelope is literally {0,0,0,0,0} — this screen gates
//      every derived figure on `totalReadings > 0` so a zeroed envelope can
//      never render as a clean trip.
//    · No push stream exists for reeferTemp on the wire; the SVG's "one live
//      tick" is honored here as an explicit re-query on appear and on pull —
//      the header does not claim a subscription this build cannot open.
//
//  §W OFFLINE POLICY: ONLINE_ONLY(FSMA continuous-record readings and the
//  USDA setpoint band are proof-of-condition; a cached temperature is
//  indistinguishable from a live one and could defend a spoilage claim that
//  was never actually measured). Nothing is persisted client-side; on any
//  failure the model is cleared and the reason is surfaced.
//
//  — Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Decoded models

private struct ReeferSetpoint204B: Decodable {
    let productName: String
    let tempMinF: Double
    let tempMaxF: Double
    let toleranceF: Double
    let monitoringIntervalMin: Int
    let fsmaRegulated: Bool
    let ethyleneSensitive: Bool
    let notes: String?
}

private struct ReeferSearch204B: Decodable {
    let count: Int
    let source: String
    let best: ReeferSetpoint204B?
}

private struct ReeferZone204B: Decodable {
    let tempF: Double
    let tempC: Double
    let status: String?
    let recordedAt: String
}

private struct ReeferStats204B: Decodable {
    let min: Double
    let max: Double
    let avg: Double
    let totalReadings: Int
    let excursions: Int

    /// The server returns a zeroed envelope when there are no rows and when
    /// the database is unreachable. Everything derived from this struct is
    /// gated on this flag so an absent record can never render as a clean one.
    var hasRecord: Bool { totalReadings > 0 }
}

private struct ReeferHourlyAvg204B: Decodable {
    let hour: Int
    let avg: Double
}

/// One trailer probe, resolved from `reeferTemp.getLatestByZone`.
private struct ReeferProbe204B: Identifiable {
    let id: String
    let label: String
    let tempF: Double
    let recordedAt: Date?
    let rawRecordedAt: String
}

// MARK: - Store

@MainActor
private final class ColdChainStore204B: ObservableObject {
    @Published private(set) var load: LoadsAPI.LoadDetail?
    @Published private(set) var setpoint: ReeferSetpoint204B?
    @Published private(set) var setpointSource: String?
    @Published private(set) var setpointSearched = false
    @Published private(set) var probes: [ReeferProbe204B] = []
    @Published private(set) var stats: ReeferStats204B?
    @Published private(set) var hourly: [ReeferHourlyAvg204B] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    let loadId: String
    private let api: EusoTripAPI

    /// Window used for every reeferTemp read on this screen. Surfaced in the
    /// UI so the min/max/avg figures carry their own scope.
    static let windowHours = 24

    /// The band `reeferTemp.getStats` (reeferTemp.ts:495) applies when the
    /// caller sends none. Mirrored here ONLY so the UI can name the band the
    /// excursion count was actually measured against when this load has no
    /// commodity setpoint on file. Never shown as a commodity band.
    static let serverDefaultTargetMinF: Double = 33
    static let serverDefaultTargetMaxF: Double = 40

    init(loadId: String, api: EusoTripAPI = .shared) {
        self.loadId = loadId
        self.api = api
    }

    private func clear() {
        load = nil
        setpoint = nil
        setpointSource = nil
        setpointSearched = false
        probes = []
        stats = nil
        hourly = []
    }

    func refresh() async {
        guard !loadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clear()
            errorMessage = "Open the cold-chain spec from a load to see its temperature record."
            return
        }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            guard let resolved = try await api.loads.getDetail(id: loadId) else {
                clear()
                errorMessage = "This load is no longer available. Return to Loads and choose another one."
                return
            }
            load = resolved

            var failures: [String] = []
            // Every reeferTemp read is scoped to THIS load. If the id does not
            // resolve to the numeric key the server filters on, the reads are
            // skipped entirely — an unscoped query would return the caller's
            // other readings and attribute them to this load.
            let numericLoadId = Int(resolved.id)

            // USDA / FSMA setpoint band for the recorded commodity.
            let productName = (resolved.commodityName ?? resolved.commodity ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if productName.isEmpty {
                setpoint = nil
                setpointSource = nil
                setpointSearched = false
            } else {
                struct SearchInput: Encodable {
                    let productName: String
                    let limit: Int
                }
                do {
                    let search: ReeferSearch204B = try await api.query(
                        "commodity.searchReefer",
                        input: SearchInput(productName: productName, limit: 1)
                    )
                    setpoint = search.best
                    setpointSource = search.source
                    setpointSearched = true
                } catch {
                    setpoint = nil
                    setpointSource = nil
                    setpointSearched = false
                    failures.append(error.eusoUserCopy)
                }
            }

            if let numericLoadId {
                // Latest probe per trailer zone.
                struct ZoneInput: Encodable { let loadId: Int }
                do {
                    let zones: [String: ReeferZone204B] = try await api.query(
                        "reeferTemp.getLatestByZone",
                        input: ZoneInput(loadId: numericLoadId)
                    )
                    probes = Self.orderedProbes(from: zones)
                } catch {
                    probes = []
                    failures.append(error.eusoUserCopy)
                }

                // Trip statistics, scoped to the same tolerance band the
                // setpoint declares. When no setpoint is on file the server's
                // own defaults apply and the excursion band is labelled as
                // such in the UI rather than presented as a commodity band.
                struct StatsInput: Encodable {
                    let loadId: Int
                    let hours: Int
                    let targetMin: Double
                    let targetMax: Double
                }
                do {
                    stats = try await api.query(
                        "reeferTemp.getStats",
                        input: StatsInput(
                            loadId: numericLoadId,
                            hours: Self.windowHours,
                            targetMin: setpoint?.tempMinF ?? Self.serverDefaultTargetMinF,
                            targetMax: setpoint?.tempMaxF ?? Self.serverDefaultTargetMaxF
                        )
                    )
                } catch {
                    stats = nil
                    failures.append(error.eusoUserCopy)
                }

                // Hourly trace points.
                struct HourlyInput: Encodable {
                    let loadId: Int
                    let hours: Int
                }
                do {
                    hourly = try await api.query(
                        "reeferTemp.getHourlyAvgs",
                        input: HourlyInput(loadId: numericLoadId, hours: Self.windowHours)
                    )
                } catch {
                    hourly = []
                    failures.append(error.eusoUserCopy)
                }
            } else {
                probes = []
                stats = nil
                hourly = []
                failures.append("This load's identifier does not resolve to a temperature-log key, so no reading could be scoped to it.")
            }

            errorMessage = failures.isEmpty ? nil : failures.joined(separator: " ")
        } catch {
            clear()
            errorMessage = error.eusoUserCopy
        }
    }

    /// Front / center / rear in trailer order, skipping zones the server did
    /// not return. A missing zone is omitted, never zero-filled.
    private static func orderedProbes(from zones: [String: ReeferZone204B]) -> [ReeferProbe204B] {
        let order: [(key: String, label: String)] = [
            ("front", "FRONT"),
            ("center", "CENTER"),
            ("rear", "REAR"),
        ]
        return order.compactMap { entry in
            guard let zone = zones[entry.key] else { return nil }
            return ReeferProbe204B(
                id: entry.key,
                label: entry.label,
                tempF: zone.tempF,
                recordedAt: ISO8601DateFormatter().date(from: zone.recordedAt),
                rawRecordedAt: zone.recordedAt
            )
        }
    }
}

// MARK: - Screen

struct ShipperReeferColdChainSpec: View {
    let loadId: String
    @StateObject private var store: ColdChainStore204B
    @Environment(\.palette) private var palette

    init(loadId: String = "") {
        self.loadId = loadId
        _store = StateObject(wrappedValue: ColdChainStore204B(loadId: loadId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AddendaHeader(
                    eyebrow: "SHIPPER · REEFER · FSMA COLD-CHAIN",
                    idText: store.load?.loadNumber ?? loadId,
                    title: "Cold chain"
                )

                if let errorMessage = store.errorMessage {
                    DegradedNote(text: errorMessage)
                        .padding(.top, Space.s3)
                }

                if store.isLoading, store.load == nil {
                    ProgressView("Loading cold-chain record")
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.s6)
                }

                if let load = store.load {
                    loadCard(load)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s4)

                    SectionLabel("LATEST PROBE · TRAILER ZONES")
                        .padding(.top, Space.s5)
                    probeSection
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)

                    SectionLabel("USDA / FSMA SETPOINT")
                        .padding(.top, Space.s5)
                    setpointCard
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)

                    SectionLabel("CONTINUOUS RECORD · LAST \(ColdChainStore204B.windowHours)H")
                        .padding(.top, Space.s5)
                    recordCard
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s2)

                    if !store.hourly.isEmpty {
                        SectionLabel("HOURLY AVERAGE TRACE")
                            .padding(.top, Space.s5)
                        traceCard
                            .padding(.horizontal, Space.s5)
                            .padding(.top, Space.s2)
                    }

                    endorsementGapNote
                        .padding(.top, Space.s5)
                }

                if !loadId.isEmpty {
                    AddendaCTAPair(
                        primary: "Refresh record",
                        secondary: "Message ESang",
                        primaryLoading: store.isLoading,
                        onPrimary: { Task { await store.refresh() } }
                    )
                    .padding(.top, Space.s5)
                }

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.refresh() }
        .eusoRefreshable { await store.refresh() }
    }

    // MARK: Load identity

    private func loadCard(_ load: LoadsAPI.LoadDetail) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                AddendaIconChip(systemImage: "thermometer.snowflake", tint: Brand.info)
                VStack(alignment: .leading, spacing: 4) {
                    Text(load.commodityName ?? load.commodity ?? "Commodity not recorded")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text(load.laneDisplay)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                AddendaChip(
                    text: load.status.replacingOccurrences(of: "_", with: " ").uppercased(),
                    color: Brand.info
                )
            }
            Divider().overlay(palette.borderFaint)
            factRow("EQUIPMENT", (load.equipmentType ?? "Not recorded").replacingOccurrences(of: "_", with: " ").uppercased())
            factRow("WEIGHT", load.weightDisplay)
            factRow("PICKUP", load.pickupDate.map(Self.formatDate) ?? "Not recorded")
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    // MARK: Probes

    @ViewBuilder
    private var probeSection: some View {
        if store.probes.isEmpty {
            emptyState(
                icon: "sensor.tag.radiowaves.forward",
                title: "No probe reading on this load",
                message: "The reefer temperature log returned no rows for this load. A probe reading is written by the tractor's telemetry or by a driver's manual entry; until one exists there is no in-trailer temperature to show."
            )
        } else {
            VStack(spacing: Space.s2) {
                ForEach(store.probes) { probe in
                    probeRow(probe)
                }
            }
        }
    }

    private func probeRow(_ probe: ReeferProbe204B) -> some View {
        let verdict = bandVerdict(for: probe.tempF)
        return HStack(alignment: .center, spacing: Space.s3) {
            VStack(alignment: .leading, spacing: 4) {
                Text(probe.label)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(String(format: "%.1f°F", probe.tempF))
                    .font(.system(size: 22, weight: .bold).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
            }
            Spacer(minLength: Space.s3)
            VStack(alignment: .trailing, spacing: 4) {
                if let verdict {
                    AddendaChip(text: verdict.text, color: verdict.color)
                } else {
                    AddendaChip(text: "NO BAND ON FILE", color: Brand.warning)
                }
                Text(Self.staleness(probe.recordedAt, raw: probe.rawRecordedAt))
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    /// IN BAND / OUT OF BAND is only a claim when a real setpoint band exists.
    /// Without a band on file the verdict is withheld — a temperature with no
    /// tolerance is not evidence of compliance.
    private func bandVerdict(for tempF: Double) -> (text: String, color: Color)? {
        guard let spec = store.setpoint else { return nil }
        let low = spec.tempMinF - spec.toleranceF
        let high = spec.tempMaxF + spec.toleranceF
        if tempF >= spec.tempMinF && tempF <= spec.tempMaxF {
            return ("IN BAND", Brand.success)
        }
        if tempF >= low && tempF <= high {
            return ("IN TOLERANCE", Brand.warning)
        }
        return ("OUT OF BAND", Brand.danger)
    }

    // MARK: Setpoint

    @ViewBuilder
    private var setpointCard: some View {
        if let spec = store.setpoint {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top, spacing: Space.s3) {
                    AddendaIconChip(systemImage: "ruler", tint: Brand.info)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(spec.productName)
                            .font(EType.title)
                            .foregroundStyle(palette.textPrimary)
                        Text(String(format: "hold %.0f–%.0f°F · tolerance ±%.0f°F", spec.tempMinF, spec.tempMaxF, spec.toleranceF))
                            .font(EType.mono(.caption))
                            .foregroundStyle(palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    AddendaChip(
                        text: spec.fsmaRegulated ? "FSMA" : "NON-FSMA",
                        color: spec.fsmaRegulated ? Brand.info : Brand.neutral
                    )
                }
                Divider().overlay(palette.borderFaint)
                factRow("MONITORING INTERVAL", "\(spec.monitoringIntervalMin) min")
                factRow("ETHYLENE SENSITIVE", spec.ethyleneSensitive ? "Yes" : "No")
                if let source = store.setpointSource {
                    factRow("SOURCE", source.uppercased())
                }
                if let notes = spec.notes, !notes.isEmpty {
                    Text(notes)
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Space.s4)
            .addendaPanel(palette)
        } else if store.setpointSearched {
            emptyState(
                icon: "questionmark.folder",
                title: "No USDA/FSMA setpoint on file",
                message: "The commodity reference has no temperature band for this load's recorded commodity, so EusoTrip will not assert a hold range or an in-band verdict for it."
            )
        } else {
            emptyState(
                icon: "questionmark.folder",
                title: "Commodity not recorded",
                message: "The setpoint lookup keys off the load's commodity. Record the commodity on the load and the USDA/FSMA band will resolve."
            )
        }
    }

    // MARK: Continuous record

    @ViewBuilder
    private var recordCard: some View {
        if let stats = store.stats, stats.hasRecord {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top, spacing: Space.s3) {
                    AddendaIconChip(
                        systemImage: stats.excursions == 0 ? "checkmark.seal" : "exclamationmark.triangle.fill",
                        tint: stats.excursions == 0 ? Brand.success : Brand.danger
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(stats.excursions) excursion\(stats.excursions == 1 ? "" : "s")")
                            .font(EType.title)
                            .foregroundStyle(stats.excursions == 0 ? Brand.success : Brand.danger)
                            .monospacedDigit()
                        Text("across \(stats.totalReadings) reading\(stats.totalReadings == 1 ? "" : "s") in the last \(ColdChainStore204B.windowHours) hours")
                            .font(EType.caption)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                Divider().overlay(palette.borderFaint)
                factRow("MIN", String(format: "%.1f°F", stats.min))
                factRow("MAX", String(format: "%.1f°F", stats.max))
                factRow("AVERAGE", String(format: "%.1f°F", stats.avg))
                factRow("EXCURSION BAND", excursionBandLabel)
                Text("Excursions are counted server-side against the band shown above. This is the count for the readings this account can see; it is not a certificate of continuous compliance.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.s4)
            .addendaPanel(palette)
        } else {
            emptyState(
                icon: "waveform.path.ecg",
                title: "No continuous record for this account",
                message: "The temperature log returned no readings for this load in the last \(ColdChainStore204B.windowHours) hours. An empty log is not a clean trip — EusoTrip will not report zero excursions against zero readings."
            )
        }
    }

    private var excursionBandLabel: String {
        if let spec = store.setpoint {
            return String(format: "%.0f–%.0f°F · USDA/FSMA", spec.tempMinF, spec.tempMaxF)
        }
        return String(
            format: "%.0f–%.0f°F · server default (no commodity band on file)",
            ColdChainStore204B.serverDefaultTargetMinF,
            ColdChainStore204B.serverDefaultTargetMaxF
        )
    }

    // MARK: Hourly trace

    private var traceCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            traceChart
                .frame(height: 64)
            HStack {
                Text(String(format: "%.1f°F", traceLow))
                    .font(.system(size: 9, weight: .bold)).monospacedDigit()
                Spacer()
                Text("\(store.hourly.count) hourly point\(store.hourly.count == 1 ? "" : "s")")
                    .font(.system(size: 9, weight: .bold))
                Spacer()
                Text(String(format: "%.1f°F", traceHigh))
                    .font(.system(size: 9, weight: .bold)).monospacedDigit()
            }
            .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    /// Chart bounds are derived from the returned points (and the band when a
    /// band exists) so the trace is never rescaled to flatter a reading. The
    /// trace card only renders when `store.hourly` is non-empty, so these
    /// bounds always describe real samples — there is no synthesized axis.
    private var traceBounds: (low: Double, high: Double) {
        var lows = store.hourly.map(\.avg)
        var highs = lows
        if let spec = store.setpoint {
            lows.append(spec.tempMinF - spec.toleranceF)
            highs.append(spec.tempMaxF + spec.toleranceF)
        }
        guard let minimum = lows.min(), let maximum = highs.max() else {
            // Unreachable while the render gate holds; kept total so the type
            // has no implicit crash and no invented axis.
            return (0, 1)
        }
        return (minimum - 1, maximum + 1)
    }

    private var traceLow: Double { traceBounds.low }

    private var traceHigh: Double { traceBounds.high }

    private var traceChart: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let low = traceLow
            let high = traceHigh
            let span = max(0.001, high - low)
            let points = store.hourly

            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(palette.bgCardSoft)

                if let spec = store.setpoint {
                    let bandTop = height - CGFloat((spec.tempMaxF - low) / span) * height
                    let bandBottom = height - CGFloat((spec.tempMinF - low) / span) * height
                    Rectangle()
                        .fill(Brand.success.opacity(0.16))
                        .frame(height: max(1, bandBottom - bandTop))
                        .position(x: width / 2, y: (bandTop + bandBottom) / 2)
                }

                Path { path in
                    guard points.count > 1 else { return }
                    let stepX = width / CGFloat(points.count - 1)
                    for (index, point) in points.enumerated() {
                        let y = height - CGFloat((point.avg - low) / span) * height
                        let pt = CGPoint(x: CGFloat(index) * stepX, y: y)
                        if index == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                }
                .stroke(
                    LinearGradient.primary,
                    style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
                )

                if points.count == 1, let only = points.first {
                    let y = height - CGFloat((only.avg - low) / span) * height
                    Circle()
                        .fill(Brand.info)
                        .frame(width: 7, height: 7)
                        .position(x: width / 2, y: y)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            )
        }
        .accessibilityLabel("Hourly average temperature trace, \(store.hourly.count) points")
    }

    // MARK: Named backend gap

    private var endorsementGapNote: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            SectionLabel("SPOILAGE ENDORSEMENT")
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "shield.slash")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Brand.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cargo endorsement status unavailable")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text("No procedure exists to read or bind a reefer spoilage endorsement for a load (insurance.bindCargoEndorsement is not implemented on the server). Rather than paint a coverage limit that nothing verifies, this panel stays empty.")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Space.s4)
            .addendaPanel(palette)
            .padding(.horizontal, Space.s5)
        }
    }

    // MARK: Shared parts

    private func emptyState(icon: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                Text(message)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(EType.micro)
                .foregroundStyle(palette.textTertiary)
            Spacer(minLength: Space.s3)
            Text(value)
                .font(EType.mono(.caption))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private static func staleness(_ date: Date?, raw: String) -> String {
        guard let date else { return raw.isEmpty ? "time not recorded" : raw }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 0 { return "recorded \(date.formatted(date: .abbreviated, time: .shortened))" }
        if seconds < 120 { return "recorded \(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 120 { return "recorded \(minutes) min ago" }
        return "recorded \(minutes / 60) h ago"
    }

    private static func formatDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

#Preview("204B · Reefer Cold-Chain · Dark") {
    ShipperScreenWrap(palette: Theme.dark, currentSlot: .none) {
        ShipperReeferColdChainSpec()
    }
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("204B · Reefer Cold-Chain · Light") {
    ShipperScreenWrap(palette: Theme.light, currentSlot: .none) {
        ShipperReeferColdChainSpec()
    }
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
