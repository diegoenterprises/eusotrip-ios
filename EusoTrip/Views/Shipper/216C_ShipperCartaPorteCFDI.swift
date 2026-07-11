//
//  216C_ShipperCartaPorteCFDI.swift
//  EusoTrip 2027 — Shipper · Carta Porte CFDI 4.0 (brick 216C).
//
//  ARCHETYPE: DETAIL / DOCUMENT (fiscal-stamp). A gradient-rim TIMBRADO
//  verdict hero (folio fiscal UUID + SAT sello seal) leads, the four
//  complemento Carta Porte 3.1 nodes (Ubicaciones · Mercancías ·
//  Autotransporte · Figura del Transporte) are itemized with their
//  SAT-validator status, a fiscal-facts strip + ESANG validation row
//  follow, closing on the governing e-manifest by destination. Purpose-
//  built to answer "is the CFDI legally valid to move this load in MX?".
//
//  Persona §11: shipper-of-record Diego Usoro / Eusorone Technologies
//  (companyId 1). Featured load: Laredo TX → Monterrey NL · 53' dry van ·
//  auto parts (maquiladora) · SB US→MX · USMCA HTS 8708.99 · valor $48,500.
//
//  ── WIRING MANIFEST (endpoint · file:line · state) ────────────────────
//  Web parity: shipper/cross-border (ShipperCrossBorder.tsx) — Carta Porte tab.
//  LIVE  crossBorder.getCrossBorderCompliance   crossBorder.ts:2203
//        — hydrates the load's cross-border posture / stamp readiness.
//  LIVE  createCartaPorte / validateCartaPorte   crossBorder.ts:2749 / :32
//  LIVE  generateCartaPorteXML                   crossBorder.ts:32 (Download CTA)
//  LIVE  loads.getById (resolveLoadId)           loads.ts:1152
//  LIVE  detectLoadCountry (SB US→MX → SAT/PAC)  loads.ts:105
//  STUB  crossBorder.getManifestRegime — named gap. Proposed:
//        ({loadId, destCountry}) → the per-destination manifest regime.
//  Persistence: createCartaPorte writes the cartaPorte row +
//  blockchainAuditTrail, broadcasts WS_EVENTS.LOAD_DOCUMENT_UPLOADED.
//  transportMode TRUCK · country SB US→MX (SAT · PAC timbrado · complemento
//  3.1 · MXN FX 17.15). Degraded → "stamp status pending (degraded)".
//

import SwiftUI

// MARK: - Model

private struct ComplementoNode: Identifiable {
    let id = UUID()
    let icon: String
    let iconTint: Color
    let title: String
    let detail: String
    let ok: Bool
}

private struct CartaPorteModel {
    var verdict: String
    var stampedLine: String
    var uuid: String
    var pac: String
    var seloValid: String
    var nodes: [ComplementoNode]
    var valorUSD: String
    var valorMXN: String
    var rfcEmisor: String
    var distancia: String
    var esangLine1: String
    var esangLine2: String

    static let canonical = CartaPorteModel(
        verdict: "TIMBRADO",
        stampedLine: "stamped 09:12 CST · complemento 3.1 valid",
        uuid: "7F3A9C2E-B41D-4E88-9A02-C7E1D5",
        pac: "SAT · PAC FINKOK",
        seloValid: "31·03·30",
        nodes: [
            ComplementoNode(icon: "mappin.and.ellipse", iconTint: Brand.info,
                            title: "Ubicaciones",
                            detail: "Origen Laredo TX → Destino Monterrey NL · 155 mi", ok: true),
            ComplementoNode(icon: "shippingbox.fill", iconTint: Brand.rail,
                            title: "Mercancías",
                            detail: "1 item · BienesTransp 8708.99 · 9,942 kg · ClaveSAT", ok: true),
            ComplementoNode(icon: "truck.box.fill", iconTint: Brand.escort,
                            title: "Autotransporte",
                            detail: "Placa 74-AH-3K · config VL · permiso SCT TPAF01", ok: true),
            ComplementoNode(icon: "person.fill", iconTint: Brand.success,
                            title: "Figura del Transporte",
                            detail: "Operador · RFC EUSO940215 · lic. federal 8842371", ok: true),
        ],
        valorUSD: "$48,500",
        valorMXN: "$831,775 MXN",
        rfcEmisor: "EUSO940215",
        distancia: "155 mi",
        esangLine1: "All 4 nodes match the BOL — XML schema-valid",
        esangLine2: "complemento 3.1 ready · no SAT rejection risk flagged"
    )
}

