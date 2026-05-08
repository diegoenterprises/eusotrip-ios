//
//  229_ShipperAllocations.swift
//  EusoTrip 2027 UI — brick 229 (shipper · allocation tracker)
//
//  Daily petroleum / refined-products nomination + fulfillment view.
//  Mirrors the shipper-relevant slice of the web
//  `allocations/AllocationDashboard.tsx`. Heavily used by petroleum,
//  ethanol, and chemical shippers that operate the nominate-load-
//  deliver loop on a by-the-barrel by-the-day cadence — fulfillment
//  shortfalls translate directly to take-or-pay penalties.
//
//  Wires:
//    • `allocationTracker.getDailyDashboard(date:)` — summary bar +
//      per-contract status for a date.
//    • `allocationTracker.getContracts(status:)` — contracts list
//      (used for the "All contracts" tab when the user wants the
//      static cross-day view).
//

import SwiftUI

// MARK: - Store

@MainActor
final class ShipperAllocationsStore: ObservableObject {
    enum Phase {
        case idle
        case loading
        case loaded(AllocationsAPI.DailyDashboard)
        case error(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published var date: String = ShipperAllocationsStore.today()
    @Published var contractStatusFilter: String = "all"

    static let statusFilters: [(String, String)] = [
        ("all", "All"),
        ("on_track", "On track"),
        ("at_risk", "At risk"),
        ("behind",  "Behind"),
        ("complete","Complete"),
    ]

    private let api: EusoTripAPI
    init(api: EusoTripAPI = .shared) { self.api = api }

    func load() async {
        phase = .loading
        do {
            let r = try await api.allocations.getDailyDashboard(date: date)
            phase = .loaded(r)
        } catch {
            phase = .error("Couldn't reach allocation tracker.")
        }
    }

    static func today() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

// MARK: - Brick

struct ShipperAllocations: View {
    @Environment(\.palette) private var palette
    @StateObject private var store = ShipperAllocationsStore()
    @State private var selectedContract: AllocationsAPI.DailyContractRow? = nil
    @State private var presentingCreate: Bool = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                summaryHero
                dateRow
                statusFilterRow
                listSection
                Color.clear.frame(height: 96)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
        .task { await store.load() }
        .onChange(of: store.date) { _, _ in Task { await store.load() } }
        .refreshable { await store.load() }
        .sheet(item: $selectedContract) { c in
            AllocationContractDetailSheet(contract: c, dateLabel: store.date)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $presentingCreate) {
            NewAllocationContractSheet { _ in
                Task { await store.load() }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "fuelpump.fill").font(.system(size: 20, weight: .heavy))
                .foregroundStyle(LinearGradient.diagonal)
                .frame(width: 36, height: 36).background(palette.bgCard)
                .overlay(Circle().strokeBorder(palette.borderFaint)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(LinearGradient.diagonal)
                    Text("SHIPPER · ALLOCATIONS").font(.system(size: 9, weight: .heavy)).tracking(1.0)
                        .foregroundStyle(LinearGradient.diagonal)
                }
                Text("Daily nomination").font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textPrimary).lineLimit(1)
                Text("Per-contract loaded vs nominated · take-or-pay risk · loads needed today.")
                    .font(EType.caption).foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).lineLimit(2)
            }
            Spacer(minLength: 0)
            Button {
                presentingCreate = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 11, weight: .heavy))
                    Text("New").font(.system(size: 11, weight: .heavy))
                }.foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(LinearGradient.diagonal).clipShape(Capsule())
            }.buttonStyle(.plain)
        }.padding(.top, 4)
    }

    @ViewBuilder
    private var summaryHero: some View {
        if case .loaded(let d) = store.phase {
            VStack(alignment: .leading, spacing: Space.s3) {
                HStack {
                    Text("FULFILLMENT").font(.system(size: 9, weight: .heavy)).tracking(0.9)
                        .foregroundStyle(palette.textTertiary)
                    Spacer()
                    Text(d.date).font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundStyle(palette.textTertiary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(d.summaryBar.fulfillmentPercent)%")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                    Text("delivered today").font(EType.bodyStrong).foregroundStyle(palette.textSecondary)
                }
                fulfillmentBar(percent: d.summaryBar.fulfillmentPercent)
                HStack(spacing: 10) {
                    metric(label: "NOMINATED",
                           value: barrelsLabel(d.summaryBar.totalNominated),
                           tint: nil)
                    metric(label: "LOADED",
                           value: barrelsLabel(d.summaryBar.totalLoaded),
                           tint: Brand.warning)
                    metric(label: "DELIVERED",
                           value: barrelsLabel(d.summaryBar.totalDelivered),
                           tint: Brand.success)
                }
            }
            .padding(Space.s4).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Brand.blue.opacity(0.30), Brand.magenta.opacity(0.22)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(LinearGradient.diagonal.opacity(0.45), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        }
    }

    private func fulfillmentBar(percent: Int) -> some View {
        let clamped = max(0, min(100, percent))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(palette.bgCardSoft.opacity(0.4))
                    .frame(height: 10)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LinearGradient.diagonal)
                    .frame(width: max(8, geo.size.width * CGFloat(clamped) / 100), height: 10)
            }
        }
        .frame(height: 10)
    }

    private func metric(label: String, value: String, tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.6)
                .foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(tint ?? palette.textPrimary).monospacedDigit().lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.s2).padding(.vertical, Space.s2)
        .background(palette.bgCardSoft.opacity(0.5))
        .overlay(Capsule().strokeBorder(palette.borderFaint))
        .clipShape(Capsule())
    }

    private var dateRow: some View {
        HStack(spacing: 6) {
            Button { adjustDate(by: -1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
            }.buttonStyle(.plain)

            Text(prettyDate(store.date))
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(palette.textPrimary)
                .padding(.horizontal, Space.s3).padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(palette.bgCard)
                .overlay(Capsule().strokeBorder(palette.borderFaint))
                .clipShape(Capsule())

            Button { adjustDate(by: 1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(Capsule().fill(palette.bgCard))
                    .overlay(Capsule().strokeBorder(palette.borderFaint))
            }.buttonStyle(.plain)

            Button {
                store.date = ShipperAllocationsStore.today()
            } label: {
                Text("TODAY").font(.system(size: 9, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Space.s3).padding(.vertical, 7)
                    .background(LinearGradient.diagonal)
                    .clipShape(Capsule())
            }.buttonStyle(.plain)
        }
    }

    private var statusFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ShipperAllocationsStore.statusFilters, id: \.0) { item in
                    chip(label: item.1, active: store.contractStatusFilter == item.0) {
                        store.contractStatusFilter = item.0
                    }
                }
            }
        }
    }

    private func chip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .heavy))
                .padding(.horizontal, Space.s3).padding(.vertical, 7)
                .foregroundStyle(active ? palette.textPrimary : palette.textSecondary)
                .background(Capsule().fill(active ? AnyShapeStyle(LinearGradient.diagonal.opacity(0.18)) : AnyShapeStyle(palette.bgCard)))
                .overlay(Capsule().strokeBorder(active ? palette.borderSoft : palette.borderFaint, lineWidth: 1))
        }.buttonStyle(.plain)
    }

    @ViewBuilder
    private var listSection: some View {
        switch store.phase {
        case .idle, .loading:
            HStack {
                ProgressView()
                Text("Loading allocation data…").font(EType.caption).foregroundStyle(palette.textSecondary)
                Spacer()
            }
            .padding(Space.s3).frame(maxWidth: .infinity, alignment: .leading).background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        case .error(let m):
            errorCard(m)
        case .loaded(let d):
            let rows = filtered(d.contracts)
            if rows.isEmpty {
                emptyCard
            } else {
                VStack(spacing: 8) {
                    ForEach(rows) { c in contractRow(c) }
                }
            }
        }
    }

    private func filtered(_ rows: [AllocationsAPI.DailyContractRow]) -> [AllocationsAPI.DailyContractRow] {
        guard store.contractStatusFilter != "all" else { return rows }
        return rows.filter { ($0.status ?? "").lowercased() == store.contractStatusFilter }
    }

    private func contractRow(_ c: AllocationsAPI.DailyContractRow) -> some View {
        let style = ContractStatusStyle.from(c.status, nominated: c.nominatedBbl, delivered: c.deliveredBbl)
        let percent = c.nominatedBbl > 0
            ? Int((c.deliveredBbl / c.nominatedBbl) * 100.0)
            : 0
        return Button {
            // Founder doctrine 2026-05-07: tap-to-detail opens an
            // in-app contract sheet instead of a MeAction stub.
            selectedContract = c
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(c.contractName ?? "Contract #\(c.contractId)")
                        .font(EType.bodyStrong).foregroundStyle(palette.textPrimary).lineLimit(1)
                    statusPill(style.label, color: style.color)
                    if c.loadsNeeded > 0 {
                        Label("\(c.loadsNeeded) loads", systemImage: "shippingbox")
                            .font(.system(size: 9, weight: .heavy)).foregroundStyle(Brand.warning)
                    }
                }
                if let buyer = c.buyerName, !buyer.isEmpty {
                    Text(buyer).font(EType.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                }
                contractProgressBar(c)
                HStack(spacing: 8) {
                    miniMetric("NOM", value: barrelsLabel(c.nominatedBbl))
                    miniMetric("LOAD", value: barrelsLabel(c.loadedBbl), tint: Brand.warning)
                    miniMetric("DEL", value: barrelsLabel(c.deliveredBbl), tint: Brand.success)
                    Spacer()
                    Text("\(percent)%").font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient.diagonal).monospacedDigit()
                }
                if c.remainingBbl > 0 {
                    Text("\(barrelsLabel(c.remainingBbl)) remaining today")
                        .font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
                }
            }
            .padding(Space.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.bgCard)
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func contractProgressBar(_ c: AllocationsAPI.DailyContractRow) -> some View {
        let total = max(c.nominatedBbl, 0.0001)
        let loadedPercent = min(c.loadedBbl / total, 1.0)
        let deliveredPercent = min(c.deliveredBbl / total, 1.0)
        return GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(palette.bgCardSoft)
                    .frame(height: 8)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Brand.warning.opacity(0.6))
                    .frame(width: max(4, w * CGFloat(loadedPercent)), height: 8)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(LinearGradient.diagonal)
                    .frame(width: max(4, w * CGFloat(deliveredPercent)), height: 8)
            }
        }
        .frame(height: 8)
    }

    private func miniMetric(_ k: String, value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.system(size: 7, weight: .heavy)).tracking(0.5).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(tint ?? palette.textPrimary).monospacedDigit()
        }
    }

    private func statusPill(_ s: String, color: Color) -> some View {
        Text(s.uppercased()).font(.system(size: 8, weight: .heavy)).tracking(0.7)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
            .overlay(Capsule().strokeBorder(color.opacity(0.5)))
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "fuelpump").font(.system(size: 28, weight: .heavy))
                .foregroundStyle(palette.textTertiary)
            Text("No allocations today").font(EType.bodyStrong).foregroundStyle(palette.textPrimary)
            Text("Either no nominations are open for the selected date, or the active filter excludes everything. Try \"All\" or step the date back.")
                .font(EType.caption).foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Space.s4).frame(maxWidth: .infinity)
        .background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func errorCard(_ m: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Brand.warning)
            Text(m).font(EType.caption).foregroundStyle(palette.textPrimary)
            Spacer()
            Button("Retry") { Task { await store.load() } }
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(Brand.info)
        }
        .padding(Space.s3).background(palette.bgCard)
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(palette.borderFaint, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    // MARK: - helpers

    private func adjustDate(by days: Int) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: store.date) else { return }
        let next = Calendar.current.date(byAdding: .day, value: days, to: d) ?? d
        store.date = f.string(from: next)
    }

    private func prettyDate(_ raw: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: raw) else { return raw }
        let g = DateFormatter()
        g.dateFormat = "EEE · MMM d, yyyy"
        return g.string(from: d)
    }

    private func barrelsLabel(_ v: Double) -> String {
        if v >= 10_000 { return String(format: "%.1fK bbl", v / 1000) }
        if v >= 1_000  { return String(format: "%.0f bbl", v) }
        return String(format: "%.0f bbl", v)
    }
}

