//
//  216G_ShipperMXLandedCost.swift
//  EusoTrip 2027 — Shipper · MX Landed Cost (brick 216G).
//
//  ARCHETYPE: DETAIL / MONEY (mirrors 227 Settlement Detail money grammar).
//  A gradient money H1 ("$8,239 to clear") leads, a pedimento amount hero
//  card follows, then a recoverable-vs-net split bar over an
//  IGI/DTA/PRV/agente/IVA line-item ledger that separates the creditable
//  IVA from the real net cost, closing on the duty/tax basis by
//  destination + a full-width money CTA. Purpose-built to answer "what
//  cash clears the pedimento, and what does this actually cost after
//  recoverable tax?".
//
//  Persona §11: shipper-of-record Diego Usoro / Eusorone Technologies
//  (companyId 1). Featured load: Laredo TX → Monterrey NL · auto parts ·
//  SB US→MX · HS 8708.99 · valor $48,500.
//
//  ── WIRING MANIFEST (endpoint · file:line · state) ────────────────────
//  Web parity: shipper/cross-border (ShipperCrossBorder.tsx) — Landed cost tab.
//  LIVE  crossBorder.calculatePedimentoTaxes     crossBorder.ts:2910
//        — taxes[]={code,name,amount,currency}: IGI 0 (USMCA), DTA, PRV, IVA.
//  LIVE  crossBorder.getCrossBorderCompliance     crossBorder.ts:2203
//  LIVE  crossBorder.convertCurrency (USD→MXN 17.15)  crossBorder.ts:2674
//  LIVE  usmcaCertification.dutySavings = value*0.025  crossBorder.ts:830
//  LIVE  loads.getById · detectLoadCountry         loads.ts:1152 / :105
//  STUB  crossBorder.approveLandedCost — named gap. Proposed:
//        ({loadId, pedimentoId, toClearUSD}) → {ok, ledgerId}. Writes a
//        settlements/ledger row + audit + WS_EVENTS.SETTLEMENT_UPDATED. CTA.
//  STUB  crossBorder.calculateLandedCost — per-country landed-cost select.
//  transportMode TRUCK · country SB US→MX (IGI $0 USMCA · IVA 16%
//  creditable/IMMEX-deferrable · MXN FX 17.15). Degraded →
//  "landed cost pending (degraded)".
//

import SwiftUI

// MARK: - Model

private struct LandedLine: Identifiable {
    let id = UUID()
    let dot: Color
    let title: String
    let amount: String
    /// nil → render in the palette's primary ink; set only for the
    /// duty-saved IGI line (success green).
    let amountColor: Color?
    let sub: String
}

private struct LandedCostModel {
    var toClear: String
    var subtitle: String
    var lane: String
    var cargoLine: String
    var amountMXN: String
    var recoverableLabel: String
    var netLabel: String
    var recoverableFraction: Double
    var lines: [LandedLine]
    var ivaAmount: String
    var ivaSub: String
    var trueCost: String
    var esangLine1: String
    var esangLine2: String

    static let canonical = LandedCostModel(
        toClear: "$8,239 to clear",
        subtitle: "Eusorone Technologies → Monterrey NL · LD-260602-9C2EBA41D0",
        lane: "Laredo TX → Monterrey NL",
        cargoLine: "auto parts · HS 8708.99 · valor $48,500",
        amountMXN: "$141,304 MXN @ 17.15",
        recoverableLabel: "IVA recoverable $7,922",
        netLabel: "net cost $317",
        recoverableFraction: 0.962,
        lines: [
            LandedLine(dot: Brand.success, title: "IGI · import duty",
                       amount: "$0.00", amountColor: Brand.success,
                       sub: "USMCA T-MEC · duty saved $1,212.50"),
            LandedLine(dot: Brand.warning, title: "DTA · customs processing",
                       amount: "$23.32", amountColor: nil,
                       sub: "400 MXN · 0.8% rate"),
            LandedLine(dot: Brand.warning, title: "PRV · prevalidation",
                       amount: "$13.88", amountColor: nil,
                       sub: "238 MXN · per pedimento"),
            LandedLine(dot: Brand.escort, title: "Agente aduanal · honorarios",
                       amount: "$280.00", amountColor: nil,
                       sub: "patente 3801 · Aduanas Reyes"),
        ],
        ivaAmount: "$7,922",
        ivaSub: "135,864 MXN · creditable",
        trueCost: "$317.20",
        esangLine1: "Real cost to move this is $317 — IVA comes back",
        esangLine2: "USMCA already saved $1,212 duty · quote the lane on $317 net"
    )
}

