//
//  324_CatalystDriverSettlementLedger.swift
//  EusoTrip — Catalyst · Driver Settlement Ledger (brick 324).
//
//  Pixel-match to `03 Catalyst/Dark-SVG/324 Catalyst Driver Settlement Ledger.svg`.
//  Per-driver settlement ledger drill-down — 90D window with
//  due/escrow/paid breakdown + per-load rows.
//
//  Wire bindings:
//    accounting.getDriverSettlements(driverId:)  — settlement docs
//

import SwiftUI

private struct LedgerEntry: Decodable, Hashable, Identifiable {
    let id: Int
    var stringId: String { String(id) }
    let loadId: Int?
    let loadNumber: String?
    let grossAmount: String?
    let netAmount: String?
    let status: String?
    let generatedAt: String?
    let paidAt: String?
    let pickupCity: String?
    let destCity: String?
}
private struct LedgerEnvelope: Decodable {
    let docs: [LedgerEntry]?
    let total: Int?
}

struct CatalystDriverSettlementLedgerScreen: View {
    let theme: Theme.Palette
    let driverId: String
    let driverName: String?

    init(theme: Theme.Palette, driverId: String, driverName: String? = nil) {
        self.theme = theme
        self.driverId = driverId
        self.driverName = driverName
    }

    var body: some View {
        Shell(theme: theme) { LedgerBody(driverId: driverId, driverName: driverName) } nav: {
            BottomNav(
                leading: [NavSlot(label: "Home",     systemImage: "house",         isCurrent: false),
                          NavSlot(label: "Dispatch", systemImage: "rectangle.split.3x1.fill", isCurrent: false)],
                trailing: [NavSlot(label: "Drivers", systemImage: "person.3.fill",  isCurrent: true),
                           NavSlot(label: "Me",      systemImage: "person",         isCurrent: false)],
                orbState: .idle
            )
        }
    }
}

private struct LedgerBody: View {
    let driverId: String
    let driverName: String?
    @Environment(\.palette) private var palette

    enum Filter: String, CaseIterable {
        case all = "All", due = "Due", escrow = "Escrow", paid = "Paid"
    }

    @State private var entries: [LedgerEntry] = []
    @State private var filter: Filter = .all
    @State private var loading: Bool = true

    private var dueAmt: Double    { sumOf(entries.filter { ($0.status ?? "").lowercased().contains("due") || ($0.status ?? "").lowercased() == "pending" }) }
    private var escrowAmt: Double { sumOf(entries.filter { ($0.status ?? "").lowercased() == "escrow" || ($0.status ?? "").lowercased() == "held" }) }
    private var paid90Amt: Double { sumOf(entries.filter { ($0.status ?? "").lowercased() == "paid" || ($0.status ?? "").lowercased() == "completed" }) }
    private var ytdAmt: Double    { sumOf(entries) }

    private var filtered: [LedgerEntry] {
        switch filter {
        case .all: return entries
        case .due: return entries.filter { ($0.status ?? "").lowercased().contains("due") || ($0.status ?? "").lowercased() == "pending" }
        case .escrow: return entries.filter { ($0.status ?? "").lowercased() == "escrow" }
        case .paid: return entries.filter { ($0.status ?? "").lowercased() == "paid" || ($0.status ?? "").lowercased() == "completed" }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Space.s4) {
                header
                ownerOpBanner
                identityCard
                kpiGrid
                filterTabs
                if loading && entries.isEmpty {
                    LifecycleCard { Text("Loading ledger…").font(EType.caption).foregroundStyle(palette.textSecondary) }
                } else if filtered.isEmpty {
                    EusoEmptyState(systemImage: "tray", title: "No entries in this lens", subtitle: "Settled loads land here as POD signatures and clearings flow through.")
                } else {
                    ForEach(filtered) { e in entryCard(e) }
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
                Text("CATALYST · DRIVER · LEDGER").font(.system(size: 9, weight: .heavy)).tracking(1.0).foregroundStyle(LinearGradient.diagonal)
            }
            Text("Settlement ledger").font(.system(size: 22, weight: .heavy)).foregroundStyle(palette.textPrimary)
            Text("DR-\(driverId) · 90D · \(entries.count) SETTLEMENTS").font(EType.caption).foregroundStyle(palette.textSecondary)
        }
    }

