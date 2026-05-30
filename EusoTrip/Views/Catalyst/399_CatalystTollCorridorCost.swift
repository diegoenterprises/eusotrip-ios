//
//  399_CatalystTollCorridorCost.swift
//  EusoTrip 2027 UI — Catalyst track · carrier network-intelligence band
//
//  Moment: Michael Eusorone (Eusotrans LLC owner-op) opens Toll Spend from the
//          Wallet tab to see every toll dollar the fleet ran up this month, split
//          into the share auto-passed back to the shipper-of-record on settlement
//          vs the share his margin absorbed. This is NOT the home/detail skeleton
//          and NOT the 394 lending ledger: the hero is a SPEND figure with a
//          reimbursable/absorbed split bar, and the body is a CORRIDOR ledger —
//          each tollway agency with its transponder tag, event count and the
//          reimbursable/absorbed verdict. Money rows carry the agency chip but
//          omit lifecycle dots (Foundation Contract §5). The screen exists so toll
//          leakage never silently eats linehaul margin.
//
//  Verbatim SwiftUI twin of:
//    03 Catalyst/Dark-SVG/399 Catalyst Toll Corridor Cost.svg
//  ported into the iOS house Shell + BottomNav chrome.
//
//  Web peer: /catalyst/wallet/toll-spend.
//  Wiring manifest (line-confirmed on disk — the tolls router has NO Swift
//  client surface yet, so the hero/split/corridor seeds below are the Code/
//  representative figures that mirror the SVG verbatim and get overwritten on
//  hydrate once the tolls client lands; one WIRE marker per missing call):
//    • hero spend + split + corridor rows → tolls.getRecentRoutes (tolls.ts:15)
//    • per-route toll basis               → tolls.calculate        (tolls.ts:52)
//    • "Reconcile to loads" CTA           → catalystProcedure write (_core/trpc.ts:150)
//      (posts the toll accessorial line on each load settlement via the
//       accessorial router, inserts a blockchainAudit row, broadcasts the
//       settlement delta on the wallet WS channel for the carrier)
//    • "IFTA export" CTA                  → iftaCalculator (loaded-mile toll basis)
//  transportMode = truck; country = US (FHWA tollway agencies, USD). CA 407-ETR /
//  MX casetas resolve through detectLoadCountry when a corridor crosses.
//  Reimbursable share is billed to shipper-of-record Diego Usoro / Eusorone (§11).
//  RBAC: read protectedProcedure; write catalystProcedure (carrier-scope).
//
//  Bottom nav (Catalyst variant): HOME · DISPATCH · [orb] · WALLET · ME (WALLET current).
//

import SwiftUI

// MARK: - Shell wrapper

struct CatalystTollCorridorCostScreen: View {
    let theme: Theme.Palette

    init(theme: Theme.Palette) {
        self.theme = theme
    }

    var body: some View {
        Shell(theme: theme) {
            TollCorridorBody_399()
        } nav: {
            BottomNav(
                leading: catalystNavLeading_399(),
                trailing: catalystNavTrailing_399(),
                orbState: .idle
            )
        }
    }
}

// MARK: - BottomNav (HOME · DISPATCH · [orb] · WALLET · ME — WALLET current)

private func catalystNavLeading_399() -> [NavSlot] {
    [NavSlot(label: "Home",     systemImage: "house.fill", isCurrent: false),
     NavSlot(label: "Dispatch", systemImage: "tray.full",  isCurrent: false)]
}

private func catalystNavTrailing_399() -> [NavSlot] {
    [NavSlot(label: "Wallet", systemImage: "creditcard",  isCurrent: true),
     NavSlot(label: "Me",     systemImage: "person.fill", isCurrent: false)]
}

// MARK: - View model (seeded with the Code/ representative figures · SVG-verbatim)

private struct TollCorridor_399: Identifiable {
    enum Verdict { case reimbursable, absorbed }
    let id: String              // agency tag id
    let name: String            // "I-80 Ohio Turnpike"
    let tagLine: String         // "E-ZPass OH-44192 · 38 events · cl-5"
    let amount: String          // "$1,486"
    let verdict: Verdict
    let verdictLabel: String    // "100% REIMB" / "ABSORBED"
    let tint: Color             // chip + glyph tint
}

private struct TollSpendVM_399 {
    let spendMTD: String            // "$4,182"
    let monthLabel: String          // "MTD MAY"
    let reimbursable: String        // "$3,140"
    let absorbed: String            // "$1,042"
    let reimbursableFrac: Double    // 0.75
    let splitCaption: String        // "75% auto-billed to shipper-of-record · settled on payout"
    let perLoadedMile: String       // "$0.31"
    let perMileDelta: String        // "−4% vs Apr"
    let transponders: String        // "3"
    let iftaBasis: String           // "$2.1k"
    let corridors: [TollCorridor_399]
    let corridorCount: String       // "4 of 18"
    let insightTitle: String        // "ESang: the NJ $842 leg ran empty"
    let insightSub: String          // "Loaded routing via US-1 saves ~$58/trip"
}

