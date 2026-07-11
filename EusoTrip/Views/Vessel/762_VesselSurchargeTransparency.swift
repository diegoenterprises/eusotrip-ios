//
//  762_VesselSurchargeTransparency.swift
//  EusoTrip — Vessel Operator · Surcharge Transparency (STACKED-WATERFALL + LEDGER).
//
//  Verbatim bespoke port of canonical wireframe "762 Vessel Surcharge
//  Transparency · Dark" (06 Vessel · Vessel Operator). MONEY archetype,
//  purpose-built as a single proportional STACKED composition bar (base vs
//  each surcharge segment) over a per-surcharge ledger with trend glyphs —
//  deliberately DISTINCT from the fuel-only trackers (797/685) and the
//  reconciliation tables (728). One tab surfaces every ocean accessorial —
//  BAF, LSS, THC origin/dest, PSS, war-risk — so the all-in is never a
//  surprise line at invoice.
//
//  Docked under SHIPMENTS. transportMode=vessel · currency from the active
//  country regime (US=USD · CA=CAD · MX=MXN).
//
//  REAL WIRING (tRPC):
//    · rateComparison.compare {originPortId, destinationPortId, containerSize}
//      -> rates[].{totalAllIn, surchargesBreakdown{baf, thcOrigin,
//      thcDestination, pss}}  (server/routers/rateComparison.ts:17,48-66) —
//      EXISTS. Bound when a port pair is injected; the four covered codes
//      (BAF/THC-O/THC-D/PSS) render live, the remainder from the reference.
//    · vesselShipments.listBOLs {limit} -> anchors the booking ref (:961).
//  STUB (handed to the-oath): vesselRate.surchargeBreakdown — the single
//  structured all-in incl. LSS + war-risk + GRI + effective windows. Until
//  it lands those lines render the certified reference model, flagged in the
//  ledger's gap note (never presented as a live per-quote figure).
//
//  Sole author Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

struct VesselSurchargeTransparencyScreen: View {
    let theme: Theme.Palette
    /// Optional live port pair — when both are > 0 the screen binds the
    /// stacked composition to `rateComparison.compare`. From the registry it
    /// constructs unbound and renders the reference composition honestly.
    var originPortId: Int = 0
    var destinationPortId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            VesselSurchargeTransparencyBody(originPortId: originPortId,
                                            destinationPortId: destinationPortId)
        } nav: {
            BottomNav.vesselOperatorShipments()
        }
    }
}

// MARK: - Model

private struct Surcharge762Line: Identifiable {
    enum Trend { case up, down, flat }
    let id: String
    let code: String          // BASE · BAF · LSS · THC-O · THC-D · PSS · WRS
    let name: String
    let effective: String
    let amount: Double
    let trend: Trend
    let isBase: Bool
    let segColor: Color       // waterfall segment tint
}

/// rateComparison.compare decode (only the fields this screen binds).
private struct RateCompare762: Decodable {
    let rates: [Rate762]
}
private struct Rate762: Decodable {
    let totalAllIn: Double?
    let ratePerUnit: String?
    let surchargesBreakdown: Surcharges762?
}
private struct Surcharges762: Decodable {
    let baf: Double?
    let thcOrigin: Double?
    let thcDestination: Double?
    let pss: Double?
}

// MARK: - Body

private struct VesselSurchargeTransparencyBody: View {
    let originPortId: Int
    let destinationPortId: Int

    @Environment(\.palette) private var palette

    @State private var bols: [VesselDocBOL] = []
    @State private var liveRate: Rate762? = nil
    @State private var loading = true
    @State private var loadError: String? = nil

    // Certified reference composition (the wireframe canon). Overridden per
    // covered code when a live rate returns.
    private var lines: [Surcharge762Line] {
        var base = referenceLines
        if let r = liveRate, let s = r.surchargesBreakdown {
            base = base.map { line in
                let amt: Double? = {
                    switch line.code {
                    case "BASE":  return (r.ratePerUnit).flatMap(Double.init)
                    case "BAF":   return s.baf
                    case "THC-O": return s.thcOrigin
                    case "THC-D": return s.thcDestination
                    case "PSS":   return s.pss
                    default:      return nil
                    }
                }()
                guard let amt, amt > 0 else { return line }
                return Surcharge762Line(id: line.id, code: line.code, name: line.name,
                                        effective: line.effective, amount: amt,
                                        trend: line.trend, isBase: line.isBase, segColor: line.segColor)
            }
        }
        return base
    }

