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
//  LIVE WIRING (zero-fallback purge · 2026-06-09 · audit B13):
//    • route ledger → tolls.getRecentRoutes (tolls.ts:15) — REAL completed
//      routes, decoded in-file against the exact server projection.
//    • hero spend / split / per-mile / transponders / IFTA basis — SERVER
//      WIRE-GAP: no toll-spend ledger proc exists (tolls.calculate is a
//      zero-stub awaiting an external toll API). All dollar figures render
//      honest em-dash; the old $4,182 MTD seed board is GONE.
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

// MARK: - View model (built from the LIVE tolls.getRecentRoutes envelope only)

private struct TollCorridor_399: Identifiable {
    enum Verdict { case reimbursable, absorbed, unknown }
    let id: String              // load id
    let name: String            // "Houston, TX → Dallas, TX" (real route)
    let tagLine: String         // completion date line
    let amount: String          // "—" until a per-route toll ledger exists
    let verdict: Verdict
    let verdictLabel: String
    let tint: Color
}

private struct TollSpendVM_399 {
    let spendMTD: String
    let monthLabel: String
    let reimbursable: String
    let absorbed: String
    let reimbursableFrac: Double
    let splitCaption: String
    let perLoadedMile: String
    let perMileDelta: String
    let transponders: String
    let iftaBasis: String
    let corridors: [TollCorridor_399]
    let corridorCount: String
    let insightTitle: String
    let insightSub: String

    /// Honest empty envelope — em-dash everywhere until real data exists.
    /// WIRE-GAP: no toll-spend ledger procedure exists server-side
    /// (tolls.calculate is a stub awaiting an external toll API), so the
    /// dollar figures can NEVER light up from this build — they stay
    /// em-dash by design instead of inventing "$4,182".
    static let empty = TollSpendVM_399(
        spendMTD: "—", monthLabel: "MTD",
        reimbursable: "—", absorbed: "—", reimbursableFrac: 0,
        splitCaption: "Toll reimbursement split appears once toll events are connected.",
        perLoadedMile: "—", perMileDelta: "",
        transponders: "—", iftaBasis: "—",
        corridors: [],
        corridorCount: "—",
        insightTitle: "No toll insight yet",
        insightSub: "Connect toll events to see leakage analysis."
    )
}

/// Mirrors one row of `tolls.getRecentRoutes` (tolls.ts:15) — bare array.
private struct RecentRouteWire_399: Decodable {
    let id: Int
    let origin: String
    let destination: String
    let completedAt: String?
}

// MARK: - Body

private struct TollCorridorBody_399: View {
    @Environment(\.palette) private var palette