    private var ownerOpBanner: some View {
        LifecycleCard(accentGradient: true) {
            VStack(alignment: .leading, spacing: 4) {
                Text("OWNER-OP SEAM · CLEAN BOOKS").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(palette.textTertiary)
                Text("Catalyst pays driver · same companyId both sides · clean Schedule C books")
                    .font(EType.caption).foregroundStyle(palette.textPrimary)
            }
        }
    }

    private var identityCard: some View {
        LifecycleCard {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient.diagonal).frame(width: 56, height: 56)
                    Text(initialsFor(driverName)).font(.system(size: 20, weight: .heavy)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(driverName ?? "Driver").font(.system(size: 17, weight: .heavy)).foregroundStyle(palette.textPrimary)
                    Text("DR-\(driverId) · ACH ····6411").font(.caption.monospaced()).foregroundStyle(palette.textTertiary)
                }
                Spacer()
                Text("A+").font(.system(size: 28, weight: .heavy)).foregroundStyle(LinearGradient.diagonal)
            }
        }
    }

    private var kpiGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        return LazyVGrid(columns: cols, spacing: 8) {
            kpi("DUE NOW",  "$\(Int(dueAmt).formatted(.number))",    "POD signed",  .green)
            kpi("ESCROW",   "$\(Int(escrowAmt).formatted(.number))", "POD pending", .orange)
            kpi("PAID 90D", "$\(Int(paid90Amt).formatted(.number))", "cleared · net-0", .blue)
            kpi("YTD",      "$\(Int(ytdAmt).formatted(.number))",    "\(entries.count) loads · gross", .blue)
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
                    case .all: return entries.count
                    case .due: return entries.filter { ($0.status ?? "").lowercased().contains("due") }.count
                    case .escrow: return entries.filter { ($0.status ?? "").lowercased() == "escrow" }.count
                    case .paid: return entries.filter { ($0.status ?? "").lowercased() == "paid" || ($0.status ?? "").lowercased() == "completed" }.count
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

    private func entryCard(_ e: LedgerEntry) -> some View {
        let net = Double(e.netAmount ?? "0") ?? 0
        let status = (e.status ?? "—").uppercased()
        let color: Color = {
            switch status.lowercased() {
            case "due", "pending":   return .green
            case "escrow":            return .orange
            case "paid", "completed": return .blue
            default:                  return palette.textSecondary
            }
        }()
        return LifecycleCard {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(e.loadNumber ?? "LD-\(String(format: "%06d", e.loadId ?? 0))")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Spacer()
                    Text(status)
                        .font(.system(size: 9, weight: .heavy)).tracking(0.6)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(color.opacity(0.18)))
                        .foregroundStyle(color)
                }
                if let pickup = e.pickupCity, let dest = e.destCity {
                    Text("\(pickup) → \(dest)").font(.caption).foregroundStyle(palette.textSecondary)
                }
                Text("Net $\(Int(net).formatted(.number))")
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(palette.textPrimary)
            }
        }
    }

    private func sumOf(_ rows: [LedgerEntry]) -> Double {
        rows.reduce(0) { acc, e in acc + (Double(e.netAmount ?? e.grossAmount ?? "0") ?? 0) }
    }

    private func initialsFor(_ name: String?) -> String {
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return "—" }
        let parts = name.split(separator: " ").map(String.init)
        let first = parts.first?.first.map(String.init) ?? ""
        let last = parts.count > 1 ? (parts.last?.first.map(String.init) ?? "") : ""
        return (first + last).uppercased()
    }

    private func load() async {
        loading = true; defer { loading = false }
        struct In: Encodable { let driverId: Int?; let limit: Int; let offset: Int }
        do {
            let r: LedgerEnvelope = try await EusoTripAPI.shared.query(
                "accounting.getDriverSettlements",
                input: In(driverId: Int(driverId), limit: 50, offset: 0)
            )
            entries = r.docs ?? []
        } catch { /* */ }
    }
}

#Preview("324 Ledger · Dark")  { CatalystDriverSettlementLedgerScreen(theme: Theme.dark, driverId: "001", driverName: "Owner-op").environmentObject(EusoTripSession()).preferredColorScheme(.dark) }
#Preview("324 Ledger · Light") { CatalystDriverSettlementLedgerScreen(theme: Theme.light, driverId: "001", driverName: "Owner-op").environmentObject(EusoTripSession()).preferredColorScheme(.light) }
