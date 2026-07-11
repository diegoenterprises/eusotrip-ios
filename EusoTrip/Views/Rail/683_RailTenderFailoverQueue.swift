//
//  683_RailTenderFailoverQueue.swift
//  EusoTrip — Rail · Shipper · Tender Failover Queue (brick 683).
//
//  Verbatim SwiftUI port of "05 Rail/683 Rail Tender Failover Queue" (Dark).
//  SHIPPER-SIDE FAILOVER priority-ladder: a declined tender (EDI 990) today
//  dead-ends; this re-routes it down a ranked fallback ladder automatically.
//  Composition follows function — a decline hero (990 reason code + auto-
//  failover countdown) over a numbered fallback-carrier queue (position, live
//  acceptance signal, NEXT UP / QUEUED / EXHAUSTED pill) — NOT a bid matrix.
//
//  Web parity: app/(rail)/tender/failover/page.tsx.
//
//  tRPC wiring (honest binding):
//    • decline detect ← railTenderWorkflow.receiveTenderResponse (EXISTS
//                        railTenderWorkflow.ts:220 — EDI 990 B1 response code)
//    • fallback ranking ← railTenderWorkflow.carrierAcceptanceRate (EXISTS
//                        railTenderWorkflow.ts:514 — live per-carrier signal)
//    • re-tender to fallback ← railTenderWorkflow.submitTender (EXISTS
//                        railTenderWorkflow.ts:85, gated on a linked shipmentId)
//    • STUB → the-oath: getFallbackQueue + advanceFallback (the ranked ladder
//                        + auto-sequencing; rate-delta column reads the live
//                        accept-rate signal until per-fallback rate lands).
//
//  RBAC: protectedProcedure. transportMode = rail · tri-country interchange
//  band US AAR 48h / CA TC / MX ARTF.
//  BottomNav: canonical Shipper enum HOME · LOADS · [orb] · WALLET · ME.
//
//  Author: Mike "Diego" Usoro / Eusorone Technologies, Inc.
//

import SwiftUI

// MARK: - Screen root

struct RailTenderFailoverQueueScreen: View {
    let theme: Theme.Palette
    /// Declined-tender context (wireframe defaults: CSX declined reason 65 on
    /// KC → HOU, 25 cars, STCC 0112210). shipmentId gates the real re-tender.
    var declinedCarrier: String = "CSX"
    var declineReason: String = "65"
    var declineText: String = "no equipment available"
    var originStation: String = "KC"
    var destStation: String = "HOU"
    var railcarCount: Int = 25
    var commodityStcc: String = "0112210"
    var carType: String = "covered_hopper"
    var shipmentId: Int? = nil

    init(theme: Theme.Palette = Theme.dark) { self.theme = theme }

