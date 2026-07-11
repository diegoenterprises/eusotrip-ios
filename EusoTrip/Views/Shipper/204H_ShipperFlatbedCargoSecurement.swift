//
//  204H_ShipperFlatbedCargoSecurement.swift
//  EusoTrip 2027 — Shipper · Flatbed Cargo Securement (brick 204H).
//
//  ARCHETYPE: WLL-GAUGE + TIE-DOWN ROSTER + SECUREMENT GATE. A semicircular
//  working-load-limit coverage gauge leads (aggregate provided WLL vs the
//  49 CFR 393.106 ≥50%-of-cargo-weight requirement), a TIE-DOWN ROSTER
//  ledger totals each device's WLL, closing on a SECUREMENT GATE checklist
//  that blocks departure until passed. Purpose-built for the WLL math —
//  not the oversize dimension bars (204D), not a stat grid.
//
//  Persona §11: Diego Usoro / Eusorone Technologies (shipper-of-record).
//  Featured load: LD-260615-FB7K9 · steel coils eye-to-sky · 4 coils ·
//  44,000 lb · flatbed (48ft) · Houston TX → Kansas City KS.
//
//  ── WIRING MANIFEST (endpoint · file:line · state) ────────────────────
//  Web parity: shipper/loads/[id]/securement-gate.tsx
//  LIVE  trailerRegulatory.getFlatbedRegulations   trailerRegulatory.ts:169
//        (49 CFR 393 · WLL ≥ 50% each direction · commodity rules)
//  LIVE  trailerRegulatory.getStepDeckRegulations  trailerRegulatory.ts:453
//  LIVE  visualIntelligence.assessCargo            visualIntelligence.ts:119
//        (per-side securement + condition photo evidence)
//  LIVE  bol.generateCompletionTicket              bol.ts:821 (securement write)
//  GATE  flatbed_securement_verified — loadLifecycle stateMachine.ts:718
//        blocks the en_route transition until chains/straps/binders inspect.
//  STUB  securement.validateWLL — named gap. Proposed:
//        ({loadId, tiedowns:[{type,wll,count}], cargoWeight})
//          → {aggregateWLL, requiredWLL, passes}. The WLL aggregation is
//        rule text in getFlatbedRegulations, not a callable validator. CTA.
//  transportMode TRUCK · country US (49 CFR 393 Subpart I · 393.106 WLL ·
//  393.120 coils · 393.110 min tie-downs · 393.104 edge protection).
//  Degraded → "securement check pending (degraded)".
//

import SwiftUI

// MARK: - Model

private struct TieDown: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
    let rightTop: String
    let rightSub: String
    let rightColor: Color
    let isAggregate: Bool
}

private struct GateRow: Identifiable {
    enum Result { case pass, warn, na }
    let id = UUID()
    let title: String
    let detail: String
    let result: Result
    let rightText: String
}

private struct SecurementModel {
    var coverage: String
    var coverageFill: Double
    var coverageTick: Double
    var reqProv: String
    var commodity: String
    var cargoLine: String
    var laneLine: String
    var tiedowns: [TieDown]
    var gate: [GateRow]

    static let canonical = SecurementModel(
        coverage: "120%",
        coverageFill: 0.80,
        coverageTick: 0.667,
        reqProv: "req 22,000 · prov 26,400 lb",
        commodity: "Steel coils",
        cargoLine: "eye-to-sky · 4 coils · 44,000 lb",
        laneLine: "HOU TX → KCK KS · flatbed 48ft",
        tiedowns: [
            TieDown(icon: "link", title: "Grade-70 chain · 3/8 in",
                    detail: "×4 · WLL 6,600 lb ea · through-eye",
                    rightTop: "+26,400", rightSub: "lb WLL",
                    rightColor: Brand.success, isAggregate: false),
            TieDown(icon: "rectangle.compress.vertical", title: "Ratchet strap · 4 in",
                    detail: "×4 · WLL 5,400 lb ea · backup",
                    rightTop: "+ margin", rightSub: "redundant",
                    rightColor: Brand.neutral, isAggregate: false),
            TieDown(icon: "checkmark", title: "Aggregate WLL",
                    detail: "required 22,000 lb · §393.106 met",
                    rightTop: "26,400 lb", rightSub: "",
                    rightColor: Brand.success, isAggregate: true),
        ],
        gate: [
            GateRow(title: "Minimum tie-downs",
                    detail: "1 per 10ft + by weight · §393.110",
                    result: .pass, rightText: "PASS"),
            GateRow(title: "Coils eye-to-sky · cradle + chocks",
                    detail: "commodity rule · §393.120",
                    result: .pass, rightText: "PASS"),
            GateRow(title: "Edge protection on all straps",
                    detail: "prevents abrasion cut · §393.104",
                    result: .pass, rightText: "PASS"),
            GateRow(title: "Per-side securement photo",
                    detail: "2 of 4 captured · L · R · fwd · aft",
                    result: .warn, rightText: "2 / 4"),
            GateRow(title: "Tarp / weather protection",
                    detail: "not required for bare steel coils",
                    result: .na, rightText: "N/A"),
        ]
    )
}

