//
//  216E_ShipperVUCEMPedimento.swift
//  EusoTrip 2027 — Shipper · VUCEM Pedimento (brick 216E).
//
//  ARCHETYPE: DETAIL / COMPLIANCE-GATE. A gradient-rim pedimento gate hero
//  (A1 draft + numero + 6-segment gate bar) leads, a six-check Mexican-
//  import compliance grid (RFC · Padrón · Agente · Carta Porte · USMCA ·
//  NOM) follows, then the licensed agente aduanal who transmits it, the
//  aduana/clave/duty facts, closing on the import-filing system by
//  destination. Purpose-built to answer "what's between this load and a
//  stamped VUCEM pedimento, and who files it?".
//
//  Persona §11: shipper-of-record Diego Usoro / Eusorone Technologies
//  (companyId 1); agente aduanal is a licensed third party. Featured load:
//  Laredo TX → Monterrey NL · auto parts · SB US→MX · HS 8708.99 · $48,500.
//
//  ── WIRING MANIFEST (endpoint · file:line · state) ────────────────────
//  Web parity: shipper/cross-border (ShipperCrossBorder.tsx) — Pedimento tab.
//  LIVE  crossBorder.checkMexicanImportCompliance  crossBorder.ts:3532
//        — {compliant, checks[]={rule,status,detail}} feeds the 6-check gate.
//  LIVE  createPedimento / validatePedimento        crossBorder.ts:33
//  LIVE  calculatePedimentoTaxes                     crossBorder.ts:2910
//  LIVE  getVUCEMProcedures (services mexicanDeepDive)
//  LIVE  loads.getById · detectLoadCountry           loads.ts:1152 / :105
//  STUB  crossBorder.submitPedimento — named gap. Proposed:
//        ({loadId, pedimentoId, vucemAck}) → {numeroPedimento, documentId,
//        status}. Flips pedimentos.status draft→submitted + audit row. CTA.
//  STUB  crossBorder.getImportFilingRegime — per-destination regime select.
//  transportMode TRUCK · country SB US→MX (SAT/VUCEM · aduana 24 Nuevo
//  Laredo · clave A1 · IGI $0 USMCA · MXN FX 17.15). Degraded →
//  "compliance gate pending (degraded)".
//

import SwiftUI

// MARK: - Model

private struct PedimentoCheck: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let warn: Bool
}

private struct PedimentoModel {
    var verdict: String
    var subline: String
    var numero: String
    /// number of the 6 segments that are cleared.
    var clearedSegments: Int
    var checks: [PedimentoCheck]
    var agenteName: String
    var agenteDetail: String
    var aduana: String
    var tipoCambio: String
    var igiDuty: String
    var esangLine1: String
    var esangLine2: String

    static let canonical = PedimentoModel(
        verdict: "READY TO FILE",
        subline: "5 of 6 cleared · 1 NOM advisory · not yet transmitted",
        numero: "No. 26 24 3801 0003421",
        clearedSegments: 5,
        checks: [
            PedimentoCheck(title: "RFC tax ID",      detail: "valid · registered",       warn: false),
            PedimentoCheck(title: "Padrón Import.",  detail: "registered",               warn: false),
            PedimentoCheck(title: "Agente Aduanal",  detail: "patente 3801 · engaged",   warn: false),
            PedimentoCheck(title: "Carta Porte",     detail: "CFDI 4.0 · stamped",       warn: false),
            PedimentoCheck(title: "USMCA origin",    detail: "cert provided",            warn: false),
            PedimentoCheck(title: "NOM cert",        detail: "advisory · confirm exempt", warn: true),
        ],
        agenteName: "Aduanas Reyes S.C. · patente 3801",
        agenteDetail: "Nuevo Laredo · transmits via VUCEM · RFC ARE110304",
        aduana: "24 N. Laredo",
        tipoCambio: "17.15",
        igiDuty: "$0.00",
        esangLine1: "Confirm the auto-parts NOM exemption first",
        esangLine2: "8708.99 is NOM-002 exempt for OEM parts · ask agente to note"
    )
}