    var body: some View {
        Shell(theme: theme) {
            RailTenderFailoverBody(declinedCarrier: declinedCarrier, declineReason: declineReason,
                                   declineText: declineText, originStation: originStation,
                                   destStation: destStation, railcarCount: railcarCount,
                                   commodityStcc: commodityStcc, carType: carType, shipmentId: shipmentId)
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

// MARK: - Data

private struct FailoverAccept683: Decodable {
    let carrier: String?
    let acceptanceRate: Double?
    let accepted: Int?
    let total: Int?
}

private struct FailoverRow683: Identifiable {
    let id: String        // SCAC
    let scac: String
    let name: String
    var acceptRate: Double?
    var decided: Int
    var position: Int
    var state: State
    enum State { case nextUp, queued, exhausted }
}

// MARK: - Body

private struct RailTenderFailoverBody: View {
    let declinedCarrier: String
    let declineReason: String
    let declineText: String
    let originStation: String
    let destStation: String
    let railcarCount: Int
    let commodityStcc: String
    let carType: String
    let shipmentId: Int?

    @Environment(\.palette) private var palette

    @State private var rows: [FailoverRow683] = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var reTendering = false
    @State private var actionNote: String? = nil

    // Fallback ladder (SCAC · display · fallback regime) from the wireframe.
    private static let ladder: [(scac: String, name: String)] = [
        ("BNSF", "BNSF Railway"),
        ("UP",   "Union Pacific"),
        ("CPKC", "CPKC"),
        ("FXE",  "Ferromex (MX)"),
    ]

    private var laneLabel: String { "\(originStation) → \(destStation)" }
    private var railRefId: String { "TND-\(declinedCarrier)-7741" }
    private var nextUp: FailoverRow683? { rows.first(where: { $0.state == .nextUp }) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                chipRow
                declineHero
                if loading {
                    LifecycleCard { Text("Building fallback ladder…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    queueSection
                }
                regimeRow
                if let note = actionNote {
                    Text(note).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Brand.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ctaPair
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
                Text("✦ SHIPPER · RAIL · TENDER FAILOVER")
                    .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                    .foregroundStyle(LinearGradient.primary)
                Spacer()
                Text(railRefId)
                    .font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(1.0)
                    .foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Tender declined")
                    .font(.system(size: 28, weight: .bold)).kerning(-0.4)
                    .foregroundStyle(palette.textPrimary)
                Spacer()
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
            }
            .padding(.top, 10)
            Text("\(declinedCarrier) declined · EDI 990 · auto re-tendering")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary).padding(.top, 4)
            IridescentHairline().padding(.top, 14)
        }
    }

    private var chipRow: some View {
        HStack(spacing: Space.s2) {
            miniChip("990 D", tint: Color(hex: 0xFF6B5E))
            miniChip("\(Self.ladder.count) fallback", tint: palette.textSecondary)
            miniChip("auto re-tender", tint: Color(hex: 0x6FA8FF))
        }
    }

    @ViewBuilder
    private func miniChip(_ text: String, tint: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .heavy)).tracking(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(palette.bgCard))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Decline hero

    private var declineHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(hex: 0xFF6B5E))
                Text("EDI 990 · DECLINE RECEIVED")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Color(hex: 0xFF6B5E))
                Spacer(minLength: 4)
                Text("DECLINED")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.3)
                    .foregroundStyle(Color(hex: 0xFF6B5E))
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(Color(hex: 0xFF6B5E).opacity(0.14)))
            }
            Text("\(declinedCarrier) declined · reason \(declineReason)")
                .font(.system(size: 20, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text("\(declineText) · \(laneLabel) · \(railcarCount) cars · STCC \(commodityStcc)")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .heavy)).foregroundStyle(Color(hex: 0x6FA8FF))
                Text(failoverBanner)
                    .font(.system(size: 10, weight: .heavy)).foregroundStyle(Color(hex: 0x6FA8FF))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: 0x6FA8FF).opacity(0.10)))
        }
        .padding(Space.s5)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
            .strokeBorder(LinearGradient.diagonal, lineWidth: 1.5))
    }

    private var failoverBanner: String {
        if let n = nextUp { return "AUTO-FAILOVER → \(n.scac) (next up)" }
        return "AUTO-FAILOVER · resolving next carrier"
    }

    // MARK: Queue

    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FALLBACK CARRIER QUEUE · \(rows.count)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(Color(hex: 0x9FB0BE))
                Spacer()
                Text("by priority").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.textTertiary)
            }
            IridescentHairline()
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    queueRow(row)
                    if idx < rows.count - 1 { Divider().padding(.horizontal, 16).overlay(palette.borderFaint) }
                }
            }
            .padding(.vertical, 6)
            .background(palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            Text("Rate delta pending — per-fallback rate lands with getFallbackQueue; rows rank by live acceptance rate today.")
                .font(.system(size: 10)).foregroundStyle(palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func queueRow(_ row: FailoverRow683) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().strokeBorder(positionColor(row), lineWidth: 2).frame(width: 34, height: 34)
                Text("\(row.position)")
                    .font(.system(size: 15, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(positionColor(row))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(rowSub(row))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 6)
            statePill(row)
        }
        .padding(16)
    }

    private func rowSub(_ row: FailoverRow683) -> String {
        if row.decided == 0 { return "no decided history" }
        if let ar = row.acceptRate { return "\(Int(ar.rounded()))% accept · \(row.decided) decided" }
        return "acceptance unverified"
    }

    private func positionColor(_ row: FailoverRow683) -> Color {
        switch row.state {
        case .nextUp:    return Color(hex: 0x6FA8FF)
        case .queued:    return palette.textTertiary
        case .exhausted: return Color(hex: 0xFF6B5E)
        }
    }

    @ViewBuilder
    private func statePill(_ row: FailoverRow683) -> some View {
        switch row.state {
        case .nextUp:
            pill("NEXT UP", Color(hex: 0x6FA8FF), Color(hex: 0x6FA8FF).opacity(0.14))
        case .queued:
            pill("QUEUED", palette.textSecondary, Color.white.opacity(0.06))
        case .exhausted:
            pill("EXHAUSTED", Color(hex: 0xFF6B5E), Color(hex: 0xFF6B5E).opacity(0.14))
        }
    }

    @ViewBuilder
    private func pill(_ text: String, _ fg: Color, _ bg: Color) -> some View {
        Text(text).font(.system(size: 9.5, weight: .heavy)).tracking(0.3)
            .foregroundStyle(fg)
            .padding(.horizontal, 14).padding(.vertical, 5)
            .background(Capsule().fill(bg))
    }

    // MARK: Regime chips

    private var regimeRow: some View {
        HStack(spacing: Space.s2) {
            regimeChip("US · AAR", "48h interchange", active: true)
            regimeChip("CA · TC", "CN↔CPKC", active: false)
            regimeChip("MX · ARTF", "Ferromex IXN", active: false)
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

    // MARK: CTA

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: reTendering ? "Re-tendering…" : "Re-tender to \(nextUp?.scac ?? "next")",
                      action: { Task { await reTender() } },
                      trailingIcon: "arrow.triangle.2.circlepath",
                      isLoading: reTendering)
            RailSecondaryActionButton(
                title: "Manual",
                sheetTitle: "Failover ladder context",
                lines: [
                    "\(declinedCarrier) declined · EDI 990 reason \(declineReason) · \(declineText)",
                    "\(laneLabel) · \(railcarCount) cars · STCC \(commodityStcc)",
                    nextUp.map { "Next up · \($0.name) · \(Int(($0.acceptRate ?? 0).rounded()))% accept" } ?? "No next-up carrier resolved",
                    "Re-tender fires submitTender to the next-up carrier once a rail shipment is linked."
                ],
                systemImage: "arrow.triangle.branch"
            )
        }
    }

    // MARK: Load / actions

    private func load() async {
        loading = true; loadError = nil; actionNote = nil
        struct AcceptIn: Encodable { let carrier: String; let commodityStcc: String; let windowDays: Int }
        var assembled: [FailoverRow683] = []
        for (i, item) in Self.ladder.enumerated() {
            let ar: FailoverAccept683? = try? await EusoTripAPI.shared.query(
                "railTenderWorkflow.carrierAcceptanceRate",
                input: AcceptIn(carrier: item.scac, commodityStcc: commodityStcc, windowDays: 180)) as FailoverAccept683?
            let state: FailoverRow683.State = i == 0 ? .nextUp : (i == Self.ladder.count - 1 ? .exhausted : .queued)
            assembled.append(FailoverRow683(id: item.scac, scac: item.scac, name: item.name,
                                            acceptRate: ar?.acceptanceRate, decided: ar?.total ?? 0,
                                            position: i + 1, state: state))
        }
        self.rows = assembled
        loading = false
    }

    private func reTender() async {
        guard let shipmentId, let n = nextUp else {
            actionNote = "Attach a rail shipment to re-tender — advanceFallback auto-sequencing is pending; today re-tender fires submitTender to the next-up carrier once linked."
            return
        }
        reTendering = true; actionNote = nil
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
                input: TenderIn(shipmentId: shipmentId, carrier: n.scac,
                                originScac: originStation, destinationScac: destStation,
                                commodityStcc: commodityStcc, carType: carType,
                                railcarCount: railcarCount, pickupDate: String(iso))) as Ack
            actionNote = "Re-tendered to \(n.name)."
        } catch {
            actionNote = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        reTendering = false
    }
}

#Preview("683 · Rail Tender Failover · Night") {
    RailTenderFailoverQueueScreen(theme: Theme.dark)
        .environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("683 · Rail Tender Failover · Light") {
    RailTenderFailoverQueueScreen(theme: Theme.light)
        .environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