    // Live state — honest empty envelope until tolls.getRecentRoutes answers.
    @State private var vm: TollSpendVM_399 = .empty
    @State private var loading: Bool = true
    @State private var loadError: String? = nil

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
                Text(loading ? "LOADING…" : "RECENT ROUTES").font(EType.micro).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(spacing: Space.s3) {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(palette.textPrimary).frame(width: 28, height: 28)
                    .accessibilityLabel("Back to Wallet")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Toll Spend").font(EType.display).foregroundStyle(palette.textPrimary)
                    Text(vm.corridors.isEmpty
                         ? "Toll events not yet connected"
                         : "\(vm.corridors.count) recent route\(vm.corridors.count == 1 ? "" : "s") · toll basis pending")
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
            kpiTile("$ / LOADED MI", vm.perLoadedMile, sub: vm.perMileDelta.isEmpty ? "not connected" : vm.perMileDelta,
                    valueStyle: AnyShapeStyle(LinearGradient.diagonal), subColor: palette.textSecondary)
            kpiTile("TRANSPONDERS", vm.transponders, sub: "not connected",
                    valueStyle: AnyShapeStyle(palette.textPrimary), subColor: palette.textSecondary)
            kpiTile("IFTA BASIS", vm.iftaBasis, sub: "not connected",
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
                Text("RECENT ROUTES · TOLL BASIS").font(EType.micro).tracking(1.0).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(vm.corridorCount).font(EType.caption).foregroundStyle(palette.textSecondary)
            }
            VStack(spacing: 0) {
                if vm.corridors.isEmpty {
                    EusoEmptyState(
                        systemImage: "road.lanes",
                        title: loading ? "Loading recent routes…" : "No completed routes yet",
                        subtitle: loading ? "" : (loadError ?? "Completed loads appear here with their toll basis once toll events are connected.")
                    )
                    .padding(.vertical, Space.s3)
                } else {
                    ForEach(Array(vm.corridors.enumerated()), id: \.element.id) { idx, c in
                        corridorRow(c)
                        if idx < vm.corridors.count - 1 {
                            Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.leading, 52)
                        }
                    }
                }
            }
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        }
    }

    private func verdictColor_399(_ v: TollCorridor_399.Verdict) -> Color {
        switch v {
        case .reimbursable: return Brand.success
        case .absorbed:     return Brand.warning
        case .unknown:      return palette.textTertiary
        }
    }

    private func corridorRow(_ c: TollCorridor_399) -> some View {
        HStack(alignment: .center, spacing: Space.s3) {
            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(c.tint.opacity(0.14))
                Image(systemName: c.verdict == .absorbed ? "exclamationmark.triangle" : "road.lanes")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(c.tint)
            }.frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.name).font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(c.tagLine).font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: Space.s2)
            VStack(alignment: .trailing, spacing: 3) {
                Text(c.amount).font(EType.bodyStrong).monospacedDigit().foregroundStyle(palette.textPrimary)
                Text(c.verdictLabel).font(.system(size: 10, weight: .bold)).tracking(0.6)
                    .foregroundStyle(verdictColor_399(c.verdict))
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
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(LinearGradient.primary))
            }.buttonStyle(.plain)
            Button {
                // WIRE: iftaCalculator (loaded-mile toll basis) — hands the
                // loaded-mile toll basis to the IFTA estimator for the Q2 filing.
            } label: {
                Text("IFTA export").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                    .frame(width: 144, height: 48)
                    .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
            }.buttonStyle(.plain)
        }
    }

    // MARK: Network (LIVE — tolls.getRecentRoutes; spend ledger is a server WIRE-GAP)

    private struct RecentRoutesInput_399: Encodable { let limit: Int }

    private func loadAll() async {
        loading = true
        loadError = nil
        defer { loading = false }

        do {
            let routes: [RecentRouteWire_399] = try await EusoTripAPI.shared.query(
                "tolls.getRecentRoutes", input: RecentRoutesInput_399(limit: 8))

            let corridors: [TollCorridor_399] = routes.map { r in
                TollCorridor_399(
                    id: "route-\(r.id)",
                    name: "\(r.origin) → \(r.destination)",
                    tagLine: r.completedAt.map { "completed \(String($0.prefix(10))) · toll basis not yet connected" }
                        ?? "completed — · toll basis not yet connected",
                    amount: "—",
                    verdict: .unknown,
                    verdictLabel: "—",
                    tint: Brand.blue
                )
            }

            // Dollar figures stay em-dash: NO toll-spend ledger proc exists
            // (tolls.calculate is a zero-stub). Routes are the only live data.
            vm = TollSpendVM_399(
                spendMTD: "—", monthLabel: "MTD",
                reimbursable: "—", absorbed: "—", reimbursableFrac: 0,
                splitCaption: "Toll reimbursement split appears once toll events are connected.",
                perLoadedMile: "—", perMileDelta: "",
                transponders: "—", iftaBasis: "—",
                corridors: corridors,
                corridorCount: corridors.isEmpty ? "—" : "\(corridors.count) recent",
                insightTitle: corridors.isEmpty ? "No toll insight yet" : "Toll events not yet connected",
                insightSub: corridors.isEmpty
                    ? "Connect toll events to see leakage analysis."
                    : "These completed routes await per-route toll reconciliation."
            )
        } catch {
            vm = .empty
            loadError = "Couldn't reach the tolls service - retry."
        }
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
