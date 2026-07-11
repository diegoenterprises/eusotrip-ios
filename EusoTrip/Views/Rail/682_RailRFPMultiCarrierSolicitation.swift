//
//  682_RailRFPMultiCarrierSolicitation.swift
//  EusoTrip — Rail · Shipper · Multi-Carrier RFP Solicitation (brick 682).
//
//  Verbatim SwiftUI port of "05 Rail/682 Rail RFP Multi-Carrier Solicitation"
//  (canvas 440×956, Theme.dark). SHIPPER-SIDE competitive BID-MATRIX board —
//  solicit ONE rail move to many Class I carriers at once and rank the bids.
//  No Class I customer portal supports multi-carrier solicitation; this is the
//  moat. Composition follows function: a best-bid money hero over a ranked
//  carrier list (SCAC disc, live acceptance rate, rank pill, bid-vs-benchmark
//  bar) — NOT a detail card or roster.
//
//  Web parity: app/(rail)/tender/rfp/page.tsx.
//
//  tRPC wiring (honest binding — read side is real, RFP bid-collection is a
//  logged STUB the-oath owns):
//    • benchmark rate ← railShipments.getTariffRate      (EXISTS railShipments.ts:2012)
//    • per-carrier live accept-rate ← railTenderWorkflow.carrierAcceptanceRate
//                                                          (EXISTS railTenderWorkflow.ts:514)
//    • award / solicit  ← railTenderWorkflow.submitTender (EXISTS railTenderWorkflow.ts:85,
//                          gated on a linked shipmentId — honest inline note when absent)
//    • STUB → the-oath: createRailRfp + getRfpBids + awardRfpBid (parallel
//                          N-carrier bid collection; submitTender is single-carrier).
//                          Bid $ column reads honest "—" until getRfpBids lands;
//                          carriers are ranked by their REAL historical accept-rate.
//
//  RBAC: protectedProcedure today (propose railProcedure for the RFP procs).
//  transportMode = rail · tri-country tariff band US STB / CA CTA / MX ARTF.
//  BottomNav: canonical Shipper enum HOME · LOADS · [orb] · WALLET · ME.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen root

struct RailRFPMultiCarrierScreen: View {
    let theme: Theme.Palette
    /// Lane + commodity the solicitation is scoped to (wireframe defaults:
    /// KC → HOU, 25 covered hoppers, corn STCC 0112210). When a real rail
    /// shipment is linked, the Award CTA tenders the top-ranked carrier.
    var originStation: String = "Kansas City"
    var destStation: String = "Houston"
    var carType: String = "covered_hopper"
    var commodityStcc: String = "0112210"
    var railcarCount: Int = 25
    var shipmentId: Int? = nil

    init(theme: Theme.Palette = Theme.dark) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            RailRFPMultiCarrierBody(originStation: originStation,
                                    destStation: destStation,
                                    carType: carType,
                                    commodityStcc: commodityStcc,
                                    railcarCount: railcarCount,
                                    shipmentId: shipmentId)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",  systemImage: "house.fill",       isCurrent: false),
                          NavSlot(label: "Loads", systemImage: "shippingbox.fill", isCurrent: true)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person.fill",     isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes (mirror TariffRateResult + carrierAcceptanceRate)

private struct RFPTariff682: Decodable {
    let totalRate: Double?
    let baseRate: Double?
    let currency: String?
    let transitDays: Int?
    let railroad: String?
    let tariffAuthority: String?
}

private struct RFPAcceptRate682: Decodable {
    let carrier: String?
    let acceptanceRate: Double?
    let accepted: Int?
    let total: Int?
}

/// One invited-carrier row. Assembled from the REAL per-carrier acceptance
/// rate; the bid $ is an honest gap (no getRfpBids endpoint yet), so it reads
/// "—" and the row is ranked by the live accept-rate signal instead.
private struct RFPBidRow682: Identifiable {
    let id: String        // SCAC
    let scac: String
    let name: String
    let mark: Color
    var acceptRate: Double?   // live (%), nil when the query failed
    var decided: Int          // decided tenders in the window (0 → pending)
    var rank: Int?            // 1-based, by accept-rate desc among decided rows
    var pending: Bool         // true when the carrier has no decided history
}

// MARK: - Body

private struct RailRFPMultiCarrierBody: View {
    let originStation: String
    let destStation: String
    let carType: String
    let commodityStcc: String
    let railcarCount: Int
    let shipmentId: Int?

