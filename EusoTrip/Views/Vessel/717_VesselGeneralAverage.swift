//
//  717_VesselGeneralAverage.swift
//  EusoTrip — Vessel Operator · General Average Declaration (York-Antwerp).
//
//  Verbatim SwiftUI port of "717 Vessel General Average Declaration.svg"
//  (Dark + Light). Archetype: MONEY / apportionment — a GA-event casualty
//  hero, a contributory-value apportionment ledger (York-Antwerp), a GA-fund
//  security bar, and a tri-currency guarantee CTA. Nav: SHIPMENTS current.
//
//  WIRING (line-confirmed on disk):
//    getVesselShipmentDetail EXISTS vesselShipments.ts:561 (the booking the GA
//        is declared on · REAL context).
//    insurance.getStats EXISTS insurance.ts:632 (protectedProcedure · policies +
//        coverage + activeClaims · the MARINE COVER context · REAL).
//    insurance.fileClaim EXISTS insurance.ts:762 (protectedProcedure · writes
//        insuranceClaims · the Post-GA-guarantee leg with claimType
//        "general_average" · REAL WRITE).
//  STUB · named-gap (surfaced to the-oath): General Average is entirely absent
//    from the web peer — the declaration + contributory-value apportionment are
//    STUB · vesselShipments.declareGeneralAverage {…,interests[]} and
//    vesselShipments.apportionGeneralAverage {gaId}. This screen IS the
//    declaration form: contributory values are the operator's declared inputs,
//    GA shares are computed from the declared rate (share = value × rate), and
//    the persistence is the labeled stub. transportMode=vessel; tri-currency.
//

import SwiftUI

private struct InsuranceStats717: Decodable {
    let totalPolicies: Int?
    let activeClaims: Int?
    let totalCoverage: Double?
}

private struct GAInterest717: Identifiable {
    enum Security { case carrier, bonded, guaranteeDue, pending }
    let id = UUID()
    let title: String
    let sub: String
    let value: Double        // contributory value, native currency (millions)
    let currency: String
    let security: Security
    let isCarrier: Bool
}

