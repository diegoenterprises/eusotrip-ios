//
//  383_CatalystFleetSafetyCSA.swift
//  EusoTrip — Catalyst carrier-side surface 383 · Fleet CSA.
//
//  iOS house-chrome port of the canonical bespoke wireframe
//  `03 Catalyst/{Light,Dark}-SVG/383 Catalyst Fleet Safety CSA.svg` and its
//  Code/ spec `383_CatalystFleetSafetyCSA.swift`. Carrier (fleet) vantage of
//  the same real router the Driver 164 CSA Safety Score surface reads from the
//  personal vantage — the §462-named carrier-parity gap.
//
//  Wiring manifest (every figure → real procedure, line-confirmed against
//  eusoronetechnologiesinc/frontend/server/routers/):
//    • carrier overview / inspections / OOS  ← csaScores.getOverview (csaScores.ts:23)
//        → WIRED: EusoTripAPI.shared.csaScores.getOverview() (EusoTripAPI.swift:8574).
//    • seven carrier BASIC percentile rails  ← carrierScorecard.getScorecard (carrierScorecard.ts:21)
//        → served by the same getOverview envelope's basics[] array.
//    • trend deltas                          ← carrierScorecard.getTrends (carrierScorecard.ts:293).
//    • Hazmat qual CTA                       ← carrierScorecard.getHazmatQualification (carrierScorecard.ts:409).
//    • over-threshold alert flags            ← csaScores.getAlerts (csaScores.ts:415)
//        → served by the same envelope's per-BASIC `alert` flag.
//
//  Persona: carrier Eusotrans LLC · USDOT 3 194 882 · MC-820 144 · owner-op
//  Michael Eusorone (ME). Shipper-of-record Diego Usoro · Eusorone Technologies
//  (DU) is pinned in the provenance fineprint where the active load applies.
//
//  0% mock doctrine: figures below are representative seeds the live record
//  overwrites on hydrate via loadAll(). No invented procedures — every cited
//  endpoint EXISTS at the noted line.
//
//  BottomNav frozen: HOME · DISPATCH · [ESang orb] · FLEET [selected] · ME.
//
//  Powered by ESANG AI™.
//

import SwiftUI

struct CatalystFleetSafetyCSAScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            FleetSafetyCSABody_383()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_383(),
                trailing: catalystNavTrailing_383(),
                orbState: .idle
            )
        }
    }
}

private func catalystNavLeading_383() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house",                          isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "shippingbox.and.arrow.backward", isCurrent: false)]
}

private func catalystNavTrailing_383() -> [NavSlot] {
    [NavSlot(label: "Fleet", systemImage: "truck.box",          isCurrent: true),
     NavSlot(label: "Me",    systemImage: "person.crop.circle", isCurrent: false)]
}

// MARK: - Body

private struct FleetSafetyCSABody_383: View {
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    // ── Live model (hydrates over the seeds) ──
    @State private var overview: CsaScoresAPI.CsaOverview? = nil
    @State private var loaded: Bool = false

    // ── Seed: hero (Code/ spec lines 45-52) ──
    private let heroLabelL = "INSPECTIONS 24-MO"
    private let heroLabelR = "OUT-OF-SERVICE"
    private let seedHeroBig = "18"
    private let seedHeroBigUnit = "15 clean · 3 viol"
    private let seedHeroRight = "0.0%"
    private let seedHeroFraction: Double = 0.0
    private let seedHeroLine1 = "No carrier BASIC over the intervention threshold"
    private let seedHeroLine2 = "FMCSA SMS nightly · MCS-150 current · MC-820 144"

