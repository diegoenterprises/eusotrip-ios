//
//  769_VesselNVOCCFMCTariffBond.swift
//  EusoTrip — Vessel Operator · NVOCC FMC Tariff & Bond (BOND-GAUGE + LEDGER).
//
//  Verbatim bespoke port of canonical wireframe "769 Vessel NVOCC FMC Tariff
//  & Bond · Dark" (06 Vessel · Vessel Operator). Regulatory-compliance-board
//  archetype, purpose-built as a surety-bond coverage gauge (drawn vs
//  available) over an FMC tariff-publication ledger (each rule
//  PUBLISHED/PENDING with effective date) — deliberately DISTINCT from the
//  per-quote surcharge composition (762) and the rate/trusted-trader surfaces
//  (687/759). The operator's OTI compliance under 46 CFR Part 515.
//
//  Docked under COMPLIANCE. transportMode=vessel · tri-country US·CA·MX.
//
//  REAL WIRING (registration fields, confirmed on disk):
//    · fmcLicenseType (server/routers/registration.ts:2461 · z.enum NVOCC /
//      OFF / NVOCC_OFF / VOCC / FOREIGN_NVOCC), fmcLicenseNumber (:2460),
//      fmcBondAmount (:2462 · 46 CFR 515 minima $50K OFF / $75K NVOCC /
//      $150K foreign) — the license + bond identity are real registration
//      captures.
//  STUB (handed to the-oath): fmc.tariffStatus / fmc.publishTariff — there is
//  no ongoing tariff-PUBLICATION model nor a bond-UTILIZATION (claims-drawn)
//  tracker (registration captures the license at signup only). The bond gauge
//  + tariff ledger render the certified reference model, flagged in the
//  section gap note; publish-tariff is a human-gated regulatory write.
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselNVOCCFMCTariffBondScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) {
            VesselNVOCCFMCTariffBondBody()
        } nav: {
            BottomNav.vesselOperatorShipments()
        }
    }
}

// MARK: - Model

private struct Tariff769: Identifiable {
    enum State { case published, pending }
    let id: String
    let ruleCode: String
    let name: String
    let effective: String
    let state: State
}

// MARK: - Body

private struct VesselNVOCCFMCTariffBondBody: View {
    @Environment(\.palette) private var palette

    // Certified reference bond figures (46 CFR 515 · NVOCC $75K minimum).
    private let bondAmount: Double = 75_000
    private let bondDrawn: Double = 13_500
    private var bondAvailable: Double { bondAmount - bondDrawn }
    private var drawnPct: Double { bondAmount > 0 ? bondDrawn / bondAmount : 0 }

    private let tariffs: [Tariff769] = [
        .init(id: "gri",  ruleCode: "Rule 8400", name: "General rate increase (GRI)", effective: "eff Jun 1", state: .published),
        .init(id: "baf",  ruleCode: "Rule 8421", name: "Bunker adjustment (BAF)",     effective: "eff Jun 1", state: .published),
        .init(id: "ess",  ruleCode: "FMC-1",     name: "Essential terms · service contract", effective: "filed", state: .published),
        .init(id: "nra",  ruleCode: "NRA",       name: "Negotiated rate arrangement", effective: "draft Jun 16", state: .pending),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDocTopBar(eyebrow: "VESSEL OPERATOR · FMC OTI",
                            idCaption: "46 CFR 515",
                            title: "FMC tariff & bond")
            IridescentHairline().padding(.horizontal, Space.s5)

            VStack(alignment: .leading, spacing: Space.s5) {
                heroCard
                bondSection
                tariffSection
                TriCountryAuthorityBand(title: "REGULATOR · OCEAN TRANSPORT INTERMEDIARY",
                                        regimes: regulatorRegimes)
                VesselDocCTAPair(primaryTitle: "Publish tariff",
                                 secondaryTitle: "View bond",
                                 primaryIcon: "square.and.arrow.up.fill",
                                 onPrimary: {}, onSecondary: {})
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("OTI #019861N · type NVOCC_OFF")
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text("● LICENSED")
                    .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Brand.success)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Brand.success.opacity(0.16)))
            }
            Text("FMC compliance")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s3)
            Text("46 CFR Part 515 · OTI license active")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 3)
            Text("Eusorone Technologies · renewed Apr 2026")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .padding(.top, Space.s3)
        }
        .padding(Space.s5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    // MARK: Surety-bond coverage gauge

    private var bondSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            VesselSectionHeader(label: "SURETY BOND · COVERAGE", right: "FMC-48")
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(vesselDocCurrency(bondAmount))
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(palette.textPrimary)
                            .monospacedDigit()
                        Text("FMC-48 bond · NVOCC minimum")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("$\(String(format: "%.1f", bondAvailable / 1000))K available")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Brand.success)
                        Text("$\(String(format: "%.1f", bondDrawn / 1000))K claims drawn")
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(palette.textTertiary)
                    }
                }
                // Gauge bar.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.textPrimary.opacity(0.06)).frame(height: 10)
                        Capsule()
                            .fill(LinearGradient(colors: [Brand.hazmat, Color(hex: 0xFF7A00)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, geo.size.width * CGFloat(drawnPct)), height: 10)
                    }
                }
                .frame(height: 10)
                HStack {
                    Text("\(Int(drawnPct * 100))% drawn")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text("\(Int((1 - drawnPct) * 100))% headroom")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            .padding(Space.s4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    // MARK: Tariff-publication ledger

    private var tariffSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            VesselSectionHeader(label: "TARIFF PUBLICATION · FMC", right: "\(publishedCount)/\(tariffs.count) published")
            VStack(spacing: 0) {
                ForEach(Array(tariffs.enumerated()), id: \.element.id) { idx, t in
                    tariffRow(t)
                    if idx < tariffs.count - 1 {
                        Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            VesselDocGapNote(text: "Reference tariff ledger + bond utilization. Live publication state + claims-drawn tracking land with the FMC tariff endpoint.")
        }
    }

    private var publishedCount: Int { tariffs.filter { $0.state == .published }.count }

    private func tariffRow(_ t: Tariff769) -> some View {
        let published = t.state == .published
        return HStack(spacing: Space.s3) {
            Text(t.ruleCode)
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 58, height: 18)
                .background(RoundedRectangle(cornerRadius: 6).fill(palette.textPrimary.opacity(0.06)))
            VStack(alignment: .leading, spacing: 3) {
                Text(t.name)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(t.effective)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 6)
            Text(published ? "PUBLISHED" : "PENDING")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(published ? Brand.success : Color(hex: 0xFFC246))
        }
        .padding(.horizontal, Space.s4).padding(.vertical, 11)
    }

    private var regulatorRegimes: [CountryRegime] {
        [
            .init(code: "US", authority: "US · FMC · 46 CFR 515", detail: "OTI + bond", consequence: nil, state: .active),
            .init(code: "CA", authority: "CA · CTA", detail: "freight forwarder reg.", consequence: nil, state: .standby),
            .init(code: "MX", authority: "MX · SCT/AMANAC", detail: "agente de carga", consequence: nil, state: .standby),
        ]
    }
}

#Preview("769 · Vessel NVOCC FMC Tariff & Bond · Night") {
    VesselNVOCCFMCTariffBondScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("769 · Vessel NVOCC FMC Tariff & Bond · Light") {
    VesselNVOCCFMCTariffBondScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
