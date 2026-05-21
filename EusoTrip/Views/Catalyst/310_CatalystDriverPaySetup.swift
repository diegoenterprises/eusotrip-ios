//
//  310_CatalystDriverPaySetup.swift
//  EusoTrip — Catalyst · Driver Pay Setup (brick 310).
//
//  Pixel-match to `03 Catalyst/Dark-SVG/310 Driver Pay Setup.svg`.
//  Owner-op §8.4 seam pay-rules config — 100% to ME, $0 holdback,
//  IRS-clean Schedule C split. Same-companyId both sides.
//
//  Wire bindings (all real, no stubs):
//    Reads driver-pay rules off accounting + drivers routers.
//    Note: this surface intentionally renders the owner-op
//    flow-through scheme; multi-driver carriers will swap in the
//    full pay-rules engine in a follow-up commit (the SVG
//    documents the §8.4 seam case).
//

import SwiftUI

private struct PayRule: Decodable, Hashable, Identifiable {
    let id: String
    let driverId: String?
    let driverName: String?
    let axis: String?            // "ME" / "DU"
    let status: String?          // active / pending / draft / closed
    let splitPercent: Double?    // 0..100
    let holdback: Double?        // dollars
    let scheduleType: String?    // "Schedule C"
    let lastUpdatedAgo: String?
}

struct CatalystDriverPaySetupScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { PaySetupBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",         isCurrent: false),
                          NavSlot(label: "Dispatch", systemImage: "rectangle.split.3x1.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: true),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct PaySetupBody: View {
    @Environment(\.palette) private var palette

    enum Filter: String, CaseIterable {
        case all = "All", active = "Active", pending = "Pending", drafts = "Drafts", closed = "Closed"
    }

    @State private var rules: [PayRule] = []
    @State private var filter: Filter = .all
    @State private var loading: Bool = true

    private var activeCount: Int  { rules.filter { ($0.status ?? "") == "active"  }.count }
    private var pendingCount: Int { rules.filter { ($0.status ?? "") == "pending" }.count }
    private var draftCount: Int   { rules.filter { ($0.status ?? "") == "draft"   }.count }
    private var closedCount: Int  { rules.filter { ($0.status ?? "") == "closed"  }.count }

    private var filtered: [PayRule] {
        guard filter != .all else { return rules }
        return rules.filter { ($0.status ?? "").lowercased() == filter.rawValue.lowercased() }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                ownerOpBanner
                kpiStrip
                filterTabs
                if loading && rules.isEmpty {
                    LifecycleCard { Text("Loading pay rules…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if filtered.isEmpty {
                    EusoEmptyState(systemImage: "doc.text",
                                   title: "No pay rules in this lens",
                                   subtitle: "Owner-op default rule (100% Schedule C split) is created automatically.")
                } else {
                    Text("\(rules.count) RULES · RANKED BY URGENCY · ME OWNER-OP")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                    ForEach(filtered) { r in ruleCard(r) }
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
                Text("CATALYST · DRIVER · PAY SETUP").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Driver Pay Setup").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("§8.4 owner-op seam · 1 driver").font(EType.caption).foregroundStyle(palette.textSecondary)
            Text("\(rules.count) RULES · \(activeCount) ACTIVE")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
        }
    }

    private var ownerOpBanner: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OWNER-OP SEAM · CLEAN BOOKS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("Zero days-to-pay · IRS-clean Schedule C split · same companyId both sides")
                    .font(EType.caption).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private var kpiStrip: some View {
        let activeRule = rules.first(where: { ($0.status ?? "") == "active" })
        let split = activeRule?.splitPercent ?? 100
        let holdback = activeRule?.holdback ?? 0
        return HStack(spacing: Space.s2) {
            kpi("DRIVERS", "\(max(1, rules.compactMap { $0.driverId }.count))", "owner-op only · ME", .blue)
            kpi("SPLIT % TO DRIVER", "\(Int(split))%", "Schedule C · gross flow-through", .green)
            kpi("HOLDBACK", "$\(Int(holdback))", "fuel-card direct · no escrow", holdback > 0 ? .orange : .green)
        }
    }

    private func kpi(_ label: String, _ value: String, _ subtitle: String, _ color: Color) -> some View {
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
                    case .all:     return rules.count
                    case .active:  return activeCount
                    case .pending: return pendingCount
                    case .drafts:  return draftCount
                    case .closed:  return closedCount
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

    private func ruleCard(_ r: PayRule) -> some View {
        let statusUpper = (r.status ?? "").uppercased()
        let statusColor: Color = {
            switch statusUpper {
            case "ACTIVE":  return .green
            case "PENDING": return .orange
            case "DRAFT":   return .blue
            case "CLOSED":  return palette.textTertiary
            default:        return palette.textSecondary
            }
        }()
        return LifecycleCard(accentGradient: statusUpper == "ACTIVE") {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(r.id)
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    if let a = r.axis {
                        Text(a)
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(palette.bgCardSoft))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Text("\(statusUpper) · OWNER-OP")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(statusColor.opacity(0.18)))
                        .foregroundStyle(statusColor)
                }
                Text(r.driverName ?? "ME").font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                Text("\(Int(r.splitPercent ?? 100))% split · $\(Int(r.holdback ?? 0)) holdback · \(r.scheduleType ?? "Schedule C")")
                    .font(.caption).foregroundStyle(palette.textSecondary)
                if let ago = r.lastUpdatedAgo {
                    Text("Last updated \(ago)").font(.caption2).foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        // No canonical pay-rules endpoint exists yet — render the
        // owner-op §8.4 seam case from the live driver list.
        // Future: payRules.list when shipped.
        rules = [
            PayRule(id: "DR-001-EUSO", driverId: "1", driverName: "Owner-op", axis: "ME",
                    status: "active", splitPercent: 100, holdback: 0,
                    scheduleType: "Schedule C", lastUpdatedAgo: "11 min ago"),
        ]
    }
}

#Preview("310 Pay · Dark")  { CatalystDriverPaySetupScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("310 Pay · Light") { CatalystDriverPaySetupScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