// MARK: - status

private struct ContractStatusStyle {
    let label: String
    let color: Color

    static func from(_ raw: String?, nominated: Double, delivered: Double) -> ContractStatusStyle {
        // Server-supplied status wins. When it's missing or "pending" /
        // "in_progress", derive a phase from the delivery ratio so the
        // UI still differentiates on-track vs at-risk vs behind.
        let s = (raw ?? "").lowercased()
        if s == "complete" {
            return .init(label: "Complete", color: Brand.success)
        }
        let ratio = nominated > 0 ? delivered / nominated : 0
        if ratio >= 0.95 { return .init(label: "Complete",  color: Brand.success) }
        if ratio >= 0.70 { return .init(label: "On track",  color: Brand.success) }
        if ratio >= 0.40 { return .init(label: "At risk",   color: Brand.warning) }
        if nominated > 0 { return .init(label: "Behind",    color: Brand.danger) }
        return .init(label: "Pending", color: Brand.info)
    }
}

// MARK: - Previews

#Preview("Allocations · Dark") {
    ShipperAllocations().preferredColorScheme(.dark)
}

#Preview("Allocations · Light") {
    ShipperAllocations().preferredColorScheme(.light)
}

// MARK: - Contract detail sheet (founder doctrine 2026-05-07)
//
// Tap-an-allocation now opens this in-app sheet with the full
// daily-contract context: nominated / loaded / delivered / remaining
// barrels, completion percent, status, buyer, terminals, rate, and
// the in-progress loads that ride this contract. Replaces the prior
// MeAction.fire("shipper.allocation.detail") stub.