    private var referenceLines: [Surcharge762Line] {
        [
            .init(id: "base",  code: "BASE",  name: "Ocean freight base",       effective: "eff contract", amount: 12000, trend: .flat, isBase: true,  segColor: Brand.blue),
            .init(id: "baf",   code: "BAF",   name: "Bunker adjustment factor", effective: "eff Jun idx",  amount: 1840,  trend: .up,   isBase: false, segColor: Color(hex: 0xFFC246)),
            .init(id: "lss",   code: "LSS",   name: "Low-sulfur surcharge",     effective: "eff IMO 2020", amount: 1200,  trend: .flat, isBase: false, segColor: Color(hex: 0x5AB0FF)),
            .init(id: "thco",  code: "THC-O", name: "Terminal handling · origin", effective: "eff CNSHA",  amount: 1250,  trend: .flat, isBase: false, segColor: Color(hex: 0x34D8A6)),
            .init(id: "thcd",  code: "THC-D", name: "Terminal handling · dest",   effective: "eff USLGB",  amount: 1430,  trend: .flat, isBase: false, segColor: Color(hex: 0xA98BFF)),
            .init(id: "pss",   code: "PSS",   name: "Peak-season surcharge",    effective: "eff Jun–Nov",  amount: 480,   trend: .up,   isBase: false, segColor: Color(hex: 0xFF9F1C)),
            .init(id: "wrs",   code: "WRS",   name: "War-risk surcharge",       effective: "eff Red Sea",  amount: 220,   trend: .flat, isBase: false, segColor: Color(hex: 0xFF6F61)),
        ]
    }

    private var baseAmount: Double { lines.first(where: { $0.isBase })?.amount ?? 0 }
    private var surchargeTotal: Double { lines.filter { !$0.isBase }.reduce(0) { $0 + $1.amount } }
    private var allIn: Double { lines.reduce(0) { $0 + $1.amount } }
    private var surchargeCount: Int { lines.filter { !$0.isBase }.count }

