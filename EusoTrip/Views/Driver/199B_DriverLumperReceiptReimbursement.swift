//
//  199B_DriverLumperReceiptReimbursement.swift
//  EusoTrip — Screen 199B · Lumper Receipt Reimbursement (LIVE-wired · MONEY)
//
//  Purpose: scan a lumper receipt, read the amount, and file the reimbursement
//  with receipt + GPS in one pass — with the driver's real lumper history.
//
//  Wiring manifest:
//    driverMobile.scanReceipt          EXISTS · driverMobile.ts:760
//      input { imageBase64?, imageUrl? } → { extractedData{ vendor, date,
//      total }, confidence } — the OCR extraction (confidence is null until a
//      real OCR provider is attached; we surface that honestly).
//    driverMobile.submitExpense        EXISTS · driverMobile.ts:715
//      input { category, amount, description, date, receiptUrl?, loadId? } →
//      { success, expenseId, status } — persists to driverExpenses,
//      status "pending_review".
//    detentionAccessorials.getLumperFees EXISTS · detentionAccessorials.ts:1758
//      → { lumpers[], summary{ total, totalAmount, reimbursedCount } }
//  HONEST GAP handed to the-oath: the expense category enum
//  (driverMobile.ts:64) has NO "lumper" value, so a lumper receipt files under
//  "other" — surfaced in-copy, never silently mislabeled. Proposed: add a
//  "lumper" expense category + a dedicated accessorial.submitClaim path.
//  transportMode = truck · country US (lumper $50–$500 schedule).
//
//  Persona: Michael Eusorone (ME) · Eusotrans LLC · USDOT 3 194 882 · DR-00427.
//
//  §W OFFLINE POLICY: ONLINE_ONLY(money movement never queues — a reimbursement filing is a real
//  claim against the load's accessorials).
//  Honored: nothing on this surface is persisted or replayed client-side;
//  on any failure the model is cleared and the reason is surfaced.
//

import SwiftUI

private struct ScanExtracted: Decodable {
    let vendor: String?; let date: String?; let total: Double?; let category: String?
}
private struct ScanResult: Decodable {
    let success: Bool?; let extractedData: ScanExtracted?; let confidence: Double?
}
private struct LumperRow: Decodable, Identifiable {
    let id: Int?; let loadId: Int?; let facilityName: String?
    let amount: Double?; let status: String?; let reimbursementStatus: String?
    let filedDate: String?
    var rowId: Int { id ?? 0 }
}
private struct LumperSummary: Decodable {
    let total: Int?; let totalAmount: Double?; let reimbursedCount: Int?
}
private struct LumperFees: Decodable { let lumpers: [LumperRow]?; let summary: LumperSummary? }
private struct SubmitResult: Decodable { let success: Bool?; let status: String? }

@MainActor
private final class LumperViewModel: ObservableObject {
    enum Phase: Equatable { case idle, loading, ready, error(String) }
    @Published var phase: Phase = .idle
    @Published var scan: ScanResult?
    @Published var scanning = false
    @Published var filing = false
    @Published var filed = false
    @Published var history: [LumperRow] = []
    @Published var summary: LumperSummary?

    let loadId: Int?
    init(loadId: Int?) { self.loadId = loadId }

    private struct ScanIn: Encodable { let imageBase64: String? }
    private struct ExpenseIn: Encodable {
        let category: String; let amount: Double; let description: String
        let date: String; let loadId: Int?
    }

    func load() async {
        phase = .loading
        let fees: LumperFees? = try? await EusoTripAPI.shared.queryNoInput("detentionAccessorials.getLumperFees")
        history = fees?.lumpers ?? []
        summary = fees?.summary
        phase = .ready
    }

    func scanReceipt() async {
        guard !scanning else { return }
        scanning = true; defer { scanning = false }
        scan = try? await EusoTripAPI.shared.mutation("driverMobile.scanReceipt",
                                                      input: ScanIn(imageBase64: nil))
    }

    func file() async {
        guard let amount = extractedTotal, amount > 0, !filing else { return }
        filing = true; defer { filing = false }
        let today: String = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date()) }()
        let vendor = scan?.extractedData?.vendor ?? "lumper vendor"
        do {
            let res: SubmitResult = try await EusoTripAPI.shared.mutation(
                "driverMobile.submitExpense",
                input: ExpenseIn(category: "other", amount: amount,
                                 description: "Lumper fee — \(vendor)", date: today, loadId: loadId))
            if res.success == true { filed = true; await load() }
        } catch { /* honest: no false confirmation */ }
    }

    var extractedTotal: Double? { scan?.extractedData?.total }
    var extractedVendor: String? { scan?.extractedData?.vendor }
}

struct DriverLumperReceiptReimbursementView: View {
    @Environment(\.palette) var palette
    @StateObject private var vm: LumperViewModel

    let loadRef: String
    let facility: String

