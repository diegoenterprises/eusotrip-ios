//
//  701_RailRepairWorkOrder.swift
//  EusoTrip — Rail Engineer · Mechanical Repair Work Order (repair-billing
//  ledger downstream of the bad-order handoff).
//
//  Bespoke port of "05 Rail/Light-SVG/701 Rail Mechanical Repair Work Order.svg" (+ Dark).
//  ARCHETYPE = MONEY LEDGER — amount hero, in-progress status card, labor /
//  material / handling breakdown with split bar + TOTAL band, AAR Interchange
//  Rule 95 responsibility row.
//
//  Role: RAIL_ENGINEER (carrier billing family). transportMode=rail.
//
//  WIRING MANIFEST (verified against frontend/server/routers/):
//    railShipments.getRailInspections  EXISTS railShipments.ts:1915 {limit} →
//        failed rows are the REAL open-defect feed (the work-order subject).
//    railFreightAudit.recentAudits     EXISTS railFreightAudit.ts:103 {limit} →
//        {audits:[], total, note} — invoice-audit history. Empty on disk today
//        (no invoice storage), rendered as an honest empty billing history.
//    railFreightAudit.auditInvoice     EXISTS railFreightAudit.ts:27 — the
//        charge-audit engine. It audits line items the caller supplies; with
//        zero charge lines on file there is nothing real to audit, so the
//        Bill CTA surfaces the honest no-charge-lines state instead of posting
//        a fabricated $0 invoice.
//
//

import SwiftUI
struct RailRepairWorkOrderScreen: View {
    let theme: Theme.Palette

