//
//  696_VesselSettlementBatch.swift
//  EusoTrip — Vessel Operator · Settlement Batch.
//
//  Faithful 1:1 port of "696 Vessel Settlement Batch.svg" (Light + Dark) — batch-settlement BOARD
//  archetype: ocean bookings grouped into one net-30 run with per-booking approve/pending/hold state,
//  a fundable subtotal hero, a fused ESang unmatched-invoice check, and a single fund action. Carrier
//  identity is an initials disc (flagship rule), not a glyph. Distinct from the 674 cost ledger.
//  Nav anchored to the registered vessel sibling wrapper (757/664/680): Shell + BottomNav
//  HOME · SHIPMENTS · [orb] · COMPLIANCE[inked — settlement/compliance domain] · ME.
//
//  Data / wiring (endpoint MCP-confirmed via EUSOTRIP_PLATFORM this fire):
//    settlement batch ledger   <- settlementBatching.getBatches (EXISTS settlementBatching.ts:175 ·
//      input {status?,batchType?,dateFrom?,dateTo?}? · returns {batches:[{batchNumber,batchType,status,
//      totalLoads,subtotalAmount,fscAmount,accessorialAmount,deductionAmount,totalAmount,periodStart,
//      periodEnd,...}]} scoped to ctx.user.companyId, ORDER BY createdAt DESC).
//    settlement batch detail   <- settlementBatching.getBatchDetail (EXISTS settlementBatching.ts:199 ·
//      input {batchId:Int} · returns {batch,items}). Hero + lines render from these real rows only.
//    ESANG unmatched-invoice (fused)  <- esangCoach.forScreen (EXISTS esangCoach.ts:264 ·
//      input {screen,contextIds?,driverState?} · returns {tip,...}). Coach line replaces the seed when
//      Gemini returns a tip.
//    "Approve batch" -> settlementBatching.approveBatch (EXISTS settlementBatching.ts:227 · input
//      {batchId:Int} · moves a draft/pending batch -> approved). Wired only when a real numeric batchId
//      is loaded; missing/invalid batches are surfaced directly.
//
//  0 mock data on load. If the settlement batch table has no rows, the screen renders an honest empty
//  state instead of carrier/amount seeds. RimCard/ESangRow/EmptyInput from the canonical port are NOT shared app
//  symbols, so all file-scoped helpers are suffixed 696 (built from sibling 757's grammar). palette.card
//  / Brand.awarded / Brand.equipment / .formattedThousands / StatusPill(tone:) do NOT exist in-module and
//  were replaced with palette.bgCard / Brand.* / thousands696 / StatusPill(kind:).
//

import SwiftUI

private enum SettleState696 { case approved, pending, hold
    var pill: String { self == .approved ? "APPROVED" : self == .pending ? "PENDING" : "HOLD" }
    var tone: Color  { self == .approved ? Brand.success : self == .pending ? Brand.warning : Brand.danger }

    static func fromBatchStatus(_ status: String?) -> SettleState696 {
        switch status?.lowercased() {
        case "approved", "processing", "paid":
            return .approved
        case "failed", "disputed":
            return .hold
        default:
            return .pending
        }
    }
}

private struct BatchLine696: Identifiable {
    let id = UUID(); let initials: String; let disc: Color; let lane: String; let sub: String
    let amount: Int; let state: SettleState696
}

/// Grouped thousands formatter — the canonical port's `Int.formattedThousands` is
/// not a shared app symbol, so we render the same "184,200" grouping file-scoped.
private func thousands696(_ n: Int) -> String {
    let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
    return f.string(from: NSNumber(value: n)) ?? "\(n)"
}

