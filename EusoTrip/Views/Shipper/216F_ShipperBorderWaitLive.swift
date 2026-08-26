//
//  216F_ShipperBorderWaitLive.swift
//  EusoTrip 2027 - Shipper border wait (drill-down of 216 Compliance).
//
//  ARCHETYPE: DETAIL / RANKED COMPARISON. Read-only. Every crossing, every
//  wait figure, every drive estimate and the ranking itself come from the
//  server's port-of-entry recommendation for THIS load's recorded origin
//  coordinates. Each row carries its own provenance: a wait sourced from the
//  live CBP feed is labelled differently from a directory average, and the
//  header badge never says LIVE unless the response says the feed answered.
//
//  SwiftUI twin of:
//    02 Shipper/Light-SVG/216F Shipper Border Wait Live.svg
//    02 Shipper/Dark-SVG/216F Shipper Border Wait Live.svg
//
//  ── WIRING MANIFEST (line-confirmed on disk frontend/server/routers/) ──
//    loads.getById                                   EXISTS · loads.ts:1225
//        supplies the geocoded pickup anchor the ranking is measured from
//    crossBorderShipping.recommendCrossings           EXISTS · crossBorder.ts:565
//        input {fromLat, fromLng, border, fastEligible, hazmatRequired, limit}
//        → {recommendations[], baseline, live, cacheAgeSeconds, sampledAt}
//    crossBorderShipping.estimateBorderTimeSavings    EXISTS · crossBorder.ts:3599
//        input {programId} → {standardMinutes, programMinutes, savingsPercent}
//        NOTE ON NAMESPACE: routers.ts:3214-3216 mounts crossBorderCompliance.ts
//        at `crossBorder` and crossBorder.ts at `crossBorderShipping`. The
//        wireframe header called these `crossBorder.*`. `crossBorder.recommend-
//        Crossings` does also exist (crossBorderCompliance.ts:866, a re-mount),
//        but `crossBorder.estimateBorderTimeSavings` does NOT — the mounted
//        `crossBorderShipping` names are used for both so the pair stays
//        consistent with 216G's already-shipping namespace.
//  NOT CALLED — no such procedure exists tree-wide:
//    crossBorder.getBorderWait  MISSING · superseded by recommendCrossings,
//      which returns the same wait figures with their source attached.
//
//  DELIBERATE OMISSIONS (each would have required inventing data):
//    · The SVG's live route map with a rig moving along a polyline is NOT
//      rendered. No procedure returns a route polyline for a shipper-owned
//      load, and no procedure snaps a tractor position onto one. A schematic
//      map with an interpolated truck would be a picture of a fact nobody
//      measured. The corridor bar that replaces it is drawn from the real
//      drive-minutes and wait-minutes split.
//    · The FAST savings figure is labelled as a PROGRAM BENCHMARK, because
//      estimateBorderTimeSavings returns a program-level table lookup — it is
//      not this load's saving and is not presented as one.
//
//  §W OFFLINE POLICY: ONLINE_ONLY(a border wait is only useful while it is
//  current; a cached wait time is worse than none because it is actionable
//  and wrong). Nothing is persisted client-side. The server's own 5-minute
//  CBP cache IS surfaced — `cacheAgeSeconds` and the per-row source string are
//  rendered so a cached figure is visibly distinct from a live one.
//
//  — Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Decoded models

private struct BorderLocation216F: Decodable {
    let city: String?
    let state: String?
}

/// Top-level `pickupCoord` slot of `loads.getById` (loads.ts:1506). The server
/// already nulls null-island endpoints, so a non-nil pair is a real geocode.
private struct BorderCoord216F: Decodable {
    let lat: Double?
    let lng: Double?
}

private struct BorderLoad216F: Decodable {
    let id: String
    let loadNumber: String
    let status: String
    let commodity: String?
    let commodityName: String?
    let hazmatClass: String?
    let originCountry: String?
    let destCountry: String?
    let pickupCoord: BorderCoord216F?
    let pickupLocation: BorderLocation216F?
    let deliveryLocation: BorderLocation216F?

    var lane: String {
        "\(location(pickupLocation)) -> \(location(deliveryLocation))"
    }