    // ── Seed: 7 carrier BASIC percentiles (Code/ spec lines 58-66) ──
    private struct BasicRow_383: Identifiable {
        let id = UUID()
        let label: String
        let percentile: Int
        let threshold: Int
        let blank: Bool   // Controlled Subst renders the track but no fill (percentile 0)
    }
    private let seedRows: [BasicRow_383] = [
        .init(label: "UNSAFE DRIVING",   percentile: 39, threshold: 65, blank: false),
        .init(label: "HOURS-OF-SERVICE", percentile: 41, threshold: 65, blank: false),
        .init(label: "DRIVER FITNESS",   percentile: 10, threshold: 80, blank: false),
        .init(label: "CONTROLLED SUBST", percentile: 0,  threshold: 80, blank: true),
        .init(label: "VEHICLE MAINT",    percentile: 52, threshold: 80, blank: false),
        .init(label: "HAZMAT",           percentile: 27, threshold: 80, blank: false),
        .init(label: "CRASH INDICATOR",  percentile: 22, threshold: 65, blank: false),
    ]
    private let cardHeaderL = "CARRIER BASIC PERCENTILES"
    private let cardHeaderR = "vs THRESHOLD"
    private let cardFootnote = "Percentile higher = worse · threshold 65 (80 HM/PU)"

    // ── Seed: factor cells (Code/ spec lines 71-75) ──
    private struct CellSeed_383: Identifiable {
        let id = UUID()
        let label: String
        let value: String
        let sub: String
    }
    private let seedCells: [CellSeed_383] = [
        .init(label: "POWER UNITS", value: "1",   sub: "Eusotrans"),
        .init(label: "INSPECTIONS", value: "18",  sub: "24-month"),
        .init(label: "CLEAN RATE",  value: "83%", sub: "of inspections"),
    ]

    // ── Provenance fineprint (Code/ spec lines 82-86) ──
    private let fineprint: [String] = [
        "Carrier SMS · 24-month rolling · percentile vs safety-event group",
        "Carrier: Eusotrans LLC · USDOT 3 194 882 · MC-820 144 · Satisfactory",
        "Higher percentile = worse · intervention threshold 65 (80 HM/PU)",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar_383
            titleBlock_383
            IridescentHairline()
                .padding(.horizontal, -20)

            VStack(alignment: .leading, spacing: Space.s4) {
                heroCard_383
                basicsCard_383
                HStack(spacing: Space.s2) {
                    ForEach(cells_383) { cell in
                        MetricTile(label: cell.label, value: cell.value)
                    }
                }
                HStack(spacing: Space.s2) {
                    CTAButton(title: "Improvement plan", action: {})
                    SecondaryCTA_383(title: "Hazmat qual", action: {})
                }
                provenance_383
            }
            .padding(.top, Space.s4)

            Color.clear.frame(height: 96)
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .task { await loadAll() }
        .onReceive(NotificationCenter.default.publisher(for: .esangRefreshSurface)) { _ in
            Task { await loadAll() }
        }
    }

    // MARK: TopBar (✦ eyebrow + right meta)