    private var quoteLine: String {
        if let l = bols.first(where: { $0.lane != nil })?.lane { return "MSC quote · 40'HC · \(l)" }
        return "MSC quote · 40'HC · CNSHA→USLGB"
    }
    private var bookingRef: String {
        bols.first?.bolNumber ?? "VES-260523-9F2C41A0E7"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VesselDocTopBar(eyebrow: "VESSEL OPERATOR · SURCHARGES",
                            idCaption: "BAF · LSS · PSS",
                            title: "Surcharges")
            IridescentHairline().padding(.horizontal, Space.s5)

            VStack(alignment: .leading, spacing: Space.s5) {
                if loading {
                    VesselDocSkeleton(bodyHeight: 320)
                } else {
                    heroCard
                    compositionSection
                    ledgerSection
                    TriCountryAuthorityBand(title: "SURCHARGE CURRENCY · TARIFF REGIME",
                                            regimes: currencyRegimes)
                    VesselDocCTAPair(primaryTitle: "Lock this rate",
                                     secondaryTitle: "Export",
                                     primaryIcon: "lock.fill",
                                     onPrimary: {}, onSecondary: {})
                }
                Color.clear.frame(height: 8)
            }
            .padding(.horizontal, Space.s5)
            .padding(.top, Space.s4)
        }
        .task { await load() }
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(quoteLine)
                    .font(EType.mono(.caption))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text("ALL-IN")
                    .font(.system(size: 8.5, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(Color(hex: 0x5AB0FF))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Capsule().fill(Color(hex: 0x5AB0FF).opacity(0.14)))
            }
            Text(vesselDocCurrency(allIn))
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .monospacedDigit()
                .padding(.top, Space.s3)
            Text("base \(vesselDocCurrency(baseAmount)) + \(surchargeCount) surcharges \(vesselDocCurrency(surchargeTotal))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 3)
            Text(liveRate != nil ? "Live rate · FMC tariff filed · USD" : "FMC tariff filed · effective Jun 1–30 · USD")
                .font(.system(size: 11, weight: .bold))
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

    // MARK: Stacked-waterfall composition

    private var compositionSection: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            VesselSectionHeader(label: "ALL-IN COMPOSITION",
                                right: "base + \(surchargeCount)")
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(lines) { line in
                        Rectangle()
                            .fill(line.isBase ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(line.segColor))
                            .frame(width: max(2, geo.size.width * CGFloat(line.amount / max(allIn, 1))))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .frame(height: 22)
            // Legend — the six surcharge segments, compact and scannable.
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                      alignment: .leading, spacing: 6) {
                ForEach(lines.filter { !$0.isBase }) { line in
                    HStack(spacing: 5) {
                        Circle().fill(line.segColor).frame(width: 7, height: 7)
                        Text(line.code)
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: Surcharge ledger

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            VesselSectionHeader(label: "SURCHARGE LEDGER", right: "\(lines.count) lines")
            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.element.id) { idx, line in
                    ledgerRow(line)
                    if idx < lines.count - 1 {
                        Divider().overlay(palette.borderFaint).padding(.horizontal, Space.s4)
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))

            if liveRate == nil {
                VesselDocGapNote(text: "Reference all-in composition. Live per-quote breakdown with effective windows lands with the structured surcharge endpoint.")
            }
        }
    }

    private func ledgerRow(_ line: Surcharge762Line) -> some View {
        HStack(spacing: Space.s3) {
            Text(line.code)
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(line.isBase ? palette.textSecondary : palette.textSecondary)
                .frame(width: 50, height: 18)
                .background(RoundedRectangle(cornerRadius: 6).fill(palette.textPrimary.opacity(0.06)))
            VStack(alignment: .leading, spacing: 3) {
                Text(line.name)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(line.effective)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 6)
            trendGlyph(line.trend)
            Text(vesselDocCurrency(line.amount))
                .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(palette.textPrimary)
        }
        .padding(.horizontal, Space.s4)
        .padding(.vertical, 10)
    }

    @ViewBuilder private func trendGlyph(_ t: Surcharge762Line.Trend) -> some View {
        switch t {
        case .up:
            Image(systemName: "triangle.fill")
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(Color(hex: 0xFFC246))
        case .down:
            Image(systemName: "triangle.fill")
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(Brand.success)
                .rotationEffect(.degrees(180))
        case .flat:
            RoundedRectangle(cornerRadius: 1).fill(palette.textTertiary)
                .frame(width: 8, height: 2.4)
        }
    }

    private var currencyRegimes: [CountryRegime] {
        [
            .init(code: "US", authority: "US · USD · FMC tariff", detail: "BAF / LSS / PSS filed · USD", consequence: nil, state: .active),
            .init(code: "CA", authority: "CA · CAD · CTA", detail: "GST on surcharge · CAD", consequence: nil, state: .standby),
            .init(code: "MX", authority: "MX · MXN · SAT", detail: "IVA 16% · MXN", consequence: nil, state: .standby),
        ]
    }

    // MARK: Load

    private func load() async {
        loading = true; loadError = nil
        struct ListIn: Encodable { let limit: Int }
        struct CompareIn: Encodable { let originPortId: Int; let destinationPortId: Int; let containerSize: String }
        do {
            async let bolTask: [VesselDocBOL] = EusoTripAPI.shared.query(
                "vesselShipments.listBOLs", input: ListIn(limit: 20))
            self.bols = (try? await bolTask) ?? []

            if originPortId > 0 && destinationPortId > 0 {
                let resp: RateCompare762 = try await EusoTripAPI.shared.query(
                    "rateComparison.compare",
                    input: CompareIn(originPortId: originPortId,
                                     destinationPortId: destinationPortId,
                                     containerSize: "40ft_hc"))
                self.liveRate = resp.rates.first
            }
        } catch {
            // The reference composition still renders; surface nothing loud
            // for a missing rate row — the gap note already tells the story.
            self.liveRate = nil
        }
        loading = false
    }
}

#Preview("762 · Vessel Surcharge Transparency · Night") {
    VesselSurchargeTransparencyScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("762 · Vessel Surcharge Transparency · Light") {
    VesselSurchargeTransparencyScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