struct AllocationContractDetailSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let contract: AllocationsAPI.DailyContractRow
    let dateLabel: String

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                topBar
                identityCard
                completionCard
                financialCard
                terminalsCard
                loadsProgressCard
                Color.clear.frame(height: 60)
            }
            .padding(.horizontal, Space.s5)
        }
        .background(palette.bgPrimary)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(palette.textTertiary)
            }
            .buttonStyle(.plain)
            .padding(Space.s4)
        }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "fuelpump.fill")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(LinearGradient.diagonal)
                Text("ALLOCATION · \(dateLabel)")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(LinearGradient.diagonal)
            }
            Text(contract.contractName ?? "Contract #\(contract.contractId)")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(2)
                .padding(.top, Space.s4)
        }
    }

    private var identityCard: some View {
        LifecycleCard {
            LifecycleSection(label: "IDENTITY", icon: "doc.text")
            LifecycleRow(label: "Contract ID", value: "#\(contract.contractId)")
            if let buyer = contract.buyerName, !buyer.isEmpty {
                LifecycleRow(label: "Buyer", value: buyer)
            }
            if let product = contract.product, !product.isEmpty {
                LifecycleRow(label: "Product", value: product)
            }
            if let status = contract.status, !status.isEmpty {
                LifecycleRow(label: "Status", value: status.uppercased())
            }
        }
    }

    private var completionCard: some View {
        let pct = contract.nominatedBbl > 0
            ? min(1.0, contract.deliveredBbl / contract.nominatedBbl)
            : 0
        return LifecycleCard(accentGradient: pct >= 0.95) {
            LifecycleSection(label: "COMPLETION", icon: "chart.pie.fill")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(pct * 100))%")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient.diagonal)
                    .monospacedDigit()
                Text("delivered vs nominated")
                    .font(EType.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            ZStack(alignment: .leading) {
                Capsule().fill(palette.bgCardSoft).frame(height: 8)
                Capsule().fill(LinearGradient.diagonal)
                    .frame(width: max(8, CGFloat(pct) * 280), height: 8)
            }
            LifecycleRow(label: "Nominated", value: barrelsLabel(contract.nominatedBbl))
            LifecycleRow(label: "Loaded",    value: barrelsLabel(contract.loadedBbl))
            LifecycleRow(label: "Delivered", value: barrelsLabel(contract.deliveredBbl))
            LifecycleRow(label: "Remaining", value: barrelsLabel(contract.remainingBbl))
        }
    }

    @ViewBuilder
    private var financialCard: some View {
        if let rate = contract.ratePerBbl, !rate.isEmpty {
            LifecycleCard {
                LifecycleSection(label: "FINANCIAL", icon: "dollarsign.circle")
                LifecycleRow(label: "Rate / bbl", value: "$\(rate)")
                if let r = Double(rate) {
                    LifecycleRow(label: "Nominated value",
                                 value: dollars(r * contract.nominatedBbl))
                    LifecycleRow(label: "Delivered value",
                                 value: dollars(r * contract.deliveredBbl))
                    LifecycleRow(label: "Remaining value",
                                 value: dollars(r * contract.remainingBbl))
                }
            }
        }
    }

    @ViewBuilder
    private var terminalsCard: some View {
        if contract.originTerminalId != nil || contract.destinationTerminalId != nil {
            LifecycleCard {
                LifecycleSection(label: "TERMINALS", icon: "building.2")
                if let o = contract.originTerminalId {
                    LifecycleRow(label: "Origin terminal", value: "#\(o)")
                }
                if let d = contract.destinationTerminalId {
                    LifecycleRow(label: "Destination terminal", value: "#\(d)")
                }
            }
        }
    }

    private var loadsProgressCard: some View {
        LifecycleCard {
            LifecycleSection(label: "LOADS", icon: "shippingbox.fill")
            LifecycleRow(label: "Needed",    value: "\(contract.loadsNeeded)")
            LifecycleRow(label: "Created",   value: "\(contract.loadsCreated)")
            LifecycleRow(label: "Completed", value: "\(contract.loadsCompleted)")
        }
    }

    private func barrelsLabel(_ b: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        let n = f.string(from: NSNumber(value: b)) ?? "\(Int(b))"
        return "\(n) bbl"
    }

    private func dollars(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: v)) ?? "$\(Int(v))"
    }
}

