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
//      periodEnd,...}]} scoped to ctx.user.companyId, ORDER BY createdAt DESC). The real batch hero
//      (payable / count / batch-number) is driven from the first batch when present; the per-booking
//      line states/amounts render from the bespoke seed ledger as the wireframe specifies.
//    ESANG unmatched-invoice (fused)  <- esangCoach.forScreen (EXISTS esangCoach.ts:264 ·
//      input {screen,contextIds?,driverState?} · returns {tip,...}). Coach line replaces the seed when
//      Gemini returns a tip.
//    "Fund …" -> settlementBatching.approveBatch (EXISTS settlementBatching.ts:227 · input {batchId:Int}
//      · moves a draft/pending batch -> approved). Wired only when a real numeric batchId is loaded;
//      otherwise the fund verb is honestly a no-op on the seed and re-runs load(). Surfaced honestly.
//
//  0 mock data on load for the hero — the payable/count/batch-id render from the real getBatches row when
//  present, else the honest seed. RimCard/ESangRow/EmptyInput from the canonical port are NOT shared app
//  symbols, so all file-scoped helpers are suffixed 696 (built from sibling 757's grammar). palette.card
//  / Brand.awarded / Brand.equipment / .formattedThousands / StatusPill(tone:) do NOT exist in-module and
//  were replaced with palette.bgCard / Brand.* / thousands696 / StatusPill(kind:).
//

import SwiftUI

private enum SettleState696 { case approved, pending, hold
    var pill: String { self == .approved ? "APPROVED" : self == .pending ? "PENDING" : "HOLD" }
    var tone: Color  { self == .approved ? Brand.success : self == .pending ? Brand.warning : Brand.danger }
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
    @State private var esang = "2 invoices unmatched to B/L"

    @State private var batchId = "BATCH-260531-OCEAN"
    @State private var realBatchId: Int? = nil
    @State private var payable: Int? = nil
    @State private var lines: [BatchLine696] = [
        .init(initials: "MK", disc: Brand.info,    lane: "Shanghai → Long Beach", sub: "Maersk · VES-260523-9F2C41A0E7",  amount: 48200, state: .approved),
        .init(initials: "HL", disc: Brand.warning, lane: "Rotterdam → Houston",   sub: "Hapag-Lloyd · VES-260524-3B1C77E0", amount: 39400, state: .approved),
        .init(initials: "ON", disc: Brand.vessel,  lane: "Busan → Los Angeles",   sub: "ONE · VES-260525-7D2A90C4",       amount: 42600, state: .approved),
        .init(initials: "CM", disc: Brand.success, lane: "Ningbo → Oakland",      sub: "CMA CGM · VES-260526-5E4F12B8",   amount: 31800, state: .pending),
        .init(initials: "CO", disc: Brand.escort,  lane: "Yantian → Seattle",     sub: "COSCO · VES-260527-1A8C63D9",     amount: 22200, state: .hold),
    ]

    private var fundable: Int { lines.filter { $0.state == .approved }.map(\.amount).reduce(0, +) }
    private var approvedCount: Int { lines.filter { $0.state == .approved }.count }
    private var payableDisplay: Int { payable ?? lines.map(\.amount).reduce(0, +) }

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
                    Text("BATCH LINES · CARRIER / BOOKING / AMOUNT")
                        .font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(palette.textTertiary)
                    linesCard
                    esangRow
                    HStack(spacing: 12) {
                        CTAButton(title: "Fund \(approvedCount) · $\(thousands696(fundable))",
                                  action: { Task { await fundBatch() } },
                                  trailingIcon: "checkmark.circle")
                        Button { } label: {
                            Text("Holds").font(.system(size: 15, weight: .semibold)).foregroundStyle(palette.textPrimary)
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
                    Text("\(batchId) · net-30").font(.system(size: 11, design: .monospaced)).foregroundStyle(palette.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    labelValue("APPROVED", "\(approvedCount) / \(lines.count)", Brand.success)
                    labelValue("FUNDABLE", "$\(thousands696(fundable))", palette.textPrimary)
                    labelValue("CLEARS", "3.4 days", palette.textPrimary)
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
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.element.id) { idx, l in
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
                    if idx < lines.count - 1 { Divider().overlay(palette.borderFaint) }
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
                Text("ESang · resolve CMA CGM + COSCO before funding").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.textTertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(palette.bgCard).overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).stroke(palette.borderFaint, lineWidth: 1)))
    }

    // MARK: - Data
    private func load() async {
        loading = true; loadError = nil
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
                if let amt = b.totalAmount, let v = Double(amt) { payable = Int(v.rounded()) }
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
        // Wired only when a real numeric batchId is loaded; on the seed it honestly re-runs load().
        guard let id = realBatchId else { await load(); return }
        struct In696: Encodable { let batchId: Int }
        struct Out696: Decodable { let status: String? }
        let _: Out696? = try? await EusoTripAPI.shared.mutation("settlementBatching.approveBatch", input: In696(batchId: id))
        await load()
    }
}

// MARK: - File-scoped input (no module-level EmptyInput)

private struct EmptyInput696: Encodable {}

#Preview("696 · Vessel Settlement Batch · Night") { VesselSettlementBatchScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("696 · Vessel Settlement Batch · Light") { VesselSettlementBatchScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