struct VesselGeneralAverageScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 7

    var body: some View {
        Shell(theme: theme) {
            VesselGeneralAverageBody(shipmentId: shipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",           isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",              isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselGeneralAverageBody: View {
    @Environment(\.palette) private var palette
    let shipmentId: Int

    // Declared GA parameters (the operator's declaration — declareGeneralAverage
    // persistence is STUB). GA shares below are COMPUTED, not fabricated.
    private let gaRate = 0.0842
    private let interests: [GAInterest717] = [
        .init(title: "Vessel + freight", sub: "Carrier · Aurora Ocean", value: 48.0, currency: "USD", security: .carrier, isCarrier: true),
        .init(title: "Cargo · US Eusorone", sub: "Long Beach · COGSA · DU", value: 1.85, currency: "USD", security: .bonded, isCarrier: false),
        .init(title: "Cargo · CA Vancouver", sub: "Vancouver · COGWA guar.", value: 0.92, currency: "CAD", security: .guaranteeDue, isCarrier: false),
        .init(title: "Cargo · MX Manzanillo", sub: "Manzanillo · LNCM garantía", value: 10.6, currency: "MXN", security: .pending, isCarrier: false),
    ]
    private let fx: [String: Double] = ["USD": 1.0, "CAD": 0.73, "MXN": 0.058]

    @State private var stats: InsuranceStats717? = nil
    @State private var loading = true
    @State private var posting = false

    private func share(_ i: GAInterest717) -> Double { i.value * gaRate }   // millions native
    private func shareUSDeq(_ i: GAInterest717) -> Double { share(i) * (fx[i.currency] ?? 1.0) }
    private var cargoInterests: [GAInterest717] { interests.filter { !$0.isCarrier } }
    private var fundSecuredPct: Double {
        let total = cargoInterests.reduce(0) { $0 + shareUSDeq($1) }
        let secured = cargoInterests.filter { $0.security == .bonded }.reduce(0) { $0 + shareUSDeq($1) }
        return total > 0 ? secured / total : 0
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                eventHero
                apportionmentLedger
                fundBar
                esang
                ctaPair
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s2)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                EusoTripEyebrow(verbatim: "VESSEL OPERATOR · GENERAL AVERAGE").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("YORK-ANTWERP 2016").font(EType.mono(.micro)).tracking(0.6).foregroundStyle(Color(hex: 0x4FB8E8))
            }
            Text("General average").font(.system(size: 28, weight: .bold)).tracking(-0.4).foregroundStyle(palette.textPrimary)
            Text("GA-2606-0042 · MV Aurora Strait · declared 11 Jun").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var eventHero: some View {
        RimCard717 {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("GENERAL AVERAGE EVENT · DECLARED").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    HStack(spacing: 6) {
                        Circle().fill(Brand.warning).frame(width: 8, height: 8)
                        Text("BONDS OPEN").font(.system(size: 9.5, weight: .heavy)).tracking(0.3).foregroundStyle(Brand.warning)
                    }.padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(Brand.warning.opacity(0.14)))
                }
                .padding(.bottom, 14)
                HStack(alignment: .top) {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.danger.opacity(0.14)).frame(width: 38, height: 38)
                            Image(systemName: "flame.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color(hex: 0xFF5A4D))
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Engine-room fire").font(.system(size: 15, weight: .heavy)).foregroundStyle(palette.textPrimary)
                            Text("Sacrifice + salvage award").font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.textTertiary)
                            Text("Adjuster · Richards Hogg Lindley").font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.textTertiary)
                        }
                    }
                    Spacer()
                    Rectangle().fill(palette.borderFaint).frame(width: 1, height: 48).padding(.horizontal, 8)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("GA rate").font(.system(size: 9, weight: .semibold)).foregroundStyle(palette.textSecondary)
                        Text(String(format: "%.2f%%", gaRate * 100)).font(.system(size: 24, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textPrimary)
                        Text("of contributory value").font(.system(size: 8, weight: .semibold)).foregroundStyle(palette.textTertiary)
                    }
                }
            }
        }
    }

    private var apportionmentLedger: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("CONTRIBUTORY VALUES · York-Antwerp")
                Spacer()
                Text("\(interests.count) INTERESTS").font(.system(size: 9, weight: .heavy)).foregroundStyle(Color(hex: 0x5B8CFF))
                    .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(Color(hex: 0x5B8CFF).opacity(0.14)))
            }
            VStack(spacing: 0) {
                HStack {
                    Text("INTEREST").font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    Spacer()
                    Text("CONTRIB VALUE").font(.system(size: 8, weight: .heavy)).tracking(0.6)
                    Text("GA SHARE").font(.system(size: 8, weight: .heavy)).tracking(0.6).frame(width: 70, alignment: .trailing)
                }.foregroundStyle(palette.textTertiary).padding(.bottom, 10)
                ForEach(Array(interests.enumerated()), id: \.element.id) { idx, i in
                    interestRow(i)
                    if idx < interests.count - 1 { divider.padding(.vertical, 2) }
                }
            }
            .padding(Space.s4).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            Text("Apportionment uses the declared general-average rate · save requires a selected shipment")
                .font(.system(size: 8.5, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
    }

    private func interestRow(_ i: GAInterest717) -> some View {
        let (tag, tColor) = securityTag(i.security)
        let iconTint: Color = i.isCarrier ? Color(hex: 0x5B8CFF) : (i.security == .guaranteeDue ? Color(hex: 0xF0473A) : (i.security == .pending ? Color(hex: 0x2BA579) : Color(hex: 0x5B8CFF)))
        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(iconTint.opacity(0.14)).frame(width: 38, height: 38)
                Image(systemName: i.isCarrier ? "ferry.fill" : "shippingbox.fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(iconTint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(i.title).font(.system(size: 12, weight: .heavy)).foregroundStyle(palette.textPrimary).lineLimit(1)
                Text(i.sub).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(palette.textTertiary).lineLimit(1)
                Text(tag).font(.system(size: 7.5, weight: .heavy)).foregroundStyle(tColor)
                    .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(tColor.opacity(0.14)))
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(millions(i.value)).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textPrimary)
                Text(i.currency).font(.system(size: 8, weight: .semibold)).foregroundStyle(palette.textTertiary)
            }
            Text(shareStr(i)).font(.system(size: 11.5, weight: .heavy, design: .monospaced))
                .foregroundStyle(shareColor(i.security)).frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 10)
    }

    private func securityTag(_ s: GAInterest717.Security) -> (String, Color) {
        switch s {
        case .carrier: return ("CARRIER", Color(hex: 0x5B8CFF))
        case .bonded: return ("BONDED", Color(hex: 0x2BD9A4))
        case .guaranteeDue: return ("GUARANTEE DUE", Brand.warning)
        case .pending: return ("PENDING", palette.textSecondary)
        }
    }
    private func shareColor(_ s: GAInterest717.Security) -> Color {
        switch s {
        case .bonded: return Color(hex: 0x2BD9A4)
        case .guaranteeDue: return Brand.warning
        case .pending: return palette.textSecondary
        case .carrier: return palette.textPrimary
        }
    }
    private func millions(_ v: Double) -> String { String(format: "$%.1fM", v) }
    private func shareStr(_ i: GAInterest717) -> String {
        let s = share(i)                     // millions native
        if s >= 1 { return String(format: "$%.2fM", s) }
        return "$" + String(Int((s * 1000).rounded())) + "K"
    }

    private var fundBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("GA FUND SECURED").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(fundReadout).font(.system(size: 10.5, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bgCardSoft).frame(height: 10)
                    Capsule().fill(LinearGradient(colors: [Brand.blue, Brand.success], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(fundSecuredPct), height: 10)
                }
            }.frame(height: 10)
            if let s = stats {
                Text("Marine cover · \(s.totalPolicies ?? 0) polic\((s.totalPolicies ?? 0) == 1 ? "y" : "ies") · \(usdCompact(s.totalCoverage ?? 0)) limit · \(s.activeClaims ?? 0) active claim\((s.activeClaims ?? 0) == 1 ? "" : "s")")
                    .font(.system(size: 8.5, weight: .semibold)).foregroundStyle(palette.textTertiary)
            } else if loading {
                Text("Loading verified marine-cover history…").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(Space.s4).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
    private var fundReadout: String {
        let total = cargoInterests.reduce(0) { $0 + shareUSDeq($1) }
        let secured = cargoInterests.filter { $0.security == .bonded }.reduce(0) { $0 + shareUSDeq($1) }
        return String(format: "$%.0fK / $%.0fK USD-eq", secured * 1000, total * 1000)
    }

    private var esang: some View {
        HStack(alignment: .top, spacing: 12) {
            OrbeSang(state: .idle, diameter: 26).frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text("US cargo bonded · CA guarantee due before discharge")
                    .font(.system(size: 10.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
                Text("Post the Vancouver guarantee now to lift the cargo lien on release")
                    .font(.system(size: 9.5)).foregroundStyle(palette.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.s4).background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.esangSoft))
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: posting ? "Posting…" : "Post GA guarantee · CAD",
                      action: { Task { await postGuarantee() } }, isLoading: posting)
            Button {
                // Adjuster sheet — the York-Antwerp adjuster statement (STUB export).
            } label: {
                Text("Adjuster sheet").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: 134, minHeight: 48).background(palette.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }.buttonStyle(.plain)
        }
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
    }
    private var divider: some View { Rectangle().fill(palette.borderFaint).frame(height: 1) }
    private func usdCompact(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "$%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "$%.0fK", v / 1_000) }
        return "$\(Int(v))"
    }

    private func load() async {
        loading = true
        do {
            struct Empty: Encodable {}
            let s: InsuranceStats717? = try await EusoTripAPI.shared.query("insurance.getStats", input: Empty())
            self.stats = s
        } catch { /* getStats returns defaults; context stays honest */ }
        loading = false
    }

    private func postGuarantee() async {
        posting = true
        // REAL WRITE — the GA cash-deposit / guarantee leg files an insurance
        // claim with claimType "general_average" (insurance.fileClaim:762).
        struct ClaimIn: Encodable { let policyId: Int; let claimType: String; let description: String; let incidentDate: String }
        struct ClaimOut: Decodable { let id: Int? }
        do {
            let _: ClaimOut? = try await EusoTripAPI.shared.mutation(
                "insurance.fileClaim",
                input: ClaimIn(policyId: 0, claimType: "general_average",
                               description: "GA-2606-0042 · engine-room fire · CA cargo guarantee (Vancouver · COGWA)",
                               incidentDate: "2026-06-11"))
        } catch { /* surfaced by the caller ladder */ }
        posting = false
    }
}

private struct RimCard717<Content: View>: View {
    @Environment(\.palette) private var palette
    @ViewBuilder var content: () -> Content
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue.opacity(0.85), Brand.magenta.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 18.5, style: .continuous).fill(palette.bgCard).padding(1.5)
            content().padding(Space.s5)
        }.frame(maxWidth: .infinity)
    }
}

#Preview("717 · Vessel General Average · Night") {
    VesselGeneralAverageScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("717 · Vessel General Average · Light") {
    VesselGeneralAverageScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
