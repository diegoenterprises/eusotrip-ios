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
//  WIRING:
//    · vesselShipments.getVesselShipments     — anchors the ledger to real vessel bookings.
//    · vesselShipments.getVesselShipmentDetail — resolves live origin/destination port labels.
//    · co2Calculator.calculateVesselShipment  — computes per-booking CII attained AER + rating.
//    · Export CTA                             — writes a CSV from those live rows and opens ShareLink.
//    · SEEMP plan CTA                         — opens a data-derived compliance plan from the same CII evidence.
//
//  All calls go through EusoTripAPI.shared with real @State loading/error/empty
//  + do/catch. No mock data, no synthetic success, no hardcoded voyage rows.
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

/// Locally derived fleet card from real vessel booking CII calculations.
private struct FleetCarbon681 {
    let vesselId: String?
    let attainedAER: Double?            // gCO₂/t·nm — hero "ATTAINED AER · 2024"
    let requiredAER: Double?            // gCO₂/t·nm — hero "REQUIRED"
    let grade: String?
    let year: Int?
    let sourceCount: Int
    let quarters: [QuarterAER]?         // attained AER by quarter (drift bars)

    struct QuarterAER: Identifiable {
        let quarter: String?            // "Q1" … "Q4"
        let attainedAER: Double?
        let grade: String?              // "A"…"E" (band color for the bar)
        var id: String { quarter ?? UUID().uuidString }
    }
}

/// One per-voyage carbon-contribution ledger row from
/// `co2Calculator.calculateVesselShipment`.
private struct VoyageCarbon681: Identifiable {
    let id: String
    let voyageId: String?               // "VES-260523"
    let origin: String?                 // "CNSHA"
    let destination: String?            // "USLGB"
    let createdAt: String?
    let distanceNm: Double?             // 11,240nm
    let teu: Double?                    // TEU 8,420
    let note: String?                   // "ballast leg" / "slow-steam"
    let attainedAER: Double?            // 15.1 gCO₂/t·nm
    let grade: String?                  // "A"…"E"
}

private struct VesselShipmentList681: Decodable {
    let shipments: [VesselShipmentRow681]?
}

private struct VesselShipmentRow681: Decodable {
    let id: Int?
    let bookingNumber: String?
    let voyageNumber: String?
    let serviceRoute: String?
    let numberOfContainers: Int?
    let containerSize: String?
    let status: String?
    let originPortId: Int?
    let destinationPortId: Int?
    let createdAt: String?
}

private struct VesselShipmentDetail681: Decodable {
    let id: Int?
    let bookingNumber: String?
    let voyageNumber: String?
    let serviceRoute: String?
    let numberOfContainers: Int?
    let containerSize: String?
    let status: String?
    let createdAt: String?
    let originPort: Port681?
    let destinationPort: Port681?
}

private struct Port681: Decodable {
    let name: String?
    let unlocode: String?
    let city: String?
    let state: String?
    let country: String?
}