// MARK: - Store

@MainActor
private final class PedimentoStore: ObservableObject {
    @Published private(set) var model = PedimentoModel.canonical
    @Published private(set) var degraded: String? = nil
    @Published var submitting = false

    let loadId: String
    private let api: EusoTripAPI

    init(loadId: String, api: EusoTripAPI = .shared) {
        self.loadId = loadId
        self.api = api
    }

    func refresh() async {
        struct In: Encodable { let loadId: String }
        struct Gate: Decodable { let compliant: Bool? }
        do {
            let _: Gate = try await api.query(
                "crossBorder.checkMexicanImportCompliance", input: In(loadId: loadId))
            degraded = nil
        } catch {
            degraded = "Compliance gate pending (degraded) — last check shown"
        }
    }

    func submit() async {
        submitting = true
        defer { submitting = false }
        struct In: Encodable { let loadId: String }
        let _: PedAck? = try? await api.mutation(
            "crossBorder.submitPedimento", input: In(loadId: loadId))
    }
}

private struct PedAck: Decodable {}

// MARK: - View

struct ShipperVUCEMPedimento: View {
    let loadId: String
    @StateObject private var store: PedimentoStore
    @Environment(\.palette) private var palette

    init(loadId: String = "LD-260602-9C2EBA41D0") {
        self.loadId = loadId
        _store = StateObject(wrappedValue: PedimentoStore(loadId: loadId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AddendaHeader(eyebrow: "✦ SHIPPER · VUCEM · PEDIMENTO A1",
                              idText: store.loadId,
                              title: "Pedimento")

                if let degraded = store.degraded {
                    DegradedNote(text: degraded).padding(.top, Space.s3)
                }

                gateHero
                    .padding(.horizontal, Space.s5).padding(.top, Space.s4)

                SectionLabel("VUCEM COMPLIANCE GATE · 6 CHECKS")
                    .padding(.top, Space.s5)
                gateGrid
                    .padding(.horizontal, Space.s5).padding(.top, Space.s2)

                SectionLabel("AGENTE ADUANAL · LICENSED FILER")
                    .padding(.top, Space.s5)
                agenteCard
                    .padding(.horizontal, Space.s5).padding(.top, Space.s2)

                factsStrip
                    .padding(.horizontal, Space.s5).padding(.top, Space.s4)

                esangRow
                    .padding(.horizontal, Space.s5).padding(.top, Space.s3)

                SectionLabel("IMPORT FILING SYSTEM · BY DESTINATION")
                    .padding(.top, Space.s4)
                filingRegime
                    .padding(.horizontal, Space.s5).padding(.top, Space.s2)

                AddendaCTAPair(primary: "Submit to VUCEM",
                               secondary: "Message agente",
                               primaryLoading: store.submitting,
                               onPrimary: { Task { await store.submit() } })
                    .padding(.top, Space.s5)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    // MARK: Pedimento gate hero

    private var gateHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CLAVE A1 · IMPO")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Brand.hazmat)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.warning.opacity(0.16)))
                Spacer(minLength: Space.s2)
                Text("VUCEM · SAT")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s4).padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: 4) {
                Text(store.model.verdict)
                    .font(.system(size: 26, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(Brand.hazmat)
                Text(store.model.subline)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.75)
            }
            .padding(.horizontal, Space.s4).padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: 6) {
                Text(store.model.numero)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textPrimary)
                HStack(spacing: 5) {
                    ForEach(0..<6, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(i < store.model.clearedSegments
                                  ? AnyShapeStyle(LinearGradient.primary)
                                  : AnyShapeStyle(Brand.warning.opacity(0.40)))
                            .frame(height: 8)
                    }
                }
            }
            .padding(.horizontal, Space.s4).padding(.top, Space.s3)
            .padding(.bottom, Space.s4)
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: Radius.xl, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: Radius.xl,
                                   style: .continuous)
                .fill(Brand.warning.opacity(0.10))
                .frame(height: 42)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.85), lineWidth: 1.5))
    }

    // MARK: 6-check gate grid (2×3)

    private var gateGrid: some View {
        let cols = [GridItem(.flexible(), spacing: Space.s2),
                    GridItem(.flexible(), spacing: Space.s2)]
        return LazyVGrid(columns: cols, spacing: Space.s2) {
            ForEach(store.model.checks) { check in
                HStack(spacing: Space.s2) {
                    ZStack {
                        Circle().fill((check.warn ? Brand.warning : Brand.success).opacity(0.16))
                            .frame(width: 20, height: 20)
                        Image(systemName: check.warn ? "exclamationmark.triangle.fill" : "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(check.warn ? Brand.hazmat : Brand.success)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(check.title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.75)
                        Text(check.detail)
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(check.warn ? Brand.hazmat : palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Space.s3)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill((check.warn ? Brand.warning : Brand.success).opacity(check.warn ? 0.10 : 0.07)))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(check.warn ? Brand.warning.opacity(0.30) : Color.clear, lineWidth: 1))
            }
        }
    }

    // MARK: Agente aduanal card

    private var agenteCard: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(Brand.escort.opacity(0.14)).frame(width: 40, height: 40)
                Text("AR").font(.system(size: 13, weight: .heavy)).foregroundStyle(Brand.escort)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(store.model.agenteName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(store.model.agenteDetail)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s4)
        .addendaPanel(palette)
    }

    // MARK: Facts strip

    private var factsStrip: some View {
        HStack(spacing: Space.s2) {
            fact(label: "ADUANA", value: store.model.aduana, gradient: false)
            fact(label: "TIPO CAMBIO", value: store.model.tipoCambio, gradient: false)
            fact(label: "IGI DUTY", value: store.model.igiDuty, gradient: true)
        }
    }

    private func fact(label: String, value: String, gradient: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(gradient ? Color.white.opacity(0.85) : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(value)
                .font(.system(size: 17, weight: .bold)).monospacedDigit()
                .foregroundStyle(gradient ? .white : palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(
            Group {
                if gradient {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(LinearGradient.diagonal)
                } else {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCardSoft)
                }
            })
        .overlay {
            if !gradient {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            }
        }
    }

    // MARK: ESANG advisory row

    private var esangRow: some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Text("E").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(store.model.esangLine1)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(store.model.esangLine2)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: Space.s2)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(palette.textTertiary)
        }
        .padding(Space.s3)
        .addendaPanel(palette)
    }

    // MARK: Import filing by destination (connected segmented bar)

    private var filingRegime: some View {
        HStack(spacing: 0) {
            filingCell(code: "MX · VUCEM", sub: "Pedimento A1 · active", active: true)
            Divider().frame(height: 30).overlay(palette.borderFaint)
            filingCell(code: "CA · CBSA", sub: "B3 + ACI", active: false)
            Divider().frame(height: 30).overlay(palette.borderFaint)
            filingCell(code: "US · CBP", sub: "Entry + ACE", active: false)
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color.white.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint, lineWidth: 1))
    }

    private func filingCell(code: String, sub: String, active: Bool) -> some View {
        VStack(spacing: 2) {
            Text(code)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(sub)
                .font(.system(size: 8, weight: .regular))
                .foregroundStyle(active ? Brand.blue : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.s2)
        .background(active ? Brand.blue.opacity(0.18) : Color.clear)
    }
}

// MARK: - Previews

#Preview("216E · VUCEM Pedimento · Dark") {
    ShipperScreenWrap(palette: Theme.dark, currentSlot: .none) {
        ShipperVUCEMPedimento()
    }
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("216E · VUCEM Pedimento · Light") {
    ShipperScreenWrap(palette: Theme.light, currentSlot: .none) {
        ShipperVUCEMPedimento()
    }
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
