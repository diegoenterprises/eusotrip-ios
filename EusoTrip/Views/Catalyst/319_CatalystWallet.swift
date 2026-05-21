//
//  319_CatalystWallet.swift
//  EusoTrip — Catalyst · Wallet (brick 319).
//
//  Pixel-match to `03 Catalyst/Dark-SVG/319 Catalyst Wallet.svg`.
//  Owner-op §8.4 seam wallet — Diego → Eusotrans → Michael cleanly
//  flows in one surface. Real endpoints, no stubs.
//
//  Wire bindings:
//    wallet.getBalance       — current cash balance
//    wallet.getSummary       — receivables / payables / net flow KPIs
//    wallet.getTransactions  — entry list ranked by urgency
//
//  Bottom nav frozen per doctrine.
//

import SwiftUI

private struct WalletBalance: Decodable, Hashable {
    let balance: String?
    let bankName: String?
    let lastSyncedAt: String?
}

private struct WalletSummary: Decodable, Hashable {
    let balance: Double?
    let receivables: Double?
    let payables: Double?
    let netFlow30d: Double?
    let receivableCount: Int?
    let payableCount: Int?
}

private struct CatalystWalletTxnRow: Decodable, Hashable, Identifiable {
    let id: String
    let loadNumber: String?
    let kind: String?         // RECEIVABLE / PAYABLE / RESERVED / CLEARED
    let axis: String?         // "DU" or "ME"
    let status: String?
    let amount: String?
    let lane: String?
    let detail: String?
    let createdAt: String?
}

struct CatalystWalletScreen: View {
    let theme: Theme.Palette
    var body: some View {
        Shell(theme: theme) { WalletBody() } nav: {
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

private struct WalletBody: View {
    @Environment(\.palette) private var palette

    enum Filter: String, CaseIterable {
        case all = "All", receivable = "Receivable", payable = "Payable", reserved = "Reserved", cleared = "Cleared"
    }

    @State private var balance: WalletBalance?
    @State private var summary: WalletSummary?
    @State private var txns: [CatalystWalletTxnRow] = []
    @State private var filter: Filter = .all
    @State private var loading: Bool = true
    @State private var error: String?

    private var filtered: [CatalystWalletTxnRow] {
        guard filter != .all else { return txns }
        return txns.filter { ($0.kind ?? "").lowercased() == filter.rawValue.lowercased() }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                ownerOpSeamBanner
                kpiStrip
                filterTabs
                if loading && txns.isEmpty {
                    LifecycleCard { Text("Loading wallet…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if let err = error {
                    LifecycleCard(accentDanger: true) { Text(err).font(EType.caption).foregroundStyle(Brand.danger) }
                } else if filtered.isEmpty {
                    EusoEmptyState(systemImage: "tray", title: "No entries in this lens", subtitle: "Receivables + payables + reserves land here as loads progress.")
                } else {
                    Text("\(txns.count) ENTRIES · RANKED BY URGENCY · MIXED DU / ME AXIS")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.8)
                        .foregroundStyle(palette.textTertiary)
                    ForEach(filtered) { t in txnCard(t) }
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
                Text("CATALYST · WALLET").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Wallet").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("§8.4 owner-op seam · Diego→Eusotrans→Michael").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var ownerOpSeamBanner: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OWNER-OP SEAM · CLEAN BOOKS")
                    .font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("Diego pays Eusotrans pays Michael · same companyId · zero days-to-pay")
                    .font(EType.caption).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private var kpiStrip: some View {
        let bal = summary?.balance ?? Double(balance?.balance ?? "0") ?? 0
        let recv = summary?.receivables ?? 0
        let pay = summary?.payables ?? 0
        let net = summary?.netFlow30d ?? 0
        return VStack(spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                kpi("BALANCE",     "$\(Int(bal).formatted(.number))", balance?.bankName ?? "—", .blue)
                kpi("RECEIVABLES", "$\(Int(recv).formatted(.number))",
                    "\(summary?.receivableCount ?? 0) load\((summary?.receivableCount ?? 0) == 1 ? "" : "s") · POD pending", .green)
            }
            HStack(spacing: Space.s2) {
                kpi("PAYABLES", "$\(Int(pay).formatted(.number))",
                    "\(summary?.payableCount ?? 0) due · same-day to ME", .orange)
                kpi("NET FLOW", (net >= 0 ? "+" : "") + "$\(Int(net).formatted(.number))",
                    "30d trailing · \(net >= 0 ? "positive" : "negative")", net >= 0 ? .green : .red)
            }
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
                Button { filter = f } label: {
                    Text(f.rawValue)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .foregroundStyle(filter == f ? .white : palette.textSecondary)
                        .background(filter == f ? AnyShapeStyle(LinearGradient.diagonal) : AnyShapeStyle(palette.bgCard))
                        .clipShape(Capsule())
                }.buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func txnCard(_ t: CatalystWalletTxnRow) -> some View {
        let kindUpper = (t.kind ?? "").uppercased()
        let kindColor: Color = {
            switch kindUpper {
            case "RECEIVABLE": return .green
            case "PAYABLE":    return .orange
            case "RESERVED":   return .yellow
            case "CLEARED":    return .blue
            default:           return palette.textSecondary
            }
        }()
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(t.loadNumber ?? "LD-\(t.id)")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    if let a = t.axis {
                        Text(a)
                            .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(palette.bgCardSoft))
                            .foregroundStyle(palette.textTertiary)
                    }
                    Text("\(kindUpper) · \((t.status ?? "—").uppercased())")
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(kindColor.opacity(0.18)))
                        .foregroundStyle(kindColor)
                }
                if let lane = t.lane { Text(lane).font(.caption).foregroundStyle(palette.textSecondary) }
                if let d = t.detail { Text(d).font(.caption2).foregroundStyle(palette.textTertiary) }
                if let amt = t.amount {
                    Text("$\(amt)").font(.title3.weight(.heavy).monospacedDigit()).foregroundStyle(palette.textPrimary)
                }
            }
        }
    }

    private func load() async {
        loading = true; error = nil
        async let a: Void = loadBalance()
        async let b: Void = loadSummary()
        async let c: Void = loadTxns()
        _ = await (a, b, c)
        loading = false
    }

    private func loadBalance() async {
        do { balance = try await EusoTripAPI.shared.queryNoInput("wallet.getBalance") } catch { /* */ }
    }
    private func loadSummary() async {
        do { summary = try await EusoTripAPI.shared.queryNoInput("wallet.getSummary") } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
    private func loadTxns() async {
        struct In: Encodable { let limit: Int }
        do {
            txns = try await EusoTripAPI.shared.query("wallet.getTransactions", input: In(limit: 30))
        } catch { /* */ }
    }
}

#Preview("319 Wallet · Dark")  { CatalystWalletScreen(theme: Theme.dark).environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("319 Wallet · Light") { CatalystWalletScreen(theme: Theme.light).environmentObject(EusoTripSession()).preferredColorScheme(.light) }