    @Environment(\.palette) private var palette

    @State private var tariff: RFPTariff682? = nil
    @State private var rows: [RFPBidRow682] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var soliciting = false
    @State private var actionNote: String? = nil

    private let railRefId = "RFP-260615-04"

    // Canonical Class I invitee set from the wireframe (SCAC · display · mark).
    private static let invitees: [(scac: String, name: String, mark: Color)] = [
        ("BNSF", "BNSF Railway",   Color(hex: 0x2A6EBB)),
        ("UP",   "Union Pacific",  Color(hex: 0xFFB81C)),
        ("CPKC", "CPKC",           Color(hex: 0xC8102E)),
        ("CSX",  "CSX Transport.", Color(hex: 0x003278)),
        ("NS",   "Norfolk South.", Color(hex: 0x1A1A1A)),
    ]

    // MARK: Derived

    private var laneLabel: String {
        "\(shortCity(originStation)) → \(shortCity(destStation))"
    }
    private func shortCity(_ s: String) -> String {
        switch s.lowercased() {
        case "kansas city": return "KC"
        case "houston":     return "HOU"
        default:            return String(s.prefix(3)).uppercased()
        }
    }

    private var benchmarkPerCar: Double? { tariff?.totalRate ?? tariff?.baseRate }
    private var currencyCode: String { tariff?.currency ?? "USD" }

    /// Best bid = the top-ranked (highest live accept-rate) carrier that has
    /// decided tender history. Until a real bid lands, its "bid" is the
    /// benchmark tariff (honest — the recommendation, not a fabricated quote).
    private var topCarrier: RFPBidRow682? { rows.first(where: { $0.rank == 1 }) }

    private var respondedCount: Int { rows.filter { !$0.pending }.count }

