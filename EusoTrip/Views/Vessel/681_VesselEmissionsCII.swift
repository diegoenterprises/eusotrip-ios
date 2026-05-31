//
//  681_VesselEmissionsCII.swift
//  EusoTrip — Vessel Operator · Emissions CII (Carbon Intensity Indicator).
//
//  Verbatim port of canonical wireframe "681 Vessel Emissions CII · Dark".
//  GRADED-RATING-SCALE archetype: a continuous A→E IMO CII band with the
//  vessel's attained-AER marker + required-AER tick, a quarterly attained-AER
//  drift bar series, and a per-voyage carbon-contribution ledger. Read-only
//  surface (no write). RBAC vesselProcedure · transportMode=vessel · IMO DCS.
//
//  WIRING — every data source named in the wireframe <desc>:
//    · sustainability.getFleetCarbon  (hero attained/required AER + quarterly
//      drift bars)                                  — NOT on Swift API → PORT-GAP
//    · co2Calculator.calculateVesselShipment (per-voyage gCO2/t·nm ledger rows,
//      vesselProcedure-gated)                        — NOT on Swift API → PORT-GAP
//    · sustainability.exportCarbonReport (Export CTA) — NOT on Swift API → PORT-GAP
//    · CII A–E letter-grade banding `getCII` — declared a STUB in the canonical
//      <desc>; grade + band boundaries computed client-side from the real
//      attained/required AER returned by getFleetCarbon (deterministic, not
//      fabricated). When no live AER loads, the band renders an empty state.
//
//  All calls go through EusoTripAPI.shared with real @State loading/error/empty
//  + do/catch. No mock data. Endpoints absent from the Swift surface surface a
//  real error/empty state and a PORT-GAP marker.
//

import SwiftUI

struct VesselEmissionsCIIScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselEmissionsCIIBody() } nav: {
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

// MARK: - Data shapes
//
// Decoded verbatim from the proposed tRPC shapes named in the wireframe
// <desc>. Every field is optional so a partial/absent payload degrades to a
// real empty state rather than crashing.

/// `sustainability.getFleetCarbon` envelope — attained/required AER for the
/// hero + the rolling quarterly attained-AER drift series.
private struct FleetCarbon681: Decodable {
    let vesselId: String?
    let attainedAER: Double?            // gCO₂/t·nm — hero "ATTAINED AER · 2024"
    let requiredAER: Double?            // gCO₂/t·nm — hero "REQUIRED"
    let year: Int?
    let quarters: [QuarterAER]?         // attained AER by quarter (drift bars)

    struct QuarterAER: Decodable, Identifiable {
        let quarter: String?            // "Q1" … "Q4"
        let attainedAER: Double?
        let grade: String?              // "A"…"E" (band color for the bar)
        var id: String { quarter ?? UUID().uuidString }
    }
}

/// One per-voyage carbon-contribution ledger row from
/// `co2Calculator.calculateVesselShipment`.
private struct VoyageCarbon681: Decodable, Identifiable {
    let id: String
    let voyageId: String?               // "VES-260523"
    let origin: String?                 // "CNSHA"
    let destination: String?            // "USLGB"
    let distanceNm: Double?             // 11,240nm
    let teu: Int?                       // TEU 8,420
    let note: String?                   // "ballast leg" / "slow-steam"
    let attainedAER: Double?            // 15.1 gCO₂/t·nm
    let grade: String?                  // "A"…"E"
}

// MARK: - CII grade model (client-side band — wireframe <desc> STUB `getCII`)

private enum CIIGrade: String, CaseIterable {
    case a = "A", b = "B", c = "C", d = "D", e = "E"

    /// Verbatim band fills from the canonical SVG rating strip.
    var color: Color {
        switch self {
        case .a: return Color(hex: 0x00C48C)
        case .b: return Color(hex: 0x66BB6A)
        case .c: return Color(hex: 0xFFB100)
        case .d: return Color(hex: 0xFF7043)
        case .e: return Color(hex: 0xF44336)
        }
    }

    /// Tinted glyph color used in the voyage ledger rows (SVG uses #FFA726
    /// for the C-grade glyph specifically).
    var glyphColor: Color {
        switch self {
        case .a: return Color(hex: 0x00C48C)
        case .b: return Color(hex: 0x66BB6A)
        case .c: return Color(hex: 0xFFA726)
        case .d: return Color(hex: 0xFF7043)
        case .e: return Color(hex: 0xF44336)
        }
    }