    var isHazmat: Bool {
        (hazmatClass?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
    }

    private func location(_ value: BorderLocation216F?) -> String {
        let parts = [value?.city, value?.state]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Location not recorded" : parts.joined(separator: ", ")
    }
}

private struct BorderCrossing216F: Decodable, Identifiable {
    var id: String { code }
    let code: String
    let name: String
    let border: String
    let state: String?
    let province: String?
    let milesFromCaller: Int
    let driveMinutes: Int
    let commercialWaitMinutes: Int
    let fastWaitMinutes: Int?
    let effectiveWaitMinutes: Int
    let fastLaneAvailable: Bool
    let hazmatCapable: Bool
    /// "low" | "moderate" | "high" | "critical"
    let severity: String
    let totalMinutes: Int
    /// True when the CBP border-wait feed answered for THIS port.
    let live: Bool
    /// "CBP BWT API" | "directory average"
    let source: String
    let deltaMinutes: Int
    let isBaseline: Bool

    var locale: String {
        let parts = [state, province].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? border : parts.joined(separator: " / ")
    }
}

private struct BorderBaseline216F: Decodable {
    let code: String
    let name: String
    let totalMinutes: Int
}

private struct BorderRecommendation216F: Decodable {
    let recommendations: [BorderCrossing216F]
    let baseline: BorderBaseline216F?
    /// True when the CBP feed returned any port at all on this sample.
    let live: Bool
    let cacheAgeSeconds: Double?
    let sampledAt: String?
}

private struct BorderTimeSavings216F: Decodable {
    let standardMinutes: Int
    let programMinutes: Int
    let savingsPercent: Int
}

/// Why the ranking could not be requested. Each is a distinct truth.
private enum BorderWaitBlock216F {
    case noCoordinates
    case notCrossBorder
}

// MARK: - Store

@MainActor
private final class BorderWaitStore216F: ObservableObject {
    @Published private(set) var load: BorderLoad216F?
    @Published private(set) var recommendation: BorderRecommendation216F?
    @Published private(set) var fastSavings: BorderTimeSavings216F?
    @Published private(set) var block: BorderWaitBlock216F?
    @Published private(set) var borderLabel: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    let loadId: String
    private let api: EusoTripAPI

    /// Ranked candidates requested per query. Named so the section label can
    /// say what the list is capped at rather than implying it is exhaustive.
    static let candidateLimit = 4

    /// The trusted-trader program whose benchmark is shown. A program-level
    /// table lookup, not a per-load figure.
    static let benchmarkProgramId = "FAST"

    init(loadId: String, api: EusoTripAPI = .shared) {
        self.loadId = loadId
        self.api = api
    }

    private func clear() {
        load = nil
        recommendation = nil
        fastSavings = nil
        block = nil
        borderLabel = nil
    }

    func refresh() async {
        guard !loadId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            clear()
            errorMessage = "Open border wait from a cross-border load to rank its crossings."
            return
        }

        isLoading = true
        defer { isLoading = false }
        errorMessage = nil

        do {
            struct LoadInput: Encodable { let id: String }
            let result: BorderLoad216F? = try await api.query(
                "loads.getById",
                input: LoadInput(id: loadId)
            )
            guard let resolved = result else {
                clear()
                errorMessage = "This load is no longer available. Return to Loads and choose another one."
                return
            }
            load = resolved
            recommendation = nil
            fastSavings = nil
            block = nil
            borderLabel = nil

            guard let border = Self.borderCode(for: resolved) else {
                block = .notCrossBorder
                return
            }
            borderLabel = border

            // The ranking is measured FROM a real point. Without a geocoded
            // pickup anchor the request is not made at all — sending a zeroed
            // coordinate would rank crossings from the middle of the Atlantic
            // and return a confident, wrong answer.
            guard let lat = resolved.pickupCoord?.lat,
                  let lng = resolved.pickupCoord?.lng,
                  !(lat == 0 && lng == 0) else {
                block = .noCoordinates
                return
            }

            var failures: [String] = []

            struct RecommendInput: Encodable {
                let fromLat: Double
                let fromLng: Double
                let border: String
                let fastEligible: Bool
                let hazmatRequired: Bool
                let limit: Int
            }
            do {
                recommendation = try await api.query(
                    "crossBorderShipping.recommendCrossings",
                    input: RecommendInput(
                        fromLat: lat,
                        fromLng: lng,
                        border: border,
                        // No procedure reports whether this load's assigned
                        // driver holds a FAST card, so the ranking is NOT
                        // biased toward FAST lanes. Per-port FAST wait times
                        // still render where the port publishes them.
                        fastEligible: false,
                        hazmatRequired: resolved.isHazmat,
                        limit: Self.candidateLimit
                    )
                )
            } catch {
                recommendation = nil
                failures.append(error.eusoUserCopy)
            }

            struct SavingsInput: Encodable { let programId: String }
            do {
                fastSavings = try await api.query(
                    "crossBorderShipping.estimateBorderTimeSavings",
                    input: SavingsInput(programId: Self.benchmarkProgramId)
                )
            } catch {
                fastSavings = nil
                failures.append(error.eusoUserCopy)
            }

            errorMessage = failures.isEmpty ? nil : failures.joined(separator: " ")
        } catch {
            clear()
            errorMessage = error.eusoUserCopy
        }
    }