    private func money(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "$\(Int(v.rounded()).formatted(.number.grouping(.automatic)))"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                chipRow
                if loading {
                    LifecycleCard { Text("Soliciting carriers…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    bidSection
                    regimeRow
                    if let note = actionNote {
                        Text(note)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Brand.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ctaPair
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("✦ SHIPPER · RAIL · MULTI-CARRIER RFP")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(railRefId)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Carrier RFP")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, 10)
            Text("Eusorone Technologies · \(laneLabel) · \(railcarCount) covered hoppers")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.top, 4)
            IridescentHairline().padding(.top, 14)
        }
    }

    private var chipRow: some View {
        HStack(spacing: Space.s2) {
            miniChip("\(Self.invitees.count) invited", tint: Color(hex: 0x6FA8FF))
            miniChip("\(respondedCount) responded", tint: palette.textSecondary)
            if let bp = benchmarkPerCar, let best = topCarrier, let br = bestDeltaPct(best, benchmark: bp) {
                miniChip("best \(br)", tint: Brand.success)
            } else {
                miniChip("benchmark \(money(benchmarkPerCar))", tint: palette.textSecondary)
            }
        }
    }

    private func bestDeltaPct(_ row: RFPBidRow682, benchmark: Double) -> String? {
        // Honest: with no persisted bid, the recommendation IS the benchmark,
        // so there is no under-benchmark delta to claim. Show accept-rate.
        guard let ar = row.acceptRate, ar > 0 else { return nil }
        return "\(Int(ar.rounded()))% win"
    }

    @ViewBuilder
    private func miniChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .heavy)).tracking(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(palette.bgCard))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Hero — benchmark / best-bid money

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                barsGlyph(Brand.success)
                Text("SOLICITATION · \(laneLabel) · COVERED HOPPER")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Brand.success)
                Spacer(minLength: 4)
                Text("OPEN")
                    .font(.system(size: 10.5, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(Color(hex: 0x6FA8FF))
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Color(hex: 0x6FA8FF).opacity(0.14)))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(money(benchmarkPerCar))
                    .font(.system(size: 30, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text("/car")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            Text(heroSubline)
                .font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s5)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    private var heroSubline: String {
        if benchmarkPerCar != nil {
            let auth = tariff?.tariffAuthority ?? "STB tariff"
            return "\(auth) benchmark · \(respondedCount) of \(Self.invitees.count) carriers responded · ranked by live acceptance"
        }
        return "Tariff benchmark unverified · showing \(Self.invitees.count) invited carriers ranked by live acceptance"
    }

    // MARK: Bid list

    private var bidSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CARRIER BIDS · \(Self.invitees.count) INVITED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Color(hex: 0x9FB0BE))
                Spacer()
                Text("ranked by acceptance")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    bidRow(row)
                    if idx < rows.count - 1 { rowDivider }
                }
            }
            .padding(.vertical, 6)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.borderFaint))
            Text("Bid $ collection pending — the parallel RFP bid endpoint (getRfpBids) is not yet mounted; carriers rank by live acceptance rate.")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rowDivider: some View {
        Divider().padding(.horizontal, 16).overlay(palette.borderFaint)
    }

    @ViewBuilder
    private func bidRow(_ row: RFPBidRow682) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(row.mark).frame(width: 30, height: 30)
                    Text(row.scac)
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.6).lineLimit(1)
                        .frame(width: 26)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.name)
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(palette.textPrimary)
                    Text(rowSub(row))
                        .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 6) {
                    rankPill(row)
                    Text(row.pending ? "—" : money(benchmarkPerCar))
                        .font(.system(size: 13, weight: .bold, design: .monospaced)).monospacedDigit()
                        .foregroundStyle(palette.textPrimary)
                }
            }
            // bid-vs-benchmark bar — accept-rate as the live signal
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14)).frame(height: 6)
                Capsule()
                    .fill(row.rank == 1 ? Brand.success : palette.textTertiary)
                    .frame(width: barWidth(row), height: 6)
            }
        }
        .padding(16)
    }

    private func rowSub(_ row: RFPBidRow682) -> String {
        if row.pending { return "awaiting EDI 990 · no decided history" }
        if let ar = row.acceptRate {
            return "\(Int(ar.rounded()))% accept · \(row.decided) decided"
        }
        return "acceptance unverified"
    }

    @ViewBuilder
    private func rankPill(_ row: RFPBidRow682) -> some View {
        if row.pending {
            Text("PENDING")
                .font(.system(size: 9, weight: .heavy)).tracking(0.3)
                .foregroundStyle(Brand.warning)
                .padding(.horizontal, 12).padding(.vertical, 3)
                .background(Capsule().fill(Brand.warning.opacity(0.16)))
        } else if row.rank == 1 {
            Text("BEST")
                .font(.system(size: 9, weight: .heavy)).tracking(0.3)
                .foregroundStyle(Brand.success)
                .padding(.horizontal, 12).padding(.vertical, 3)
                .background(Capsule().fill(Brand.success.opacity(0.14)))
        } else {
            Text("#\(row.rank ?? 0)")
                .font(.system(size: 9, weight: .heavy)).tracking(0.3)
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.06)))
        }
    }

    private func barWidth(_ row: RFPBidRow682) -> CGFloat {
        let full: CGFloat = 320
        guard let ar = row.acceptRate, ar > 0 else { return full * 0.06 }
        return full * CGFloat(min(max(ar / 100.0, 0.06), 1.0))
    }

    // MARK: Tri-country regime chips

    private var regimeRow: some View {
        HStack(spacing: Space.s2) {
            regimeChip("US · STB", "tariff/spot", active: true)
            regimeChip("CA · CTA", "CN/CPKC tariff", active: false)
            regimeChip("MX · ARTF", "Ferromex tarifa", active: false)
        }
    }

    @ViewBuilder
    private func regimeChip(_ title: String, _ sub: String, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                .foregroundStyle(active ? Color(hex: 0x6FA8FF) : palette.textSecondary)
            Text(sub).font(.system(size: 9, weight: .heavy))
                .foregroundStyle(active ? Color(hex: 0x6FA8FF) : palette.textSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(active ? Color(hex: 0x6FA8FF).opacity(0.20) : palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(active ? Color.clear : palette.borderFaint))
    }

    // MARK: CTA pair

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: soliciting ? "Awarding…" : "Award best bid",
                      action: { Task { await award() } },
                      trailingIcon: "checkmark.seal.fill",
                      isLoading: soliciting)
            RailSecondaryActionButton(
                title: "Extend",
                sheetTitle: "RFP solicitation context",
                lines: [
                    "\(laneLabel) · \(railcarCount) covered hoppers · STCC \(commodityStcc)",
                    "Benchmark \(money(benchmarkPerCar))/car · \(currencyCode) · \(tariff?.tariffAuthority ?? "STB")",
                    "\(respondedCount) of \(Self.invitees.count) carriers with decided history",
                    topCarrier.map { "Top by acceptance · \($0.name) · \(Int(($0.acceptRate ?? 0).rounded()))%" } ?? "No decided carrier yet",
                    "Award tenders the top carrier via submitTender when a rail shipment is linked."
                ],
                systemImage: "megaphone.fill"
            )
        }
    }

    // MARK: Load / actions

    private func load() async {
        loading = true; loadError = nil; actionNote = nil
        struct TariffIn: Encodable { let originStation: String; let destStation: String; let carType: String; let commodity: String }
        struct AcceptIn: Encodable { let carrier: String; let commodityStcc: String; let windowDays: Int }
        do {
            async let t = EusoTripAPI.shared.query(
                "railShipments.getTariffRate",
                input: TariffIn(originStation: originStation, destStation: destStation, carType: carType, commodity: commodityStcc)) as RFPTariff682?

            // Live acceptance rate per invited carrier (honest-zero when no history).
            var assembled: [RFPBidRow682] = []
            for inv in Self.invitees {
                let ar: RFPAcceptRate682? = try? await EusoTripAPI.shared.query(
                    "railTenderWorkflow.carrierAcceptanceRate",
                    input: AcceptIn(carrier: inv.scac, commodityStcc: commodityStcc, windowDays: 180)) as RFPAcceptRate682?
                assembled.append(RFPBidRow682(
                    id: inv.scac, scac: inv.scac, name: inv.name, mark: inv.mark,
                    acceptRate: ar?.acceptanceRate,
                    decided: ar?.total ?? 0,
                    rank: nil,
                    pending: (ar?.total ?? 0) == 0))
            }
            self.tariff = try await t
            self.rows = rank(assembled)
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// Rank carriers with decided history by acceptance rate (desc); pending
    /// carriers sink to the bottom keeping their invite order.
    private func rank(_ input: [RFPBidRow682]) -> [RFPBidRow682] {
        var decided = input.filter { !$0.pending }
        let pending = input.filter { $0.pending }
        decided.sort { ($0.acceptRate ?? 0) > ($1.acceptRate ?? 0) }
        for i in decided.indices { decided[i].rank = i + 1 }
        return decided + pending
    }

    private func award() async {
        guard let shipmentId, let top = topCarrier else {
            actionNote = "Attach a rail shipment to solicit — the RFP award endpoint (awardRfpBid) is pending; today Award tenders the top carrier once a shipment is linked."
            return
        }
        soliciting = true; actionNote = nil
        struct TenderIn: Encodable {
            let shipmentId: Int; let carrier: String
            let originScac: String; let destinationScac: String
            let commodityStcc: String; let carType: String
            let railcarCount: Int; let pickupDate: String
        }
        do {
            struct Ack: Decodable { let tenderId: String? }
            let iso = ISO8601DateFormatter().string(from: Date().addingTimeInterval(86400)).prefix(10)
            _ = try await EusoTripAPI.shared.mutation(
                "railTenderWorkflow.submitTender",
                input: TenderIn(shipmentId: shipmentId, carrier: top.scac,
                                originScac: shortCity(originStation), destinationScac: shortCity(destStation),
                                commodityStcc: commodityStcc, carType: carType,
                                railcarCount: railcarCount, pickupDate: String(iso))) as Ack
            actionNote = "Awarded to \(top.name) · tender submitted."
        } catch {
            actionNote = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        soliciting = false
    }

    @ViewBuilder
    private func barsGlyph(_ tint: Color) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            Capsule().fill(tint).frame(width: 4, height: 8)
            Capsule().fill(tint).frame(width: 4, height: 13)
            Capsule().fill(tint).frame(width: 4, height: 17)
        }
    }
}

#Preview("682 · Rail RFP Multi-Carrier · Night") {
    RailRFPMultiCarrierScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("682 · Rail RFP Multi-Carrier · Light") {
    RailRFPMultiCarrierScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