struct VesselSettlementBatchScreen: View {
    let theme: Theme.Palette
    init(theme: Theme.Palette) { self.theme = theme }
    var body: some View {
        Shell(theme: theme) {
            VesselSettlementBatchBody696()
        } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",      systemImage: "house",                   isCurrent: false),
                          NavSlot(label: "Shipments", systemImage: "shippingbox",             isCurrent: false)],
                trailing: [NavSlot(label: "Compliance", systemImage: "checkmark.shield.fill", isCurrent: true),
                           NavSlot(label: "Me",          systemImage: "person",               isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct VesselSettlementBatchBody696: View {
    @Environment(\.palette) private var palette
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionMessage: String? = nil
    @State private var actionError: String? = nil
    @State private var funding = false
    @State private var showOnlyHolds = false
    @State private var esang = "ESANG invoice review pending"
    @State private var esangSubline = "ESANG · open a real batch to evaluate invoice matches"

    @State private var batchId = "No settlement batch"
    @State private var realBatchId: Int? = nil
    @State private var payable: Int? = nil
    @State private var batchStatus: String? = nil
    @State private var totalLoads: Int? = nil
    @State private var lines: [BatchLine696] = []

    private var fundable: Int { lines.filter { $0.state == .approved }.map(\.amount).reduce(0, +) }
    private var approvedCount: Int { lines.filter { $0.state == .approved }.count }
    private var payableDisplay: Int { payable ?? lines.map(\.amount).reduce(0, +) }
    private var visibleLines: [BatchLine696] { showOnlyHolds ? lines.filter { $0.state == .hold } : lines }
    private var batchCanApprove: Bool {
        guard realBatchId != nil else { return false }
        return batchStatus == nil || batchStatus == "draft" || batchStatus == "pending_approval"
    }
    private var approveTitle: String {
        if funding { return "Approving..." }
        if realBatchId == nil { return "No batch to approve" }
        if batchCanApprove { return "Approve batch" }
        return "Batch \(batchStatusLabel)"
    }
    private var batchStatusLabel: String {
        guard let s = batchStatus, !s.isEmpty else { return "pending" }
        return s.replacingOccurrences(of: "_", with: " ")
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                IridescentHairline()
                if loading {
                    LifecycleCard { Text("Building batch…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = loadError {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else {
                    heroCard
                    Text(showOnlyHolds ? "BATCH LINES · HOLDS" : "BATCH LINES · LOAD / SETTLEMENT / AMOUNT")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    linesCard
                    esangRow
                    actionFeedback
                    HStack(spacing: 12) {
                        CTAButton(title: approveTitle,
                                  action: { Task { await fundBatch() } },
                                  trailingIcon: "checkmark.circle")
                        Button { toggleHolds() } label: {
                            Text(showOnlyHolds ? "All lines" : "Holds").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
                                .frame(maxWidth: 126, minHeight: 52)
                                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard)
                                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).stroke(palette.borderFaint, lineWidth: 1)))
                        }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("VESSEL OPERATOR · SETTLEMENT BATCH").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
                Spacer()
                Text("NET-30").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Settlement batch").font(.system(size: 28, weight: .bold)).foregroundStyle(palette.textPrimary)
                Spacer()
                StatusPill(text: "\(lines.count) Bookings", kind: .info)
            }
        }
    }

    private var heroCard: some View {
        LifecycleCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("BATCH PAYABLE").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    Text("$\(thousands696(payableDisplay))").font(.system(size: 36, weight: .bold)).foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                    Text("\(batchId) · \(batchStatusLabel)").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    labelValue("APPROVED", "\(approvedCount) / \(totalLoads ?? lines.count)", Brand.success)
                    labelValue("PAYABLE", "$\(thousands696(payableDisplay))", palette.textPrimary)
                    labelValue("STATUS", batchStatusLabel.uppercased(), palette.textPrimary)
                }.padding(.top, 4)
            }
        }
    }

    private func labelValue(_ label: String, _ value: String, _ valueColor: Color) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 13, weight: .bold)).foregroundStyle(valueColor).monospacedDigit()
        }
    }

    private var linesCard: some View {
        LifecycleCard {
            if visibleLines.isEmpty {
                Text(showOnlyHolds ? "No held lines in this settlement batch." : "No settlement lines returned for this batch.")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visibleLines.enumerated()), id: \.element.id) { idx, l in
                        HStack(alignment: .top, spacing: 12) {
                            Text(l.initials).font(.system(size: 13, weight: .heavy)).foregroundStyle(.white)
                                .frame(width: 40, height: 40).background(Circle().fill(l.disc))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(l.lane).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary)
                                Text(l.sub).font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textSecondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(l.state.pill).font(.system(size: 11, weight: .heavy)).tracking(0.4).foregroundStyle(l.state.tone)
                                Text("$\(thousands696(l.amount))").font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).monospacedDigit()
                            }
                        }
                        .padding(.vertical, 11)
                        if idx < visibleLines.count - 1 { Divider().overlay(palette.borderFaint) }
                    }
                }
            }
        }
    }

    private var esangRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient.diagonal).frame(width: 28, height: 28)
                Circle().fill(RadialGradient(colors: [.white.opacity(0.75), .clear], center: .topLeading, startRadius: 0, endRadius: 14)).frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(esang).font(.system(size: 12.5, weight: .bold)).foregroundStyle(palette.textPrimary)
                Text(esangSubline).font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard).overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(palette.borderFaint, lineWidth: 1)))
    }

    @ViewBuilder private var actionFeedback: some View {
        if let actionError {
            LifecycleCard(accentDanger: true) {
                Text(actionError).font(EType.caption).foregroundStyle(Brand.danger)
            }
        } else if let actionMessage {
            LifecycleCard {
                Text(actionMessage).font(EType.caption).foregroundStyle(Brand.success)
            }
        }
    }

    // MARK: - Data
    private func load() async {
        loading = true; loadError = nil; actionError = nil; actionMessage = nil; lines = []
        do {
            struct Batch: Decodable {
                let id: Int?
                let batchNumber: String?
                let status: String?
                let totalLoads: Int?
                let totalAmount: String?
            }
            struct Resp: Decodable { let batches: [Batch]? }
            let r: Resp = try await EusoTripAPI.shared.query("settlementBatching.getBatches", input: EmptyInput696())
            if let b = r.batches?.first {
                if let n = b.batchNumber, !n.isEmpty { batchId = n }
                if let id = b.id { realBatchId = id }
                batchStatus = b.status
                totalLoads = b.totalLoads
                if let amt = b.totalAmount, let v = Double(amt) { payable = Int(v.rounded()) }
                if let id = b.id {
                    try await loadBatchDetail(batchId: id, status: b.status)
                }
                esangSubline = "ESANG · live invoice checks are scoped to \(batchId)"
            } else {
                batchId = "No settlement batch"
                realBatchId = nil
                payable = nil
                batchStatus = nil
                totalLoads = nil
                lines = []
                esangSubline = "ESANG · open a real batch to evaluate invoice matches"
            }
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }

        // Fused ESang unmatched-invoice coach (best-effort — never blocks the ledger).
        struct CoachIn696: Encodable { let screen: String }
        struct CoachOut696: Decodable { let tip: String? }
        if let coach: CoachOut696 = try? await EusoTripAPI.shared.query("esangCoach.forScreen", input: CoachIn696(screen: "me")),
           let l = coach.tip, !l.isEmpty { esang = l }
        loading = false
    }

    private func fundBatch() async {
        // Real mutation: settlementBatching.approveBatch {batchId:Int} (moves draft/pending -> approved).
        guard let id = realBatchId else {
            actionMessage = nil
            actionError = "There is no settlement batch to approve for this company yet."
            return
        }
        guard batchCanApprove else {
            actionMessage = nil
            actionError = "Batch \(batchId) is \(batchStatusLabel); only draft or pending approval batches can be approved here."
            return
        }
        funding = true
        actionError = nil
        actionMessage = nil
        defer { funding = false }
        struct In696: Encodable { let batchId: Int }
        struct Out696: Decodable { let batchId: Int?; let status: String?; let approvedAt: String? }
        do {
            let out: Out696 = try await EusoTripAPI.shared.mutation("settlementBatching.approveBatch", input: In696(batchId: id))
            let success = "Batch \(out.batchId ?? id) approved\(out.approvedAt.map { " at \($0)" } ?? "")."
            await load()
            actionMessage = success
        } catch {
            actionError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func loadBatchDetail(batchId: Int, status: String?) async throws {
        struct In696: Encodable { let batchId: Int }
        struct Item: Decodable {
            let id: Int?
            let settlementId: Int?
            let loadId: Int?
            let loadNumber: String?
            let pickupDate: String?
            let deliveryDate: String?
            let lineAmount: String?
            let netAmount: String?
        }
        struct Detail: Decodable { let items: [Item]? }

        let detail: Detail = try await EusoTripAPI.shared.query("settlementBatching.getBatchDetail", input: In696(batchId: batchId))
        let state = SettleState696.fromBatchStatus(status)
        lines = (detail.items ?? []).map { item in
            let ref = cleanRef696(item.loadNumber) ?? item.loadId.map { "Load #\($0)" } ?? "Settlement line"
            let settlement = item.settlementId.map { "Settlement #\($0)" } ?? "Settlement pending"
            let dates = compactDateRange696(item.pickupDate, item.deliveryDate)
            let sub = dates.isEmpty ? settlement : "\(settlement) · \(dates)"
            let amount = moneyToInt696(item.netAmount) ?? moneyToInt696(item.lineAmount) ?? 0
            return BatchLine696(
                initials: initials696(ref),
                disc: state.tone,
                lane: ref,
                sub: sub,
                amount: amount,
                state: state
            )
        }
    }

    private func toggleHolds() {
        if showOnlyHolds {
            showOnlyHolds = false
            actionMessage = nil
            actionError = nil
        } else if lines.contains(where: { $0.state == .hold }) {
            showOnlyHolds = true
            actionMessage = nil
            actionError = nil
        } else {
            actionMessage = nil
            actionError = "No held settlement lines are present in this batch."
        }
    }
}

// MARK: - File-scoped input (no module-level EmptyInput)

private struct EmptyInput696: Encodable {}

private func moneyToInt696(_ value: String?) -> Int? {
    guard let value else { return nil }
    let cleaned = value.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")
    guard let amount = Double(cleaned) else { return nil }
    return Int(amount.rounded())
}

private func cleanRef696(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
    return value
}

private func initials696(_ value: String) -> String {
    let letters = value.filter { $0.isLetter || $0.isNumber }
    let prefix = String(letters.prefix(2)).uppercased()
    return prefix.isEmpty ? "SB" : prefix
}

private func compactDateRange696(_ pickup: String?, _ delivery: String?) -> String {
    let p = pickup?.prefix(10)
    let d = delivery?.prefix(10)
    switch (p, d) {
    case let (p?, d?):
        return "\(p) -> \(d)"
    case let (p?, nil):
        return "Pickup \(p)"
    case let (nil, d?):
        return "Delivery \(d)"
    default:
        return ""
    }
}

#Preview("696 · Vessel Settlement Batch · Night") { VesselSettlementBatchScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("696 · Vessel Settlement Batch · Light") { VesselSettlementBatchScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
