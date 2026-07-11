//
//  698_RailInterlineSettlementReconciliation.swift
//  EusoTrip — Rail Engineer · Interline Settlement Reconciliation.
//
//  Bespoke port of "05 Rail/Dark-SVG/698 Rail Interline Settlement
//  Reconciliation.svg".
//  ARCHETYPE = REVENUE-DIVISION + NET-BALANCE board — a total-revenue hero,
//  the real charge composition, a per-road ISS division section, a net-balance
//  verdict band, and a reconciliation-activity feed. Deliberately a division
//  board, NOT 696's customer-detention ledger and NOT a detail card.
//
//  Role: RAIL_ENGINEER (carrier/compliance). transportMode=rail.
//
//  WIRING MANIFEST (verified against frontend/server/routers/railShipments.ts +
//  railFreightAudit.ts):
//    railShipments.getRailSettlement  EXISTS railShipments.ts:1465 {shipmentId}
//        → {shipmentNumber,status,linehaul,demurrage,total,currency}. Tenant-
//        gated. This is the REAL gross under division + its charge composition.
//    railFreightAudit.recentAudits  EXISTS railFreightAudit.ts:103 {limit} →
//        {audits[],total,note}. The reconciliation-activity feed (honestly empty
//        until invoice storage lands — never a fabricated audit row).
//    railFreightAudit.fileRecovery  EXISTS railFreightAudit.ts:122 {invoiceId,
//        findingIds[]} → {disputeId}. "Open exception" files a real recovery
//        dispute into the shared disputes vertical.
//  VERIFIED ABSENT (honest state, never fabricated):
//    An interline.getSettlement ISS per-road revenue split (share% · net per
//    road) is not on disk. The per-road division reads "pending road audits" and
//    the split bar sums only what is audited — never a guessed 3-road split.
//    settleInterline (a road-to-road money move) is admin/ISS-gated and absent;
//    the settle control surfaces that honestly.
//

import SwiftUI

struct RailInterlineSettlementScreen: View {
    let theme: Theme.Palette
    var shipmentId: Int = 0
    var shipmentNumber: String = ""