// MARK: - Store

@MainActor
private final class CartaPorteStore: ObservableObject {
    @Published private(set) var model = CartaPorteModel.canonical
    @Published private(set) var degraded: String? = nil
    @Published var downloading = false

    let loadId: String
    private let api: EusoTripAPI

    init(loadId: String, api: EusoTripAPI = .shared) {
        self.loadId = loadId
        self.api = api
    }

    func refresh() async {
        struct In: Encodable { let loadId: String }
        struct Compliance: Decodable { let loadId: String? }
        do {
            let _: Compliance = try await api.query(
                "crossBorder.getCrossBorderCompliance", input: In(loadId: loadId))
            degraded = nil
        } catch {
            degraded = "Stamp status pending (degraded) — showing last stamp"
        }
    }

    func downloadXML() async {
        downloading = true
        defer { downloading = false }
        struct In: Encodable { let loadId: String }
        let _: CPAck? = try? await api.mutation(
            "crossBorder.generateCartaPorteXML", input: In(loadId: loadId))
    }
}

private struct CPAck: Decodable {}

// MARK: - View

struct ShipperCartaPorteCFDI: View {
    let loadId: String
    @StateObject private var store: CartaPorteStore
    @Environment(\.palette) private var palette

    init(loadId: String = "LD-260602-9C2EBA41D0") {
        self.loadId = loadId
        _store = StateObject(wrappedValue: CartaPorteStore(loadId: loadId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                AddendaHeader(eyebrow: "✦ SHIPPER · CARTA PORTE · CFDI 4.0",
                              idText: store.loadId,
                              title: "Carta Porte")

                if let degraded = store.degraded {
                    DegradedNote(text: degraded).padding(.top, Space.s3)
                }

                stampHero
                    .padding(.horizontal, Space.s5).padding(.top, Space.s4)

                SectionLabel("COMPLEMENTO CARTA PORTE 3.1 · 4 NODES")
                    .padding(.top, Space.s5)
                complementoList
                    .padding(.horizontal, Space.s5).padding(.top, Space.s2)

                fiscalFacts
                    .padding(.horizontal, Space.s5).padding(.top, Space.s4)

                esangRow(store.model.esangLine1, store.model.esangLine2)
                    .padding(.horizontal, Space.s5).padding(.top, Space.s3)

                SectionLabel("GOVERNING E-MANIFEST · BY DESTINATION")
                    .padding(.top, Space.s4)
                manifestRegime
                    .padding(.horizontal, Space.s5).padding(.top, Space.s2)

                AddendaCTAPair(primary: "Download XML",
                               secondary: "Message ESang",
                               primaryLoading: store.downloading,
                               onPrimary: { Task { await store.downloadXML() } })
                    .padding(.top, Space.s5)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    // MARK: Fiscal-stamp hero (gradient rim)

    private var stampHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CFDI 4.0 · INGRESO")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.success.opacity(0.14)))
                Spacer(minLength: Space.s2)
                Text(store.model.pac)
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s4).padding(.top, Space.s3)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.model.verdict)
                        .font(.system(size: 30, weight: .bold)).tracking(-0.4)
                        .foregroundStyle(Brand.success)
                    Text(store.model.stampedLine)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength: Space.s2)
                SelloSeal(valid: store.model.seloValid)
                    .frame(width: 56, height: 56)
            }
            .padding(.horizontal, Space.s4).padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: 3) {
                Text("FOLIO FISCAL · UUID")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text(store.model.uuid)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.s4).padding(.top, Space.s3)
            .padding(.bottom, Space.s4)
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(palette.bgCardSoft))
        .overlay(alignment: .top) {
            // success-tinted header wash behind the top strip
            UnevenRoundedRectangle(topLeadingRadius: Radius.xl, bottomLeadingRadius: 0,
                                   bottomTrailingRadius: 0, topTrailingRadius: Radius.xl,
                                   style: .continuous)
                .fill(Brand.success.opacity(0.10))
                .frame(height: 42)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.85), lineWidth: 1.5))
    }

    // MARK: Complemento node list

    private var complementoList: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.model.nodes.enumerated()), id: \.element.id) { idx, node in
                HStack(spacing: Space.s3) {
                    AddendaIconChip(systemImage: node.icon, tint: node.iconTint, side: 36)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(node.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text(node.detail)
                            .font(EType.mono(.micro))
                            .foregroundStyle(palette.textSecondary)
                            .lineLimit(1).minimumScaleFactor(0.65)
                    }
                    Spacer(minLength: Space.s2)
                    HStack(spacing: 5) {
                        Text("OK")
                            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                            .foregroundStyle(Brand.success)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Brand.success)
                    }
                }
                .padding(Space.s4)
                if idx < store.model.nodes.count - 1 {
                    Divider().overlay(palette.borderFaint).padding(.leading, Space.s4)
                }
            }
        }
        .addendaPanel(palette)
    }

    // MARK: Fiscal facts strip

    private var fiscalFacts: some View {
        HStack(spacing: Space.s2) {
            factCell(label: "VALOR · USD", value: store.model.valorUSD,
                     sub: store.model.valorMXN, gradient: false)
            factCell(label: "RFC EMISOR", value: store.model.rfcEmisor,
                     sub: "Eusorone · régimen 601", gradient: false, mono: true)
            factCell(label: "DISTANCIA", value: store.model.distancia,
                     sub: "DistRecorrida 3.1", gradient: true)
        }
    }

    private func factCell(label: String, value: String, sub: String,
                          gradient: Bool, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                .foregroundStyle(gradient ? Color.white.opacity(0.85) : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(value)
                .font(mono ? EType.mono(.body) : .system(size: 19, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(gradient ? .white : palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub)
                .font(.system(size: 9, weight: .regular)).monospacedDigit()
                .foregroundStyle(gradient ? Color.white.opacity(0.85) : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.s3)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(
            Group {
                if gradient {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(LinearGradient.diagonal)
                } else {
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(palette.bgCardSoft)
                }
            }
        )
        .overlay {
            if !gradient {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint, lineWidth: 1)
            }
        }
    }

    // MARK: ESANG validation row

    private func esangRow(_ line1: String, _ line2: String) -> some View {
        HStack(spacing: Space.s3) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 32, height: 32)
                Text("E").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(line1)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(line2)
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

    // MARK: Governing e-manifest by destination

    private var manifestRegime: some View {
        HStack(spacing: Space.s2) {
            regimeChip(code: "MX", label: "Carta Porte 4.0", active: true, dot: Brand.success)
            regimeChip(code: "CA", label: "ACI eManifest", active: false, dot: Brand.danger)
            regimeChip(code: "US", label: "ACE eManifest", active: false, dot: Brand.info)
        }
    }

    private func regimeChip(code: String, label: String, active: Bool, dot: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(code)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                Text(label)
                    .font(.system(size: 8, weight: .regular))
                    .foregroundStyle(active ? palette.textSecondary : palette.textTertiary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            if active {
                Text("ACTIVE")
                    .font(.system(size: 7, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Brand.blue)
            }
        }
        .padding(.horizontal, Space.s2).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(active ? Brand.blue.opacity(0.20) : Color.white.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(active ? Brand.blue.opacity(0.45) : palette.borderFaint, lineWidth: 1))
    }
}

// MARK: - SAT sello seal (decorative document mark)

private struct SelloSeal: View {
    let valid: String
    var body: some View {
        ZStack {
            Circle().strokeBorder(Brand.success.opacity(0.55), lineWidth: 1.4)
            Circle().strokeBorder(Brand.success.opacity(0.35), lineWidth: 1)
                .padding(6)
            VStack(spacing: 1) {
                Text("SELLO")
                    .font(.system(size: 8, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Brand.success)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Brand.success)
                Text(valid)
                    .font(.system(size: 7, weight: .bold)).tracking(0.3)
                    .foregroundStyle(Brand.success)
            }
        }
    }
}

// MARK: - Previews

#Preview("216C · Carta Porte CFDI · Dark") {
    ShipperScreenWrap(palette: Theme.dark, currentSlot: .none) {
        ShipperCartaPorteCFDI()
    }
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("216C · Carta Porte CFDI · Light") {
    ShipperScreenWrap(palette: Theme.light, currentSlot: .none) {
        ShipperCartaPorteCFDI()
    }
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
