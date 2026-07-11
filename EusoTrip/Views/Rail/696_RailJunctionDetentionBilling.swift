//
//  696_RailJunctionDetentionBilling.swift
//  EusoTrip — Rail Engineer · Junction Detention Billing.
//
//  Bespoke port of "05 Rail/Dark-SVG/696 Rail Junction Detention Billing.svg".
//  ARCHETYPE = MONEY LEDGER in the 227 Settlement cadence — a big tabular
//  amount hero, an accruing-status band, a stacked breakdown bar with a
//  per-line ledger, a TOTAL band, and dwell-reason chips. Deliberately the
//  settlement-money composition, NOT a detail card.
//
//  Role: RAIL_ENGINEER (carrier/compliance). transportMode=rail.
//
//  WIRING MANIFEST (verified against frontend/server/routers/railDemurrageAuto.ts):
//    railDemurrageAuto.detentionAtJunction  EXISTS:389 {yardId,window} →
//        {totalDue, carCount, byStatus{status:amount}, lines[{demurrageId,
//        railcarNumber,status,chargeableHours,ratePerHour,amount,placedAt}]}.
//        Tenant-scoped to the caller's company. This is the REAL junction
//        detention ledger — hero amount, stacked bar, and per-line rows.
//    railDemurrageAuto.reportByDwellReason  EXISTS:499 {periodDays} → reasons[]
//        — the dwell-cause chips (honest zeros until a dwellReason capture lands;
//        never a fabricated cause).
//    railDemurrageAuto.billDetention  EXISTS:436 {confirm:true, demurrageId} —
//        IRREVERSIBLE money write (accruing → invoiced), tenant-checked, audited
//        (blockchainAuditTrail rail.detention_billed). Human-gated with a
//        confirmation dialog; bills the top accruing line.
//    railDemurrageAuto.createDispute  EXISTS:264 {confirm:true, demurrageId,
//        reason} — files a demurrage_disputes row and drops the charge from the
//        billable rollup. Confirmation-gated.
//  COUNTRY: free-time US/CA 48h · MX 24h · currency USD/CAD/MXN (band below).
//

import SwiftUI

struct RailJunctionDetentionBillingScreen: View {
    let theme: Theme.Palette
    /// The interchange junction (rail yard) whose detention is being billed.
    var yardId: Int = 0