private let seedTollSpend_399 = TollSpendVM_399(
    spendMTD: "$4,182", monthLabel: "MTD MAY",
    reimbursable: "$3,140", absorbed: "$1,042", reimbursableFrac: 0.75,
    splitCaption: "75% auto-billed to shipper-of-record · settled on payout",
    perLoadedMile: "$0.31", perMileDelta: "−4% vs Apr",
    transponders: "3", iftaBasis: "$2.1k",
    corridors: [
        TollCorridor_399(id: "OH-44192", name: "I-80 Ohio Turnpike",
                         tagLine: "E-ZPass OH-44192 · 38 events · cl-5",
                         amount: "$1,486", verdict: .reimbursable, verdictLabel: "100% REIMB", tint: Brand.blue),
        TollCorridor_399(id: "PA-77310", name: "I-76 PA Turnpike",
                         tagLine: "E-ZPass PA-77310 · 29 events · cl-5",
                         amount: "$1,204", verdict: .reimbursable, verdictLabel: "100% REIMB", tint: Brand.blue),
        TollCorridor_399(id: "NJ-55028", name: "NJ Turnpike",
                         tagLine: "E-ZPass NJ-55028 · 21 events · deadhead",
                         amount: "$842", verdict: .absorbed, verdictLabel: "ABSORBED", tint: Brand.warning),
        TollCorridor_399(id: "NY-90114", name: "GW Bridge · Port Authority",
                         tagLine: "E-ZPass NY-90114 · 6 crossings · 5-axle",
                         amount: "$650", verdict: .reimbursable, verdictLabel: "100% REIMB", tint: Brand.escort),
    ],
    corridorCount: "4 of 18",
    insightTitle: "ESang: the NJ $842 leg ran empty",
    insightSub: "Loaded routing via US-1 saves ~$58/trip"
)

// MARK: - Body

private struct TollCorridorBody_399: View {
    @Environment(\.palette) private var palette