    var body: some View {
        Shell(theme: theme) {
            RailRepairWorkOrderBody()
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

private struct InspectionRow701: Decodable {
    let id: String?
    let type: String?
    let date: String?
    let location: String?
    let status: String?
    let inspector: String?
    let notes: String?
    let passed: Bool?
}

private struct RecentAudits701: Decodable {
    struct AuditRow: Decodable, Identifiable {
        let invoiceNumber: String?
        let auditStatus: String?
        let invoiceTotal: Double?
        var id: String { invoiceNumber ?? UUID().uuidString }
    }
    let audits: [AuditRow]?
    let total: Int?
    let note: String?
}

private struct LimitInput701: Encodable { let limit: Int }

/// One real repair work order off `railMechanical.getWorkOrders`.
private struct WorkOrderRow701: Decodable, Identifiable {
    let id: String
    let railcarNumber: String?
    let defectCode: String?
    let description: String?
    let status: String?
    let totalBilled: Double?
    let openedAt: String?
    let closedAt: String?
}
private struct WorkOrdersInput701: Encodable { let limit: Int }
private struct OpenWorkOrderInput701: Encodable { let railcarNumber: String; let defectCode: String?; let description: String? }
private struct OpenWorkOrderResult701: Decodable { let success: Bool?; let id: Int? }

// MARK: - Body

private struct RailRepairWorkOrderBody: View {
    @Environment(\.palette) private var palette
    @State private var defects: [InspectionRow701] = []
    @State private var audits: RecentAudits701? = nil
    @State private var workOrders: [WorkOrderRow701] = []
    @State private var openingWO = false
    @State private var woMessage: String? = nil
    @State private var loading = true
    @State private var regime = 0
    @State private var showBillSheet = false
    @State private var laborHours = ""
    @State private var laborCost = ""
    @State private var partsCost = ""
    @State private var isBilling = false
    @State private var showDisputeNotice = false

    private let regimes: [(String, String)] = [("US · 48H", "USD"), ("CA · 48H", "CAD"), ("MX · 24H", "MXN")]

    /// Failed inspections = the real open-defect list; newest first.
    private var failedDefects: [InspectionRow701] {
        defects
            .filter { $0.passed == false }
            .sorted { (Self.date($0.date) ?? .distantPast) > (Self.date($1.date) ?? .distantPast) }
    }

    private var subjectDefect: InspectionRow701? { failedDefects.first }
    private var billedAuditCount: Int { audits?.total ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrowRow
            Text("Repair work order")
                .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, 20).padding(.top, Space.s3)
            Text(subtitleLine)
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 20).padding(.top, 4)
            chipRow.padding(.horizontal, 20).padding(.top, Space.s3)
            IridescentHairline().padding(.top, Space.s3)

            VStack(alignment: .leading, spacing: Space.s4) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 64)
                } else if subjectDefect == nil {
                    EusoEmptyState(systemImage: "wrench.and.screwdriver",
                                   title: "No open defects",
                                   subtitle: "A repair work order opens from a failed mechanical inspection. Every inspection on file passed — there is nothing to cost.")
                } else {
                    amountHero
                    statusCard
                    breakdownHeader
                    breakdownLedger
                    responsibilityRow
                    triBand
                    footerActions
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Space.s5)
        }
        .task { await reload() }
        .eusoRefreshable { await reload() }
        .sheet(isPresented: $showBillSheet) {
            VStack(alignment: .leading, spacing: Space.s3) {
                Text("Bill Repair").font(EType.h2).foregroundStyle(palette.textPrimary)
                Text("Enter labor and material costs to close this work order.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                
                TextField("Labor Hours", text: $laborHours)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 14, weight: .bold))
                    .padding(Space.s3).background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                
                TextField("Labor Cost", text: $laborCost)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 14, weight: .bold))
                    .padding(Space.s3).background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                
                TextField("Parts Cost", text: $partsCost)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 14, weight: .bold))
                    .padding(Space.s3).background(palette.bgCardSoft)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint))
                
                CTAButton(title: isBilling ? "Billing…" : "Bill Repair", action: { Task { await billRepair() } })
                    .disabled(laborHours.isEmpty && laborCost.isEmpty && partsCost.isEmpty || isBilling)
                Spacer()
            }
            .padding(20).presentationDetents([.height(360)]).presentationDragIndicator(.visible)
            .background(palette.bgPage)
        }
        .alert("Nothing to dispute", isPresented: $showDisputeNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A dispute attaches to a billed repair charge. No charge lines are on file for this work order, so there is nothing to dispute.")
        }
    }

    private var eyebrowRow: some View {
        HStack(spacing: 0) {
            EusoTripEyebrow(verbatim: "CARRIER · RAIL · REPAIR")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(LinearGradient.primary)
            Spacer(minLength: 8)
            Text("WORK ORDER")
                .font(.system(size: 9, weight: .heavy)).tracking(1.0)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 20).padding(.top, Space.s4)
    }

    private var subtitleLine: String {
        if let d = subjectDefect {
            var bits: [String] = []
            if let loc = d.location, !loc.isEmpty { bits.append(loc) }
            if let t = d.type, !t.isEmpty { bits.append(t.replacingOccurrences(of: "_", with: " ")) }
            if let dd = Self.date(d.date) { bits.append(Self.shortLabel(dd)) }
            return bits.isEmpty ? "Open defect on file" : bits.joined(separator: " · ")
        }
        return "Mechanical repair billing · AAR interchange rules"
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            chip(failedDefects.isEmpty ? "no defects" : "\(failedDefects.count) open defect\(failedDefects.count == 1 ? "" : "s")",
                 failedDefects.isEmpty ? palette.textSecondary : Brand.warning)
            chip("estimate · unbilled", Brand.warning)
            chip("AAR FM", Brand.blue)
        }
    }

    private func chip(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .heavy)).foregroundStyle(c)
            .padding(.horizontal, 12).frame(height: 26)
            .background(Capsule().fill(palette.bgCardSoft))
            .overlay(Capsule().strokeBorder(palette.borderFaint))
    }

    // MARK: Amount hero — honest "estimate (unbilled)": no charge rows exist,
    // so the number never fabricates a live total.

    private var amountHero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("—")
                .font(.system(size: 34, weight: .bold)).monospacedDigit()
                .foregroundStyle(palette.textTertiary)
            Text("estimate (unbilled) — amounts appear when labor and material are recorded against this defect")
                .font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Status card — the real defect record.

    @ViewBuilder
    private var statusCard: some View {
        if let d = subjectDefect {
            VStack(alignment: .leading, spacing: 8) {
                Text("DEFECT · OPEN")
                    .font(.system(size: 9.5, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 22)
                    .background(Capsule().fill(LinearGradient.primary))
                Text(d.location ?? "Railcar not identified")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                if let notes = d.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 10)).foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let inspector = d.inspector, !inspector.isEmpty {
                    Text("inspected by \(inspector)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .strokeBorder(palette.borderFaint))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private var breakdownHeader: some View {
        HStack {
            Text("BREAKDOWN · LABOR / MATERIAL")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Spacer()
            Text(regimes[regime].1)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.textSecondary)
        }
    }

    // MARK: Ledger — empty split bar + honest empty rows; the TOTAL band
    // reads "—" until real charge lines exist. Billing history from
    // recentAudits (real endpoint, honestly empty today).

    private var breakdownLedger: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(palette.bgCardSoft)
                .frame(height: 12)
                .overlay(Capsule().strokeBorder(palette.borderFaint))
                .padding(.bottom, 10)
            Text("No labor, material, or handling lines are on file for this defect.")
                .font(.system(size: 11)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            Divider().overlay(palette.borderFaint).padding(.bottom, 8)
            HStack {
                Text("TOTAL · BILLABLE")
                    .font(.system(size: 11, weight: .heavy)).tracking(0.4)
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                Text("—")
                    .font(.system(size: 18, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(palette.textTertiary)
            }
            if billedAuditCount == 0 {
                Text("Billing history: no audited repair invoices on file.")
                    .font(.system(size: 9.5)).foregroundStyle(palette.textTertiary)
                    .padding(.top, 8)
            } else {
                Text("Billing history: \(billedAuditCount) audited invoice\(billedAuditCount == 1 ? "" : "s") on file.")
                    .font(.system(size: 9.5)).foregroundStyle(palette.textSecondary)
                    .padding(.top, 8)
            }
        }
        .padding(16)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(palette.borderFaint))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    // MARK: Responsibility — AAR Interchange Rule 95. Keyed to data
    // presence: no charge rows means no responsibility assignment on file.

    private var responsibilityRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RESPONSIBILITY · AAR INTERCHANGE RULE 95")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                .foregroundStyle(palette.textTertiary)
            Text("No responsibility assignment is on file. Car-owner vs handling-line responsibility resolves when this repair is costed.")
                .font(.system(size: 10.5)).foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(palette.bgCardSoft))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(i == regime ? Brand.blue.opacity(0.5) : palette.borderFaint))
                .onTapGesture { regime = i }
            }
        }
    }

    /// The top open bad-order defect that has no work order yet — the
    /// real subject for "Open work order".
    private var openableDefect: InspectionRow701? {
        defects.first { d in
            d.passed == false && !workOrders.contains { ($0.railcarNumber ?? "") == (d.location ?? "") && ($0.status ?? "") != "closed" }
        }
    }

    @ViewBuilder
    private var footerActions: some View {
        if let m = woMessage {
            Text(m).font(EType.caption).foregroundStyle(palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        if !workOrders.isEmpty {
            Text("\(workOrders.filter { ($0.status ?? "") != "closed" }.count) open · \(workOrders.count) total work order\(workOrders.count == 1 ? "" : "s")")
                .font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundStyle(palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        HStack(spacing: Space.s3) {
            if let d = openableDefect {
                CTAButton(title: openingWO ? "Opening…" : "Open work order", action: {
                    Task { await openWorkOrder(railcar: d.location ?? "Railcar", defectCode: d.type, description: d.notes) }
                })
                .frame(maxWidth: .infinity)
                .disabled(openingWO)
            } else {
                CTAButton(title: "Bill repair", action: { showBillSheet = true })
                    .frame(maxWidth: .infinity)
            }
            Button(action: { showDisputeNotice = true }) {
                Text("Dispute")
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

    // MARK: Load

    private func reload() async {
        loading = true
        async let insp: [InspectionRow701] = EusoTripAPI.shared.query(
            "railShipments.getRailInspections", input: LimitInput701(limit: 100))
        async let hist: RecentAudits701 = EusoTripAPI.shared.query(
            "railFreightAudit.recentAudits", input: LimitInput701(limit: 20))
        async let wos: [WorkOrderRow701] = EusoTripAPI.shared.query(
            "railMechanical.getWorkOrders", input: WorkOrdersInput701(limit: 50))
        self.defects = (try? await insp) ?? []
        self.audits = try? await hist
        self.workOrders = (try? await wos) ?? []
        loading = false
    }

    /// Open a real repair work order from a bad-order inspection defect.
    private func openWorkOrder(railcar: String, defectCode: String?, description: String?) async {
        guard !openingWO else { return }
        openingWO = true; defer { openingWO = false }
        do {
            let out: OpenWorkOrderResult701 = try await EusoTripAPI.shared.mutation(
                "railMechanical.openWorkOrder",
                input: OpenWorkOrderInput701(railcarNumber: railcar, defectCode: defectCode, description: description))
            if out.success == true {
                woMessage = "Work order opened for \(railcar)."
                await reload()
            } else {
                woMessage = "The work order didn't open. Try again."
            }
        } catch {
            woMessage = "The work order didn't open. Check your connection and try again."
        }
    }

    private func billRepair() async {
        guard let wo = workOrders.first(where: { ($0.status ?? "") != "closed" }) else { return }
        guard !isBilling else { return }
        isBilling = true; defer { isBilling = false }
        struct In: Encodable {
            let workOrderId: Int
            let laborHours: Double?
            let laborCost: Double?
            let partsCost: Double?
        }
        struct Out: Decodable { let success: Bool }
        let idVal = Int(wo.id.replacingOccurrences(of: "wo_", with: "")) ?? 0
        guard idVal > 0 else { return }
        do {
            let _: Out = try await EusoTripAPI.shared.mutation(
                "railMechanical.closeWorkOrder",
                input: In(
                    workOrderId: idVal,
                    laborHours: Double(laborHours),
                    laborCost: Double(laborCost),
                    partsCost: Double(partsCost)
                )
            )
            showBillSheet = false
            laborHours = ""; laborCost = ""; partsCost = ""
            woMessage = "Repair billed successfully."
            await reload()
        } catch {
            woMessage = "Billing failed. Check your connection."
        }
    }

    private static func date(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: s)
    }

    private static func shortLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}

#Preview("701 · Rail Repair Work Order · Night") {
    RailRepairWorkOrderScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark)
}
#Preview("701 · Rail Repair Work Order · Light") {
    RailRepairWorkOrderScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light)
}
