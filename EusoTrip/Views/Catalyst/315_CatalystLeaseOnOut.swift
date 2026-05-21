//
//  315_CatalystLeaseOnOut.swift
//  EusoTrip — Catalyst · Lease-on / Lease-out (brick 315).
//
//  Pixel-match to `03 Catalyst/Dark-SVG/315 Lease-on Lease-out.svg`.
//  Owner-op authority leasing — Eusotrans leases its MC under
//  another carrier (lease-on) OR leases trucks out to other
//  carriers (lease-out).
//
//  Wire bindings:
//    authority.getMyLeases     — all leases
//    authority.getLeaseStats   — active count + gross + expiring
//

import SwiftUI

private struct LeaseRow: Decodable, Hashable, Identifiable {
    let id: String
    let direction: String?      // "lease_on" / "lease_out"
    let status: String?         // active / draft / review / sent / counter / closed
    let counterpartyName: String?
    let summary: String?
    let termMonths: Int?
    let splitPercent: String?
    let grossWtd: Double?
    let expiresAt: String?
    let signedAt: String?
}

private struct LeaseStats: Decodable, Hashable {
    let activeLeases: Int?
    let leaseOnCount: Int?
    let leaseOutCount: Int?
    let grossWtd: Double?
    let expiringWithin14d: Int?
}

struct CatalystLeaseOnOutScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { LeaseBody() } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",         isCurrent: false),
                          NavSlot(label: "Dispatch", systemImage: "rectangle.split.3x1.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Wallet", systemImage: "creditcard.fill", isCurrent: false),
                           NavSlot(label: "Me",     systemImage: "person",          isCurrent: true)],
                orbState: .idle
            )
        }
    }
}

private struct LeaseBody: View {
    @Environment(\.palette) private var palette

    enum Filter: String, CaseIterable {
        case all = "All", leaseOn = "Lease-on", leaseOut = "Lease-out", drafts = "Drafts"
    }

    @State private var leases: [LeaseRow] = []
    @State private var stats: LeaseStats?
    @State private var filter: Filter = .all
    @State private var loading: Bool = true

    private var filtered: [LeaseRow] {
        switch filter {
        case .all: return leases
        case .leaseOn: return leases.filter { ($0.direction ?? "") == "lease_on" }
        case .leaseOut: return leases.filter { ($0.direction ?? "") == "lease_out" }
        case .drafts: return leases.filter { ($0.status ?? "") == "draft" }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                kpiStrip
                filterTabs
                if loading && leases.isEmpty {
                    LifecycleCard { Text("Loading leases…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if filtered.isEmpty {
                    EusoEmptyState(systemImage: "doc.text", title: "No leases in this lens", subtitle: "Lease-on / lease-out contracts land here.")
                } else {
                    ForEach(filtered) { l in leaseCard(l) }
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
                Text("CATALYST · LEASE-ON / LEASE-OUT").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Lease-on / out").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("Owner-op contracting · MC authority").font(EType.caption).foregroundStyle(palette.textSecondary)
            let active = stats?.activeLeases ?? leases.filter { ($0.status ?? "") == "active" }.count
            let lOn = stats?.leaseOnCount ?? 0
            let lOut = stats?.leaseOutCount ?? 0
            Text("\(active) ACTIVE · \(lOn) LEASE-ON · \(lOut) LEASE-OUT")
                .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textSecondary)
        }
    }

    private var kpiStrip: some View {
        let active = stats?.activeLeases ?? 0
        let gross = stats?.grossWtd ?? 0
        let expiring = stats?.expiringWithin14d ?? 0
        return HStack(spacing: Space.s2) {
            kpi("ACTIVE",     "\(active)", "leases live", .green)
            kpi("GROSS WTD",  "$\(Int(gross).formatted(.number))", "this week", .blue)
            kpi("EXPIRES <14d","\(expiring)", "renew now", expiring > 0 ? .orange : .green)
        }
    }

    private func kpi(_ label: String, _ value: String, _ subtitle: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
            Text(value).font(.system(size: 18, weight: .heavy).monospacedDigit()).foregroundStyle(color)
            Text(subtitle).font(.caption2).foregroundStyle(palette.textTertiary)
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
                    case .all: return leases.count
                    case .leaseOn: return leases.filter { ($0.direction ?? "") == "lease_on" }.count
                    case .leaseOut: return leases.filter { ($0.direction ?? "") == "lease_out" }.count
                    case .drafts: return leases.filter { ($0.status ?? "") == "draft" }.count
                    }
                }()
                Button { filter = f } label: {
                    HStack(spacing: 4) {
                        Text(f.rawValue).font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        Text("· \(count)").font(.system(size: 9, weight: .heavy)).foregroundStyle(palette.textTertiary)
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

    private func leaseCard(_ l: LeaseRow) -> some View {
        let isLeaseOn = (l.direction ?? "") == "lease_on"
        let dirArrow = isLeaseOn ? "← LEASE-ON" : "→ LEASE-OUT"
        let statusUpper = (l.status ?? "").uppercased()
        let statusColor: Color = {
            switch statusUpper {
            case "ACTIVE":   return .green
            case "DRAFT":    return .blue
            case "REVIEW":   return .yellow
            case "SENT":     return .blue
            case "COUNTER":  return .orange
            case "CLOSED":   return palette.textTertiary
            default:         return palette.textSecondary
            }
        }()
        return LifecycleCard(accentGradient: statusUpper == "ACTIVE") {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(l.id)
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(dirArrow)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(palette.bgCardSoft))
                        .foregroundStyle(palette.textTertiary)
                    Text(statusUpper)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(statusColor.opacity(0.18)))
                        .foregroundStyle(statusColor)
                }
                if let cp = l.counterpartyName {
                    Text(cp).font(EType.body.weight(.bold)).foregroundStyle(palette.textPrimary)
                }
                if let s = l.summary {
                    Text(s).font(.caption).foregroundStyle(palette.textSecondary)
                }
                let parts: [String] = [
                    l.termMonths.map { "\($0)-month term" },
                    l.splitPercent.map { "\($0) split" },
                    l.grossWtd.map { "$\(Int($0)) WTD" },
                ].compactMap { $0 }
                if !parts.isEmpty {
                    Text(parts.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(palette.textTertiary)
                }
            }
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        async let lq: Void = loadLeases()
        async let sq: Void = loadStats()
        _ = await (lq, sq)
    }

    private func loadLeases() async {
        struct In: Encodable { let limit: Int }
        do { leases = try await EusoTripAPI.shared.query("authority.getMyLeases", input: In(limit: 30)) } catch { /* */ }
    }
    private func loadStats() async {
        do { stats = try await EusoTripAPI.shared.queryNoInput("authority.getLeaseStats") } catch { /* */ }
    }
}

#Preview("315 Lease · Dark")  { CatalystLeaseOnOutScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("315 Lease · Light") { CatalystLeaseOnOutScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