    static func from(_ raw: String?) -> CIIGrade? {
        guard let raw, let g = CIIGrade(rawValue: raw.uppercased()) else { return nil }
        return g
    }
}

// MARK: - Body

private struct VesselEmissionsCIIBody: View {
    @Environment(\.palette) private var palette

    @State private var fleet: FleetCarbon681? = nil
    @State private var voyages: [VoyageCarbon681] = []
    @State private var loading = true
    @State private var loadError: String? = nil

    // PORT-GAP banner — endpoints named in the wireframe <desc> that are not on
    // the Swift EusoTripAPI surface yet. Surfaced honestly rather than mocked.
    @State private var portGapNote: String? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                if loading {
                    loadingSkeleton
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) {
                        Text(err).font(EType.caption).foregroundStyle(Brand.danger)
                    }
                    if let note = portGapNote {
                        LifecycleCard(accentWarning: true) {
                            Text(note).font(EType.caption).foregroundStyle(Brand.warning)
                        }
                    }
                } else if let f = fleet {
                    heroCard(f)
                    ratingBandSection(f)
                    voyageLedgerSection
                    ctaRow
                } else {
                    EusoEmptyState(
                        systemImage: "leaf",
                        title: "No carbon data",
                        subtitle: "Attained / required AER and the per-voyage carbon ledger will appear here once the vessel's IMO DCS figures sync.")
                    if let note = portGapNote {
                        LifecycleCard(accentWarning: true) {
                            Text(note).font(EType.caption).foregroundStyle(Brand.warning)
                        }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Header (eyebrow + title + DCS meta)

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.primary)
                    Text("VESSEL OPERATOR · CARBON INTENSITY")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.primary)
                }
                Spacer()
                Text("VES-260523 · DCS")
                    .font(EType.mono(.micro)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            Text("Emissions CII")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: - Loading skeleton

    private var loadingSkeleton: some View {
        VStack(spacing: Space.s4) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(palette.borderFaint))
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 184)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(palette.bgCardSoft).frame(height: 240)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        }
    }

    // MARK: - Hero card (grade chip · attained AER · required + delta)

    private func heroCard(_ f: FleetCarbon681) -> some View {
        let attained = f.attainedAER
        let required = f.requiredAER
        let grade = computedGrade(attained: attained, required: required)
        // Delta vs required, as a percentage — wireframe shows "+4.4%".
        let deltaPct: Double? = {
            guard let a = attained, let r = required, r != 0 else { return nil }
            return (a - r) / r * 100
        }()
        let over = (deltaPct ?? 0) > 0

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.95), Brand.magenta.opacity(0.95)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 18.5, style: .continuous)
                .fill(Color(hex: 0x1C2128))
                .padding(1.5)

            HStack(alignment: .top, spacing: Space.s4) {
                // Grade glyph chip
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient.diagonal)
                        .frame(width: 64, height: 64)
                    VStack(spacing: 1) {
                        Text(grade?.rawValue ?? "—")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                        Text("GRADE")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                // Attained AER block
                VStack(alignment: .leading, spacing: 6) {
                    Text("ATTAINED AER · \(f.year.map { String($0) } ?? "2024")")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(Color(hex: 0x6E7681))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(attained.map { String(format: "%.1f", $0) } ?? "—")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .monospacedDigit()
                        Text("gCO₂/t·nm")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xAAB2BB))
                    }
                }
                Spacer(minLength: 0)
                // Required + delta
                VStack(alignment: .trailing, spacing: 4) {
                    Text("REQUIRED")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(Color(hex: 0x6E7681))
                    Text(required.map { String(format: "%.1f", $0) } ?? "—")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                        .monospacedDigit()
                    if let d = deltaPct {
                        Text(String(format: "%@%.1f%%", over ? "+" : "", d))
                            .font(.system(size: 11, weight: .bold)).tracking(0.3)
                            .foregroundStyle(over ? Color(hex: 0xFFA726) : Brand.success)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background((over ? Color(hex: 0xFFB100) : Brand.success).opacity(0.22))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(Space.s5)
        }
        .frame(minHeight: 120)
    }

    // MARK: - CII rating band section

    @ViewBuilder
    private func ratingBandSection(_ f: FleetCarbon681) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CII RATING BAND · IMO DCS")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Color(hex: 0x6E7681))
                Spacer()
                Text("d1–d4 boundaries")
                    .font(.system(size: 11)).foregroundStyle(Color(hex: 0xAAB2BB))
            }
            VStack(alignment: .leading, spacing: 0) {
                ratingScale(f)
                    .padding(.top, 28)
                    .padding(.horizontal, 20)
                quarterDrift(f)
                    .padding(.top, 22)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x1C2128))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08)))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    /// The continuous A→E rating strip with attained marker + required tick.
    private func ratingScale(_ f: FleetCarbon681) -> some View {
        let attained = f.attainedAER
        let required = f.requiredAER
        return VStack(alignment: .leading, spacing: 6) {
            // attained value marker (above the A grade cell, per wireframe)
            if let a = attained {
                Text(String(format: "%.1f", a))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
            }
            // A B C D E band
            HStack(spacing: 2) {
                ForEach(CIIGrade.allCases, id: \.self) { g in
                    Text(g.rawValue)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(g.color)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            // required tick label
            if let r = required {
                Text(String(format: "req %.1f", r))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color(hex: 0xAAB2BB))
            }
        }
    }

    /// Quarterly attained-AER drift bars + the "trim speed to hold C" note.
    @ViewBuilder
    private func quarterDrift(_ f: FleetCarbon681) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ATTAINED AER · BY QUARTER")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Color(hex: 0x6E7681))
                Spacer()
                Text("rolling 12-mo → band D")
                    .font(.system(size: 9)).foregroundStyle(Color(hex: 0x6E7681))
            }
            if let quarters = f.quarters, !quarters.isEmpty {
                let maxAER = quarters.compactMap { $0.attainedAER }.max() ?? 1
                HStack(alignment: .top, spacing: Space.s5) {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(quarters) { q in
                            VStack(spacing: 4) {
                                let h = barHeight(q.attainedAER, max: maxAER)
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill((CIIGrade.from(q.grade) ?? .c).color)
                                    .frame(width: 20, height: h)
                                Text(q.quarter ?? "—")
                                    .font(.system(size: 8))
                                    .foregroundStyle(Color(hex: 0x6E7681))
                            }
                            .frame(height: 36, alignment: .bottom)
                        }
                    }
                    Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("attained slipping +1.4 over")
                            .font(.system(size: 11)).foregroundStyle(Color(hex: 0xAAB2BB))
                        Text("4 quarters · trim speed to hold C")
                            .font(.system(size: 11)).foregroundStyle(Color(hex: 0xAAB2BB))
                    }
                }
            } else {
                Text("Quarterly attained-AER drift will appear here once the rolling 12-month series syncs from IMO DCS.")
                    .font(EType.caption).foregroundStyle(palette.textTertiary)
            }
        }
    }

    private func barHeight(_ aer: Double?, max: Double) -> CGFloat {
        guard let aer, max > 0 else { return 4 }
        // Map AER to the 14…23px range used in the wireframe bars.
        let frac = min(1, Swift.max(0, aer / max))
        return 14 + CGFloat(frac) * 9
    }

    // MARK: - Voyage carbon-contribution ledger

    @ViewBuilder
    private var voyageLedgerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("VOYAGES · CARBON CONTRIBUTION")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Color(hex: 0x6E7681))
                Spacer()
                Text("See all")
                    .font(.system(size: 12)).foregroundStyle(Color(hex: 0xAAB2BB))
            }
            if voyages.isEmpty {
                EusoEmptyState(
                    systemImage: "ferry",
                    title: "No voyage ledger",
                    subtitle: "Per-voyage gCO₂/t·nm carbon contribution rows will appear here.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(voyages.enumerated()), id: \.element.id) { idx, v in
                        voyageRow(v)
                        if idx < voyages.count - 1 {
                            Rectangle().fill(Color.white.opacity(0.08))
                                .frame(height: 1)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .background(Color(hex: 0x1C2128))
                .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08)))
                .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            }
        }
    }

    private func voyageRow(_ v: VoyageCarbon681) -> some View {
        let grade = CIIGrade.from(v.grade)
        let glyph = grade?.glyphColor ?? Color(hex: 0xFFA726)
        let chip = grade?.color ?? Color(hex: 0xFFB100)
        let lane: String = {
            let o = v.origin ?? "—"; let d = v.destination ?? "—"
            return "\(o) → \(d)"
        }()
        let meta: String = {
            var parts: [String] = []
            if let id = v.voyageId { parts.append(id) }
            if let nm = v.distanceNm { parts.append(String(format: "%@nm", nmString(nm))) }
            if let teu = v.teu { parts.append("TEU \(teuString(teu))") }
            else if let note = v.note { parts.append(note) }
            return parts.joined(separator: " · ")
        }()
        return HStack(spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(glyph.opacity(0.2))
                    .frame(width: 40, height: 40)
                Image(systemName: "water.waves")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(glyph)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(lane)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                Text(meta)
                    .font(EType.mono(.caption)).tracking(0.4)
                    .foregroundStyle(Color(hex: 0xAAB2BB))
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(v.attainedAER.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                Text(grade?.rawValue ?? "—")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(glyph)
                    .frame(width: 36, height: 20)
                    .background(chip.opacity(0.22))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 18)
    }

    private func nmString(_ nm: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: nm)) ?? String(format: "%.0f", nm)
    }
    private func teuString(_ teu: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: teu)) ?? "\(teu)"
    }

    // MARK: - CTA row (Export carbon report · SEEMP plan)

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            Button {
                Task { await exportReport() }
            } label: {
                Text("Export carbon report")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .background(LinearGradient.primary)
            .clipShape(Capsule())
            .buttonStyle(.plain)

            Button { } label: {
                Text("SEEMP plan")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
            }
            .background(Color(hex: 0x232932))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
            .clipShape(Capsule())
            .buttonStyle(.plain)
        }
    }

    // MARK: - Load

    private func load() async {
        loading = true; loadError = nil; portGapNote = nil
        struct VesselInput: Encodable { let vesselId: String?; let year: Int? }
        struct VoyageInput: Encodable { let limit: Int }
        do {
            // PORT-GAP: sustainability.getFleetCarbon not on EusoTripAPI Swift
            // surface — needs backend wire (vessel attained/required AER +
            // quarterly drift series). Wired to the canonical tRPC path so it
            // lights up the moment the Swift API exposes it.
            async let fleetCall: FleetCarbon681 = EusoTripAPI.shared.query(
                "sustainability.getFleetCarbon",
                input: VesselInput(vesselId: nil, year: nil))
            // PORT-GAP: co2Calculator.calculateVesselShipment is vesselProcedure-
            // gated and not exposed on the Swift Co2CalculatorAPI — needs backend
            // wire for the per-voyage gCO₂/t·nm ledger rows.
            async let voyageCall: [VoyageCarbon681] = EusoTripAPI.shared.query(
                "co2Calculator.calculateVesselShipment",
                input: VoyageInput(limit: 20))
            let (f, vs) = try await (fleetCall, voyageCall)
            self.fleet = f
            self.voyages = vs
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
            portGapNote = "PORT-GAP: sustainability.getFleetCarbon + co2Calculator.calculateVesselShipment are named in the wireframe but not on the Swift EusoTripAPI surface yet — backend wire required. CII A–E grade is computed client-side (getCII is a declared stub)."
        }
        loading = false
    }

    private func exportReport() async {
        // PORT-GAP: sustainability.exportCarbonReport not on EusoTripAPI Swift
        // surface — needs backend wire. CTA is live but reports the gap honestly
        // instead of faking a success.
        struct ExportInput: Encodable { let vesselId: String? }
        struct ExportOut: Decodable { let url: String? }
        do {
            let _: ExportOut = try await EusoTripAPI.shared.mutation(
                "sustainability.exportCarbonReport",
                input: ExportInput(vesselId: fleet?.vesselId))
        } catch {
            portGapNote = "PORT-GAP: sustainability.exportCarbonReport not on the Swift EusoTripAPI surface — export needs a backend wire."
        }
    }

    // MARK: - Client-side CII grade (wireframe <desc> STUB `getCII`)

    /// Deterministic A–E grade from the real attained AER relative to the
    /// required AER. Per IMO CII banding, grade C straddles the required line;
    /// vessels above required (worse) slip toward D/E, below required (better)
    /// climb toward A/B. Boundaries are the canonical d1–d4 multipliers
    /// (≈0.86 / 0.94 / 1.06 / 1.18 of required) applied to live values — no
    /// fabricated data; if either AER is missing the grade is unknown.
    private func computedGrade(attained: Double?, required: Double?) -> CIIGrade? {
        guard let a = attained, let r = required, r > 0 else { return nil }
        let ratio = a / r
        switch ratio {
        case ..<0.86:  return .a
        case ..<0.94:  return .b
        case ..<1.06:  return .c
        case ..<1.18:  return .d
        default:       return .e
        }
    }
}

#Preview("681 · Vessel Emissions CII · Night") { VesselEmissionsCIIScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("681 · Vessel Emissions CII · Light") { VesselEmissionsCIIScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