    var body: some View {
        Shell(theme: theme) {
            RailInterlineSettlementBody(shipmentId: shipmentId, shipmentNumber: shipmentNumber)
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",       isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox", isCurrent: true)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield", isCurrent: false),
                           NavSlot(label: "Me",          systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

// MARK: - Data shapes

private struct RailSettlement698: Decodable {
    let shipmentNumber: String?
    let status: String?
    let linehaul: Double?
    let demurrage: Double?
    let total: Double?
    let currency: String?
}
private struct SettlementInput698: Encodable { let shipmentId: Int }

private struct RecentAudits698: Decodable {
    struct Audit: Decodable, Identifiable {
        let invoiceNumber: String?
        let auditStatus: String?
        var id: String { invoiceNumber ?? UUID().uuidString }
    }
    let audits: [Audit]?
    let total: Int?
    let note: String?
}
private struct RecentAuditsInput698: Encodable { let limit: Int }

private struct FileRecoveryInput698: Encodable { let invoiceId: String; let findingIds: [String] }
private struct FileRecoveryResult698: Decodable { let disputeId: String?; let status: String? }

// MARK: - Body

private struct RailInterlineSettlementBody: View {
    let shipmentId: Int
    let shipmentNumber: String

    @Environment(\.palette) private var palette
    @State private var settlement: RailSettlement698? = nil
    @State private var audits: RecentAudits698? = nil
    @State private var loading = true
    @State private var filing = false
    @State private var actionMessage: String? = nil
    @State private var actionIsError = false
    @State private var regime = 0
    @State private var showSettleNotice = false

    private let regimes: [(String, String, String)] = [
        ("US · USD", "ISS", "$"),
        ("CA · CAD", "Interline", "$"),
        ("MX · MXN", "ISS-MX", "$"),
    ]
    private var symbol: String { regimes[regime].2 }
    private var currency: String { settlement?.currency ?? regimes[regime].1 }

    private var gross: Double { settlement?.total ?? 0 }
    private var linehaul: Double { settlement?.linehaul ?? 0 }
    private var demurrage: Double { settlement?.demurrage ?? 0 }
    private var auditRows: [RecentAudits698.Audit] { audits?.audits ?? [] }
    private var shipNo: String { settlement?.shipmentNumber ?? (shipmentNumber.isEmpty ? "rail shipment" : shipmentNumber) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("Interline settle")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text("\(shipNo) · run-through division")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4).lineLimit(1)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 64)
                } else {
                    grossHero
                    compositionCard
                    divisionHeader
                    divisionSection
                    netBalanceBand
                    activityHeader
                    activityFeed
                    triBand
                    footerActions
                    if let m = actionMessage {
                        LifecycleCard(accentDanger: actionIsError) {
                            Text(m).font(EType.caption).foregroundStyle(actionIsError ? Brand.danger : Brand.success)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .refreshable { await reload() }
        .alert("Settlement moves money between roads", isPresented: $showSettleNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("An ISS interline settlement is an audited road-to-road money movement, released through the settlement pipeline once every run-through road's audit is in. Open an exception here to contest a share before it settles.")
        }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            Text("✦ CARRIER · RAIL · INTERLINE $")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("ISS SETTLE")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip(money(gross), Brand.blue)
            chip(currency, palette.textSecondary)
            chip(settlement?.status ?? "unsettled", Brand.warning)
        }
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    private func money(_ v: Double) -> String {
        "\(symbol)\(v.formatted(.number.precision(.fractionLength(v < 1000 ? 2 : 0)).grouping(.automatic)))"
    }

    // MARK: Gross hero.

    private var grossHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("INTERLINE REVENUE · DIVISION (ISS)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(Brand.warning)
                Spacer()
                Text((settlement?.status ?? "unsettled").uppercased())
                    .font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(LinearGradient(colors: [Brand.warning.opacity(0.12), Brand.blue.opacity(0.06)], startPoint: .leading, endPoint: .trailing))
            VStack(alignment: .leading, spacing: 4) {
                Text(money(gross)).font(.system(size: 40, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
                Text("Gross revenue to divide across the run-through roads · \(currency)")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.primary, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    // MARK: Real charge composition (linehaul vs demurrage).

    @ViewBuilder
    private var compositionCard: some View {
        let parts: [(String, Double, Color)] = [
            ("Linehaul", linehaul, Brand.blue),
            ("Demurrage", demurrage, Brand.warning),
        ].filter { $0.1 > 0 }
        let sum = parts.reduce(0) { $0 + $1.1 }
        VStack(alignment: .leading, spacing: 12) {
            Text("CHARGE COMPOSITION · WHAT DIVIDES")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            if sum > 0 {
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                            Rectangle().fill(p.2).frame(width: max(3, g.size.width * CGFloat(p.1 / sum)))
                        }
                    }.clipShape(Capsule())
                }.frame(height: 12)
                ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3).fill(p.2).frame(width: 12, height: 12)
                        Text(p.0).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text(money(p.1)).font(.system(size: 12, weight: .heavy)).monospacedDigit().foregroundStyle(palette.textPrimary)
                    }
                }
            } else {
                Text("No settled charge components on this shipment yet.").font(.system(size: 11)).foregroundStyle(palette.textTertiary)
            }
        }
        .padding(16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var divisionHeader: some View {
        HStack {
            Text("DIVISION OF REVENUE · NET BALANCES")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Spacer()
            Text("\(currency) · ISS").font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textTertiary)
        }
    }

    // MARK: Per-road division — honest pending until audits return.

    private var divisionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.bgCardSoft).frame(height: 12)
                    Capsule().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .foregroundStyle(Brand.blue.opacity(0.5)).frame(height: 12)
                }
            }.frame(height: 12)
            HStack(spacing: 10) {
                Image(systemName: "hourglass").font(.system(size: 14, weight: .bold)).foregroundStyle(Brand.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Division pending road audits").font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                    Text("The ISS split computes once each run-through road files its audit. The bar fills only with audited shares — never a guessed split.")
                        .font(.system(size: 10)).foregroundStyle(palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var netBalanceBand: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("NET BALANCE · INTERLINE").font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
                Text("settles to \(currency)").font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Text("PENDING").font(.system(size: 12, weight: .heavy)).foregroundStyle(Brand.warning)
                .padding(.horizontal, 14).frame(height: 30).background(Capsule().fill(Brand.warning.opacity(0.12)))
        }
        .padding(16)
        .background(palette.bgCardSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var activityHeader: some View {
        HStack {
            Text("RECONCILIATION ACTIVITY")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Spacer()
            Text("last 3d").font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textTertiary)
        }
    }

    @ViewBuilder
    private var activityFeed: some View {
        if auditRows.isEmpty {
            EusoEmptyState(systemImage: "doc.text.magnifyingglass",
                           title: "No audits received yet",
                           subtitle: audits?.note ?? "No run-through road has filed a freight-bill audit for this shipment. Division activity posts here as each road's audit returns.")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(auditRows.enumerated()), id: \.element.id) { i, a in
                    HStack(spacing: 10) {
                        Circle().fill(Brand.info).frame(width: 7, height: 7)
                        Text("Audit received · \(a.invoiceNumber ?? "invoice")").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textPrimary)
                        Spacer()
                        Text((a.auditStatus ?? "").uppercased()).font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                    }
                    .padding(.vertical, 12)
                    if i < auditRows.count - 1 { Divider().overlay(palette.borderFaint) }
                }
            }
            .padding(.horizontal, 16)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var triBand: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(regimes[i].0).font(.system(size: 8, weight: .heavy)).tracking(0.3)
                    Text(regimes[i].1).font(.system(size: 9, weight: .heavy))
                }
                .foregroundStyle(i == regime ? Brand.blue : palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(i == regime ? Brand.blue.opacity(0.5) : palette.borderFaint))
                .onTapGesture { regime = i }
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: filing ? "Filing…" : "Open exception", action: { Task { await openException() } })
                .frame(maxWidth: .infinity)
                .disabled(filing)
            Button(action: { showSettleNotice = true }) {
                Text("Settle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 118)
                    .frame(minHeight: 48, maxHeight: 48)
                    .background(palette.bgCardSoft)
                    .overlay(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                                .strokeBorder(palette.borderFaint))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func reload() async {
        loading = true
        let s: RailSettlement698? = try? await EusoTripAPI.shared.query(
            "railShipments.getRailSettlement", input: SettlementInput698(shipmentId: shipmentId))
        self.settlement = s
        let a: RecentAudits698? = try? await EusoTripAPI.shared.query(
            "railFreightAudit.recentAudits", input: RecentAuditsInput698(limit: 20))
        self.audits = a
        loading = false
    }

    private func openException() async {
        filing = true; actionMessage = nil
        do {
            let r: FileRecoveryResult698 = try await EusoTripAPI.shared.mutation(
                "railFreightAudit.fileRecovery",
                input: FileRecoveryInput698(invoiceId: shipNo, findingIds: []))
            actionIsError = false
            actionMessage = "Exception \(r.disputeId ?? "filed") opened in the disputes queue — the interline share is contested until it's worked."
        } catch {
            actionIsError = true
            actionMessage = "The exception didn't file. Nothing changed — check your connection and try again."
        }
        filing = false
    }
}

#Preview("698 · Rail Interline Settlement · Night") {
    RailInterlineSettlementScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("698 · Rail Interline Settlement · Light") {
    RailInterlineSettlementScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