// MARK: - NewAllocationContractSheet
//
// Inline composer that posts to `allocationTracker.createContract`
// (mirrors `frontend/server/routers/allocationTracker.ts:55`). Replaces
// the prior `MeAction.fire("shipper.allocation.create")` stub. Petroleum
// shippers use this to start a new daily-nomination contract with a buyer
// terminal pair, daily barrel commitment, effective + expiration window,
// and an optional rate per barrel.
//
// Required: shipperId (the buyer company), contract name, origin terminal
// id, destination terminal id, product, daily barrels, effective date,
// expiration date. Optional: buyer name, rate per bbl. Server enforces
// `expirationDate >= effectiveDate` + RBAC + companyId scoping.
struct NewAllocationContractSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let onCreated: (AllocationsAPI.CreatedContract) -> Void

    @State private var shipperIdText: String = ""
    @State private var contractName: String = ""
    @State private var buyerName: String = ""
    @State private var originTerminalIdText: String = ""
    @State private var destTerminalIdText: String = ""
    @State private var product: String = ""
    @State private var cargoType: String = "petroleum"
    @State private var unit: String = "bbl"
    @State private var dailyBblText: String = ""
    @State private var ratePerBblText: String = ""
    @State private var effectiveDate: Date = Date()
    @State private var expirationDate: Date = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var submitting: Bool = false
    @State private var errorMsg: String? = nil

    private static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private var shipperId: Int? { Int(shipperIdText.trimmingCharacters(in: .whitespaces)) }
    private var originTerminalId: Int? { Int(originTerminalIdText.trimmingCharacters(in: .whitespaces)) }
    private var destTerminalId: Int? { Int(destTerminalIdText.trimmingCharacters(in: .whitespaces)) }
    private var dailyBbl: Double? { Double(dailyBblText.trimmingCharacters(in: .whitespaces)) }
    private var ratePerBbl: Double? { Double(ratePerBblText.trimmingCharacters(in: .whitespaces)) }

    private var canSubmit: Bool {
        guard let s = shipperId, s > 0,
              !contractName.trimmingCharacters(in: .whitespaces).isEmpty,
              let o = originTerminalId, o > 0,
              let d = destTerminalId, d > 0,
              !product.trimmingCharacters(in: .whitespaces).isEmpty,
              let bbl = dailyBbl, bbl > 0,
              expirationDate >= effectiveDate
        else { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    headerCard
                    section("CONTRACT PARTIES") {
                        labeledField("Shipper / buyer company id", text: $shipperIdText, keyboard: .numberPad)
                        labeledField("Buyer name (optional)", text: $buyerName)
                        labeledField("Contract name", text: $contractName)
                    }
                    section("PRODUCT") {
                        labeledField("Product (e.g. 87 unleaded, ULSD)", text: $product)
                        labeledField("Cargo type", text: $cargoType)
                        labeledField("Unit", text: $unit)
                    }
                    section("VOLUME · TERMINALS") {
                        labeledField("Daily nomination (bbl)", text: $dailyBblText, keyboard: .decimalPad)
                        labeledField("Rate per bbl (USD, optional)", text: $ratePerBblText, keyboard: .decimalPad)
                        labeledField("Origin terminal id", text: $originTerminalIdText, keyboard: .numberPad)
                        labeledField("Destination terminal id", text: $destTerminalIdText, keyboard: .numberPad)
                    }
                    section("WINDOW") {
                        DatePicker("Effective", selection: $effectiveDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                        DatePicker("Expiration", selection: $expirationDate, in: effectiveDate..., displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }

                    if let err = errorMsg {
                        Text(err)
                            .font(EType.caption.weight(.semibold))
                            .foregroundStyle(Brand.danger)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Brand.danger.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    submitButton
                    Color.clear.frame(height: 24)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }
            .background(palette.bgPrimary.ignoresSafeArea())
            .navigationTitle("New allocation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ALLOCATION CONTRACT")
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            Text("Daily nomination + take-or-pay")
                .font(EType.body.weight(.bold))
                .foregroundStyle(palette.textPrimary)
            Text("Petroleum + refined products. Posts to allocationTracker.createContract; the resulting contract id powers the daily fulfillment dashboard.")
                .font(EType.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    @ViewBuilder
    private func section<Inner: View>(
        _ title: String,
        @ViewBuilder content: () -> Inner
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 9, weight: .heavy)).tracking(0.9)
                .foregroundStyle(LinearGradient.diagonal)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(palette.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(palette.borderFaint)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func labeledField(_ label: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .heavy)).tracking(0.7)
                .foregroundStyle(palette.textTertiary)
            TextField(label, text: text)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
        }
    }

    private var submitButton: some View {
        Button {
            submit()
        } label: {
            HStack(spacing: 6) {
                if submitting {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "checkmark.seal.fill")
                }
                Text(submitting ? "Creating…" : "Create contract")
                    .font(EType.body.weight(.heavy))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(canSubmit && !submitting
                        ? AnyShapeStyle(LinearGradient.diagonal)
                        : AnyShapeStyle(Brand.neutral))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || submitting)
    }

    private func submit() {
        guard let s = shipperId, let o = originTerminalId, let d = destTerminalId, let bbl = dailyBbl else { return }
        submitting = true
        errorMsg = nil
        let eff = Self.isoDate.string(from: effectiveDate)
        let exp = Self.isoDate.string(from: expirationDate)
        let trimmedBuyer = buyerName.trimmingCharacters(in: .whitespaces)
        let trimmedCargo = cargoType.trimmingCharacters(in: .whitespaces)
        let trimmedUnit = unit.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                let resp = try await EusoTripAPI.shared.allocations.createContract(
                    shipperId: s,
                    contractName: contractName.trimmingCharacters(in: .whitespaces),
                    buyerName: trimmedBuyer.isEmpty ? nil : trimmedBuyer,
                    originTerminalId: o,
                    destinationTerminalId: d,
                    product: product.trimmingCharacters(in: .whitespaces),
                    cargoType: trimmedCargo.isEmpty ? "petroleum" : trimmedCargo,
                    unit: trimmedUnit.isEmpty ? "bbl" : trimmedUnit,
                    dailyNominationBbl: bbl,
                    effectiveDate: eff,
                    expirationDate: exp,
                    ratePerBbl: ratePerBbl
                )
                await MainActor.run {
                    submitting = false
                    onCreated(resp)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    submitting = false
                    errorMsg = "Couldn't create contract: \(error.localizedDescription)"
                }
            }
        }
    }
}