    /// The server accepts "US-CA", "US-MX" or "ALL". A lane with no recorded
    /// countries, or a domestic lane, gets no ranking rather than "ALL" —
    /// ranking every North American port for a Dallas-to-Houston move would
    /// be a confidently irrelevant answer.
    private static func borderCode(for load: BorderLoad216F) -> String? {
        guard let origin = load.originCountry?.uppercased(),
              let destination = load.destCountry?.uppercased(),
              !origin.isEmpty, !destination.isEmpty,
              origin != destination else { return nil }
        let pair = Set([origin, destination])
        if pair == Set(["US", "MX"]) { return "US-MX" }
        if pair == Set(["US", "CA"]) { return "US-CA" }
        return nil
    }
}

// MARK: - Screen

struct ShipperBorderWaitLive: View {
    let loadId: String
    @StateObject private var store: BorderWaitStore216F
    @Environment(\.palette) private var palette

    init(loadId: String = "") {
        self.loadId = loadId
        _store = StateObject(wrappedValue: BorderWaitStore216F(loadId: loadId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AddendaHeader(
                    eyebrow: "SHIPPER · BORDER CROSSINGS",
                    idText: store.load?.loadNumber ?? loadId,
                    title: "Border wait"
                )

                if let errorMessage = store.errorMessage {
                    DegradedNote(text: errorMessage)
                        .padding(.top, Space.s3)
                }

                if store.isLoading, store.load == nil {
                    ProgressView("Ranking crossings")
                        .frame(maxWidth: .infinity)
                        .padding(.top, Space.s6)
                }

                if let load = store.load {
                    loadCard(load)
                        .padding(.horizontal, Space.s5)
                        .padding(.top, Space.s4)

                    if let block = store.block {
                        blockedCard(block)
                            .padding(.horizontal, Space.s5)
                            .padding(.top, Space.s4)
                    }

                    if let recommendation = store.recommendation {
                        SectionLabel("FEED STATE")
                            .padding(.top, Space.s5)
                        feedCard(recommendation)
                            .padding(.horizontal, Space.s5)
                            .padding(.top, Space.s2)

                        if let best = recommendation.recommendations.first {
                            SectionLabel("BEST BY TIME TO CROSS")
                                .padding(.top, Space.s5)
                            corridorCard(best)
                                .padding(.horizontal, Space.s5)
                                .padding(.top, Space.s2)
                        }

                        SectionLabel("CROSSINGS · TOP \(BorderWaitStore216F.candidateLimit) BY TOTAL MINUTES")
                            .padding(.top, Space.s5)
                        crossingList(recommendation)
                            .padding(.horizontal, Space.s5)
                            .padding(.top, Space.s2)
                    }

                    if let savings = store.fastSavings {
                        SectionLabel("\(BorderWaitStore216F.benchmarkProgramId) PROGRAM BENCHMARK · NOT THIS LOAD")
                            .padding(.top, Space.s5)
                        savingsCard(savings)
                            .padding(.horizontal, Space.s5)
                            .padding(.top, Space.s2)
                    }

                    routingGapNote
                        .padding(.top, Space.s5)
                }

                if !loadId.isEmpty {
                    AddendaCTAPair(
                        primary: "Refresh waits",
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

    private func loadCard(_ load: BorderLoad216F) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                AddendaIconChip(systemImage: "road.lanes", tint: Brand.info)
                VStack(alignment: .leading, spacing: 4) {
                    Text(load.commodityName ?? load.commodity ?? "Cargo not recorded")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text(load.lane)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                AddendaChip(
                    text: load.status.replacingOccurrences(of: "_", with: " ").uppercased(),
                    color: Brand.info
                )
            }
            Divider().overlay(palette.borderFaint)
            factRow("CORRIDOR", store.borderLabel ?? "Not a recorded US-MX or US-CA lane")
            factRow("HAZMAT FILTER", load.isHazmat ? "On · hazmat-capable ports only" : "Off")
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    // MARK: Feed state

    private func feedCard(_ recommendation: BorderRecommendation216F) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            AddendaIconChip(
                systemImage: recommendation.live ? "dot.radiowaves.left.and.right" : "clock.arrow.circlepath",
                tint: recommendation.live ? Brand.success : Brand.warning
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(recommendation.live ? "CBP feed answered" : "Directory averages only")
                    .font(EType.title)
                    .foregroundStyle(recommendation.live ? Brand.success : Brand.warning)
                Text(recommendation.live
                     ? "At least one port returned a published wait on this sample. Rows below say which."
                     : "The CBP border-wait feed returned nothing on this sample, so every wait below is a directory average, not a current measurement.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let age = recommendation.cacheAgeSeconds {
                    Text(Self.cacheAgeLabel(age))
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                }
                if let sampledAt = recommendation.sampledAt, !sampledAt.isEmpty {
                    Text("sampled \(Self.formatTimestamp(sampledAt))")
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
        .overlay(alignment: .topTrailing) {
            if !recommendation.live {
                staleBreadcrumb
                    .padding(Space.s2)
            }
        }
    }

    /// Cached/stale state is drawn with a dashed rim so it is distinguishable
    /// from a live panel at a glance, not only by reading the copy.
    private var staleBreadcrumb: some View {
        Text("STALE")
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .foregroundStyle(Brand.warning)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(
                Capsule().strokeBorder(
                    Brand.warning,
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
            )
    }

    // MARK: Corridor split

    /// The SVG's map hero, replaced with the one thing the wire actually
    /// measures: how the total time to cross splits between driving there and
    /// waiting at the booth.
    private func corridorCard(_ best: BorderCrossing216F) -> some View {
        let drive = max(0, best.driveMinutes)
        let wait = max(0, best.effectiveWaitMinutes)
        let total = max(1, drive + wait)
        return VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(best.name)
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(best.locale) · \(best.milesFromCaller) mi from the pickup anchor")
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(best.totalMinutes)m")
                        .font(.system(size: 24, weight: .bold).monospacedDigit())
                        .foregroundStyle(palette.textPrimary)
                    Text("TOTAL")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                        .foregroundStyle(palette.textTertiary)
                }
            }

            GeometryReader { geo in
                let width = geo.size.width
                HStack(spacing: 3) {
                    Capsule()
                        .fill(LinearGradient.primary)
                        .frame(width: max(2, width * CGFloat(drive) / CGFloat(total)))
                    Capsule()
                        .fill(severityColor(best.severity))
                }
                .frame(height: 10)
            }
            .frame(height: 10)

            HStack {
                Label("\(drive)m drive", systemImage: "steeringwheel")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: Space.s2)
                Label("\(wait)m wait", systemImage: "hourglass")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(severityColor(best.severity))
            }

            Divider().overlay(palette.borderFaint)
            factRow("WAIT SOURCE", best.source.uppercased())
            factRow("CONGESTION", best.severity.uppercased())
            Text("Drive minutes are a straight-line estimate at a truck-realistic average speed, not a routed ETA. The wait is whatever the source named above reported.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    // MARK: Crossing list

    private func crossingList(_ recommendation: BorderRecommendation216F) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if recommendation.recommendations.isEmpty {
                Text("No commercial port of entry on this corridor matched the filters for this load.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Space.s4)
            } else {
                ForEach(Array(recommendation.recommendations.enumerated()), id: \.element.id) { index, crossing in
                    crossingRow(crossing)
                    if index < recommendation.recommendations.count - 1 {
                        Divider().overlay(palette.borderFaint).padding(.leading, 56)
                    }
                }
            }
        }
        .addendaPanel(palette)
    }

    private func crossingRow(_ crossing: BorderCrossing216F) -> some View {
        HStack(alignment: .top, spacing: Space.s3) {
            AddendaIconChip(
                systemImage: "building.columns",
                tint: crossing.isBaseline ? Brand.info : Brand.neutral
            )
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
                    Text(crossing.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if crossing.isBaseline {
                        AddendaChip(text: "BEST", color: Brand.info)
                    }
                    Spacer(minLength: 0)
                }
                Text("\(crossing.locale) · \(crossing.milesFromCaller) mi · \(crossing.driveMinutes)m drive")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.s2) {
                    AddendaChip(
                        text: crossing.live ? "LIVE FEED" : "DIRECTORY AVG",
                        color: crossing.live ? Brand.success : Brand.warning
                    )
                    if crossing.fastLaneAvailable, let fast = crossing.fastWaitMinutes {
                        AddendaChip(text: "FAST \(fast)m", color: Brand.info)
                    } else if crossing.fastLaneAvailable {
                        AddendaChip(text: "FAST LANE · NO WAIT PUBLISHED", color: Brand.neutral)
                    }
                    if crossing.hazmatCapable {
                        AddendaChip(text: "HAZMAT", color: Brand.hazmat)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(crossing.effectiveWaitMinutes)m")
                    .font(.system(size: 16, weight: .bold).monospacedDigit())
                    .foregroundStyle(severityColor(crossing.severity))
                Text("WAIT")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                if !crossing.isBaseline {
                    Text(deltaLabel(crossing.deltaMinutes))
                        .font(EType.mono(.micro))
                        .foregroundStyle(crossing.deltaMinutes > 0 ? Brand.warning : Brand.success)
                }
            }
        }
        .padding(Space.s4)
    }

    private func deltaLabel(_ minutes: Int) -> String {
        if minutes == 0 { return "±0m" }
        return minutes > 0 ? "+\(minutes)m" : "\(minutes)m"
    }

    /// Congestion colour is bound to the server's own severity band, so the
    /// green/amber/red is a reading of state and not a decoration.
    private func severityColor(_ severity: String) -> Color {
        switch severity.lowercased() {
        case "low": return Brand.success
        case "moderate": return Brand.warning
        case "high", "critical": return Brand.danger
        default: return Brand.neutral
        }
    }

    // MARK: Program benchmark

    private func savingsCard(_ savings: BorderTimeSavings216F) -> some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            HStack(alignment: .top, spacing: Space.s3) {
                AddendaIconChip(systemImage: "figure.walk.motion", tint: Brand.info)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(savings.standardMinutes) min → \(savings.programMinutes) min")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                    Text("\(savings.savingsPercent)% typical reduction for \(BorderWaitStore216F.benchmarkProgramId) participants")
                        .font(EType.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Text("These are program-level reference figures, not a measurement of this load. No procedure reports whether this load's carrier or driver actually holds the credential, so the ranking above is not biased toward FAST lanes.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    // MARK: Blocked states

    private func blockedCard(_ block: BorderWaitBlock216F) -> some View {
        let copy: (String, String) = {
            switch block {
            case .noCoordinates:
                return ("Pickup anchor is not geocoded",
                        "Crossings are ranked by distance and drive time from the load's pickup point. This load has no geocoded pickup coordinate, so EusoTrip will not rank ports from a substituted location.")
            case .notCrossBorder:
                return ("Not a recorded US-MX or US-CA lane",
                        "Border-wait ranking applies to a lane whose origin and destination countries are recorded and different, on a corridor the port directory covers. Record both country codes on the load to rank its crossings.")
            }
        }()
        return HStack(alignment: .top, spacing: Space.s3) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Brand.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text(copy.0)
                    .font(EType.title)
                    .foregroundStyle(palette.textPrimary)
                Text(copy.1)
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    // MARK: Named backend gap

    private var routingGapNote: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            SectionLabel("COMMITTING A CROSSING")
            HStack(alignment: .top, spacing: Space.s3) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Brand.warning)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Re-routing from this screen is unavailable")
                        .font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                    Text("Pinning a load to a chosen port of entry would need a mutation that does not exist on the server. This screen ranks and explains; changing the plan happens on the load itself.")
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

    private static func cacheAgeLabel(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        if whole <= 0 { return "feed cache just refreshed" }
        if whole < 120 { return "feed cache \(whole)s old" }
        return "feed cache \(whole / 60) min old"
    }

    private static func formatTimestamp(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return value }
        return date.formatted(date: .omitted, time: .standard)
    }
}

#Preview("216F · Border Wait · Dark") {
    ShipperScreenWrap(palette: Theme.dark, currentSlot: .none) {
        ShipperBorderWaitLive()
    }
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("216F · Border Wait · Light") {
    ShipperScreenWrap(palette: Theme.light, currentSlot: .none) {
        ShipperBorderWaitLive()
    }
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