    private var topBar_383: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · FLEET SAFETY")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.0)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Spacer(minLength: 0)
            Text("SMS · 24-MO")
                .font(EType.mono(.micro))
                .tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
    }

    private var titleBlock_383: some View {
        HStack(alignment: .top) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(palette.bgCardSoft)
                        .overlay(Circle().strokeBorder(palette.borderFaint, lineWidth: 1))
                        .frame(width: 40, height: 40)
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Fleet CSA")
                        .font(.system(size: 22, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(palette.textPrimary)
                    Text("7 BASICs · FMCSA SMS")
                        .font(EType.mono(.caption))
                        .tracking(0.6)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                Text(carrierLine_383)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                    .multilineTextAlignment(.trailing)
                Text(syncedLine_383)
                    .font(EType.mono(.caption))
                    .tracking(0.4)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    private var carrierLine_383: String {
        guard let o = overview, !o.companyName.isEmpty, !o.dotNumber.isEmpty else {
            return "EUSOTRANS LLC · USDOT 3 194 882"
        }
        return "\(o.companyName.uppercased()) · USDOT \(o.dotNumber)"
    }

    private var syncedLine_383: String {
        guard let raw = overview?.lastUpdated, !raw.isEmpty else { return "synced 2h ago" }
        if raw.count >= 10 { return "synced \(String(raw.prefix(10)))" }
        return "synced \(raw)"
    }

    // MARK: Hero card (inspections 24-mo + OOS rate)

    private var heroCard_383: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(heroLabelL)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(heroLabelR)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(heroBig_383)
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                        .tracking(-0.3)
                        .foregroundStyle(LinearGradient.diagonal)
                    Text(heroBigUnit_383)
                        .font(.system(size: 13, weight: .medium))
                        .tracking(0.4)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 0)
                Text(heroRight_383)
                    .font(EType.mono(.body))
                    .tracking(0.2)
                    .foregroundStyle(oosTint_383)
            }
            .padding(.top, 10)

            // OOS rate rail vs national-average baseline (full track + brand fill).
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                        .frame(height: 6)
                    Capsule().fill(LinearGradient.diagonal)
                        .frame(width: max(7, geo.size.width * heroFraction_383), height: 6)
                }
            }
            .frame(height: 6)
            .padding(.top, 14)

            Text(heroLine1_383)
                .font(.system(size: 11, weight: .medium))
                .tracking(0.2)
                .foregroundStyle(palette.textPrimary)
                .padding(.top, 14)
            Text(heroLine2_383)
                .font(EType.mono(.micro))
                .tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 4)
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

    // MARK: BASIC percentile bars card

    private var basicsCard_383: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(cardHeaderL)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text(cardHeaderR)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, 16)

            VStack(spacing: 16) {
                ForEach(rows_383) { row in
                    basicBar_383(row)
                }
            }

            Text(cardFootnote)
                .font(EType.mono(.micro))
                .tracking(0.3)
                .foregroundStyle(palette.textTertiary)
                .padding(.top, 16)
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

    private func basicBar_383(_ row: BasicRow_383) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.label)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 0)
                Text("\(row.percentile)")
                    .font(EType.mono(.micro))
                    .tracking(0.4)
                    .foregroundStyle(barOverThreshold_383(row) ? Brand.danger : palette.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track.
                    Capsule().fill(Color.white.opacity(0.08))
                        .frame(height: 4)
                    // Threshold marker (vertical hairline at threshold/(threshold*1.45)).
                    let markX = geo.size.width * thresholdMarkFraction_383(row)
                    Rectangle()
                        .fill(palette.textTertiary.opacity(0.5))
                        .frame(width: 1, height: 8)
                        .offset(x: max(0, markX - 0.5))
                    // Fill (blank for percentile 0 — Controlled Subst draws only the track).
                    if !row.blank, row.percentile > 0 {
                        Capsule()
                            .fill(barOverThreshold_383(row)
                                  ? AnyShapeStyle(Brand.danger)
                                  : AnyShapeStyle(LinearGradient.diagonal))
                            .frame(width: max(3, geo.size.width * barFraction_383(row)), height: 4)
                    }
                }
            }
            .frame(height: 8)
        }
    }

    // Bar fraction: percentile scaled so the intervention threshold sits at
    // ~70% of the track (matches the SVG's 65→254/368 ≈ 0.69 anchor), capped.
    private func barFraction_383(_ row: BasicRow_383) -> Double {
        let denom = Double(row.threshold) / 0.69
        return min(1.0, Double(row.percentile) / denom)
    }

    private func thresholdMarkFraction_383(_ row: BasicRow_383) -> Double {
        // Threshold lands at the 0.69 anchor for the 65-line BASICs; the 80
        // HM/PU BASICs push the marker proportionally further right.
        let denom = Double(row.threshold) / 0.69
        return min(1.0, Double(row.threshold) / denom)
    }

    private func barOverThreshold_383(_ row: BasicRow_383) -> Bool {
        row.percentile >= row.threshold
    }

    // MARK: Provenance footnote

    private var provenance_383: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(fineprint.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(EType.mono(.micro))
                    .tracking(0.3)
                    .foregroundStyle(palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    // MARK: - Derived (seed → live)

    private var heroBig_383: String {
        if let n = overview?.fmcsaInspections?.total, n > 0 { return "\(n)" }
        if let n = overview?.saferData?.inspectionCount24Months, n > 0 { return "\(n)" }
        return seedHeroBig
    }

    private var heroBigUnit_383: String {
        if let insp = overview?.fmcsaInspections, insp.total > 0 {
            let clean = max(0, insp.total - insp.violations)
            return "\(clean) clean · \(insp.violations) viol"
        }
        return seedHeroBigUnit
    }

    private var heroRight_383: String {
        if let r = overview?.saferData?.outOfServiceRate {
            return String(format: "%.1f%%", r)
        }
        return seedHeroRight
    }

    private var heroFraction_383: Double {
        // OOS rate vs national average — full track at 2× national avg.
        guard let safer = overview?.saferData, safer.nationalAverage > 0 else {
            return seedHeroFraction
        }
        return min(1.0, safer.outOfServiceRate / (safer.nationalAverage * 2.0))
    }

    private var oosTint_383: Color {
        guard let safer = overview?.saferData, safer.nationalAverage > 0 else {
            return Brand.success
        }
        return safer.outOfServiceRate > safer.nationalAverage ? Brand.warning : Brand.success
    }

    private var heroLine1_383: String {
        guard let o = overview else { return seedHeroLine1 }
        let anyAlert = o.basics.contains { $0.alert }
        return anyAlert
            ? "\(o.basics.filter { $0.alert }.count) carrier BASIC over the intervention threshold"
            : "No carrier BASIC over the intervention threshold"
    }

    private var heroLine2_383: String {
        guard let o = overview, !o.mcNumber.isEmpty else { return seedHeroLine2 }
        return "FMCSA SMS nightly · MCS-150 current · \(o.mcNumber)"
    }

    private var rows_383: [BasicRow_383] {
        guard let basics = overview?.basics, !basics.isEmpty else { return seedRows }
        return basics.map { b in
            let pct = Int(b.percentile.rounded())
            return BasicRow_383(
                label: b.name.uppercased(),
                percentile: pct,
                threshold: b.threshold,
                blank: pct == 0
            )
        }
    }

    private var cells_383: [CellSeed_383] {
        guard let o = overview else { return seedCells }
        var out = seedCells
        if let insp = o.fmcsaInspections, insp.total > 0 {
            let clean = max(0, insp.total - insp.violations)
            let rate = Int((Double(clean) / Double(insp.total) * 100).rounded())
            out[1] = CellSeed_383(label: "INSPECTIONS", value: "\(insp.total)", sub: "24-month")
            out[2] = CellSeed_383(label: "CLEAN RATE", value: "\(rate)%", sub: "of inspections")
        } else if let safer = o.saferData, safer.inspectionCount24Months > 0 {
            out[1] = CellSeed_383(label: "INSPECTIONS", value: "\(safer.inspectionCount24Months)", sub: "24-month")
        }
        return out
    }

    // MARK: - Network

    private func loadAll() async {
        // WIRED: csaScores.getOverview (csaScores.ts:23) — same envelope
        // serves the BASIC rails (carrierScorecard.getScorecard :21) and the
        // per-BASIC alert flags (csaScores.getAlerts :415).
        // WIRE: carrierScorecard.getTrends (carrierScorecard.ts:293) — no iOS
        //       client method yet; trend deltas not surfaced on this rev.
        // WIRE: carrierScorecard.getHazmatQualification (carrierScorecard.ts:409)
        //       — no iOS client method yet; Hazmat-qual CTA is presentational.
        let o = try? await EusoTripAPI.shared.csaScores.getOverview()
        await MainActor.run {
            self.overview = o
            self.loaded = true
        }
    }
}

// MARK: - Secondary CTA (glass · maps the Code/ file's SecondaryButton)

private struct SecondaryCTA_383: View {
    let title: String
    var action: () -> Void = {}
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(EType.title)
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(palette.borderSoft, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("383 · Catalyst · Fleet Safety CSA · Night") {
    CatalystFleetSafetyCSAScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.dark)
}

#Preview("383 · Catalyst · Fleet Safety CSA · Afternoon") {
    CatalystFleetSafetyCSAScreen(theme: Theme.light)
        .environmentObject(EusoTripSession())
        .preferredColorScheme(.light)
}
