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
                MeAction.fire("shipper.allocation.create", userInfo: nil)
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
            MeAction.fire("shipper.allocation.detail", userInfo: ["contractId": c.contractId])
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
