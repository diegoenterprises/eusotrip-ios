//
//  787_VesselDetentionBillingBatch.swift
//  EusoTrip — Vessel Operator · Detention Billing Batch (SETTLEMENT-LEDGER archetype).
//
//  Faithful 1:1 port of "787 Vessel Detention Billing Batch.svg" (Light + Dark).
//  The DOWNSTREAM posting surface (distinct from the approve/dispute queue and
//  from 731's category ledger): takes the already-approved demurrage/detention
//  charges and posts them to the load settlement in one run. The operator
//  SELECTS which approved charges fold into the batch (tap to include/exclude),
//  watches the 5-stage billing-posting lifecycle (Approved → Batched → Invoiced
//  → Posted → Cleared, Batched active), and fires one CTA that invoices the
//  selected set into settlement.accessorialTotal. Selectable ledger + one
//  decisive post replaces a per-claim invoicing slog.
//
//  WIRING (server/routers/detentionAccessorials.ts — verified this fire):
//    · getAccessorialBilling {status:'approved',batchSize}? (query,
//        protectedProcedure, companyId-scoped :2310)
//        -> { pendingCharges[{id,loadId,type,amount,status,facilityName,
//             shipperName,carrierName,origin,destination,createdAt}],
//             batchSummary{totalItems,totalAmount,byType,readyToInvoice} }
//    · "Invoice N" -> invoiceDetentionCharge {claimId} (mutation :2387, IDOR-
//        gated ownership) looped over the SELECTED claimIds; each posts to the
//        load's settlement.accessorialTotal + flips the claim to 'invoiced'.
//        (A true one-pass invoiceDetentionBatch({claimIds}) is a proposed
//        server gap — the loop is the honest current path.)
//    · "Select all" -> client-side toggle of the selection set.
//  transportMode=vessel · USD. No mock data.
//

import SwiftUI

private struct BillingCharge787: Decodable, Identifiable {
    let id: Int
    let loadId: Int?
    let type: String?
    let amount: Double?
    let facilityName: String?
    let origin: String?
    let destination: String?
}
private struct BillingSummary787: Decodable {
    let totalItems: Int?
    let totalAmount: Double?
    let readyToInvoice: Int?
}
private struct BillingResponse787: Decodable {
    let pendingCharges: [BillingCharge787]?
    let batchSummary: BillingSummary787?
}
private struct InvoiceResult787: Decodable { let success: Bool?; let invoicedAmount: Double? }

struct VesselDetentionBillingBatchScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { VesselDetentionBillingBatchBody() } nav: { VesselDetnNav(active: .compliance) }
    }
}

private struct VesselDetentionBillingBatchBody: View {
    @Environment(\.palette) private var palette
    @State private var data: BillingResponse787? = nil
    @State private var selected: Set<Int> = []
    @State private var loading = true
    @State private var loadError: String? = nil
    @State private var actionMessage: String? = nil
    @State private var actionError: String? = nil
    @State private var posting = false