// MARK: - Store

@MainActor
private final class LandedCostStore: ObservableObject {
    @Published private(set) var model = LandedCostModel.canonical
    @Published private(set) var degraded: String? = nil
    @Published var approving = false

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
            degraded = "Landed cost pending (degraded) — last quote shown"
        }
    }

    func approve() async {
        approving = true
        defer { approving = false }
        struct In: Encodable { let loadId: String }
        let _: LandedAck? = try? await api.mutation(
            "crossBorder.approveLandedCost", input: In(loadId: loadId))
    }
}

private struct LandedAck: Decodable {}

// MARK: - View

struct ShipperMXLandedCost: View {
    let loadId: String
    @StateObject private var store: LandedCostStore
    @Environment(\.palette) private var palette

    init(loadId: String = "LD-260602-9C2EBA41D0") {
        self.loadId = loadId
        _store = StateObject(wrappedValue: LandedCostStore(loadId: loadId))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                moneyHeader

                if let degraded = store.degraded {
                    DegradedNote(text: degraded).padding(.top, Space.s3)
                }

                amountHero
                    .padding(.horizontal, Space.s5).padding(.top, Space.s4)

                SectionLabel("CLEARANCE COST · IGI / DTA / IVA / AGENTE")
                    .padding(.top, Space.s5)
                costLedger
                    .padding(.horizontal, Space.s5).padding(.top, Space.s2)

                ivaCallout
                    .padding(.horizontal, Space.s5).padding(.top, Space.s3)

                esangRow
                    .padding(.horizontal, Space.s5).padding(.top, Space.s3)

                SectionLabel("DUTY / TAX BASIS · BY DESTINATION")
                    .padding(.top, Space.s4)
                dutyBasis
                    .padding(.horizontal, Space.s5).padding(.top, Space.s2)

                // Money grammar: single full-width CTA carrying the amount.
                CTAButton(title: "Approve landed cost · $8,239",
                          action: { Task { await store.approve() } },
                          leadingIcon: "checkmark",
                          isLoading: store.approving)
                    .padding(.horizontal, Space.s5).padding(.top, Space.s5)

                Color.clear.frame(height: 96)
            }
        }
        .task { await store.refresh() }
        .refreshable { await store.refresh() }
    }

    // MARK: Money header (bespoke — 227 money grammar)

    private var moneyHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("✦ SHIPPER · LANDED COST · MX IMPORT")
                    .font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: Space.s3)
                Text("A1 · PEDIMENTO")
                    .font(EType.mono(.micro)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s5)

            HStack(alignment: .center, spacing: Space.s2) {
                Button(action: {
                    NotificationCenter.default.post(name: .eusoShipperNavBack, object: nil)
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.textPrimary)
                        .frame(width: 24, height: 30, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Text("Cross-border")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s2)

            Text(store.model.toClear)
                .font(.system(size: 34, weight: .bold)).tracking(-0.6)
                .monospacedDigit()
                .foregroundStyle(LinearGradient.primary)
                .padding(.horizontal, Space.s5).padding(.top, Space.s3)
            Text(store.model.subtitle)
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, Space.s5).padding(.top, 2)

            IridescentHairline().padding(.top, Space.s3)
        }
    }

    // MARK: Amount hero card (gradient rim)

    private var amountHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(store.loadId)
                    .font(EType.mono(.micro))
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: Space.s2)
                Text("USMCA · IGI $0")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Brand.success.opacity(0.14)))
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.model.lane)
                        .font(.system(size: 18, weight: .bold)).tracking(-0.2)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(store.model.cargoLine)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("$8,239")
                        .font(.system(size: 22, weight: .bold)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                    Text(store.model.amountMXN)
                        .font(EType.mono(.micro))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(.top, Space.s4)
        }
        .padding(Space.s4)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCardSoft))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(LinearGradient.diagonal.opacity(0.85), lineWidth: 1.5))
    }

    // MARK: Cost ledger (recoverable/net bar + line items)

    private var costLedger: some View {
        VStack(alignment: .leading, spacing: 0) {
            // recoverable vs net split bar
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    let w = geo.size.width
                    HStack(spacing: 3) {
                        Capsule().fill(Brand.info.opacity(0.30))
                            .frame(width: max(10, w * store.model.recoverableFraction))
                        Capsule().fill(LinearGradient.primary)
                    }
                    .frame(height: 14)
                }
                .frame(height: 14)
                HStack {
                    Text(store.model.recoverableLabel)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Brand.info)
                    Spacer()
                    Text(store.model.netLabel)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                }
            }
            .padding(Space.s4)
            Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)

            ForEach(store.model.lines) { line in
                HStack(alignment: .top, spacing: Space.s3) {
                    Circle().fill(line.dot).frame(width: 10, height: 10).padding(.top, 3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(line.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(palette.textPrimary)
                        Text(line.sub)
                            .font(.system(size: 10, weight: .regular)).monospacedDigit()
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: Space.s2)
                    Text(line.amount)
                        .font(.system(size: 14, weight: .bold)).monospacedDigit()
                        .foregroundStyle(line.amountColor ?? palette.textPrimary)
                }
                .padding(.horizontal, Space.s4).padding(.vertical, Space.s3)
            }
        }
        .addendaPanel(palette)
    }

    // MARK: IVA callout + TRUE COST

    private var ivaCallout: some View {
        HStack(spacing: Space.s2) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Circle().fill(Brand.info).frame(width: 10, height: 10)
                    Text("IVA · 16% VAT")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: Space.s2)
                    Text(store.model.ivaAmount)
                        .font(.system(size: 14, weight: .bold)).monospacedDigit()
                        .foregroundStyle(Brand.info)
                }
                Text(store.model.ivaSub)
                    .font(.system(size: 10, weight: .regular)).monospacedDigit()
                    .foregroundStyle(Brand.info)
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(Brand.info.opacity(0.06)))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(Brand.info.opacity(0.18), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text("TRUE COST")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(Color.white.opacity(0.85))
                Text(store.model.trueCost)
                    .font(.system(size: 20, weight: .bold)).monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .padding(Space.s3)
            .frame(width: 120, height: 56, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(LinearGradient.diagonal))
        }
    }

    // MARK: ESANG row

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

    // MARK: Duty/tax basis by destination

    private var dutyBasis: some View {
        HStack(spacing: Space.s2) {
            basisCell(code: "MX · MXN", sub: "IGI 0% · IVA 16%", active: true)
            basisCell(code: "CA · CAD", sub: "duty · GST 5%", active: false)
            basisCell(code: "US · USD", sub: "duty · no VAT", active: false)
        }
    }

    private func basisCell(code: String, sub: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(code)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(sub)
                .font(.system(size: 8, weight: .regular)).monospacedDigit()
                .foregroundStyle(active ? palette.textSecondary : palette.textTertiary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, Space.s2).padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(active ? Brand.blue.opacity(0.20) : Color.white.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(active ? Brand.blue.opacity(0.45) : palette.borderFaint, lineWidth: 1))
    }
}

// MARK: - Previews

#Preview("216G · MX Landed Cost · Dark") {
    ShipperScreenWrap(palette: Theme.dark, currentSlot: .none) {
        ShipperMXLandedCost()
    }
    .environment(\.palette, Theme.dark)
    .preferredColorScheme(.dark)
}

#Preview("216G · MX Landed Cost · Light") {
    ShipperScreenWrap(palette: Theme.light, currentSlot: .none) {
        ShipperMXLandedCost()
    }
    .environment(\.palette, Theme.light)
    .preferredColorScheme(.light)
}