    // House 0%-mock: seeds mirror the SVG verbatim and are overwritten on
    // hydrate once the tolls client surface lands (see WIRE markers in loadAll).
    @State private var vm: TollSpendVM_399 = seedTollSpend_399

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            IridescentHairline()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Space.s4) {
                    heroCard
                    kpiStrip
                    corridorSection
                    insightRow
                    ctaPair
                }
                .padding(.horizontal, Space.s5)
                .padding(.top, Space.s3)
                .padding(.bottom, Space.s7)
            }
        }
        .task { await loadAll() }
    }

    // MARK: TopBar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("✦ CATALYST · TOLLS").font(EType.micro).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text("BESTPASS · 3 TAGS").font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary).frame(width: 28, height: 28)
                    .accessibilityLabel("Back to Wallet")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Toll Spend").font(EType.display).foregroundStyle(palette.textPrimary)
                    Text("Eusotrans LLC · 142 toll events MTD · auto-reconciled")
                        .font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
            }
            .padding(.top, Space.s2)
        }
        .padding(.horizontal, Space.s5).padding(.top, Space.s5).padding(.bottom, Space.s3)
    }

    // MARK: Hero — MTD spend + reimbursable/absorbed split bar

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(LinearGradient.diagonal)
            RoundedRectangle(cornerRadius: Radius.xl - 1.5, style: .continuous).fill(palette.bgCard).padding(1.5)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TOLL SPEND · \(vm.monthLabel)").font(EType.micro).tracking(1.0)
                            .foregroundStyle(palette.textTertiary)
                        Text(vm.spendMTD).font(.system(size: 38, weight: .bold).monospacedDigit())
                            .foregroundStyle(LinearGradient.diagonal)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("REIMBURSABLE").font(EType.micro).tracking(0.6).foregroundStyle(Brand.success)
                        Text(vm.reimbursable).font(.system(size: 16, weight: .bold).monospacedDigit())
                            .foregroundStyle(Brand.success)
                        Text("ABSORBED").font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
                            .padding(.top, 2)
                        Text(vm.absorbed).font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                splitBar.padding(.top, Space.s3)
                Text(vm.splitCaption).font(EType.caption).foregroundStyle(palette.textSecondary)
                    .padding(.top, Space.s2)
            }
            .padding(Space.s4)
        }
        .frame(height: 150)
    }

    private var splitBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Brand.rail.opacity(0.18))
                Capsule().fill(Brand.rail).frame(width: geo.size.width)
                Capsule().fill(LinearGradient(colors: [Brand.success, Color(hex: 0x00A57A)],
                                              startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * vm.reimbursableFrac)
            }
        }
        .frame(height: 10)
        .accessibilityLabel("\(Int(vm.reimbursableFrac * 100)) percent reimbursable")
    }

    // MARK: KPI strip

    private var kpiStrip: some View {
        HStack(spacing: Space.s3) {
            kpiTile("$ / LOADED MI", vm.perLoadedMile, sub: vm.perMileDelta,
                    valueStyle: AnyShapeStyle(LinearGradient.diagonal), subColor: Brand.success)
            kpiTile("TRANSPONDERS", vm.transponders, sub: "all active",
                    valueStyle: AnyShapeStyle(palette.textPrimary), subColor: palette.textSecondary)
            kpiTile("IFTA Q2 BASIS", vm.iftaBasis, sub: "loaded-mi credited",
                    valueStyle: AnyShapeStyle(palette.textPrimary), subColor: palette.textSecondary)
        }
    }

    private func kpiTile(_ label: String, _ value: String, sub: String,
                         valueStyle: AnyShapeStyle, subColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(EType.micro).tracking(1.0).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 26, weight: .semibold).monospacedDigit()).foregroundStyle(valueStyle)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(EType.caption).foregroundStyle(subColor).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(Space.s3).frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: Corridor ledger

    private var corridorSection: some View {
        VStack(alignment: .leading, spacing: Space.s2) {
            HStack {
                Text("TOLL CORRIDORS · MTD").font(EType.micro).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(vm.corridorCount).font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(vm.corridors.enumerated()), id: \.element.id) { idx, c in
                    corridorRow(c)
                    if idx < vm.corridors.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, 52)
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private func corridorRow(_ c: TollCorridor_399) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(c.tint.opacity(0.14))
                Image(systemName: c.verdict == .reimbursable ? "road.lanes" : "exclamationmark.triangle")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(c.tint)
            }.frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.name).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                Text(c.tagLine).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 3) {
                Text(c.amount).font(EType.bodyStrong).monospacedDigit().foregroundStyle(palette.textPrimary)
                Text(c.verdictLabel).font(.system(size: 10, weight: .bold)).tracking(0.6)
                    .foregroundStyle(c.verdict == .reimbursable ? Brand.success : Brand.warning)
            }
        }
        .padding(Space.s3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(c.name), \(c.amount), \(c.verdictLabel)")
    }

    // MARK: ESang insight

    private var insightRow: some View {
        Button {
            // WIRE: tolls.getRecentRoutes (tolls.ts:15) — tap drills into the
            // empty-leg detail the ESang insight surfaces; routes off the
            // corridor envelope once the tolls client lands.
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal)
                    Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear],
                                                 center: .init(x: 0.35, y: 0.30), startRadius: 0, endRadius: 16))
                }.frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.insightTitle).font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    Text(vm.insightSub).font(EType.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(Space.s3)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            Button {
                // WIRE: catalystProcedure write (_core/trpc.ts:150) — posts the
                // toll accessorial line on each load settlement via the
                // accessorial router, inserts a blockchainAudit row, broadcasts
                // the settlement delta on the wallet WS channel for the carrier.
            } label: {
                Text("Reconcile to loads").font(EType.bodyStrong).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Capsule().fill(LinearGradient.primary))
            }.buttonStyle(.plain)
            Button {
                // WIRE: iftaCalculator (loaded-mile toll basis) — hands the
                // loaded-mile toll basis to the IFTA estimator for the Q2 filing.
            } label: {
                Text("IFTA export").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 144, height: 48)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
            }.buttonStyle(.plain)
        }
    }

    // MARK: Network

    private func loadAll() async {
        // WIRE: tolls.getRecentRoutes (tolls.ts:15) — hero spend + reimbursable/
        // absorbed split + corridor rows. No Swift client surface on EusoTripAPI
        // yet, so the SVG-verbatim seeds above stand in (house 0%-mock); this
        // overwrites `vm` once `EusoTripAPI.shared.tolls.getRecentRoutes()` lands.
        // WIRE: tolls.calculate (tolls.ts:52) — per-route toll basis enrichment
        // for each corridor row.
    }
}

// MARK: - Previews

#Preview("399 · Catalyst · Toll Spend · Night") {
    CatalystTollCorridorCostScreen(theme: Theme.dark)
        .preferredColorScheme(.dark)
}

#Preview("399 · Catalyst · Toll Spend · Afternoon") {
    CatalystTollCorridorCostScreen(theme: Theme.light)
        .preferredColorScheme(.light)
}