// MARK: - Store

@MainActor
private final class SecurementStore: ObservableObject {
    @Published private(set) var model = SecurementModel.canonical
    @Published private(set) var degraded: String? = nil
    @Published var verifying = false

    let loadId: String
    private let api: EusoTripAPI

    init(loadId: String, api: EusoTripAPI = .shared) {
        self.loadId = loadId
        self.api = api
    }

    func refresh() async {
        struct In: Encodable { let trailerType: String }
        struct Reg: Decodable { let trailerType: String? }
        do {
            let _: Reg = try await api.query(
                "trailerRegulatory.getFlatbedRegulations",
                input: In(trailerType: "flatbed"))
            degraded = nil
        } catch {
            degraded = "Securement check pending (degraded) — last WLL shown"
        }
    }

    func verify() async {
        verifying = true
        defer { verifying = false }
        struct In: Encodable { let loadId: String }
        let _: SecAck? = try? await api.mutation(
            "securement.validateWLL", input: In(loadId: loadId))
    }
}

private struct SecAck: Decodable {}

// MARK: - View

struct ShipperFlatbedCargoSecurement: View {
    let loadId: String
    @StateObject private var store: SecurementStore
    @Environment(\.palette) private var palette

    init(loadId: String = "LD-260615-FB7K9") {
        self.loadId = loadId
        _store = StateObject(wrappedValue: SecurementStore(loadId: loadId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AddendaHeader(eyebrow: "✦ SHIPPER · FLATBED · CARGO SECUREMENT",
                              idText: store.loadId,
                              title: "Securement")

                if let degraded = store.degraded {
                    DegradedNote(text: degraded).padding(.top, Space.s3)
                }

                gaugeHero
                    .padding(.horizontal, Space.s5).padding(.top, Space.s4)

                SectionLabel("TIE-DOWN ROSTER · WLL AGGREGATE")
                    .padding(.top, Space.s5)
                roster
                    .padding(.horizontal, Space.s5).padding(.top, Space.s2)

                SectionLabel("SECUREMENT GATE · BLOCKS DEPARTURE · 49 CFR 393")
                    .padding(.top, Space.s5)
                gateChecklist
                    .padding(.horizontal, Space.s5).padding(.top, Space.s2)

                AddendaCTAPair(primary: "Verify securement",
                               secondary: "Message ESang",
                               primaryLoading: store.verifying,
                               onPrimary: { Task { await store.verify() } })
                    .padding(.top, Space.s5)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    // MARK: WLL coverage gauge hero

    private var gaugeHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CARGO SECUREMENT · 49 CFR 393 · WLL BALANCE")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(Brand.success)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s4).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Brand.success.opacity(0.12))

            HStack(alignment: .top, spacing: Space.s4) {
                WLLGauge(coverage: store.model.coverage,
                         fill: store.model.coverageFill,
                         tick: store.model.coverageTick,
                         reqProv: store.model.reqProv)
                    .frame(width: 150, height: 110)

                VStack(alignment: .leading, spacing: 5) {
                    Text(store.model.commodity)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(store.model.cargoLine)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Text(store.model.laneLine)
                        .font(EType.mono(.caption))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("SECURED")
                            .font(.system(size: 11, weight: .heavy)).tracking(0.3)
                    }
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.success.opacity(0.20)))
                    .padding(.top, 2)
                    Divider().overlay(palette.borderFaint).padding(.vertical, 2)
                    Text("WLL ≥ 50% each direction")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                    Text("fwd · aft · lateral · §393.106")
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(Space.s4)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .addendaPanel(palette)
    }

    // MARK: Tie-down roster

    private var roster: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.model.tiedowns.enumerated()), id: \.element.id) { idx, td in
                HStack(spacing: Space.s3) {
                    AddendaIconChip(systemImage: td.icon,
                                    tint: td.isAggregate ? Brand.success : Brand.neutral)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(td.title)
                            .font(.system(size: 14, weight: td.isAggregate ? .heavy : .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text(td.detail)
                            .font(EType.mono(.caption))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: Space.s2)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(td.rightTop)
                            .font(.system(size: td.isAggregate ? 16 : 13, weight: .heavy))
                            .monospacedDigit()
                            .foregroundStyle(td.rightColor)
                        if !td.rightSub.isEmpty {
                            Text(td.rightSub)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }
                .padding(Space.s4)
                if idx < store.model.tiedowns.count - 1 {
                    Divider().overlay(palette.borderFaint).padding(.leading, Space.s4)
                }
            }
        }
        .addendaPanel(palette)
    }

    // MARK: Securement gate

    private var gateChecklist: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.model.gate.enumerated()), id: \.element.id) { idx, row in
                HStack(alignment: .top, spacing: Space.s3) {
                    gateDot(row.result)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text(row.detail)
                            .font(EType.mono(.caption))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.75)
                    }
                    Spacer(minLength: Space.s2)
                    Text(row.rightText)
                        .font(.system(size: 10, weight: .heavy)).tracking(0.3)
                        .foregroundStyle(resultColor(row.result))
                }
                .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
                if idx < store.model.gate.count - 1 {
                    Divider().overlay(palette.borderFaint).padding(.leading, Space.s4)
                }
            }
        }
        .addendaPanel(palette)
    }

    private func resultColor(_ r: GateRow.Result) -> Color {
        switch r {
        case .pass: return Brand.success
        case .warn: return Brand.hazmat
        case .na:   return Brand.neutral
        }
    }

    private func gateDot(_ r: GateRow.Result) -> some View {
        let color = resultColor(r)
        let glyph: String = r == .pass ? "checkmark" : (r == .warn ? "exclamationmark" : "minus")
        return Circle().fill(color.opacity(0.20)).frame(width: 18, height: 18)
            .overlay(Image(systemName: glyph)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(color))
    }
}