    private var charges: [BillingCharge787] { data?.pendingCharges ?? [] }
    private var approvedTotal: Double { charges.reduce(0) { $0 + ($1.amount ?? 0) } }
    private var selectedCharges: [BillingCharge787] { charges.filter { selected.contains($0.id) } }
    private var selectedTotal: Double { selectedCharges.reduce(0) { $0 + ($1.amount ?? 0) } }
    private var heldTotal: Double { approvedTotal - selectedTotal }
    private func isDemurrage(_ c: BillingCharge787) -> Bool { (c.type ?? "").lowercased().contains("demurrage") }
    private var demTotal: Double { selectedCharges.filter { isDemurrage($0) }.reduce(0) { $0 + ($1.amount ?? 0) } }
    private var detTotal: Double { selectedCharges.filter { !isDemurrage($0) }.reduce(0) { $0 + ($1.amount ?? 0) } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                VDetnEyebrow(section: "BILLING BATCH", caption: "DRAYAGE + OCEAN")
                titleRow
                IridescentHairline()

                if loading {
                    loadingCard
                } else if let err = loadError {
                    errorCard(err)
                } else if charges.isEmpty {
                    EusoEmptyState(systemImage: "tray.and.arrow.up",
                                   title: "No approved charges",
                                   subtitle: "No approved detention or demurrage charges are queued for settlement.")
                } else {
                    summaryCard
                    lifecycleStrip
                    ledgerCard
                    postsToStrip
                    ctaPair
                    if let e = actionError {
                        errorCard(e)
                    } else if let m = actionMessage {
                        LifecycleCard { Text(m).font(EType.caption).foregroundStyle(Brand.success) }
                    }
                }
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, Space.s5).padding(.top, Space.s4)
        }
        .task { await load() }
        .eusoRefreshable { await load() }
    }

    private var titleRow: some View {
        HStack(alignment: .top) {
            Text("Detention billing").font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(charges.count) APPROVED").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                    .foregroundStyle(palette.textTertiary)
                Text("drayage + ocean").font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
            }
        }
    }

    // MARK: Summary card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SELECTED · READY TO INVOICE").font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(palette.textTertiary)
                    Text(VDetn.money(selectedTotal))
                        .font(.system(size: 30, weight: .bold, design: .monospaced))
                        .foregroundStyle(LinearGradient.diagonal).minimumScaleFactor(0.6).lineLimit(1)
                    Text("\(selected.count) of \(charges.count) charges · \(VDetn.money(approvedTotal)) approved · \(VDetn.money(heldTotal)) held")
                        .font(.system(size: 11)).foregroundStyle(palette.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("SELECTED").font(.system(size: 9, weight: .heavy)).tracking(0.6).foregroundStyle(palette.textTertiary)
                    Text("\(selected.count)").font(.system(size: 26, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
                }
            }
            // demurrage / detention split
            GeometryReader { g in
                let denom = max(1, demTotal + detTotal)
                HStack(spacing: 4) {
                    Capsule().fill(LinearGradient.primary).frame(width: max(0, CGFloat(demTotal / denom) * g.size.width - 4))
                    Capsule().fill(Brand.warning)
                }
                .frame(height: 8)
            }
            .frame(height: 8)
            HStack(spacing: 20) {
                splitLegend("Demurrage", demTotal, Brand.blue)
                splitLegend("Detention", detTotal, Brand.warning)
                Spacer(minLength: 0)
            }
        }
        .padding(Space.s5)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5).fill(LinearGradient.diagonal).frame(width: 3).padding(.vertical, 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func splitLegend(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 10)).foregroundStyle(palette.textSecondary)
            Text(VDetn.money(value)).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(palette.textPrimary)
        }
    }

    // MARK: Lifecycle strip

    private let stages787 = ["APPROVED", "BATCHED", "INVOICED", "POSTED", "CLEARED"]
    private let subs787 = ["done", "now", "1 tap", "est 4m", "net-7"]
    private let activeStage787 = 1
    private var lifecycleStrip: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("BILLING POSTING · STAGE 2 OF 5").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    ForEach(0..<stages787.count, id: \.self) { i in
                        Text(stages787[i]).font(.system(size: 7, weight: .bold)).tracking(0.3)
                            .foregroundStyle(i == activeStage787 ? AnyShapeStyle(LinearGradient.primary)
                                             : (i < activeStage787 ? AnyShapeStyle(palette.textSecondary) : AnyShapeStyle(palette.textTertiary)))
                            .frame(maxWidth: .infinity)
                    }
                }
                GeometryReader { g in
                    let n = CGFloat(stages787.count)
                    let colW = g.size.width / n
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.textPrimary.opacity(0.10))
                            .frame(width: max(0, g.size.width - colW), height: 2).offset(x: colW / 2, y: 5)
                        Capsule().fill(LinearGradient.primary)
                            .frame(width: colW, height: 2).offset(x: colW / 2, y: 5)
                        HStack(spacing: 0) {
                            ForEach(0..<stages787.count, id: \.self) { i in
                                let done = i <= activeStage787
                                Circle().fill(done ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.textPrimary.opacity(0.18)))
                                    .frame(width: i == activeStage787 ? 10 : 7, height: i == activeStage787 ? 10 : 7)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .frame(height: 12)
                HStack(spacing: 0) {
                    ForEach(0..<subs787.count, id: \.self) { i in
                        Text(subs787[i]).font(.system(size: 9, weight: i == activeStage787 ? .bold : .regular, design: .monospaced))
                            .foregroundStyle(i == activeStage787 ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(palette.textTertiary))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // MARK: Selectable ledger

    private var ledgerCard: some View {
        VStack(alignment: .leading, spacing: Space.s3) {
            Text("APPROVED CHARGES · TAP TO INCLUDE").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
            VStack(spacing: 0) {
                let rows = Array(charges.prefix(6).enumerated())
                ForEach(rows, id: \.element.id) { idx, c in
                    chargeRow(c)
                    if idx < rows.count - 1 {
                        Rectangle().fill(palette.borderFaint).frame(height: 1).padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func chargeRow(_ c: BillingCharge787) -> some View {
        let on = selected.contains(c.id)
        let dem = isDemurrage(c)
        let typeColor = dem ? Brand.blue : Brand.warning
        return Button {
            if on { selected.remove(c.id) } else { selected.insert(c.id) }
        } label: {
            HStack(spacing: Space.s3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(on ? AnyShapeStyle(LinearGradient.primary) : AnyShapeStyle(Color.clear))
                        .frame(width: 24, height: 24)
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(on ? Color.clear : palette.textTertiary.opacity(0.6), lineWidth: 2))
                    if on { Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white) }
                }
                VDetnIconChip(systemImage: dem ? "clock.badge.exclamationmark" : "shippingbox", color: typeColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(dem ? "Demurrage" : "Detention") · \(c.facilityName ?? "Terminal")")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(palette.textPrimary).lineLimit(1)
                    Text("\(c.origin ?? "—") → \(c.destination ?? "—")")
                        .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary).lineLimit(1)
                }
                Spacer(minLength: Space.s2)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(VDetn.money(c.amount ?? 0)).font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(palette.textPrimary)
                    Text(dem ? "DEMURRAGE" : "DETENTION").font(.system(size: 9, weight: .heavy)).tracking(0.4)
                        .foregroundStyle(typeColor)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .opacity(on ? 1 : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Posts-to strip

    private var postsToStrip: some View {
        HStack(spacing: 4) {
            Text("Posts to").font(.system(size: 11)).foregroundStyle(palette.textSecondary)
            Text("settlement · accessorial").font(.system(size: 11, weight: .bold)).foregroundStyle(palette.textPrimary)
            Text("· \(selectedCharges.first.map { "load \($0.loadId ?? 0)" } ?? "each load")")
                .font(EType.mono(.caption)).foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Color.white.opacity(0.05)))
    }

    // MARK: CTA

    private var ctaPair: some View {
        HStack(spacing: Space.s2) {
            CTAButton(title: posting ? "Posting…" : "Invoice \(selected.count) · \(VDetn.money(selectedTotal))",
                      action: { Task { await invoiceBatch() } }, isLoading: posting)
            secondaryButton787(title: allSelected ? "Clear" : "Select all") { toggleAll() }.frame(width: 128)
        }
    }

    private var allSelected: Bool { !charges.isEmpty && selected.count == charges.count }
    private func toggleAll() {
        if allSelected { selected.removeAll() } else { selected = Set(charges.map { $0.id }) }
    }

    private func secondaryButton787(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(EType.title).foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Color(hex: 0x232932))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderSoft))
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Load / actions

    private struct BillingInput787: Encodable { let status: String; let batchSize: Int }
    private struct InvoiceInput787: Encodable { let claimId: Int }

    private func load() async {
        loading = true; loadError = nil
        do {
            let resp: BillingResponse787 = try await EusoTripAPI.shared.query(
                "detentionAccessorials.getAccessorialBilling", input: BillingInput787(status: "approved", batchSize: 50))
            self.data = resp
            self.selected = Set((resp.pendingCharges ?? []).map { $0.id })
        } catch {
            loadError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func invoiceBatch() async {
        guard !posting else { return }
        actionMessage = nil; actionError = nil
        let ids = selectedCharges.map { $0.id }
        guard !ids.isEmpty else { actionError = "Select at least one approved charge to invoice."; return }
        posting = true
        var posted = 0
        var total = 0.0
        var firstError: String? = nil
        for id in ids {
            do {
                let r: InvoiceResult787 = try await EusoTripAPI.shared.mutation(
                    "detentionAccessorials.invoiceDetentionCharge", input: InvoiceInput787(claimId: id))
                if r.success == true { posted += 1; total += r.invoicedAmount ?? 0 }
            } catch {
                if firstError == nil { firstError = (error as? EusoTripAPIError)?.errorDescription ?? error.localizedDescription }
            }
        }
        if posted > 0 {
            actionMessage = "Invoiced \(posted) charge\(posted == 1 ? "" : "s") · \(VDetn.money(total)) posted to settlement accessorials."
            await load()
        }
        if let fe = firstError, posted == 0 { actionError = fe }
        posting = false
    }

    private var loadingCard: some View {
        LifecycleCard { Text("Loading approved charges…").font(EType.caption).foregroundStyle(palette.textSecondary) }
    }
    private func errorCard(_ e: String) -> some View {
        LifecycleCard(accentDanger: true) { Text(e).font(EType.caption).foregroundStyle(Brand.danger) }
    }
}

#Preview("787 · Vessel Detention Billing Batch · Night") { VesselDetentionBillingBatchScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("787 · Vessel Detention Billing Batch · Light") { VesselDetentionBillingBatchScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