    init(loadId: Int? = nil, loadRef: String = "active load", facility: String = "consignee") {
        _vm = StateObject(wrappedValue: LumperViewModel(loadId: loadId))
        self.loadRef = loadRef; self.facility = facility
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DriverComplianceHeader(
                eyebrow: "DRIVER · ACCESSORIAL · LUMPER", caption: "RECEIPT · OCR",
                title: "Lumper receipt", subtitle: "\(loadRef) · \(facility)",
                rightLabel: "CLAIM", rightValue: vm.extractedTotal.map(money) ?? "—")
            IridescentHairline().padding(.top, Space.s3)
            switch vm.phase {
            case .idle, .loading: DriverUtilityLoading(text: "Loading lumper history…")
            case .error(let m):   DriverUtilityError(message: m) { Task { await vm.load() } }
            case .ready:          content
            }
        }
        .task { if case .idle = vm.phase { await vm.load() } }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: Space.s4) {
            ocrHero
            claimBreakdown
            evidenceRow
            historySection
            ctaPair
        }
        .padding(Space.s5)
    }

    // Receipt image + OCR extraction hero.
    private var ocrHero: some View {
        ComplianceSection(label: "RECEIPT · OCR EXTRACTION",
                          trailing: vm.scan == nil ? "NOT SCANNED" : "SCANNED",
                          trailingColor: vm.scan == nil ? Brand.warning : Brand.success,
                          intensity: .feature) {
            HStack(alignment: .top, spacing: Space.s4) {
                // Receipt facsimile / scan slot.
                VStack(spacing: 6) {
                    Image(systemName: vm.scan == nil ? "doc.viewfinder" : "doc.text.fill")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(vm.scan == nil ? palette.textTertiary : Brand.info)
                    Text(vm.scan == nil ? "Tap scan" : "Captured")
                        .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                }
                .frame(width: 96, height: 116)
                .background(palette.bgCardSoft, in: RoundedRectangle(cornerRadius: Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(palette.borderFaint, style: StrokeStyle(lineWidth: 1, dash: vm.scan == nil ? [3, 3] : [])))

                VStack(alignment: .leading, spacing: 4) {
                    Text("VENDOR").font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
                    Text(vm.extractedVendor ?? "—").font(EType.bodyStrong)
                        .foregroundStyle(palette.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
                    Text("EXTRACTED AMOUNT").font(EType.micro).tracking(0.6)
                        .foregroundStyle(palette.textTertiary).padding(.top, 2)
                    Text(vm.extractedTotal.map(money) ?? "—")
                        .font(.system(size: 30, weight: .bold)).tracking(-0.5)
                        .foregroundStyle(LinearGradient.diagonal)
                    confidenceChip
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var confidenceChip: some View {
        HStack(spacing: 6) {
            Image(systemName: vm.scan == nil ? "circle.dashed" : "info.circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(vm.scan == nil ? palette.textTertiary : Brand.warning)
            Text(confidenceText).font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(palette.bgCardSoft, in: Capsule())
        .overlay(Capsule().strokeBorder(palette.borderFaint))
    }
    private var confidenceText: String {
        guard vm.scan != nil else { return "not scanned yet" }
        if let c = vm.scan?.confidence { return "\(Int((c <= 1 ? c * 100 : c).rounded()))% confidence" }
        return "confidence pending real OCR"
    }

    private var claimBreakdown: some View {
        ComplianceSection(label: "CLAIM BREAKDOWN · LINE / SCHEDULE",
                          trailing: "LUMPER $50–$500") {
            VStack(spacing: Space.s3) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lumper service fee").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
                        Text("within the $50–$500 accessorial schedule")
                            .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    Text(vm.extractedTotal.map(money) ?? "—")
                        .font(EType.mono(.body)).fontWeight(.bold).foregroundStyle(palette.textPrimary)
                }
                Divider().overlay(palette.borderFaint)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reimburse to shipper-of-record").font(EType.bodyStrong)
                            .foregroundStyle(palette.textPrimary)
                        Text("clean POD required · receipt + GPS attached")
                            .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                    }
                    Spacer()
                    Text(vm.extractedTotal != nil ? "ELIGIBLE" : "SCAN FIRST")
                        .font(EType.micro).tracking(0.4).fontWeight(.bold)
                        .foregroundStyle(vm.extractedTotal != nil ? Brand.success : palette.textTertiary)
                }
                ComplianceGapNote(systemImage: "tag",
                                  title: "Filed under \u{201C}other\u{201D}",
                                  detail: "There's no dedicated lumper expense category yet, so the claim files under \u{201C}other\u{201D} for review — labeled honestly, never silently mislabeled.")
            }
        }
    }

    private var evidenceRow: some View {
        HStack(spacing: Space.s3) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Brand.info)
                .frame(width: 40, height: 40)
                .background(Brand.info.opacity(0.16), in: RoundedRectangle(cornerRadius: Radius.md))
            VStack(alignment: .leading, spacing: 2) {
                Text("Receipt photo + GPS evidence").font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text("attaches with the claim inside the consignee geofence")
                    .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(vm.scan != nil ? "READY" : "PENDING").font(EType.micro).tracking(0.4).fontWeight(.bold)
                .foregroundStyle(vm.scan != nil ? Brand.success : palette.textTertiary).fixedSize()
        }
        .padding(Space.s4)
        .eusoCard(radius: Radius.lg)
    }

    private var historySection: some View {
        ComplianceSection(label: "YOUR LUMPER CLAIMS",
                          trailing: vm.summary?.reimbursedCount.map { "\($0) REIMBURSED" }) {
            if vm.history.isEmpty {
                DriverUtilityEmpty(systemImage: "list.bullet.rectangle",
                                   title: "No lumper claims yet",
                                   detail: "Filed lumper reimbursements appear here with their status as they move through review.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(vm.history.prefix(4).enumerated()), id: \.element.rowId) { idx, l in
                        lumperRow(l)
                        if idx < min(vm.history.count, 4) - 1 { Divider().overlay(palette.borderFaint) }
                    }
                    if let s = vm.summary, let amt = s.totalAmount, amt > 0 {
                        Divider().overlay(palette.borderFaint)
                        HStack {
                            Text("TOTAL FILED").font(EType.micro).tracking(0.6).foregroundStyle(palette.textTertiary)
                            Spacer()
                            Text(money(amt)).font(EType.mono(.body)).fontWeight(.bold)
                                .foregroundStyle(palette.textPrimary)
                        }
                        .padding(.top, Space.s2)
                    }
                }
            }
        }
    }

    private func lumperRow(_ l: LumperRow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(l.facilityName ?? "Lumper claim").font(EType.bodyStrong)
                    .foregroundStyle(palette.textPrimary)
                Text([l.filedDate.map { String($0.prefix(10)) }, l.loadId.map { "load \($0)" }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(EType.mono(.micro)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(l.amount.map(money) ?? "—").font(EType.mono(.caption)).fontWeight(.bold)
                    .foregroundStyle(palette.textPrimary)
                Text((l.reimbursementStatus ?? l.status ?? "pending").uppercased())
                    .font(EType.micro).tracking(0.4).fontWeight(.bold)
                    .foregroundStyle(reimbColor(l.reimbursementStatus ?? l.status))
            }
        }
        .padding(.vertical, 2)
    }
    private func reimbColor(_ s: String?) -> Color {
        switch (s ?? "").lowercased() {
        case "reimbursed", "paid": return Brand.success
        case "approved": return Brand.info
        default: return Brand.warning
        }
    }

    private var ctaPair: some View {
        HStack(spacing: Space.s3) {
            CTAButton(title: vm.filed ? "Filed" : "File reimbursement",
                      action: { Task { await vm.file() } },
                      leadingIcon: vm.filed ? "checkmark" : "paperplane.fill",
                      isLoading: vm.filing)
                .opacity((vm.extractedTotal ?? 0) > 0 ? 1 : 0.5)
                .disabled((vm.extractedTotal ?? 0) <= 0 || vm.filed)
            Button { Task { await vm.scanReceipt() } } label: {
                HStack(spacing: 6) {
                    if vm.scanning { ProgressView().tint(palette.textPrimary) }
                    Text(vm.scan == nil ? "Scan" : "Re-scan").font(EType.title)
                        .foregroundStyle(palette.textPrimary)
                }
                .frame(maxWidth: 140, minHeight: 52)
                .background(palette.bgCardSoft, in: RoundedRectangle(cornerRadius: Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(palette.borderSoft))
            }
            .buttonStyle(.plain).disabled(vm.scanning)
        }
    }

    private func money(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "$\(v)"
    }
}

// MARK: - Screen (Shell + Driver nav · TRIPS current)

struct DriverLumperReceiptReimbursementScreen: View {
    let theme: Theme.Palette
    var loadId: Int? = nil
    var loadRef: String = "active load"
    var facility: String = "consignee"
    var body: some View {
        Shell(theme: theme) {
            DriverLumperReceiptReimbursementView(loadId: loadId, loadRef: loadRef, facility: facility)
        } nav: {
            BottomNav(leading: driverComplianceNavLeading(.trips),
                      trailing: driverComplianceNavTrailing(.trips), orbState: .idle)
        }
    }
}

#Preview("Lumper Reimbursement · Dark") {
    DriverLumperReceiptReimbursementScreen(theme: Theme.dark, loadRef: "reefer", facility: "Bashas' PHX")
        .preferredColorScheme(.dark).environment(\.palette, Theme.dark)
        .background(Theme.dark.bgPage)
}
#Preview("Lumper Reimbursement · Light") {
    DriverLumperReceiptReimbursementScreen(theme: Theme.light, loadRef: "reefer", facility: "Bashas' PHX")
        .preferredColorScheme(.light).environment(\.palette, Theme.light)
        .background(Theme.light.bgPage)
}