private struct VesselCIICalc681: Decodable {
    let distanceNm: Double?
    let fuelConsumedTonnes: Double?
    let fuelType: String?
    let co2Tonnes: Double?
    let co2PerTeu: Double?
    let teuCount: Double?
    let ciiAttained: Double?
    let ciiRating: String?
    let dataAvailable: Bool?
    let reason: String?
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
    @State private var exporting = false
    @State private var actionMessage: String? = nil
    @State private var actionError: String? = nil
    @State private var exportURL: URL? = nil
    @State private var showSEEMPPlan = false

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
                } else if let f = fleet {
                    heroCard(f)
                    ratingBandSection(f)
                    // Wave A2 — RadialFillGauge de-orphaned onto its census
                    // host: the REAL attained AER on the IMO A–E dial with
                    // the required-AER tick. Band boundaries are the SAME
                    // deterministic ratio thresholds `computedGrade` already
                    // applies (0.86/0.94/1.06/1.18 × required); mounts only
                    // when both live AER figures exist.
                    ciiGaugeSection(f)
                    voyageLedgerSection
                    ctaRow
                    actionFeedback
                } else if !voyages.isEmpty {
                    EusoEmptyState(
                        systemImage: "leaf",
                        title: "CII pending",
                        subtitle: "Your vessel bookings loaded, but the calculator does not have enough fuel, port-coordinate, and TEU data to produce an attained AER yet.")
                    voyageLedgerSection
                    ctaRow
                    actionFeedback
                } else {
                    EusoEmptyState(
                        systemImage: "leaf",
                        title: "No carbon data",
                        subtitle: "Attained AER and per-voyage carbon rows appear once a vessel booking exists with enough port, TEU, and fuel data for CII.")
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showSEEMPPlan) { seempPlanSheet }
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
                Text("LIVE CII · DCS")
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
        let grade = CIIGrade.from(f.grade) ?? computedGrade(attained: attained, required: required)
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
                        Text(grade?.rawValue ?? "-")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                        Text("GRADE")
                            .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                // Attained AER block
                VStack(alignment: .leading, spacing: 6) {
                    Text("ATTAINED AER · \(f.year.map { String($0) } ?? "—")")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(Color(hex: 0x6E7681))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(attained.map { String(format: "%.1f", $0) } ?? "-")
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
                    Text(required.map { String(format: "%.1f", $0) } ?? "-")
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
                    Text("\(f.sourceCount) live row\(f.sourceCount == 1 ? "" : "s")")
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
                Text(f.quarters?.isEmpty == false ? "live buckets" : "awaiting DCS")
                    .font(.system(size: 9)).foregroundStyle(Color(hex: 0x6E7681))
            }
            if let quarters = f.quarters, !quarters.isEmpty {
                let maxAER = quarters.compactMap { $0.attainedAER }.max() ?? 1
                let summary = quarterSummary(quarters)
                HStack(alignment: .top, spacing: Space.s5) {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(quarters) { q in
                            VStack(spacing: 4) {
                                let h = barHeight(q.attainedAER, max: maxAER)
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill((CIIGrade.from(q.grade) ?? .c).color)
                                    .frame(width: 20, height: h)
                                Text(q.quarter ?? "-")
                                    .font(.system(size: 8))
                                    .foregroundStyle(Color(hex: 0x6E7681))
                            }
                            .frame(height: 36, alignment: .bottom)
                        }
                    }
                    Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.primary)
                            .font(.system(size: 11)).foregroundStyle(Color(hex: 0xAAB2BB))
                        Text(summary.secondary)
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
            let o = v.origin ?? "-"; let d = v.destination ?? "-"
            return "\(o) → \(d)"
        }()
        let meta: String = {
            var parts: [String] = []
            if let id = v.voyageId { parts.append(id) }
            if let nm = v.distanceNm { parts.append(String(format: "%@nm", nmString(nm))) }
            if let teu = v.teu { parts.append("TEU \(teuString(teu))") }
            if let note = v.note { parts.append(note) }
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
                Text(v.attainedAER.map { String(format: "%.1f", $0) } ?? "-")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .monospacedDigit()
                Text(grade?.rawValue ?? "-")
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
    private func teuString(_ teu: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = teu.rounded() == teu ? 0 : 1
        return f.string(from: NSNumber(value: teu)) ?? String(format: "%.1f", teu)
    }

    // MARK: - CTA row (Export carbon report · SEEMP plan)

    private var ctaRow: some View {
        HStack(spacing: Space.s3) {
            Button {
                Task { await exportReport() }
            } label: {
                Text(exporting ? "Preparing…" : "Export carbon report")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .background(LinearGradient.primary)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .buttonStyle(.plain)
            .disabled(exporting)

            Button { showSEEMPPlan = true } label: {
                Text("SEEMP plan")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 148, height: 48)
            }
            .background(Color(hex: 0x232932))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var actionFeedback: some View {
        if let actionError {
            LifecycleCard(accentDanger: true) {
                Text(actionError).font(EType.caption).foregroundStyle(Brand.danger)
            }
        } else if let actionMessage {
            LifecycleCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(actionMessage).font(EType.caption).foregroundStyle(Brand.success)
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share carbon report", systemImage: "square.and.arrow.up")
                                .font(EType.caption.weight(.semibold))
                        }
                    }
                }
            }
        }
    }

    private var seempPlanSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.s4) {
                    LifecycleCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SEEMP evidence")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(palette.textPrimary)
                            Text(seempEvidenceLine)
                                .font(EType.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                    LifecycleCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Action plan")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(palette.textPrimary)
                            ForEach(seempActions, id: \.self) { item in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Brand.success)
                                    Text(item)
                                        .font(EType.caption)
                                        .foregroundStyle(palette.textSecondary)
                                }
                            }
                        }
                    }
                    ShareLink(item: seempPacketText) {
                        Label("Share SEEMP plan", systemImage: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(LinearGradient.primary)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .navigationTitle("SEEMP plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showSEEMPPlan = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Load

    private func load() async {
        loading = true
        loadError = nil
        actionMessage = nil
        actionError = nil
        exportURL = nil
        defer { loading = false }

        struct ListInput: Encodable { let limit: Int; let offset: Int }
        struct DetailInput: Encodable { let id: Int }
        struct CalcInput: Encodable { let shipmentId: Int }

        do {
            let list: VesselShipmentList681 = try await EusoTripAPI.shared.query(
                "vesselShipments.getVesselShipments",
                input: ListInput(limit: 8, offset: 0))
            guard let rows = list.shipments, !rows.isEmpty else {
                fleet = nil
                voyages = []
                return
            }

            var built: [VoyageCarbon681] = []
            for row in rows {
                guard let id = row.id else { continue }
                let detail: VesselShipmentDetail681? = try? await EusoTripAPI.shared.query(
                    "vesselShipments.getVesselShipmentDetail",
                    input: DetailInput(id: id))
                let calc: VesselCIICalc681 = try await EusoTripAPI.shared.query(
                    "co2Calculator.calculateVesselShipment",
                    input: CalcInput(shipmentId: id))
                built.append(voyageCarbonRow(from: row, detail: detail, calc: calc))
            }

            voyages = built
            fleet = buildFleet(from: built)
        } catch {
            loadError = error.eusoUserCopy
            fleet = nil
            voyages = []
        }
    }

    private func exportReport() async {
        exporting = true
        actionMessage = nil
        actionError = nil
        exportURL = nil
        defer { exporting = false }

        guard !voyages.isEmpty else {
            actionError = "No vessel CII rows are loaded yet."
            return
        }

        do {
            let filename = "vessel-cii-report-\(Int(Date().timeIntervalSince1970)).csv"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try ciiCSV().data(using: .utf8)?.write(to: url, options: .atomic)
            exportURL = url
            actionMessage = "Carbon CII report ready: \(filename)."
        } catch {
            actionError = error.eusoUserCopy
        }
    }

    private func voyageCarbonRow(
        from row: VesselShipmentRow681,
        detail: VesselShipmentDetail681?,
        calc: VesselCIICalc681
    ) -> VoyageCarbon681 {
        let booking = firstNonEmpty(detail?.bookingNumber, row.bookingNumber)
        let voyage = firstNonEmpty(detail?.voyageNumber, row.voyageNumber, booking)
        let route = firstNonEmpty(detail?.serviceRoute, row.serviceRoute)
        let origin = portLabel(detail?.originPort)
            ?? routeEndpoint(route, index: 0)
            ?? row.originPortId.map { "Port \($0)" }
        let destination = portLabel(detail?.destinationPort)
            ?? routeEndpoint(route, index: 1)
            ?? row.destinationPortId.map { "Port \($0)" }
        let status = firstNonEmpty(detail?.status, row.status).map(statusLabel)
        let pendingReason = calc.dataAvailable == false ? calc.reason : nil
        let fuelNote: String? = {
            guard let fuel = positive(calc.fuelConsumedTonnes) else { return nil }
            let fuelType = calc.fuelType?.uppercased() ?? "FUEL"
            return String(format: "%.1f t %@", fuel, fuelType)
        }()
        let note = firstNonEmpty(pendingReason, fuelNote, status)

        return VoyageCarbon681(
            id: row.id.map(String.init) ?? detail?.id.map(String.init) ?? booking ?? UUID().uuidString,
            voyageId: voyage,
            origin: origin,
            destination: destination,
            createdAt: firstNonEmpty(detail?.createdAt, row.createdAt),
            distanceNm: positive(calc.distanceNm),
            teu: positive(calc.teuCount),
            note: note,
            attainedAER: positive(calc.ciiAttained),
            grade: firstNonEmpty(calc.ciiRating)
        )
    }

    private func buildFleet(from rows: [VoyageCarbon681]) -> FleetCarbon681? {
        let valid = rows.filter { $0.attainedAER != nil || CIIGrade.from($0.grade) != nil }
        guard let latest = valid.first else { return nil }
        return FleetCarbon681(
            vesselId: latest.voyageId,
            attainedAER: latest.attainedAER,
            requiredAER: nil,
            grade: latest.grade,
            year: year(from: latest.createdAt) ?? Calendar.current.component(.year, from: Date()),
            sourceCount: valid.count,
            quarters: quarterRows(from: valid)
        )
    }

    private func quarterRows(from rows: [VoyageCarbon681]) -> [FleetCarbon681.QuarterAER]? {
        var buckets: [String: [VoyageCarbon681]] = [:]
        for row in rows where row.attainedAER != nil {
            buckets[quarterKey(from: row.createdAt) ?? "Current", default: []].append(row)
        }
        guard !buckets.isEmpty else { return nil }
        return buckets.keys.sorted().map { key in
            let members = buckets[key] ?? []
            let values = members.compactMap(\.attainedAER)
            let avg = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
            return FleetCarbon681.QuarterAER(
                quarter: key,
                attainedAER: avg,
                grade: worstGrade(in: members)
            )
        }
    }

    private func quarterSummary(_ quarters: [FleetCarbon681.QuarterAER]) -> (primary: String, secondary: String) {
        let values = quarters.compactMap(\.attainedAER)
        guard let latest = values.last else {
            return ("No attained AER values in DCS bucket", "\(quarters.count) live bucket\(quarters.count == 1 ? "" : "s")")
        }
        if values.count >= 2, let first = values.first {
            let delta = latest - first
            let direction = delta > 0 ? "up" : (delta < 0 ? "down" : "flat")
            return (
                String(format: "attained AER %@ %.1f", direction, abs(delta)),
                "\(quarters.count) live bucket\(quarters.count == 1 ? "" : "s") · based on vessel calculator rows"
            )
        }
        return (
            String(format: "latest attained AER %.1f", latest),
            "additional DCS periods will build the trend"
        )
    }

    private var seempEvidenceLine: String {
        guard let fleet else {
            return "No attained AER is available yet. Close the missing fuel, TEU, and port-coordinate fields before locking a SEEMP corrective-action packet."
        }
        let grade = CIIGrade.from(fleet.grade)?.rawValue ?? "pending"
        let attained = fleet.attainedAER.map { String(format: "%.1f gCO₂/t·nm", $0) } ?? "attained AER pending"
        return "\(grade) · \(attained) · \(fleet.sourceCount) calculator row\(fleet.sourceCount == 1 ? "" : "s")"
    }

    private var seempActions: [String] {
        let grade = CIIGrade.from(fleet?.grade)
        switch grade {
        case .a?, .b?:
            return [
                "Keep fuel, distance, TEU, and port-coordinate telemetry complete for every voyage so the current CII rating remains auditable.",
                "Maintain hull, propeller, and engine-efficiency evidence in the vessel compliance vault before annual IMO DCS submission.",
                "Review lower-carbon bunker options only where procurement and voyage constraints support the switch."
            ]
        case .c?:
            return [
                "Place C-band voyages on watch and review slow-steaming windows, weather routing, and berth-window buffers before departure.",
                "Close missing fuel and TEU records within the booking record so future attained-AER drift is not hidden by data gaps.",
                "Prepare corrective-action evidence now so the plan can be escalated quickly if the vessel slips into D or E."
            ]
        case .d?, .e?:
            return [
                "Open the corrective-action register for every D/E voyage and attach voyage, fuel, weather-routing, and port-delay evidence.",
                "Evaluate speed-power optimization, hull cleaning, propeller inspection, and fuel-switch candidates against the affected routes.",
                "Route the plan for compliance review before annual IMO DCS submission; do not mark the vessel as recovered until fresh CII calculations confirm it."
            ]
        case nil:
            return [
                "Complete missing fuel, port-coordinate, and TEU fields so CII can be calculated from real booking data.",
                "Verify the vessel DCS or CII provider integration before presenting a grade to operations.",
                "Keep SEEMP corrective actions in draft until attained AER is available."
            ]
        }
    }

    private var seempPacketText: String {
        var lines: [String] = [
            "EusoTrip SEEMP Plan",
            seempEvidenceLine,
            "",
            "Action plan:"
        ]
        lines.append(contentsOf: seempActions.map { "- \($0)" })
        if !voyages.isEmpty {
            lines.append("")
            lines.append("Source voyages:")
            lines.append(contentsOf: voyages.map { row in
                let lane = "\(row.origin ?? "—") to \(row.destination ?? "—")"
                let aer = row.attainedAER.map { String(format: "%.1f gCO₂/t·nm", $0) } ?? "AER pending"
                let grade = CIIGrade.from(row.grade)?.rawValue ?? "grade pending"
                return "- \(row.voyageId ?? row.id): \(lane), \(aer), \(grade)"
            })
        }
        return lines.joined(separator: "\n")
    }

    private func ciiCSV() -> String {
        var lines = ["Voyage,Origin,Destination,Created,Distance NM,TEU,Attained AER,Grade,Note"]
        for row in voyages {
            lines.append([
                csv(row.voyageId),
                csv(row.origin),
                csv(row.destination),
                csv(row.createdAt),
                row.distanceNm.map { String(format: "%.1f", $0) } ?? "",
                row.teu.map { String(format: "%.1f", $0) } ?? "",
                row.attainedAER.map { String(format: "%.3f", $0) } ?? "",
                csv(row.grade),
                csv(row.note)
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func csv(_ value: String?) -> String {
        let raw = value ?? ""
        if raw.contains(",") || raw.contains("\"") || raw.contains("\n") {
            return "\"\(raw.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return raw
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        values.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }.first
    }

    private func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func portLabel(_ port: Port681?) -> String? {
        guard let port else { return nil }
        if let code = firstNonEmpty(port.unlocode) { return code }
        if let city = firstNonEmpty(port.city) {
            let suffix = [port.state, port.country].compactMap { firstNonEmpty($0) }.joined(separator: ", ")
            return suffix.isEmpty ? city : "\(city), \(suffix)"
        }
        return firstNonEmpty(port.name)
    }

    private func routeEndpoint(_ route: String?, index: Int) -> String? {
        guard let route = firstNonEmpty(route) else { return nil }
        let separators = ["→", "->", " to ", "-"]
        for separator in separators where route.contains(separator) {
            let parts = route.components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard parts.indices.contains(index) else { return nil }
            return parts[index]
        }
        return nil
    }

    private func statusLabel(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func quarterKey(from iso: String?) -> String? {
        guard let iso, iso.count >= 7 else { return nil }
        let year = String(iso.prefix(4))
        let monthText = String(iso.dropFirst(5).prefix(2))
        guard let month = Int(monthText), (1...12).contains(month) else { return nil }
        return "\(year) Q\((month - 1) / 3 + 1)"
    }

    private func year(from iso: String?) -> Int? {
        guard let iso, iso.count >= 4 else { return nil }
        return Int(String(iso.prefix(4)))
    }

    private func worstGrade(in rows: [VoyageCarbon681]) -> String? {
        rows.compactMap { row -> (String, Int)? in
            guard let grade = CIIGrade.from(row.grade) else { return nil }
            return (grade.rawValue, gradeIndex(grade))
        }
        .max { $0.1 < $1.1 }?
        .0
    }

    private func gradeIndex(_ grade: CIIGrade) -> Int {
        switch grade {
        case .a: return 0
        case .b: return 1
        case .c: return 2
        case .d: return 3
        case .e: return 4
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

    // MARK: - CII dial (Wave A2 — RadialFillGauge de-orphaned)

    /// The attained-AER dial. Domain spans 0.6×…1.4× the required AER so
    /// the five IMO bands (d1–d4 multipliers, the SAME thresholds
    /// `computedGrade` applies) all render; the required AER is the tick.
    /// Mounts only when BOTH live AER values exist — no fabricated dial.
    @ViewBuilder
    private func ciiGaugeSection(_ f: FleetCarbon681) -> some View {
        if let attained = f.attainedAER, let required = f.requiredAER, required > 0 {
            RadialFillGauge(
                title: "ATTAINED vs REQUIRED · CII DIAL",
                model: RadialGaugeModel(
                    value: attained,
                    min: required * 0.6,
                    max: required * 1.4,
                    lowerIsBetter: true,
                    bands: [
                        RadialGaugeBand(id: "a", grade: "A", label: "Superior",
                                        color: Color(hex: 0x00C48C), lowerBound: required * 0.6),
                        RadialGaugeBand(id: "b", grade: "B", label: "Minor",
                                        color: Color(hex: 0x66BB6A), lowerBound: required * 0.86),
                        RadialGaugeBand(id: "c", grade: "C", label: "Moderate",
                                        color: Color(hex: 0xFFB100), lowerBound: required * 0.94),
                        RadialGaugeBand(id: "d", grade: "D", label: "Inferior",
                                        color: Color(hex: 0xFF7043), lowerBound: required * 1.06),
                        RadialGaugeBand(id: "e", grade: "E", label: "Critical",
                                        color: Color(hex: 0xF44336), lowerBound: required * 1.18),
                    ],
                    targets: [
                        RadialGaugeTarget(value: required,
                                          label: "REQ \(String(format: "%.1f", required))")
                    ],
                    unit: "gCO₂/t·nm",
                    caption: "ATTAINED AER · \(f.year.map(String.init) ?? "—")",
                    decimals: 1
                )
            )
        }
    }
}

#Preview("681 · Vessel Emissions CII · Night") { VesselEmissionsCIIScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("681 · Vessel Emissions CII · Light") { VesselEmissionsCIIScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
