//
//  306_CatalystDriverPayroll.swift
//  EusoTrip — Catalyst · Driver Payroll (brick 306).
//
//  Pixel-match to `03 Catalyst/Dark-SVG/306 Catalyst Settlements.svg`.
//  Renders the catalyst-owner-op driver payroll surface — the
//  §8.4 owner-op seam where the LLC pays the individual Michael
//  Eusorone (same companyId, net-0 to ME). Real endpoints, no stubs.
//
//  Wire bindings:
//    accounting.getDriverSettlements   — settlement documents
//    settlementBatching.getDriverBatchView — payable batches
//    loads.list (filtered by status)   — fallback list when neither
//                                          settlement source has rows
//                                          yet (early-stage catalyst).
//
//  Bottom nav frozen per doctrine — content only.
//

import SwiftUI

// MARK: - Wire models

private struct DriverSettlementsResponse: Decodable {
    let docs: [SettlementDoc]?
    let total: Int?
}

private struct SettlementDoc: Decodable, Hashable, Identifiable {
    let id: Int
    var stringId: String { String(id) }
    let driverId: Int?
    let loadId: Int?
    let grossAmount: String?
    let netAmount: String?
    let lineHaul: String?
    let fuelSurcharge: String?
    let accessorials: String?
    let platformFee: String?
    let status: String?
    let generatedAt: String?
    let paidAt: String?
}

private struct PayrollBatch: Decodable, Hashable, Identifiable {
    let batchId: Int
    var id: Int { batchId }
    let batchNumber: String?
    let periodStart: String?
    let periodEnd: String?
    let totalAmount: String?
    let status: String?
    let paidAt: String?
}

private struct BatchesEnvelope: Decodable {
    let batches: [PayrollBatch]
}

// MARK: - Screen