    var body: some View {
        Shell(theme: theme) {
            RailJunctionDetentionBillingBody(yardId: yardId)
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

private struct JunctionLine696: Decodable, Identifiable {
    let demurrageId: Int?
    let railcarNumber: String?
    let status: String?
    let chargeableHours: Double?
    let ratePerHour: Double?
    let amount: Double?
    let placedAt: String?
    let releasedAt: String?
    var id: Int { demurrageId ?? -1 }
}
private struct JunctionDetention696: Decodable {
    let yardId: Int?
    let totalDue: Double?
    let carCount: Int?
    let byStatus: [String: Double]?
    let lines: [JunctionLine696]?
}
private struct JunctionInput696: Encodable { let yardId: Int; let window: String? }

private struct DwellReason696: Decodable, Identifiable {
    let reason: String?
    let count: Int?
    let totalCharges: Double?
    var id: String { reason ?? UUID().uuidString }
}
private struct DwellReport696: Decodable { let reasons: [DwellReason696]? }
private struct DwellInput696: Encodable { let periodDays: Int }

private struct BillInput696: Encodable { let confirm: Bool; let demurrageId: Int }
private struct BillResult696: Decodable { let success: Bool?; let status: String?; let amount: Double? }
private struct DisputeInput696: Encodable { let confirm: Bool; let demurrageId: Int; let reason: String }
private struct DisputeResult696: Decodable { let disputeId: String?; let status: String? }

// MARK: - Body

private struct RailJunctionDetentionBillingBody: View {
    let yardId: Int

    @Environment(\.palette) private var palette
    @State private var detention: JunctionDetention696? = nil
    @State private var reasons: [DwellReason696] = []
    @State private var loading = true
    @State private var billing = false
    @State private var disputing = false
    @State private var actionMessage: String? = nil
    @State private var actionIsError = false
    @State private var regime = 0
    @State private var showBillConfirm = false
    @State private var showDisputeConfirm = false

    private let regimes: [(String, String, String)] = [
        ("US · 48H", "USD", "$"),
        ("CA · 48H", "CAD", "$"),
        ("MX · 24H", "MXN", "$"),
    ]
    private var currency: String { regimes[regime].1 }
    private var symbol: String { regimes[regime].2 }

    private var lines: [JunctionLine696] { (detention?.lines ?? []).sorted { ($0.amount ?? 0) > ($1.amount ?? 0) } }
    private var totalDue: Double { detention?.totalDue ?? 0 }
    private var carCount: Int { detention?.carCount ?? lines.count }
    private var topAccruing: JunctionLine696? { lines.first { $0.status == "accruing" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("Junction detention")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text("Interchange junction · \(carCount) car\(carCount == 1 ? "" : "s")")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 64)
                } else {
                    amountHero
                    breakdownCard
                    ledgerHeader
                    lineLedger
                    dwellReasons
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
        .confirmationDialog("Bill this detention charge?", isPresented: $showBillConfirm, titleVisibility: .visible) {
            Button("Bill \(money(topAccruing?.amount ?? 0))", role: .destructive) { Task { await bill() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This moves the top accruing charge to invoiced — an irreversible money write, audited on the ledger. Only an accruing charge can be billed.")
        }
        .confirmationDialog("Dispute this detention charge?", isPresented: $showDisputeConfirm, titleVisibility: .visible) {
            Button("File dispute", role: .destructive) { Task { await dispute() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Files a dispute on the top charge and drops it from the billable rollup until an admin resolves it.")
        }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            Text("✦ CARRIER · RAIL · DETENTION")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("JUNCTION BILL")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip("\(carCount) car\(carCount == 1 ? "" : "s")", palette.textSecondary)
            chip(currency, Brand.blue)
            chip(totalDue > 0 ? "accruing" : "clear", totalDue > 0 ? Brand.warning : Brand.success)
        }
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    private func money(_ v: Double) -> String {
        "\(symbol)\(v.formatted(.number.precision(.fractionLength(2)).grouping(.automatic)))"
    }

    // MARK: Amount hero.

    private var amountHero: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(totalDue > 0 ? "DETENTION · ACCRUING" : "DETENTION · NOTHING DUE")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(totalDue > 0 ? Brand.warning : Brand.success)
                Spacer()
                Text(currency).font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
            }
            .padding(.horizontal, 16).frame(height: 40)
            .background(LinearGradient(colors: [(totalDue > 0 ? Brand.warning : Brand.success).opacity(0.12), Brand.blue.opacity(0.06)],
                                       startPoint: .leading, endPoint: .trailing))
            VStack(alignment: .leading, spacing: 4) {
                Text(money(totalDue))
                    .font(.system(size: 40, weight: .bold)).monospacedDigit()
                    .foregroundStyle(palette.textPrimary)
                Text(totalDue > 0
                     ? "Junction detention still owed across \(carCount) car\(carCount == 1 ? "" : "s") · awaiting bill"
                     : "No junction detention owed at this interchange right now.")
                    .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        }
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(LinearGradient.primary, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }

    // MARK: Breakdown — real stacked bar by charge STATUS.

    private var statusBuckets: [(label: String, amount: Double, color: Color)] {
        let by = detention?.byStatus ?? [:]
        let order: [(String, String, Color)] = [
            ("accruing", "Accruing", Brand.warning),
            ("invoiced", "Billed", Brand.info),
            ("disputed", "Disputed", Brand.escort),
            ("paid", "Paid", Brand.success),
            ("waived", "Waived", Brand.neutral),
        ]
        return order.compactMap { key, label, color in
            let amt = by[key] ?? 0
            return amt > 0 ? (label, amt, color) : nil
        }
    }

    @ViewBuilder
    private var breakdownCard: some View {
        let buckets = statusBuckets
        let sum = buckets.reduce(0) { $0 + $1.amount }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("BREAKDOWN · BY CHARGE STATUS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.7).foregroundStyle(palette.textTertiary)
                Spacer()
                Text(currency).font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
            }
            if sum > 0 {
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(Array(buckets.enumerated()), id: \.offset) { _, b in
                            Rectangle().fill(b.color)
                                .frame(width: max(3, g.size.width * CGFloat(b.amount / sum)))
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 12)
                VStack(spacing: 8) {
                    ForEach(Array(buckets.enumerated()), id: \.offset) { _, b in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3).fill(b.color).frame(width: 12, height: 12)
                            Text(b.label).font(.system(size: 12, weight: .bold)).foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text("\(Int((b.amount / sum) * 100))%").font(.system(size: 10, design: .monospaced)).foregroundStyle(palette.textTertiary)
                            Text(money(b.amount)).font(.system(size: 12, weight: .heavy)).monospacedDigit().foregroundStyle(palette.textPrimary)
                        }
                    }
                }
            } else {
                Text("No charge components to break down.").font(.system(size: 11)).foregroundStyle(palette.textTertiary)
            }
            Divider().overlay(palette.borderFaint)
            HStack {
                Text("TOTAL · GROSS").font(.system(size: 10, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textSecondary)
                Spacer()
                Text(money(sum)).font(.system(size: 16, weight: .bold)).monospacedDigit().foregroundStyle(palette.textPrimary)
            }
        }
        .padding(16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private var ledgerHeader: some View {
        HStack {
            Text("PER-CAR DETENTION LINES")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Spacer()
            Text("CAR · HOURS · AMOUNT")
                .font(.system(size: 9, weight: .bold)).foregroundStyle(palette.textTertiary)
        }
    }

    @ViewBuilder
    private var lineLedger: some View {
        if lines.isEmpty {
            EusoEmptyState(systemImage: "tram.fill",
                           title: "No detention lines",
                           subtitle: "No car is accruing junction detention at this interchange in the window. Lines appear here the moment a car dwells past its free time.")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.element.id) { i, l in
                    lineRow(l)
                    if i < lines.count - 1 { Divider().overlay(palette.borderFaint) }
                }
            }
            .padding(.horizontal, 16)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func lineRow(_ l: JunctionLine696) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(l.railcarNumber ?? "Car #\(l.demurrageId ?? 0)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                Text("\((l.chargeableHours ?? 0).formatted(.number.precision(.fractionLength(1)))) chargeable hrs · \(symbol)\((l.ratePerHour ?? 0).formatted(.number.precision(.fractionLength(0))))/hr")
                    .font(.system(size: 9)).foregroundStyle(palette.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(money(l.amount ?? 0)).font(.system(size: 13, weight: .heavy)).monospacedDigit().foregroundStyle(palette.textPrimary)
                Text((l.status ?? "accruing").uppercased())
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(statusColor(l.status))
            }
        }
        .padding(.vertical, 12)
    }

    private func statusColor(_ s: String?) -> Color {
        switch s {
        case "accruing": return Brand.warning
        case "invoiced": return Brand.info
        case "disputed": return Brand.escort
        case "paid":     return Brand.success
        case "waived":   return Brand.neutral
        default:         return palette.textTertiary
        }
    }

    // MARK: Dwell-reason chips — real reportByDwellReason (honest zeros).

    @ViewBuilder
    private var dwellReasons: some View {
        let captured = reasons.filter { ($0.count ?? 0) > 0 }
        VStack(alignment: .leading, spacing: 8) {
            Text("DWELL REASON · CAPTURED AT PLACEMENT")
                .font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            if captured.isEmpty {
                Text("No dwell reason captured yet — placement-cause tagging fills these chips as cars are spotted.")
                    .font(.system(size: 10)).foregroundStyle(palette.textTertiary).fixedSize(horizontal: false, vertical: true)
            } else {
                FlowChips696(items: captured.map { "\(readable($0.reason)) · \($0.count ?? 0)" })
            }
        }
    }

    private func readable(_ r: String?) -> String {
        (r ?? "unknown").replacingOccurrences(of: "_", with: " ")
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
            CTAButton(title: billing ? "Billing…" : "Bill detention",
                      action: { if topAccruing != nil { showBillConfirm = true } })
                .frame(maxWidth: .infinity)
                .disabled(billing || topAccruing == nil)
            Button(action: { if topAccruing != nil { showDisputeConfirm = true } }) {
                Text(disputing ? "Filing…" : "Dispute")
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
            .disabled(disputing || topAccruing == nil)
        }
    }

    // MARK: Load + money actions

    private func reload() async {
        loading = true
        let d: JunctionDetention696? = try? await EusoTripAPI.shared.query(
            "railDemurrageAuto.detentionAtJunction", input: JunctionInput696(yardId: yardId, window: "30d"))
        self.detention = d
        let r: DwellReport696? = try? await EusoTripAPI.shared.query(
            "railDemurrageAuto.reportByDwellReason", input: DwellInput696(periodDays: 30))
        self.reasons = r?.reasons ?? []
        loading = false
    }

    private func bill() async {
        guard let l = topAccruing, let id = l.demurrageId else { return }
        billing = true; actionMessage = nil
        do {
            let r: BillResult696 = try await EusoTripAPI.shared.mutation(
                "railDemurrageAuto.billDetention", input: BillInput696(confirm: true, demurrageId: id))
            actionIsError = false
            actionMessage = "Billed \(money(r.amount ?? l.amount ?? 0)) — charge moved to invoiced and recorded on the audit ledger."
            await reload()
        } catch {
            actionIsError = true
            actionMessage = "The bill didn't post. The charge is unchanged — check your connection and try again."
        }
        billing = false
    }

    private func dispute() async {
        guard let l = topAccruing, let id = l.demurrageId else { return }
        disputing = true; actionMessage = nil
        do {
            let r: DisputeResult696 = try await EusoTripAPI.shared.mutation(
                "railDemurrageAuto.createDispute", input: DisputeInput696(confirm: true, demurrageId: id, reason: "other"))
            actionIsError = false
            actionMessage = "Dispute \(r.disputeId ?? "filed") — the charge is held out of the billable rollup until an admin resolves it."
            await reload()
        } catch {
            actionIsError = true
            actionMessage = "The dispute didn't file. The charge is unchanged — check your connection and try again."
        }
        disputing = false
    }
}

// Small wrapping chip row for the dwell reasons.
private struct FlowChips696: View {
    @Environment(\.palette) private var palette
    let items: [String]
    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 110), spacing: 8)]
        LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { t in
                Text(t)
                    .font(.system(size: 10, weight: .heavy)).foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 12).frame(height: 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Capsule().fill(palette.bgCardSoft))
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
            }
        }
    }
}

#Preview("696 · Rail Junction Detention · Night") {
    RailJunctionDetentionBillingScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("696 · Rail Junction Detention · Light") {
    RailJunctionDetentionBillingScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