// MARK: - Semicircular WLL gauge

private struct WLLGauge: View {
    let coverage: String
    let fill: Double
    let tick: Double
    let reqProv: String
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                // Track (top semicircle)
                Circle().trim(from: 0, to: 0.5)
                    .stroke(Color.white.opacity(0.08),
                            style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    .rotationEffect(.degrees(180))
                // Fill
                Circle().trim(from: 0, to: 0.5 * max(0.02, min(fill, 1)))
                    .stroke(Brand.success,
                            style: StrokeStyle(lineWidth: 11, lineCap: .round))
                    .rotationEffect(.degrees(180))
                // Minimum tick
                Circle().trim(from: 0.5 * tick - 0.004, to: 0.5 * tick + 0.004)
                    .stroke(palette.textPrimary.opacity(0.45),
                            style: StrokeStyle(lineWidth: 15, lineCap: .butt))
                    .rotationEffect(.degrees(180))
                VStack(spacing: 0) {
                    Spacer()
                    Text(coverage)
                        .font(.system(size: 26, weight: .bold)).tracking(-0.5)
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("WLL COVERAGE")
                        .font(.system(size: 8, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                }
                .padding(.bottom, 6)
            }
            .frame(height: 84)
            Text(reqProv)
                .font(EType.mono(.micro))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

// MARK: - Previews

#Preview("204H · Flatbed Cargo Securement · Dark") {
    ShipperScreenWrap(palette: Theme.dark, currentSlot: .none) {
        ShipperFlatbedCargoSecurement()
    }
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("204H · Flatbed Cargo Securement · Light") {
    ShipperScreenWrap(palette: Theme.light, currentSlot: .none) {
        ShipperFlatbedCargoSecurement()
    }
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