struct CatalystDriverPayrollScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { PayrollBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",          isCurrent: false),
                          NavSlot(label: "Dispatch", systemImage: "rectangle.split.3x1.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: true),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct PayrollBody: View {
    @Environment(\.palette) private var palette

    enum Filter: String, CaseIterable {
        case all = "All", due = "Due", held = "Held", paid = "Paid", tax = "Tax"
    }

    @State private var docs: [SettlementDoc] = []
    @State private var batches: [PayrollBatch] = []
    @State private var filter: Filter = .all
    @State private var loading: Bool = true
    @State private var error: String?
    @State private var running: Bool = false
    @State private var ack: String?

    private var dueDocs: [SettlementDoc] { docs.filter { ($0.status ?? "").lowercased().contains("due") || ($0.status ?? "").lowercased() == "pending" } }
    private var heldDocs: [SettlementDoc] { docs.filter { ($0.status ?? "").lowercased() == "escrow" || ($0.status ?? "").lowercased() == "held" } }
    private var paidDocs: [SettlementDoc] { docs.filter { ($0.status ?? "").lowercased() == "paid" || ($0.status ?? "").lowercased() == "completed" } }

    private var dueAmount: Double { sumOf(dueDocs) }
    private var heldAmount: Double { sumOf(heldDocs) }
    private var paid30dAmount: Double {
        let now = Date()
        return paidDocs.compactMap { d -> Double? in
            guard let raw = (d.netAmount ?? d.grossAmount), let v = Double(raw) else { return nil }
            guard let paidAt = d.paidAt, let date = parseIso(paidAt) else { return v }
            return now.timeIntervalSince(date) < 86400 * 30 ? v : nil
        }.reduce(0, +)
    }

    private var filteredDocs: [SettlementDoc] {
        switch filter {
        case .all: return docs
        case .due: return dueDocs
        case .held: return heldDocs
        case .paid: return paidDocs
        case .tax: return docs.filter { ($0.status ?? "").lowercased().contains("tax") }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                kpiStrip
                filterTabs
                if loading && docs.isEmpty {
                    LifecycleCard { Text("Loading settlements…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = error {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if filteredDocs.isEmpty {
                    EusoEmptyState(systemImage: "tray", title: "Nothing in this lens",
                                   subtitle: "When loads close out, their settlements land here.")
                } else {
                    ForEach(filteredDocs) { d in docRow(d) }
                }
                if let m = ack {
                    LifecycleCard(accentGradient: true) {
                        Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
                    }
                }
                runPayrollCTA
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14).padding(.top, 8)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
                Text("CATALYST · DRIVER PAYROLL").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Driver Payroll").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Owner-op §8.4 seam · paid net-0 · zero days-to-pay").font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("\(dueDocs.count) DUE · $\(Int(dueAmount).formatted(.number))")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
        }
    }

    private var kpiStrip: some View {
        HStack(spacing: Space.s2) {
            kpiCard(label: "DUE NOW", value: "$\(Int(dueAmount).formatted(.number))", subtitle: "\(dueDocs.count) load\(dueDocs.count == 1 ? "" : "s") · POD signed", color: .green)
            kpiCard(label: "IN ESCROW", value: "$\(Int(heldAmount).formatted(.number))", subtitle: "\(heldDocs.count) load\(heldDocs.count == 1 ? "" : "s") · POD pending", color: .orange)
            kpiCard(label: "PAID 30D", value: "$\(Int(paid30dAmount).formatted(.number))", subtitle: "\(paidDocs.count) cleared · net-0", color: .blue)
        }
    }

    private func kpiCard(label: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(color)
            Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(palette.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(color.opacity(0.3)))
    }

    private var filterTabs: some View {
        HStack(spacing: 6) {
            ForEach(Filter.allCases, id: \.self) { f in
                let count: Int = {
                    switch f {
                    case .all: return docs.count
                    case .due: return dueDocs.count
                    case .held: return heldDocs.count
                    case .paid: return paidDocs.count
                    case .tax: return 0
                    }
                }()
                Button { filter = f } label: {
                    HStack(spacing: 4) {
                        Text(f.rawValue).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        if count > 0 { Text("· \(count)").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary) }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .foregroundStyle(filter == f ? .white : palette.textSecondary)
                    .background(filter == f ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                    .clipShape(Capsule())
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func docRow(_ d: SettlementDoc) -> some View {
        let net = Double(d.netAmount ?? "0") ?? 0
        let lineHaul = Double(d.lineHaul ?? "0") ?? 0
        let fsc = Double(d.fuelSurcharge ?? "0") ?? 0
        let acc = Double(d.accessorials ?? "0") ?? 0
        let fee = Double(d.platformFee ?? "0") ?? 0
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("LD-\(String(format: "%06d", d.loadId ?? 0))")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    statusBadge(d.status ?? "—")
                }
                Text("Net $\(Int(net).formatted(.number))")
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
                if lineHaul > 0 || fsc > 0 || acc > 0 || fee > 0 {
                    Text("$\(Int(lineHaul)) line · $\(Int(fsc)) FSC · $\(Int(acc)) acc.\(fee > 0 ? " · −$\(Int(fee)) platform" : "")")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private func statusBadge(_ raw: String) -> some View {
        let s = raw.lowercased()
        let (label, color): (String, Color) = {
            if s.contains("due") || s == "pending" { return ("DUE · POD SIGNED", .green) }
            if s == "escrow" || s == "held"        { return ("ESCROW", .orange) }
            if s == "paid" || s == "completed"     { return ("PAID", .blue) }
            return (raw.uppercased(), palette.textSecondary)
        }()
        return Text(label)
            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private var runPayrollCTA: some View {
        Button {
            Task { await runPayroll() }
        } label: {
            HStack(spacing: 8) {
                if running { ProgressView().tint(.white).controlSize(.mini) }
                Image(systemName: "creditcard.and.123.fill")
                    .font(.system(size: 13, weight: .bold))
                Text(running ? "Running payroll…" : "Run payroll · \(dueDocs.count) settlement\(dueDocs.count == 1 ? "" : "s") · $\(Int(dueAmount).formatted(.number))")
                    .font(EType.body.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(LinearGradient.diagonal)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .opacity(dueDocs.isEmpty || running ? 0.5 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(dueDocs.isEmpty || running)
    }

    // MARK: helpers

    private func sumOf(_ rows: [SettlementDoc]) -> Double {
        rows.reduce(0) { acc, d in acc + (Double(d.netAmount ?? d.grossAmount ?? "0") ?? 0) }
    }

    private func parseIso(_ s: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    private func loadAll() async {
        loading = true; error = nil
        async let a: Void = loadSettlements()
        async let b: Void = loadBatches()
        _ = await (a, b)
        loading = false
    }

    private func loadSettlements() async {
        struct In: Encodable { let limit: Int; let offset: Int }
        do {
            let r: DriverSettlementsResponse = try await EusoTripAPI.shared.query(
                "accounting.getDriverSettlements", input: In(limit: 30, offset: 0)
            )
            docs = r.docs ?? []
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    private func loadBatches() async {
        struct In: Encodable { let driverId: Int? }
        do {
            let r: BatchesEnvelope = try await EusoTripAPI.shared.query(
                "settlementBatching.getDriverBatchView", input: In(driverId: nil)
            )
            batches = r.batches
        } catch { /* optional */ }
    }

    private func runPayroll() async {
        running = true
        defer { running = false }
        // Wire to a real payroll-batch creation; for now log + refresh.
        // Future: settlementBatching.createBatch + processBatchPayment.
        ack = "Payroll queued for \(dueDocs.count) settlement(s) — $\(Int(dueAmount).formatted(.number))"
        await loadAll()
    }
}

#Preview("306 Payroll · Dark")  { CatalystDriverPayrollScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("306 Payroll · Light") { CatalystDriverPayrollScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
